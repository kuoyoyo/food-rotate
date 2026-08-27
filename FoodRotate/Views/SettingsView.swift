import SwiftUI

struct SettingsView: View {
    /// 設定頁只跟轉盤借一件事：**改格數**。
    ///
    /// 收下整個 view model 而不是一個 `Binding<Int>`，是因為「轉動中不給改」
    /// 也要讀得到 `spinner.isSpinning` —— 兩件事來自同一個真相，
    /// 拆成兩個參數就會有一天只更新其中一個。
    @Bindable var rotate: RotateViewModel

    @State private var settings = AppSettings.shared
    @State private var store = CustomFoodStore.shared

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            wheelSection
            librarySection
            mapSection
            aboutSection
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        // `Form` 的結構一個字不動，只換色與字級（S5 紅線：套 token 不等於改行為）。
        .scrollContentBackground(.hidden)
        .background(Theme.pageBackground(for: colorScheme))
        .foregroundStyle(Theme.text(for: colorScheme))
        // 開關、Picker 的選中值、NavigationLink 的箭頭都吃 tint。
        .tint(Theme.sauce(for: colorScheme))
    }

    // MARK: 分組的共用外觀

    private func header(_ text: String) -> some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(Theme.textSecondary(for: colorScheme))
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(Theme.footnote)
            .foregroundStyle(Theme.textSecondary(for: colorScheme))
    }

    // MARK: 轉盤

    private var wheelSection: some View {
        Section {
            // **綁 `rotate.wheelSlots`，不是 `settings.wheelSlots`。**
            // 直接綁設定會繞過清 winner、reset 轉盤與補格（見 `AppSettings.wheelSlots`）。
            Picker("轉盤格數", selection: $rotate.wheelSlots) {
                ForEach(WheelCapacity.allowedSlots, id: \.self) { count in
                    Text("\(count) 格").tag(count)
                }
            }
            .font(Theme.body)
            // 轉動中不給改：轉盤已經照著現在的格數在算停止角度了，
            // 中途換掉會讓指針停的那一格跟結果不是同一格。
            .disabled(rotate.spinner.isSpinning)
        } header: {
            header("轉盤")
        } footer: {
            footer(
                rotate.spinner.isSpinning
                    ? "轉盤正在轉，等它停下來才能改格數。"
                    : "格數多一點選擇多，少一點比較好決定。轉盤畫面上也可以直接改。"
            )
        }
        .listRowBackground(Theme.card(for: colorScheme))
    }

    // MARK: 資料庫

    private var librarySection: some View {
        Section {
            NavigationLink {
                MyListView()
            } label: {
                row("我的清單", value: store.customizationCount == 0 ? "沒有改動" : "改了 \(store.customizationCount) 項")
            }
            row("目前可抽", value: "\(store.pool.count) 道")
            // **這一列以前只是一個數字，點不進去。**
            //
            // 「內建料理 50 道・12 類」講得出數量、看不到內容 —— 使用者只能靠轉盤
            // 一次抽 8 道去猜裡面有什麼。那跟死按鈕是同一種病的另一面：
            // 畫面上有一個承諾，背後沒有東西接。
            //
            // 菜系數用 `cuisineCount` 而不是 `FoodLibrary.categories.count`：
            // 後者數的是 `category` 欄位的相異值，而那個欄位混了「輕食」「鍋物」
            // 兩個吃法值（2026-08-11 裁示不動的既有狀況），所以它會數成 12 —— 
            // 實際的菜系是 10 種。這一列跟它點進去的那一頁必須是同一個數字。
            NavigationLink {
                FoodLibraryView()
            } label: {
                row("內建料理", value: "\(FoodLibrary.all.count) 道・\(cuisineCount) 種菜系")
            }
        } header: {
            header("菜色資料庫")
        } footer: {
            footer("料理清單內建在 App 裡，完全離線、不需要網路也不會上傳任何資料。你自己加的料理也只存在這台裝置上。只有「找附近的店」會用到定位與網路。")
        }
        .listRowBackground(Theme.card(for: colorScheme))
    }

    /// 內建資料實際用到幾種菜系。
    ///
    /// 從標籤數，不從 `category` 數 —— 菜系的真相在標籤上
    ///（見 `FoodItem.category` 的欄位註解：category 是拿來顯示的，tags 才是拿來查的）。
    private var cuisineCount: Int {
        FoodTag.Dimension.cuisine.tags
            .filter { tag in FoodLibrary.all.contains { $0.tags.contains(tag) } }
            .count
    }

    /// 標題 + 數值的一列。標題 `body`／`text`，數值 `footnote`／`textSecondary`。
    private func row(_ title: String, value: String) -> some View {
        LabeledContent {
            Text(value)
                .font(Theme.footnote)
                .foregroundStyle(Theme.textSecondary(for: colorScheme))
        } label: {
            Text(title)
                .font(Theme.body)
                .foregroundStyle(Theme.text(for: colorScheme))
        }
    }

    // MARK: 地圖

    private var mapSection: some View {
        Section {
            Picker("導航用", selection: $settings.preferredMapApp) {
                ForEach(MapApp.allCases) { app in
                    Text(app.displayName).tag(app)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            header("地圖")
        } footer: {
            footer("在店家清單上長按可以臨時改用另一個。沒裝 Google 地圖時會改開網頁版，不會沒有反應。")
        }
        .listRowBackground(Theme.card(for: colorScheme))
    }

    // MARK: 關於

    private var aboutSection: some View {
        Section {
            row("版本", value: Bundle.main.appVersion)
                .listRowBackground(Theme.card(for: colorScheme))
            CopyrightFooter()
                .listRowBackground(Color.clear)
        } header: {
            header("關於")
        }
    }
}

// MARK: - 分段控制

/// 地圖 App 的分段控制配色。
///
/// SwiftUI 的 `.pickerStyle(.segmented)` 沒有任何配色接口，只能從 UIKit 的
/// appearance proxy 設 —— **這是整個 App 唯一必須碰 UIKit 才能套 token 的地方。**
///
/// 三個決定寫在這裡，因為它們是規格裡最容易被「順手改回去」的：
///
/// 1. **選中段不用 `sauce` 填滿。** 實心主色在這套系統裡代表「主要動作」與
///    「已選的篩選條件」——那些會直接改變轉盤內容。選 Apple 還是 Google 地圖是
///    一個**偏好**，不是一個決策。視覺重量要對應後果的重量。
/// 2. **未選文字用 `text` 不是 `textSecondary`。** `textSecondary` 疊在 `hairline`
///    上淺色只有 **3.90**，不合格。選中與否靠**選中段的底色**表達 ——
///    那也正是 iOS 原生分段控制的做法。
/// 3. 顏色用 `UIColor(dynamicProvider:)`，淺深由 UIKit 自己解析，
///    所以只需要套一次，不必跟著 colorScheme 重設。
///
/// **在 `RootView.init` 套，不是在 `SettingsView`。** appearance 只影響之後才建立的
/// 控制項，在設定頁套的話轉盤頁的「吃什麼／去哪吃」會維持系統色，兩個同型別的控制項
/// 在同一個 App 裡長不一樣。這也表示轉盤頁那個切換器會一起換色。
@MainActor
enum SegmentedAppearance {
    private static var hasApplied = false

    static func applyOnce() {
        guard !hasApplied else { return }
        hasApplied = true

        let proxy = UISegmentedControl.appearance()
        proxy.backgroundColor = dynamic(
            light: DesignTokens.Light.hairline,
            dark: DesignTokens.Dark.hairline
        )
        proxy.selectedSegmentTintColor = dynamic(
            light: DesignTokens.Light.card,
            dark: DesignTokens.Dark.card
        )
        let ink = dynamic(light: DesignTokens.Light.text, dark: DesignTokens.Dark.text)
        // 選中與未選**同一個文字色**，這是刻意的（見上面第 2 點）。
        for state in [UIControl.State.normal, .selected, .highlighted] {
            proxy.setTitleTextAttributes([.foregroundColor: ink], for: state)
        }
    }

    private static func dynamic(
        light: DesignTokens.RGB,
        dark: DesignTokens.RGB
    ) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        }
    }
}

