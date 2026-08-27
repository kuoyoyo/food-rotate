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

    /// **刻意**沒有菜系的料理：`id` → 為什麼。
    ///
    /// 有些東西本來就不屬於任何一國菜，硬塞一個菜系會製造錯誤的篩選結果
    /// （標「台式」的話，選台式的人會抽到一個沒有台灣味的餐盒）。這種情況要能豁免，
    /// 否則檢查會永遠叫，久了就沒有人看 —— 一個天天喊狼來了的檢查等於沒有檢查。
    ///
    /// value 是原因不是 `Bool`，**強迫加進來的人寫下理由**，這份清單才不會變成
    /// 「檢查太吵就丟進去」的垃圾桶。
    static let cuisineExemptions: [String: String] = [
        "low-calorie-bento": "便利商店的低卡餐盒不屬於任何一國菜，改由圖示系統的 fallback 接住"
        // 出處：`PM提案-7道菜補標籤-待核可.md` 第一節，2026-08-11
    ]

    enum Finding: Equatable, Sendable {
        /// 兩道菜共用同一個 `id`。抽樣時的 `seen` 去重會把後面那道當成重複而丟掉。
        case duplicateID(id: String, names: [String])

        /// 這道菜在圖示需要的維度上沒有任何標籤，S2 之後會沒有圖可用。
        case missingIconDimension(id: String, name: String, dimension: FoodTag.Dimension)

        /// 豁免已經沒有意義了 —— 這道菜現在有菜系標籤。
        ///
        /// 豁免清單不會自己過期，留著會讓下一個真正的缺漏被靜靜吃掉。
        case staleCuisineExemption(id: String, name: String)

        /// 這個**忌口**標籤在整份資料裡一道菜都沒有掛到。
        ///
        /// 這是 2026-08-27 稽核抓到的那一類缺陷（「素可」零命中）。上面兩條問的都是
        /// 「這道菜有沒有標籤」，**沒有人反過來問「這個標籤有沒有菜」** ——
        /// 於是一個永遠篩不出東西的選項在篩選器上掛了好幾個月，兩輪 QC 都沒看到。
        case restrictionMatchesNothing(tag: FoodTag)
    }

    /// 為什麼只驗忌口，不驗全部六個維度。
    ///
    /// 忌口是**硬條件**：`FoodPicker` 第一步篩完就 `guard !allowed.isEmpty`，
    /// 空了直接回 `.restrictions`，不放寬、不退而求其次。所以一個零命中的忌口標籤
    /// 等於一條死路 —— 點下去必定空轉盤，而畫面給的出口（取消忌口）救不了他。
    ///
    /// 軟標籤零命中只會被逐層放寬掉（`FoodPicker` 第三步），使用者仍然拿得到一盤菜、
    /// 而且畫面會老實說「已放寬 X」。那是**設計好的降級，不是缺陷**，
    /// 在這裡叫它一聲只會讓這份報告開始喊狼來了。
    static let matchCheckedDimensions: [FoodTag.Dimension] = [.restriction]

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
            let isExempt = cuisineExemptions[item.id] != nil
            let hasCuisine = !item.tags(in: .cuisine).isEmpty

            if isExempt, hasCuisine {
                results.append(.staleCuisineExemption(id: item.id, name: item.name))
            }

            for dimension in iconDimensions where item.tags(in: dimension).isEmpty {
                // 被豁免的只擋菜系那一條，吃法照樣要有 —— 豁免的理由是「不屬於任何一國菜」，
                // 不是「這道菜什麼標籤都不用掛」。
                if dimension == .cuisine, isExempt { continue }
                results.append(
                    .missingIconDimension(id: item.id, name: item.name, dimension: dimension)
                )
            }
        }

        return results
    }

    /// **整份資料庫**的稽核：逐筆的那些，加上只有對完整資料庫才成立的那些。
    ///
    /// 為什麼要跟 `findings(in:)` 分開，而不是多加一條進去：
    ///
    /// `findings(in:)` 問的每一件事都是**逐筆**的（這道菜有沒有菜系？這個 id 撞號了嗎？），
    /// 所以它對任何一份清單都成立 —— 測試才能拿兩三筆造出來的資料逼它出聲。
    /// 「這個標籤有沒有菜掛到」不是逐筆的問題，它問的是**這一份清單完不完整**。
    /// 把它混進 `findings(in:)`，兩筆的測試資料會立刻被判定成「三個忌口都沒人掛」——
    /// 那不是缺陷，那只是一份小清單。**一個對小清單必定誤報的檢查等於沒有檢查。**
    ///
    /// 所以分兩個入口，各自的前提寫在名字上：逐筆的叫 `findings`，
    /// 要求完整的叫 `libraryFindings`。`FoodLibrary` 載入時走後者。
    static func libraryFindings(in items: [FoodItem]) -> [Finding] {
        var results = findings(in: items)

        // 反過來問：每一個忌口標籤有沒有菜掛著。
        // 依 `Dimension.tags` 的順序回報，理由跟上面一樣 —— 順序要穩定。
        for dimension in matchCheckedDimensions {
            for tag in dimension.tags where !items.contains(where: { $0.tags.contains(tag) }) {
                results.append(.restrictionMatchesNothing(tag: tag))
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
            case let .staleCuisineExemption(id, name):
                lines.append("  • \(name)（\(id)）已經有菜系標籤了，把它從 cuisineExemptions 移除")
            case let .restrictionMatchesNothing(tag):
                lines.append(
                    "  • 忌口「\(tag.rawValue)」一道菜都沒有掛到 —— 選了它必定空轉盤。"
                    + "補資料，或把這個 case 從 FoodTag 移除"
                )
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
