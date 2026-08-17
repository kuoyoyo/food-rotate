import Foundation
import Testing

@testable import FoodRotate

/// 歷史紀錄的身分與可還原性（S6 P1-4、P2-4）。
///
/// 兩件事在這裡收斂：
///
/// 1. **餐廳紀錄不還原。** 存下來的店家資料會過期（店會關、電話會換），
///    把三個月前的清單「還原」出來是另一種假裝知道。而現在那個還原按鈕
///    本來就是死的 —— 死按鈕跟靜默退回是同一種病。
/// 2. **中選的那一道用 id 認，不用名字認。** 名字會被使用者改掉，
///    同名的兩道也分不開（P2-4）。
///
/// 舊紀錄沒有這兩個新欄位，所以每一條都要能降級。
@Suite("歷史紀錄")
struct SpinRecordTests {

    private static func dish(_ id: String, _ name: String) -> FoodItem {
        FoodItem(id: id, name: name, emoji: "🍜", category: "台式", tags: [], pros: [], cons: [])
    }

    private static func place(_ name: String) -> FoodItem {
        FoodItem(
            id: "place-\(UUID().uuidString)", name: name, emoji: "🍽️",
            category: "餐廳 · 300 公尺", tags: [], pros: ["測試路 1 號"], cons: []
        )
    }

    // MARK: - 可不可以還原

    @Test("菜色紀錄可以還原")
    func 菜色紀錄可以還原() {
        let items = [Self.dish("a", "牛肉麵"), Self.dish("b", "滷肉飯")]
        let record = SpinRecord(
            date: .now, prompt: "", items: items,
            winner: items[0], source: .dishes
        )
        #expect(record.canRestore)
    }

    @Test("餐廳紀錄不可以還原 —— 存下來的店家資料會過期")
    func 餐廳紀錄不可以還原() {
        let items = [Self.place("段純貞牛肉麵"), Self.place("穆記牛肉麵")]
        let record = SpinRecord(
            date: .now, prompt: "", items: items,
            winner: items[0], source: .restaurants
        )
        #expect(record.canRestore == false)
    }

    @Test("舊紀錄沒有 source，用內容推：清單裡是店家就當成餐廳紀錄")
    func 舊紀錄用內容推出模式() {
        let dishes = SpinRecord(date: .now, prompt: "", items: [Self.dish("a", "牛肉麵")], winnerName: "牛肉麵")
        let places = SpinRecord(date: .now, prompt: "", items: [Self.place("段純貞")], winnerName: "段純貞")

        #expect(dishes.resolvedSource == .dishes)
        #expect(places.resolvedSource == .restaurants)
        #expect(dishes.canRestore)
        #expect(places.canRestore == false)
    }

    @Test("解不開的舊紀錄不可以還原 —— 還原出一份空清單就是一顆死按鈕")
    func 解不開的舊紀錄不可以還原() {
        let record = SpinRecord(date: .now, prompt: "", items: [], winnerName: "牛肉麵")
        // 舊版存的 JSON 少了欄位會整個解不開，`items` 回空陣列（見 SpinRecord.items）。
        #expect(record.items.isEmpty)
        #expect(record.canRestore == false)
    }

    // MARK: - 中選的是哪一道

    @Test("用 id 認中選的那一道，不用名字")
    func 用id認中選() {
        let items = [Self.dish("a", "牛肉麵"), Self.dish("b", "滷肉飯")]
        let record = SpinRecord(date: .now, prompt: "", items: items, winner: items[1], source: .dishes)

        #expect(record.winner?.id == "b")
    }

    @Test("兩道同名時，id 分得出來而名字分不出來")
    func 同名兩道用id分得開() {
        // 使用者把自訂的「阿婆麵線」改成跟內建的「牛肉麵」同名，這是做得到的。
        let items = [Self.dish("builtin", "牛肉麵"), Self.dish("custom-1", "牛肉麵")]
        let record = SpinRecord(date: .now, prompt: "", items: items, winner: items[1], source: .dishes)

        #expect(record.winner?.id == "custom-1", "用名字認的話會拿到第一個，那是另一道菜")
    }

    @Test("舊紀錄沒有 winnerID，降級用名字找回來")
    func 舊紀錄降級用名字() {
        let items = [Self.dish("a", "牛肉麵"), Self.dish("b", "滷肉飯")]
        let record = SpinRecord(date: .now, prompt: "", items: items, winnerName: "滷肉飯")

        #expect(record.winner?.id == "b")
    }
}
