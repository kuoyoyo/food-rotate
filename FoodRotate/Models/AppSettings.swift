import Foundation
import SwiftUI

/// 使用者設定的單一來源。
///
/// 以前這裡還存著引擎選擇、自架服務位址、模型名稱、fallback 開關，
/// 以及一套「記上一次產生花了幾秒」的估計機制。拿掉語言模型之後那些全部消失，
/// 剩下的兩項都是純粹的偏好。
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let hasSeenWelcome = "hasSeenWelcome"
        static let wheelSlots = "wheelSlots"
        static let preferredMapApp = "preferredMapApp"
        static let lastNearbyDuration = "lastNearbyDuration"
        static let searchRadius = "searchRadius"
    }

    private let defaults = UserDefaults.standard

    var hasSeenWelcome: Bool {
        didSet { defaults.set(hasSeenWelcome, forKey: Key.hasSeenWelcome) }
    }

    /// 轉盤要幾格。改了不必重抽，畫面會直接從既有的候選裡取用。
    var wheelSlots: Int {
        didSet { defaults.set(wheelSlots, forKey: Key.wheelSlots) }
    }

    /// 點店家時要開哪個地圖 App。清單列上長按可以臨時換另一個，不必進來改。
    var preferredMapApp: MapApp {
        didSet { defaults.set(preferredMapApp.rawValue, forKey: Key.preferredMapApp) }
    }

    /// 「去哪吃」要找多遠以內的店（公尺）。
    var searchRadius: Double {
        didSet { defaults.set(searchRadius, forKey: Key.searchRadius) }
    }

    private init() {
        defaults.register(defaults: [
            Key.wheelSlots: WheelCapacity.defaultSlots,
            Key.preferredMapApp: MapApp.apple.rawValue,
            Key.searchRadius: SearchRadius.defaultValue,
        ])
        hasSeenWelcome = defaults.bool(forKey: Key.hasSeenWelcome)
        preferredMapApp = MapApp(rawValue: defaults.string(forKey: Key.preferredMapApp) ?? "") ?? .apple
        let storedRadius = defaults.double(forKey: Key.searchRadius)
        searchRadius = SearchRadius.allowed.contains(storedRadius) ? storedRadius : SearchRadius.defaultValue
        let storedSlots = defaults.integer(forKey: Key.wheelSlots)
        wheelSlots = WheelCapacity.allowedSlots.contains(storedSlots)
            ? storedSlots
            : WheelCapacity.defaultSlots
    }

    // MARK: - 搜尋耗時

    /// 「去哪吃」載入條與 Live Activity 進度條的長度來源。
    ///
    /// 定位與地圖搜尋都拿不到真實進度，只能估。用**上一次實際花的秒數**比寫死的常數準：
    /// 室內冷啟動定位跟戶外已有快取差好幾倍。
    ///
    /// 上下限是為了擋掉極端值——一次二十秒的冷啟動不該讓之後每一輪的進度條都爬得那麼慢。
    var estimatedNearbyDuration: TimeInterval {
        let stored = defaults.double(forKey: Key.lastNearbyDuration)
        guard stored > 0 else { return 6 }
        return min(20, max(2, stored))
    }

    func recordNearbyDuration(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        defaults.set(seconds, forKey: Key.lastNearbyDuration)
    }
}

/// 「去哪吃」找多遠以內的店。
enum SearchRadius {
    /// 公尺。上限只到十公里——再遠就不是「今天中午去吃」的距離了。
    static let allowed: [Double] = [1_000, 3_000, 5_000, 10_000]

    /// 五公里大約是都會區騎車十五分鐘的範圍，是「值得為了一頓飯跑一趟」的上限。
    static let defaultValue: Double = 5_000

    static func label(_ meters: Double) -> String {
        "\(Int(meters / 1000)) 公里"
    }
}
