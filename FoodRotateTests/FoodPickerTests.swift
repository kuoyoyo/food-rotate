import Testing

@testable import FoodRotate

/// `FoodPicker` 的抽樣規則。
///
/// 這裡只釘兩條，但都是**實跑抓到過問題、而且重構時最容易手滑洗掉**的行為
/// （PM 指定，見 `PM裁示-S1開工前提問-回覆.md` 第二節）：
///
/// 1. 忌口永遠不放寬
/// 2. 放寬是「往下補」不是「重來」
///
/// 測試刻意用自己造的候選池而不是 `FoodLibrary.all`：真實資料會隨著加菜改變，
/// 那樣測試哪天紅了會分不出是規則壞了還是資料變了。
///
/// 另外，`FoodPicker` 內部每一層都會洗牌，所以「誰在結果裡」是穩定的、
/// 「誰排第幾個」不是。斷言一律只針對集合，不針對順序；會受洗牌影響的斷言跑 50 次，
/// 一次僥倖過不算過。
@Suite("FoodPicker 的兩條不可改規則")
struct FoodPickerTests {

    // MARK: - 測試資料

    private static func food(
        id: String,
        name: String,
        tags: Set<FoodTag>
    ) -> FoodItem {
        FoodItem(
            id: id,
            name: name,
            emoji: "🍽️",
            category: "測試",
            tags: tags,
            pros: [],
            cons: []
        )
    }

    /// 重跑次數。用來壓掉洗牌造成的偶然通過。
    private static let shuffleRuns = 50

    // MARK: - 規則一：忌口永遠不會被自動放寬

    @Test("候選池裡沒有一道符合忌口時，回報條件過嚴，而且不放寬任何維度")
    func 忌口篩完為空就不放寬() {
        // 候選池裡沒有任何一道標了「無牛」。注意每一道都掛了「日式」，
        // 也就是說**只要肯放寬忌口，隨時湊得滿六格** —— 但規則說不准。
        let library = [
            Self.food(id: "a", name: "牛丼", tags: [.japanese, .rice]),
            Self.food(id: "b", name: "牛肉壽喜燒", tags: [.japanese, .hotpot]),
            Self.food(id: "c", name: "牛肉燴飯", tags: [.japanese, .rice]),
        ]
        var filter = FilterSelection()
        filter.tags = [.noBeef]

        let result = FoodPicker.pick(from: library, matching: filter, count: 6)

        #expect(result.items.isEmpty)
        #expect(result.isOverConstrained)
        // 這條是重點：不是「放寬到最後仍然沒有」，而是**根本沒進放寬迴圈**。
        // 如果哪天有人把忌口併進 softDimensions，這裡會冒出 [.restriction]。
        #expect(result.relaxedDimensions.isEmpty)
    }

    @Test("忌口有得選時，結果裡不會混進不符合忌口的菜")
    func 忌口在放寬過程中仍然成立() {
        // 符合「無牛」的只有 2 道，但要 6 格 —— 一定會觸發放寬。
        // 放寬放掉的必須是菜系那類軟條件，不能為了湊格數把牛肉端出來。
        let library = [
            Self.food(id: "ok1", name: "親子丼", tags: [.japanese, .rice, .noBeef]),
            Self.food(id: "ok2", name: "鮭魚茶泡飯", tags: [.japanese, .rice, .noBeef]),
            Self.food(id: "beef1", name: "牛丼", tags: [.japanese, .rice]),
            Self.food(id: "beef2", name: "牛肉燴飯", tags: [.korean, .rice]),
            Self.food(id: "beef3", name: "牛肉麵", tags: [.taiwanese, .noodles]),
        ]
        var filter = FilterSelection()
        filter.tags = [.japanese, .noBeef]

        for _ in 0..<Self.shuffleRuns {
            let result = FoodPicker.pick(from: library, matching: filter, count: 6)

            #expect(result.items.count == 2)
            #expect(result.items.allSatisfy { $0.tags.contains(.noBeef) })
        }
    }

