import SwiftUI

/// 轉出結果後彈出的結果頁，包含完整優缺點與地圖入口。
struct ResultSheet: View {
    let winner: FoodItem
    /// 店家的電話。有的話給一顆可以直接撥的按鈕——
    /// MapKit 給不出營業時間，想確認有沒有開，打過去問最快。
    let phoneNumber: String?
    /// 抽到的是店家時，直接導航過去。
    let onOpenMaps: () -> Void
    let onCall: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showNearby = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    hero

                    VStack(spacing: 14) {
                        pointSection(
                            // 店家借用同一個型別，`pros` 裡放的是地址（見 NearbyPlace.asFoodItem）。
                            title: winner.isPlace ? "在哪裡" : "為什麼可以吃",
                            symbol: "checkmark.circle.fill",
                            tint: .green,
                            points: winner.pros
                        )
                        pointSection(
                            title: "要注意的地方",
                            symbol: "exclamationmark.triangle.fill",
                            tint: .orange,
                            points: winner.cons
                        )
                    }

                    // 抽到的已經是一家店，就不用再搜一次「哪裡有賣這家店」了。
                    Button {
                        if winner.isPlace { onOpenMaps() } else { showNearby = true }
                    } label: {
                        Label(
                            winner.isPlace ? "導航過去" : "找附近有賣的店",
                            systemImage: winner.isPlace ? "arrow.triangle.turn.up.right.circle.fill" : "mappin.and.ellipse"
                        )
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)

                    // MapKit 查不到營業時間，所以不假裝知道。給一顆電話按鈕，
                    // 想確認有沒有開、要不要訂位，打過去問是最直接的辦法。
                    if let phoneNumber {
                        Button(action: onCall) {
                            Label("打電話問（\(phoneNumber)）", systemImage: "phone.fill")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }

                    CopyrightFooter()
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("轉盤結果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showNearby) {
                NearbyRestaurantsView(dish: winner.name)
            }
        }
        .presentationDetents([.large])
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Text(winner.displayEmoji)
                .font(.system(size: 76))
            Text(winner.isPlace ? "今天就去" : "今天就吃")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(winner.name)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text(winner.category)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
                .foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func pointSection(title: String, symbol: String, tint: Color, points: [String]) -> some View {
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)

                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(tint.opacity(0.5))
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(point)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
