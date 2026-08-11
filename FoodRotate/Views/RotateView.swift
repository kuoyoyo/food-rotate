import SwiftData
import SwiftUI

/// 主畫面的狀態。選條件、抽一組、轉盤、記錄結果都在這裡收斂。
///
/// 以前這裡有一半的程式碼在處理「等模型」這件事：載入進度、階段回報、
/// 超時換文字、Live Activity。抽樣改成本地查表之後那些全都不需要了 ——
/// 抽一組是同步的、瞬間的、不會失敗。
@MainActor
@Observable
final class RotateViewModel {
    /// 轉盤上轉的是菜色還是附近的店。
    var source: WheelSource = .dishes {
        didSet {
            guard source != oldValue else { return }
            // 切到「去哪吃」時把菜系以外的標籤清掉。它們在這個模式下沒有作用，
            // 留著只會讓上面的條件摘要寫著一堆其實沒有生效的東西。
            if source == .restaurants {
                filter.tags = filter.tags(in: .cuisine)
            }
            allItems = []
            load()
        }
    }

    /// 使用者選的標籤。改了就即時重抽，不必按按鈕。
    var filter = FilterSelection()

    /// 這一輪抽到的全部候選。
    ///
    /// 跟畫面上的 `items` 分開存，是為了讓「轉盤格數」可以隨時上下調整而不用重抽。
    /// 只留截斷後的結果就回不去了：從 4 格改回 8 格時沒有東西可以補。
    private(set) var allItems: [FoodItem] = []

    /// 實際放上轉盤的候選。
    var items: [FoodItem] {
        Array(allItems.prefix(settings.wheelSlots))
    }

    /// 為了湊滿格數放寬掉的維度，UI 用它老實說明。空的代表條件本來就夠用。
    private(set) var relaxedDimensions: [FoodTag.Dimension] = []

    /// 忌口條件把候選篩光了。這時候不放寬也不硬給，直接請使用者調整。
    private(set) var isOverConstrained = false

    /// 只有「去哪吃」會真的在載入。「吃什麼」是本地查表，這裡永遠是 false。
    private(set) var isLoading = false
    /// 「去哪吃」失敗的原因（沒授權、抓不到位置、地圖沒回應）。
    private(set) var errorMessage: String?
    /// 載入條的起訖時間。跟 Live Activity 用同一組估計值。
    private(set) var progressRange: ClosedRange<Date> = Date.now...Date.now.addingTimeInterval(1)
    private(set) var stage: GenerationActivityAttributes.Stage = .locating

    var winner: FoodItem?
    var showResult = false

    let spinner = WheelSpinner()
    private let settings = AppSettings.shared
    private let store = CustomFoodStore.shared
    private let nearby = NearbySearchModel()
    private let liveActivity = LoadingActivityController()

    /// `FoodItem.id` → 原本的店家，導航要用它的座標。
    private var foundPlaces: [String: NearbyPlace] = [:]

    /// 開地圖導航到這一格代表的店。不是店就什麼都不做。
    func openInMaps(_ item: FoodItem) {
        guard let place = foundPlaces[item.id] else { return }
        NearbySearchModel.openInMaps(place)
    }

    /// 打電話問這家店。MapKit 給不出營業時間，打過去問是最直接的辦法。
    func call(_ item: FoodItem) {
        guard let place = foundPlaces[item.id] else { return }
        NearbySearchModel.call(place)
    }

    /// 這家店有沒有電話可以打。
    func phoneNumber(for item: FoodItem) -> String? {
        foundPlaces[item.id]?.phoneNumber
    }

    /// 轉盤格數。改了不必重抽，直接從既有候選裡多取或少取。
    var wheelSlots: Int {
        get { settings.wheelSlots }
        set {
            guard newValue != settings.wheelSlots else { return }
            settings.wheelSlots = newValue
            // 格數變了，之前算好的停止角度就不對了。
            winner = nil
            spinner.reset()
            // 補格：從 8 格加到 12 格時，上一輪只抽了 8 道，要再抽一次才填得滿。
            if allItems.count < newValue { pick() }
            Haptics.buttonTap()
        }
    }

