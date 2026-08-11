import Foundation

/// 轉盤的角度計算。
///
/// 抽成不依賴 SwiftUI 與 UIKit 的純函數，一來邏輯本身就該跟畫面分開，
/// 二來這段最容易因為浮點誤差選錯格，必須測得到。
///
/// 座標約定：指針固定在 12 點鐘方向。第 i 格佔據本地角度
/// `[i × 每格角度, (i+1) × 每格角度)`，本地角度 0 為正上方、順時針遞增。
/// 轉盤順時針轉 θ 度之後，本地角度 a 會出現在畫面角度 `a + θ`，
/// 因此指針（畫面角度 0）下方的本地角度是 `-θ mod 360`。
enum WheelGeometry {
    /// 目前停在指針下的是第幾格。
    static func segmentUnderPointer(angle: Double, segmentCount: Int) -> Int {
        guard segmentCount > 0 else { return 0 }
        let segment = 360.0 / Double(segmentCount)
        var local = (-angle).truncatingRemainder(dividingBy: 360)
        if local < 0 { local += 360 }
        let index = Int(local / segment)
        // 浮點誤差可能讓 local 剛好等於 360，夾回合法範圍。
        return min(max(index, 0), segmentCount - 1)
    }

    /// 從 `current` 轉到讓 `winner` 停在指針下所需要轉的總角度。
    ///
    /// - Parameters:
    ///   - jitter: 落點在格內的偏移比例，範圍 -0.5...0.5。0 是正中央。
    ///             留一點偏移是為了不要每次都停在同一個位置，看起來太假。
    ///   - turns: 額外多轉幾整圈，讓動畫有份量。
    static func delta(
        from current: Double,
        segmentCount: Int,
        winner: Int,
        turns: Int,
        jitter: Double
    ) -> Double {
        guard segmentCount > 0 else { return 0 }
        let segment = 360.0 / Double(segmentCount)
        let clampedJitter = min(max(jitter, -0.45), 0.45)

        var target = (360 - (Double(winner) + 0.5 + clampedJitter) * segment)
            .truncatingRemainder(dividingBy: 360)
        if target < 0 { target += 360 }

        var currentMod = current.truncatingRemainder(dividingBy: 360)
        if currentMod < 0 { currentMod += 360 }

        var delta = target - currentMod
        if delta < 0 { delta += 360 }
        return delta + 360 * Double(turns)
    }

    /// 三次緩出。慢下來的手感比等速自然，也讓最後幾格的卡榫聲拉得夠開。
    static func easeOut(_ x: Double) -> Double {
        1 - pow(1 - x, 3)
    }

    /// `easeOut` 的反函數，把「轉到第幾格」換算成「第幾秒」。
    static func easeOutInverse(_ y: Double) -> Double {
        1 - pow(1 - y, 1.0 / 3.0)
    }

    /// 轉動過程中每次跨格的時間點與當下的相對速度。
    ///
    /// 一次算完再排程，比每一幀去比對角度可靠：不會漏拍，也不必在 view body 裡做副作用。
    static func tickSchedule(
        startAngle: Double,
        totalDelta: Double,
        segmentCount: Int,
        duration: Double
    ) -> [(time: Double, intensity: Double)] {
        guard segmentCount > 0, totalDelta > 0, duration > 0 else { return [] }
        let segment = 360.0 / Double(segmentCount)

        var result: [(time: Double, intensity: Double)] = []
        var boundary = (startAngle / segment).rounded(.down) * segment + segment
        let end = startAngle + totalDelta

        while boundary < end {
            let progress = (boundary - startAngle) / totalDelta
            result.append((
                time: duration * easeOutInverse(progress),
                intensity: pow(1 - progress, 0.6)
            ))
            boundary += segment
        }
        return result
    }
}
