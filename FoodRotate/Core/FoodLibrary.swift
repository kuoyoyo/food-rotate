import Foundation

/// 內建的菜色資料庫。
///
/// 資料放在 `foods.json` 而不是寫成 Swift 字面值，是為了之後移植 Android：
/// 同一份檔案丟進 `assets/` 就能用，不必重打一次五十道菜。
enum FoodLibrary {
    /// 全部內建菜色。第一次存取時解析，之後直接用。
    static let all: [FoodItem] = load()

    /// 資料庫裡實際用到的分類，依第一次出現的順序。
    /// 不寫死清單，加一道新菜換一個分類就會自己反映出來。
    static var categories: [String] {
        var seen = Set<String>()
        return all.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    private static func load() -> [FoodItem] {
        guard let url = Bundle.main.url(forResource: "foods", withExtension: "json") else {
            fatalError("foods.json 不在 bundle 裡。檢查它有沒有被加進 target 的 Copy Bundle Resources。")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([FoodItem].self, from: data)
        } catch {
            // 刻意 fatalError 而不是回空陣列：資料是隨 App 一起出貨的，
            // 解不開就是開發階段打錯字。靜默回空陣列會變成「使用者看到空轉盤，
            // 但沒有人知道為什麼」，那種錯最難找。
            fatalError("foods.json 解析失敗：\(error)")
        }
    }
}
