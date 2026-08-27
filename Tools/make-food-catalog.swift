//
//  make-food-catalog.swift — 把 foods.json 產生成看得懂的菜色資料庫
//
//  存在的理由：50 道菜一直只存在於 `FoodRotate/Core/foods.json`，一份 20KB 的原始 JSON。
//  README 說「50 道內建料理」，但沒有任何地方看得到那 50 道**是什麼**。
//
//  為什麼是產生的而不是手寫一份 Markdown：手寫的那份第一天就開始過期。
//  這支跟 App **編同一批型別**（`FoodItem`／`FoodTag`／`FoodIcon`／`FoodDataAudit`），
//  所以「哪道菜配哪個圖示」「哪個標籤屬於哪個維度」不是這裡重寫一遍的，
//  是直接問 App 本人 —— 規則改了，重跑就跟著改，不可能分岔。
//  （同一條理由見 `Tools/make-icon.swift`：icon 的配色也是讀 `DesignTokens` 而不是烙進 SVG。）
//
//  用法（要跟 Core 的型別一起編，所以是 swiftc 不是 swift）：
//      swiftc Tools/make-food-catalog.swift \
//          FoodRotate/Core/FoodItem.swift FoodRotate/Core/FoodTag.swift \
//          FoodRotate/Core/FoodIcon.swift FoodRotate/Core/FoodDataAudit.swift \
//          -o /tmp/make-food-catalog \
//        && /tmp/make-food-catalog FoodRotate/Core/foods.json > docs/菜色資料庫.md
//
//  驗證方式：刪掉 docs/菜色資料庫.md 重跑，`git diff` 必須是空的。
//

import Foundation

@main
struct MakeFoodCatalog {

