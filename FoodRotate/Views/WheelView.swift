import SwiftUI
import UIKit

/// 轉盤的動畫狀態機。
///
/// 刻意不用 `withAnimation`：轉盤要在「每跨過一格」的瞬間給觸覺回饋，而 SwiftUI 動畫
/// 不會告訴外面現在轉到哪裡。這裡改成自己定義緩動函數，角度由時間算出來（純函數，
/// 可以安全地放在 `TimelineView` 的 body 裡），觸覺的時間點則在起轉前一次算完並排程。
@MainActor
@Observable
final class WheelSpinner {
    private(set) var isSpinning = false
    private(set) var restingAngle: Double = 0

    private var startAngle: Double = 0
    private var totalDelta: Double = 0
    private var startDate: Date = .distantPast
    private var duration: Double = 0
    private var tickTask: Task<Void, Never>?

    /// 起轉。`winner` 是要停在哪一格，先決定贏家再回推角度，
    /// 這樣浮點誤差只會影響停的位置好不好看，不會選錯格。
    func spin(segmentCount: Int, winner: Int, onFinish: @escaping () -> Void) {
        guard segmentCount > 0, !isSpinning else { return }

        startAngle = restingAngle
        totalDelta = WheelGeometry.delta(
            from: restingAngle,
            segmentCount: segmentCount,
            winner: winner,
            turns: Int.random(in: 5...7),
            jitter: Double.random(in: -0.32...0.32)
        )
        duration = 4.2
        startDate = .now
        isSpinning = true

        scheduleTicks(segmentCount: segmentCount)

        Task { [duration] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self.finish(onFinish: onFinish)
        }
    }

    /// 依時間算出目前角度。純函數，沒有副作用，放在 view body 裡是安全的。
    func angle(at date: Date) -> Double {
        guard isSpinning else { return restingAngle }
        let elapsed = date.timeIntervalSince(startDate)
        guard elapsed > 0 else { return startAngle }
        guard elapsed < duration else { return startAngle + totalDelta }
        return startAngle + totalDelta * WheelGeometry.easeOut(elapsed / duration)
    }

    func reset() {
        tickTask?.cancel()
        tickTask = nil
        isSpinning = false
        restingAngle = 0
        startAngle = 0
        totalDelta = 0
    }

    private func finish(onFinish: () -> Void) {
        guard isSpinning else { return }
        restingAngle = (startAngle + totalDelta).truncatingRemainder(dividingBy: 360)
        isSpinning = false
        tickTask?.cancel()
        tickTask = nil
        // 停下來的成功觸覺就在這裡，中選轉場要接的也是這個時間點。
        Haptics.wheelStopped()
        onFinish()
    }

    /// 起轉前一次算完所有跨格時間點，再用一個 Task 依序睡到每個時間點。
    private func scheduleTicks(segmentCount: Int) {
        tickTask?.cancel()

        let ticks = WheelGeometry.tickSchedule(
            startAngle: startAngle,
            totalDelta: totalDelta,
            segmentCount: segmentCount,
            duration: duration
        )
        guard !ticks.isEmpty else { return }

        tickTask = Task {
            var previous: Double = 0
            for tick in ticks {
                let wait = tick.time - previous
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                }
                guard !Task.isCancelled else { return }
                Haptics.wheelTick(intensity: CGFloat(tick.intensity))
                previous = tick.time
            }
        }
    }
}

// MARK: - 中選轉場

/// 中選瞬間的動效。參數全部來自 `Design/設計規格-圖示與動效-v1.md` 第三節（已核可）。
///
/// 三層是**依序**不是同時：高亮 → 結果頁帶入。交界用同一個秒數串起來，
/// 不開兩個獨立計時器 —— 那會在低效能裝置上散掉。
enum WheelCelebration {
    /// 第一層高亮的時長，也是結果頁延後開啟的秒數。
    ///
    /// 兩邊共用同一個常數：分開寫成兩個 0.28 遲早會有一邊被改掉，
    /// 而那時候的症狀是「結果頁把動效蓋掉」，很難聯想到是數字不同步。
    static let duration: Double = 0.28

