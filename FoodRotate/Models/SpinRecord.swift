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

    var winner: FoodItem? {
        items.first { $0.name == winnerName }
    }

    private static func encode(_ items: [FoodItem]) -> String {
        guard let data = try? JSONEncoder().encode(items) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
