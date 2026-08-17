import CoreLocation
import Foundation
import Testing

@testable import FoodRotate

/// 「去哪吃」搜尋的非同步邊界（S6 P1-1、P1-2）。
///
/// 兩個缺陷都是同一句話沒有答案：**這個結果屬於哪一次請求。**
///
/// - P1-1：切回「吃什麼」之後，還在路上的搜尋回來把餐廳寫進菜色清單
/// - P1-2：載入中改條件被 `guard !isLoading` 直接忽略 ——
///   使用者看到新菜系已經選中，拿到的卻是舊搜尋的結果
///
/// 這兩件事在正常速度下都不會發生（搜尋通常兩三秒就回來了），
/// 所以測試把「查一個詞」換成停在閘門前，由測試決定什麼時候回來。
@Suite("去哪吃搜尋的非同步邊界", .serialized)
@MainActor
struct RestaurantSearchRaceTests {

    /// 讓搜尋停在半路，由測試放行，並記下每一次被查的詞。
    actor SearchGate {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var askedTerms: [String] = []

        func arrive(term: String) async {
            askedTerms.append(term)
            await withCheckedContinuation { waiters.append($0) }
        }

        func releaseAll() {
            let pending = waiters
            waiters = []
            for continuation in pending { continuation.resume() }
        }

        /// 等到至少有 `count` 次查詢抵達閘門。
        ///
        /// **一定要有上限。** 沒有上限的話「第二次請求根本沒發出去」這個缺陷
        /// 會讓測試整個吊死（實測就是這樣），而吊死的測試看不出是哪裡壞了 ——
        /// 有上限才會落到下面的 `#expect` 上，紅得清清楚楚。
        /// 回傳有沒有等到。
        @discardableResult
        func waitUntilArrived(_ count: Int, timeout: Duration = .seconds(2)) async -> Bool {
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                if askedTerms.count >= count { return true }
                // **要真的睡，不能只 `Task.yield()`。**
                // 踩過：純 yield 的忙迴圈會一直把自己排回去，剛建立的搜尋 Task
                // 根本排不進來 —— 等 2000 次也等不到，而它其實只需要一次排程機會。
                try? await Task.sleep(for: .milliseconds(1))
            }
            return askedTerms.count >= count
        }
    }

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

    /// 每個搜尋詞回一家同名的店，方便斷言「拿到的是哪一次請求的結果」。
    private static func model(gate: SearchGate) -> NearbySearchModel {
        NearbySearchModel(
            queryTerm: { term, _ in
                await gate.arrive(term: term)
                return [Self.place("\(term)的店")]
            },
            location: { Self.taipei }
        )
    }

    /// 讓已經排好的 main actor 工作跑完。
    ///
    /// **不能用「固定讓幾次」。** 一開始寫 8 次，結果同一份程式碼跑五遍會紅四遍 ——
    /// 這幾支測試共用 `AppSettings.shared`／`CustomFoodStore.shared`，
    /// 跟別的測試搶 main actor，8 次在忙的時候不夠。
    /// 而**偶爾失敗的測試比沒有測試更糟**：紅了沒人知道是程式壞了還是機器忙。
    ///
    /// 現在是「讓到沒有東西可讓為止」，上限 500 次 —— 缺陷存在時它一兩次就寫進來了，
    /// 500 次是給慢機器的餘裕，不是在等一個猜的時間。
    private static func settle() async {
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    /// 等到條件成立，或等到上限為止。回傳有沒有等到。
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

    // MARK: - P1-1

    @Test("切回「吃什麼」之後，還在路上的餐廳搜尋不得把結果灌進清單")
    func 切模式後舊結果不得回灌() async throws {
        let gate = SearchGate()
        let model = RotateViewModel(nearby: Self.model(gate: gate))

        model.source = .restaurants
        await gate.waitUntilArrived(1)

        // 使用者不等了，切回「吃什麼」。這裡會重抽一組菜色。
        model.source = .dishes
        await Self.waitUntil { !model.allItems.isEmpty }
        let dishes = model.allItems.map(\.id)
        #expect(dishes.allSatisfy { !$0.hasPrefix("place-") }, "切回來之後清單應該是菜色")

        // 舊的搜尋現在才回來。
        await gate.releaseAll()
        await Self.settle()

        #expect(
            model.allItems.allSatisfy { !$0.id.hasPrefix("place-") },
            "已經切回「吃什麼」了，餐廳結果不該再寫進清單"
        )
        #expect(model.isLoading == false)
    }

    // MARK: - P1-2

    @Test("載入中改條件不得被忽略，最後生效的必須是最後一次請求")
    func 載入中改條件要重新搜尋() async throws {
        let gate = SearchGate()
        let model = RotateViewModel(nearby: Self.model(gate: gate))

        // **條件先設好再切模式。** 切模式本身就會打一次搜尋，如果那一次跟
        // 後面的請求混在一起，測試自己就變成一個競態 —— 這裡踩過：
        // 「第一次抵達的是哪一個」不確定，同一份程式碼跑五遍紅四遍。
        model.filter.tags = [.japanese]
        model.source = .restaurants
        #expect(await gate.waitUntilArrived(1), "第一次搜尋沒有發出去")

        // 還在載入，使用者改成韓式。畫面上韓式已經是選中的了。
        model.filter.tags = [.korean]
        model.load()
        await Self.settle()

        // 第二次請求要真的發出去，不能被「還在載入」擋掉。
        let secondRequestWasMade = await gate.waitUntilArrived(2)
        #expect(secondRequestWasMade, "載入中改條件被忽略了，第二次請求根本沒發出去")
        await gate.releaseAll()
        await Self.settle()
        await gate.releaseAll()
        await Self.settle()

        let names = model.allItems.map(\.name)
        #expect(
            names.contains(where: { $0.contains("韓") }),
            "使用者選的是韓式，清單裡必須是韓式那一次請求的結果"
        )
        #expect(
            names.allSatisfy { !$0.contains("日") },
            "舊的日式結果不得留在畫面上"
        )
    }

    @Test("後到的舊請求不得覆蓋新請求的結果")
    func 舊請求晚回來不得覆蓋() async throws {
        let gate = SearchGate()
        let model = RotateViewModel(nearby: Self.model(gate: gate))

        model.filter.tags = [.japanese]
        model.source = .restaurants
        #expect(await gate.waitUntilArrived(1), "第一次搜尋沒有發出去")

        model.filter.tags = [.korean]
        model.load()
        #expect(await gate.waitUntilArrived(2), "第二次請求沒有發出去")

        // 兩個一起放行。舊的那一個也會醒來 —— 它不該蓋掉新的。
        await gate.releaseAll()
        await Self.settle()
        await gate.releaseAll()
        await Self.settle()

        #expect(model.allItems.map(\.name).allSatisfy { !$0.contains("日") })
    }
}
