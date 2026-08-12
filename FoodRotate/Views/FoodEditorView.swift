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
            Text("基本資料")
        } footer: {
            Text("Emoji 會顯示在轉盤的格子上。選了分類就會自動掛上對應的菜系標籤，篩選時找得到。")
        }
    }

    /// 標籤。**跟篩選器用同一個 `TagGrid`**，不另做一套。
    ///
    /// 唯一的差別是忌口區不加警示權重：篩選器裡的「無牛」是使用者的限制
    /// （一條不會被自動放寬、有後果的規則），這裡的「無牛」是**在描述這道菜不含牛**。
    /// 同一個標籤在兩個畫面語意不同，只有前者需要警示。
    private var tagsSection: some View {
        Section("標籤") {
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
        }
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
            Text(title)
        } footer: {
            Text(footer)
        }
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
            // 先清掉改名覆寫再存。這道菜可能在轉盤上被改過名字，
            // 那筆覆寫會蓋在這裡存的新名字上面，畫面看起來就像沒改到。
            store.rename(id: item.id, to: item.name)
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

    var body: some View {
        List {
            Section {
                Button("新增料理", systemImage: "plus.circle.fill") { isAdding = true }

                if store.customItems.isEmpty {
                    Text("還沒有自己加的料理。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.customItems) { item in
                        Button {
                            editing = item
                        } label: {
                            row(item, detail: item.category)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets { store.exclude(store.customItems[index]) }
                    }
                }
            } header: {
                Text("我加的料理")
            } footer: {
                Text("自己加的料理會跟內建的五十道一起參加抽樣。")
            }

            Section {
                if store.excludedBuiltIns.isEmpty {
                    Text("沒有排除任何料理。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.excludedBuiltIns) { item in
                        HStack {
                            row(item, detail: item.category)
                            Spacer(minLength: 8)
                            Button("還原") { store.restore(id: item.id) }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("以後都不要的")
            }

            if store.customizationCount > 0 {
                Section {
                    Button("還原成預設", role: .destructive) { isConfirmingReset = true }
                } footer: {
                    Text("會一併刪掉你自己加的料理，這個動作沒辦法復原。")
                }
            }
        }
        .navigationTitle("我的清單")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isAdding) { FoodEditorView(editing: nil) }
        .sheet(item: $editing) { FoodEditorView(editing: $0) }
        .confirmationDialog("還原成預設？", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("還原", role: .destructive) { store.resetAll() }
            Button("取消", role: .cancel) {}
        }
    }

    private func row(_ item: FoodItem, detail: String) -> some View {
        HStack(spacing: 12) {
            Text(item.displayEmoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
