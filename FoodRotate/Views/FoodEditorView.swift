import SwiftUI

/// 新增或編輯一道自己的料理。
///
/// 內建的五十道不見得涵蓋每個人常吃的東西——巷口那家的特定品項、
/// 家裡固定會煮的菜、公司樓下的自助餐，這些只有使用者自己知道。
///
/// 欄位刻意分成必填與選填：名稱與 emoji 沒有它轉盤畫不出來，其餘都可以之後再補。
/// 標籤沒選也能存，只是這道菜在任何篩選條件下都不會被優先挑中（會落到放寬那幾層）。
struct FoodEditorView: View {
    /// nil 代表新增，有值代表編輯既有的自訂料理。
    let editing: FoodItem?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var store = CustomFoodStore.shared

    @State private var name = ""
    @State private var emoji = "🍽️"
    @State private var category = ""
    @State private var tags: Set<FoodTag> = []
    @State private var pros: [String] = [""]
    @State private var cons: [String] = [""]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                basicsSection
                tagsSection
                pointsSection(
                    title: "優點",
                    footer: "選填。留空的欄位不會存進去。",
                    points: $pros
                )
                pointsSection(
                    title: "缺點",
                    footer: "選填。",
                    points: $cons
                )
            }
            .navigationTitle(editing == nil ? "新增料理" : "編輯料理")
            .navigationBarTitleDisplayMode(.inline)
            // 這一頁**不在 S5-B 規格的四頁裡**（規格寫「表單本身 S4 已完成，不動」，
            // 指的是 `TagGrid`）。但它跟其他頁擺在一起看的時候，系統的藍灰分組色
            // 跟這套暖色 token 明顯是兩個東西，所以這裡只做**與設定頁完全相同的一件事**：
            // 換頁底、卡片、分組標題、footer 的顏色。欄位、`TagGrid`、儲存邏輯一個字沒動。
            .scrollContentBackground(.hidden)
            .background(Theme.pageBackground(for: colorScheme))
            .tint(Theme.sauce(for: colorScheme))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存", action: save).disabled(!canSave)
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    // MARK: 欄位

    private var basicsSection: some View {
        Section {
            LabeledContent("名稱") {
                TextField("例如 阿婆麵線", text: $name)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Emoji") {
                // 只留第一個字元。使用者很容易連打好幾個，或是打成一串文字，
                // 轉盤上一格放不下，不如在輸入的時候就收斂。
                TextField("🍜", text: $emoji)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: emoji) { _, new in
                        if let first = new.first { emoji = String(first) }
                    }
            }

            Picker("分類", selection: $category) {
                Text("不指定").tag("")
                ForEach(FoodLibrary.categories, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            // 分類與菜系標籤必須連動。
            //
            // 新增「青醬義大利麵」選了分類「義式」，如果沒有同時掛上義式標籤，
            // 這道菜在菜系篩「義式」時篩不到——分類是拿來顯示的，標籤才是拿來查的
            // （見 FoodItem 的欄位註解）。要求使用者在兩個地方各選一次同一件事，
            // 只會製造漏掉的機會，所以這裡自動同步。
            .onChange(of: category) { old, new in
                if let previous = FoodTag(rawValue: old) { tags.remove(previous) }
                if let current = FoodTag(rawValue: new) { tags.insert(current) }
            }
        } header: {
            editorHeader("基本資料")
        } footer: {
            editorFooter("Emoji 會顯示在轉盤的格子上。選了分類就會自動掛上對應的菜系標籤，篩選時找得到。")
        }
        .listRowBackground(Theme.card(for: colorScheme))
    }

    private func editorHeader(_ text: String) -> some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(Theme.textSecondary(for: colorScheme))
    }

    private func editorFooter(_ text: String) -> some View {
        Text(text)
            .font(Theme.footnote)
            .foregroundStyle(Theme.textSecondary(for: colorScheme))
    }

    /// 標籤。**跟篩選器用同一個 `TagGrid`**，不另做一套。
    ///
    /// 唯一的差別是忌口區不加警示權重：篩選器裡的「無牛」是使用者的限制
    /// （一條不會被自動放寬、有後果的規則），這裡的「無牛」是**在描述這道菜不含牛**。
    /// 同一個標籤在兩個畫面語意不同，只有前者需要警示。
    private var tagsSection: some View {
        Section {
            TagGrid(
                filter: Binding(
                    get: { FilterSelection(tags: tags) },
                    set: { tags = $0.tags }
                ),
                dimensions: FoodTag.Dimension.allCases,
                emphasizesRestriction: false,
                onChange: {}
            )
            .padding(.vertical, Theme.space8)
        } header: {
            editorHeader("標籤")
        }
        .listRowBackground(Theme.card(for: colorScheme))
    }

    private func pointsSection(title: String, footer: String, points: Binding<[String]>) -> some View {
        Section {
            ForEach(points.indices, id: \.self) { index in
                TextField("每則 25 字內", text: points[index])
            }
            Button("再加一則", systemImage: "plus") {
                points.wrappedValue.append("")
            }
            .disabled(points.wrappedValue.count >= 3)
        } header: {
            editorHeader(title)
        } footer: {
            editorFooter(footer)
        }
        .listRowBackground(Theme.card(for: colorScheme))
    }

    // MARK: 存讀

    private func loadExisting() {
        guard let item = editing else { return }
        name = item.name
        emoji = item.emoji
        category = item.category
        tags = item.tags
        pros = item.pros.isEmpty ? [""] : item.pros
        cons = item.cons.isEmpty ? [""] : item.cons
    }

    private func save() {
        let cleaned = { (list: [String]) in
            list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }

        let item = FoodItem(
            // 新增時 id 由 store 發，這裡放什麼都會被蓋掉。
            id: editing?.id ?? "",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            emoji: emoji.isEmpty ? "🍽️" : emoji,
            category: category.isEmpty ? "自訂" : category,
            tags: tags,
            pros: cleaned(pros),
            cons: cleaned(cons)
        )

        if editing == nil {
            store.add(item)
        } else {
            // 直接寫回整筆就好。自訂料理的名字只有一個來源（`customItems` 本身），
            // 不需要再去清什麼覆寫 —— 以前那個「先 rename 再 update」反而會
            // 留下一筆指向新名的孤兒覆寫（S6 P2-3）。
            store.update(item)
        }
        Haptics.buttonTap()
        dismiss()
    }
}

