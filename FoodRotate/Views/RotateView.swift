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
            // **切模式一定要把還在路上的搜尋停掉並作廢。**
            //
            // 以前只是把清單清空就重新載入 —— 但舊搜尋還在跑，它回來時
            // 會把餐廳寫進「吃什麼」的清單裡（S6 P1-1）。使用者眼前是菜色模式，
            // 轉盤上卻突然變成一排店名。
            abandonSearch()
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

    /// 「去哪吃」這一輪找不到指定菜系的店，退回了一般餐廳。
    ///
    /// 跟 `relaxedDimensions` 是同一件事的兩個模式版本：**放寬了就要說**。
    /// 以前這個退回是靜默的，使用者選了「歐陸」拿到一般餐廳而畫面上什麼都沒講。
    private(set) var didFallBackToGeneric = false

    /// 這一輪搜的是哪幾個菜系。提示文字要講出使用者選的那個詞。
    private(set) var searchedCuisines: Set<FoodTag> = []

    /// 只有「去哪吃」會真的在載入。「吃什麼」是本地查表，這裡永遠是 false。
    private(set) var isLoading = false
    /// 「去哪吃」失敗的原因（沒授權、抓不到位置、地圖沒回應）。
    private(set) var errorMessage: String?
    /// 載入條的起訖時間。跟 Live Activity 用同一組估計值。
    private(set) var progressRange: ClosedRange<Date> = Date.now...Date.now.addingTimeInterval(1)
    private(set) var stage: GenerationActivityAttributes.Stage = .locating

    var winner: FoodItem?
    var showResult = false

    let spinner: WheelSpinner
    private let settings = AppSettings.shared
    private let store = CustomFoodStore.shared
    private let nearby: NearbySearchModel
    private let liveActivity = LoadingActivityController()

    /// `FoodItem.id` → 原本的店家，導航要用它的座標。
    private var foundPlaces: [String: NearbyPlace] = [:]

    /// 「這是第幾次搜尋」。跟轉盤那一輪用的是同一個機制（見 `Generation`）。
    private var searchRuns = GenerationSource()

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

    /// `spinner` 可注入是為了測試。轉盤那一輪的 bug 全部跟「什麼時候醒來」有關，
    /// 測試要能自己決定醒來的時機（見 `WheelSpinner.Wait`）。正式路徑用預設值。
    init(spinner: WheelSpinner = WheelSpinner(), nearby: NearbySearchModel = NearbySearchModel()) {
        self.spinner = spinner
        self.nearby = nearby
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
    /// 停掉並作廢目前這一次搜尋。切模式與重新搜尋都要先做這件事。
    ///
    /// 三件事缺一不可：取消工作、讓號碼作廢、收掉 Live Activity 與背景時間。
    /// 只取消不作廢的話，已經越過最後一個檢查點的結果照樣寫得進來。
    private func abandonSearch() {
        searchRuns.invalidate()
        nearby.stop()
        liveActivity.cancel()
        isLoading = false
    }

    private func findRestaurants() {
        // **不能因為「還在載入」就忽略新條件。**
        //
        // 以前這裡是 `guard !isLoading else { return }`：使用者在載入中改成韓式，
        // 畫面上韓式已經選中了，但請求根本沒發出去，最後拿到的是日式的結果（S6 P1-2）。
        // 正確的做法是取消舊的、重開一次 —— 慢一點沒關係，給錯答案不行。
        abandonSearch()

        let run = searchRuns.next()
        isLoading = true
        errorMessage = nil
        relaxedDimensions = []
        isOverConstrained = false
        winner = nil
        spinner.reset()

        // 菜系在這個模式下只是**搜尋詞**，不是分類條件。翻譯規則與理由見
        // `RestaurantSearchTerms`——那張表不是分類邏輯，別當成分類邏輯改。
        let cuisines = filter.tags(in: .cuisine)
        searchedCuisines = cuisines
        didFallBackToGeneric = false

        let estimate = settings.estimatedNearbyDuration
        let startedAt = Date.now
        stage = .locating
        progressRange = startedAt...startedAt.addingTimeInterval(estimate)
        liveActivity.start(
            prompt: cuisines.isEmpty ? "附近的店" : RestaurantSearchTerms.displayName(for: cuisines),
            estimate: estimate
        )

        nearby.searchRestaurants(
            terms: RestaurantSearchTerms.terms(for: cuisines),
            onStage: { [weak self] stage in
                self?.apply(stage: stage, run: run)
            },
            onFinish: { [weak self] outcome in
                self?.apply(outcome: outcome, run: run, startedAt: startedAt)
            }
        )
    }

    /// 階段只有一個來源：這裡設定，Live Activity 與畫面跟著更新。
    /// 分兩個地方各記一份遲早會對不起來。
    private func apply(stage newStage: GenerationActivityAttributes.Stage, run: Generation) {
        guard isCurrentSearch(run) else { return }
        stage = newStage
        if newStage.isRunning { liveActivity.update(stage: newStage) }
    }

    /// 搜尋回來了。**結果由參數帶進來，不從 `nearby.phase` 讀。**
    ///
    /// 從共享狀態讀等於「拿號碼牌驗完身分，再去櫃檯拿最新的那一份」——
    /// 驗了等於沒驗，因為下一個請求可能已經把 `phase` 改掉了（S6 P1-2）。
    private func apply(
        outcome: NearbySearchModel.RestaurantSearchOutcome,
        run: Generation,
        startedAt: Date
    ) {
        guard isCurrentSearch(run) else { return }

        isLoading = false
        settings.recordNearbyDuration(Date.now.timeIntervalSince(startedAt))

        switch outcome {
        case .results(let places, let didFallBack):
            liveActivity.end(stage: .done(count: places.count))
            didFallBackToGeneric = didFallBack
            allItems = places.map(\.asFoodItem)
            // `asFoodItem` 裝不下座標，但導航需要它，所以另外留一份對照。
            // 用 id 對回去，因為使用者可以在卡片上改名，名字對不住。
            foundPlaces = Dictionary(uniqueKeysWithValues: places.map { ("place-\($0.id.uuidString)", $0) })
            Haptics.prepare()
        case .failed(let message):
            liveActivity.end(stage: .failed)
            allItems = []
            errorMessage = message
        }
    }

    /// 這個結果還算數嗎。
    ///
    /// 兩個條件都要成立：號碼是這一輪的，而且**現在還在「去哪吃」模式**。
    /// 後者是給 P1-1 的第二道鎖 —— 切模式時號碼已經作廢，但兩件事分別
    /// 表達不同的意思，寫在一起才看得懂為什麼。
    private func isCurrentSearch(_ run: Generation) -> Bool {
        searchRuns.isCurrent(run) && source == .restaurants
    }

    func spin(saveTo context: ModelContext) {
        guard canSpin else { return }
        let index = Int.random(in: 0..<items.count)
        // **記住的是那一道菜的 id，不是它在清單裡的位置。**
        //
        // 位置只在「這一份清單」裡有意義。轉盤要轉 4.2 秒，這段時間清單可能已經
        // 換過（改格數、換一組、拿掉一道），拿舊位置去讀新清單輕則抽出別道菜、
        // 重則超出範圍崩潰（S6 P0-1）。
        //
        // 這是第二層防線：第一層是 `WheelSpinner` 的號碼牌，上一輪根本不會醒來執行。
        // 兩層都要有 —— 號碼牌保護的是「哪一輪算數」，id 保護的是「算數的那一輪
        // 講的是哪一道菜」。
        let pickedID = items[index].id
        winner = nil
        Haptics.buttonTap()

        spinner.spin(segmentCount: items.count, winner: index) { [weak self] in
            guard let self else { return }
            // 找不到就代表清單已經不是起轉時的那一份了，這一輪的結果沒有意義。
            guard let picked = self.items.first(where: { $0.id == pickedID }) else { return }
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
                // 由下推入。`dampingFraction` 偏高幾乎不回彈 ——
                // 這是宣告結果的動作，不是彈跳的玩具。
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    self.showResult = true
                }
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
            winner: winner,
            // 存下模式，歷史頁才判斷得出這一列能不能還原（P1-4）。
            source: source
        )
        context.insert(record)
        // 走 `HistoryStorage` 而不是 `try?`：寫入失敗要有人知道（S6 P2-5）。
        HistoryStorage.shared.save(context)
    }
}

