//
//  make-icon.swift — 產生 App Icon
//
//  用程式畫而不是拉圖，是為了讓 icon 的八格配色跟 App 內的轉盤同源：
//  兩邊都讀 `FoodRotate/DesignTokens.swift`，改了 token 重跑這支就會跟著動。
//  但**同源不等於同值** —— icon 版會再套一道加深（`DesignTokens.deepenedForIcon`），
//  因為 icon 在桌面上只有 60pt，App 裡那組色會糊成一團灰。
//
//  這個檔案放在專案根目錄的 Tools/ 底下，不在 FoodRotate/ 同步資料夾內，
//  所以不會被當成 App 的原始碼編進去。
//
//  用法（要跟 token 一起編，所以是 swiftc 不是 swift）：
//      swiftc Tools/make-icon.swift FoodRotate/DesignTokens.swift -o /tmp/make-icon \
//          && /tmp/make-icon FoodRotate/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
//  以前是 `swift Tools/make-icon.swift <輸出路徑>` 單檔直譯。改成兩個檔之後直譯器不能用了
//  （它只看得到第一個檔），而頂層程式碼在多檔編譯下要放 main.swift，所以這裡改用 `@main`
//  把進入點包起來，檔名才留得住。
//

import AppKit
import CoreGraphics
import Foundation

@main
struct MakeIcon {

    // MARK: - 配色（與 App 同一份 token，另外加深）

    /// 主色・醬。icon 的指針、中心圈與刀叉都用它。
    ///
    /// **不套加深**：那道轉換是為了讓粉彩的盤色在 60pt 下不糊成灰，而醬本來就是深色
    /// （規格只把公式定義在 `wheelOnLight` 母盤上）。醬再加深會壓成一團看不出色相的暗紅。
    static let accent = DesignTokens.sauce.cgColor

    // MARK: - 進入點