    // MARK: - 規則二：放寬是往下補，不是重來

    @Test("湊不滿格時，完全符合的菜全部留在結果裡，不足的才從放寬一層補")
    func 放寬是往下補不是重來() {
        // 這就是註解裡記載的那個實跑 bug 的情境：
        // 「日式 + 無牛」只有 5 道，轉盤要 6 格。舊寫法會整個換一組寬鬆條件重篩，
        // 結果盤上一道日式都沒有 —— 使用者明明說了想吃日式。
        var library = (1...5).map {
            Self.food(id: "jp\($0)", name: "日式\($0)", tags: [.japanese, .noBeef])
        }
        library += (1...4).map {
            Self.food(id: "kr\($0)", name: "韓式\($0)", tags: [.korean, .noBeef])
        }
        let japaneseIDs = Set(library.filter { $0.tags.contains(.japanese) }.map(\.id))

        var filter = FilterSelection()
        filter.tags = [.japanese, .noBeef]

        for _ in 0..<Self.shuffleRuns {
            let result = FoodPicker.pick(from: library, matching: filter, count: 6)
            let resultIDs = Set(result.items.map(\.id))

            #expect(result.items.count == 6)
            // 五道日式一道都不能少 —— 這是「往下補」跟「重來」的分水嶺。
            #expect(resultIDs.isSuperset(of: japaneseIDs))
            // 第六格才是補進來的別的菜系。
            #expect(resultIDs.subtracting(japaneseIDs).count == 1)
            // 而且要老實說出放寬了菜系。
            #expect(result.relaxedDimensions == [.cuisine])
        }
    }

    @Test("放寬多層時，越符合的層級越前面，且不重複收同一道菜")
    func 逐層累積不重複() {
        // 日式(1) → 放寬菜系後多出韓式(1) → 再放寬吃法後多出剩下的。
        // 每一層都要去重，同一道菜不能因為在兩層都符合而被收兩次。
        let library = [
            Self.food(id: "jp1", name: "日式拉麵", tags: [.japanese, .noodles]),
            Self.food(id: "kr1", name: "韓式冷麵", tags: [.korean, .noodles]),
            Self.food(id: "tw1", name: "滷肉飯", tags: [.taiwanese, .rice]),
            Self.food(id: "it1", name: "披薩", tags: [.italian, .bread]),
        ]
        var filter = FilterSelection()
        filter.tags = [.japanese, .noodles]

        for _ in 0..<Self.shuffleRuns {
            let result = FoodPicker.pick(from: library, matching: filter, count: 4)
            let ids = result.items.map(\.id)

            #expect(ids.count == Set(ids).count, "同一道菜被收了兩次")
            #expect(ids.first == "jp1", "完全符合的那道必須排在最前面")
            #expect(ids.count == 4)
            // 放寬由後往前：`softDimensions` 裡菜系排在吃法前面，代表菜系比較重要，
            // 所以先放掉吃法，撐不住了才放掉菜系。順序反過來就是規則壞了。
            #expect(result.relaxedDimensions == [.form, .cuisine])
        }
    }

    // MARK: - 避免連按兩次拿到同一組

    @Test("上一輪出現過的菜會被排到後面，但候選池不夠時仍然拿得出來")
    func 上一輪的菜排後面而不是排除() {
        let library = (1...4).map {
            Self.food(id: "f\($0)", name: "菜\($0)", tags: [.japanese])
        }
        var filter = FilterSelection()
        filter.tags = [.japanese]

        // 要 4 道但只有 4 道，全部都在上一輪出現過 —— 排除的話會湊不滿。
        let result = FoodPicker.pick(
            from: library,
            matching: filter,
            count: 4,
            avoiding: Set(library.map(\.id))
        )
        #expect(result.items.count == 4)
    }
}
