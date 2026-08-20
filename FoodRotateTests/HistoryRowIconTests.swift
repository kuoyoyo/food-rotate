import Foundation
import Testing

@testable import FoodRotate

/// 歷史頁那一列左邊畫哪一個線稿圖示（kuoyo 2026-08-21）。
///
/// 歷史頁原本畫的是 emoji。S5-B 當時的理由是「那顆 emoji 可能是使用者自己挑的」——
/// 這對「我的清單」成立，對歷史頁不成立：歷史頁那顆來自 `record.winner`，
/// 而中選的通常是內建料理，emoji 是 `foods.json` 裡我們自己寫的。
/// 規則沒變（不能換掉使用者的內容），套法變了（依據是「這是誰的東西」）。
///
/// ## 這一組是規格測試，不是先紅後綠
///
/// 要老實講：`winnerIcon` 是這次新加的東西，它沒有「修之前的錯誤行為」可以先紅。
/// 真正被回報的缺陷（畫面上是 emoji 不是線稿）在 View 裡，單元測試碰不到 ——
/// 那一段是靠實機截圖驗的。
///
/// 這裡釘的是**降級路徑**：`winner` 是 nil、或那一筆是店家時要畫什麼。
/// 那兩條在畫面上都只會表現成「圖示怪怪的」，不會報錯，最容易靜靜地壞掉。
@Suite("歷史列的線稿圖示")
struct HistoryRowIconTests {

    private static func dish(_ id: String, _ name: String, tags: Set<FoodTag>) -> FoodItem {
        FoodItem(
            id: id, name: name, emoji: "🍜", category: "台式",
            tags: tags, pros: [], cons: []
        )
    }

    private static func place(_ name: String) -> FoodItem {
        FoodItem(
            id: "place-\(UUID().uuidString)", name: name, emoji: "🍽️",
            category: "餐廳 · 300 公尺", tags: [], pros: ["測試路 1 號"], cons: []
        )
    }

    @Test("中選的是麵食就畫麵食 —— 跟轉盤與候選清單同一套規則")
    func 依中選那一道的吃法決定() {
        let items = [
            Self.dish("beef-noodle", "牛肉麵", tags: [.taiwanese, .noodles]),
            Self.dish("lu-rou-fan", "滷肉飯", tags: [.taiwanese, .rice]),
        ]
        let record = SpinRecord(
            date: .now, prompt: "台式", items: items,
            winner: items[0], source: .dishes
        )

        #expect(record.winnerIcon == .noodles)
        #expect(record.winnerIcon == items[0].icon, "不能自己判一次，要跟 FoodItem.icon 同一個來源")
    }

    @Test("店家紀錄降級成中性餐具 —— 店沒有吃法標籤")
    func 店家降級成中性() {
        let items = [Self.place("段純貞牛肉麵"), Self.place("穆記牛肉麵")]
        let record = SpinRecord(
            date: .now, prompt: "", items: items,
            winner: items[0], source: .restaurants
        )

        #expect(record.winnerIcon == .neutral)
    }

    @Test("舊紀錄解不開時降級成中性，不是空白也不是崩潰")
    func 舊紀錄降級成中性() {
        let record = SpinRecord(
            date: .now, prompt: "台式", items: [], winnerName: "牛肉麵"
        )
        // 舊版存的 JSON 少欄位，`items` 解不開就是空的，`winner` 因此是 nil。
        record.itemsJSON = "{ 這不是合法的 JSON }"

        #expect(record.winner == nil, "前提：這一筆的清單解不開")
        #expect(record.winnerIcon == .neutral, "沒有資料可以判斷類型時要有東西可畫")
    }

    @Test("自訂料理沒選吃法時也是中性，不會沒有圖")
    func 沒有吃法標籤也有圖可畫() {
        let items = [Self.dish("custom-x", "阿婆麵線", tags: [])]
        let record = SpinRecord(
            date: .now, prompt: "", items: items,
            winner: items[0], source: .dishes
        )

        #expect(record.winnerIcon == .neutral)
    }
}
