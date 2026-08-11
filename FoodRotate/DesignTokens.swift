import Foundation

/// 設計 token 的**單一來源**。
///
/// 只用 Foundation，刻意不 import SwiftUI —— 因為這份值有兩個消費者：
/// App 端的 `Theme.swift`（包成 SwiftUI 的 `Color`）與 `Tools/make-icon.swift`
/// （包成 CoreGraphics 的 `CGColor`）。放在只依賴 Foundation 的地方，
/// 那支 macOS 腳本才能跟 App 編同一個檔。**兩份色盤各自演化正是這輪要解掉的問題**
/// （見 `Design/PM決策-視覺方向v1-回覆.md` 第四節），所以界線請維持：
/// 這個檔不准出現 `Color`、`UIColor`、`CGColor` 或任何 View。
///
/// 值的來源：
/// - 方向 B（灶）+ 折衷案，`Design/PM決策-視覺方向v1-回覆.md`，2026-08-11 定案
/// - `Design/設計規格-Theme-v1.md`（S1a），七項全數核可於 `Design/PM核可-設計規格Theme-v1.md`
///
/// 字級不在這裡：它對應的是系統 `TextStyle`（要保住 Dynamic Type）而不是數字，
/// 沒辦法脫離 SwiftUI 表達，所以放在 `Theme.swift`。
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

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    // MARK: - 表面與主色

    /// 主色・醬。淺色模式用。
    static let sauce = RGB(0x9B3B2C)

    enum Light {
        static let pageBackground = RGB(0xEFEAE0)
        static let card = RGB(0xF8F5EE)
        static let text = RGB(0x241E18)
        /// 分層用的髮絲線。**給實色不給透明度**：透明度會隨底層疊加而漂移，
        /// 卡片疊在頁底上跟疊在 sheet 上會變成兩個顏色。
        static let hairline = RGB(0xDAD7D0)

        /// 次要文字（「今天就吃」、版權）。on 卡片 5.14 ／ on 頁底 4.67。
        static let textSecondary = RGB(0x6C6761)
        /// 優點綠。on 卡片 5.67。
        static let positive = RGB(0x3F6B45)
        /// 缺點橘。on 卡片 5.59。
        static let negative = RGB(0x8F5418)
        /// 疊在主色上的文字（主要按鈕）。on `sauce` 6.31。
        static let onSauce = RGB(0xF8F5EE)

        /// 「要行動」那類提示卡的底色。`negative` 6% 疊頁底的等值實色。
        ///
        /// **6% 是被對比逼出來的，不是挑好看的**：染色會把底壓暗，
        /// 深橘標題的對比跟著掉 —— 8% 就是上限（4.57），10% 只剩 4.45 不合格。
        /// 取 6% 留餘裕（4.69）。
        ///
        /// 這個底跟頁底只差 1.08，光靠底色看不出是一張卡，所以淺色的提示卡
        /// **必須**再加一條 1px 髮絲線邊框。
        static let noticeSurface = RGB(0xE9E1D4)
    }

    enum Dark {
        static let pageBackground = RGB(0x1A1714)
        static let card = RGB(0x23201B)
        static let text = RGB(0xEFE9DE)
        static let hairline = RGB(0x3B3832)

        /// 次要文字。on 卡片 6.62 ／ on 頁底 7.28。
        static let textSecondary = RGB(0xAAA59C)
        /// 優點綠。on 卡片 8.38。
        static let positive = RGB(0x8CC98A)
        /// 缺點橘。on 卡片 8.46。
        static let negative = RGB(0xEFAE6E)
        /// 結果頁頂端的把手。= `text` 34% 疊在頁底上的等值實色。
        static let grabber = RGB(0x625E59)

        /// 疊在主色上的文字（主要按鈕）。
        ///
        /// **是深墨不是白。** 白字疊在 `sauce` `#D9674F` 上只有 3.50，不合格；
        /// 深墨是 5.10。深色模式把主色提亮是為了在深底上浮起來，但提亮的同時
        /// 也把「能配白字」這個前提拿掉了 —— 「淺色配深字、深色配淺字」的直覺
        /// 在這裡會反過來。
        ///
        /// **這是整份規格最容易被下一個人「順手修正」回白字的一項，不要改。**
        static let onSauce = RGB(0x1A1714)

        /// 「要行動」那類提示卡的底色。`negative` 10% 疊頁底的等值實色。
        /// 深色這邊跟頁底差 1.20，看得出是一張卡，不需要邊框。
        static let noticeSurface = RGB(0x2F261D)

        /// 深色模式的主色。
        ///
        /// 不是淺色那個 `sauce` 疊上去就好：`#9B3B2C` 在深卡片上對比只有 2.36，
        /// 完全不能用，所以深色需要自己的提亮版（4.64）。
        static let sauce = RGB(0xD9674F)
    }

    // 底色刻意帶暖偏（不是中性灰黑），跟「灶」的食材色系同一個世界。

    // MARK: - 轉盤

    /// 格子上的字要用哪一種墨。
    ///
    /// 存在的理由：以前轉盤是**無條件白字**，而定案八色裡的蛋黃與抹茶配白字只有
    /// 2.50 / 2.63，遠低於 4.5 的門檻。文字色必須跟著格子色走。
    enum LabelInk: Equatable, Sendable {
        case light
        case dark

        var color: RGB {
            switch self {
            case .light: Ink.light
            case .dark: Ink.dark
            }
        }
    }

    /// 格子上的兩種墨。
    ///
    /// 淺墨是**純白**不是卡片色：規格那張對比表是照 `#FFFFFF` 算的，
    /// 換成 `#F8F5EE` 會讓幾格 4.5x 的掉到門檻底下。
    enum Ink {
        static let light = RGB(0xFFFFFF)
        static let dark = Light.text
    }

    /// 一格的完整資訊：底色與它該配的墨色。
    ///
    /// 綁成一個型別而不是兩個平行陣列，是為了讓「改了底色卻忘了改文字色」這件事
    /// 在結構上就不容易發生 —— 對比不合格是看不出來的那種壞。
    struct WheelSlot: Equatable, Sendable {
        let fill: RGB
        let ink: LabelInk
    }

    /// 母盤八色（淺底）。陣列順序就是取色順序表裡的 index 0–7。
    /// 命名沿用設計提案的食材名，改色時比較好對照文件。
    static let wheelOnLight: [WheelSlot] = [
        WheelSlot(fill: RGB(0xB25239), ink: .light), // 0 辣椒 5.05
        WheelSlot(fill: RGB(0xD19A40), ink: .dark),  // 1 蛋黃 6.60（白字只有 2.50，所以走墨字）
        WheelSlot(fill: RGB(0x9AA65C), ink: .dark),  // 2 抹茶 6.27（同上，白字 2.63）
        WheelSlot(fill: RGB(0x557F68), ink: .light), // 3 蔥綠 4.54（明度微調過，原 #5E8C72 是 3.84）
        WheelSlot(fill: RGB(0x4A7E8B), ink: .light), // 4 青瓷 4.52（明度微調過，原 #4E8593 是 4.12）
        WheelSlot(fill: RGB(0x5A6E9E), ink: .light), // 5 藍染 5.05
        WheelSlot(fill: RGB(0x8B6A9E), ink: .light), // 6 芋泥 4.51
        WheelSlot(fill: RGB(0xA5603F), ink: .light), // 7 焙茶 4.83
    ]

    /// 母盤八色（深底）。順序與 `wheelOnLight` 一一對應，同一格在深淺兩邊是同一個色相。
    ///
    /// 深底**全部用墨字**：深色模式下盤色本來就提亮了，墨字反而穩定。
    static let wheelOnDark: [WheelSlot] = [
        WheelSlot(fill: RGB(0xCE694E), ink: .dark), // 0 辣椒 4.53（提亮過）
        WheelSlot(fill: RGB(0xDEA950), ink: .dark), // 1 蛋黃 7.77
        WheelSlot(fill: RGB(0xA9B56C), ink: .dark), // 2 抹茶 7.47
        WheelSlot(fill: RGB(0x6E9C81), ink: .dark), // 3 蔥綠 5.29
        WheelSlot(fill: RGB(0x5E95A3), ink: .dark), // 4 青瓷 4.95
        WheelSlot(fill: RGB(0x7085B8), ink: .dark), // 5 藍染 4.52（提亮過）
        WheelSlot(fill: RGB(0x9B7AAE), ink: .dark), // 6 芋泥 4.54
        WheelSlot(fill: RGB(0xBB7453), ink: .dark), // 7 焙茶 4.51（提亮過）
    ]

    enum Surface: Equatable, Sendable {
        case light
        case dark
    }

    /// 這個格數該用哪幾個顏色，依序。
    ///
    /// 為什麼不是「取前 n 個」或「index % 8」：
    /// - 4／6 格**跳號取**，讓相鄰色相差最大（4 格是辣椒／抹茶／青瓷／芋泥，四個象限）
    /// - 10／12 格**不擴充色相**。12 個降飽和的食材色必然互相靠近，硬擠只會更難辨識，
    ///   而且等於推翻已定案的八色。改用同色相的淺一階變體排在末端。
    ///
    /// 格數理論上只會是 4／6／8／10／12（`WheelCapacity.allowedSlots`），但轉盤實際畫幾格
    /// 是看**抽到幾道菜** —— 條件太嚴時可能只有 3 道。所以沒列在表裡的格數要有退路。
    static func wheelSlots(count: Int, on surface: Surface) -> [WheelSlot] {
        guard count > 0 else { return [] }

        let mother = surface == .light ? wheelOnLight : wheelOnDark
        let order = slotOrder(for: count)
        return order.map { reference in
            let base = mother[reference.index]
            guard reference.isLightVariant else { return base }
            // 淺階變體一律墨字：它比母色淺一階，白字必然更不夠。
            return WheelSlot(fill: lightenedVariant(base.fill), ink: .dark)
        }
    }

    /// 取色序列裡的一項：母盤第幾號、是不是淺階變體。
    struct SlotReference: Equatable, Sendable {
        let index: Int
        let isLightVariant: Bool
    }

    static func slotOrder(for count: Int) -> [SlotReference] {
        func mother(_ indices: [Int]) -> [SlotReference] {
            indices.map { SlotReference(index: $0, isLightVariant: false) }
        }
        func variant(_ indices: [Int]) -> [SlotReference] {
            indices.map { SlotReference(index: $0, isLightVariant: true) }
        }

        switch count {
        case 4: return mother([0, 2, 4, 6])
        case 6: return mother([0, 2, 3, 4, 6, 7])
        case 8: return mother([0, 1, 2, 3, 4, 5, 6, 7])
        case 10: return mother([0, 1, 2, 3, 4, 5, 6, 7]) + variant([0, 2])
        case 12: return mother([0, 1, 2, 3, 4, 5, 6, 7]) + variant([0, 2, 3, 1])
        default:
            // 表外的格數（抽不滿時會發生）。照 12 格那條序列取前 n 個，
            // 超過 12 才繞回去 —— 繞回去只會發生在格數上限被調高，那時候應該回來補表。
            let canonical = slotOrder(for: 12)
            return (0..<count).map { canonical[$0 % canonical.count] }
        }
    }

    // MARK: - 由母盤推導出來的顏色

    /// 淺一階變體：同色相，飽和 ×0.82、明度 ×1.20。
    ///
    /// 10／12 格用。不另存一份色票，是因為它必須跟著母盤走 ——
    /// 母盤改了而變體沒改，就是這輪要解掉的那種分岔。
    static func lightenedVariant(_ color: RGB) -> RGB {
        color.scaled(saturation: 0.82, brightness: 1.20)
    }

    /// icon 版加深：同色相，飽和 ×1.12、明度 ×0.86。
    ///
    /// App 裡的轉盤有大片留白襯著，icon 在桌面上只有 60 點大小，同一組色會糊成一團灰，
    /// 所以 icon 需要更深的版本。這道轉換**必須留著**，不能把兩邊壓成同一組數值
    /// （見 `Design/PM決策-視覺方向v1-回覆.md` 第四節）。
    ///
    /// 母盤取 `wheelOnLight`。純函數，不需要另存一份色票。
    static func deepenedForIcon(_ color: RGB) -> RGB {
        color.scaled(saturation: 1.12, brightness: 0.86)
    }

    // MARK: - 形

    // PM 決策第一節：「圓角／陰影收斂到 10 / 8」。
    //
    // 規格第五節給了語意歸屬（10 用在卡片／提示框／載入框／sheet 分區塊，
    // 8 用在卡片內的圖示底／小型狀態標記；按鈕與 chip 維持 Capsule），
    // 但**命名維持照大小**，設計說由工程決定。維持大小命名的理由：同一個值服務好幾種語意，
    // 叫 `radiusCard` 反而會讓「提示框為什麼用卡片的圓角」變成需要解釋的事。
    static let radiusLarge: Double = 10
    static let radiusSmall: Double = 8

    /// 結果頁上緣。比 `radiusLarge` 大很多，因為那是整個畫面寬度的表面邊緣，
    /// 10 在那個尺度上看起來像沒做圓角。
    static let radiusSheet: Double = 20

    /// 角標。`radiusSmall` 8 對 16pt 高的元素太圓了。
    static let radiusBadge: Double = 4

    /// 分層用的髮絲線寬度。顏色見 `Light.hairline` / `Dark.hairline`。
    static let hairlineWidth: Double = 1

    // MARK: - 間距

    // 4 的倍數，八階。現有程式碼裡的 6／10／14 三個奇數值就近靠攏（6→4、9→8、10→12、14→16）。
    // 靠攏是各個 View 各自改，屬於 S3–S5 的範圍，這裡只先把階梯定義出來。

    static let space2: Double = 2
    static let space4: Double = 4
    static let space8: Double = 8
    static let space12: Double = 12
    static let space16: Double = 16
    static let space20: Double = 20
    static let space24: Double = 24
    static let space32: Double = 32
}

