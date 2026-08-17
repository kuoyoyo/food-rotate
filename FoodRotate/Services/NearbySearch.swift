import CoreLocation
import Foundation
import MapKit
import UIKit

/// 一筆附近的搜尋結果。
///
/// **MapKit 給不出營業時間，也給不出「現在有沒有開」。**
/// `MKMapItem` 的公開屬性只有名稱、位置、地址、電話、網站、時區與 POI 類別
/// （查過 iOS 26 SDK 的 `MKMapItem.h`）。要真的知道開沒開必須接 Google Places API，
/// 那需要金鑰與計費，是另一件事。
///
/// 所以這裡把 MapKit **給得出來的**都帶上，讓使用者自己判斷：
/// 電話可以直接打過去問，網站與地圖卡片上通常寫著營業時間。
struct NearbyPlace: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    /// 與使用者的直線距離（公尺）。
    let distance: CLLocationDistance
    let phoneNumber: String?
    let website: URL?
    /// 店家類別（餐廳、咖啡廳、烘焙坊…）。已經翻成中文。
    let categoryName: String?

    var distanceText: String {
        if distance < 1000 {
            return "\(Int(distance.rounded())) 公尺"
        }
        return String(format: "%.1f 公里", distance / 1000)
    }

    /// 卡片副標：類別 · 距離。沒有類別就只有距離。
    var subtitle: String {
        [categoryName, distanceText].compactMap { $0 }.joined(separator: " · ")
    }

    /// 給地圖 App 搜尋用的查詢字串。
    ///
    /// **刻意用「店名 空格 地址」而不是經緯度。** 座標雖然精準，但使用者在
    /// Google 地圖上看到的會是一個沒有名字的圖釘，點不到評論、營業時間、照片，
    /// 也沒辦法把它存進自己的清單。用店名加地址，落地的是真正的店家頁面。
    ///
    /// 地址要一起帶，否則「鼎泰豐」「麥當勞」這種連鎖店會導到別家分店。
    var searchQuery: String {
        address.isEmpty ? name : "\(name) \(address)"
    }

    /// 轉成轉盤看得懂的形狀。
    ///
    /// **這是刻意的權宜。** 轉盤、卡片、結果頁、歷史紀錄全都吃 `FoodItem`，
    /// 讓店家借用同一個型別，四個地方一行都不用改。
    /// 代價是幾個欄位的語意被撐開了：`category` 放「類別 · 距離」、`pros` 放店家資訊。
    /// 這在 `FoodItem` 的欄位註解裡也記了一筆。
    ///
    /// 真正乾淨的做法是抽一個 `WheelEntry` 協定讓菜色與店家各自實作，
    /// 但那要動 `WheelView` 與 `SpinRecord` 的編碼，範圍大得多。
    /// 等到店家模式要顯示營業時間、評分這些菜色沒有的東西時，再回來做那件事。
    var asFoodItem: FoodItem {
        var info: [String] = []
        if !address.isEmpty { info.append(address) }
        if let phoneNumber { info.append("電話 \(phoneNumber)") }
        if let host = website?.host() { info.append(host) }

        return FoodItem(
            id: "place-\(id.uuidString)",
            name: name,
            emoji: "🍽️",
            category: subtitle,
            tags: [],
            pros: info,
            cons: []
        )
    }
}

/// `MKPointOfInterestCategory` 翻成中文。
///
/// 只翻這個 App 會搜到的那幾類（`pointOfInterestFilter` 限定的範圍），
/// 其餘一律回 nil 讓 UI 省略——與其顯示一個沒翻譯的英文列舉值，不如不顯示。
extension MKPointOfInterestCategory {
    var localizedName: String? {
        switch self {
        case .restaurant: "餐廳"
        case .cafe: "咖啡廳"
        case .bakery: "烘焙坊"
        case .foodMarket: "食品市場"
        case .brewery: "啤酒吧"
        case .winery: "酒莊"
        default: nil
        }
    }
}

/// 轉盤上轉的是什麼。
///
/// 兩種模式回答的是不同的問題：「吃什麼」是不知道想吃哪一道，
/// 「去哪吃」是已經想吃了但不知道去哪家。後者以前只能從結果頁進去查單一道菜，
/// 沒辦法讓運氣直接幫你選一家店。
enum WheelSource: String, CaseIterable, Identifiable, Sendable {
    case dishes
    case restaurants

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dishes: "吃什麼"
        case .restaurants: "去哪吃"
        }
    }

    var symbolName: String {
        switch self {
        case .dishes: "fork.knife"
        case .restaurants: "mappin.and.ellipse"
        }
    }
}

