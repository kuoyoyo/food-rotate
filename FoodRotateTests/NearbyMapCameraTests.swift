import CoreLocation
import MapKit
import Testing

@testable import FoodRotate

/// 地圖視窗要框得住結果（S6 P2-2）。
///
/// 搜尋接受使用者選的上限（最遠 10 公里）內的店，但地圖視窗永遠是 2,500 公尺見方 ——
/// **超出那一圈的店，圖釘在畫面外。** 清單上看得到、地圖上找不到，
/// 使用者會以為地圖壞了。
@Suite("地圖視窗")
struct NearbyMapCameraTests {

    private static let taipei = CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)

    /// 從台北車站往北 `meters` 公尺的一家店。
    private static func place(northOf origin: CLLocationCoordinate2D, meters: Double) -> NearbyPlace {
        let degreesPerMeter = 1.0 / 111_000.0
        return NearbyPlace(
            name: "\(Int(meters)) 公尺外",
            address: "",
            coordinate: CLLocationCoordinate2D(
                latitude: origin.latitude + meters * degreesPerMeter,
                longitude: origin.longitude
            ),
            distance: meters,
            phoneNumber: nil,
            website: nil,
            categoryName: nil
        )
    }

    /// 這個座標在視窗裡面嗎。
    private static func contains(_ region: MKCoordinateRegion, _ point: CLLocationCoordinate2D) -> Bool {
        let halfLat = region.span.latitudeDelta / 2
        let halfLon = region.span.longitudeDelta / 2
        return abs(point.latitude - region.center.latitude) <= halfLat
            && abs(point.longitude - region.center.longitude) <= halfLon
    }

    @Test("最遠的店也要在視窗裡")
    func 最遠的店也框得住() {
        let places = [
            Self.place(northOf: Self.taipei, meters: 300),
            Self.place(northOf: Self.taipei, meters: 8_000),
        ]

        let region = NearbyMapCamera.region(around: Self.taipei, covering: places)

        for place in places {
            #expect(Self.contains(region, place.coordinate), "\(place.name) 落在視窗外")
        }
        #expect(Self.contains(region, Self.taipei), "使用者自己的位置也要在視窗裡")
    }

    @Test("店都很近的時候不要縮太小，也不要放大到看不出街廓")
    func 店很近時視窗不會過小() {
        let places = [Self.place(northOf: Self.taipei, meters: 120)]

        let region = NearbyMapCamera.region(around: Self.taipei, covering: places)
        let latMeters = region.span.latitudeDelta * 111_000

        #expect(latMeters >= 500, "太小的視窗會貼在圖釘上，看不出位置關係")
        #expect(latMeters <= 3_000)
    }

    @Test("一家店都沒有的時候仍然給得出一個以使用者為中心的視窗")
    func 沒有結果時仍有視窗() {
        let region = NearbyMapCamera.region(around: Self.taipei, covering: [])

        #expect(region.center.latitude == Self.taipei.latitude)
        #expect(region.span.latitudeDelta > 0)
    }
}
