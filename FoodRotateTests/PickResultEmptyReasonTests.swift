import Testing

@testable import FoodRotate

/// 一道都抽不到的時候，**是哪一種空**（QC 2026-08-19 的 F）。
///
/// `isOverConstrained` 原本是用 `items.isEmpty` 算出來的，所以兩件完全不同的事
/// 走到同一個分支，畫面上都說：
///
/// > 忌口條件把所有選項都篩掉了。這一項不會自動放寬，請把其中一個忌口取消再試。
///
/// 但候選池被排空的那個人**可能一個忌口都沒選** —— 那句話對他不只是廢話，
/// 是把他指向一個沒有東西可以取消的地方。他真正的出口在設定頁的「我的清單」。
///
/// 這跟「附近沒有店」不能說成「服務故障」是同一條規則：
/// **我們可以說不知道，不能說一個知道的錯答案。**
@Suite("一道都抽不到的兩種原因")
struct PickResultEmptyReasonTests {

    private static func food(_ id: String, tags: Set<FoodTag>) -> FoodItem {
        FoodItem(
            id: id, name: id, emoji: "🍜", category: "台式",
            tags: tags, pros: ["優點"], cons: ["缺點"]
        )
    }

    @Test("候選池是空的 —— 不是忌口造成的，不能那樣說")
    func 空池不算忌口過嚴() {
        let result = FoodPicker.pick(from: [], matching: FilterSelection(), count: 8)

        #expect(result.items.isEmpty)
        #expect(
            result.isOverConstrained == false,
            "一個忌口都沒選，不該說「忌口條件把所有選項都篩掉了」"
        )
        #expect(
            result.emptyReason == .libraryEmpty,
            "出口在設定頁的「我的清單」，不是取消忌口"
        )
    }

    @Test("忌口真的把選項篩光了 —— 這時候才叫忌口過嚴")
    func 忌口篩光才算忌口過嚴() {
        // 池子裡有東西，但沒有一道標了「無牛」。
        let pool = [
            Self.food("beef-noodle", tags: [.taiwanese, .noodles]),
            Self.food("beef-rice", tags: [.taiwanese, .rice]),
        ]
        let result = FoodPicker.pick(
            from: pool,
            matching: FilterSelection(tags: [.noBeef]),
            count: 8
        )

        #expect(result.items.isEmpty)
        #expect(result.isOverConstrained, "這一種才是「取消一個忌口就有救」")
        #expect(result.emptyReason == .restrictions)
    }

    @Test("抽得到東西的時候沒有原因可講")
    func 抽得到就沒有原因() {
        let pool = [
            Self.food("a", tags: [.taiwanese, .noodles, .noBeef]),
            Self.food("b", tags: [.taiwanese, .rice, .noBeef]),
        ]
        let result = FoodPicker.pick(
            from: pool,
            matching: FilterSelection(tags: [.noBeef]),
            count: 8
        )

        #expect(result.items.count == 2)
        #expect(result.emptyReason == nil)
        #expect(result.isOverConstrained == false)
    }
}