/// 找附近有沒有賣這道菜的店。
///
/// 定位走 iOS 18 之後的 `CLServiceSession` + `CLLocationUpdate.liveUpdates()`，
/// 不用 delegate，因此整條路徑都是 async/await，也沒有 Swift 6 的資料競爭問題。
/// 搜尋走 `MKLocalSearch`，不需要任何 API key。
@MainActor
@Observable
final class NearbySearchModel {
    enum Phase: Equatable {
        case idle
        case locating
        case searching
        case results([NearbyPlace])
        case failed(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.locating, .locating), (.searching, .searching): true
            case (.results(let a), .results(let b)): a.map(\.id) == b.map(\.id)
            case (.failed(let a), .failed(let b)): a == b
            default: false
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var userCoordinate: CLLocationCoordinate2D?

    /// 抓著這個 session 才代表 App 正在「使用中」，放掉就等於結束定位授權需求。
    private var serviceSession: CLServiceSession?
    private var searchTask: Task<Void, Never>?

    /// 查一個搜尋詞。
    ///
    /// 抽成可注入的函式，是為了讓「第二個詞找不到」這種情境測得到（S6 P1-3）——
    /// 那一條的錯誤完全發生在**多詞合併的邏輯**裡，跟真實網路無關，
    /// 但不注入的話只能靠 MapKit 剛好回什麼，那不是測試。
    /// 正式路徑用預設值，也就是下面那支 `searchWithMapKit`。
    typealias TermQuery = @MainActor (_ term: String, _ location: CLLocation) async throws -> [NearbyPlace]
    private let queryTerm: TermQuery

    /// 取得位置。同樣只為了測試而可注入 —— 測試環境沒有定位權限，
    /// 不注入的話整條搜尋路徑在第一步就停住，後面的狀態機一行都測不到。
    /// `nil` 代表走正式路徑（`resolveLocation()`）。
    typealias LocationProvider = @MainActor () async throws -> CLLocation
    private let locationOverride: LocationProvider?

    init(
        queryTerm: @escaping TermQuery = NearbySearchModel.searchWithMapKit,
        location: LocationProvider? = nil
    ) {
        self.queryTerm = queryTerm
        self.locationOverride = location
    }

    private func obtainLocation() async throws -> CLLocation {
        if let locationOverride { return try await locationOverride() }
        return try await resolveLocation()
    }

    func search(dish: String) {
        searchTask?.cancel()
        searchTask = Task { await self.run(dish: dish) }
    }

    /// 一次拿到一整批附近的店，給「去哪吃」模式填轉盤用。
    ///
    /// 跟 `search(dish:)` 的差別只在查詢字串與失敗訊息：那個是「附近有沒有賣這道菜」，
    /// 這個是「附近有哪些店」。搜尋、範圍上限、排序完全共用，不另外寫一套。
    ///
    /// - Parameters:
    ///   - terms: 要拿去搜店名的字，見 `RestaurantSearchTerms`。多個字的結果會合併。
    ///   - onStage: 真實階段回報，給 Live Activity 用。定位跟搜尋各數秒，值得告訴使用者。
    func searchRestaurants(
        terms: [String],
        onStage: (@MainActor (GenerationActivityAttributes.Stage) -> Void)? = nil,
        onFinish: (@MainActor (RestaurantSearchOutcome) -> Void)? = nil
    ) {
        searchTask?.cancel()
        searchTask = Task {
            await self.runRestaurants(terms: terms, onStage: onStage, onFinish: onFinish)
        }
    }

    /// 一次「去哪吃」搜尋的最終結果。
    ///
    /// **由回呼帶出去，不要讓呼叫端自己去讀 `phase`。**
    /// `phase` 是共享狀態，下一個請求隨時可能改掉它 —— 拿號碼牌驗完身分，
    /// 再去櫃檯拿「最新的那一份」，等於沒驗（S6 P1-2）。
    enum RestaurantSearchOutcome: Sendable {
        case results([NearbyPlace], didFallBackToGeneric: Bool)
        case failed(String)
    }

