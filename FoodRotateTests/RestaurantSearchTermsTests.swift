import Testing

@testable import FoodRotate

/// 「去哪吃」的搜尋詞翻譯。
///
/// 這張表最大的風險不是算錯，是**被後人當成分類邏輯改**。
/// 所以測試除了驗值，也把「它只是搜尋詞」這件事寫成可執行的斷言：
/// 沒列在翻譯表裡的菜系，拿的就是標籤自己的字，沒有任何額外處理。
@Suite("去哪吃的搜尋詞")
struct RestaurantSearchTermsTests {

    @Test("沒選菜系就查一般餐廳")
    func 沒選菜系() {
        #expect(RestaurantSearchTerms.terms(for: []) == ["餐廳"])
    }

    @Test("沒列在翻譯表裡的菜系，直接用標籤的字")
    func 未翻譯的菜系用原詞() {
        // 這六個實測都夠用（日式 25 家、韓式 25、義式 20、美式 18、台式 12、墨西哥 8）。
        for tag in [FoodTag.japanese, .korean, .italian, .american, .taiwanese, .mexican] {
            #expect(RestaurantSearchTerms.terms(for: [tag]) == [tag.rawValue])
        }
    }

    @Test("歐陸刻意不翻譯")
    func 歐陸保留原詞() {
        // 替代詞實測更差（西餐廳 1 家、歐式料理 0 家）。附近歐陸的店少是事實，
        // 該做的是老實退回並說明，不是換個字假裝找到了。
        #expect(RestaurantSearchTerms.terms(for: [.european]) == ["歐陸"])
    }

    @Test("查不到的三個菜系有換過說法")
    func 需要翻譯的菜系() {
        #expect(RestaurantSearchTerms.terms(for: [.southAsian]) == ["印度料理"])
        #expect(RestaurantSearchTerms.terms(for: [.southeastAsian]) == ["泰式", "越南料理"])
        #expect(RestaurantSearchTerms.terms(for: [.chinese]) == ["中華料理"])
    }

    @Test("多選時依標籤順序展開，而且不重複")
    func 多選的順序穩定且去重() {
        // 順序要穩定，否則同樣的選擇兩次搜尋回來的店家排序會莫名其妙地不同。
        let terms = RestaurantSearchTerms.terms(for: [.korean, .japanese, .southeastAsian])
        #expect(terms == ["日式", "韓式", "泰式", "越南料理"])
        #expect(terms.count == Set(terms).count)
    }

    @Test("每一個菜系都問得出至少一個搜尋詞")
    func 十個菜系都有詞可用() {
        // 漏一個的話那個菜系會拿空字串去搜，MapKit 會回一堆不相干的東西。
        for tag in FoodTag.Dimension.cuisine.tags {
            let terms = RestaurantSearchTerms.terms(for: [tag])
            #expect(!terms.isEmpty, "\(tag.rawValue) 沒有搜尋詞")
            #expect(terms.allSatisfy { !$0.isEmpty }, "\(tag.rawValue) 有空的搜尋詞")
        }
    }

    @Test("提示文字講的是使用者選的詞，不是翻譯後的詞")
    func 提示用原本的菜系名() {
        // 使用者點的是「南亞」，提示裡冒出一個他沒點過的「印度料理」只會讓人困惑。
        #expect(RestaurantSearchTerms.displayName(for: [.southAsian]) == "南亞")
        #expect(RestaurantSearchTerms.displayName(for: [.japanese, .korean]) == "日式、韓式")
    }

    @Test("翻譯表只碰菜系，不會混進別的維度")
    func 翻譯表只收菜系() {
        // 這張表如果哪天被塞進「無牛」之類的東西，就代表有人把它當成篩選邏輯在改了。
        for tag in RestaurantSearchTerms.translations.keys {
            #expect(tag.dimension == .cuisine, "\(tag.rawValue) 不是菜系，不該出現在搜尋詞翻譯表")
        }
    }
}
