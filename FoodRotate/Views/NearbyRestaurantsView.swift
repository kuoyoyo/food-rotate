import MapKit
import SwiftUI

/// 地圖視窗要框住哪一塊。
/// **視窗要框住所有結果，不是一個固定的圈。**
///
/// 以前永遠是 2,500 公尺見方，但搜尋接受的是使用者選的上限（最遠 10 公里）——
/// 超出那一圈的店，圖釘落在畫面外：清單上看得到、地圖上找不到（S6 P2-2）。
enum NearbyMapCamera {
    /// 視窗最小邊長。店都很近的時候不要貼到圖釘上，那樣看不出位置關係。
    static let minimumSpan: CLLocationDistance = 900
    /// 邊緣留白。圖釘剛好貼在框線上會被地圖控制項蓋掉。
    static let padding = 1.35

    static func region(
        around user: CLLocationCoordinate2D,
        covering places: [NearbyPlace]
    ) -> MKCoordinateRegion {
        // 使用者自己也要在框裡 —— 不然「附近」這兩個字沒有參照點。
        let latitudes = [user.latitude] + places.map(\.coordinate.latitude)
        let longitudes = [user.longitude] + places.map(\.coordinate.longitude)

        let minLatitude = latitudes.min() ?? user.latitude
        let maxLatitude = latitudes.max() ?? user.latitude
        let minLongitude = longitudes.min() ?? user.longitude
        let maxLongitude = longitudes.max() ?? user.longitude

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )

        let metersPerDegreeLatitude = 111_000.0
        // 經度一度的距離隨緯度收縮，高緯度不修正的話東西向會框得太寬。
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(center.latitude * .pi / 180)

        let latitudeMeters = (maxLatitude - minLatitude) * metersPerDegreeLatitude * padding
        let longitudeMeters = (maxLongitude - minLongitude) * metersPerDegreeLongitude * padding

        return MKCoordinateRegion(
            center: center,
            latitudinalMeters: max(latitudeMeters, minimumSpan),
            longitudinalMeters: max(longitudeMeters, minimumSpan)
        )
    }
}

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

    private func focus(on places: [NearbyPlace]) {
        guard let coordinate = model.userCoordinate else { return }
        camera = .region(NearbyMapCamera.region(around: coordinate, covering: places))
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
        .onAppear { focus(on: places) }
        // **結果換了視窗也要跟著換。** 只靠 `onAppear` 的話，重搜之後
        // 框的還是上一批店的範圍。
        .onChange(of: places.map(\.id)) { _, _ in focus(on: places) }
    }
}
