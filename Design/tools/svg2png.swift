// 把 SVG 點陣化成指定像素的 PNG。給 render-icons.py 用。
//
//     swift Design/tools/svg2png.swift <輸出資料夾> <像素,逗號分隔> <svg...>
//
// 每個檔案產出 <名稱>@<像素>.png，透明底、單色墨跡（顏色由 Python 端上 token）。
//
// ⚠️ 為什麼是 Swift 而不是 qlmanage
// 一開始用 `qlmanage -t`，它**不縮放** —— 把 24×24 的 SVG 原尺寸貼在畫布左上角，
// 其餘留白。量出來每個圖示都是「面積利用率 100%」，因為量到的是畫布不是圖示。
// 小尺寸還會直接吐一塊黑方塊。
//
// 這正是這支腳本要防的那類錯誤：一個看起來成功、其實量錯對象的驗證。
// 所以 render-icons.py 的量測表附有已知值可以對照（肉食 83%×69%）——
// 換渲染器而數字對不上，就是渲染器壞了，不是圖示改了。
//
// NSImage 從 macOS 13 起原生支援 SVG，不需要安裝任何東西。

import AppKit

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write("用法：swift svg2png.swift <outdir> <px,px,...> <svg...>\n".data(using: .utf8)!)
    exit(2)
}

let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
let sizes = args[2].split(separator: ",").compactMap { Int($0) }
let svgs = args[3...].map { URL(fileURLWithPath: $0) }

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for svg in svgs {
    guard let image = NSImage(contentsOf: svg) else {
        FileHandle.standardError.write("讀不到 \(svg.lastPathComponent)\n".data(using: .utf8)!)
        exit(1)
    }
    let stem = svg.deletingPathExtension().lastPathComponent

    for px in sizes {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { exit(1) }

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = ctx
        // 抗鋸齒要開著：真機就是這樣畫的，關掉會看到一個不存在的、更銳利的畫面。
        ctx?.cgContext.setShouldAntialias(true)
        ctx?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px),
                   from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try png.write(to: outDir.appendingPathComponent("\(stem)@\(px).png"))
    }
}
