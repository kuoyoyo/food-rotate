import CoreLocation
import Foundation
import MapKit
import Testing

@testable import FoodRotate

/// 換模式之後，上一個模式留下來的狀態誰負責清。
///
/// S6 那批問的是**時機**（「這個結果屬於哪一次請求」）；這一組問的是另一件事：
/// **「去哪吃」講的話，切回「吃什麼」之後還算不算數。**
///
/// 三個缺陷共用同一個形狀 —— 有人在 A 路徑上設了狀態，B 路徑沒有負責清：
///
/// - A：`didFallBackToGeneric` 只在 `findRestaurants()` 裡歸零，`pick()` 沒碰它，
///   於是「附近沒有『歐陸』的店」跟著使用者一起走進菜色模式。而且它在 `statusArea`
///   的 `else if` 鏈裡**排在放寬提示前面**，殘留的那句話會把「已放寬 菜系」整句蓋掉 ——
///   使用者拿到不完全符合的東西，畫面卻沒說。
/// - B：`restore(_:)` 換掉了清單，卻沒有換模式，也沒有收掉上一個模式的錯誤卡片。
/// - C：`wheelSlots` 的補格直接呼叫 `pick()`，不看現在是哪一個模式。
///
/// 三個在正常操作下都到得了，不需要卡時機 —— 所以這裡不用閘門，
/// 只要等非同步的搜尋落地就好。
@Suite("換模式之後的狀態殘留", .serialized)
@MainActor
struct RotateModeSwitchTests {

    private static let taipei = CLLocation(latitude: 25.0330, longitude: 121.5654)