    static func main() {
        let size = 1024.0

        // MARK: 畫布

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

        // MARK: 背景

        // 暖色系漸層。彩色轉盤本身已經很吵，背景保持低彩度才不會糊成一團。
        // 這兩個值目前沒有對應的 token（是 icon 專用的），S1a 的 icon 章節可能會重新定義。
        if let gradient = CGGradient(
            colorsSpace: space,
            colors: [
                CGColor(red: 1.00, green: 0.91, blue: 0.80, alpha: 1),
                CGColor(red: 0.99, green: 0.72, blue: 0.51, alpha: 1),
            ] as CFArray,
            locations: [0, 1]
        ) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size),
                end: CGPoint(x: size, y: 0),
                options: []
            )
        }

        // MARK: 轉盤

        // 圓心略低於畫布中心，上方留給指針。
        let center = CGPoint(x: size / 2, y: size * 0.480)
        let radius = size * 0.390

        // 六格不是八格：icon 在桌面上只有 60pt，八格會糊成一團看不出是轉盤。
        let segmentCount = 6
        let segmentAngle = 2 * Double.pi / Double(segmentCount)

        // 走跟 App 內 6 格轉盤**完全一樣**的取色序列（母盤 0,2,3,4,6,7），
        // 而不是自己取前六個 —— 那條序列是跳號取的，為的是讓相鄰色相差最大。
        //
        // 淺底那套是 icon 的基準（icon 背景是暖色淺底），再套加深：
        // 加深公式（飽和 ×1.12、明度 ×0.86）收在 DesignTokens，跟 App 共用同一份母盤。
        let palette = DesignTokens.wheelSlots(count: segmentCount, on: .light)
            .map { DesignTokens.deepenedForIcon($0.fill) }

        // 轉盤底下的陰影，讓它從背景浮起來。
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -size * 0.018),
            blur: size * 0.05,
            color: CGColor(red: 0.55, green: 0.25, blue: 0.08, alpha: 0.30)
        )
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))
        ctx.restoreGState()

        // 八個扇形。從正上方開始順時針排，跟 App 內的轉盤方向一致。
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
            ctx.setFillColor(palette[index].cgColor)
            ctx.fillPath()
        }

        // 扇形之間的白色分隔線。
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.setLineWidth(size * 0.011)
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

        // 外圈白框。
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.setLineWidth(size * 0.032)
        ctx.strokeEllipse(in: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))

        // MARK: 中心圓

        // 中心圓直徑佔轉盤的 40%（原本 29%）。格數少了之後中心留白顯得空，
        // 把刀叉放大才撐得住 60pt 的縮圖 —— 那個尺寸下扇形只是配色，刀叉才是可辨識的部分。
        let hubRadius = radius * 0.40
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -size * 0.006),
            blur: size * 0.022,
            color: CGColor(red: 0.4, green: 0.18, blue: 0.05, alpha: 0.35)
        )
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(
            x: center.x - hubRadius, y: center.y - hubRadius,
            width: hubRadius * 2, height: hubRadius * 2
        ))
        ctx.restoreGState()

        ctx.setStrokeColor(accent)
        ctx.setLineWidth(size * 0.016)
        ctx.strokeEllipse(in: CGRect(
            x: center.x - hubRadius + size * 0.008,
            y: center.y - hubRadius + size * 0.008,
            width: (hubRadius - size * 0.008) * 2,
            height: (hubRadius - size * 0.008) * 2
        ))

        // 中心的刀叉。用 SF Symbol 而不是自己畫路徑，形狀才跟 App 內其他圖示同一套。
        let symbolSize = hubRadius * 1.18
        let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .semibold)
        if let symbol = NSImage(systemSymbolName: "fork.knife", accessibilityDescription: nil)?
            .withSymbolConfiguration(config),
           let mask = symbol.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let width = Double(mask.width)
            let height = Double(mask.height)
            let scale = min(symbolSize / width, symbolSize / height)
            let drawRect = CGRect(
                x: center.x - width * scale / 2,
                y: center.y - height * scale / 2,
                width: width * scale,
                height: height * scale
            )
            // SF Symbol 是黑色加 alpha，拿它的 alpha 當遮罩再填色。
            ctx.saveGState()
            ctx.translateBy(x: 0, y: drawRect.midY * 2)
            ctx.scaleBy(x: 1, y: -1)
            ctx.clip(to: drawRect, mask: mask)
            ctx.setFillColor(accent)
            ctx.fill(drawRect)
            ctx.restoreGState()
        }

        // MARK: 指針

        // 指向下方的三角形，壓在轉盤上緣。有這個才看得出是「轉盤」而不是圓餅圖。
        let pointerHalfWidth = size * 0.070
        let pointerTop = center.y + radius + size * 0.030
        let pointerTip = center.y + radius - size * 0.075

        ctx.beginPath()
        ctx.move(to: CGPoint(x: center.x, y: pointerTip))
        ctx.addLine(to: CGPoint(x: center.x - pointerHalfWidth, y: pointerTop))
        ctx.addLine(to: CGPoint(x: center.x + pointerHalfWidth, y: pointerTop))
        ctx.closePath()

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -size * 0.008),
            blur: size * 0.025,
            color: CGColor(red: 0.4, green: 0.18, blue: 0.05, alpha: 0.4)
        )
        ctx.setFillColor(accent)
        ctx.fillPath()
        ctx.restoreGState()

        // 指針要再描一次路徑，fillPath 會把路徑清掉。
        ctx.beginPath()
        ctx.move(to: CGPoint(x: center.x, y: pointerTip))
        ctx.addLine(to: CGPoint(x: center.x - pointerHalfWidth, y: pointerTop))
        ctx.addLine(to: CGPoint(x: center.x + pointerHalfWidth, y: pointerTop))
        ctx.closePath()
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.setLineWidth(size * 0.016)
        ctx.setLineJoin(.round)
        ctx.strokePath()

        // MARK: 輸出

        let outputPath = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "AppIcon.png"

        guard let image = ctx.makeImage() else { fatalError("產生點陣圖失敗") }
        let url = URL(fileURLWithPath: outputPath)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else {
            fatalError("無法寫入 \(outputPath)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("寫入 PNG 失敗") }
        print("已產生 \(outputPath)（\(Int(size))×\(Int(size))）")
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
