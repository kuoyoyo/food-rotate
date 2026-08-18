import SwiftUI

/// 歷史與「我的清單」共用的一列。
///
/// 這兩頁的列結構幾乎一樣（emoji + 菜名 + 一行說明 + 角標 + 右側附加物），
/// 差別只有右邊掛什麼，所以是同一個元件而不是各寫一份 —— S4 的候選清單
/// 之所以會有「靜止態橘色尖角」那種問題，就是因為列的細節散在各處。
///
/// **emoji 保留，不換成線稿圖示。** 這兩頁顯示的是使用者做過的事、加過的東西，
/// 那顆 emoji 可能是他自己在新增料理時挑的。轉盤與候選清單換成線稿是對的，
/// 因為那裡顯示的是內建資料的分類。
///
/// > 我們可以換掉自己的樣式，不能換掉使用者的內容。
///
/// 線稿圖示原本負責傳達的「類型」改用 `TagBadge` 用文字講，資訊一點都沒有少。
struct DishListRow<Trailing: View>: View {
    let emoji: String
    let title: String
    /// 第二行。歷史頁放條件摘要，我的清單放分類。
    let subtitle: String?
    /// 角標的來源。歷史頁的舊紀錄解不開 JSON 時會是 `nil`，那就不顯示角標。
    let badgeSource: FoodItem?
    /// 要不要一併顯示吃法角標。歷史頁只顯示菜系（那一列右邊已經有時間與還原了）。
    let showsFormBadge: Bool
    @ViewBuilder let trailing: Trailing

    @Environment(\.colorScheme) private var colorScheme

    // 這兩個是**純幾何數字**，跟畫面狀態無關，所以標 `nonisolated`。
    //
    // `View` 是 `@MainActor`，型別裡的 static 屬性會跟著繼承那個隔離；
    // 但 `alignmentGuide` 的 closure 是 `@Sendable`（版面計算不保證在主執行緒），
    // 於是「從 Sendable closure 讀 main actor 屬性」變成警告。
    // 真正的答案不是把 closure 搬到主執行緒，是**這兩個常數本來就不需要主執行緒**。
    //
    // 之所以是 computed 而不是 `static let`：泛型型別不能有 static 儲存屬性。

    /// emoji 佔的寬度。分隔線的縮排要對齊它的右緣，所以是一個具名常數。
    nonisolated static var emojiWidth: CGFloat { 32 }
    /// 分隔線該縮排多少 —— 左內距 + emoji + 兩者之間的間隔。
    nonisolated static var separatorInset: CGFloat { Theme.space12 + emojiWidth + Theme.space12 }

    init(
        emoji: String,
        title: String,
        subtitle: String?,
        badgeSource: FoodItem?,
        showsFormBadge: Bool,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
        self.badgeSource = badgeSource
        self.showsFormBadge = showsFormBadge
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Theme.space12) {
            Text(emoji)
                .font(.system(size: 28))
                .frame(width: Self.emojiWidth)

            VStack(alignment: .leading, spacing: Theme.space2) {
                HStack(spacing: Theme.space4) {
                    Text(title)
                        .font(Theme.headline)
                        .foregroundStyle(Theme.text(for: colorScheme))
                        .lineLimit(1)

                    badges
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.textSecondary(for: colorScheme))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.space8)

            trailing
        }
        .padding(.horizontal, Theme.space12)
        // 56 而不是候選清單的 44：這裡的列有兩行（菜名 + 說明）。
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var badges: some View {
        if let item = badgeSource {
            let surface: TagBadge.Surface = colorScheme == .dark ? .dark : .light
            TagBadge.cuisine(for: item, surface: surface)
            if showsFormBadge {
                TagBadge.form(for: item, surface: surface)
            }
        }
    }
}

extension View {
    /// 把一列套上這兩頁共用的列外觀：卡片底、縮排到 emoji 右緣的分隔線。
    ///
    /// **這兩頁仍然是 `List`。** 換成自製容器就會失去 `.onDelete` 的左滑刪除
    /// （歷史的刪除紀錄、我的清單的移除自訂料理），那是**行為**，S5 的紅線是
    /// 「套 token 不等於改行為」。所以底色與分隔線走 `List` 自己的接口。
    func dishListRowStyle(for scheme: ColorScheme) -> some View {
        self
            .listRowBackground(Theme.card(for: scheme))
            // 內距歸列自己管，`DishListRow` 已經有 space12。
            .listRowInsets(EdgeInsets())
            .listRowSeparatorTint(Theme.hairline(for: scheme))
            .alignmentGuide(.listRowSeparatorLeading) { _ in
                DishListRow<EmptyView>.separatorInset
            }
    }

    /// 這兩頁的頁面底色。`List` 預設會鋪系統的分組底色，要先關掉才看得到 token。
    func dishListBackground(for scheme: ColorScheme) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.pageBackground(for: scheme))
    }
}
