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
