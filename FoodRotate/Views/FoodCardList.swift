import SwiftUI

/// 轉盤下方的候選清單。
///
/// 這是這個 App 真正解決問題的地方：轉盤只給你一個答案，清單讓你知道
/// 其他選項各自好在哪、雷在哪，才有辦法接受或推翻轉盤的結果。
///
/// **改成一份清單而不是一疊卡片。** 以前每一道是獨立卡片（圓角 + 內距 + 卡間距，
/// 單張約 64pt），12 道就是 768pt；改成同一個容器裡的列之後單列 44pt，省下約三成高度。
/// 視覺上也才像「一份清單」而不是「一疊各自獨立的東西」。
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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space12) {
            HStack {
                Text("候選清單")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.text(for: colorScheme))
                Spacer()
                Text("\(items.count) 道")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary(for: colorScheme))
            }

            VStack(spacing: 0) {
                // 身分**一定要用 `item.id`，不能用陣列索引**。
                //
                // 每一列自己持有狀態（展開優缺點、左滑的位置）。用索引當身分的話，
                // 刪掉第 3 道之後 SwiftUI 認為「第 3 列還是第 3 列」，於是那個狀態
                // 留在原位、換一道菜繼續套用 —— 使用者刪一道，畫面上會有另一道
                // 莫名其妙被展開或被滑開。
                //
                // `id` 在同一份清單裡不會撞號：內建資料由 `FoodDataAudit.duplicateID`
                // 盯著（測試對真實 `foods.json` 斷言零問題），自訂與店家都是 UUID，
                // `FoodPicker` 抽樣時也是用 `id` 去重。
                //
                // 索引仍然要，但只拿來畫列與列之間的分隔線 —— 那是位置的事，不是身分的事。
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        // 分隔線縮排到圖示右緣，列與列才不會看起來像表格。
                        Divider()
                            .overlay(Theme.hairline(for: colorScheme))
                            .padding(.leading, Theme.space12 + 24 + Theme.space12)
                    }
                    FoodRow(
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
            }
            .background(
                Theme.card(for: colorScheme),
                in: RoundedRectangle(cornerRadius: Theme.radiusLarge)
            )
            // 一定要裁切：列左滑之後會往容器外跑，露出來的動作按鈕也會凸出右緣。
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusLarge)
                    .stroke(Theme.hairline(for: colorScheme), lineWidth: Theme.hairlineWidth)
            )

            if !items.isEmpty {
                Text("點一列看優缺點，右邊的 ⋯ 可以改名或把這輪不想吃的拿掉。轉盤會跟著更新。")
                    .font(Theme.micro)
                    .foregroundStyle(Theme.textSecondary(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

/// 左滑露出來的動作有多寬。
///
/// 位移與門檻的計算已經拿掉了 —— 那是自己仲裁手勢方向的時代留下的，
/// 現在方向交給巢狀 `ScrollView`（見 `FoodRow.body`），停的位置由
/// `scrollTargetBehavior` 決定，沒有需要自己算的數字。
enum RowSwipe {
    static let actionWidth: CGFloat = 96
}

/// 清單裡的一列。
struct FoodRow: View {
    let item: FoodItem
    let isWinner: Bool
    /// 剩兩道就不給刪了，轉盤至少要有兩格才轉得起來（產品規則）。
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
        // 左滑改用**巢狀的水平 `ScrollView`**，不再自己用 `DragGesture` 判斷方向。
        //
        // 上一版是 `.simultaneousGesture(DragGesture(minimumDistance: 12))` 加一個
        // 「橫向才接手」的 guard。那個 guard 擋的是「改不改狀態」，**不是「要不要參與
        // 手勢競技」** —— 手指移動 12pt 之後手勢就已經進場並把 `ScrollView` 的 pan 擋在外面，
        // guard 只是讓它什麼都不做，於是慢慢垂直拖就變成既不滑開也不捲動。
        // （快速 fling 時捲動先贏，所以那時候是好的 —— 這個 bug 只有慢速拖曳測得出來。）
        //
        // 換成水平 `ScrollView` 之後，方向仲裁交給 UIKit ——
        // 它本來就會依主要方向決定要給內層還是外層，那是原生滑動列的做法。
        // **這一塊我已經連錯三次手勢的掛法，不再自己仲裁。**
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                rowContent
                    // 佔滿一整個容器寬度，滑動距離才剛好是動作的寬度。
                    .containerRelativeFrame(.horizontal)

                if canDelete {
                    deleteAction
                }
            }
            .scrollTargetLayout()
        }
        // 對齊子元素的邊緣：只會停在「收合」與「完全露出動作」兩個位置。
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        // 剩兩道就不給拿掉（轉盤最少要留 2 格），這時候整列不該滑得動。
        .scrollDisabled(!canDelete)
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
        // 「以後都不要」是永久的，要問第二次。
        //
        // 它跟「這輪不要」同在一個 Menu、都是點一下，只有紅字之差 ——
        // 但一個換一組就回來，一個是從此不再出現。**`role: .destructive` 只改顏色，
        // 不改後果。** 手滑點錯下面那個，使用者未必知道去哪裡救。
        //
        // 「這輪不要」刻意**不加**確認：它可逆、而且是最常用的一個（左滑快捷就是為它做的），
        // 加確認等於把最常用的動作變慢，去換一個不存在的風險。
        .confirmationDialog(
            "以後都不要「\(item.name)」？",
            isPresented: $isConfirmingExclude,
            titleVisibility: .visible
        ) {
            Button("以後都不要", role: .destructive, action: onExcludeForever)
            Button("取消", role: .cancel) {}
        } message: {
            // 說明要講出**救回來的路徑** —— 永久性動作要讓人知道它不是不可逆的，
            // 這跟「放寬要老實說明」是同一條原則：後果要講出來。
            Text("這道菜不會再出現在轉盤上。可以在設定的「我的清單」裡改回來。")
        }
    }

    /// 列本體（含展開後的優缺點）。它是水平 ScrollView 的第一個子元素。
    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            row

            if isExpanded {
                details
                    .padding(.horizontal, Theme.space12)
                    .padding(.bottom, Theme.space12)
            }
        }
        .background(alignment: .leading) {
            // 中選的那道左側一條主色。比整列換底色安靜，但掃一眼就找得到。
            if isWinner {
                Theme.sauce(for: colorScheme)
                    .frame(width: 3)
            }
        }
        // 列本身要有不透明底，否則會透出後面的動作色塊。
        //
        // **形狀要明講 `Rectangle`。** 不給形狀的話 iOS 26 會讓它跟容器的圓角做同心處理，
        // 每一列的底都變成圓角矩形，列與列之間的凹處就露出後面的橘色 ——
        // 靜止狀態下整份清單右緣會排一整排小尖角。要圓角的是整個容器，不是每一列。
        .background(Theme.card(for: colorScheme), in: Rectangle())
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.22)) { isExpanded.toggle() }
        }
    }

    private var row: some View {
        HStack(spacing: Theme.space12) {
            // 跟轉盤同一套線稿圖示。清單裡的圖示是輔助資訊，不該比菜名重，所以走次要色。
            Image(item.icon.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(Theme.textSecondary(for: colorScheme))

            Text(item.name)
                .font(Theme.headline)
                .fontWeight(isWinner ? .semibold : .regular)
                .foregroundStyle(Theme.text(for: colorScheme))
                .lineLimit(1)

            Spacer(minLength: Theme.space8)

            // 分類文字換成角標 —— 同樣的資訊，但跟結果頁是同一個元件。
            TagBadge.cuisine(for: item, surface: colorScheme == .dark ? .dark : .light)
            TagBadge.form(for: item, surface: colorScheme == .dark ? .dark : .light)

            menu
        }
        .padding(.horizontal, Theme.space12)
        .frame(minHeight: 44)
    }

    /// 五個操作收進一個 `⋯`。密度提高之後三顆膠囊按鈕放不下。
    private var menu: some View {
        Menu {
            if !item.isPlace {
                Button("找附近有賣的店", systemImage: "mappin.and.ellipse") { showNearby = true }
            } else {
                Button("導航過去", systemImage: "arrow.triangle.turn.up.right.circle.fill", action: onOpenMaps)
            }
            if let phoneNumber {
                Button("打電話問（\(phoneNumber)）", systemImage: "phone.fill", action: onCall)
            }
            Button("改名", systemImage: "pencil") {
                draftName = item.name
                isRenaming = true
            }
            // 轉盤最少要留 2 格才轉得起來，所以剩兩道就不給拿掉。
            if canDelete {
                Button("這輪不要", systemImage: "minus.circle", action: onDelete)
            }
            // 店家每次搜尋 id 都不一樣，記不住「以後」，所以沒有這個選項。
            if !item.isPlace {
                Button("以後都不要", systemImage: "xmark.circle", role: .destructive) {
                    isConfirmingExclude = true
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary(for: colorScheme))
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
        }
    }

    /// 左滑露出來的「這輪不要」。
    ///
    /// 這是最常用的一個動作，每次都開 `⋯` Menu 太慢，所以給一個快捷。
    /// **可用條件跟 Menu 裡那一項共用同一個 `canDelete`** —— 轉盤最少要留 2 格。
    private var deleteAction: some View {
        // 用色塊 + 手勢而不是 `Button`：iOS 26 的按鈕即使 `.plain` 也會帶自己的形狀，
        // 露出來的動作會變成一塊圓角矩形浮在列上，貼不齊容器邊緣。
        Theme.negative(for: colorScheme)
            .frame(width: RowSwipe.actionWidth)
            .overlay {
                Image(systemName: "minus.circle")
                    .font(Theme.headline)
                    .foregroundStyle(colorScheme == .dark ? Theme.Dark.onSauce : Theme.Light.onSauce)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onDelete)
            .accessibilityElement()
            .accessibilityLabel("這輪不要")
            .accessibilityAddTraits(.isButton)
    }

    /// 點開之後在同一列下方長出優缺點，不做卡片轉場 —— 收合時整份清單維持高密度。
    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.space8) {
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
        }
        .padding(.leading, 24 + Theme.space12)
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
}
