import Testing

@testable import FoodRotate

/// 資料檢查本身也要有東西接著。
///
/// 這支檢查的價值在於「該叫的時候要叫」，而它平常是安靜的 —— 安靜的東西壞掉了不會有人發現，
/// 所以這裡用造出來的資料逼它出聲。
///
/// 這裡**也**斷言真實的 `foods.json` 零問題。S1b 交付時那 7 道缺標籤的菜還沒補，
/// 所以當時不能這樣寫；補完之後就該把門關上，否則下一次有人加菜漏標籤，
/// 又要等到有人剛好看主控台才會發現。
@Suite("foods.json 的資料檢查")
struct FoodDataAuditTests {

    private static func food(id: String, name: String, tags: Set<FoodTag>) -> FoodItem {
        FoodItem(id: id, name: name, emoji: "🍽️", category: "測試", tags: tags, pros: [], cons: [])
    }

    // MARK: - 標籤有沒有菜（2026-08-27 補的那道防線）

    /// 造一組「三個忌口都有人掛」的健康資料，讓下面兩條只在該叫的時候叫。
    private static var wellTaggedPair: [FoodItem] {
        [
            Self.food(id: "a", name: "日式拉麵", tags: [.japanese, .noodles, .noBeef, .noSeafood]),
            Self.food(id: "b", name: "滷肉飯", tags: [.taiwanese, .rice, .noBeef, .noPork]),
        ]
    }

    @Test("一個沒有任何菜掛到的忌口標籤要被抓出來 —— 那是一條死路")
    func 零命中的忌口會被抓到() {
        // 「無海鮮」在這組資料裡沒有人掛。忌口不放寬（`FoodPicker` 第一步就 guard），
        // 所以選了它必定空轉盤，而畫面給的出口「取消忌口」救不了他。
        let items = [
            Self.food(id: "a", name: "日式拉麵", tags: [.japanese, .noodles, .noBeef]),
            Self.food(id: "b", name: "滷肉飯", tags: [.taiwanese, .rice, .noBeef, .noPork]),
        ]

        #expect(
            FoodDataAudit.libraryFindings(in: items) == [.restrictionMatchesNothing(tag: .noSeafood)]
        )
    }

    @Test("這條檢查只在整份資料庫的入口跑，逐筆的那個入口不准碰它")
    func 逐筆入口不做覆蓋率檢查() {
        // 這是分兩個入口的整個理由。同一份兩筆的資料：
        // `libraryFindings` 該叫（它問的是「這份清單完不完整」），
        // `findings` 不准叫（它問的是逐筆的問題，而兩筆本來就不會蓋滿三個忌口）。
        // 混在一起的話，所有用造出來的小資料寫的測試會全部誤報。
        let items = [Self.food(id: "a", name: "日式拉麵", tags: [.japanese, .noodles])]

        #expect(FoodDataAudit.findings(in: items).isEmpty)
        #expect(FoodDataAudit.libraryFindings(in: items).count == 3, "三個忌口都沒人掛")
    }

    @Test("軟標籤零命中不叫 —— 那是放寬機制在管的，不是缺陷")
    func 軟標籤零命中不叫() {
        // 這組資料一個「韓式」「宵夜」「偏甜」都沒有，但那些維度會被逐層放寬，
        // 使用者照樣拿得到一盤菜，畫面也會說「已放寬 X」。在這裡叫等於喊狼來了。
        #expect(FoodDataAudit.libraryFindings(in: Self.wellTaggedPair).isEmpty)
    }

    @Test("真實的 foods.json 三個忌口都有菜掛著")
    func 真實資料沒有死路() {
        // 這一條就是 2026-08-27 那個缺陷的門。「素可」在的時候它會紅。
        let findings = FoodDataAudit.libraryFindings(in: FoodLibrary.all)
            .filter { if case .restrictionMatchesNothing = $0 { true } else { false } }

        #expect(findings.isEmpty, "有忌口標籤篩不出任何東西：\(findings)")
    }

    @Test("菜系與吃法都有的資料不會被誤報")
    func 健康的資料沒有問題() {
        let items = [
            Self.food(id: "a", name: "日式拉麵", tags: [.japanese, .noodles, .noBeef]),
            Self.food(id: "b", name: "滷肉飯", tags: [.taiwanese, .rice]),
        ]
        #expect(FoodDataAudit.findings(in: items).isEmpty)
    }

    @Test("少了菜系或吃法標籤要被抓出來，因為 S2 之後那格會沒有圖")
    func 缺標籤會被抓到() {
        let items = [
            Self.food(id: "no-cuisine", name: "低卡餐盒", tags: [.lightMeal]),
            Self.food(id: "no-form", name: "美式牛排", tags: [.american]),
        ]
        let findings = FoodDataAudit.findings(in: items)

        #expect(findings.count == 2)
        #expect(findings.contains(
            .missingIconDimension(id: "no-cuisine", name: "低卡餐盒", dimension: .cuisine)
        ))
        #expect(findings.contains(
            .missingIconDimension(id: "no-form", name: "美式牛排", dimension: .form)
        ))
    }

    // MARK: - 真實資料

    @Test("內建的 50 道菜全部通過檢查")
    func 真實資料沒有缺口() {
        let findings = FoodDataAudit.findings(in: FoodLibrary.all)
        // 失敗時把報告一起印出來，不然只看到「陣列不是空的」要自己去查是哪一道。
        #expect(
            findings.isEmpty,
            "\(FoodDataAudit.consoleReport(for: findings) ?? "")"
        )
    }

    // MARK: - 豁免

    @Test("刻意沒有菜系的料理不會被一直提醒，但吃法照樣要有")
    func 豁免只擋菜系() {
        // 低卡餐盒是目前唯一的豁免案例：它不屬於任何一國菜，硬塞菜系反而會製造錯誤的篩選結果。
        let exempt = Self.food(id: "low-calorie-bento", name: "低卡餐盒", tags: [.lightMeal])
        #expect(FoodDataAudit.findings(in: [exempt]).isEmpty)

        // 但豁免不是「什麼都不用掛」—— 拿掉吃法還是要叫。
        let noForm = Self.food(id: "low-calorie-bento", name: "低卡餐盒", tags: [])
        #expect(FoodDataAudit.findings(in: [noForm]) == [
            .missingIconDimension(id: "low-calorie-bento", name: "低卡餐盒", dimension: .form)
        ])
    }

    @Test("豁免的料理後來補了菜系，要提醒把豁免拿掉")
    func 過期的豁免會被抓到() {
        // 豁免清單不會自己過期。留著一個沒有意義的豁免，
        // 下次真的有人把這道菜的菜系拔掉就不會有人知道。
        let item = Self.food(
            id: "low-calorie-bento",
            name: "低卡餐盒",
            tags: [.lightMeal, .taiwanese]
        )
        #expect(FoodDataAudit.findings(in: [item]) == [
            .staleCuisineExemption(id: "low-calorie-bento", name: "低卡餐盒")
        ])
    }

    @Test("id 撞號要被抓出來，否則抽樣去重會默默吃掉後面那道")
    func 重複的id會被抓到() {
        let items = [
            Self.food(id: "same", name: "滷肉飯", tags: [.taiwanese, .rice]),
            Self.food(id: "same", name: "雞肉飯", tags: [.taiwanese, .rice]),
        ]
        let findings = FoodDataAudit.findings(in: items)

        #expect(findings == [.duplicateID(id: "same", names: ["滷肉飯", "雞肉飯"])])
    }
}
