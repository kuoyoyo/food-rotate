import Foundation

/// 一道菜身上可以掛的標籤，也是篩選器唯一的語彙。
///
/// 以前這件事是靠「使用者打一段中文 → 模型讀懂 → 希望它照做」，
/// 中間有兩層猜測。改成固定的標籤集合之後，篩選是查表，不是理解，
/// 所以選了「無牛」就一定不會出現牛肉麵，不必再有 `DietaryFilter` 那種事後補救。
///
/// `rawValue` 就是畫面上顯示的字，也是 `foods.json` 裡寫的字。
/// 三者同一份，改一個地方就好，不會有對照表要維護。
enum FoodTag: String, Codable, Hashable, Sendable, CaseIterable {
    // MARK: 菜系
    case taiwanese = "台式"
    case chinese = "中式"
    case japanese = "日式"
    case korean = "韓式"
    case southeastAsian = "東南亞"
    case southAsian = "南亞"
    case italian = "義式"
    case american = "美式"
    case european = "歐陸"
    case mexican = "墨西哥"

    // MARK: 吃法
    //
    // 刻意跟菜系分開。舊的 `FoodItem.categories` 把「日式」跟「麵食」放在同一個清單裡，
    // 一道菜只能選一個，於是拉麵要嘛是日式要嘛是麵食。分成兩個維度之後，
    // 「想吃日式的麵」才問得出來。
    case noodles = "麵食"
    case rice = "飯食"
    case soupDish = "湯的"
    case hotpot = "鍋物"
    case snack = "小吃"
    case bread = "麵包餅皮"
    case lightMeal = "輕食"

    // MARK: 情境
    case breakfast = "早餐"
    case lunch = "午餐"
    case dinner = "晚餐"
    case lateNight = "宵夜"

    // MARK: 口味
    case light = "清爽"
    case heavy = "重口味"
    case spicy = "辣"
    case sweet = "偏甜"

    // MARK: 忌口
    //
    // 刻意是**正面標記**（「這道菜不含牛」）而不是負面排除。
    // 資料是人寫死的，標「無牛」比執行期用關鍵字猜「牛肉麵含牛」可靠得多，
    // 也不會像舊的 DietaryFilter 那樣把「牛蒡天婦羅」誤殺。
    case noBeef = "無牛"
    case noPork = "無豬"
    case noSeafood = "無海鮮"
    case vegetarianFriendly = "素可"

    // MARK: 其他
    case cheap = "便宜"
    case quick = "快"
    case filling = "吃得飽"
    case healthy = "健康"

    /// 標籤所屬的維度。篩選規則與 UI 分組都靠它。
    var dimension: Dimension {
        switch self {
        case .taiwanese, .chinese, .japanese, .korean, .southeastAsian,
             .southAsian, .italian, .american, .european, .mexican:
            .cuisine
        case .noodles, .rice, .soupDish, .hotpot, .snack, .bread, .lightMeal:
            .form
        case .breakfast, .lunch, .dinner, .lateNight:
            .occasion
        case .light, .heavy, .spicy, .sweet:
            .flavour
        case .noBeef, .noPork, .noSeafood, .vegetarianFriendly:
            .restriction
        case .cheap, .quick, .filling, .healthy:
            .trait
        }
    }

    /// 篩選的維度。
    ///
    /// `allCases` 的順序就是畫面上由上到下的順序，也是放寬時**由後往前**的順序
    /// （見 `FoodPicker`）：越後面的越先被放掉，因為越不重要。
    enum Dimension: String, CaseIterable, Hashable, Sendable {
        case restriction = "忌口"
        case cuisine = "菜系"
        case form = "吃法"
        case occasion = "什麼時候吃"
        case flavour = "口味"
        case trait = "其他"

        var tags: [FoodTag] {
            FoodTag.allCases.filter { $0.dimension == self }
        }

        /// 這個維度是不是硬條件。硬條件永遠不會被放寬。
        var isHardConstraint: Bool { self == .restriction }
    }
}

/// 使用者目前選了哪些標籤。
///
/// 只是一個 `Set`，但包一層是為了讓「依維度取出」這件事有個明確的地方，
/// 呼叫端不用每次都寫 `filter { $0.dimension == ... }`。
struct FilterSelection: Equatable, Sendable {
    var tags: Set<FoodTag> = []

    var isEmpty: Bool { tags.isEmpty }

    func tags(in dimension: FoodTag.Dimension) -> Set<FoodTag> {
        tags.filter { $0.dimension == dimension }
    }

    mutating func toggle(_ tag: FoodTag) {
        if tags.contains(tag) {
            tags.remove(tag)
        } else {
            tags.insert(tag)
        }
    }

    /// 給歷史紀錄存的可讀摘要，例如「日式・清爽・宵夜」。
    ///
    /// 依 `allCases` 的順序排，這樣同一組選擇每次產生的字串都一樣，
    /// 歷史頁不會出現兩筆看起來不同其實一樣的紀錄。
    var summary: String {
        let ordered = FoodTag.allCases.filter { tags.contains($0) }
        return ordered.map(\.rawValue).joined(separator: "・")
    }
}