    /// 「去哪吃」要找多遠以內的店。改了就重找。
    var searchRadius: Double {
        get { settings.searchRadius }
        set { settings.searchRadius = newValue }
    }

    /// 抽到的候選比目前格數少，用來跟使用者說明為什麼選不到那麼多格。
    var isShortOfSlots: Bool {
        !allItems.isEmpty && allItems.count < settings.wheelSlots
    }

    var canSpin: Bool { !items.isEmpty && !spinner.isSpinning && !isLoading }

    init() {
        load()
    }

    /// 填一組新的候選。依模式決定資料從哪來。
    func load() {
        switch source {
        case .dishes: pick()
        case .restaurants: findRestaurants()
        }
    }

    /// 從資料庫抽一組菜色。
    ///
    /// 同步且不會 throw —— 資料在 bundle 裡，沒有網路、沒有模型、沒有等待。
    private func pick() {
        errorMessage = nil
        isLoading = false
        let previous = Set(allItems.map(\.id))
        let result = FoodPicker.pick(
            // 候選池來自 store 而不是 FoodLibrary：它已經併好自訂料理、
            // 扣掉「以後都不要」的、也套上改過的名字。
            from: store.pool,
            matching: filter,
            // 要的數量必須就是轉盤格數。
            //
            // 一度為了「格數往上調時不用重抽」而一律要 12 道，結果放寬的判斷跟著用了 12
            // 當基準：選「日式 + 無牛」剛好湊得出 6 道、轉盤也只有 6 格，畫面卻說
            // 「完全符合的不夠，已放寬菜系」。少抽幾道的代價只是格數調大時重抽一次，
            // 拿它換一句不實的提示並不划算。
            count: settings.wheelSlots,
            avoiding: previous
        )
        allItems = result.items
        relaxedDimensions = result.relaxedDimensions
        isOverConstrained = result.isOverConstrained
        winner = nil
        spinner.reset()
    }

    /// 找一批附近的店填進轉盤。
    ///
    /// 這是整個 App 唯一會讓人真的等的路徑，所以 Live Activity 只接在這裡：
    /// 定位加地圖搜尋要數秒，值得讓人可以切出去做別的事。
    private func findRestaurants() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        relaxedDimensions = []
        isOverConstrained = false
        winner = nil
        spinner.reset()

        let keyword = filter.tags(in: .cuisine).map(\.rawValue).joined(separator: " ")
        let estimate = settings.estimatedNearbyDuration
        let startedAt = Date.now
        stage = .locating
        progressRange = startedAt...startedAt.addingTimeInterval(estimate)
        liveActivity.start(prompt: keyword.isEmpty ? "附近的店" : keyword, estimate: estimate)