    static func main() throws {
        let path = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "FoodRotate/Core/foods.json"

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let items = try JSONDecoder().decode([FoodItem].self, from: data)

        var out = ""
        func line(_ text: String = "") { out += text + "\n" }

        // MARK: 檔頭

        line("# 菜色資料庫")
        line()
        line("轉盤裡內建的 \(items.count) 道料理，全部列在這裡。")
        line()
        line("> **這份檔案是產生的，不要手改。**")
        line("> 來源：[`FoodRotate/Core/foods.json`](../FoodRotate/Core/foods.json)")
        line("> 產生器：[`Tools/make-food-catalog.swift`](../Tools/make-food-catalog.swift)（用法寫在檔頭）")
        line(">")
        line("> 圖示與維度不是這份文件自己算的，是跟 App 編同一批型別問出來的 ——")
        line("> 規則改了重跑就跟著改，不會有一份說法留在文件裡過期。")
        line()
        line("**App 裡也有同一份**：設定 → 菜色資料庫 → 內建料理。")
        line("那一頁可以搜尋（菜名與標籤都比對）、點開看單道的完整標籤與優缺點。")
        line("這一份的用處是不裝 App 也看得到，而且 diff 得出來。")
        line()
        line("---")
        line()

        // MARK: 標籤覆蓋率

        line("## 標籤覆蓋率")
        line()
        line("每個標籤各有幾道菜掛著。**這張表是拿來發現漏洞的**，不是裝飾 ——")
        line("`素可` 這個忌口標籤在 \(items.count) 道菜裡零命中的事就是在這裡現形的")
        line("（2026-08-27 稽核，該標籤已移除）。")
        line()
        line("忌口尤其要看：它是**硬條件、永遠不會被自動放寬**，所以一個零命中的忌口標籤")
        line("等於一條死路 —— 選了它必定空轉盤。其餘五個維度零命中只會被逐層放寬，")
        line("使用者照樣拿得到一盤菜。這條差別現在由 `FoodDataAudit.restrictionMatchesNothing` 守著。")
        line()

        for dimension in FoodTag.Dimension.allCases {
            // 兩段粗體要用空白隔開，緊貼著寫 `**A****B**` 在 GitHub 上不會斷開。
            let hard = dimension.isHardConstraint ? " **（硬條件，不放寬）**" : ""
            line("**\(dimension.rawValue)**\(hard)")
            line()
            line("| 標籤 | 幾道菜 |")
            line("|---|---:|")
            for tag in dimension.tags {
                let count = items.filter { $0.tags.contains(tag) }.count
                let cell = count == 0 ? "**0** ⚠️" : "\(count)"
                line("| \(tag.rawValue) | \(cell) |")
            }
            line()
        }

        line("---")
        line()

        // MARK: 菜系分布

        let cuisines = FoodTag.Dimension.cuisine.tags
        line("## 菜系分布")
        line()
        line("| 菜系 | 幾道菜 |")
        line("|---|---:|")
        for tag in cuisines {
            let count = items.filter { $0.tags.contains(tag) }.count
            line("| \(tag.rawValue) | \(count) |")
        }
        let noCuisine = items.filter { $0.tags(in: .cuisine).isEmpty }
        if !noCuisine.isEmpty {
            line("| （刻意沒有菜系） | \(noCuisine.count) |")
        }
        line()
        line("一道菜只會有一個菜系（`FoodDataAudit` 盯著這件事）。")
        line("吃法／情境／口味則可以有好幾個 —— 上面每個維度的加總會超過 \(items.count)，那是正常的。")
        line()
        line("---")
        line()

        // MARK: 全部菜色

        line("## 全部 \(items.count) 道")
        line()
        line("每道菜的優缺點**全文照列，沒有截斷**。")
        line("「要注意」不是免責聲明 —— 產品規則是每道菜都要有缺點，")
        line("目的是讓使用者有依據推翻轉盤給的答案，不是說服他接受。")
        line()

        func table(_ group: [FoodItem]) {
            line("| 菜色 | 標籤 | 忌口 | 可以吃 | 要注意 |")
            line("|---|---|---|---|---|")
            for item in group {
                let soft = [FoodTag.Dimension.form, .occasion, .flavour, .trait]
                    .flatMap { dimension in dimension.tags.filter { item.tags.contains($0) } }
                    .map(\.rawValue)
                    .joined(separator: "・")
                let restrictions = FoodTag.Dimension.restriction.tags
                    .filter { item.tags.contains($0) }
                    .map(\.rawValue)
                    .joined(separator: "・")
                // `category` 有 4 道放的是吃法值而不是菜系（2026-08-27 稽核的 H，
                // 已知且刻意不動）。列出來讓它看得見，而不是被這份文件蓋掉。
                let cuisine = item.tags(in: .cuisine).first?.rawValue
                let categoryNote = cuisine == item.category
                    ? ""
                    : "・分類寫「\(item.category)」"
                let name = "\(item.emoji) **\(item.name)**<br>"
                    + "<sub>`\(item.id)` · 圖示 `\(item.icon.rawValue)`\(categoryNote)</sub>"
                line(
                    "| \(name) | \(soft) | \(restrictions.isEmpty ? "—" : restrictions) "
                    + "| \(item.pros.joined(separator: "<br>")) "
                    + "| \(item.cons.joined(separator: "<br>")) |"
                )
            }
            line()
        }

        for tag in cuisines {
            let group = items.filter { $0.tags.contains(tag) }
            guard !group.isEmpty else { continue }
            line("### \(tag.rawValue)（\(group.count) 道）")
            line()
            table(group)
        }

        if !noCuisine.isEmpty {
            line("### 刻意沒有菜系（\(noCuisine.count) 道）")
            line()
            for item in noCuisine {
                let why = FoodDataAudit.cuisineExemptions[item.id] ?? "（沒有登記理由）"
                line("\(item.name)：\(why)")
                line()
            }
            line("硬塞一個菜系會製造錯誤的篩選結果 —— 標「台式」的話，")
            line("選台式的人會抽到一個沒有台灣味的餐盒。所以豁免要能登記，")
            line("而且 `FoodDataAudit.cuisineExemptions` 的 value 是**原因不是 `Bool`**，")
            line("強迫加進來的人寫下理由。")
            line()
            table(noCuisine)
        }

        line("---")
        line()

        // MARK: 稽核

        line("## 資料稽核")
        line()
        let findings = FoodDataAudit.libraryFindings(in: items)
        if let report = FoodDataAudit.consoleReport(for: findings) {
            line("```")
            line(report)
            line("```")
        } else {
            line("`FoodDataAudit.libraryFindings` 跑過這 \(items.count) 筆：**零問題**。")
            line()
            line("驗的是 id 有沒有撞號、每道菜有沒有圖示需要的兩個維度、豁免有沒有過期，")
            line("以及每個忌口標籤有沒有菜掛著。App 在 DEBUG 建置載入資料時會跑同一份檢查。")
        }
        line()

        FileHandle.standardOutput.write(Data(out.utf8))
    }
}
