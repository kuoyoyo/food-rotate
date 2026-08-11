import SwiftUI

/// 狀態提示分兩種，**用「有沒有顏色」分權重，不是用「哪個顏色」分**。
///
/// 以前五種提示長得一模一樣（同一個卡片、同樣的圖示＋標題＋說明），只有 tint 是橘或藍。
/// 但橘與藍是兩個**並列的顏色**，不是兩個層級 —— 使用者讀到的是「有五種不同顏色的提示」，
/// 不是「有兩種重要程度」。**拿掉顏色本身就是降權重**，比把藍換成灰更徹底。
///
/// 拆成兩個型別而不是一個加旗標，是因為它們的結構本來就不同（卡片 vs 單行）。
///
/// | | 要行動 | 資訊告知 |
/// |---|---|---|
/// | 容器 | 卡片，淺色另加 1px 邊框 | 無 |
/// | 顏色 | `negative` | 不上色，`textSecondary` |
/// | 結構 | 標題 + 說明 | 單行 |
/// | 高度 | 約 76pt | 約 20pt |

/// 要使用者做一件事的提示。目前只有兩種：找不到附近的店、沒有符合的料理。
///
/// **不新增紅色。** 這兩種都是「你要做一件事」，不是「出事了」；
/// 多一個紅色會變成三個層級，但實際上只有兩種該有的反應。
struct ActionNotice: View {
    let symbol: String
    let title: String
    let message: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: Theme.space12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.negative(for: colorScheme))
            VStack(alignment: .leading, spacing: Theme.space4) {
                Text(title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.negative(for: colorScheme))
                Text(message)
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.text(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.space12)
        .background(
            Theme.noticeSurface(for: colorScheme),
            in: RoundedRectangle(cornerRadius: Theme.radiusLarge)
        )
        // 淺色的卡底跟頁底只差 1.08，光靠底色看不出是一張卡，一定要這條線。
        // 深色差 1.20，看得出來，所以不畫。
        .overlay {
            if colorScheme != .dark {
                RoundedRectangle(cornerRadius: Theme.radiusLarge)
                    .stroke(Theme.Light.hairline, lineWidth: Theme.hairlineWidth)
            }
        }
    }
}

/// 只是告訴使用者發生了什麼的提示。單行、不上色、沒有容器。
///
/// **降權重不等於藏起來。** 產品規則要求「放寬條件時要老實說明放寬了哪個維度」，
/// 單行版本仍然寫明維度（「不夠 8 道，已放寬 菜系」）—— 規則要的是「說出來」，
/// 不是「大聲說」。
struct InfoNotice: View {
    let symbol: String
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.space4) {
            Image(systemName: symbol)
                .font(Theme.caption)
            Text(text)
                .font(Theme.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.textSecondary(for: colorScheme))
        .padding(.vertical, Theme.space8)
    }
}
