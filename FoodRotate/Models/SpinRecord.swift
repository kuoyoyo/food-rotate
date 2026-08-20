import Foundation
import SwiftData

/// 一次轉盤的歷史紀錄。
///
/// 候選清單以 JSON 存成字串而非 SwiftData 關聯，因為 `FoodItem` 已經是 `Codable`，
/// 存成一欄可以讓歷史頁「重新轉同一組清單」時原樣還原。
@Model
final class SpinRecord {
    var date: Date = Date()
    /// 這一輪的條件摘要，例如「日式・清爽・宵夜」。以前存的是使用者打的那段話。
    var prompt: String = ""
    var itemsJSON: String = ""
    var winnerName: String = ""

    /// 這一輪轉的是菜色還是店家。**空字串代表舊紀錄**（S6 之前存的都沒有這一欄）。
    ///
    /// 沒有它連「這一列要不要顯示還原」都判斷不了 —— 而顯示了卻按不動，
    /// 就是一顆死按鈕。
    var sourceRawValue: String = ""

    /// 中選那一道的 `id`。**空字串代表舊紀錄。**
    ///
    /// 以前只存名字，但名字是會變的：使用者可以在轉盤上改名，
    /// 兩道菜也可能同名（自訂的跟內建的）。名字是拿來顯示的，id 才是身分（P2-4）。
    var winnerID: String = ""

    /// 已經不再寫入，但欄位要留著。
    ///
    /// 這是舊版存「用了哪個模型引擎」的地方。SwiftData 的 store 已經有這一欄，
    /// 直接從 model 上拿掉會需要一次 migration；留著空字串則什麼都不用做。
    var engineRawValue: String = ""

    init(date: Date, prompt: String, items: [FoodItem], winnerName: String) {
        self.date = date
        self.prompt = prompt
        self.itemsJSON = Self.encode(items)
        self.winnerName = winnerName
    }

    convenience init(
        date: Date, prompt: String, items: [FoodItem],
        winner: FoodItem, source: WheelSource
    ) {
        self.init(date: date, prompt: prompt, items: items, winnerName: winner.name)
        self.winnerID = winner.id
        self.sourceRawValue = source.rawValue
    }

    /// 這一輪轉的是什麼。舊紀錄沒有這一欄，**用內容推**：
    /// 店家的 id 一律是 `place-` 前綴（見 `FoodItem.isPlace`）。
    ///
    /// 這就是 SwiftData 那邊不需要 migration plan 的原因 —— 新欄位有預設值，
    /// 舊資料照樣讀得出來，缺的部分由這裡降級補上。
    var resolvedSource: WheelSource {
        if let stored = WheelSource(rawValue: sourceRawValue) { return stored }
        return items.contains(where: \.isPlace) ? .restaurants : .dishes
    }

    /// 這一筆能不能還原回轉盤。
    ///
    /// 兩個條件：
    ///
    /// 1. **必須是菜色紀錄。** 存下來的店家資料會過期（店會關、電話會換），
    ///    把三個月前的清單「還原」出來是另一種假裝知道。
    /// 2. **清單必須解得開。** 舊版存的 JSON 少了欄位會整個解不開，
    ///    那時候還原出來是一份空清單 —— 那也是一顆死按鈕。
    ///
    /// 不能做的事就不要出現在畫面上：`canRestore == false` 的那一列**不顯示還原圖示**，
    /// 而且不加任何其他視覺差別（不淡化、不加鎖）—— 淡化在這套系統裡代表
    /// 「停用」，但餐廳紀錄沒有壞也沒有失效，它本來就沒有「還原」這個概念。
    var canRestore: Bool {
        resolvedSource == .dishes && !items.isEmpty
    }

    /// 還原這一輪的候選清單。
    ///
    /// 舊版存下來的 JSON 沒有 `id` 與 `tags` 這兩個新欄位，`JSONDecoder` 會直接解不開，
    /// 所以這裡的 `try?` 不只是防禦——升級後開啟舊紀錄一定會走到它，回空陣列，
    /// 歷史頁就顯示不出可還原的清單。這是刻意接受的代價：為了幾筆舊紀錄寫一套
    /// 相容解碼，不值得。轉出的結果（`winnerName`）仍然看得到。
    var items: [FoodItem] {
        guard let data = itemsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([FoodItem].self, from: data)
        else { return [] }
        return decoded
    }

    /// 中選的那一道。**先用 id 認，認不到才降級用名字。**
    ///
    /// 名字只能拿來顯示：使用者改得掉，而且兩道同名時分不出是哪一道。
    /// 降級那條路只服務 S6 之前存的舊紀錄。
    var winner: FoodItem? {
        if !winnerID.isEmpty, let byID = items.first(where: { $0.id == winnerID }) {
            return byID
        }
        return items.first { $0.name == winnerName }
    }

    /// 歷史頁那一列左邊要畫哪一個線稿圖示。
    ///
    /// **降級到 `.neutral` 有兩種情況，都是它本來就該接住的：**
    ///
    /// 1. 舊紀錄的 JSON 解不開（見 `items`），`winner` 是 nil —— 沒有資料可以判斷類型。
    /// 2. 這一筆是店家紀錄。店家借用 `FoodItem` 但沒有吃法標籤，
    ///    `FoodIcon.icon(for:)` 本來就會回 `.neutral`（那是它存在的理由之一）。
    ///
    /// 規則放在這裡而不是 `HistoryView` 裡，理由跟 `FoodItem.icon` 一樣：
    /// **同一條規則只能有一個來源。**
    var winnerIcon: FoodIcon { winner?.icon ?? .neutral }

    private static func encode(_ items: [FoodItem]) -> String {
        guard let data = try? JSONEncoder().encode(items) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
