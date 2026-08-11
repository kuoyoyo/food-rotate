import ActivityKit
import Foundation

/// 「找附近的店」這件事在 Dynamic Island 與鎖定畫面上的樣子。
///
/// App 與 widget extension 都會編到這個檔（`project.pbxproj` 裡兩個 target 的
/// Sources phase 各掛一次），所以放在 `FoodRotate/` 同步資料夾外面，
/// 避免只被 App target 吃掉。
///
/// **這裡以前服務的是「等語言模型產生菜單」。** 菜色改成本地資料庫之後那件事變成瞬間的，
/// 硬要顯示進度條就是騙人，所以 Live Activity 改接到唯一真的會讓人等的路徑：
/// 定位 + `MKLocalSearch`。階段也跟著換成那條路徑真正會發生的事。
///
/// **設計重點：進度條與文字的資訊來源刻意分開。**
/// 定位跟地圖搜尋都拿不到真實百分比，所以進度條走 `startedAt...estimatedFinish`
/// 的時間估計，由 `ProgressView(timerInterval:)` 在系統端自己畫（Live Activity 的更新
/// 有頻率限制，不可能每秒推一次）。文字則是**真實階段**，定位好了、開始搜了都如實反映。
/// 這樣進度條負責「還要等多久」的手感，文字負責「現在到底在幹嘛」的事實，
/// 兩者都不需要說謊。
struct GenerationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stage: Stage
        /// 進度條起點。
        var startedAt: Date
        /// 進度條終點，來自上一次同一條路徑實際花的時間。
        var estimatedFinish: Date
    }

    /// 這次在找什麼，例如「日式・宵夜」或某道菜名。整輪不會變，所以放在 attributes。
    var prompt: String

    enum Stage: Codable, Hashable {
        /// 正在取得位置。授權對話框開著的時候會停在這裡。
        case locating
        /// 位置拿到了，正在問地圖有哪些店。
        case searching
        /// 完成，附上找到幾家。
        case done(count: Int)
        /// 失敗（沒授權、抓不到位置、地圖沒回應、附近沒有）。
        case failed
    }
}

extension GenerationActivityAttributes.Stage {
    var title: String {
        switch self {
        case .locating: "正在取得你的位置…"
        case .searching: "正在找附近的店…"
        case .done(let count): "找到 \(count) 家，可以轉了"
        case .failed: "找不到附近的店"
        }
    }

    var symbolName: String {
        switch self {
        case .locating: "location.fill"
        case .searching: "magnifyingglass"
        case .done: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    /// 這一輪還在跑嗎。完成與失敗之後進度條就不該再動。
    var isRunning: Bool {
        switch self {
        case .locating, .searching: true
        case .done, .failed: false
        }
    }
}
