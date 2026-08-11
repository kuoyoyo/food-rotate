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
        onStage: (@MainActor (GenerationActivityAttributes.Stage) -> Void)? = nil
    ) {
        searchTask?.cancel()
        searchTask = Task { await self.runRestaurants(terms: terms, onStage: onStage) }
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
        onStage: (@MainActor (GenerationActivityAttributes.Stage) -> Void)?
    ) async {
        phase = .locating
        onStage?(.locating)
        didFallBackToGeneric = false
        do {
            let location = try await resolveLocation()
            guard !Task.isCancelled else { return }
            userCoordinate = location.coordinate

            phase = .searching
            onStage?(.searching)

            // 每個搜尋詞各查一次再合併。一個詞代表不了一個菜系 ——
            // 「東南亞」要靠「泰式」加「越南料理」才問得出東西（見 `RestaurantSearchTerms`）。
            var places = try await searchPlaces(terms: terms, near: location)

            // 指定了菜系卻一家都沒有，退回查一般餐廳而不是直接失敗。
            // 使用者要的是「現在去哪吃」，附近沒有日式不代表沒得吃。
            //
            // **但這件事要記下來讓畫面說出去。** 以前這裡是靜默的，違反「放寬要老實說明」。
            if places.isEmpty, terms != [RestaurantSearchTerms.generic] {
                places = (try? await searchPlaces(
                    terms: [RestaurantSearchTerms.generic], near: location
                )) ?? []
                didFallBackToGeneric = !places.isEmpty
            }
            guard !Task.isCancelled else { return }

            if places.isEmpty {
                phase = .failed("附近十五公里內找不到餐廳。可能是定位不準，或這裡的地圖資料太少。")
                onStage?(.failed)
            } else {
                phase = .results(places)
                onStage?(.done(count: places.count))
            }
        } catch is CancellationError {
            return
        } catch let error as LocationError {
            phase = .failed(error.message)
            onStage?(.failed)
        } catch {
            phase = .failed(Self.describeSearchFailure(
                error, dish: terms.first ?? RestaurantSearchTerms.generic
            ))
            onStage?(.failed)
        }
    }

    /// 幾個搜尋詞各查一次，結果合併。
    ///
    /// 合併時用「店名 + 座標」去重，不是用 `id`：`NearbyPlace` 的 `id` 是每次建立時
    /// 新生成的 UUID，同一家店在兩個搜尋詞裡會拿到兩個不同的 id，用它去重等於沒去重。
    private func searchPlaces(terms: [String], near location: CLLocation) async throws -> [NearbyPlace] {
        var merged: [NearbyPlace] = []
        var seen = Set<String>()

        for term in terms {
            guard !Task.isCancelled else { break }
            for place in try await searchPlaces(dish: term, near: location) {
                let key = "\(place.name)@\(place.coordinate.latitude),\(place.coordinate.longitude)"
                guard seen.insert(key).inserted else { continue }
                merged.append(place)
            }
        }
        // 合併之後順序會變成「第一個詞的全部、第二個詞的全部」，要重新照距離排，
        // 否則轉盤上前幾格會全是同一個搜尋詞來的店。
        return merged.sorted { $0.distance < $1.distance }
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
            let location = try await currentLocation()
            guard !Task.isCancelled else { return }
            userCoordinate = location.coordinate

            phase = .searching
            let places = try await searchPlaces(dish: dish, near: location)
            guard !Task.isCancelled else { return }

            if places.isEmpty {
                phase = .failed("十五公里內找不到賣「\(dish)」的店。可以換個更常見的說法，例如把「豬肉親子丼」改成「親子丼」或「日式定食」。")
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

    private func searchPlaces(dish: String, near location: CLLocation) async throws -> [NearbyPlace] {
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
    private static var maxDistance: CLLocationDistance {
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