    /// 這一輪有沒有因為一家都找不到而退回一般餐廳。
    ///
    /// 存在的理由是產品規則第三條：**放寬要老實說明**。以前這個退回是靜默的 ——
    /// 使用者選了「歐陸」拿到一般餐廳，畫面上沒有任何說明，那等於默默給了不符合的東西。
    private(set) var didFallBackToGeneric = false

    /// 上一次拿到的位置。人在原地連按幾次「換一組」時不必重新定位——
    /// 定位往往是這條路徑裡最慢的一段，快取後第二次幾乎只剩地圖搜尋的時間。
    private var cachedLocation: (location: CLLocation, at: Date)?
    private static let locationCacheLifetime: TimeInterval = 120

    private func runRestaurants(
        terms: [String],
        onStage: (@MainActor (GenerationActivityAttributes.Stage) -> Void)?,
        onFinish: (@MainActor (RestaurantSearchOutcome) -> Void)? = nil
    ) async {
        phase = .locating
        onStage?(.locating)
        didFallBackToGeneric = false
        do {
            let location = try await obtainLocation()
            guard !Task.isCancelled else { return }
            userCoordinate = location.coordinate

            phase = .searching
            onStage?(.searching)

            // 每個搜尋詞各查一次再合併。一個詞代表不了一個菜系 ——
            // 「東南亞」要靠「泰式」加「越南料理」才問得出東西（見 `RestaurantSearchTerms`）。
            let outcome = try await searchPlaces(terms: terms, near: location)
            var places = outcome.places

            // 指定了菜系卻一家都沒有，退回查一般餐廳而不是直接失敗。
            // 使用者要的是「現在去哪吃」，附近沒有日式不代表沒得吃。
            //
            // **但這件事要記下來讓畫面說出去。** 以前這裡是靜默的，違反「放寬要老實說明」。
            //
            // **服務端出事的時候不做 fallback。** 那時候「一家都沒有」是假象，
            // 退回去查一般餐廳等於用一個猜的結果蓋掉一個我們其實不知道的答案。
            if places.isEmpty, outcome.hardFailure == nil, terms != [RestaurantSearchTerms.generic] {
                places = (try? await searchPlaces(
                    terms: [RestaurantSearchTerms.generic], near: location
                ).places) ?? []
                didFallBackToGeneric = !places.isEmpty
            }
            guard !Task.isCancelled else { return }

            if places.isEmpty, let hardFailure = outcome.hardFailure {
                // 一家都沒拿到，而且是服務端的問題 —— 要說「服務出事」，
                // 不能說「附近沒有餐廳」。
                finish(.failed(Self.describeSearchFailure(
                    hardFailure, dish: terms.first ?? RestaurantSearchTerms.generic
                )), onStage: onStage, onFinish: onFinish)
            } else if places.isEmpty {
                finish(
                    .failed(Self.noRestaurantsMessage()),
                    onStage: onStage, onFinish: onFinish
                )
            } else {
                finish(
                    .results(places, didFallBackToGeneric: didFallBackToGeneric),
                    onStage: onStage, onFinish: onFinish
                )
            }
        } catch is CancellationError {
            // 取消不回報。**這一輪已經不算數了**，回報只會讓上層去處理一個
            // 沒有人在等的結果 —— 而那正是 P1-1 的形狀。
            return
        } catch let error as LocationError {
            finish(.failed(error.message), onStage: onStage, onFinish: onFinish)
        } catch {
            finish(.failed(Self.describeSearchFailure(
                error, dish: terms.first ?? RestaurantSearchTerms.generic
            )), onStage: onStage, onFinish: onFinish)
        }
    }

    /// 終點只有一個。
    ///
    /// `phase`（給「附近的店」那一頁看的）與回呼（給轉盤那一頁用的）
    /// **在同一個地方、用同一份資料寫出去**，兩邊不可能對不起來。
    private func finish(
        _ outcome: RestaurantSearchOutcome,
        onStage: (@MainActor (GenerationActivityAttributes.Stage) -> Void)?,
        onFinish: (@MainActor (RestaurantSearchOutcome) -> Void)?
    ) {
        // 已經被取消就不要再寫任何狀態 —— 包括 `phase`。
        guard !Task.isCancelled else { return }

        switch outcome {
        case .results(let places, _):
            phase = .results(places)
            onStage?(.done(count: places.count))
        case .failed(let message):
            phase = .failed(message)
            onStage?(.failed)
        }
        onFinish?(outcome)
    }

