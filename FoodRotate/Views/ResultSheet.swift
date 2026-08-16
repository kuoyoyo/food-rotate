import SwiftUI

/// 轉出結果後疊上來的結果頁。
///
/// **固定深色，不跟隨系統 colorScheme。** 這是一個慶祝的瞬間，不是一個深色模式 ——
/// 它的作用是讓中選的菜在壓暗的背景上浮起來，看完就關掉。
/// 所以這個檔案裡不會出現 `@Environment(\.colorScheme)`，配色一律走下面的 `Ink`。
/// （使用者本來就在深色模式時反差會變小，那是可接受的：那時整個 App 都是深的，
/// 慶祝感由中選高亮與轉場承擔，不靠明暗差。）
///
/// 它開出去的「附近的店」**維持淺色** —— 那是要停留、讀地址、看地圖的工作畫面，
/// 一起做深等於做了半套深色模式。
struct ResultSheet: View {
    let winner: FoodItem
    /// 店家的電話。有的話給一顆可以直接撥的按鈕——
    /// MapKit 給不出營業時間，想確認有沒有開，打過去問最快。
    let phoneNumber: String?
    /// 抽到的是店家時，直接導航過去。
    let onOpenMaps: () -> Void
    let onCall: () -> Void
    /// 關掉結果頁。overlay 沒有系統的 `dismiss`，由外面決定怎麼收。
    let onDismiss: () -> Void

    /// 中選圖示轉場用。`nil` 代表這一次不做轉場（`reduceMotion`）。
    var transition: HeroTransition?

    /// 下拉關閉的進度 0...1，給外面的壓暗層跟著回亮。
    @Binding var dragProgress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showNearby = false
    @State private var dragOffset: CGFloat = 0
    /// 內容有沒有捲在最頂。捲到頂之後再往下拉才是「要關掉」，否則那是在捲內容。
    @State private var scrollAtTop = true
    @AccessibilityFocusState private var nameFocused: Bool

