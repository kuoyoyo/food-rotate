import SwiftUI

struct RootView: View {
    @State private var rotateModel = RotateViewModel()
    @State private var selectedTab: AppTab = .rotate
    @State private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 中選圖示從轉盤飛到結果頁 hero 用的。
    ///
    /// 掛在**這裡**而不是 `RotateView`，因為結果頁也得掛在這裡（見下）——
    /// `matchedGeometryEffect` 的兩端必須在同一個 namespace 底下。
    @Namespace private var heroNamespace

    /// 結果頁被往下拖了多少（0...1）。壓暗層跟著它回亮。
    @State private var resultDragProgress: Double = 0

    /// 分段控制的配色走 UIKit 的 appearance proxy，而它只影響**之後才建立**的控制項，
    /// 所以要在最外層、最早的地方套一次 —— 這樣設定頁的地圖切換與轉盤頁的
    /// 「吃什麼／去哪吃」才是同一組色。
    init() {
        SegmentedAppearance.applyOnce()
    }

    enum AppTab: String, Hashable {
        case rotate, history, settings

        #if DEBUG
        /// `-startTab settings` 之類的啟動參數讓截圖驗證可以直接開在指定分頁。
        static var launchArgument: AppTab? {
            UserDefaults.standard.string(forKey: "startTab").flatMap(AppTab.init(rawValue:))
        }
        #endif
    }

    var body: some View {
        ZStack {
            tabs

            // 結果頁疊在**分頁列與導覽列之上**。
            //
            // 它以前是 `.sheet`，系統會自動蓋掉整個畫面；換成 overlay 之後就得自己
            // 站在夠上層的地方，掛在 `RotateView` 裡的話分頁列會壓在它上面。
            if rotateModel.showResult, let winner = rotateModel.winner {
                resultOverlay(winner: winner)
            }
        }
        .sheet(isPresented: .init(
            get: { !settings.hasSeenWelcome },
            set: { if !$0 { settings.hasSeenWelcome = true } }
        )) {
            WelcomeView { settings.hasSeenWelcome = true }
        }
        #if DEBUG
        .onAppear {
            if let tab = AppTab.launchArgument { selectedTab = tab }
        }
        #endif
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("轉盤", systemImage: "circle.hexagongrid.fill", value: AppTab.rotate) {
                NavigationStack {
                    RotateView(model: rotateModel, heroNamespace: heroNamespace)
                }
            }

            Tab("歷史", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                NavigationStack {
                    HistoryView { record in
                        rotateModel.restore(record)
                        selectedTab = .rotate
                    }
                }
            }

            Tab("設定", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
    }

    // MARK: - 結果頁

    /// 壓暗層 + 結果頁。
    ///
    /// 壓暗層刻意只到 0.55：轉盤還看得見輪廓，使用者知道自己還在轉盤那一頁、
    /// 結果頁是疊上來的，不是換頁。做到 0.8 以上就變成換頁了。
    @ViewBuilder
    private func resultOverlay(winner: FoodItem) -> some View {
        ZStack(alignment: .bottom) {
            Theme.Dark.pageBackground
                // 下拉時跟著回亮，讓人看得出「再拉就會關」。
                .opacity(0.55 * (1 - resultDragProgress))
                .ignoresSafeArea()
                .allowsHitTesting(false)
                // 壓暗層與 sheet 是兩條不同的曲線：它淡入，sheet 由下推入。
                // `reduceMotion` 時兩者都收斂到 0.15，跟 sheet 一起。
                .transition(.opacity.animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.22)))

            ResultSheet(
                winner: winner,
                phoneNumber: rotateModel.phoneNumber(for: winner),
                onOpenMaps: { rotateModel.openInMaps(winner) },
                onCall: { rotateModel.call(winner) },
                onDismiss: dismissResult,
                // `reduceMotion` 時不做圖示轉場，hero 直接以 76pt 出現。
                transition: reduceMotion ? nil : HeroTransition(
                    namespace: heroNamespace, id: winner.id, isSource: true
                ),
                dragProgress: $resultDragProgress
            )
            .ignoresSafeArea(edges: .bottom)
            // 一般是由下推入，`reduceMotion` 時改成淡入。
            .transition(
                reduceMotion
                    ? .opacity.animation(.easeInOut(duration: 0.15))
                    : .move(edge: .bottom)
            )
        }
    }

    private func dismissResult() {
        withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.22)) {
            rotateModel.showResult = false
        }
        resultDragProgress = 0
    }
}

/// 首次啟動的說明頁。說清楚怎麼用，以及資料不會被上傳。
struct WelcomeView: View {
    let onDone: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.space24) {
                    VStack(spacing: Theme.space12) {
                        // **不是 🎡。** 使用者剛剛在桌面上點了那顆 icon，第一個畫面
                        // 出現同一個圖形 ——「我點的就是這個」。原本那個摩天輪跟這個
                        // App 沒有任何關係。
                        //
                        // 圖是 `Tools/make-icon.swift` 產的，跟 App Icon 同一段幾何、
                        // 同一組色，背景透明、分隔線是挖穿的，所以淺深兩邊都是頁底透出來。
                        Image("mark-wheel")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .accessibilityHidden(true)
                        Text("食物轉盤")
                            .font(Theme.display)
                            .foregroundStyle(Theme.text(for: colorScheme))
                        Text("不知道吃什麼的時候，讓它幫你決定")
                            .font(Theme.subheadline)
                            .foregroundStyle(Theme.textSecondary(for: colorScheme))
                    }
                    .padding(.top, Theme.space32)

                    VStack(spacing: Theme.space20) {
                        point(
                            symbol: "line.3.horizontal.decrease.circle.fill",
                            title: "點條件，不用打字",
                            detail: "選了就即時換一組，選「無牛」就一定不會出現牛肉麵。"
                        )
                        point(
                            symbol: "bolt.fill",
                            title: "瞬間就有結果",
                            detail: "\(FoodLibrary.all.count) 道料理內建在 App 裡，離線可用，不上傳任何資料。"
                        )
                        point(
                            symbol: "list.bullet.rectangle.portrait.fill",
                            title: "每道菜都有優缺點",
                            detail: "清單告訴你其他選項好在哪、雷在哪，方便你推翻它。"
                        )
                        point(
                            symbol: "mappin.and.ellipse",
                            title: "順便找店",
                            detail: "轉出結果後可以搜尋附近有賣的店，直接開地圖導航。"
                        )
                    }
                    .padding(.horizontal, Theme.space8)

                    CopyrightFooter()
                }
                .padding(Theme.space24)
            }

            Button {
                onDone()
            } label: {
                Text("開始用")
                    .font(Theme.headline)
                    // 深色的 `onSauce` 是**深墨不是白**（白字只有 3.50）。
                    .foregroundStyle(
                        colorScheme == .dark ? Theme.Dark.onSauce : Theme.Light.onSauce
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.space16)
                    .background(Theme.sauce(for: colorScheme), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.space24)
            .padding(.bottom, Theme.space20)
        }
        .background(Theme.pageBackground(for: colorScheme))
        .interactiveDismissDisabled()
    }

    private func point(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.space12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.sauce(for: colorScheme))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: Theme.space4) {
                Text(title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.text(for: colorScheme))
                Text(detail)
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.textSecondary(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