    /// 幾個搜尋詞各查一次，結果合併。
    ///
    /// 合併時用「店名 + 座標」去重，不是用 `id`：`NearbyPlace` 的 `id` 是每次建立時
    /// 新生成的 UUID，同一家店在兩個搜尋詞裡會拿到兩個不同的 id，用它去重等於沒去重。
    /// 多個搜尋詞查完之後的結果。
    struct TermSearchOutcome {
        var places: [NearbyPlace]
        /// 服務端的失敗（掛掉、被擋、解不開）。**「找不到店」不算在這裡。**
        var hardFailure: (any Error)?
    }

    /// internal 而非 private：多詞合併的容錯是 P1-3 的核心，要測得到。
    func searchPlaces(terms: [String], near location: CLLocation) async throws -> TermSearchOutcome {
        var merged: [NearbyPlace] = []
        var seen = Set<String>()

        var hardFailure: (any Error)?

        for term in terms {
            guard !Task.isCancelled else { break }

            let found: [NearbyPlace]
            do {
                found = try await queryTerm(term, location)
            } catch {
                // **一個詞查不到，不能拖垮其他詞。**
                //
                // 「東南亞」查的是「泰式」＋「越南料理」。泰式找到 3 家、
                // 越南料理拋 not-found —— 以前這裡直接 throw 出去，那 3 家跟著消失，
                // 使用者看到的是「附近沒有東南亞料理」，而事實是有 3 家泰式（P1-3）。
                if Self.isNotFound(error) { continue }

                // 服務端的失敗是另一回事：**不能靜靜地變成「沒有店」。**
                // 記下第一個，讓上層決定要說什麼；後面的詞照樣繼續查。
                hardFailure = hardFailure ?? error
                continue
            }

            for place in found {
                let key = "\(place.name)@\(place.coordinate.latitude),\(place.coordinate.longitude)"
                guard seen.insert(key).inserted else { continue }
                merged.append(place)
            }
        }
        // 合併之後順序會變成「第一個詞的全部、第二個詞的全部」，要重新照距離排，
        // 否則轉盤上前幾格會全是同一個搜尋詞來的店。
        return TermSearchOutcome(
            places: merged.sorted { $0.distance < $1.distance },
            hardFailure: hardFailure
        )
    }

    /// 這個錯誤是「這裡沒有這種店」還是「地圖服務出事了」。
    ///
    /// **這是整段容錯唯一的分界線。** `MKLocalSearch` 兩種情況都是 throw，
    /// 分不出來就只能二選一：把服務故障說成「沒有店」（假裝知道），
    /// 或把「沒有店」說成故障（嚇人又不給 fallback）。兩個都不對。
    /// 「附近沒有餐廳」的說法。
    ///
    /// **距離只有一個來源：使用者選的上限。** 這兩句以前寫死「十五公里」，
    /// 而實際上限早就改成可調（1／3／5／10，預設 5）——
    /// 同一個檔案的註解自己寫著「一度寫死十五公里，但那對『現在要去吃飯』來說太遠了」，
    /// **決定改了，文案沒跟著改**。選 1 公里卻被告知「十五公里內都沒有」，
    /// 那是在講一個不是事實的數字。
    static func noRestaurantsMessage(radius: Double = maxDistance) -> String {
        "附近 \(SearchRadius.label(radius)) 內找不到餐廳。可能是定位不準，或這裡的地圖資料太少。"
    }

    static func noPlacesSellingMessage(dish: String, radius: Double = maxDistance) -> String {
        "\(SearchRadius.label(radius)) 內找不到賣「\(dish)」的店。可以換個更常見的說法，例如把「豬肉親子丼」改成「親子丼」或「日式定食」。"
    }

    static func isNotFound(_ error: any Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == MKErrorDomain,
              nsError.code >= 0,
              let code = MKError.Code(rawValue: UInt(nsError.code))
        else { return false }
        return code == .placemarkNotFound || code == .directionsNotFound
    }

    func stop() {
        searchTask?.cancel()
        searchTask = nil
        serviceSession?.invalidate()
        serviceSession = nil
    }

