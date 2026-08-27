import SwiftUI

/// 歷史與「我的清單」共用的一列。
///
/// 這兩頁的列結構幾乎一樣（emoji + 菜名 + 一行說明 + 角標 + 右側附加物），
/// 差別只有右邊掛什麼，所以是同一個元件而不是各寫一份 —— S4 的候選清單
/// 之所以會有「靜止態橘色尖角」那種問題，就是因為列的細節散在各處。
///
/// ## 左邊那一格畫 emoji 還是線稿
///
/// 規則只有一句：
///
/// > 我們可以換掉自己的樣式，不能換掉使用者的內容。
///
/// **S5-B 當初把這條規則套成「這兩頁一律保留 emoji」，那一步套錯了。**
/// 原本的理由寫著「那顆 emoji 可能是他自己在新增料理時挑的」——
/// 這對「我的清單」百分之百成立，對歷史頁卻不成立：歷史頁那顆 emoji 來自
/// `record.winner`，而中選的通常是內建料理，那顆 emoji 是 `foods.json` 裡
/// **我們自己寫的**，不是使用者挑的。
///
/// 所以規則沒有變，套法變了 —— **依據是「這是誰的東西」，不是「這是哪一頁」**：
///
/// | 頁面 | 內容是誰的 | 畫什麼 |
/// |---|---|---|
/// | 歷史 | 我們的資料（中選那一道） | 線稿 `FoodIcon` |
/// | 我的清單 | 使用者加的、使用者挑的 emoji | emoji |
///
/// （kuoyo 2026-08-21 指出歷史頁還是 emoji。原本的判斷與更正一起留在這裡，
/// 不然下一個人照舊稿又會把它改回去。）
///
/// 線稿負責的「類型」資訊在兩頁都另外由 `TagBadge` 用文字講，所以哪一種都不會少資訊。
/// 列左邊那一格畫什麼。
///
/// **放在 `DishListRow` 外面，不是巢狀在裡面。** 巢狀的話它會變成
/// `DishListRow<Trailing>.DishRowArt` —— 一個跟 `Trailing` 綁在一起的型別，
/// 於是 `Trailing` 從 `art:` 這個參數就推得出來，跟預設值是 `EmptyView` 的
/// `trailing:` 打架，編譯器會警告（而且未來的 Swift 版本會直接變成錯誤）。
/// 那個型別參數跟「左邊畫什麼」一點關係都沒有，本來就不該綁在一起。
///
/// 這跟 `DishListRowMetrics` 是同一個根：**不依賴 `Trailing` 的東西不要放進泛型型別裡。**
/// 那些常數 2026-08-27 一併搬出去了，所以現在這條規則在這個檔案裡是一致的 ——
/// 兩個不依賴 `Trailing` 的東西都在型別外面。
enum DishRowArt: Equatable {
    /// 使用者自己挑的 emoji。**不要替他換掉。**
    case emoji(String)
    /// 我們的線稿圖示，跟轉盤與候選清單同一套。
    case icon(FoodIcon)
}

/// 這兩頁的列幾何。
///
/// **放在 `DishListRow` 外面，跟 `DishRowArt` 同一個理由：不依賴 `Trailing` 的東西
/// 不要放進泛型型別裡。** 放在裡面的時候，光是要讀一個常數就得寫成
/// `DishListRow<EmptyView>.separatorInset` —— 隨便填一個跟這個數字毫無關係的型別參數，
/// 只為了把泛型型別具體化。`PROJECT_STATUS.md` 把那個讀法記成「彆扭」記了很久，
/// 但它跟 `DishRowArt` 當初那個「未來的 Swift 版本會是錯誤」的警告是**同一個根**。
///
/// 純幾何、跟畫面狀態無關，所以整個 enum 是 `nonisolated`：
/// `View` 是 `@MainActor`，型別裡的 static 屬性會跟著繼承那個隔離，而
/// `alignmentGuide` 的 closure 是 `@Sendable`（版面計算不保證在主執行緒），
/// 於是「從 Sendable closure 讀 main actor 屬性」會變成警告。
/// 真正的答案不是把 closure 搬到主執行緒，是**這兩個常數本來就不需要主執行緒**。
///
/// 搬出來之後也不必再是 computed —— 泛型型別不能有 static 儲存屬性，這個 enum 可以。
nonisolated enum DishListRowMetrics {
    /// 左邊那一格佔的寬度。分隔線的縮排要對齊它的右緣，所以是一個具名常數。
    ///
    /// **emoji 與線稿共用同一個寬度**，兩頁的分隔線縮排才會一致 ——
    /// 線稿本身只畫 24pt（跟候選清單同尺寸），置中放在這 32pt 的格子裡。
    static let artWidth: CGFloat = 32

    /// 線稿本身畫多大。跟候選清單那一份同尺寸。
    static let iconSize: CGFloat = 24

    /// 分隔線該縮排多少 —— 左內距 + 左邊那一格 + 兩者之間的間隔。
    static let separatorInset: CGFloat = Theme.space12 + artWidth + Theme.space12

    /// 一列最矮多高。56 而不是候選清單的 44：這裡的列有兩行（菜名 + 說明）。
    static let minHeight: CGFloat = 56
}

struct DishListRow<Trailing: View>: View {
    let art: DishRowArt
    let title: String
    /// 第二行。歷史頁放條件摘要，我的清單放分類。
    let subtitle: String?
    /// 角標的來源。歷史頁的舊紀錄解不開 JSON 時會是 `nil`，那就不顯示角標。
    let badgeSource: FoodItem?
    /// 要不要一併顯示吃法角標。歷史頁只顯示菜系（那一列右邊已經有時間與還原了）。
    let showsFormBadge: Bool
    @ViewBuilder let trailing: Trailing

    @Environment(\.colorScheme) private var colorScheme

    init(
        art: DishRowArt,
        title: String,
        subtitle: String?,
        badgeSource: FoodItem?,
        showsFormBadge: Bool,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.art = art
        self.title = title
        self.subtitle = subtitle
        self.badgeSource = badgeSource
        self.showsFormBadge = showsFormBadge
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Theme.space12) {
            leading

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
        .frame(minHeight: DishListRowMetrics.minHeight)
        .contentShape(Rectangle())
    }

    /// 左邊那一格。
    @ViewBuilder
    private var leading: some View {
        switch art {
        case .emoji(let emoji):
            Text(emoji)
                .font(.system(size: 28))
                .frame(width: DishListRowMetrics.artWidth)
        case .icon(let icon):
            // 走 `textSecondary` —— 這裡的圖示是輔助資訊，不該比菜名重
            //（跟 `FoodRow` 同一條）。
            Image(icon.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: DishListRowMetrics.iconSize, height: DishListRowMetrics.iconSize)
                .frame(width: DishListRowMetrics.artWidth)
                .foregroundStyle(Theme.textSecondary(for: colorScheme))
                // 類型資訊由旁邊的 `TagBadge` 用文字講，這裡不必再報一次。
                .accessibilityHidden(true)
        }
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
                DishListRowMetrics.separatorInset
            }
    }

    /// 這兩頁的頁面底色。`List` 預設會鋪系統的分組底色，要先關掉才看得到 token。
    func dishListBackground(for scheme: ColorScheme) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.pageBackground(for: scheme))
    }
}
