import Testing

@testable import FoodRotate

/// 「內建料理」那一頁的搜尋（2026-08-27 加的那一頁）。
///
/// 這一組刻意**大部分跑真實的 `FoodLibrary.all`**，而不是造假資料。
/// 理由：搜尋要驗的不只是「filter 寫對了嗎」，而是「使用者實際會打的字，
/// 在我們實際出貨的 50 道菜上找不找得到東西」。後者用兩筆假資料驗不到。
@Suite("內建料理的搜尋")
struct FoodSearchTests {

    private static func names(_ query: String) -> [String] {
        FoodSearch.matches(in: FoodLibrary.all, query: query).map(\.name)
    }

    @Test("空的搜尋回整份清單，不是回零筆")
    func 空字串不篩() {
        #expect(FoodSearch.matches(in: FoodLibrary.all, query: "").count == FoodLibrary.all.count)
        // 使用者把字刪光、或只打了空白，意思是「我不篩了」。
        #expect(FoodSearch.matches(in: FoodLibrary.all, query: "   ").count == FoodLibrary.all.count)
    }

    @Test("打菜名的一部分就找得到")
    func 菜名部分比對() {
        #expect(Self.names("牛肉麵") == ["牛肉麵"])
        // 部分字串：「便當」應該同時找到排骨便當與雞腿便當。
        let bentos = Self.names("便當")
        #expect(bentos.count >= 2)
        #expect(bentos.allSatisfy { $0.contains("便當") })
    }

    @Test("打標籤也要找得到 —— 這是這個搜尋存在的主要理由")
    func 標籤比對() {
        // 「有什麼是不含牛的」比「有沒有一道叫牛肉麵的」有用得多。
        let noBeef = FoodSearch.matches(in: FoodLibrary.all, query: "無牛")
        #expect(noBeef.count == 32, "無牛在 50 道裡有 32 道")
        #expect(noBeef.allSatisfy { $0.tags.contains(.noBeef) })

        // 牛肉麵沒有「無牛」標籤，不能因為名字裡有「牛」就被撈進來。
        #expect(!noBeef.contains { $0.name == "牛肉麵" })
    }

    @Test("菜名與標籤是聯集，不是二選一")
    func 兩邊都比() {
        // 「日式」是標籤：7 道日式料理都要在。
        let japanese = FoodSearch.matches(in: FoodLibrary.all, query: "日式")
        #expect(japanese.count == 7)
        // 而「台式炒飯」的名字裡有「台式」，它同時也掛著台式標籤 —— 兩條路都通，
        // 但結果只能出現一次，不能因為兩邊都中就重複。
        let taiwanese = Self.names("台式")
        #expect(taiwanese.count == Set(taiwanese).count, "同一道菜不能因為名字與標籤都中而出現兩次")
    }

    @Test("找不到就是空的，不要退而求其次給一份看起來像結果的東西")
    func 找不到回空() {
        // 這條擋的是「找不到就回全部」那種好意 —— 那會讓使用者以為這 50 道
        // 都符合他打的字。空結果由畫面老實說明（`FoodLibraryView.noMatch`）。
        #expect(FoodSearch.matches(in: FoodLibrary.all, query: "佛跳牆").isEmpty)
    }

    @Test("英文大小寫不敏感")
    func 大小寫不敏感() {
        let items = [
            FoodItem(id: "a", name: "Pizza", emoji: "🍕", category: "義式",
                     tags: [.italian], pros: [], cons: []),
        ]
        #expect(FoodSearch.matches(in: items, query: "pizza").count == 1)
        #expect(FoodSearch.matches(in: items, query: "PIZZA").count == 1)
    }

    @Test("已經移除的「素可」找不到任何東西")
    func 素可已經不是標籤了() {
        // 它現在只是一個普通字串，沒有菜名或標籤含有它。
        #expect(FoodSearch.matches(in: FoodLibrary.all, query: "素可").isEmpty)
    }
}
