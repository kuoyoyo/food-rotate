import Foundation
import Testing

@testable import FoodRotate

/// 自訂料理的名字只能有一個真相來源（S6 P2-3）。
///
/// 以前有兩個：轉盤上改名寫進 `renamedNames`，但「我的清單」直接列 `customItems`，
/// **同一道菜在兩個畫面顯示不同名字**。
///
/// 更糟的是編輯後儲存那條路徑：`FoodEditorView.save` 會先 `rename(id:to:)` 再 `update(item)`，
/// 而呼叫 `rename` 的當下 store 裡還是舊名，於是「新名 ≠ 舊名」成立，
/// **反而留下一筆指向新名的覆寫** —— 清掉覆寫的動作自己製造了一筆覆寫。
///
/// 規則定成：**`renamedNames` 只服務改不動的內建料理；自訂料理的名字就在 `customItems` 裡。**
@Suite("自訂料理的改名", .serialized)
@MainActor
struct CustomFoodStoreRenameTests {

    /// 每一支測試用自己的 UserDefaults 網域，不碰使用者的偏好設定。
    private static func freshStore(_ function: String = #function) -> CustomFoodStore {
        let name = "test.rename.\(function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return CustomFoodStore(defaults: defaults)
    }

    private static func newCustomItem(in store: CustomFoodStore, name: String) -> FoodItem {
        store.add(FoodItem(
            id: "", name: name, emoji: "🍜", category: "自訂",
            tags: [], pros: [], cons: []
        ))
        return store.customItems.last!
    }

    @Test("在轉盤上改自訂料理的名字，「我的清單」要看到同一個名字")
    func 兩個畫面看到同一個名字() {
        let store = Self.freshStore()
        let item = Self.newCustomItem(in: store, name: "阿婆麵線")

        store.rename(id: item.id, to: "巷口麵線")

        let inMyList = store.customItems.first { $0.id == item.id }?.name
        let onWheel = store.pool.first { $0.id == item.id }?.name

        #expect(inMyList == "巷口麵線")
        #expect(onWheel == "巷口麵線")
        #expect(inMyList == onWheel, "同一道菜在兩個畫面必須是同一個名字")
    }

    @Test("自訂料理改名之後不留覆寫紀錄 —— 名字就存在料理本身")
    func 自訂料理不留覆寫() {
        let store = Self.freshStore()
        let item = Self.newCustomItem(in: store, name: "阿婆麵線")

        store.rename(id: item.id, to: "巷口麵線")

        #expect(store.renamedNames[item.id] == nil, "自訂料理的名字不該有第二份")
        #expect(store.customizationCount == 1, "只算一件改動（那道自訂料理），不是兩件")
    }

    @Test("編輯後儲存不會留下一筆指向新名的覆寫")
    func 編輯儲存不留孤兒覆寫() {
        let store = Self.freshStore()
        let item = Self.newCustomItem(in: store, name: "阿婆麵線")

        // `FoodEditorView.save` 的順序：先清覆寫、再寫回整筆。
        store.rename(id: item.id, to: "巷口麵線")
        var edited = item
        edited.name = "巷口麵線"
        store.update(edited)

        #expect(store.renamedNames.isEmpty)
        #expect(store.customItems.first?.name == "巷口麵線")
        #expect(store.pool.first { $0.id == item.id }?.name == "巷口麵線")
    }

    @Test("內建料理照舊走覆寫 —— bundle 裡的資料改不動，只能疊一層")
    func 內建料理仍然走覆寫() {
        let store = Self.freshStore()
        let builtIn = FoodLibrary.all[0]

        store.rename(id: builtIn.id, to: "我家的\(builtIn.name)")

        #expect(store.renamedNames[builtIn.id] == "我家的\(builtIn.name)")
        #expect(store.pool.first { $0.id == builtIn.id }?.name == "我家的\(builtIn.name)")
    }

