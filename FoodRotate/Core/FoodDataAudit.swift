import Foundation

/// 內建資料的健康檢查。
///
/// 存在的理由：`foods.json` 是手寫的，而且沒有 schema 擋著。標籤打錯字會在
/// `FoodLibrary` 解析時 `fatalError`（那種錯很吵，好找），**但「少打一個標籤」不會** ——
/// 少一個標籤解得開、跑得動，只是那道菜從某些篩選結果裡消失。
///
/// S2 把 emoji 換成「菜系 × 吃法」推出來的組合圖示之後，這種安靜的缺漏會直接變成
/// **畫面上那一格沒有圖**。所以檢查要在缺漏還只是資料問題的時候就叫出來，
/// 不要等它變成畫面問題。
///
/// 純函數、只用 Foundation，跟 `Core/` 其他檔一樣可以直接對翻 Kotlin，也方便寫測試。
enum FoodDataAudit {

    /// 圖示系統要靠哪幾個維度決定畫哪張圖。
    ///
    /// 依設計提案是「菜系 × 形態」的組合。缺其中任一個維度就湊不出圖示名，
    /// 所以這兩個維度是**每道菜都必須有**的，其餘四個維度（情境、口味、忌口、其他）
    /// 本來就允許留白。
    static let iconDimensions: [FoodTag.Dimension] = [.cuisine, .form]

    enum Finding: Equatable, Sendable {
        /// 兩道菜共用同一個 `id`。抽樣時的 `seen` 去重會把後面那道當成重複而丟掉。
        case duplicateID(id: String, names: [String])

        /// 這道菜在圖示需要的維度上沒有任何標籤，S2 之後會沒有圖可用。
        case missingIconDimension(id: String, name: String, dimension: FoodTag.Dimension)
    }

    static func findings(in items: [FoodItem]) -> [Finding] {
        var results: [Finding] = []

        var namesByID: [String: [String]] = [:]
        for item in items {
            namesByID[item.id, default: []].append(item.name)
        }
        // 依 items 的順序回報，不用 Dictionary 的順序 —— 否則同一份資料每次跑出來的
        // 報告順序都不一樣，看起來像是又冒出新問題。
        var reportedIDs = Set<String>()
        for item in items where namesByID[item.id]!.count > 1 {
            guard reportedIDs.insert(item.id).inserted else { continue }
            results.append(.duplicateID(id: item.id, names: namesByID[item.id]!))
        }

        for item in items {
            for dimension in iconDimensions where item.tags(in: dimension).isEmpty {
                results.append(
                    .missingIconDimension(id: item.id, name: item.name, dimension: dimension)
                )
            }
        }

        return results
    }

    /// 給 DEBUG 主控台看的報告。沒有問題就回 `nil`。
    static func consoleReport(for findings: [Finding]) -> String? {
        guard !findings.isEmpty else { return nil }

        var lines = ["⚠️ foods.json 資料檢查：\(findings.count) 個問題"]
        for finding in findings {
            switch finding {
            case let .duplicateID(id, names):
                lines.append("  • id 重複「\(id)」：\(names.joined(separator: "、"))")
            case let .missingIconDimension(id, name, dimension):
                lines.append("  • \(name)（\(id)）少了「\(dimension.rawValue)」維度的標籤")
            }
        }
        return lines.joined(separator: "\n")
    }
}

extension FoodItem {
    /// 這道菜在某個維度上掛了哪些標籤。
    func tags(in dimension: FoodTag.Dimension) -> Set<FoodTag> {
        tags.filter { $0.dimension == dimension }
    }
}
