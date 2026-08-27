import Foundation
import Testing

@testable import FoodRotate

/// 標籤集合縮小時，已經存在使用者手機裡的資料要活下來。
///
/// ## 為什麼需要這一支
///
/// 2026-08-27 的稽核發現「素可」在 50 道菜裡**一道都沒有掛**，裁示是把這個 case
/// 從 `FoodTag` 移除。移除一個 `RawRepresentable` 的 case 看起來只是刪兩行，
/// 但它會穿過兩條**已經寫進使用者硬碟**的解碼路徑：
///
/// | 路徑 | 原本的失敗方式 |
/// |---|---|
/// | `CustomFoodStore` 的 `customFoodItems`（UserDefaults） | `decode` 是 `try?` → 整包回 `nil` → `customItems = []`。**使用者所有的自訂料理一起消失** |
/// | `SpinRecord.itemsJSON`（SwiftData） | `items` 是 `try?` → 回空陣列 → `canRestore` 變 false，那一列的還原圖示無聲消失 |
///
/// 兩條都不會當、不會噴、不會有任何錯誤訊息 —— 使用者只會發現東西不見了。
/// 第一條尤其嚴重：他掛「素可」的可能只有一道自訂料理，賠掉的是**全部**。
///
/// ## 所以規則是
///
/// > **不認得的標籤就丟掉那個標籤，不要丟掉那道菜。**
///
/// 這個取捨的前提要講清楚：丟標籤是有代價的（那道菜從某些篩選結果裡消失），
/// 但那正是 `FoodDataAudit` 存在的理由 —— 缺標籤有人接。而丟掉整份清單沒有人接。
///
/// ## 用「純素」而不是只用「素可」來驗
///
/// 「素可」在移除**之前**還是合法標籤，只拿它驗的話這一支在修之前就是綠的 ——
/// 一支在缺陷還在時就綠的測試證明不了任何事。所以主要的斷言用一個
/// **無論移除前後都不存在**的 rawValue（`純素`），它在寬容解碼做好之前必定紅。
/// 「素可」那一條另外寫，記錄這次實際被移除的那個值。
@Suite("標籤集合縮小時的資料相容")
struct TagMigrationTests {

    /// 直接寫 JSON 而不是編碼一個 `FoodItem`：要模擬的是**舊版寫下、新版讀到**，
    /// 用新版的型別編出來的東西不可能含有新版不認得的標籤。
    private static func itemJSON(id: String, name: String, tags: [String]) -> String {
        let list = tags.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        {"id":"\(id)","name":"\(name)","emoji":"🍜","category":"台式",\
        "tags":[\(list)],"pros":["好吃"],"cons":["貴"]}
        """
    }

    private static func decodeItem(_ json: String) throws -> FoodItem {
        try JSONDecoder().decode(FoodItem.self, from: Data(json.utf8))
    }

    // MARK: - 單筆

    @Test("不認得的標籤只丟掉那個標籤，那道菜要還在")
    func 未知標籤不會拖垮整道菜() throws {
        let item = try Self.decodeItem(
            Self.itemJSON(id: "a", name: "陽春麵", tags: ["台式", "純素", "麵食"])
        )

        #expect(item.name == "陽春麵")
        #expect(item.tags == [.taiwanese, .noodles], "認得的兩個要留著，不認得的那個丟掉就好")
    }

    @Test("整道菜的標籤都不認得時，回一個沒有標籤的菜，不是解碼失敗")
    func 全部標籤都不認得也不能整筆丟掉() throws {
        let item = try Self.decodeItem(
            Self.itemJSON(id: "b", name: "神秘料理", tags: ["純素", "生酮"])
        )

        #expect(item.name == "神秘料理")
        #expect(item.tags.isEmpty)
        // 沒有吃法標籤的菜由 `FoodIcon.neutral` 接住 —— 那是它存在的理由之一。
        #expect(item.icon == .neutral)
    }

    @Test("這次移除的「素可」走的就是同一條路")
    func 素可移除後照樣解得開() throws {
        // 這一條在移除之前是綠的（那時「素可」還合法），移除之後才真正在驗東西。
        // 留著它是為了讓下一個人看得到「這次拿掉的是哪一個值」。
        let item = try Self.decodeItem(
            Self.itemJSON(id: "c", name: "印度香米飯", tags: ["南亞", "飯食", "素可"])
        )

        #expect(item.tags == [.southAsian, .rice])
        #expect(FoodTag(rawValue: "素可") == nil, "「素可」已於 2026-08-27 移除")
    }

    // MARK: - 兩條真的會踩到的儲存路徑

    @Test("一道自訂料理帶著未知標籤，不能害其他自訂料理一起消失")
    @MainActor
    func 自訂料理不會整份不見() throws {
        let defaults = UserDefaults(suiteName: "test.migration.\(UUID().uuidString)")!
        // 舊版寫下來的三筆，中間那筆掛著已經被移除的標籤。
        let stored = """
        [\(Self.itemJSON(id: "custom-1", name: "阿婆麵線", tags: ["台式", "麵食"])),\
        \(Self.itemJSON(id: "custom-2", name: "自家滷菜", tags: ["素可", "輕食"])),\
        \(Self.itemJSON(id: "custom-3", name: "公司樓下自助餐", tags: ["台式", "飯食"]))]
        """
        defaults.set(Data(stored.utf8), forKey: "customFoodItems")

        let store = CustomFoodStore(defaults: defaults)

        #expect(store.customItems.count == 3, "三筆全部要在 —— 以前這裡會是 0")
        #expect(store.customItems.map(\.name) == ["阿婆麵線", "自家滷菜", "公司樓下自助餐"])
        #expect(store.customItems[1].tags == [.lightMeal], "被移除的標籤丟掉，「輕食」要留著")
    }

    @Test("舊的歷史紀錄帶著未知標籤，還原按鈕不能無聲消失")
    func 歷史紀錄還原得了() {
        // 同樣用「純素」而不是「素可」：這一支也必須在寬容解碼做好之前是紅的。
        let json = """
        [\(Self.itemJSON(id: "d", name: "水餃", tags: ["中式", "純素"])),\
        \(Self.itemJSON(id: "e", name: "陽春麵", tags: ["台式", "麵食"]))]
        """
        let record = SpinRecord(
            date: .now, prompt: "素可", items: [],
            winner: FoodItem(
                id: "d", name: "水餃", emoji: "🥟", category: "中式",
                tags: [], pros: [], cons: []
            ),
            source: .dishes
        )
        record.itemsJSON = json

        #expect(record.items.count == 2)
        #expect(record.canRestore, "解得開就還原得了 —— 少一個標籤不是解不開")
        #expect(record.winner?.name == "水餃")
    }
}
