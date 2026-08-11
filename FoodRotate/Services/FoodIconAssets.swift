import UIKit

/// 圖示資產的存取點。
///
/// 跟 `FoodIcon` 分開的理由：`FoodIcon` 是**產品規則**（哪一道菜配哪一類圖示），
/// 放在 `Core/` 只依賴 Foundation、要對翻 Kotlin；「怎麼從 asset catalog 拿到那張圖」
/// 是 iOS 的事，不該混進去。
enum FoodIconAssets {

    /// 拿一張圖示。資產還沒進 catalog 時回 `nil`。
    ///
    /// 一律以 template 模式取用 —— 圖示是單色的，顏色由格子的文字色決定，
    /// 資產本身不帶顏色（規格八-3a：這一條與「文字色跟著格子走」綁在一起，
    /// 否則同一格裡會出現白圖示配墨字）。
    static func image(for icon: FoodIcon) -> UIImage? {
        UIImage(named: icon.assetName)?.withRenderingMode(.alwaysTemplate)
    }

    #if DEBUG
    /// 哪些圖示還沒進 asset catalog。全部到齊時回 `nil`。
    ///
    /// 跟 `FoodDataAudit` 同一個理由：缺圖示不會當掉、不會報錯，只會讓轉盤上那一格
    /// 少一張圖 —— 安靜的壞。差別是這裡連「安靜」都不給，開 App 就列出來。
    static func missingReport() -> String? {
        let missing = FoodIcon.allCases.filter { UIImage(named: $0.assetName) == nil }
        guard !missing.isEmpty else { return nil }

        var lines = ["⚠️ 圖示資產缺 \(missing.count)/\(FoodIcon.allCases.count) 個（轉盤暫時畫回 emoji）"]
        lines += missing.map { "  • \($0.assetName)" }
        lines.append("  ← 設計師交 SVG，工程轉 PDF 進 Assets.xcassets（template 模式）")
        return lines.joined(separator: "\n")
    }
    #endif
}