    /// 固定深色的配色。
    ///
    /// 收成一個具名的組，是為了讓「這裡是刻意寫死深色」在程式碼上看得出來 ——
    /// 直接散落地寫 `Theme.Dark.xxx` 的話，下一個人很容易「順手」接上系統 colorScheme。
    private enum Ink {
        static let page = Theme.Dark.pageBackground
        static let card = Theme.Dark.card
        static let text = Theme.Dark.text
        static let secondary = Theme.Dark.textSecondary
        static let sauce = Theme.Dark.sauce
        /// 主色按鈕上的字。**深墨不是白**：白字疊在提亮後的主色上只有 3.50。
        static let onSauce = Theme.Dark.onSauce
        static let positive = Theme.Dark.positive
        static let negative = Theme.Dark.negative
        static let grabber = Theme.Dark.grabber
        /// 次要按鈕的外框。
        static let hairline = Theme.Dark.hairline
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content
        }
        .background(Ink.page)
        // 下緣不做圓角：它貼齊螢幕底，做了會露出後面的轉盤。
        .clipShape(.rect(topLeadingRadius: Theme.radiusSheet, topTrailingRadius: Theme.radiusSheet))
        .offset(y: dragOffset)
        .gesture(dragToDismiss)
        .sheet(isPresented: $showNearby) {
            // 「附近的店」維持淺色，不繼承這裡的深色。
            NearbyRestaurantsView(dish: winner.name)
        }
        .onAppear { nameFocused = true }
    }

    // MARK: - 標題列

    /// 44pt 的標題列：把手置中、「完成」靠右、左邊留空。
    ///
    /// **不做導覽列也不放標題。** 畫面正中央就是一個 34pt 的菜名，
    /// 上面再寫一次「轉盤結果」是重複的；把手本身已經表達了「這是可以往下關掉的東西」。
    private var titleBar: some View {
        ZStack {
            Capsule()
                .fill(Ink.grabber)
                .frame(width: 36, height: 5)
                .padding(.top, Theme.space8)
                .frame(maxHeight: .infinity, alignment: .top)
                .accessibilityElement()
                .accessibilityLabel("往下拖曳可關閉")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.escape, onDismiss)

            HStack {
                Spacer()
                Button("完成", action: onDismiss)
                    .font(Theme.headline)
                    .foregroundStyle(Ink.sauce)
                    // 觸控範圍至少 44×44，純文字按鈕的字寬不夠。
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.trailing, Theme.space12)
            }
        }
        .frame(height: 44)
    }

    // MARK: - 內容

    private var content: some View {
        ScrollView {
            VStack(spacing: Theme.space24) {
                hero

                VStack(spacing: Theme.space16) {
                    pointSection(
                        // 店家借用同一個型別，`pros` 裡放的是地址（見 NearbyPlace.asFoodItem）。
                        title: winner.isPlace ? "在哪裡" : "為什麼可以吃",
                        symbol: "checkmark.circle.fill",
                        tint: Ink.positive,
                        points: winner.pros
                    )
                    pointSection(
                        title: "要注意的地方",
                        symbol: "exclamationmark.triangle.fill",
                        tint: Ink.negative,
                        points: winner.cons
                    )
                }

                actions

                // 這一頁固定深色，所以要明講 —— 不然版權那三行會跟著系統走，
                // 在淺色模式下變成淺色模式的文字色疊在深卡片上。
                CopyrightFooter(fixedScheme: .dark)
            }
            .padding(.horizontal, Theme.space20)
            .padding(.bottom, Theme.space32)
        }
        // 捲到頂之後再往下拉才是關閉，所以要知道現在在不在頂。
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y <= geometry.contentInsets.top + 1
        } action: { _, isAtTop in
            scrollAtTop = isAtTop
        }
        // 已經開始往下拖了就別再捲，否則兩個手勢會同時吃同一個方向。
        .scrollDisabled(dragOffset > 0)
    }

    private var hero: some View {
        VStack(spacing: Theme.space8) {
            heroIcon

            Text(winner.isPlace ? "今天就去" : "今天就吃")
                .font(Theme.subheadline)
                .foregroundStyle(Ink.secondary)

            Text(winner.name)
                .font(Theme.display)
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
                // 結果頁一出現就把 VoiceOver 的焦點搶到菜名上。
                // 預設焦點會落在最上面的圖示，那是「哪一類」不是「哪一道」——
                // 使用者等的是答案，不該還要往下滑一格才聽到。
                .accessibilityFocused($nameFocused)

            badges
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.space24)
        // hero 也要吃下拉關閉（規格四-2：標題列 + hero 區）。
        //
        // 必須是 `simultaneousGesture`：hero 在 `ScrollView` 裡面，
        // 掛在 sheet 根部的那個 `.gesture` 會被捲動手勢吃掉 —— 標題列在 ScrollView
        // 外面所以沒事，hero 在裡面就拖不動了（PM 實測 405pt 沒關）。
        .simultaneousGesture(dragToDismiss)
    }

    /// hero 圖示。用 S2 的吃法圖示而不是 emoji —— 它是中選轉場的主角，
    /// 必須跟轉盤上那一格是同一個東西。
    @ViewBuilder
    private var heroIcon: some View {
        let icon = Image(winner.icon.assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 76, height: 76)
            .foregroundStyle(Ink.sauce)
            // 它表達的類型資訊，下面的角標已經用文字講了。
            .accessibilityHidden(true)

        if let transition {
            // hero 是 source：它決定最終的位置與 76pt 尺寸，轉盤那顆跟著它飛過來。
            icon.matchedGeometryEffect(id: transition.id, in: transition.namespace, isSource: true)
        } else {
            icon
        }
    }

    /// 菜系 + 吃法兩個角標。hero 的圖示只表達吃法而且是圖形，配文字讓它明確。
    /// 沒有對應標籤的那個就不顯示 —— 不要顯示「未分類」，那是把資料缺口攤給使用者看。
    private var badges: some View {
        HStack(spacing: Theme.space8) {
            TagBadge.cuisine(for: winner, surface: .dark)
            TagBadge.form(for: winner, surface: .dark)
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.space12) {
            // 抽到的已經是一家店，就不用再搜一次「哪裡有賣這家店」了。
            Button {
                if winner.isPlace { onOpenMaps() } else { showNearby = true }
            } label: {
                Label(
                    winner.isPlace ? "導航過去" : "找附近有賣的店",
                    systemImage: winner.isPlace ? "arrow.triangle.turn.up.right.circle.fill" : "mappin.and.ellipse"
                )
                .font(Theme.headline)
                // 深墨字。白字在提亮後的主色上只有 3.50，不合格。不要改回白字。
                .foregroundStyle(Ink.onSauce)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.space12)
                .background(Ink.sauce, in: Capsule())
            }
            .buttonStyle(.plain)

            // MapKit 查不到營業時間，所以不假裝知道。給一顆電話按鈕，
            // 想確認有沒有開、要不要訂位，打過去問是最直接的辦法。
            if let phoneNumber {
                Button(action: onCall) {
                    Label("打電話問（\(phoneNumber)）", systemImage: "phone.fill")
                        .font(Theme.subheadline)
                        .foregroundStyle(Ink.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.space8)
                        .overlay(Capsule().stroke(Ink.hairline, lineWidth: Theme.hairlineWidth))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func pointSection(title: String, symbol: String, tint: Color, points: [String]) -> some View {
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: Theme.space8) {
                Label(title, systemImage: symbol)
                    .font(Theme.headline)
                    .foregroundStyle(tint)

                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .top, spacing: Theme.space8) {
                        Circle()
                            .fill(tint.opacity(0.5))
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(point)
                            .font(Theme.body)
                            .foregroundStyle(Ink.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.space16)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
        }
    }

    // MARK: - 下拉關閉

    /// 系統 sheet 免費給的那個手勢，換成 overlay 之後要自己做。
    ///
    /// 分區的理由：捲動與關閉搶同一個方向。**內容捲到頂之後再往下拉才是要關掉**，
    /// 在中間往下拉是在捲內容。
    private var dragToDismiss: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // 已經在拖了就繼續，避免拖到一半內容回彈導致中斷。
                guard scrollAtTop || dragOffset > 0 else { return }
                dragOffset = Self.resisted(value.translation.height)
                dragProgress = Self.progress(for: dragOffset)
            }
            .onEnded { value in
                let shouldDismiss = dragOffset >= Self.dismissDistance
                    || value.predictedEndTranslation.height - value.translation.height >= Self.dismissVelocity * 0.1

                guard shouldDismiss else {
                    // 沒到門檻就彈回原位。
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        dragOffset = 0
                        dragProgress = 0
                    }
                    return
                }
                onDismiss()
            }
    }

    /// 向上拖曳的阻尼。拖 100pt 只移動 25pt —— 讓人知道到頂了，但不硬擋。
    private static func resisted(_ translation: CGFloat) -> CGFloat {
        translation >= 0 ? translation : translation * 0.25
    }

    /// 壓暗層的回亮進度。
    ///
    /// 除數 240 跟關閉門檻 120 **刻意不同**：拖到門檻的時候背景剛好回亮一半，
    /// 那是「再拉一點就會關」的視覺提示。
    private static func progress(for offset: CGFloat) -> Double {
        min(max(Double(offset) / 240, 0), 1)
    }

    /// 位移到這裡就關。
    private static let dismissDistance: CGFloat = 120
    /// 或者放手瞬間夠快也關 —— 讓「快速甩掉」不必拖滿。
    private static let dismissVelocity: CGFloat = 800
}