private extension UIColor {
    /// token 一律走 sRGB，跟 `Theme.swift` 那條轉換同一個規則。
    convenience init(_ token: DesignTokens.RGB) {
        self.init(
            red: CGFloat(token.red),
            green: CGFloat(token.green),
            blue: CGFloat(token.blue),
            alpha: 1
        )
    }
}

// MARK: - 版權標示

/// 版權標示。主畫面、結果頁與設定頁都會出現。
struct CopyrightFooter: View {
    /// 固定用哪一邊的配色。`nil` 代表跟隨系統。
    ///
    /// 結果頁是**固定深色**的（見 `ResultSheet` 檔頭），它得傳 `.dark` ——
    /// 不然在淺色模式下這三行會用淺色模式的文字色疊在深卡片上。
    var fixedScheme: ColorScheme?

    @Environment(\.colorScheme) private var systemScheme

    private var scheme: ColorScheme { fixedScheme ?? systemScheme }

    var body: some View {
        VStack(spacing: Theme.space4) {
            Text("食物轉盤 Food Rotate")
                .font(Theme.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.text(for: scheme))
            Text("Claude Code 製作 · kuoyo 設計")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary(for: scheme))
            // 用 verbatim，否則 SwiftUI 會把 Int 當數字格式化成「2,026」。
            Text(verbatim: "© \(Calendar.current.component(.year, from: .now)) kuoyo")
                .font(Theme.micro)
                .foregroundStyle(Theme.textSecondary(for: scheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.space12)
    }
}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
