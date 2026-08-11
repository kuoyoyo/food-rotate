import MapKit
import SwiftUI

/// 找附近有沒有賣這道菜的店。地圖與清單並陳，點清單可以直接開 Apple 地圖導航。
struct NearbyRestaurantsView: View {
    let dish: String

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
        .task {
            model.search(dish: dish)
        }
        .onDisappear {
            model.stop()
        }
    }

    // MARK: 狀態

    private func progress(text: String) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("再試一次") {
                model.search(dish: dish)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func content(_ places: [NearbyPlace]) -> some View {
        VStack(spacing: 0) {
            Map(position: $camera) {
                UserAnnotation()
                ForEach(places) { place in
                    Marker(place.name, systemImage: "fork.knife", coordinate: place.coordinate)
                        .tint(Color.accentColor)
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

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            if !place.address.isEmpty {
                                Text(place.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(place.distanceText)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
