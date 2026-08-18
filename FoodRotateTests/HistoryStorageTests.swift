import Foundation
import Testing

@testable import FoodRotate

/// 歷史保存壞掉的時候要說出來（S6 P2-5）。
///
/// 現況是靜默的兩層：container 建不起來就退回記憶體、寫入用 `try?` 吞掉錯誤。
/// **使用者以為存了，重啟就沒了。** 那是「假裝成功」——跟靜默退回一般餐廳、
/// 把服務故障說成「附近沒有店」是同一類問題。
///
/// 降級本身是對的（歷史壞掉不該讓 App 開不起來），要改的是**不講**。
@Suite("歷史保存的狀態")
@MainActor
struct HistoryStorageTests {

    @Test("正常啟動不顯示任何提示")
    func 正常時安靜() {
        let storage = HistoryStorage()

        #expect(storage.isDegraded == false)
        #expect(storage.notice == nil)
    }

    @Test("退回記憶體之後要講「關掉就沒了」")
    func 退回記憶體要講清楚() {
        let storage = HistoryStorage()
        storage.markEphemeral(reason: "測試")

        #expect(storage.isDegraded)
        let notice = storage.notice
        #expect(notice != nil)
        // 要講出後果，不是只說「發生錯誤」。
        #expect(notice?.contains("關掉") == true || notice?.contains("保存") == true)
    }

    @Test("寫入失敗之後要有提示")
    func 寫入失敗要有提示() {
        let storage = HistoryStorage()
        storage.recordSave(error: NSError(domain: "test", code: 1))

        #expect(storage.isDegraded)
        #expect(storage.notice != nil)
    }

    @Test("下一次寫入成功就把失敗的提示收掉 —— 不要留一個永久的假警報")
    func 成功之後收掉提示() {
        let storage = HistoryStorage()
        storage.recordSave(error: NSError(domain: "test", code: 1))
        #expect(storage.isDegraded)

        storage.recordSave(error: nil)

        #expect(storage.isDegraded == false, "一個一直亮著的警告等於沒有警告")
        #expect(storage.notice == nil)
    }

    @Test("退回記憶體是整個 session 的事實，寫入成功也不會讓它消失")
    func 退回記憶體不會被一次成功洗掉() {
        let storage = HistoryStorage()
        storage.markEphemeral(reason: "測試")

        // 記憶體裡的寫入當然會成功 —— 但它成功了也還是關掉就沒了。
        storage.recordSave(error: nil)

        #expect(storage.isDegraded, "寫得進記憶體不代表存得住")
        #expect(storage.notice != nil)
    }
}
