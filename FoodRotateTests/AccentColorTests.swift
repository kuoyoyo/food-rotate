import Testing
import UIKit

@testable import FoodRotate

/// App 全域主色。
///
/// 這支測試是為了一個實際發生過的回歸：S2 在 `App.init()` 裡呼叫了 `UIImage(named:)`，
/// 那早於 UIKit 套用全域主色，於是整個 App 的主色退回系統藍 `#0088FF` ——
/// 按鈕、指針、tab bar 全部從橘變藍（`PM驗收-S2-未通過.md` 第一節）。
///
/// **這種壞法沒有任何既有機制接得住**：編得過、不會當、其他測試也全過，
/// 唯一的症狀是顏色不對。
///
/// 驗的是 `UIColor.tintColor` 而不是 `UIColor(named:)`：那次回歸裡**資產本身完全正常**
/// （PM 比對過 `Assets.car`），壞掉的是 UIKit 啟動時套用的那一份。驗資產會過，等於沒驗到。
///
/// 也不能用 `UIColor(Color.accentColor)`：SwiftUI 的語意色離開 view 階層就解析不到
/// App 的全域主色，無論好壞都回系統藍（實測過）。
@Suite("App 主色")
@MainActor
struct AccentColorTests {

    private static func components(_ color: UIColor, _ style: UIUserInterfaceStyle) -> (Double, Double, Double) {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue))
    }

    private static func expect(
        _ actual: (Double, Double, Double),
        near expected: (Double, Double, Double),
        _ what: String
    ) {
        let close = abs(actual.0 - expected.0) < 0.01
            && abs(actual.1 - expected.1) < 0.01
            && abs(actual.2 - expected.2) < 0.01
        #expect(close, "\(what) 是 \(actual)，應該是 \(expected)")
    }

    /// 醬 `#EF652D`／深色版 `#FF7A43`，`AccentColor.colorset` 的兩個值。
    private static let sauce = (0.937, 0.396, 0.176)
    private static let sauceDark = (1.000, 0.478, 0.263)

    @Test("UIKit 套用的全域主色是醬，不是系統藍")
    func 全域主色沒有退回系統色() {
        // 回歸時這裡會是 (0, 0.533, 1)。看到那組數字就去找有沒有人在
        // `App.init()` 或其他 UIKit 起來之前的地方碰了 asset catalog。
        Self.expect(Self.components(.tintColor, .light), near: Self.sauce, "淺色的全域主色")
        Self.expect(Self.components(.tintColor, .dark), near: Self.sauceDark, "深色的全域主色")
    }

    @Test("實際套到 view 上的也是同一個色")
    func view的tint是同一個色() {
        // `UIColor.tintColor` 是全域值，這條確認它真的有傳到 view 層級。
        Self.expect(Self.components(UIView().tintColor, .light), near: Self.sauce, "view 的 tint")
    }

    @Test("色票資產本身沒有被改掉")
    func 資產本身正確() {
        // 這條擋的是另一種壞法：有人直接改了 AccentColor.colorset 的值。
        // 跟上面兩條是不同的失敗模式，所以分開驗。
        let asset = UIColor(named: "AccentColor")
        #expect(asset != nil, "AccentColor 資產不見了")
        if let asset {
            Self.expect(Self.components(asset, .light), near: Self.sauce, "資產的淺色值")
            Self.expect(Self.components(asset, .dark), near: Self.sauceDark, "資產的深色值")
        }
    }
}
