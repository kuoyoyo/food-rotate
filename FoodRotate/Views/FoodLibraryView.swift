import SwiftUI

/// 內建料理的瀏覽頁。
///
/// ## 為什麼要有這一頁
///
/// 設定頁的「菜色資料庫」那一區以前只寫著「內建料理　50 道・12 類」——
/// **一個數字，點不進去**。App 宣稱它內建了 50 道菜，但沒有任何地方看得到那 50 道
/// 是什麼；使用者只能靠轉盤一次抽 8 道去猜。
///
/// 那跟死按鈕是同一種病的另一面：死按鈕是「看得到、按不動」，
/// 這是「講得出數量、看不到內容」。兩者都是畫面上有一個承諾而背後沒有東西接。
///
/// ## 這一頁是唯讀的
///
/// 改名、刪除、以後都不要**全部不在這裡**，它們在「我的清單」。
/// 這一頁回答的是「這個 App 內建了什麼」，不是「我改了什麼」——
/// 兩個問題分開，是因為它們的答案會隨著不同的東西改變。
///
/// 所以資料來源是 `store.builtIns` 而不是 `store.pool`：
/// **被設成「以後都不要」的那幾道仍然列在這裡**，它們還是內建的一員，
/// 只是使用者決定不抽它們。那個決定的去處是「我的清單」。
///
/// ## 依菜系分組，用的是標籤不是 `category`
///
/// `foods.json` 的 `category` 欄位混了「輕食」「鍋物」兩個吃法值（四道菜），
/// 那是 2026-08-11 裁示不動的既有狀況。分組要是照 `category` 走，這一頁就會冒出
/// 「輕食」「鍋物」兩個假菜系，把那個資料問題變成畫面問題。
/// 菜系的真相在標籤上（見 `FoodItem.category` 的欄位註解：category 是拿來顯示的，
/// tags 才是拿來查的），所以分組照 `FoodTag.Dimension.cuisine` 走。
///
/// 沒有菜系的那一道（低卡餐盒）單獨一組，理由跟 `FoodDataAudit.cuisineExemptions`
/// 記的一樣 —— 它本來就不屬於任何一國菜，硬塞一個會製造錯誤的篩選結果。
struct FoodLibraryView: View {
    @State private var store = CustomFoodStore.shared
    @State private var query = ""
    /// 展開了優缺點的那幾道。**存 id 不存索引**，跟 `FoodCardList` 同一條理由：
    /// 索引只在「這一份清單」裡有意義，而搜尋會換掉清單。
    @State private var expandedIDs: Set<String> = []

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {
            if groups.isEmpty {
                noMatch
            } else {
                ForEach(groups, id: \.title) { group in
                    Section {
                        ForEach(group.items) { item in
                            row(item)
                        }
                    } header: {
                        Text("\(group.title)　\(group.items.count) 道")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary(for: colorScheme))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .dishListBackground(for: colorScheme)
        .navigationTitle("內建料理")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "找菜名或標籤")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(matches.count) / \(store.builtIns.count)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary(for: colorScheme))
            }
        }
    }

    // MARK: 一列

    private func row(_ item: FoodItem) -> some View {
        let isExpanded = expandedIDs.contains(item.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.buttonTap()
                if isExpanded {
                    expandedIDs.remove(item.id)
                } else {
                    expandedIDs.insert(item.id)
                }
            } label: {
                DishListRow(
                    // 線稿而不是 emoji：這一頁列的是**我們的資料**，那顆 emoji 是
                    // `foods.json` 裡我們自己寫的，不是使用者挑的
                    //（見 `DishListRow` 檔頭那張表 —— 依據是「這是誰的東西」）。
                    art: .icon(item.icon),
                    title: item.name,
                    // 副標放忌口。50 道要一眼掃過的時候，「這道有沒有牛」比
                    // 「它是哪一種吃法」更決定得了要不要往下看 —— 而吃法已經有角標了。
                    //
                    // **展開時收掉**：下面的維度表已經有一行「忌口　無牛・無海鮮」，
                    // 留著就是同一件事在相鄰兩行講兩次。收合時它是這一列唯一的忌口資訊，
                    // 展開後它是重複的 —— 同一個欄位在兩種狀態下的價值不一樣。
                    subtitle: isExpanded ? nil : restrictionSummary(item),
                    badgeSource: item,
                    showsFormBadge: true
                ) {
                    Image(systemName: "chevron.down")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary(for: colorScheme))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                details(item)
            }
        }
        .animation(.snappy(duration: 0.2), value: isExpanded)
        .dishListRowStyle(for: colorScheme)
    }

    /// 展開後長出來的東西：完整標籤 + 優缺點。
    ///
    /// 優缺點的呈現跟候選清單、結果頁**同一套**（`positive` 綠、`negative` 橘、
    /// 同樣的符號與字級）—— 同一種資訊在三個地方長一樣，使用者才不用重學。
    private func details(_ item: FoodItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.space8) {
            tagBreakdown(item)
            pointList(
                title: "為什麼可以吃",
                symbol: "checkmark.circle.fill",
                tint: Theme.positive(for: colorScheme),
                points: item.pros
            )
            pointList(
                title: "要注意的地方",
                symbol: "exclamationmark.triangle.fill",
                tint: Theme.negative(for: colorScheme),
                points: item.cons
            )
        }
        .padding(.leading, DishListRowMetrics.separatorInset)
        .padding(.trailing, Theme.space12)
        .padding(.bottom, Theme.space12)
    }

    /// 這道菜的全部標籤，依維度分行。
    ///
    /// 這是這一頁比 `foods.json` 好讀的地方：原始檔裡標籤是一個扁平陣列，
    /// 看不出哪個屬於哪個維度，而維度正是篩選器的結構。
    @ViewBuilder
    private func tagBreakdown(_ item: FoodItem) -> some View {
        ForEach(FoodTag.Dimension.allCases, id: \.self) { dimension in
            let tags = dimension.tags.filter { item.tags.contains($0) }
            if !tags.isEmpty {
                HStack(alignment: .top, spacing: Theme.space8) {
                    Text(dimension.rawValue)
                        .font(Theme.caption)
                        .foregroundStyle(
                            // 忌口用警示色，跟篩選器裡那一區同一條：
                            // 它是硬條件，永遠不會被自動放寬。
                            dimension.isHardConstraint
                                ? Theme.negative(for: colorScheme)
                                : Theme.textSecondary(for: colorScheme)
                        )
                        .frame(width: 64, alignment: .leading)
                    Text(tags.map(\.rawValue).joined(separator: "・"))
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.text(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func pointList(title: String, symbol: String, tint: Color, points: [String]) -> some View {
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: Theme.space4) {
                Text(title)
                    .font(Theme.caption)
                    .foregroundStyle(tint)
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .top, spacing: Theme.space8) {
                        Image(systemName: symbol)
                            .font(Theme.caption)
                            .foregroundStyle(tint)
                        Text(point)
                            .font(Theme.footnote)
                            .foregroundStyle(Theme.text(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var noMatch: some View {
        Text("沒有符合「\(query)」的料理。試試菜名的一部分，或是「無牛」「宵夜」這類標籤。")
            .font(Theme.footnote)
            .foregroundStyle(Theme.textSecondary(for: colorScheme))
            .padding(.vertical, Theme.space12)
            .listRowBackground(Theme.card(for: colorScheme))
    }

    // MARK: 資料

    private func restrictionSummary(_ item: FoodItem) -> String? {
        let tags = FoodTag.Dimension.restriction.tags.filter { item.tags.contains($0) }
        return tags.isEmpty ? nil : tags.map(\.rawValue).joined(separator: "・")
    }

    /// 搜尋規則在 `FoodSearch`，不在這裡 —— 它是產品規則，而且要測得到。
    private var matches: [FoodItem] {
        FoodSearch.matches(in: store.builtIns, query: query)
    }

    private struct Group {
        let title: String
        let items: [FoodItem]
    }

    /// 依菜系分組，順序照 `FoodTag.Dimension.cuisine.tags`（也就是篩選器上的順序）。
    private var groups: [Group] {
        let pool = matches
        var result = FoodTag.Dimension.cuisine.tags.compactMap { tag -> Group? in
            let items = pool.filter { $0.tags.contains(tag) }
            return items.isEmpty ? nil : Group(title: tag.rawValue, items: items)
        }
        let noCuisine = pool.filter { $0.tags(in: .cuisine).isEmpty }
        if !noCuisine.isEmpty {
            result.append(Group(title: "沒有菜系", items: noCuisine))
        }
        return result
    }
}
