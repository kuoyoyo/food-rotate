import SwiftUI

/// App 端取用設計 token 的唯一入口。
///
/// 這是一層**薄**的包裝：只把 `DesignTokens` 的數值換成 SwiftUI 型別，不做元件、
/// 不封 ViewModifier（S1 的範圍就是「只換 token 不換元件」）。
/// 值本身一律回頭改 `DesignTokens.swift`，不要在這裡出現任何 hex 或數字字面值 ——
/// 這個檔一旦開始自己定義值，單一來源就又破了。
///
/// 例外是**字級**：它對應系統 `TextStyle` 而不是數字（為了保住 Dynamic Type），
/// 沒辦法在只依賴 Foundation 的地方表達，所以定義在這裡。
enum Theme {

    // MARK: - 色

    /// 主色・醬。深淺兩邊是**兩個不同的值**，不是同一個調透明度：
    /// 淺色的 `#9B3B2C` 疊在深卡片上對比只有 2.36，看不清。
    static func sauce(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(DesignTokens.Dark.sauce) : Color(DesignTokens.sauce)
    }

    enum Light {
        static let pageBackground = Color(DesignTokens.Light.pageBackground)
        static let card = Color(DesignTokens.Light.card)
        static let text = Color(DesignTokens.Light.text)
        static let hairline = Color(DesignTokens.Light.hairline)
    }

    enum Dark {
        static let pageBackground = Color(DesignTokens.Dark.pageBackground)
        static let card = Color(DesignTokens.Dark.card)
        static let text = Color(DesignTokens.Dark.text)
        static let hairline = Color(DesignTokens.Dark.hairline)
        static let sauce = Color(DesignTokens.Dark.sauce)
    }

    static func pageBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.pageBackground : Light.pageBackground
    }

    static func card(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.card : Light.card
    }

    static func text(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.text : Light.text
    }

    static func hairline(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Dark.hairline : Light.hairline
    }

    // MARK: - 轉盤

    /// 一格的底色與它該配的文字色。
    struct WheelSlot {
        let fill: Color
        /// 這一格的菜名（S2 之後還有圖示）要用的顏色。
        /// 跟著格子走，不是一律白字 —— 蛋黃與抹茶配白字只有 2.5，看不清。
        let ink: Color
    }

    /// 這個格數該用哪幾個顏色，依序。格數與配色的對應只有 `DesignTokens` 一個地方定義。
    static func wheelSlots(count: Int, for scheme: ColorScheme) -> [WheelSlot] {
        DesignTokens.wheelSlots(count: count, on: scheme == .dark ? .dark : .light)
            .map { slot in
                WheelSlot(fill: Color(slot.fill), ink: Color(slot.ink.color))
            }
    }

    // MARK: - 字

    // 語意名對應系統 TextStyle，不寫死 pt —— 寫死就吃不到 Dynamic Type。
    // `.rounded` 只用在 display 與轉盤中心鈕：圓體用多了會把「菜單感」推回「兒童遊戲」。
    //
    // 轉盤上的菜名是 Canvas 繪製，**不吃 Dynamic Type**，字級由排版規則決定，不走這裡。

    /// 結果頁菜名。
    static let display = Font.system(.largeTitle, design: .rounded, weight: .bold)
    /// 區塊標題、sheet 標題。
    static let title = Font.system(.title2, weight: .semibold)
    /// 卡片菜名、按鈕。
    static let headline = Font.system(.headline, weight: .semibold)
    /// 內文、優缺點條列。
    static let body = Font.system(.body)
    /// 摘要列、次要說明。
    static let subheadline = Font.system(.subheadline)
    /// 標籤 chip、分類。
    static let footnote = Font.system(.footnote)
    /// 維度標題、時間。
    static let caption = Font.system(.caption)
    /// 「一定不會出現」這類註記。
    static let micro = Font.system(.caption2, weight: .medium)

    // MARK: - 形

    static let radiusLarge = CGFloat(DesignTokens.radiusLarge)
    static let radiusSmall = CGFloat(DesignTokens.radiusSmall)
    static let hairlineWidth = CGFloat(DesignTokens.hairlineWidth)

    // MARK: - 間距

    static let space2 = CGFloat(DesignTokens.space2)
    static let space4 = CGFloat(DesignTokens.space4)
    static let space8 = CGFloat(DesignTokens.space8)
    static let space12 = CGFloat(DesignTokens.space12)
    static let space16 = CGFloat(DesignTokens.space16)
    static let space20 = CGFloat(DesignTokens.space20)
    static let space24 = CGFloat(DesignTokens.space24)
    static let space32 = CGFloat(DesignTokens.space32)
}

private extension Color {
    /// token 一律走這條轉換，明確指定 sRGB。
    ///
    /// 不用 `Color(red:green:blue:)` 那個便利建構式：它吃的是 `.sRGB` 沒錯，
    /// 但寫明白比較不會有人日後改成 display-P3 又沒發現轉盤跟 icon 對不上。
    init(_ token: DesignTokens.RGB) {
        self.init(.sRGB, red: token.red, green: token.green, blue: token.blue, opacity: 1)
    }
}