    private static func place(_ name: String) -> NearbyPlace {
        NearbyPlace(
            name: name,
            address: "測試路 1 號",
            coordinate: CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654),
            distance: 300,
            phoneNumber: nil,
            website: nil,
            categoryName: "餐廳"
        )
    }

    private static func dish(_ id: String, _ name: String) -> FoodItem {
        FoodItem(id: id, name: name, emoji: "🍜", category: "台式", tags: [.taiwanese], pros: [], cons: [])
    }

    /// 等到條件成立，或等到上限為止。回傳有沒有等到。
    ///
    /// **不睡一個猜的秒數。** 缺陷存在時第一次輪詢就看得到了，
    /// 上限只是給慢機器的餘裕 —— 偶爾失敗的測試比沒有測試更糟。
    @discardableResult
    private static func waitUntil(
        _ condition: () -> Bool,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return condition()
    }

    // MARK: - A：退回一般餐廳的提示不得跟著走進菜色模式

    /// 指定的菜系一家都找不到，只有「餐廳」找得到 —— 這正是會觸發退回的形狀。
    private static func fallbackModel() -> NearbySearchModel {
        NearbySearchModel(
            queryTerm: { term, _ in
                term == RestaurantSearchTerms.generic ? [Self.place("巷口小吃店")] : []
            },
            location: { Self.taipei }
        )
    }

    @Test("退回一般餐廳之後切回「吃什麼」，那句提示不得留在畫面上")
    func 退回提示不得跨模式殘留() async throws {
        let model = RotateViewModel(nearby: Self.fallbackModel())

        model.filter.tags = [.european]
        model.source = .restaurants

        #expect(
            await Self.waitUntil { model.didFallBackToGeneric },
            "這一輪本來就該退回一般餐廳，前提沒成立的話後面的斷言沒有意義"
        )

        // 使用者切回「吃什麼」。
        model.source = .dishes
        #expect(await Self.waitUntil { !model.allItems.isEmpty }, "切回來之後應該有一組菜色")

        #expect(
            model.didFallBackToGeneric == false,
            "「吃什麼」模式沒有在找店，不該說「附近沒有『歐陸』的店，改列一般餐廳」"
        )
        #expect(
            model.searchedCuisines.isEmpty,
            "上一輪搜的是哪幾個菜系，切模式之後就不是這一輪的事實了"
        )
    }

    @Test("退回的提示不得把「已放寬」那一句蓋掉")
    func 退回提示不得蓋掉放寬提示() async throws {
        let model = RotateViewModel(nearby: Self.fallbackModel())

        model.filter.tags = [.european]
        model.source = .restaurants
        #expect(await Self.waitUntil { model.didFallBackToGeneric })

        model.source = .dishes
        #expect(await Self.waitUntil { !model.allItems.isEmpty })

        // 「歐陸」在內建資料裡湊不滿一盤，所以切回來這一輪一定會放寬菜系。
        // 這是產品規則第三條：放寬了就要說 —— 而 `statusArea` 的 else if 鏈裡
        // `didFallBackToGeneric` 排在前面，它殘留就等於這句話說不出口。
        #expect(
            model.relaxedDimensions.isEmpty == false,
            "選歐陸抽不滿一盤，這一輪應該有放寬 —— 前提沒成立的話這支測試沒有意義"
        )
        #expect(
            model.didFallBackToGeneric == false,
            "殘留的退回提示會壓掉「已放寬 菜系」，使用者拿到不完全符合的東西而畫面沒說"
        )
    }

    // MARK: - B：從歷史還原

    /// 地圖服務出事 —— 這條路會留下一張「找不到附近的店」的卡片。
    private static func failingModel() -> NearbySearchModel {
        NearbySearchModel(
            queryTerm: { _, _ in
                throw NSError(domain: MKErrorDomain, code: Int(MKError.Code.serverFailure.rawValue))
            },
            location: { Self.taipei }
        )
    }

    @Test("從歷史還原一組菜色，模式要跟著回到「吃什麼」，錯誤卡片要收掉")
    func 還原要把模式帶回菜色() async throws {
        let model = RotateViewModel(nearby: Self.failingModel())

        model.source = .restaurants
        #expect(
            await Self.waitUntil { model.errorMessage != nil },
            "這一輪本來就該失敗，前提沒成立的話後面的斷言沒有意義"
        )

        let items = [Self.dish("a", "牛肉麵"), Self.dish("b", "滷肉飯")]
        let record = SpinRecord(
            date: .now, prompt: "台式", items: items,
            winner: items[0], source: .dishes
        )
        model.restore(record)

        #expect(
            model.source == .dishes,
            "還原的是一組菜色，切換器不能還停在「去哪吃」"
        )
        #expect(
            model.errorMessage == nil,
            "盤上已經是菜了，卻壓著一張「找不到附近的店」的卡片"
        )
        #expect(
            model.allItems.map(\.id) == items.map(\.id),
            "還原的清單不得被切模式順手觸發的重抽蓋掉"
        )
    }

    @Test("還原之後改條件，重抽的是菜不是店")
    func 還原之後改條件不得回去找店() async throws {
        // **這裡要用「找得到店」的搜尋，不是失敗的那一個。**
        // 用失敗的版本會讓這支測試在缺陷還在的時候也是綠的：搜尋失敗會把
        // `allItems` 清成空陣列，而空陣列的 `allSatisfy` 恆真 —— 測試通過，
        // 但通過的理由跟它要驗的事情無關。踩過一次，記在這裡。
        let model = RotateViewModel(
            nearby: NearbySearchModel(
                queryTerm: { _, _ in [Self.place("巷口小吃店")] },
                location: { Self.taipei }
            )
        )

        model.source = .restaurants
        #expect(await Self.waitUntil { model.allItems.contains(where: \.isPlace) })

        let items = [Self.dish("a", "牛肉麵"), Self.dish("b", "滷肉飯")]
        model.restore(
            SpinRecord(date: .now, prompt: "台式", items: items, winner: items[0], source: .dishes)
        )

        // 使用者在還原後的畫面上點了一個標籤 —— `FilterBar` 的 onChange 走的就是這條。
        model.filter.tags = [.japanese]
        model.load()
        // **等的是「載入結束」，不是「清單非空」。** 還原後的清單本來就非空，
        // 等它等於什麼都沒等 —— 搜尋還在路上就先斷言，缺陷還在也是綠的。
        // （`findRestaurants` 會同步把 `isLoading` 設成 true，`pick()` 則是 false，
        // 所以修好之後這一等會立刻回來。）
        #expect(
            await Self.waitUntil { !model.isLoading && !model.allItems.isEmpty },
            "重抽沒有落地，下面那條斷言不算數"
        )

        #expect(
            model.allItems.allSatisfy { !$0.isPlace },
            "使用者已經在菜色清單上了，動一個標籤不該把他丟回去找店"
        )
    }

    // MARK: - C：「去哪吃」模式調格數

    @Test("「去哪吃」模式把格數調大，轉盤上不得冒出菜色")
    func 店家模式調格數不得換成菜色() async throws {
        let settings = AppSettings.shared
        let original = settings.wheelSlots
        defer { settings.wheelSlots = original }

        // 只找得到兩家 —— 郊區、或選了冷門菜系退回之後的常態。
        let model = RotateViewModel(
            nearby: NearbySearchModel(
                queryTerm: { _, _ in [Self.place("第一家"), Self.place("第二家")] },
                location: { Self.taipei }
            )
        )

        model.wheelSlots = 4
        model.source = .restaurants
        #expect(await Self.waitUntil { model.allItems.count == 2 }, "前提：這一輪只找到兩家")

        // 使用者把格數調大。附近就只有兩家，這件事不會因為調格數而改變。
        model.wheelSlots = 8

        #expect(
            model.allItems.allSatisfy { $0.isPlace },
            "還在「去哪吃」模式，補格不該去抽菜色 —— 附近有幾家就是幾家"
        )
        #expect(
            model.items.count == 2,
            "湊不滿是事實，由 isShortOfSlots 老實說出來，不是變出八道菜"
        )
    }

    @Test("「吃什麼」模式把格數調大，照舊會補滿")
    func 菜色模式調格數照舊補格() async throws {
        let settings = AppSettings.shared
        let original = settings.wheelSlots
        defer { settings.wheelSlots = original }

        let model = RotateViewModel()
        model.wheelSlots = 4
        model.load()
        #expect(model.allItems.count == 4)

        model.wheelSlots = 8

        // 這一條是 C 的反面：加模式判斷不能把原本對的行為一起關掉。
        #expect(model.allItems.count == 8, "菜色模式的補格是對的，不要一起改掉")
        #expect(model.allItems.allSatisfy { !$0.isPlace })
    }
}
