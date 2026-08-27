import Foundation
import Testing

@testable import FoodRotate

/// 改格數的單一入口（QC 2026-08-19 的 D）。
///
/// 設定頁的 Picker 以前直接綁 `AppSettings.wheelSlots`，繞過 `RotateViewModel.wheelSlots`
/// 的三件事：清 winner、reset 轉盤、不夠就補格。於是從設定頁把 8 改成 12 之後，
/// 轉盤仍是 8 格，狀態列還跳出「只湊得出 8 格，可以少選條件或調低格數」——
/// **條件根本沒問題，那句話是假的。**
///
/// ## 這一組是特徵測試，不是先紅後綠
///
/// 要老實講：下面這些斷言**在修之前也是綠的**。缺陷不在這個 setter 裡，
/// 而在「設定頁根本沒走這個 setter」——那是 View 的接線，單元測試碰不到。
/// D 的結構修正是靠讀程式碼與建置驗的（`$settings.wheelSlots` 在 UI 層已經一個都不剩）。
///
/// 那為什麼還要寫？因為設定頁現在**繼承**了這些不變量。
/// 把它們釘下來，下一個人改壞 setter 時會有兩頁一起紅，而不是只有轉盤頁出問題、
/// 設定頁那條路要等使用者回報。
@Suite("改格數的單一入口", .serialized)
@MainActor
struct WheelSlotsEntryTests {

    /// 不汙染使用者的偏好設定。`AppSettings` 是真的單例、寫真的 `UserDefaults`。
    ///
    /// 維持 `rethrows`（closure 哪天需要 `try` 就用得上），但**呼叫端不要寫 `try`** ——
    /// 現在三支的 closure 都沒有 throwing 呼叫，寫了會噴
    /// 「no calls to throwing functions occur within 'try' expression」。
    /// 那三個警告從 S6 就在，一直沒人看到，因為 `PROJECT_STATUS.md` 的「警告 0」
    /// 是用 `xcodebuild build` 量的 —— **那個指令根本不編測試 target**。
    private static func withRestoredSlots(_ body: (AppSettings) throws -> Void) rethrows {
        let settings = AppSettings.shared
        let original = settings.wheelSlots
        defer { settings.wheelSlots = original }
        try body(settings)
    }

    @Test("格數調大要補滿，isShortOfSlots 不得說出一句假話")
    func 補格之後不得再說湊不出來() {
        Self.withRestoredSlots { _ in
            let model = RotateViewModel()
            model.wheelSlots = 4
            model.load()
            #expect(model.allItems.count == 4)

            model.wheelSlots = 12

            #expect(model.allItems.count == 12, "格數調大要補滿")
            #expect(
                model.isShortOfSlots == false,
                "補滿了就不該說「只湊得出 N 格，可以少選條件或調低格數」—— 條件沒有問題"
            )
        }
    }

    @Test("格數調小不重抽，但要把上一輪的中選清掉")
    func 調小要清掉中選() {
        Self.withRestoredSlots { _ in
            let model = RotateViewModel()
            model.wheelSlots = 12
            model.load()
            let before = model.allItems

            // 假裝上一輪轉出了最後一格 —— 調小之後它會落在被截掉的那一段。
            model.winner = model.items.last

            model.wheelSlots = 4

            #expect(model.allItems == before, "格數調小不必重抽，既有候選夠用")
            #expect(model.items.count == 4)
            #expect(
                model.winner == nil,
                "中選那一道可能已經不在盤上了，留著會讓高亮指向一格不存在的東西"
            )
        }
    }

    @Test("同一個值再設一次不做任何事")
    func 設同值不動作() {
        Self.withRestoredSlots { _ in
            let model = RotateViewModel()
            model.wheelSlots = 8
            model.load()
            let before = model.allItems
            model.winner = model.items.first

            model.wheelSlots = 8

            #expect(model.allItems == before, "沒有改變就不該重抽")
            #expect(model.winner != nil, "沒有改變就不該把中選清掉")
        }
    }
}
