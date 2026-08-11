import Foundation

/// 設計 token 的**單一來源**。
///
/// 只用 Foundation，刻意不 import SwiftUI —— 因為這份值有兩個消費者：
/// App 端的 `Theme.swift`（包成 SwiftUI 的 `Color`）與 `Tools/make-icon.swift`
/// （包成 CoreGraphics 的 `CGColor`，另外套一道加深）。放在只依賴 Foundation 的地方，
/// 那支 macOS 腳本才能跟 App 編同一個檔。**兩份色盤各自演化正是這輪要解掉的問題**
/// （見 `Design/PM決策-視覺方向v1-回覆.md` 第四節），所以界線請維持：
/// 這個檔不准出現 `Color`、`UIColor`、`CGColor` 或任何 View。
///
/// 值的來源是 `Design/PM決策-視覺方向v1-回覆.md` 第一節，方向 B（灶）+ 折衷案，
/// 2026-08-11 定案。
///
/// **S1a 還沒定案的項目不在這裡，而且刻意不給暫定值** —— 字級、間距、髮絲線的顏色、
/// 深色模式的頁面底／卡片／文字、icon 加深公式。用到就是編不過，
/// 比先填一個「看起來能跑」的數字好：半年後沒有人記得哪個是暫定的。
enum DesignTokens {

    /// 不帶色彩空間概念的三原色分量，各自 0...1。
    ///
    /// 不叫 `Color` 是為了不跟 SwiftUI 的同名型別打架，也提醒這裡只是「數值」，
    /// 要怎麼詮釋成畫面上的顏色是消費端的事。
    struct RGB: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double

        /// 用 `0xRRGGBB` 寫。設計文件給的就是 hex，抄過來不必先換算成小數，
        /// 少一次人工換算就少一種對不上的可能。
        init(_ hex: UInt32) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
        }
    }

    // MARK: - 色票

    /// 主色・醬。
    static let sauce = RGB(0x9B3B2C)

    /// 淺色模式的表面與文字。
    enum Light {
        static let pageBackground = RGB(0xEFEAE0)
        static let card = RGB(0xF8F5EE)
        static let text = RGB(0x241E18)
    }

    // 深色模式的 pageBackground / card / text：**S1a 未定案**，刻意不定義。
    // 只有轉盤八色的深底版本已經定案（見下方 `wheelOnDark`），其餘深色表面要等設計規格。
    // 連帶的：`Design/PM決策-視覺方向v1-回覆.md` 第五節第 3 點問的「深色結果頁只到哪裡」
    // 也還沒有答案，那是 S3 的事，但底色 token 是同一批。

    /// 轉盤八色（淺底）。
    ///
    /// 陣列順序就是格子順序，相鄰兩格的色相要拉得開，轉起來才看得出在動。
    /// 命名沿用設計提案的食材名，改色時比較好對照文件。
    static let wheelOnLight: [RGB] = [
        RGB(0xB25239), // 辣椒
        RGB(0xD19A40), // 蛋黃
        RGB(0x9AA65C), // 抹茶
        RGB(0x5E8C72), // 蔥綠
        RGB(0x4E8593), // 青瓷
        RGB(0x5A6E9E), // 藍染
        RGB(0x8B6A9E), // 芋泥
        RGB(0xA5603F), // 焙茶
    ]

    /// 轉盤八色（深底）。順序與 `wheelOnLight` 一一對應，同一格在深淺兩邊是同一個色相。
    static let wheelOnDark: [RGB] = [
        RGB(0xC4644A),
        RGB(0xDEA950),
        RGB(0xA9B56C),
        RGB(0x6E9C81),
        RGB(0x5E95A3),
        RGB(0x6A7EAE),
        RGB(0x9B7AAE),
        RGB(0xB57050),
    ]

    // MARK: - 圓角

    // PM 決策第一節：「圓角／陰影收斂到 10 / 8」。兩個值是定案的，
    // **但哪個元件用哪一個還沒有規格**，所以這裡只照大小命名，不叫 `card` / `button`。
    // S1a 規格到位後再決定要不要改成語意命名。

    static let radiusLarge: Double = 10
    static let radiusSmall: Double = 8

    // MARK: - 線與陰影

    // 同一節：「陰影幾乎取消，改 1px 髮絲線分層」。寬度是定案的，
    // 顏色與透明度不是 —— 深淺兩套各要一個值，等 S1a。
    static let hairlineWidth: Double = 1

    // MARK: - S1a 待補（設計規格-Theme-v1）
    //
    // 下列項目**沒有定案值，不要在這裡填**，補的時候一併把這段註解刪掉：
    //
    // - 字級階層
    // - 間距階層
    // - 髮絲線的顏色與透明度（淺／深各一）
    // - 深色模式的 pageBackground / card / text
    // - icon 版加深規則（見 `Tools/make-icon.swift`，那邊目前會直接報錯）
}
