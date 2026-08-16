import MapKit
import SwiftUI

/// 找附近有沒有賣這道菜的店。地圖與清單並陳，點清單可以直接開 Apple 地圖導航。
///
/// **只套色，不改版面。** 這一頁的主體是 `Map`，那是系統元件，我們控制不了也不該控制；
/// 周邊套 token 讓它不突兀就夠了。在一個以地圖為主的畫面上做視覺主張得不到什麼。
///
/// **維持淺色**（S3 已裁定）：這是要停留、讀地址、看地圖的工作畫面，
/// 跟著結果頁一起做深等於做了半套深色模式。所以這個檔案跟 `ResultSheet` 一樣
/// 不接 `@Environment(\.colorScheme)`，配色一律走 `Ink`。
struct NearbyRestaurantsView: View {
    let dish: String

    /// 固定淺色的配色。收成具名的組，是為了讓「這裡是刻意寫死淺色」看得出來。
    private enum Ink {
        static let page = Theme.Light.pageBackground
        static let card = Theme.Light.card
        static let text = Theme.Light.text
        static let secondary = Theme.Light.textSecondary
        static let sauce = Theme.Light.sauce
    }

    @Environment(\.dismiss) private var dismiss
    @State private var settings = AppSettings.shared
    @State private var model = NearbySearchModel()
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .idle, .locating:
                    progress(text: "正在取得你的位置…")
                case .searching:
                    progress(text: "正在找附近的「\(dish)」…")
                case .failed(let message):
                    failure(message)
                case .results(let places):
                    content(places)
                }
            }
            .navigationTitle("附近的\(dish)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
        // **整個 sheet 釘成淺色，不只頁面內容。**
        //
        // 只把內容套成淺色的話，導覽列的標題與「關閉」仍然跟著系統走 ——
        // 深色模式下就變成白色標題疊在淺色頁面上（實測對比 1.1，幾乎看不見）。
        // 系統深色時原本的 `systemGroupedBackground` 也是深的，所以以前沒事；
        // 是「固定淺色」這個決定本身要求連導覽列一起釘。
        .preferredColorScheme(.light)
        .task {
            model.search(dish: dish)
        }
        .onDisappear {
            model.stop()
        }
    }

    // MARK: 狀態

    private func progress(text: String) -> some View {
        VStack(spacing: Theme.space12) {
            ProgressView()
                .controlSize(.large)
            Text(text)
                .font(Theme.subheadline)
                .foregroundStyle(Ink.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.page)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: Theme.space16) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 42))
                .foregroundStyle(Ink.secondary)
            Text(message)
                .font(Theme.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Ink.secondary)
                .padding(.horizontal, Theme.space32)
            Button("再試一次") {
                model.search(dish: dish)
            }
            .font(Theme.headline)
            .foregroundStyle(Ink.sauce)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Ink.sauce)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.page)
    }

    private func content(_ places: [NearbyPlace]) -> some View {
        VStack(spacing: 0) {
            Map(position: $camera) {
                UserAnnotation()
                ForEach(places) { place in
                    Marker(place.name, systemImage: "fork.knife", coordinate: place.coordinate)
                        .tint(Ink.sauce)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .frame(height: 260)

            List(places) { place in
                Button {
                    NearbySearchModel.openInMaps(place)
                } label: {

                    HStack(spacing: Theme.space12) {
                        VStack(alignment: .leading, spacing: Theme.space2) {
                            Text(place.name)
                                .font(Theme.headline)
                                .foregroundStyle(Ink.text)
                            if !place.address.isEmpty {
                                Text(place.address)
                                    .font(Theme.footnote)
                                    .foregroundStyle(Ink.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: Theme.space8)
                        VStack(alignment: .trailing, spacing: Theme.space2) {
                            Text(place.distanceText)
                                .font(Theme.caption)
                                .foregroundStyle(Ink.sauce)
                            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                .foregroundStyle(Ink.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Ink.card)
                .listRowSeparatorTint(Theme.Light.hairline)
                // 長按換另一個地圖 App。多數時候用偏好的那個就好，
                // 但偶爾會想用另一個（某家店只有 Google 有評論），
                // 為了那一次跑一趟設定頁太麻煩。
                .contextMenu {
                    Button("用 \(settings.preferredMapApp.other.displayName) 開啟", systemImage: "map") {
                        NearbySearchModel.openInMaps(place, using: settings.preferredMapApp.other)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Ink.card)
        }
        .onAppear {
            guard let coordinate = model.userCoordinate else { return }
            camera = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 2500,
                    longitudinalMeters: 2500
                )
            )
        }
    }
}