    private func run(dish: String) async {
        phase = .locating
        do {
            let location = try await obtainLocation()
            guard !Task.isCancelled else { return }
            userCoordinate = location.coordinate

            phase = .searching
            let places = try await queryTerm(dish, location)
            guard !Task.isCancelled else { return }

            if places.isEmpty {
                phase = .failed(Self.noPlacesSellingMessage(dish: dish))
            } else {
                phase = .results(places)
            }
        } catch is CancellationError {
            return
        } catch let error as LocationError {
            phase = .failed(error.message)
        } catch {
            phase = .failed(Self.describeSearchFailure(error, dish: dish))
        }
    }

    /// `MKLocalSearch` 找不到店家時是**拋錯**而不是回空陣列，所以「找不到」這個
    /// 最常見的情況必須在這裡處理，不能只靠 `places.isEmpty`。
    ///
    /// 維持 internal 而非 private，是為了讓這段對應關係測得到。純函數，沒有副作用。
    static func describeSearchFailure(_ error: any Error, dish: String) -> String {
        let nsError = error as NSError
        // MKError.Code 的 rawValue 是 UInt，NSError.code 是 Int，中間要自己轉。
        guard nsError.domain == MKErrorDomain,
              nsError.code >= 0,
              let code = MKError.Code(rawValue: UInt(nsError.code))
        else {
            return error.localizedDescription
        }

        return switch code {
        case .placemarkNotFound, .directionsNotFound:
            "附近找不到賣「\(dish)」的店。這種吃法可能沒有店家專門在賣，或是換個更常見的關鍵字再試。"
        case .serverFailure:
            "地圖服務暫時沒有回應，稍後再試一次。"
        case .loadingThrottled:
            "查太頻繁被地圖服務暫時擋下，等幾秒再試。"
        case .decodingFailed:
            "地圖服務回傳的資料看不懂，稍後再試。"
        case .unknown:
            "搜尋失敗。確認網路連線後再試一次。"
        @unknown default:
            "搜尋失敗。確認網路連線後再試一次。"
        }
    }

    // MARK: - 定位

    private enum LocationError: Error {
        case denied
        case unavailable
        case timedOut

        var message: String {
            switch self {
            case .denied:
                "沒有定位權限，找不到附近的店。到「設定 → 隱私權與安全性 → 定位服務」開啟後再試。"
            case .unavailable:
                "目前抓不到位置。到戶外或開啟 Wi-Fi 後再試。"
            case .timedOut:
                "定位等太久了。確認定位服務有開啟後再試一次。"
            }
        }
    }

    /// 有近期的位置就直接用，沒有才真的去定位。
    ///
    /// 定位是這條路徑裡最慢的一段。人在原地連按幾次「換一組」時，
    /// 每次都重跑一輪 `liveUpdates()` 只是白等。
    private func resolveLocation() async throws -> CLLocation {
        if let cached = cachedLocation,
           Date.now.timeIntervalSince(cached.at) < Self.locationCacheLifetime {
            return cached.location
        }
        let fresh = try await currentLocation()
        cachedLocation = (fresh, .now)
        return fresh
    }

    /// 拿第一個有效的定位就收工。`liveUpdates()` 是無限序列，不主動 break 會一直跑下去。
    private func currentLocation() async throws -> CLLocation {
        if serviceSession == nil {
            serviceSession = CLServiceSession(authorization: .whenInUse)
        }

        return try await withThrowingTaskGroup(of: CLLocation.self) { group in
            group.addTask {
                for try await update in CLLocationUpdate.liveUpdates(.default) {
                    if update.authorizationDenied || update.authorizationDeniedGlobally {
                        throw LocationError.denied
                    }
                    if update.authorizationRestricted {
                        throw LocationError.denied
                    }
                    if let location = update.location {
                        return location
                    }
                    if update.locationUnavailable {
                        throw LocationError.unavailable
                    }
                }
                throw LocationError.unavailable
            }
            group.addTask {
                // 授權對話框開著的時候不會有任何 update 進來，需要一個上限。
                try await Task.sleep(for: .seconds(30))
                throw LocationError.timedOut
            }

            guard let first = try await group.next() else {
                throw LocationError.unavailable
            }
            group.cancelAll()
            return first
        }
    }

    // MARK: - 搜尋

