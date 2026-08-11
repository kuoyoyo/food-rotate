import Foundation

/// 一次抽樣的結果。
struct PickResult: Equatable, Sendable {
    var items: [FoodItem]

    /// 為了湊滿格數，放寬掉的維度。UI 用它老實說明「符合的不夠，已放寬『口味』」。
    /// 空陣列代表選的條件本來就夠用。
    var relaxedDimensions: [FoodTag.Dimension]

    /// 忌口條件本身就篩不出東西。這時候不放寬、不隨便給，直接讓 UI 說清楚。
    var isOverConstrained: Bool { items.isEmpty }
}

/// 從候選池裡挑出這一輪要放上轉盤的菜。
///
/// 取代原本的 `EngineRouter`。差別不只是「不叫模型」：
/// 以前是先拿到模型給的一批菜、再用 `DietaryFilter` / `MainDishFilter` / `normalized()`
/// 三層去修它，因為模型不照規則走；現在是從一開始就只挑符合的，沒有東西需要修。
///
/// 純函數、無 async、只用 Foundation 基本型別，方便日後對翻 Kotlin。
enum FoodPicker {
    /// 挑一組候選。
    ///
    /// - Parameters:
    ///   - library: 候選池（內建資料庫 + 使用者自訂，且已排除掉「以後都不要」的）。
    ///   - filter: 使用者選的標籤。
    ///   - count: 要幾道。
    ///   - avoiding: 上一輪抽到的 `id`。抽樣是瞬間的，使用者會連按很多次，
    ///     兩輪一模一樣會讓人以為壞掉，所以把上一輪的排到後面 —— 但不是排除，
    ///     候選池小的時候排除會湊不滿格。
    static func pick(
        from library: [FoodItem],
        matching filter: FilterSelection,
        count: Int,
        avoiding previous: Set<String> = []
    ) -> PickResult {
        // 第一步：忌口。硬條件，違反就是不能吃，任何情況都不放寬。
        // 篩完是空的就直接回報，不退而求其次 —— 讓「不吃牛」的人看到牛肉麵，
        // 比讓他看到空轉盤嚴重得多。
        let restrictions = filter.tags(in: .restriction)
        let allowed = library.filter { $0.tags.isSuperset(of: restrictions) }
        guard !allowed.isEmpty else {
            return PickResult(items: [], relaxedDimensions: [])
        }

        // 第二步：軟條件。同維度內取聯集（選了「日式」跟「韓式」＝日式或韓式），
        // 跨維度取交集（「日式」+「清爽」＝日式而且清爽）。
        var active = softDimensions.filter { !filter.tags(in: $0).isEmpty }

        // 第三步：不夠就逐層放寬，由後往前 —— `softDimensions` 的順序即重要性，
        // 「其他」（便宜、快）放掉的損失比「菜系」小得多。
        //
        // **放寬是往下補，不是重來。** 一開始寫成「條件不夠就整個換一組寬鬆的重篩」，
        // 結果選「日式 + 無牛」時，標了無牛的日式只有 5 道、轉盤要 6 格，
        // 於是菜系被放寬，轉盤上一道日式都沒有 —— 使用者明明講了想吃日式。
        // 改成逐層累積：完全符合的先全部放進去，不足的才從放寬一層的結果裡補，
        // 這樣「日式」那 5 道一定在盤上，第 6 格才是別的菜系。
        var pool: [FoodItem] = []
        var seen = Set<String>()
        var relaxed: [FoodTag.Dimension] = []

        func absorb(matching dimensions: [FoodTag.Dimension]) {
            let tier = allowed
                .filter { $0.matches(filter, in: dimensions) }
                .filter { seen.insert($0.id).inserted }
            pool += sample(tier, count: tier.count, avoiding: previous)
        }

        absorb(matching: active)
        while pool.count < count, let dropped = active.popLast() {
            relaxed.append(dropped)
            absorb(matching: active)
        }

        // 全部放寬還是不夠，那就是候選池本身太小，這時候有幾道給幾道。
        // 這不算「放寬」，所以不記進 relaxed —— 提示要講的是「條件太嚴」，
        // 而候選池小是另一回事（使用者排除太多道），訊息不該混在一起。
        //
        // 這裡不能再洗一次牌：`pool` 的順序就是「符合程度」的順序，
        // 洗掉就等於把剛剛費工累積的優先權丟掉。每一層內部已經各自洗過了。
        return PickResult(
            items: Array(pool.prefix(count)),
            relaxedDimensions: relaxed
        )
    }

    /// 軟條件的維度，順序即重要性（越前面越晚被放寬）。
    /// `restriction` 不在裡面，它是硬條件。
    private static let softDimensions: [FoodTag.Dimension] = [
        .cuisine, .form, .occasion, .flavour, .trait,
    ]

    /// 隨機取 `count` 道，上一輪出現過的排在後面。
    ///
    /// 先各自洗牌再串起來，而不是整包洗完再排序：後者在候選池只比 `count` 多一點時，
    /// 「排到後面」等於「永遠排在同樣的位置」，連按兩次還是同一組。
    private static func sample(_ items: [FoodItem], count: Int, avoiding previous: Set<String>) -> [FoodItem] {
        let fresh = items.filter { !previous.contains($0.id) }.shuffled()
        guard fresh.count < count else { return Array(fresh.prefix(count)) }
        let reused = items.filter { previous.contains($0.id) }.shuffled()
        return Array((fresh + reused).prefix(count))
    }
}

private extension FoodItem {
    /// 在指定的幾個維度上，這道菜符不符合選的標籤。
    /// 同維度內只要中一個就算過（聯集），每個維度都要過（交集）。
    func matches(_ filter: FilterSelection, in dimensions: [FoodTag.Dimension]) -> Bool {
        dimensions.allSatisfy { dimension in
            let wanted = filter.tags(in: dimension)
            return wanted.isEmpty || !tags.isDisjoint(with: wanted)
        }
    }
}