    /// 中選格放大到幾倍。只有 4.5% —— 轉盤是 `Canvas` 畫的，整格放大會壓到相鄰格，
    /// 4.5% 加上描邊加粗就足以讓那一格跳出來。
    static let winnerScale: Double = 1.045

    /// 其餘格降到多透明。
    static let othersOpacity: Double = 0.55

    static let highlight = Animation.spring(response: 0.28, dampingFraction: 0.72)
    static let fadeOthers = Animation.easeOut(duration: 0.20)
    static let fadeHub = Animation.easeOut(duration: 0.15)
}

// MARK: - 轉盤

struct WheelView: View {
    let items: [FoodItem]
    let angle: Double
    let isSpinning: Bool
    /// 中選的是第幾格。`nil` 代表還沒轉出結果（或條件改了、結果作廢）。
    let winnerIndex: Int?
    let onSpin: () -> Void

    /// 深淺兩底的八色是兩組不同的值（不是同一組調透明度），所以要知道現在是哪一邊。
    @Environment(\.colorScheme) private var colorScheme

    /// 中選轉場的進度，0 → 1。
    ///
    /// 用 SwiftUI 動畫而不是自己算時間：這一段沒有跨格觸覺要對時，
    /// 不像轉動本身有非用 `TimelineView` 不可的理由。
    @State private var celebration: Double = 0

    /// 開了「減少動態效果」就不做縮放，只加粗描邊。
    ///
    /// 取消的是位移與縮放，不是回饋本身 —— 觸覺照給，否則開這個設定的人
    /// 完全不知道轉完了。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 這一輪每一格的底色與文字色。
    ///
    /// 依格數取色，不是「取前 n 個」也不是 `index % 8`：4／6 格跳號取讓相鄰色相差最大，
    /// 10／12 格在末端補同色相的淺一階變體，避免同一盤上出現兩塊一樣的顏色。
    /// 規則收在 `DesignTokens`，這裡不留任何字面值。
    private var slots: [Theme.WheelSlot] {
        Theme.wheelSlots(count: items.count, for: colorScheme)
    }

    /// 這個格數的字級、行距與圖示尺寸。
    private var metrics: WheelLabel.Metrics {
        WheelLabel.metrics(forSlotCount: items.count)
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                rotatingWheel(side: side)

                // 沒有候選清單時不畫中心鈕，否則會跟「先在上面說想吃什麼」的提示疊在一起。
                // 中選之後把它淡掉：結果已經出來了，那顆鈕不再是使用者要看的東西。
                if !items.isEmpty {
                    hub(side: side)
                        .opacity(1 - celebration)
                }
                pointer(side: side)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: winnerIndex) { _, newValue in
            guard newValue != nil else {
                celebration = 0
                return
            }
            celebration = 0
            // 三個對象三條曲線，但同一個進度值 —— 一起起跑才不會散掉。
            withAnimation(WheelCelebration.highlight) { celebration = 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    /// 轉盤的無障礙描述。
    ///
    /// `Canvas` 畫出來的東西 VoiceOver 看不見，所以整個轉盤當成一個元素來報。
    /// 中選之後要講出「中選」兩個字，不然聽的人不知道轉完了、也不知道轉到哪一道。
    private var accessibilityDescription: String {
        guard !items.isEmpty else { return "轉盤，還沒有候選料理" }
        if let winnerIndex, items.indices.contains(winnerIndex) {
            return "轉盤，\(items.count) 格，中選：\(items[winnerIndex].name)"
        }
        return "轉盤，\(items.count) 格：" + items.map(\.name).joined(separator: "、")
    }

    /// 會跟著轉的部分。中心鈕與指針不在裡面 —— 它們是固定的。
    private func rotatingWheel(side: CGFloat) -> some View {
        ZStack {
            // 其餘格降透明度：整盤淡掉，中選那格再用原樣蓋回去。
            // 比「在別的格子上疊半透明黑」單純，而且降的是 opacity 本身，跟規格講的一致。
            wheelBody()
                .opacity(1 - (1 - WheelCelebration.othersOpacity) * celebration)

            if let winnerIndex, !items.isEmpty, celebration > 0 {
                // 中選格連同它的字整個重畫一次 —— 不是只疊一層白，
                // 那樣字會被蓋上一層霧，反而比周圍更難讀。
                wheelBody(only: winnerIndex)
                    .scaleEffect(winnerScale, anchor: .center)
                    .opacity(celebration)
            }
        }
        .frame(width: side, height: side)
        .rotationEffect(.degrees(angle))
        .animation(nil, value: angle)
    }

    /// 中選格放大到幾倍。開了「減少動態效果」就不放大，只靠描邊加粗來標示。
    private var winnerScale: Double {
        guard !reduceMotion else { return 1 }
        return 1 + (WheelCelebration.winnerScale - 1) * celebration
    }

    // MARK: 扇形

    /// 畫轉盤。
    ///
    /// - Parameter only: 只畫這一格（中選轉場用）。`nil` 代表整盤都畫。
    private func wheelBody(only highlighted: Int? = nil) -> some View {
        // 在進 Canvas 之前取一次。這兩個都是 computed property，
        // 留在繪製迴圈裡等於每一格都重算一次（`slots` 還會重跑 HSB 換算）。
        let slots = slots
        let metrics = metrics
        let items = items

        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 6
            guard !items.isEmpty else {
                guard highlighted == nil else { return }
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - radius, y: center.y - radius,
                        width: radius * 2, height: radius * 2
                    )),
                    with: .color(.secondary.opacity(0.15))
                )
                return
            }

