import Foundation
import OSLog
import SwiftData

/// 歷史紀錄能不能真的存下來。
///
/// 這個型別存在的理由是**降級不該是靜默的**（S6 P2-5）。原本有兩層都在無聲失敗：
///
/// 1. `ModelContainer` 建不起來就退回記憶體 —— App 開得起來，但這次的紀錄關掉就沒了
/// 2. 每一次寫入都是 `try? context.save()` —— 錯誤直接被吞掉
///
/// 兩層加起來的結果是：**使用者以為存了，重啟發現不見了。**
/// 那跟靜默退回一般餐廳、把服務故障說成「附近沒有店」是同一類問題 ——
/// 我們給了一個看起來成功的畫面，而事實不是。
///
/// **降級本身要保留**（歷史壞掉不該讓 App 開不起來），要改的是不講。
@MainActor
@Observable
final class HistoryStorage {
    static let shared = HistoryStorage()

    private static let log = Logger(subsystem: "com.kuoyo.foodrotate", category: "history")

    /// 這一次啟動退回了記憶體。**整個 session 的事實**，不會因為之後寫入成功而改變 ——
    /// 寫得進記憶體不代表存得住。
    private(set) var isEphemeral = false

    /// 最近一次寫入失敗了。下一次成功就收掉 ——
    /// 一個一直亮著的警告等於沒有警告（S5 學到的：會固定噴假警報的檢查，人會學會忽略它）。
    private(set) var lastSaveFailed = false

    var isDegraded: Bool { isEphemeral || lastSaveFailed }

    /// 要顯示給使用者的一句話。`nil` 代表一切正常，畫面上什麼都不用出現。
    ///
    /// **講後果，不講技術原因。** 「SwiftData container 初始化失敗」對使用者沒有意義，
    /// 「這次的紀錄關掉 App 就會消失」才有 —— 他可以據此決定要不要現在截圖。
    var notice: String? {
        if isEphemeral {
            return "歷史暫時沒辦法保存，這次轉出的紀錄關掉 App 就會消失。其他功能都正常。"
        }
        if lastSaveFailed {
            return "剛才那一筆紀錄沒有存成功。轉盤與清單不受影響。"
        }
        return nil
    }

    /// 建立 container。失敗就退回記憶體並記下來。
    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: SpinRecord.self)
        } catch {
            log.error("歷史 container 建立失敗，退回記憶體：\(error.localizedDescription, privacy: .public)")
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            // 記憶體版還建不起來的話就真的沒救了，那時候 crash 比裝作沒事好。
            let container = try! ModelContainer(for: SpinRecord.self, configurations: fallback)
            MainActor.assumeIsolated {
                shared.markEphemeral(reason: error.localizedDescription)
            }
            return container
        }
    }

    func markEphemeral(reason: String) {
        isEphemeral = true
        Self.log.error("歷史改用記憶體儲存：\(reason, privacy: .public)")
    }

    /// 寫入的唯一入口。**`try?` 從三個呼叫點收斂到這裡一個地方**，
    /// 這樣「錯誤被吞掉」就不可能再重新長出來。
    func save(_ context: ModelContext) {
        do {
            try context.save()
            recordSave(error: nil)
        } catch {
            recordSave(error: error)
        }
    }

    func recordSave(error: (any Error)?) {
        if let error {
            lastSaveFailed = true
            Self.log.error("歷史寫入失敗：\(error.localizedDescription, privacy: .public)")
        } else {
            lastSaveFailed = false
        }
    }
}
