import Testing

@testable import FoodRotate

/// 轉盤文字排版。
///
/// 這支存在的理由是 P0：舊做法超過 5 字就砍掉補省略號，「西班牙海鮮燉飯」變成
/// 「西班牙海…」，轉盤上根本看不出那是什麼。**零截斷**是 S2 的驗收標準，
/// 而截斷是那種改版時很容易悄悄長回來的東西。
@Suite("轉盤的兩行排版")
struct WheelLabelTests {

    @Test("四個字以內排一行")
    func 短名一行() {
        #expect(WheelLabel.lines(for: "披薩") == ["披薩"])
        #expect(WheelLabel.lines(for: "牛肉麵") == ["牛肉麵"])
        #expect(WheelLabel.lines(for: "日式拉麵") == ["日式拉麵"])
    }

    @Test("五個字以上排兩行，前行取一半（奇數時前行多一個）")
    func 長名兩行() {
        #expect(WheelLabel.lines(for: "韓式石鍋拌飯") == ["韓式石", "鍋拌飯"])
        #expect(WheelLabel.lines(for: "西班牙海鮮燉飯") == ["西班牙海", "鮮燉飯"])
        #expect(WheelLabel.lines(for: "韓式泡菜豆腐鍋") == ["韓式泡菜", "豆腐鍋"])
        #expect(WheelLabel.lines(for: "夏威夷生魚飯") == ["夏威夷", "生魚飯"])
    }

    @Test("斷行永遠不吃掉任何一個字")
    func 零截斷() {
        // 這條比上面幾條重要：上面驗的是「斷在哪」，這條驗的是「有沒有掉字」。
        // 內建 50 道全部走一遍，加上兩道最長的當哨兵。
        let names = FoodLibrary.all.map(\.name) + ["西班牙海鮮燉飯", "韓式泡菜豆腐鍋"]
        for name in names {
            let lines = WheelLabel.lines(for: name)
            #expect(lines.joined() == name, "「\(name)」被斷成 \(lines)，跟原字不一樣")
            #expect(lines.count <= 2, "「\(name)」排成了 \(lines.count) 行")
        }
    }

    @Test("最長的菜名在最擠的格數下仍然放得下")
    func 十二格放得下最長菜名() {
        // 資料庫最長 7 字，兩行容量 8 字。這條是算數上的保證，
        // 實際渲染的證明在 Design/設計規格-Theme-v1.html 那張 12 格滿載圖。
        let longest = FoodLibrary.all.map(\.name).max(by: { $0.count < $1.count })!
        #expect(longest.count <= 8, "資料庫出現 \(longest.count) 字的菜名「\(longest)」，超過兩行容量")

        let lines = WheelLabel.lines(for: longest)
        #expect(lines.allSatisfy { $0.count <= 4 }, "\(lines) 有某一行超過 4 字")
    }

    @Test("每個格數都有尺寸規格，格數越多字越小")
    func 尺寸規格單調遞減() {
        let sizes = WheelCapacity.allowedSlots.map { WheelLabel.metrics(forSlotCount: $0).fontSize }
        #expect(sizes == sizes.sorted(by: >), "字級應該隨格數增加而變小，實際是 \(sizes)")

        // 規格第七節的實際值。
        #expect(WheelLabel.metrics(forSlotCount: 4).fontSize == 17)
        #expect(WheelLabel.metrics(forSlotCount: 12).fontSize == 11)
        #expect(WheelLabel.metrics(forSlotCount: 12).iconSize == 17)
    }

    @Test("抽不滿格時取比較寬鬆的那組尺寸")
    func 表外格數有退路() {
        // 轉盤畫幾格是看抽到幾道菜，條件太嚴時可能只有 3 道。
        #expect(WheelLabel.metrics(forSlotCount: 3) == WheelLabel.metrics(forSlotCount: 4))
        #expect(WheelLabel.metrics(forSlotCount: 5) == WheelLabel.metrics(forSlotCount: 6))
        #expect(WheelLabel.metrics(forSlotCount: 7) == WheelLabel.metrics(forSlotCount: 8))
        #expect(WheelLabel.metrics(forSlotCount: 99) == WheelLabel.metrics(forSlotCount: 12))
    }
}