            let segment = 360.0 / Double(items.count)
            let scale = radius / WheelLabel.referenceRadius

            for (index, item) in items.enumerated() {
                if let highlighted, index != highlighted { continue }

                let start = Double(index) * segment - 90
                let end = start + segment

                var path = Path()
                path.move(to: center)
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(start),
                    endAngle: .degrees(end),
                    clockwise: false
                )
                path.closeSubpath()

                let slot = slots[index % slots.count]
                context.fill(path, with: .color(slot.fill))

                if highlighted == nil {
                    context.stroke(path, with: .color(.white.opacity(0.75)), lineWidth: 1.5)
                } else {
                    // 中選格的描邊加粗到 3.5，顏色用該格的文字色 —— 白描邊在蛋黃、抹茶
                    // 這種淺格子上幾乎看不見，那正是最需要被標示出來的時候。
                    context.stroke(path, with: .color(slot.ink), lineWidth: 3.5)
                }

                drawLabel(
                    item: item,
                    ink: slot.ink,
                    in: context,
                    center: center,
                    radius: radius,
                    midAngle: start + segment / 2,
                    metrics: metrics,
                    scale: scale
                )
            }

            guard highlighted == nil else { return }
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                )),
                with: .color(.white.opacity(0.9)),
                lineWidth: 5
            )
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }

    /// 每一格的字沿著半徑方向排，讀起來比橫排不歪頭。
    ///
    /// 左半邊（中線角度落在 90°–270°）如果照著中線畫，字會整個上下顛倒。
    /// 這裡多轉 180° 並把繪製點鏡射到 -x，位置不變但字面轉正。
    ///
    /// 兩行的行序**不需要再翻一次**：行距是加在旋轉後的座標系上的，
    /// 而字面也是在同一個座標系裡轉正的，兩者一起鏡射，讀起來仍然是第一行在上。
    /// （規格第七節說要翻，那是對「在全域座標算行位置」的實作才成立。實機驗過。）
    private func drawLabel(
        item: FoodItem,
        ink: Color,
        in context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        midAngle: Double,
        metrics: WheelLabel.Metrics,
        scale: CGFloat
    ) {
        var normalized = midAngle.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        let isLeftHalf = normalized > 90 && normalized < 270
        let drawAngle = isLeftHalf ? midAngle + 180 : midAngle
        let side: CGFloat = isLeftHalf ? -1 : 1

        var layer = context
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: .degrees(drawAngle))

        // 圖示。位置跟著格子走，但**方向永遠正立**。
        //
        // 線稿不像 emoji 那樣耐轉：emoji 靠質地與顏色辨識，線稿靠輪廓方向 ——
        // 一個碗倒過來就不是碗（設計實測九個圖示各轉 120°／220°／300°，
        // 湯匙變鑰匙、鍋子完全認不出來）。
        //
        // 要抵消的是**兩層**旋轉：這一格的 `drawAngle`，以及整個轉盤外層的 `angle`。
        // 而且全程抵消，不是只在停下來時轉正 —— 後者會在停止瞬間跳一下。
        // 轉動中每秒一點多圈，圖示相對盤面的自轉根本看不出來。
        var iconLayer = layer
        iconLayer.translateBy(x: side * radius * metrics.iconRadiusRatio, y: 0)
        iconLayer.rotate(by: .degrees(-(drawAngle + angle)))
        drawIcon(
            for: item,
            ink: ink,
            in: context,
            layer: &iconLayer,
            size: metrics.iconSize * scale
        )

        // 菜名。一到兩行，永遠不截斷。
        let fontSize = max(WheelLabel.minimumFontSize, metrics.fontSize * scale)
        let lines = WheelLabel.lines(for: item.name)
        let lineHeight = fontSize * metrics.lineSpacing
        let textCenter = side * radius * metrics.textRadiusRatio

        for (line, text) in lines.enumerated() {
            let offset = (Double(line) - Double(lines.count - 1) / 2) * lineHeight
            let resolved = context.resolve(
                Text(text)
                    .font(.system(size: fontSize, weight: .semibold))
                    // 不再一律白字：蛋黃與抹茶配白字只有 2.5，遠低於 4.5 的門檻。
                    .foregroundStyle(ink)
            )
            layer.draw(resolved, at: CGPoint(x: textCenter, y: offset), anchor: .center)
        }
    }

    /// 畫這道菜的類型圖示。
    ///
    /// 圖示只表達**類型**不表達身分，所以一盤裡出現兩個「麵食」是正常的 ——
    /// 分辨哪一道是哪一道靠的是旁邊的兩行全名。
    private func drawIcon(
        for item: FoodItem,
        ink: Color,
        in context: GraphicsContext,
        layer: inout GraphicsContext,
        size: CGFloat
    ) {
        // 畫在 layer 的原點 —— 位置與方向都已經由呼叫端的 translate／rotate 決定。
        let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)

        guard let image = FoodIconAssets.image(for: item.icon) else {
            // 資產缺件時什麼都不畫，而不是退回 emoji。
            //
            // 退回去會讓「圖示壞了」看起來像設計如此 —— 一盤裡混著圖示與 emoji，
            // 沒有人分得出是缺件還是刻意。缺哪幾張 DEBUG 開 App 就列出來了。
            return
        }

        var resolved = context.resolve(Image(uiImage: image))
        // 單色，顏色跟著格子的文字色走 —— 同一格裡不會出現白圖示配墨字。
        resolved.shading = .color(ink)
        layer.draw(resolved, in: rect)
    }

    // MARK: 指針與中心鈕

    private func pointer(side: CGFloat) -> some View {
        let width = max(20, side * 0.075)
        return Triangle()
            .fill(Color.accentColor)
            .overlay(Triangle().stroke(.white, lineWidth: 2.5))
            .frame(width: width, height: width * 1.1)
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            .offset(y: -side / 2 + width * 0.4)
    }

    private func hub(side: CGFloat) -> some View {
        Button(action: onSpin) {
            ZStack {
                Circle()
                    .fill(.background)
                    .shadow(color: .black.opacity(0.25), radius: 6)
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                Text(isSpinning ? "…" : "轉")
                    .font(.system(size: side * 0.09, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: side * 0.24, height: side * 0.24)
        }
        .buttonStyle(.plain)
        .disabled(isSpinning || items.isEmpty)
        .accessibilityLabel("轉動轉盤")
    }
}

/// 指向下方的三角形指針。
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
