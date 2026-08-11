import SwiftUI

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

// MARK: - 轉盤

struct WheelView: View {
    let items: [FoodItem]
    let angle: Double
    let isSpinning: Bool
    let onSpin: () -> Void

    /// 八格用的色盤。相鄰兩格的色相拉開，轉起來才看得出在動。
    private static let palette: [Color] = [
        Color(red: 0.98, green: 0.45, blue: 0.35),
        Color(red: 0.99, green: 0.72, blue: 0.30),
        Color(red: 0.55, green: 0.78, blue: 0.44),
        Color(red: 0.36, green: 0.72, blue: 0.75),
        Color(red: 0.45, green: 0.56, blue: 0.90),
        Color(red: 0.72, green: 0.53, blue: 0.88),
        Color(red: 0.95, green: 0.55, blue: 0.68),
        Color(red: 0.90, green: 0.63, blue: 0.42),
    ]

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                wheelBody(side: side)
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees(angle))
                    .animation(nil, value: angle)

                // 沒有候選清單時不畫中心鈕，否則會跟「先在上面說想吃什麼」的提示疊在一起。
                if !items.isEmpty {
                    hub(side: side)
                }
                pointer(side: side)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: 扇形

    private func wheelBody(side: CGFloat) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 6
            guard !items.isEmpty else {
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

            for (index, item) in items.enumerated() {
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
                context.fill(path, with: .color(Self.palette[index % Self.palette.count]))
                context.stroke(path, with: .color(.white.opacity(0.75)), lineWidth: 1.5)

                drawLabel(
                    item: item,
                    in: context,
                    center: center,
                    radius: radius,
                    midAngle: start + segment / 2,
                    scale: radius / 150
                )
            }

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
    private func drawLabel(
        item: FoodItem,
        in context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        midAngle: Double,
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

        let emoji = context.resolve(
            Text(item.displayEmoji).font(.system(size: max(18, 24 * scale)))
        )
        layer.draw(emoji, at: CGPoint(x: side * radius * 0.46, y: 0), anchor: .center)

        let name = context.resolve(
            Text(shortened(item.name))
                .font(.system(size: max(10, 13 * scale), weight: .semibold))
                .foregroundStyle(.white)
        )
        layer.draw(name, at: CGPoint(x: side * radius * 0.76, y: 0), anchor: .center)
    }

    /// 太長的菜名在扇形裡會超出去，截短並補上省略號。
    private func shortened(_ name: String) -> String {
        name.count <= 5 ? name : String(name.prefix(4)) + "…"
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
