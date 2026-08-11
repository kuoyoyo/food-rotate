import Testing

@testable import FoodRotate

/// 圖示的對應規則。
///
/// 前提先講清楚，因為所有斷言都建立在它上面：**圖示不負責辨識「是哪一道菜」。**
/// 身分歸兩行全名，圖示只表達類型。所以「一盤裡出現兩個麵食圖示」不是 bug，
/// 那正是設計要的 —— 舊的 emoji 之所以不能用，就是因為它假裝在做身分。
@Suite("圖示對應")
struct FoodIconTests {

    private static func food(_ name: String, _ tags: Set<FoodTag>, id: String = "test") -> FoodItem {
        FoodItem(id: id, name: name, emoji: "🍽️", category: "測試", tags: tags, pros: [], cons: [])
    }

    // MARK: - 優先序

    @Test("一道菜有多個吃法時取優先序第一個命中的")
    func 多重吃法取優先序() {
        #expect(FoodIcon.icon(for: Self.food("牛肉麵", [.noodles, .soupDish])) == .noodles)
        #expect(FoodIcon.icon(for: Self.food("麻辣火鍋", [.hotpot, .soupDish])) == .hotpot)
        #expect(FoodIcon.icon(for: Self.food("滷肉飯", [.rice, .snack])) == .rice)
        #expect(FoodIcon.icon(for: Self.food("法式燉牛肉", [.meatDish, .soupDish])) == .meatDish)
        // 夏威夷生魚飯是輕食＋飯食 —— 它就是一碗飯。
        #expect(FoodIcon.icon(for: Self.food("夏威夷生魚飯", [.lightMeal, .rice])) == .rice)
    }

    @Test("湯的排在很後面，因為它講的是狀態不是主體")
    func 湯的只在沒有別的吃法時才代表這道菜() {
        // 只有「湯的」的時候它才出頭。
        #expect(FoodIcon.icon(for: Self.food("玉米濃湯", [.soupDish])) == .soupDish)
        // 有主體的時候一律讓位。
        for form in [FoodTag.hotpot, .meatDish, .noodles, .rice, .bread, .snack] {
            let icon = FoodIcon.icon(for: Self.food("測試", [form, .soupDish]))
            #expect(icon != .soupDish, "\(form.rawValue) + 湯的 取到了湯的")
        }
    }

    @Test("優先序涵蓋全部八個吃法，沒有漏掉也沒有重複")
    func 優先序涵蓋所有吃法() {
        // 漏一個的話那個吃法的菜會靜靜地落到中性圖示，畫面上看不出是漏了還是設計如此。
        #expect(Set(FoodIcon.formPriority) == Set(FoodTag.Dimension.form.tags))
        #expect(FoodIcon.formPriority.count == Set(FoodIcon.formPriority).count)
    }

    // MARK: - fallback

    @Test("沒有吃法標籤就用中性圖示")
    func 沒有吃法用中性圖示() {
        // 使用者自訂但什麼都沒選 —— 新增表單不強制選吃法，這是刻意的（規格八-5）。
        #expect(FoodIcon.icon(for: Self.food("阿嬤煮的", [], id: "custom-1")) == .neutral)
        // 只有菜系沒有吃法。
        #expect(FoodIcon.icon(for: Self.food("低卡餐盒", [.taiwanese])) == .neutral)
    }

    @Test("店家也有圖示可用")
    func 店家不會沒有圖() {
        // 「去哪吃」借用 FoodItem 裝店家：沒有任何標籤，category 放的是距離文字。
        let place = FoodItem(
            id: "place-abc", name: "巷口牛肉麵", emoji: "📍",
            category: "120 公尺", tags: [], pros: ["台北市…"], cons: []
        )
        #expect(place.isPlace)
        #expect(FoodIcon.icon(for: place) == .neutral)
    }

    @Test("內建的 50 道每一道都推得出圖示")
    func 內建資料全部有圖() {
        for item in FoodLibrary.all {
            #expect(FoodIcon.icon(for: item) != .neutral, "「\(item.name)」落到了中性圖示")
        }
    }

    // MARK: - 資產命名

    @Test("九個圖示資產全部在 asset catalog 裡")
    func 資產全部到齊() {
        // 缺一張不會當掉，只會讓轉盤上那一格空著 —— 安靜的壞。
        // 匯入時 slug 對錯（form-light → icon-form-light-meal、
        // form-unknown → icon-form-neutral 這兩個特別容易照檔名貼錯）也會被這條擋下來。
        let report = FoodIconAssets.missingReport()
        #expect(report == nil, "\(report ?? "")")
    }

    @Test("每個圖示的資產名都不一樣，而且帶維度前綴")
    func 資產命名規則() {
        let names = FoodIcon.allCases.map(\.assetName)
        #expect(Set(names).count == names.count, "資產名撞號：\(names)")
        // 帶前綴是為了跟之後的菜系角標（icon-cuisine-*）分得開。
        #expect(names.allSatisfy { $0.hasPrefix("icon-form-") })
        #expect(names.allSatisfy { $0 == $0.lowercased() })
        #expect(FoodIcon.neutral.assetName == "icon-form-neutral")
    }
}
