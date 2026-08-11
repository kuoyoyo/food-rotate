#!/usr/bin/env swift
//
//  make-icon.swift — 產生 App Icon
//
//  用程式畫而不是拉圖，是為了讓 icon 的八格配色跟 `WheelView.palette` 完全一致，
//  日後改了 App 裡的轉盤顏色，重跑這支就能同步 icon。
//
//  這個檔案放在專案根目錄的 Tools/ 底下，不在 FoodRotate/ 同步資料夾內，
//  所以不會被當成 App 的原始碼編進去。
//
//  用法：
//      swift Tools/make-icon.swift FoodRotate/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//

import AppKit
import CoreGraphics
import Foundation

let size = 1024.0

// MARK: - 配色（與 WheelView.palette 相同）

// 色相沿用 WheelView.palette，但整體加深。App 裡的轉盤有大片留白襯著，
// icon 在桌面上只有 60 點大小，原本的粉彩會糊成一團灰。
let palette: [(Double, Double, Double)] = [
    (0.95, 0.33, 0.24),
    (0.98, 0.64, 0.16),
    (0.42, 0.71, 0.32),
    (0.20, 0.63, 0.68),
    (0.31, 0.44, 0.85),
    (0.63, 0.40, 0.83),
    (0.93, 0.40, 0.57),
    (0.85, 0.52, 0.28),
]

let accent = CGColor(red: 0.937, green: 0.396, blue: 0.176, alpha: 1)

// MARK: - 畫布

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

let canvas = CGRect(x: 0, y: 0, width: size, height: size)

// MARK: - 背景

// 暖色系漸層。彩色轉盤本身已經很吵，背景保持低彩度才不會糊成一團。
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

// MARK: - 轉盤

// 圓心略低於畫布中心，上方留給指針。
let center = CGPoint(x: size / 2, y: size * 0.480)
let radius = size * 0.390
let segmentCount = 8
let segmentAngle = 2 * Double.pi / Double(segmentCount)

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
    let (r, g, b) = palette[index]
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
    ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
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

// MARK: - 中心圓

let hubRadius = radius * 0.290
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

// MARK: - 指針

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

// MARK: - 輸出

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
