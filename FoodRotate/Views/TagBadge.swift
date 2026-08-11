import SwiftUI

/// 菜系／吃法的文字角標。
///
/// **刻意是文字不是圖示。** 菜系圖像化幾乎必然走向國族刻板印象（墨西哥要畫什麼？
/// 寬邊帽是不能用的），而且角標只有 16pt 高，菜系之間的差異比「碗與鍋」更抽象，
/// 在那個尺寸上要分辨十個做不到。文字還有一個好處：新增一個菜系的成本是零。
///
/// **也刻意不上色。** 轉盤的顏色代表「第幾格」，不代表菜系；角標再上色，
/// 同一個畫面就有兩套顏色語意在打架。
///
/// 一個元件兩種配色，結果頁（深）與 S4 的候選清單（淺）共用。
struct TagBadge: View {
    let text: String
    /// 這個角標長在深色表面上還是淺色表面上。
    ///
    /// 不接 `@Environment(\.colorScheme)`：結果頁是**固定深色**的，
    /// 接系統設定會讓它在淺色模式下變成淺角標配深底。
    let surface: Surface

    enum Surface {
        case light
        case dark

        var background: Color {
            switch self {
            case .light: Theme.Light.hairline
            case .dark: Theme.Dark.hairline
            }
        }

        var foreground: Color {
            switch self {
            case .light: Theme.Light.text
            case .dark: Theme.Dark.text
            }
        }
    }

    var body: some View {
        Text(text)
            .font(Theme.micro)
            .foregroundStyle(surface.foreground)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 2)
            .frame(height: 16)
            .background(surface.background, in: RoundedRectangle(cornerRadius: Theme.radiusBadge))
    }

    /// 水平內距。
    ///
    /// 定案 8（`space8`）：間距階梯是 4 的倍數、沒有 6，而 16pt 高的角標配 8pt
    /// 水平內距比例才對。規格第六節初版寫得自相矛盾（同時出現 8 與 6），已更正。
    private static let horizontalPadding = Theme.space8
}

extension TagBadge {
    /// 這道菜的菜系角標。沒有菜系標籤就不顯示 —— **不要顯示「未分類」**，
    /// 那是把資料缺口攤給使用者看。
    static func cuisine(for item: FoodItem, surface: Surface) -> TagBadge? {
        guard let tag = FoodTag.Dimension.cuisine.tags.first(where: { item.tags.contains($0) }) else {
            return nil
        }
        return TagBadge(text: shortName(for: tag), surface: surface)
    }

    /// 這道菜的吃法角標。用完整名稱，沒有吃法標籤就不顯示。
    static func form(for item: FoodItem, surface: Surface) -> TagBadge? {
        guard let tag = FoodIcon.formPriority.first(where: { item.tags.contains($0) }) else {
            return nil
        }
        return TagBadge(text: tag.rawValue, surface: surface)
    }

    /// 菜系去掉「式」字。16pt 高的角標放不下三個字，而「日」「韓」本來就讀得出來。
    /// 東南亞與南亞例外：縮成一個字會分不出來。
    private static func shortName(for tag: FoodTag) -> String {
        switch tag {
        case .southeastAsian: "東南"
        case .southAsian: "南亞"
        default: tag.rawValue.replacingOccurrences(of: "式", with: "")
        }
    }
}
