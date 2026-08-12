//
//  make-icon.swift — 產生 App Icon
//
//  用程式畫而不是把 SVG 丟進 asset catalog，是為了讓 icon 的配色跟 App 內的轉盤同源：
//  兩邊都讀 `FoodRotate/DesignTokens.swift`，改了 token 重跑這支就會跟著動。
//  色值一旦烙進 SVG，日後改色盤 icon 就會再次跟 App 分岔 —— 那正是 S1 花力氣解掉的問題。
//  （`Design/icons/app-icon.svg` 是設計稿與視覺驗證用的參考檔，不是生產來源。）
//
//  同源不等於同值：icon 版會再套一道加深（`DesignTokens.deepenedForIcon`），
//  因為 icon 在桌面上只有 60pt，App 裡那組色會糊成一團灰。
//
//  幾何全部以邊長 S 的比例表示（`Design/設計規格-AppIcon-v1.md` 第二節），
//  任何尺寸等比成立。
//
//  用法（要跟 token 一起編，所以是 swiftc 不是 swift）：
//      swiftc Tools/make-icon.swift FoodRotate/DesignTokens.swift -o /tmp/make-icon \
//          && /tmp/make-icon <彩色輸出.png> [<去色輸出.png>]
//

import AppKit
import CoreGraphics
import Foundation

@main
struct MakeIcon {

    // MARK: - 配色

    /// 一張 icon 需要的顏色。彩色版與去色版**共用同一段幾何**，只有這裡不同。
    struct Palette {
        let background: DesignTokens.RGB
        /// 六格的顏色，依取色序列排好。
        let slices: [DesignTokens.RGB]
        let pointer: DesignTokens.RGB
    }

    /// 彩色版。
    ///
    /// 六格走跟 App 內 6 格轉盤**完全一樣**的取色序列（母盤 0,2,3,4,6,7）再套加深 ——
    /// 使用者把 App 開起來會看到同一個東西。
    static var colorful: Palette {
        Palette(
            background: DesignTokens.Dark.pageBackground,
            slices: DesignTokens.wheelSlots(count: segmentCount, on: .light)
                .map { DesignTokens.deepenedForIcon($0.fill) },
            // 指針用淺色模式的主色，不是深色的提亮版。它疊在深底上，是整張圖唯一的品牌色點。
            pointer: DesignTokens.sauce
        )
    }

    /// 去色版。
    ///
    /// **一定要自己做，不能讓系統自動去色。** 實測模擬：沒有分隔線的話六格會變成
    /// 一個幾乎均勻的灰盤，識別完全消失。這是「顏色是裝飾、結構是分隔線」的極端案例 ——
    /// 去色之後只剩結構還在。
    static var tinted: Palette {
        let ink = DesignTokens.RGB(0xE7E2D8)
        return Palette(
            background: DesignTokens.Dark.pageBackground,
            slices: Array(repeating: ink, count: segmentCount),
            pointer: ink
        )
    }

    // MARK: - 幾何（單位為邊長 S 的比例）

    static let segmentCount = 6
    /// 轉盤直徑。
    static let wheelDiameter = 0.86
    /// 分隔線寬。**色是背景色** —— 分隔線不是畫上去的線，是地色透出來的縫。
    static let dividerWidth = 0.016
    /// 指針半寬，以轉盤半徑 R 為單位。
    static let pointerHalfWidth = 0.20
    /// 指針高 = 半寬的 1.5 倍。
    static let pointerHeightRatio = 1.5
    /// 指針底邊離圓周多遠（R 的比例）。
    static let pointerGap = 0.10
    /// 內層指針相對外層內縮多少。
    static let pointerInset = 0.012

    // MARK: - 進入點

    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        guard let colorPath = arguments.first else {
            fatalError("用法：make-icon <彩色輸出.png> [<去色輸出.png>]")
        }