// MARK: - HSB

extension DesignTokens.RGB {
    /// 同色相下縮放飽和與明度。
    ///
    /// 自己算而不是用 `UIColor` / `NSColor`：這個檔要能被 iOS App 與 macOS 腳本同時編，
    /// 而且 `Core` 那條「只用 Foundation」的界線在這裡同樣適用。
    /// 兩個係數都會夾在 0...1，避免飽和或明度被推出範圍。
    func scaled(saturation saturationScale: Double, brightness brightnessScale: Double) -> Self {
        let (hue, saturation, brightness) = hsb
        return Self(
            hue: hue,
            saturation: min(saturation * saturationScale, 1),
            brightness: min(brightness * brightnessScale, 1)
        )
    }

    var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum

        guard delta > 0 else { return (0, 0, maximum) }

        var sixths: Double
        switch maximum {
        case red: sixths = (green - blue) / delta
        case green: sixths = 2 + (blue - red) / delta
        default: sixths = 4 + (red - green) / delta
        }
        sixths /= 6
        if sixths < 0 { sixths += 1 }

        return (hue: sixths, saturation: delta / maximum, brightness: maximum)
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        guard saturation > 0 else {
            self.init(red: brightness, green: brightness, blue: brightness)
            return
        }

        let sector = (hue.truncatingRemainder(dividingBy: 1) + 1)
            .truncatingRemainder(dividingBy: 1) * 6
        let index = Int(sector)
        let fraction = sector - Double(index)

        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))

        switch index {
        case 0: self.init(red: brightness, green: t, blue: p)
        case 1: self.init(red: q, green: brightness, blue: p)
        case 2: self.init(red: p, green: brightness, blue: t)
        case 3: self.init(red: p, green: q, blue: brightness)
        case 4: self.init(red: t, green: p, blue: brightness)
        default: self.init(red: brightness, green: p, blue: q)
        }
    }
}
