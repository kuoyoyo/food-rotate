import Foundation

/// 一道候選料理。
///
/// 以前這個型別要同時服侍兩個語言模型（Apple 裝置模型的 `@Generable` schema、
/// 自架模型的 prompt 內 JSON 說明），欄位上掛滿了 `@Guide` 描述在跟模型講道理。
/// 現在資料是人寫的、存在 `foods.json` 裡，這些都不需要了 —— 純資料型別，
/// 也因此沒有任何 Apple 專屬 API，移植 Android 時可以逐行對翻。
struct FoodItem: Codable, Hashable, Sendable, Identifiable {
    /// 穩定識別碼，例如 `"beef-noodle-soup"`。
    ///
    /// 不能用 `name` 當識別：使用者可以改名，改完就對不回資料庫那一道，
    /// 「以後都不要出現」與「改名覆寫」兩個功能都會失效。
    /// 自訂項目用 `"custom-"` 前綴，附近餐廳用 `"place-"` 前綴，看前綴就知道來源。
    var id: String

    var name: String

    /// 代表這道菜主體食材或外觀的單一 emoji。
    var emoji: String

    /// 菜系，一道菜只有一個。吃法（麵食／飯食／鍋物）是 `tags` 的事，不放這裡。
    ///
    /// 例外：「去哪吃」模式借用這個型別裝店家時，這裡放的是距離文字（見 `NearbyPlace.asFoodItem`）。
    var category: String

    /// 篩選用的標籤。菜系那個標籤會跟 `category` 重複一份，這是刻意的：
    /// `category` 是拿來顯示的，`tags` 是拿來查的，兩者用途不同。
    var tags: Set<FoodTag>

    /// 2 到 3 則優點，每則 25 字內。
    var pros: [String]

    /// 1 到 2 則缺點，每則 25 字內。
    var cons: [String]
}

extension FoodItem {
    /// 顯示用的安全 emoji。
    ///
    /// 資料改成人寫的之後仍然需要驗證：欄位是自由文字，打字打錯、
    /// 貼到全形字或漢字都可能發生，轉盤上就會出現一個字混在 emoji 中間。
    var displayEmoji: String {
        guard let first = emoji.first,
              let scalar = first.unicodeScalars.first,
              scalar.properties.isEmoji,
              // 數字與 # * 的 isEmoji 也是 true，用碼位下限排掉。
              scalar.value > 0x238C || first.unicodeScalars.count > 1
        else { return "🍽️" }
        return String(first)
    }

    /// 這道菜是不是使用者自己加的。
    var isCustom: Bool { id.hasPrefix("custom-") }

    /// 這其實是一家店，不是一道菜（「去哪吃」模式借用了這個型別）。
    /// UI 用它決定要顯示「找附近有賣的店」還是「導航過去」。
    var isPlace: Bool { id.hasPrefix("place-") }
}

enum WheelCapacity {
    /// 使用者可以選的格數。下限 4 是因為再少就不像轉盤了；
    /// 上限 12 以前是被 `@Generable` 的 `.count(12)` 綁死的，現在純粹是版面考量 ——
    /// 再多格轉盤上的字就放不下。
    static let allowedSlots = [4, 6, 8, 10, 12]

    /// 預設格數。八格是字放得下又有得選的平衡點。
    static let defaultSlots = 8
}