        write(palette: colorful, to: colorPath)
        if let tintedPath = arguments.dropFirst().first {
            write(palette: tinted, to: tintedPath)
        }
    }

    static func write(palette: Palette, to path: String) {
        let size = 1024.0
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: Int(size), height: Int(size),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("建立繪圖環境失敗")
        }

        draw(palette: palette, in: ctx, size: size)

        guard let image = ctx.makeImage() else { fatalError("產生點陣圖失敗") }
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else {
            fatalError("無法寫入 \(path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("寫入 PNG 失敗") }
        print("已產生 \(path)（\(Int(size))×\(Int(size))）")
    }

    // MARK: - 繪製

    /// 彩色版與去色版跑的是**同一段程式**，差別只有傳進來的 `palette`。
    ///
    /// 沒有中心圓、沒有刀叉、沒有外圈描邊 —— 那三個在 40pt 就糊掉、29pt 完全消失。
    /// 留下來的是六格色盤與指針，那是縮到 20pt 還活著的結構。
    static func draw(palette: Palette, in ctx: CGContext, size: CGFloat) {
        // 背景滿版。
        ctx.setFillColor(palette.background.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        let center = CGPoint(x: size / 2, y: size / 2)
        let radius = size * wheelDiameter / 2
        let segmentAngle = 2 * Double.pi / Double(segmentCount)

        // 六個扇形。從正上方開始順時針排，跟 App 內的轉盤方向一致。
        for index in 0..<segmentCount {
            // CoreGraphics 的 0 度在右方且逆時針為正，這裡轉成「正上方起、順時針」。
            let start = Double.pi / 2 - Double(index) * segmentAngle
            let end = start - segmentAngle

            ctx.beginPath()
            ctx.move(to: center)
            ctx.addArc(
                center: center, radius: radius,
                startAngle: start, endAngle: end,
                clockwise: true
            )
            ctx.closePath()
            ctx.setFillColor(palette.slices[index].cgColor)
            ctx.fillPath()
        }

        // 分隔線。用背景色畫在扇形上，看起來就是地色從縫裡透出來。
        // 去色版沒有它就只是一個純色圓，這是它必須存在的理由。
        ctx.setStrokeColor(palette.background.cgColor)
        ctx.setLineWidth(size * dividerWidth)
        for index in 0..<segmentCount {
            let angle = Double.pi / 2 - Double(index) * segmentAngle
            ctx.beginPath()
            ctx.move(to: center)
            ctx.addLine(to: CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            ))
            ctx.strokePath()
        }

        drawPointer(palette: palette, in: ctx, size: size, center: center, radius: radius)
    }

    /// 指針。**兩層**：先用背景色畫一個三角在盤上切出缺口，再畫一個內縮的主色三角。
    ///
    /// 只畫一層的話指針會跟第一格的紅色黏在一起 —— 兩者都是暖紅，邊界會消失。
    ///
    /// 它比原本的細指針大四倍而且移出盤外，原因是舊的在 29pt 就看不見了。
    /// 現在 20pt 都還讀得出「有缺口的彩色分割圓」。
    static func drawPointer(
        palette: Palette,
        in ctx: CGContext,
        size: CGFloat,
        center: CGPoint,
        radius: CGFloat
    ) {
        let halfWidth = radius * pointerHalfWidth
        let height = halfWidth * pointerHeightRatio
        // 底邊在圓周外，頂點朝下插進盤裡 —— 插進去的那一段就是缺口。
        let baseY = center.y + radius + radius * pointerGap
        let apexY = baseY - height

        func triangle(halfWidth: CGFloat, baseY: CGFloat, apexY: CGFloat) {
            ctx.beginPath()
            ctx.move(to: CGPoint(x: center.x, y: apexY))
            ctx.addLine(to: CGPoint(x: center.x - halfWidth, y: baseY))
            ctx.addLine(to: CGPoint(x: center.x + halfWidth, y: baseY))
            ctx.closePath()
            ctx.fillPath()
        }

        ctx.setFillColor(palette.background.cgColor)
        triangle(halfWidth: halfWidth, baseY: baseY, apexY: apexY)

        let inset = size * pointerInset
        ctx.setFillColor(palette.pointer.cgColor)
        triangle(halfWidth: halfWidth - inset, baseY: baseY - inset, apexY: apexY + inset)
    }
}

private extension DesignTokens.RGB {
    /// token 只是數值，畫圖時才決定色彩空間。跟 App 端的 `Theme.swift` 一樣走 sRGB。
    var cgColor: CGColor {
        CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [red, green, blue, 1]
        )!
    }
}