    @Test("改回原名就把改動清掉，不要愈數愈多")
    func 改回原名清掉改動() {
        let store = Self.freshStore()
        let builtIn = FoodLibrary.all[0]

        store.rename(id: builtIn.id, to: "別的名字")
        store.rename(id: builtIn.id, to: builtIn.name)

        #expect(store.renamedNames[builtIn.id] == nil)
    }

    @Test("舊資料留下的自訂料理覆寫不得蓋過料理本身的名字")
    func 舊覆寫不得蓋過自訂料理() {
        let store = Self.freshStore()
        let item = Self.newCustomItem(in: store, name: "阿婆麵線")

        // 模擬 S6 之前留下來的孤兒覆寫。
        store.rename(id: item.id, to: "舊覆寫的名字")
        var edited = item
        edited.name = "現在的名字"
        store.update(edited)

        #expect(
            store.pool.first { $0.id == item.id }?.name == "現在的名字",
            "自訂料理的名字以料理本身為準"
        )
    }

    @Test("改過名的內建料理被排除後，排除清單要用他自己取的名字")
    func 排除清單也要套改名() {
        let store = Self.freshStore()
        let builtIn = FoodLibrary.all[0]

        store.rename(id: builtIn.id, to: "阿婆\(builtIn.name)")
        store.exclude(builtIn)

        // 以前只有 `pool` 套改名，`excludedBuiltIns` 沒套 —— 於是使用者在轉盤上
        // 取的名字到了「設定 → 我的清單 → 以後都不要的」就變回原名，
        // 他得先認出那是同一道菜才還原得了。
        #expect(store.excludedBuiltIns.map(\.name) == ["阿婆\(builtIn.name)"])
    }
}

/// 重啟之後改動還在（S6 P3-1 的「UserDefaults 重啟一致」）。
///
/// 這一組刻意**建第二個 store 讀同一個網域** —— 那就是「重新開 App」的等價物。
/// 前面那些測試只驗了記憶體裡的狀態，但使用者感受到的是「關掉再開還在不在」。
@Suite("改動要活過重啟", .serialized)
@MainActor
struct CustomFoodStorePersistenceTests {

    private static func suite() -> UserDefaults {
        UserDefaults(suiteName: "test.persist.\(UUID().uuidString)")!
    }

    @Test("自訂料理、改名、排除三種改動都活過重啟")
    func 三種改動都存得住() {
        let defaults = Self.suite()
        let builtIn = FoodLibrary.all[0]

        do {
            let store = CustomFoodStore(defaults: defaults)
            store.add(FoodItem(
                id: "", name: "阿婆麵線", emoji: "🍜", category: "自訂",
                tags: [], pros: [], cons: []
            ))
            store.rename(id: store.customItems[0].id, to: "巷口麵線")
            store.rename(id: builtIn.id, to: "我家的\(builtIn.name)")
            store.exclude(FoodLibrary.all[1])
        }

        // 重新開 App。
        let reopened = CustomFoodStore(defaults: defaults)

        #expect(reopened.customItems.map(\.name) == ["巷口麵線"], "自訂料理的新名字要存得住")
        #expect(reopened.renamedNames[builtIn.id] == "我家的\(builtIn.name)")
        #expect(reopened.excludedIDs.contains(FoodLibrary.all[1].id))
        #expect(reopened.pool.contains { $0.name == "巷口麵線" })
    }

    @Test("還原成預設之後，重啟也回不來")
    func 還原成預設之後真的清掉了() {
        let defaults = Self.suite()

        do {
            let store = CustomFoodStore(defaults: defaults)
            store.add(FoodItem(
                id: "", name: "阿婆麵線", emoji: "🍜", category: "自訂",
                tags: [], pros: [], cons: []
            ))
            store.resetAll()
        }

        let reopened = CustomFoodStore(defaults: defaults)

        #expect(reopened.customItems.isEmpty)
        #expect(reopened.customizationCount == 0)
    }
}
