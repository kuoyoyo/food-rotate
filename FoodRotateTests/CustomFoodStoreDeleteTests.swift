import Foundation
import Testing

@testable import FoodRotate

/// 一次刪好幾道時的索引錯位（QC 2026-08-19 的 E）。
///
/// `MyListView` 的 `.onDelete` 原本是這樣寫的：
///
/// ```swift
/// for index in offsets { store.exclude(store.customItems[index]) }
/// ```
///
/// `exclude` **當場**就把那一筆從 `customItems` 拿掉，所以第二個 index
/// 指到的已經不是使用者選的那一筆了 —— 刪掉的是別人。
/// 選到最後一個的話更直接：`customItems[index]` 越界，當場 trap。
///
/// 現況打不到（那一頁沒有 `EditButton`，左滑一次只給一個 index），
/// 但這跟 `FoodEditorView` 的 `ForEach(points.indices)` 是同一類東西：
/// **現在剛好安全，加一顆按鈕就會出事。**
///
/// 所以刪除的做法收進 `CustomFoodStore` 自己身上 —— 那裡才知道
/// 「刪一筆會動到這個陣列」，而且收進來之後這件事測得到。
@Suite("一次刪好幾道", .serialized)
@MainActor
struct CustomFoodStoreDeleteTests {

    /// 每一支測試用自己的 UserDefaults 網域，不碰使用者的偏好設定。
    private static func freshStore(_ function: String = #function) -> CustomFoodStore {
        let name = "test.delete.\(function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return CustomFoodStore(defaults: defaults)
    }

    private static func add(_ name: String, to store: CustomFoodStore) {
        store.add(FoodItem(
            id: "", name: name, emoji: "🍜", category: "自訂",
            tags: [], pros: [], cons: []
        ))
    }

    @Test("刪掉的必須是使用者選的那幾道，不是刪完位移之後剛好站在那個位置的")
    func 多選刪除不得錯位() {
        let store = Self.freshStore()
        Self.add("阿婆麵線", to: store)
        Self.add("巷口滷肉飯", to: store)
        Self.add("公司樓下自助餐", to: store)

        // 選第 0 與第 1 筆。
        //
        // **刻意不選 [0, 2]。** 那一組在舊寫法下會直接越界 trap，
        // 而 trap 會把整個測試行程帶走 —— 紅得看不出是哪裡壞了。
        // [0, 1] 打到的是同一個缺陷的另一面：不崩潰，但刪錯人。
        store.exclude(atOffsets: IndexSet([0, 1]))

        #expect(
            store.customItems.map(\.name) == ["公司樓下自助餐"],
            "使用者選的是前兩筆，剩下的應該是第三筆"
        )
    }

    @Test("刪最後一筆不得越界")
    func 刪到最後一筆不得越界() {
        let store = Self.freshStore()
        Self.add("阿婆麵線", to: store)
        Self.add("巷口滷肉飯", to: store)

        store.exclude(atOffsets: IndexSet([1]))

        #expect(store.customItems.map(\.name) == ["阿婆麵線"])
    }

    @Test("一次刪光")
    func 一次刪光() {
        let store = Self.freshStore()
        Self.add("阿婆麵線", to: store)
        Self.add("巷口滷肉飯", to: store)
        Self.add("公司樓下自助餐", to: store)

        store.exclude(atOffsets: IndexSet(0..<3))

        #expect(store.customItems.isEmpty)
    }
}
