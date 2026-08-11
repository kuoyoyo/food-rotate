import SwiftUI

/// 選「想吃什麼樣的東西」的地方。
///
/// 取代原本的自由文字輸入框。以前打字是必要的——模型要讀那段話才知道要給什麼；
/// 現在篩選是查表，打字反而是負擔：手機上打「不要太油的午餐」很慢，
/// 而且打了「不油」以外的說法就篩不到。改成點標籤之後，選項是有限的、
/// 每一個都保證篩得出東西。
struct FilterBar: View {
    @Binding var filter: FilterSelection
    @Binding var slots: Int
    /// 這個模式用得到哪幾個維度。
    ///
    /// 「去哪吃」只吃菜系——地圖搜尋收得下「日式」，但「無牛」「便宜」「宵夜」
    /// 沒辦法對店家生效。列出去卻不起作用比不列出來更糟。
    let activeDimensions: [FoodTag.Dimension]
    /// 「去哪吃」才有的距離上限。nil 代表現在是「吃什麼」模式，不顯示。
    let radius: Binding<Double>?
    /// 標籤改變時呼叫。抽樣是瞬間的，所以點下去就重抽，不用等按鈕。
    let onChange: () -> Void
    /// 同樣條件換一組。
    let onReroll: () -> Void

    /// 六個維度攤開來要佔掉整個第一屏，轉盤會被擠到螢幕外。
    /// 轉盤才是這個 App 的主體，所以預設收起來，要調條件時才展開。
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryRow

            if isExpanded {
                ForEach(activeDimensions, id: \.self) { dimension in
                    dimensionRow(dimension)
                }

                if !filter.isEmpty {
                    Button {
                        filter.tags.removeAll()
                        Haptics.buttonTap()
                        onChange()
                    } label: {
                        Label("清除所有條件", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                if let radius {
                    radiusPicker(radius)
                }

                slotPicker
            }
        }
        .padding(.top, 8)
        .animation(.snappy(duration: 0.22), value: isExpanded)
    }

    /// 收起來時看得到的那一行：左邊說明目前的條件，右邊直接換一組。
    ///
    /// 條件摘要不能省成一個「篩選」按鈕——收起來之後，使用者要有辦法知道
    /// 現在的轉盤是在什麼條件下抽出來的，否則會以為 App 隨便給。
    private var summaryRow: some View {
        HStack(spacing: 10) {
            Button {
                isExpanded.toggle()
                Haptics.buttonTap()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle\(filter.isEmpty ? "" : ".fill")")
                    Text(filter.isEmpty ? "選條件" : filter.summary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    filter.isEmpty ? Color(.secondarySystemGroupedBackground) : Color.accentColor.opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(filter.isEmpty ? Color.primary : Color.accentColor)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button(action: onReroll) {
                Label("換一組", systemImage: "dice")
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 3)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
    }

    /// 一個維度一列，橫向捲動。
    ///
    /// 忌口那一列的標題多一句說明，因為它跟其他列的行為不一樣：
    /// 其他列湊不滿格時會自動放寬，忌口不會。使用者要知道這個差別。
    private func dimensionRow(_ dimension: FoodTag.Dimension) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(dimension.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if dimension.isHardConstraint {
                    Text("一定不會出現")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(dimension.tags, id: \.self) { tag in
                        chip(tag)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()
        }
    }

    private func chip(_ tag: FoodTag) -> some View {
        let isOn = filter.tags.contains(tag)
        return Button {
            filter.toggle(tag)
            Haptics.buttonTap()
            onChange()
        } label: {
            Text(tag.rawValue)
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isOn ? Color.accentColor.opacity(0.18) : Color(.secondarySystemGroupedBackground),
                    in: Capsule()
                )
                .foregroundStyle(isOn ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    /// 找多遠以內的店。只有「去哪吃」看得到。
    private func radiusPicker(_ radius: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Label("找多遠", systemImage: "location.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            Picker("找多遠", selection: radius) {
                ForEach(SearchRadius.allowed, id: \.self) { meters in
                    Text(SearchRadius.label(meters)).tag(meters)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // 改了距離就要重找，不然畫面上的數字跟盤上的店對不起來。
            .onChange(of: radius.wrappedValue) { onChange() }
        }
    }

    /// 轉盤格數。
    private var slotPicker: some View {
        HStack(spacing: 10) {
            Label("轉盤格數", systemImage: "circle.hexagongrid")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            Picker("轉盤格數", selection: $slots) {
                ForEach(WheelCapacity.allowedSlots, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
