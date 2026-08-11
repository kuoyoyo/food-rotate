import Foundation

/// 使用者對候選池做的三種改動，以及它們的儲存。
///
/// 為什麼要有這一層：卡片上原本就能改名與刪除，但那只作用在**當下這一輪**的陣列，
/// 按一次「換一組」就全部還原。真正想要的是「這道菜我以後都不要看到」與
/// 「這道菜在我這裡叫別的名字」，那必須存下來。
///
/// 存在 UserDefaults 的 JSON 而不是 SwiftData：資料量小（幾十筆），
/// 而且 JSON 的形狀跟 `foods.json` 一致，之後移植 Android 只要換掉儲存層。
@MainActor
@Observable
final class CustomFoodStore {
    static let shared = CustomFoodStore()

    private enum Key {
        static let items = "customFoodItems"
        static let excluded = "excludedFoodIDs"
        static let renamed = "renamedFoodNames"
    }

    private let defaults = UserDefaults.standard

    /// 使用者自己加的料理。
    private(set) var customItems: [FoodItem] = []

    /// 「以後都不要出現」的 id。內建與自訂都適用。
    private(set) var excludedIDs: Set<String> = []

    /// `id` → 使用者改過的名字。
    ///
    /// 存 id 而不是「舊名 → 新名」，否則改過一次之後就對不回原本那道菜，
    /// 第二次改名會變成新增一筆孤兒紀錄。
    private(set) var renamedNames: [String: String] = [:]

    private init() {
        customItems = decode([FoodItem].self, forKey: Key.items) ?? []
        excludedIDs = Set(decode([String].self, forKey: Key.excluded) ?? [])
        renamedNames = decode([String: String].self, forKey: Key.renamed) ?? [:]
    }

    /// 抽樣真正會用到的候選池：內建 + 自訂，扣掉排除的，套上改過的名字。
    var pool: [FoodItem] {
        (FoodLibrary.all + customItems)
            .filter { !excludedIDs.contains($0.id) }
            .map { item in
                guard let newName = renamedNames[item.id] else { return item }
                var copy = item
                copy.name = newName
                return copy
            }
    }

    /// 使用者動過的東西有幾件。設定頁用它決定要不要顯示「還原成預設」。
    var customizationCount: Int {
        customItems.count + excludedIDs.count + renamedNames.count
    }

    // MARK: - 新增與刪除

    func add(_ item: FoodItem) {
        var new = item
        // id 一律由這裡發，呼叫端不用管，也不可能跟內建的撞到。
        new.id = "custom-\(UUID().uuidString)"
        customItems.append(new)
        persistItems()
    }

    func update(_ item: FoodItem) {
        guard let index = customItems.firstIndex(where: { $0.id == item.id }) else { return }
        customItems[index] = item
        persistItems()
    }

    /// 永久拿掉一道菜。
    ///
    /// 自訂的直接刪除；內建的沒辦法從 bundle 裡刪，所以記進排除名單。
    /// 兩者對使用者來說是同一件事，差別只在還不還得回來——自訂的刪了就沒了，
    /// 內建的隨時可以從設定頁恢復。
    func exclude(_ item: FoodItem) {
        if item.isCustom {
            customItems.removeAll { $0.id == item.id }
            renamedNames[item.id] = nil
            persistItems()
            persistRenames()
        } else {
            excludedIDs.insert(item.id)
            persistExclusions()
        }
    }

    func restore(id: String) {
        excludedIDs.remove(id)
        persistExclusions()
    }

    // MARK: - 改名

    func rename(id: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 改回原名就把覆寫拿掉，不要留一筆「新名跟原名一樣」的紀錄，
        // 否則設定頁的「你改過幾道」會愈數愈多。
        if let original = FoodLibrary.all.first(where: { $0.id == id }), original.name == trimmed {
            renamedNames[id] = nil
        } else if let custom = customItems.first(where: { $0.id == id }), custom.name == trimmed {
            renamedNames[id] = nil
        } else {
            renamedNames[id] = trimmed
        }
        persistRenames()
    }

    /// 把所有改動清掉，回到剛裝好的樣子。自訂的料理也會一起消失，所以呼叫端要先確認。
    func resetAll() {
        customItems = []
        excludedIDs = []
        renamedNames = [:]
        persistItems()
        persistExclusions()
        persistRenames()
    }

    /// 被排除的內建料理，給設定頁列出來還原用。
    var excludedBuiltIns: [FoodItem] {
        FoodLibrary.all.filter { excludedIDs.contains($0.id) }
    }

    // MARK: - 儲存

    private func persistItems() { encode(customItems, forKey: Key.items) }
    private func persistExclusions() { encode(Array(excludedIDs), forKey: Key.excluded) }
    private func persistRenames() { encode(renamedNames, forKey: Key.renamed) }

    private func encode(_ value: some Encodable, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
