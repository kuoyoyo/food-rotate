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

    /// 這一輪停下來要做的事。**一定要保存**，否則 `reset()` 取消不了它 ——
    /// 那正是 P0-1：舊的那一個醒來，把新的一輪提前結束掉。
    private var finishTask: Task<Void, Never>?

    /// 「現在是第幾輪」。醒來的工作要先問這個問題才知道自己還算不算數。
    private var runs = GenerationSource()

    /// 等一段時間再回來。
    ///
    /// 抽成可注入的一個函式，是因為這一塊的 bug **全部是「醒來的時機」造成的** ——
    /// 不能控制時機就寫不出會紅的測試，而寫不出會紅的測試就分不出
    /// 「修好了」跟「剛好沒踩到」。正式執行時它就是 `Task.sleep`。
    typealias Wait = @Sendable (Double) async -> Void
    private let wait: Wait

    init(wait: @escaping Wait = { try? await Task.sleep(for: .seconds($0)) }) {
        self.wait = wait
    }

    /// 起轉。`winner` 是要停在哪一格，先決定贏家再回推角度，
    /// 這樣浮點誤差只會影響停的位置好不好看，不會選錯格。
    func spin(segmentCount: Int, winner: Int, onFinish: @escaping () -> Void) {
        guard segmentCount > 0, !isSpinning else { return }

        // 這一輪領一個新號碼，同時把上一輪還在路上的收尾工作取消掉。
        // 兩件事都要做：取消是「請你停下來」，號碼是「就算你沒停下來也不算數」。
        finishTask?.cancel()
        let run = runs.next()

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

        finishTask = Task { [duration, wait] in
            await wait(duration)
            guard !Task.isCancelled else { return }
            self.finish(run: run, onFinish: onFinish)
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
        // 收尾工作也要取消，而且要讓在途的那一個作廢 —— 只把 `isSpinning`
        // 設成 false 擋不住它：下一輪起轉之後它又會看到 true（P0-1）。
        finishTask?.cancel()
        finishTask = nil
        runs.invalidate()
        isSpinning = false
        restingAngle = 0
        startAngle = 0
        totalDelta = 0
    }

    /// 收尾。**`run` 是這件工作出發時領到的號碼。**
    ///
    /// 只檢查 `isSpinning` 是不夠的（P0-1）：那個旗標分不出現在轉的是哪一輪，
    /// 於是上一輪醒來就把新的一輪結束掉，還執行了上一輪的 completion ——
    /// 而那個 completion 記著的是**舊清單的位置**。
    private func finish(run: Generation, onFinish: () -> Void) {
        guard isSpinning, runs.isCurrent(run) else { return }
        restingAngle = (startAngle + totalDelta).truncatingRemainder(dividingBy: 360)
        isSpinning = false
        finishTask = nil
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

        tickTask = Task { [wait] in
            var previous: Double = 0
            for tick in ticks {
                let interval = tick.time - previous
                if interval > 0 {
                    await wait(interval)
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

/// 中選圖示從轉盤飛到結果頁 hero 的兩端。
///
/// `isSource` 要跟著結果頁的開關切換。`matchedGeometryEffect` 的規則是
/// **同一個 id 底下只有 source 那一端定義幾何，其他端跟著它跑**；
/// 而這裡兩端會同時存在（結果頁只壓暗 0.55，轉盤還在後面看得見），
/// 所以誰是 source 必須明講：
///
/// - 結果頁還沒開：轉盤那顆是 source，hero 還不存在
/// - 結果頁開了：hero 變成 source，轉盤那顆讓位並隱藏
///
/// 不切換的話 hero 會被永遠釘在轉盤那一格的框上，跟菜名疊在一起。
struct HeroTransition {
    let namespace: Namespace.ID
    let id: String
    let isSource: Bool
}

// MARK: - 轉盤

struct WheelView: View {
    let items: [FoodItem]
    let angle: Double
    let isSpinning: Bool
    /// 中選的是第幾格。`nil` 代表還沒轉出結果（或條件改了、結果作廢）。
    let winnerIndex: Int?
    let onSpin: () -> Void

    /// 中選圖示要飛到結果頁的話，這裡給 namespace 與 id。`nil` 代表不做轉場。
    ///
    /// **`Canvas` 畫的東西不能參與 `matchedGeometryEffect`** —— 它需要一個真的 view。
    /// 所以中選那一格的圖示會改由一個實際的 `Image` 疊在同樣的位置上畫，
    /// Canvas 那邊則跳過不畫，避免同一個圖示出現兩份。
    var transition: HeroTransition?

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

    /// 分隔線的顏色 —— 就是頁底色。
    private var divider: Color {
        Theme.pageBackground(for: colorScheme)
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

                // 中選格的圖示改用真的 view 畫，這樣它才飛得到結果頁。
                //
                // 放在旋轉容器**外面**，位置自己算 —— 因為圖示本來就恆正立
                // （S2 的決定），不需要跟著轉，這裡剛好省掉一次反向抵消。
                if let transition, let index = matchedIconIndex {
                    matchedIcon(side: side, index: index, transition: transition)
                }

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

    /// 哪一格的圖示由真的 view 畫（而不是 Canvas）。
    private var matchedIconIndex: Int? {
        guard transition != nil, let winnerIndex, items.indices.contains(winnerIndex) else { return nil }
        return winnerIndex
    }

    /// 中選格的圖示，畫成真的 view 好讓它參與 `matchedGeometryEffect`。
    ///
    /// 位置要跟 Canvas 裡那一份**完全一致**，否則轉場起點會偏。
    /// Canvas 那邊是「先轉 drawAngle 再往 x 走 r×ratio」，換算成不旋轉的座標
    /// 就是往 `midAngle + 轉盤角度` 這個方向走同樣的距離 —— 左右半邊的鏡射相消，
    /// 兩邊得到的是同一個點。
    private func matchedIcon(
        side: CGFloat,
        index: Int,
        transition: HeroTransition
    ) -> some View {
        let radius = side / 2 - 6
        let metrics = metrics
        let segment = 360.0 / Double(items.count)
        let midAngle = Double(index) * segment - 90 + segment / 2
        let radians = (midAngle + angle) * .pi / 180
        let distance = radius * metrics.iconRadiusRatio
        let size = metrics.iconSize * radius / WheelLabel.referenceRadius

        return Image(items[index].icon.assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(slots[index % slots.count].ink)
            .matchedGeometryEffect(
                id: transition.id, in: transition.namespace, isSource: transition.isSource
            )
            // 結果頁開了之後 hero 接手當 source，這一顆讓位並隱藏 ——
            // 留著會變成一顆貼在 hero 上的重複圖示。
            .opacity(transition.isSource ? 1 : 0)
            .offset(x: distance * cos(radians), y: distance * sin(radians))
            .allowsHitTesting(false)
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
        let matchedIcon = matchedIconIndex
        let divider = divider

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
                    // 分隔線用**地色**不是白色。
                    //
                    // 白線在深色模式下會變成整個畫面最亮的東西，比任何一格都亮 ——
                    // 注意力被邊界吸走。改成頁底色之後淺色幾乎沒差（頁底本來就接近白），
                    // 深色的問題直接消失。跟 App Icon 是同一條規則：
                    // **分隔線不是畫上去的線，是地色透出來的縫。**
                    context.stroke(path, with: .color(divider), lineWidth: 1.5)
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
                    scale: scale,
                    // 中選格的圖示改由真的 view 畫（轉場要用），這裡跳過不畫，
                    // 否則同一個位置會有兩份圖示疊著。
                    drawsIcon: index != matchedIcon
                )
            }

            // 外圈的白色描邊已經取消：它原本的作用是把轉盤跟頁面分開，
            // 但那件事色塊本身就做到了，留著只是在深色下多一圈亮邊。
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
        scale: CGFloat,
        drawsIcon: Bool
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
        if drawsIcon {
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
        }

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