// MARK: - 畫面

struct RotateView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var model: RotateViewModel

    /// 中選圖示飛到結果頁 hero 用的 namespace。由 `RootView` 注入 ——
    /// 結果頁掛在那一層（要蓋過分頁列），兩端必須共用同一個 namespace。
    let heroNamespace: Namespace.ID

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                sourcePicker

                FilterBar(
                    filter: $model.filter,
                    slots: $model.wheelSlots,
                    // 「去哪吃」只吃菜系那一列，其餘維度對地圖搜尋沒有意義。
                    activeDimensions: model.source == .dishes ? FoodTag.Dimension.allCases : [.cuisine],
                    searchesByKeyword: model.source == .restaurants,
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
                        winnerID: model.winner?.id,
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
        // S1–S4 換掉的是這一頁的內容，頁底一直是系統色 —— 深色下它是純黑，
        // 而其他每一頁都是 `#1A1714`。主畫面跟全 App 不同底色沒有道理。
        .background(Theme.pageBackground(for: colorScheme))
        .navigationTitle("食物轉盤")
        .navigationBarTitleDisplayMode(.inline)
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
        // 五種提示的互斥順序是既有的優先序，**不要動**。
        //
        // 「沒有符合的料理」（`isOverConstrained`）已經移進轉盤區 —— 只有那一種發生時
        // 轉盤是空的，訊息放在使用者已經在看的地方，而且不必講兩次。
        // 它從這條 `else if` 鏈裡拿掉了，**但其餘四種的先後沒有跟著改**：
        // 錯誤仍然最前面，接著改列一般餐廳 → 已放寬 → 只湊得出 N 格。
        if let message = model.errorMessage {
            ActionNotice(
                symbol: "mappin.slash",
                title: "找不到附近的店",
                // 離線也能用的那條路要講出來。使用者現在就想決定吃什麼，
                // 不該因為定位失敗就整個 App 動不了。
                message: "\(message)\n\n改用「吃什麼」模式的話不需要網路或定位。"
            )
        } else if model.didFallBackToGeneric {
            // 「去哪吃」版的放寬提示。跟下面那個「已放寬」是同一條產品規則：
            // 給了不完全符合的東西就要說出來。
            InfoNotice(
                symbol: "arrow.up.left.and.arrow.down.right",
                text: "附近沒有「\(RestaurantSearchTerms.displayName(for: model.searchedCuisines))」的店，改列一般餐廳"
            )
        } else if !model.relaxedDimensions.isEmpty {
            // 維度名稱一定要留著 —— 規則要求說明「放寬了哪個維度」。
            InfoNotice(
                symbol: "arrow.up.left.and.arrow.down.right",
                text: "不夠 \(model.wheelSlots) 道，已放寬 \(model.relaxedDimensions.map(\.rawValue).joined(separator: "、"))"
            )
        } else if model.isShortOfSlots {
            InfoNotice(
                symbol: "circle.dashed",
                text: "只湊得出 \(model.items.count) 格，可以少選條件或調低格數"
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
                        onSpin: { model.spin(saveTo: modelContext) },
                        transition: reduceMotion ? nil : HeroTransition(
                            namespace: heroNamespace,
                            id: model.winner?.id ?? "",
                            // 結果頁開了就讓位給 hero。
                            isSource: !model.showResult
                        )
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

    @ViewBuilder
    private var emptyHint: some View {
        if model.isOverConstrained {
            // 忌口把選項全篩光了。這一種提示只在轉盤是空的時候發生，所以講在這裡就好 ——
            // 以前上面出一張卡片、下面又寫一句「換個條件再試試」，同一件事講了兩次。
            ActionNotice(
                symbol: "exclamationmark.triangle.fill",
                title: "沒有符合的料理",
                message: "忌口條件把所有選項都篩掉了。這一項不會自動放寬，請把其中一個忌口取消再試。"
            )
            .padding(.horizontal, Theme.space16)
        } else {
            VStack(spacing: Theme.space8) {
                Image(systemName: model.source.symbolName)
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.textSecondary(for: colorScheme))
                Text(model.errorMessage == nil ? "換個條件再試試" : "上面的按鈕可以再試一次")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary(for: colorScheme))
            }
            .allowsHitTesting(false)
        }
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