        nearby.searchRestaurants(keyword: keyword) { [weak self] stage in
            self?.apply(stage: stage, startedAt: startedAt)
        }
    }

    /// 階段只有一個來源：這裡設定，Live Activity 與畫面跟著更新。
    /// 分兩個地方各記一份遲早會對不起來。
    private func apply(stage newStage: GenerationActivityAttributes.Stage, startedAt: Date) {
        stage = newStage
        guard !newStage.isRunning else {
            liveActivity.update(stage: newStage)
            return
        }

        isLoading = false
        liveActivity.end(stage: newStage)
        settings.recordNearbyDuration(Date.now.timeIntervalSince(startedAt))

        switch nearby.phase {
        case .results(let places):
            allItems = places.map(\.asFoodItem)
            // `asFoodItem` 裝不下座標，但導航需要它，所以另外留一份對照。
            // 用 id 對回去，因為使用者可以在卡片上改名，名字對不住。
            foundPlaces = Dictionary(uniqueKeysWithValues: places.map { ("place-\($0.id.uuidString)", $0) })
            Haptics.prepare()
        case .failed(let message):
            allItems = []
            errorMessage = message
        default:
            allItems = []
        }
    }

    func spin(saveTo context: ModelContext) {
        guard canSpin else { return }
        let index = Int.random(in: 0..<items.count)
        winner = nil
        Haptics.buttonTap()

        spinner.spin(segmentCount: items.count, winner: index) { [weak self] in
            guard let self else { return }
            let picked = self.items[index]
            self.winner = picked
            self.save(winner: picked, to: context)

            // 讓中選轉場先跑完再開結果頁。以前是同一瞬間開，那 0.35 秒的提亮放大
            // 會整個被 sheet 蓋住，等於沒做。
            //
            // 不用計時器狀態：醒來時比對 winner 還是不是同一道就好 ——
            // 使用者在這 0.35 秒內又按了轉、或改了條件，winner 會被清掉或換人，
            // 這個 Task 自己就不會開錯的結果頁。
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(WheelCelebration.duration))
                guard let self, self.winner == picked else { return }
                self.showResult = true
            }
        }
    }

    // MARK: - 自訂候選清單

    /// 這一輪不想吃這道。只影響眼前的轉盤，下次抽還是抽得到。
    ///
    /// 轉盤格數變了，之前算好的停止角度就沒有意義，所以一併重設。
    func remove(_ item: FoodItem) {
        guard !spinner.isSpinning, let index = allItems.firstIndex(of: item) else { return }
        allItems.remove(at: index)
        if winner == item { winner = nil }
        spinner.reset()
        Haptics.buttonTap()
    }

    /// 以後都不要出現這道。寫進排除名單，並從眼前的轉盤拿掉。
    ///
    /// 店家沒有「以後」——每次搜尋都會拿到新的 id，記下來也對不回同一家，
    /// 所以對店家只做這一輪的移除。
    func excludeForever(_ item: FoodItem) {
        if !item.isPlace { store.exclude(item) }
        remove(item)
    }

    /// 改掉菜名，換成你常去那家店的說法。改動會存下來，之後抽到同一道還是新名字。
    func rename(_ item: FoodItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = allItems.firstIndex(of: item) else { return }
        // 店家的 id 每次搜尋都不一樣，存改名只會在偏好設定裡累積永遠用不到的紀錄。
        if !item.isPlace { store.rename(id: item.id, to: trimmed) }
        let wasWinner = winner == item
        allItems[index].name = trimmed
        if wasWinner { winner = allItems[index] }
    }

    /// 從歷史頁還原一組清單。
    func restore(_ record: SpinRecord) {
        let restored = record.items
        guard !restored.isEmpty else { return }
        allItems = restored
        relaxedDimensions = []
        isOverConstrained = false
        winner = nil
        spinner.reset()
    }

    private func save(winner: FoodItem, to context: ModelContext) {
        let record = SpinRecord(
            date: .now,
            prompt: filter.summary,
            items: items,
            winnerName: winner.name
        )
        context.insert(record)
        try? context.save()
    }
}

// MARK: - 畫面