/// 設定頁裡管理自訂料理與排除名單的地方。
struct MyListView: View {
    @State private var store = CustomFoodStore.shared
    @State private var editing: FoodItem?
    @State private var isAdding = false
    @State private var isConfirmingReset = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {
            Section {
                Button {
                    isAdding = true
                } label: {
                    // 實心主色 + `onSauce`：這是這一頁唯一的主要動作。
                    // 深色的 `onSauce` 是**深墨不是白**，白字疊在提亮後的主色上只有 3.50。
                    // `plus` 而不是 `plus.circle.fill`：實心圓套上深墨的 `onSauce`
                    // 會變成一個深色圓塊，比字還重。
                    Label("新增料理", systemImage: "plus")
                        .font(Theme.headline)
                        .foregroundStyle(
                            colorScheme == .dark ? Theme.Dark.onSauce : Theme.Light.onSauce
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.space12)
                        .background(
                            Theme.sauce(for: colorScheme),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.card(for: colorScheme))
                // 按鈕下面不要分隔線：它跟下面的列不是同一類東西。
                .listRowSeparator(.hidden)

                if store.customItems.isEmpty {
                    emptyNote("還沒有自己加的料理。")
                } else {
                    ForEach(store.customItems) { item in
                        Button {
                            editing = item
                        } label: {
                            row(item)
                        }
                        .buttonStyle(.plain)
                        .dishListRowStyle(for: colorScheme)
                    }
                    .onDelete { offsets in
                        for index in offsets { store.exclude(store.customItems[index]) }
                    }
                }
            } header: {
                sectionHeader("我加的料理")
            } footer: {
                sectionFooter("自己加的料理會跟內建的五十道一起參加抽樣。")
            }

            Section {
                if store.excludedBuiltIns.isEmpty {
                    emptyNote("沒有排除任何料理。")
                } else {
                    ForEach(store.excludedBuiltIns) { item in
                        row(item) {
                            // 「還原」是把東西**加回來**，不是破壞性動作，所以走主色。
                            Button("還原") { store.restore(id: item.id) }
                                .font(Theme.footnote)
                                .foregroundStyle(Theme.sauce(for: colorScheme))
                                .buttonStyle(.plain)
                        }
                        .dishListRowStyle(for: colorScheme)
                    }
                }
            } header: {
                sectionHeader("以後都不要的")
            }

            if store.customizationCount > 0 {
                Section {
                    Button("還原成預設") { isConfirmingReset = true }
                        .font(Theme.body)
                        // `negative` 而不是系統紅：這個 App 只有兩個語意色。
                        .foregroundStyle(Theme.negative(for: colorScheme))
                        .listRowBackground(Theme.card(for: colorScheme))
                } footer: {
                    sectionFooter("會一併刪掉你自己加的料理，這個動作沒辦法復原。")
                }
            }
        }
        .navigationTitle("我的清單")
        .navigationBarTitleDisplayMode(.inline)
        .dishListBackground(for: colorScheme)
        .sheet(isPresented: $isAdding) { FoodEditorView(editing: nil) }
        .sheet(item: $editing) { FoodEditorView(editing: $0) }
        .confirmationDialog("還原成預設？", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("還原", role: .destructive) { store.resetAll() }
            Button("取消", role: .cancel) {}
        }
    }

    /// 跟歷史頁共用的列。這一頁的 emoji **百分之百是使用者挑的**，更沒有理由換掉。
    private func row<Trailing: View>(
        _ item: FoodItem,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        DishListRow(
            emoji: item.displayEmoji,
            title: item.name,
            subtitle: item.category,
            badgeSource: item,
            // 這一頁的角標是主要的類型資訊來源（沒有線稿圖示），所以菜系與吃法都給。
            showsFormBadge: true,
            trailing: trailing
        )
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(Theme.textSecondary(for: colorScheme))
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(Theme.footnote)
            .foregroundStyle(Theme.textSecondary(for: colorScheme))
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(Theme.footnote)
            .foregroundStyle(Theme.textSecondary(for: colorScheme))
            .padding(.horizontal, Theme.space12)
            .padding(.vertical, Theme.space12)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Theme.card(for: colorScheme))
            .listRowSeparator(.hidden)
    }
}