    /// 真的去問 MapKit。這是 `queryTerm` 的預設實作。
    static func searchWithMapKit(dish: String, near location: CLLocation) async throws -> [NearbyPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = dish
        request.resultTypes = .pointOfInterest
        // 搜尋範圍跟著使用者選的上限走。乘二是因為 `region` 是邊長不是半徑，
        // 給小了會連範圍內的店都搜不齊。
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: Self.maxDistance * 2,
            longitudinalMeters: Self.maxDistance * 2
        )
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .restaurant, .cafe, .bakery, .foodMarket, .brewery, .winery,
        ])

        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems
            .map { item in
                NearbyPlace(
                    name: item.name ?? "未命名店家",
                    address: item.address?.shortAddress ?? item.address?.fullAddress ?? "",
                    coordinate: item.location.coordinate,
                    distance: item.location.distance(from: location),
                    phoneNumber: item.phoneNumber,
                    website: item.url,
                    categoryName: item.pointOfInterestCategory?.localizedName
                )
            }
            // `request.region` 對 MKLocalSearch 只是建議，不是硬性條件。
            // 實測在台北搜「豬肉親子丼」，本地沒有相符店家時它會回日本飯塚市、
            // 大阪、札幌的店，距離一千多公里。掛著「附近的」標題卻列出 2693 公里
            // 的結果毫無意義，所以這裡自己把超出範圍的濾掉。
            // 這也是使用者選的距離上限唯一真正生效的地方。
            .filter { $0.distance <= Self.maxDistance }
            .sorted { $0.distance < $1.distance }
    }

    /// 「附近」的上限，由使用者在設定裡決定。
    ///
    /// 一度寫死十五公里，但那對「現在要去吃飯」來說太遠了——
    /// 開車半小時的店不會是今天午餐的選項。改成可調之後預設五公里。
    static var maxDistance: CLLocationDistance {
        AppSettings.shared.searchRadius
    }

    /// 開啟導航。
    ///
    /// **目的地用「店名 + 地址」而不是經緯度。**
    /// 座標雖然精準，但地圖上落地的會是一個沒有名字的圖釘：點不到評論、營業時間、照片，
    /// 也沒辦法存進自己的清單、分享給別人。用店名加地址，落地的是真正的店家頁面，
    /// 使用者還能在那裡繼續操作。地址一定要一起帶，否則連鎖店會導到別家分店。
    static func openInMaps(_ place: NearbyPlace, using app: MapApp = AppSettings.shared.preferredMapApp) {
        let query = place.searchQuery

        switch app {
        case .apple:
            // `MKMapItem` 帶著座標與名稱，Apple 地圖會直接對上那家店的卡片。
            // 這裡仍然給座標是因為 `MKMapItem` 本來就需要一個位置，
            // 但有 `name` 之後顯示的就是店名而不是一個無名的座標圖釘。
            let item = MKMapItem(
                location: CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude),
                address: nil
            )
            item.name = place.name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])

        case .google:
            guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
            // 先試 App。沒裝的話 `canOpenURL` 回 false，退回網頁版——
            // universal link 一定開得起來，不會出現「按了沒反應」的死路。
            // 註：`canOpenURL` 需要 Info.plist 的 LSApplicationQueriesSchemes 列出
            // comgooglemaps，沒列的話一律回 false，永遠走不到 App 版。
            let appURL = URL(string: "comgooglemaps://?daddr=\(encoded)&directionsmode=driving")
            let webURL = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(encoded)")

            if let appURL, UIApplication.shared.canOpenURL(appURL) {
                UIApplication.shared.open(appURL)
            } else if let webURL {
                UIApplication.shared.open(webURL)
            }
        }
    }

    /// 撥電話給店家。號碼可能帶空白與括號，要清乾淨 `tel:` 才收得下。
    static func call(_ place: NearbyPlace) {
        guard let raw = place.phoneNumber else { return }
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        UIApplication.shared.open(url)
    }
}

/// 導航要用哪個地圖 App。
///
/// 包成 enum 而不是散在呼叫端的 if：之後移植 Android 時這件事會反過來
/// （Google 地圖是預設、Apple 地圖不存在），有這一層，呼叫端不用改。
enum MapApp: String, CaseIterable, Identifiable, Sendable {
    case apple
    case google

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: "Apple 地圖"
        case .google: "Google 地圖"
        }
    }

    var other: MapApp { self == .apple ? .google : .apple }
}
