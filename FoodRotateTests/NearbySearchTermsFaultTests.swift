import CoreLocation
import Foundation
import MapKit
import Testing

@testable import FoodRotate

/// 多詞搜尋的容錯（S6 P1-3）。
///
/// `MKLocalSearch` 找不到店家時是**拋錯**，不是回空陣列。而「找不到」跟
/// 「服務掛了」在型別上長得一模一樣（都是 throw），所以合併多個搜尋詞的時候
/// 一不小心就會把兩件事當成同一件：
///
/// - 「東南亞」要查「泰式」＋「越南料理」。泰式找到 3 家、越南料理拋 not-found，
///   **那 3 家不該跟著一起消失。**
/// - 反過來，服務端掛掉不該被說成「附近沒有店」——那是在假裝知道一件不知道的事。
///
/// 這裡把「查一個詞」注入成假的，所以測的是合併邏輯本身，跟網路無關。
@Suite("多詞搜尋的容錯")
@MainActor
struct NearbySearchTermsFaultTests {

    private static let taipei = CLLocation(latitude: 25.0330, longitude: 121.5654)

    private static func place(_ name: String, distance: CLLocationDistance) -> NearbyPlace {
        NearbyPlace(
            name: name,
            address: "測試路 1 號",
            coordinate: CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654),
            distance: distance,
            phoneNumber: nil,
            website: nil,
            categoryName: "餐廳"
        )
    }

    private static func mapKitError(_ code: MKError.Code) -> NSError {
        NSError(domain: MKErrorDomain, code: Int(code.rawValue))
    }

    // MARK: - P1-3

    @Test("第二個搜尋詞找不到店，不得抹掉第一個詞已經找到的結果")
    func 一個詞找不到不影響其他詞() async throws {
        let model = NearbySearchModel { term, _ in
            switch term {
            case "泰式": [Self.place("泰街", distance: 300), Self.place("小曼谷", distance: 800)]
            case "越南料理": throw Self.mapKitError(.placemarkNotFound)
            default: []
            }
        }

        let outcome = try await model.searchPlaces(
            terms: ["泰式", "越南料理"], near: Self.taipei
        )

        #expect(outcome.places.map(\.name) == ["泰街", "小曼谷"])
        #expect(outcome.hardFailure == nil)
    }

    @Test("唯一的搜尋詞找不到店，是「沒有店」不是錯誤 —— 這樣上層才會去做一般餐廳的 fallback")
    func 單詞找不到要能往下走fallback() async throws {
        let model = NearbySearchModel { _, _ in
            throw Self.mapKitError(.placemarkNotFound)
        }

        let outcome = try await model.searchPlaces(terms: ["歐陸"], near: Self.taipei)

        #expect(outcome.places.isEmpty)
        #expect(outcome.hardFailure == nil, "找不到不是硬錯誤，否則上層會直接報錯而不去 fallback")
    }

    @Test("服務端錯誤不得被當成「附近沒有店」")
    func 服務端錯誤不能被當成沒有店() async throws {
        let model = NearbySearchModel { _, _ in
            throw Self.mapKitError(.serverFailure)
        }

        let outcome = try await model.searchPlaces(terms: ["日式"], near: Self.taipei)

        #expect(outcome.places.isEmpty)
        #expect(outcome.hardFailure != nil, "服務掛掉要讓上層說實話，不能靜靜地變成『沒有店』")
    }

    @Test("有結果的詞成功、另一個詞服務端錯誤時，結果留著")
    func 部分成功時結果留著() async throws {
        let model = NearbySearchModel { term, _ in
            if term == "泰式" { return [Self.place("泰街", distance: 300)] }
            throw Self.mapKitError(.loadingThrottled)
        }

        let outcome = try await model.searchPlaces(
            terms: ["泰式", "越南料理"], near: Self.taipei
        )

        #expect(outcome.places.map(\.name) == ["泰街"])
    }

    @Test("合併之後仍然照距離排序，不是照搜尋詞的順序")
    func 合併後照距離排序() async throws {
        let model = NearbySearchModel { term, _ in
            switch term {
            case "泰式": [Self.place("遠的泰式", distance: 2000)]
            case "越南料理": [Self.place("近的越南", distance: 200)]
            default: []
            }
        }

        let outcome = try await model.searchPlaces(
            terms: ["泰式", "越南料理"], near: Self.taipei
        )

        #expect(outcome.places.map(\.name) == ["近的越南", "遠的泰式"])
    }
}
