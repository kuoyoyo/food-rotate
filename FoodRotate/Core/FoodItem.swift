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

extension FoodItem {
    /// 標籤**寬容解碼**：不認得的 rawValue 丟掉那個標籤，不是丟掉整道菜。
    ///
    /// 合成的 `Decodable` 遇到不認得的標籤會 throw，而這個型別的兩條解碼路徑
    /// 都是 `try?`（`CustomFoodStore` 讀 UserDefaults、`SpinRecord.items` 讀 SwiftData），
    /// 於是一個標籤解不開的後果是**整包資料無聲消失** —— 使用者掛了「素可」的可能只有
    /// 一道自訂料理，賠掉的卻是他全部的自訂料理。
    ///
    /// **這個取捨的代價要講清楚**：丟掉標籤的那道菜會從某些篩選結果裡消失。
    /// 接受它是因為那正是 `FoodDataAudit` 在管的事（缺標籤有人接），
    /// 而「整份清單不見了」沒有任何機制接得住。
    ///
    /// 前提：`FoodTag` 的 rawValue 就是資料檔裡寫的字（見 `FoodTag` 檔頭）。
    /// 所以「不認得」只有兩種來源 —— 打錯字，或是這個 case 被移除了
    /// （2026-08-27 移除「素可」是第一次）。兩種都該丟標籤而不是丟菜。
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        emoji = try container.decode(String.self, forKey: .emoji)
        category = try container.decode(String.self, forKey: .category)
        pros = try container.decode([String].self, forKey: .pros)
        cons = try container.decode([String].self, forKey: .cons)
        // 先解成字串再過濾。解成 `Set<FoodTag>` 就沒有「過濾」這個時機了。
        tags = Set(try container.decode([String].self, forKey: .tags).compactMap(FoodTag.init(rawValue:)))
    }

    /// 明寫出來讓上面那個 `init(from:)` 與合成的 `encode(to:)` 用同一份鍵。
    private enum CodingKeys: String, CodingKey {
        case id, name, emoji, category, tags, pros, cons
    }
}
