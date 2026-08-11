import SwiftUI

struct RootView: View {
    @State private var rotateModel = RotateViewModel()
    @State private var selectedTab: AppTab = .rotate
    @State private var settings = AppSettings.shared

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
        TabView(selection: $selectedTab) {
            Tab("轉盤", systemImage: "circle.hexagongrid.fill", value: AppTab.rotate) {
                NavigationStack {
                    RotateView(model: rotateModel)
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
}

/// 首次啟動的說明頁。說清楚怎麼用，以及資料不會被上傳。
struct WelcomeView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 26) {
                    VStack(spacing: 10) {
                        Text("🎡")
                            .font(.system(size: 68))
                        Text("食物轉盤")
                            .font(.largeTitle.weight(.bold))
                        Text("不知道吃什麼的時候，讓它幫你決定")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 36)

                    VStack(spacing: 18) {
                        point(
                            symbol: "line.3.horizontal.decrease.circle.fill",
                            title: "點條件，不用打字",
                            detail: "菜系、什麼時候吃、口味、忌口，選了就即時換一組。選「無牛」就一定不會出現牛肉麵。"
                        )
                        point(
                            symbol: "bolt.fill",
                            title: "瞬間就有結果",
                            detail: "\(FoodLibrary.all.count) 道料理內建在 App 裡，離線也能用，不用等、也不會上傳任何資料。"
                        )
                        point(
                            symbol: "list.bullet.rectangle.portrait.fill",
                            title: "每道菜都有優缺點",
                            detail: "轉盤給你答案，清單告訴你其他選項好在哪、雷在哪，方便你推翻它。"
                        )
                        point(
                            symbol: "mappin.and.ellipse",
                            title: "順便找店",
                            detail: "轉出結果後可以搜尋附近有賣的店，直接開地圖導航。"
                        )
                    }
                    .padding(.horizontal, 8)

                    CopyrightFooter()
                }
                .padding(24)
            }

            Button {
                onDone()
            } label: {
                Text("開始用")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled()
    }

    private func point(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
