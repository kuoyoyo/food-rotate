import Foundation

/// 一次非同步工作的身分。
///
/// 轉盤的一輪與一次餐廳搜尋看起來是兩件事，但它們的錯誤是同一個：
/// **工作發出去之後，回來的時候沒有人知道它還算不算數。**
///
/// - 轉盤：舊的那一輪醒來，看到「現在正在轉」就把新的一輪結束掉，
///   還用舊的位置去讀新的清單（S6 P0-1，唯一會崩潰的一項）
/// - 搜尋：切回「吃什麼」之後舊搜尋回來，把餐廳寫進菜色清單（S6 P1-1）
/// - 搜尋：條件改了卻因為「還在載入」被忽略，畫面顯示新菜系、內容是舊結果（S6 P1-2）
///
/// 三個都是同一句話沒有答案：**這個結果屬於哪一次請求。**
///
/// 所以身分機制只有這一份，兩邊共用。四個地方各做一套是下一個競態的溫床。
///
/// 用法固定是三步：
///
/// ```swift
/// let run = runs.next()          // 1. 發動時領號碼
/// await something()
/// guard runs.isCurrent(run) else { return }   // 2. 每個 await 之後問一次
/// commit(result)                 // 3. 確認還算數才寫進狀態
/// ```
///
/// **`Task.isCancelled` 不能取代它。** 取消是「請你停下來」，但取消不保證來得及 ——
/// 已經越過最後一個檢查點的工作還是會把結果寫出去。號碼牌管的是
/// 「寫出去的那一刻，這個結果還屬不屬於現在」。
struct Generation: Equatable, Sendable, CustomStringConvertible {
    fileprivate let value: UInt64

    /// 還沒有發動過任何一輪。**永遠不會等於任何領到的號碼。**
    static let none = Generation(value: 0)

    var description: String { self == .none ? "gen-none" : "gen\(value)" }
}

/// 號碼牌的發放者。持有它的人就是「現在是第幾輪」的唯一答案。
struct GenerationSource: Sendable {
    private var latest = Generation.none

    /// 開新的一輪，之前發出去的號碼全部作廢。
    mutating func next() -> Generation {
        latest = Generation(value: latest.value + 1)
        return latest
    }

    /// 這個號碼還是現在這一輪嗎。
    ///
    /// `.none` 一律回 false —— 沒有領過號碼的工作不該有資格寫入任何狀態。
    func isCurrent(_ generation: Generation) -> Bool {
        generation != .none && generation == latest
    }

    /// 讓所有在途的工作失效，但不開新的一輪。
    ///
    /// 用在「停下來就好，不要再開始」的場合：轉盤 `reset()`、切換模式。
    /// 作法是把號碼往前推一格 —— 那個號碼不會有人持有，所以每一個
    /// 還在路上的工作問 `isCurrent` 都會得到 false。
    mutating func invalidate() {
        latest = Generation(value: latest.value + 1)
    }
}
