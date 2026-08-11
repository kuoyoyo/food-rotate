import SwiftUI

/// 轉盤下方的食物清單，每一道都列出優缺點。
///
/// 這是這個 App 真正解決問題的地方：轉盤只給你一個答案，清單讓你知道
/// 其他選項各自好在哪、雷在哪，才有辦法接受或推翻轉盤的結果。
///
/// 展開後每張卡都能直接找附近的店、改名或刪掉。找附近特別重要：
/// 結果頁關掉之後就回不去了，沒有這個入口就得重轉一次才能查同一道菜。
struct FoodCardList: View {
    let items: [FoodItem]
    let winnerName: String?
    let onRename: (FoodItem, String) -> Void
    /// 這一輪不要。下次抽還是抽得到。
    let onDelete: (FoodItem) -> Void
    /// 以後都不要。寫進排除名單。
    let onExcludeForever: (FoodItem) -> Void
    /// 抽到的是店家時，直接導航過去。
    let onOpenMaps: (FoodItem) -> Void
    let onCall: (FoodItem) -> Void
    /// 這家店的電話，沒有就回 nil。
    let phoneNumber: (FoodItem) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("候選清單")
                    .font(.headline)
                Spacer()
                Text("\(items.count) 道")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                FoodCard(
                    item: item,
                    isWinner: item.name == winnerName,
                    canDelete: items.count > 2,
                    onRename: { onRename(item, $0) },
                    onDelete: { onDelete(item) },
                    onExcludeForever: { onExcludeForever(item) },
                    onOpenMaps: { onOpenMaps(item) },
                    onCall: { onCall(item) },
                    phoneNumber: phoneNumber(item)
                )
            }

            if !items.isEmpty {
                Text("點卡片看優缺點，可以改名或把這輪不想吃的刪掉。轉盤會跟著更新。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

struct FoodCard: View {
    let item: FoodItem
    let isWinner: Bool
    /// 剩兩道就不給刪了，轉盤至少要有兩格才轉得起來。
    let canDelete: Bool
    let onRename: (String) -> Void
    let onDelete: () -> Void
    let onExcludeForever: () -> Void
    let onOpenMaps: () -> Void
    let onCall: () -> Void
    let phoneNumber: String?

    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false
    @State private var showNearby = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var isConfirmingExclude = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    pointList(
                        // 店家借用同一個型別，`pros` 裡放的是地址。
                        title: item.isPlace ? "地址" : "優點",
                        symbol: "checkmark.circle.fill",
                        tint: Theme.positive(for: colorScheme),
                        points: item.pros
                    )
                    pointList(
                        title: "缺點",
                        symbol: "exclamationmark.triangle.fill",
                        tint: Theme.negative(for: colorScheme),
                        points: item.cons
                    )

                    // MapKit 沒有營業時間，所以不猜。有電話就讓人自己打去問。
                    if let phoneNumber {
                        Button(action: onCall) {
                            Label("打電話問（\(phoneNumber)）", systemImage: "phone.fill")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }

                    actions
                }
                .padding(.top, 10)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isWinner ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.22)) { isExpanded.toggle() }
        }
        .sheet(isPresented: $showNearby) {
            NearbyRestaurantsView(dish: item.name)
        }
        .alert("改成什麼名字？", isPresented: $isRenaming) {
            TextField("料理名稱", text: $draftName)
            Button("取消", role: .cancel) {}
            Button("儲存") { onRename(draftName) }
        } message: {
            Text("改過的名字會存下來，以後抽到這道都用新名字。")
        }
        .confirmationDialog("不要「\(item.name)」了？", isPresented: $isConfirmingExclude, titleVisibility: .visible) {
            Button("這輪不要") { onDelete() }
            // 店家每次搜尋 id 都不一樣，記不住「以後」，所以只給這一輪的選項。
            if !item.isPlace {
                Button("以後都不要", role: .destructive) { onExcludeForever() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(item.isPlace ? "從這一輪的轉盤拿掉。" : "「以後都不要」之後可以在設定頁還原。")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(item.displayEmoji)
                .font(.system(size: 30))
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.headline)
                    if isWinner {
                        Text("轉中")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                Text(item.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
    }

    /// 展開後的操作列。三個動作都是在「這一道」上做事，所以放在卡片裡而不是全域工具列。
    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                if item.isPlace { onOpenMaps() } else { showNearby = true }
            } label: {
                Label(
                    item.isPlace ? "導航" : "找附近",
                    systemImage: item.isPlace ? "arrow.triangle.turn.up.right.circle.fill" : "mappin.and.ellipse"
                )
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)

            Button {
                draftName = item.name
                isRenaming = true
            } label: {
                Label("改名", systemImage: "pencil")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)

            Button(role: .destructive) {
                isConfirmingExclude = true
            } label: {
                Label("不要", systemImage: "trash")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .disabled(!canDelete)
        }
        // 按鈕要吃自己的點擊，不能被卡片的展開手勢搶走。
        .buttonStyle(.automatic)
        .onTapGesture {}
    }

    @ViewBuilder
    private func pointList(title: String, symbol: String, tint: Color, points: [String]) -> some View {
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: symbol)
                            .font(.caption)
                            .foregroundStyle(tint)
                        Text(point)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
