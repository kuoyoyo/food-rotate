import Foundation
import Testing

@testable import FoodRotate

/// 距離文案（S6 P2-1）。
///
/// `NearbySearch.swift` 有兩處把「十五公里」寫死在錯誤訊息裡，但實際上限
/// 來自設定（1／3／5／10 公里，預設 5）。使用者選了 1 公里、搜不到，
/// 畫面卻說「附近十五公里內找不到」—— **那是在講一個不是事實的數字。**
///
/// 諷刺的是同一個檔案的註解自己寫著「一度寫死十五公里，但那對『現在要去吃飯』
/// 來說太遠了」。**決定改了，文案沒跟著改。**
///
/// 所以這裡釘的是：所有講到距離的字，只能有一個來源。
@Suite("距離文案")
@MainActor
struct SearchRadiusCopyTests {

    @Test("四種半徑各自講出自己的數字", arguments: SearchRadius.allowed)
    func 文案跟著設定走(_ radius: Double) {
        let expected = SearchRadius.label(radius)

        let empty = NearbySearchModel.noRestaurantsMessage(radius: radius)
        let noDish = NearbySearchModel.noPlacesSellingMessage(dish: "牛肉麵", radius: radius)

        #expect(empty.contains(expected), "找不到餐廳的訊息要講出真正的上限")
        #expect(noDish.contains(expected), "找不到這道菜的訊息要講出真正的上限")
        #expect(empty.contains("十五公里") == false)
        #expect(noDish.contains("十五公里") == false)
    }

    @Test("1 公里與 10 公里講的不是同一句話")
    func 不同半徑的文案不同() {
        let near = NearbySearchModel.noRestaurantsMessage(radius: 1_000)
        let far = NearbySearchModel.noRestaurantsMessage(radius: 10_000)

        #expect(near != far)
        #expect(near.contains("1 公里"))
        #expect(far.contains("10 公里"))
    }
}
