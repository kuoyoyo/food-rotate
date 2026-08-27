import Foundation

/// 在一份料理清單裡找東西。
///
/// **放在 `Core/` 而不是留在 `FoodLibraryView` 裡**，理由跟 `FoodPicker`、`FoodIcon`
/// 一樣：「打『無牛』要不要找得到牛肉麵」是**產品規則**，不是畫面的事。
/// 留在 View 的 computed property 裡就測不到，而搜尋恰好是那種
/// 「看起來能動、但少一條路就靜靜漏掉結果」的東西 —— 漏掉的那幾道菜不會有人抗議。
///
/// 純函數、只用 Foundation，跟 `Core/` 其他檔一樣可以直接對翻 Kotlin。
enum FoodSearch {

    /// 比對菜名**與標籤**。
    ///
    /// 只比菜名的話，「無牛」「宵夜」「便宜」這種查法會全部落空 ——
    /// 而那正是使用者最想問的問題：「有什麼是不含牛的」比
    /// 「有沒有一道叫牛肉麵的」有用得多。
    ///
    /// 標籤比的是 `rawValue`，也就是**畫面上顯示的那個字**（見 `FoodTag` 檔頭：
    /// rawValue = 顯示的字 = `foods.json` 裡寫的字，三者同一份）。
    /// 所以使用者打什麼就比什麼，不需要維護一張同義詞對照表。
    ///
    /// 空字串（或只有空白）回整份清單，不是回空的 —— 使用者清掉搜尋框的意思是
    /// 「我不篩了」，不是「我要看零筆」。
    static func matches(in items: [FoodItem], query: String) -> [FoodItem] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return items }
        return items.filter { item in
            item.name.localizedCaseInsensitiveContains(keyword)
                || item.tags.contains { $0.rawValue.localizedCaseInsensitiveContains(keyword) }
        }
    }
}
