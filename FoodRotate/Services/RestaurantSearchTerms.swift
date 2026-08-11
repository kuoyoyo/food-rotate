import Foundation

/// 「去哪吃」模式下，菜系標籤要拿哪些字去搜店名。
///
/// ## 這張表是**搜尋詞翻譯**，不是分類邏輯
///
/// 這件事必須講清楚，因為它長得很像分類：MapKit **沒有菜系欄位**。
/// `MKLocalSearch` 做的是拿字去比對店名與 POI 資料，比到什麼算什麼。
/// 所以「選了日式就一定是日本料理店」這件事我們**做不到**，也不該表現得像做得到
/// （跟營業時間同一類問題：地圖給不出來的東西，不假裝知道）。
///
/// 這裡唯一在做的事，是把使用者選的標籤換成「MapKit 比較找得到的說法」。
/// 換完還是文字比對，只是比得到東西的機率高一點。
///
/// **不要**拿這些字回頭去過濾 MapKit 回傳的結果 —— 店名裡沒有菜系資訊，
/// 濾不出真相，只會製造另一種假象（這正是拿掉 `DietaryFilter` 的理由）。
enum RestaurantSearchTerms {

    /// 沒有選菜系、或全部都找不到時用的字。
    static let generic = "餐廳"

    /// 需要換說法的菜系。**沒列在這裡的就直接用標籤本身的字。**
    ///
    /// 每一條都是 2026-08-12 拿台北車站周邊 5 公里實測出來的，不是憑感覺填的
    /// （測法與完整結果見 `Coder/工程回覆-去哪吃搜尋詞-給PM.md`）：
    ///
    /// | 菜系 | 原詞的結果 | 換成 | 換後 |
    /// |---|---|---|---|
    /// | 南亞 | 3 家，**而且全是東南亞的店** | 印度料理 | 20 家 |
    /// | 東南亞 | 4 家，多是食材行與冰店不是餐廳 | 泰式＋越南料理 | 41 家 |
    /// | 中式 | 6–12 家 | 中華料理 | 25 家 |
    ///
    /// 沒有換的幾個也都實測過：台式 12、日式 25、韓式 25、義式 20、美式 18、墨西哥 8，
    /// 原詞就夠用。**歐陸刻意不換** —— 它的原詞只找到 2–4 家沒錯，但替代詞更差
    /// （西餐廳 1 家、歐式料理 0 家、法式料理 1 家）。附近歐陸的店本來就少，
    /// 那是事實不是 bug，該做的是老實說「找不到就退回一般餐廳」，不是換個字假裝找到了。
    static let translations: [FoodTag: [String]] = [
        .southAsian: ["印度料理"],
        .southeastAsian: ["泰式", "越南料理"],
        .chinese: ["中華料理"],
    ]

    /// 這一輪要搜哪些字。空集合代表沒選菜系，回一般餐廳。
    ///
    /// 依 `FoodTag.allCases` 的順序展開，同一組選擇每次產生的順序都一樣 ——
    /// 否則兩次搜尋回來的店家順序會莫名其妙地不同。
    static func terms(for cuisines: Set<FoodTag>) -> [String] {
        guard !cuisines.isEmpty else { return [generic] }

        var result: [String] = []
        var seen = Set<String>()
        for tag in FoodTag.allCases where cuisines.contains(tag) {
            for term in translations[tag] ?? [tag.rawValue] where seen.insert(term).inserted {
                result.append(term)
            }
        }
        return result.isEmpty ? [generic] : result
    }

    /// 提示文字要怎麼稱呼使用者選的東西。
    ///
    /// 用標籤原本的字（「歐陸」）而不是翻譯後的字（「西餐廳」）：
    /// 使用者選的是前者，提示裡出現一個他沒點過的詞只會讓人困惑。
    static func displayName(for cuisines: Set<FoodTag>) -> String {
        FoodTag.allCases
            .filter { cuisines.contains($0) }
            .map(\.rawValue)
            .joined(separator: "、")
    }
}
