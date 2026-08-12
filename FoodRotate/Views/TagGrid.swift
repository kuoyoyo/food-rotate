import SwiftUI

/// 自動換行的排列。
///
/// 不用 `LazyVGrid`：它的欄寬是固定的，「台式」跟「麵包餅皮」會一樣寬，
/// 兩個字的標籤旁邊留一大片空白，34 個標籤就擠不進一屏。
/// 這裡每個 chip 用自己的寬度，排不下才換行。
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(within: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +)
            + verticalSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in rows(within: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(within maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + horizontalSpacing + size.width

            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// 一個可以點的標籤。
///
/// **未選的外觀跟 `TagBadge` 一樣，但刻意不共用那個元件。**
/// 角標是「這道菜有這個標籤」，chip 是「可以選這個標籤」—— 同一個東西的兩種身分。
/// `TagBadge` 沒有 `Capsule`、沒有選中態、也不吃點擊，硬要共用只會讓它長出三個旗標。
/// **共用的是顏色 token，不是元件。**
struct TagChip: View {
    let tag: FoodTag
    let isOn: Bool
    /// 這個 chip 是不是忌口。選中時用 `negative` 而不是 `sauce`。
    let isRestriction: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(tag.rawValue)
                .font(Theme.footnote)
                .foregroundStyle(foreground)
                .padding(.horizontal, Theme.space12)
                .padding(.vertical, 6)
                .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    /// 選中一律**實心填色**，不是染底。
    ///
    /// 染底在深色模式行不通：主色 `#D9674F` 提亮之後太靠近淺底，
    /// 同色文字疊上去實算 4.30／4.07／3.79（14%／18%／22%），愈染愈糟。
    /// 實心填色兩個模式同構造，只有墨色相反 —— 跟結果頁的主要按鈕是同一條規律。
    private var background: Color {
        guard isOn else { return Theme.hairline(for: colorScheme) }
        return isRestriction ? Theme.negative(for: colorScheme) : Theme.sauce(for: colorScheme)
    }

    private var foreground: Color {
        guard isOn else { return Theme.text(for: colorScheme) }
        // 選中的底一律是「主色級」的顏色，所以字走 onSauce 那一組墨色：
        // 淺色配淺字、深色配深字。
        return colorScheme == .dark ? Theme.Dark.onSauce : Theme.Light.onSauce
    }
}

/// 六個維度的標籤網格。**篩選器與新增料理表單共用同一個元件。**
struct TagGrid: View {
    @Binding var filter: FilterSelection
    /// 要顯示哪幾個維度。
    ///
    /// 「去哪吃」只給菜系 —— 其餘維度對地圖搜尋沒有作用，列出來卻不生效比不列更糟。
    /// 少五區不會讓版面塌掉，只是變短；**不要留空位或寫「此模式不適用」**，
    /// 那是把系統的限制攤給使用者看。
    let dimensions: [FoodTag.Dimension]

    /// 忌口區要不要加警示權重。
    ///
    /// **同一個標籤在兩個畫面的語意不同**：篩選器裡的「無牛」是使用者的限制，
    /// 是一條有後果、而且不會被自動放寬的規則；新增料理表單裡的「無牛」
    /// 是在描述這道菜不含牛。只有前者需要警示。
    let emphasizesRestriction: Bool

    /// 某個維度的標題要不要換句話說（「去哪吃」的菜系叫「搜尋關鍵字」）。
    var titleOverride: (FoodTag.Dimension) -> String? = { _ in nil }
    var noteOverride: (FoodTag.Dimension) -> String? = { _ in nil }
    let onChange: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space16) {
            ForEach(dimensions, id: \.self) { dimension in
                if emphasizesRestriction && dimension.isHardConstraint {
                    restrictionSection(dimension)
                } else {
                    section(dimension)
                }
            }
        }
    }

    /// 一般的一區：標題 + 自動換行的 chip。
    private func section(_ dimension: FoodTag.Dimension) -> some View {
        VStack(alignment: .leading, spacing: Theme.space8) {
            header(dimension, tint: Theme.textSecondary(for: colorScheme))
            chips(dimension)
        }
    }

    /// 忌口區：整區染色 + 警示標題。
    ///
    /// 「它不會被自動放寬」以前只靠標題旁一行小字，現在**從外觀就看得出來**：
    /// 整區有底、標題是警示色、選中的 chip 是實心 `negative`，跟其他五區完全不同。
    private func restrictionSection(_ dimension: FoodTag.Dimension) -> some View {
        VStack(alignment: .leading, spacing: Theme.space8) {
            header(dimension, tint: Theme.negative(for: colorScheme))
            chips(dimension)
        }
        .padding(Theme.space12)
        .background(
            Theme.noticeSurface(for: colorScheme),
            in: RoundedRectangle(cornerRadius: Theme.radiusLarge)
        )
        // 淺色的染色底跟頁底只差 1.08，沒有這條線看不出是一區。深色差 1.53，不需要。
        .overlay {
            if colorScheme != .dark {
                RoundedRectangle(cornerRadius: Theme.radiusLarge)
                    .stroke(Theme.Light.hairline, lineWidth: Theme.hairlineWidth)
            }
        }
    }

    private func header(_ dimension: FoodTag.Dimension, tint: Color) -> some View {
        HStack(spacing: Theme.space4) {
            Text(titleOverride(dimension) ?? dimension.rawValue)
                .font(Theme.caption)
                .foregroundStyle(tint)
            if let note = noteOverride(dimension) {
                Text(note)
                    .font(Theme.micro)
                    .foregroundStyle(tint)
            }
        }
    }

    private func chips(_ dimension: FoodTag.Dimension) -> some View {
        FlowLayout(horizontalSpacing: Theme.space8, verticalSpacing: Theme.space8) {
            ForEach(dimension.tags, id: \.self) { tag in
                TagChip(
                    tag: tag,
                    isOn: filter.tags.contains(tag),
                    isRestriction: dimension.isHardConstraint
                ) {
                    filter.toggle(tag)
                    Haptics.buttonTap()
                    onChange()
                }
            }
        }
    }
}
