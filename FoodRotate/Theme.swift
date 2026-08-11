import SwiftUI

/// App 端取用設計 token 的唯一入口。
///
/// 這是一層**薄**的包裝：只把 `DesignTokens` 的數值換成 SwiftUI 型別，不做元件、
/// 不封 ViewModifier（S1 的範圍就是「只換 token 不換元件」，見 PM 決策第六節問題 1）。
/// 值本身一律回頭改 `DesignTokens.swift`，不要在這裡出現任何 hex 或數字字面值 ——
/// 這個檔一旦開始自己定義值，單一來源就又破了。
///
/// **S1a 未定案的項目這裡沒有對應的 API。** 這是刻意的：拿不到就編不過，
/// 比給一個暫定值讓畫面「先跑起來」誠實（PM 裁示 2026-08-11 第一節條件 1）。
enum Theme {

    // MARK: - 色

    /// 主色・醬。
    static let sauce = Color(DesignTokens.sauce)

    /// 淺色模式的表面與文字。
    ///
    /// 深色模式的對應值 S1a 還沒給，所以這裡只有 `Light`，沒有 `Dark`，
    /// 也刻意不提供「依 colorScheme 自動選」的入口 —— 那會讓呼叫端以為深色已經可用。
    enum Light {
        static let pageBackground = Color(DesignTokens.Light.pageBackground)
        static let card = Color(DesignTokens.Light.card)
        static let text = Color(DesignTokens.Light.text)
    }

    /// 轉盤八色。深淺兩套都已定案，所以這裡可以直接依 `colorScheme` 給。
    ///
    /// 回傳陣列而不是單一顏色，是因為呼叫端要用格號取色（格數 4–12，超過 8 會繞回來）。
    static func wheelPalette(for scheme: ColorScheme) -> [Color] {
        let tokens = scheme == .dark ? DesignTokens.wheelOnDark : DesignTokens.wheelOnLight
        return tokens.map { Color($0) }
    }

    // MARK: - 形

    static let radiusLarge = CGFloat(DesignTokens.radiusLarge)
    static let radiusSmall = CGFloat(DesignTokens.radiusSmall)

    /// 分層用的髮絲線寬度。**顏色 S1a 未定案**，所以只有寬度沒有 `hairlineColor`。
    static let hairlineWidth = CGFloat(DesignTokens.hairlineWidth)
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