struct RotateView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var model: RotateViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                sourcePicker

                FilterBar(
                    filter: $model.filter,
                    slots: $model.wheelSlots,
                    // 「去哪吃」只吃菜系那一列，其餘維度對地圖搜尋沒有意義。
                    activeDimensions: model.source == .dishes ? FoodTag.Dimension.allCases : [.cuisine],
                    radius: model.source == .restaurants ? $model.searchRadius : nil,
                    onChange: { model.load() },
                    onReroll: {
                        model.load()
                        Haptics.buttonTap()
                    }
                )

                statusArea

                wheelArea

                if !model.items.isEmpty {
                    FoodCardList(
                        items: model.items,
                        winnerName: model.winner?.name,
                        onRename: { model.rename($0, to: $1) },
                        onDelete: { model.remove($0) },
                        onExcludeForever: { model.excludeForever($0) },
                        onOpenMaps: { model.openInMaps($0) },
                        onCall: { model.call($0) },
                        phoneNumber: { model.phoneNumber(for: $0) }
                    )
                }

                CopyrightFooter()
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("食物轉盤")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $model.showResult) {
            if let winner = model.winner {
                ResultSheet(
                    winner: winner,
                    phoneNumber: model.phoneNumber(for: winner),
                    onOpenMaps: { model.openInMaps(winner) },
                    onCall: { model.call(winner) }
                )
            }
        }
        #if DEBUG
        // 模擬器無法用指令碼點按，這個啟動參數讓流程能自己轉一次以便截圖驗證。
        .task {
            guard UserDefaults.standard.bool(forKey: "autoSpin") else { return }
            try? await Task.sleep(for: .seconds(1))
            model.spin(saveTo: modelContext)
        }
        #endif
    }

    /// 兩種模式的切換。放在最上面，因為它決定了下面所有東西的意思。
    private var sourcePicker: some View {
        Picker("轉盤來源", selection: $model.source) {
            ForEach(WheelSource.allCases) { source in
                Label(source.displayName, systemImage: source.symbolName).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 8)
    }

    // MARK: 狀態列

    @ViewBuilder
    private var statusArea: some View {
        if let message = model.errorMessage {
            NoticeBox(
                symbol: "mappin.slash",
                tint: .orange,
                title: "找不到附近的店",
                // 離線也能用的那條路要講出來。使用者現在就想決定吃什麼，
                // 不該因為定位失敗就整個 App 動不了。
                message: "\(message)\n\n改用「吃什麼」模式的話不需要網路或定位。"
            )
        } else if model.isOverConstrained {
            NoticeBox(
                symbol: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "沒有符合的料理",
                message: "忌口條件把所有選項都篩掉了。這一項不會自動放寬，請把其中一個忌口取消再試。"
            )
        } else if !model.relaxedDimensions.isEmpty {
            NoticeBox(
                symbol: "arrow.up.left.and.arrow.down.right",
                tint: .blue,
                title: "已放寬條件",
                message: "完全符合的不夠 \(model.wheelSlots) 道，已放寬「\(model.relaxedDimensions.map(\.rawValue).joined(separator: "、"))」。"
            )
        } else if model.isShortOfSlots {
            NoticeBox(
                symbol: "circle.dashed",
                tint: .blue,
                title: "只湊得出 \(model.items.count) 格",
                message: "符合條件的料理不夠 \(model.wheelSlots) 道。可以少選幾個條件，或把格數調低。"
            )
        }
    }

    // MARK: 轉盤區

    private var wheelArea: some View {
        VStack(spacing: 16) {
            ZStack {
                TimelineView(.animation(paused: !model.spinner.isSpinning)) { context in
                    WheelView(
                        items: model.items,
                        angle: model.spinner.angle(at: context.date),
                        isSpinning: model.spinner.isSpinning,
                        // 從 winner 反查格號，而不是在 model 裡再存一份索引：
                        // 兩份狀態就會有對不上的那一天（改名、刪卡片都會動到清單）。
                        winnerIndex: model.winner.flatMap { model.items.firstIndex(of: $0) },
                        onSpin: { model.spin(saveTo: modelContext) }
                    )
                }

                if model.items.isEmpty && !model.isLoading {
                    emptyHint
                }

                if model.isLoading {
                    loadingHint
                }
            }
            .frame(maxWidth: 360)
            .frame(height: 360)

            Button {
                model.spin(saveTo: modelContext)
            } label: {
                Label(model.spinner.isSpinning ? "轉動中…" : "開始轉", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(!model.canSpin)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: model.source.symbolName)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(model.errorMessage == nil ? "換個條件再試試" : "上面的按鈕可以再試一次")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .allowsHitTesting(false)
    }

    /// 搜尋附近店家時的載入區塊。
    ///
    /// 跟 Dynamic Island 用同一組資料：進度條是時間估計，文字是真實階段。
    /// App 在前景時島上不會顯示自己的 Live Activity，所以這一份不能省；
    /// 兩邊長得一樣，切換出去再回來才不會有兩套說法。
    private var loadingHint: some View {
        VStack(spacing: 12) {
            ProgressView(
                timerInterval: model.progressRange,
                countsDown: false,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .progressViewStyle(.linear)
            .frame(width: 180)

            Label(model.stage.title, systemImage: model.stage.symbolName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .animation(.default, value: model.stage)
    }
}

/// 錯誤與提示共用的小卡片。
struct NoticeBox: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
