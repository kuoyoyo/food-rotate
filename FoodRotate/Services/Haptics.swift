import UIKit

/// 轉盤的觸覺回饋。
///
/// 轉動時每跨過一格就給一下輕擊，模擬實體轉盤打到卡榫的手感；停下來時給一個成功通知。
/// 模擬器沒有 Taptic Engine，這些呼叫會安靜地什麼都不做。
@MainActor
enum Haptics {
    private static let tick = UIImpactFeedbackGenerator(style: .light)
    private static let stop = UINotificationFeedbackGenerator()
    private static let tap = UIImpactFeedbackGenerator(style: .medium)

    /// 先暖機可以讓第一下回饋不延遲。
    static func prepare() {
        tick.prepare()
        stop.prepare()
    }

    static func wheelTick(intensity: CGFloat) {
        tick.impactOccurred(intensity: max(0.25, min(1, intensity)))
        tick.prepare()
    }

    static func wheelStopped() {
        stop.notificationOccurred(.success)
    }

    static func buttonTap() {
        tap.impactOccurred()
    }
}
