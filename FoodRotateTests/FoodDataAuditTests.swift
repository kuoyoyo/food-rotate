import Testing

@testable import FoodRotate

/// 資料檢查本身也要有東西接著。
///
/// 這支檢查的價值在於「該叫的時候要叫」，而它平常是安靜的 —— 安靜的東西壞掉了不會有人發現，
/// 所以這裡用造出來的資料逼它出聲。
///
/// 刻意**不**斷言真實的 `foods.json` 零問題：目前它有已知缺口（S1b 交付時一併回報 PM），
/// 那是內容決策，補不補、怎麼補不是這支測試該替人決定的。
@Suite("foods.json 的資料檢查")
struct FoodDataAuditTests {

    private static func food(id: String, name: String, tags: Set<FoodTag>) -> FoodItem {
        FoodItem(id: id, name: name, emoji: "🍽️", category: "測試", tags: tags, pros: [], cons: [])
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
