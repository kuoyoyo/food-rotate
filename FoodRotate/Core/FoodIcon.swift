import Foundation

/// 一道菜在轉盤與卡片上要畫哪一個圖示。
///
/// **圖示不負責辨識「是哪一道菜」。** 身分歸兩行全名，圖示只表達類型
/// （`Design/設計規格-Theme-v1.md` 八-2，PM 已列入 S2 驗收標準）。
/// 這是整套系統的前提：舊的 emoji 之所以不能用，正是因為它假裝在做身分 ——
/// 50 道菜只有 23 個不重複符號，8 格撞圖率 77%，一盤裡三個 🍲 分不出誰是誰。
///
/// 只用 Foundation，跟 `Core/` 其他檔一樣可以直接對翻 Kotlin：
/// 「哪一道菜配哪一個圖示」是產品規則，不是 iOS 的事。
enum FoodIcon: String, CaseIterable, Sendable {
    case noodles
    case rice
    case soupDish
    case hotpot
    case snack
    case bread
    case lightMeal
    case meatDish

    /// 沒有吃法標籤時用的中性餐具圖示。
    ///
    /// 服務三種人：使用者自訂但沒選吃法的料理、「去哪吃」借用 `FoodItem` 裝的店家，
    /// 以及內建資料哪天又漏標。**不改新增表單的必填規則** ——
    /// 把吃法改成必選是行為改動，會擋住「想到一道菜隨手加進去」這條最常見的路徑，
    /// 為了美術方便去卡使用者的輸入是本末倒置（規格八-5）。
    case neutral

    /// Asset catalog 裡的名字。
    ///
    /// 命名規則（工程訂，已知會設計師）：`icon-<維度>-<英文值>`，全小寫、kebab-case。
    /// 帶維度前綴是因為之後還會有菜系角標（`icon-cuisine-japanese`，S3／S4 才用到），
    /// 沒有前綴的話「japanese」跟「rice」擺在一起看不出是兩個不同維度的東西。
    var assetName: String {
        "icon-form-\(Self.slug(for: self))"
    }

    private static func slug(for icon: FoodIcon) -> String {
        switch icon {
        case .noodles: "noodles"
        case .rice: "rice"
        case .soupDish: "soup"
        case .hotpot: "hotpot"
        case .snack: "snack"
        case .bread: "bread"
        case .lightMeal: "light-meal"
        case .meatDish: "meat"
        case .neutral: "neutral"
        }
    }

    /// 一道菜有多個吃法時取哪一個 —— 取第一個命中的。
    ///
    /// 「湯的」刻意排在很後面：它描述的是**狀態**不是主體，只有當一道菜沒有別的吃法時
    /// 它才代表這道菜。所以牛肉麵取「麵食」不取「湯的」，麻辣火鍋取「鍋物」不取「湯的」。
    static let formPriority: [FoodTag] = [
        .hotpot, .meatDish, .noodles, .rice, .bread, .snack, .soupDish, .lightMeal,
    ]

    static func icon(for item: FoodItem) -> Self {
        for tag in formPriority where item.tags.contains(tag) {
            return icon(for: tag) ?? .neutral
        }
        return .neutral
    }

    /// 吃法標籤對到圖示。回 `nil` 代表這個標籤不是吃法維度的。
    ///
    /// - Note: 呼叫端請用 `FoodItem.icon`，不要各自判一次 —— 同一條規則只能有一個來源。
    static func icon(for tag: FoodTag) -> FoodIcon? {
        switch tag {
        case .noodles: .noodles
        case .rice: .rice
        case .soupDish: .soupDish
        case .hotpot: .hotpot
        case .snack: .snack
        case .bread: .bread
        case .lightMeal: .lightMeal
        case .meatDish: .meatDish
        default: nil
        }
    }
}

extension FoodItem {
    /// 這道菜要畫哪一個圖示。
    ///
    /// 轉盤與卡片（S3／S4）共用這一個入口。**同一條規則只能有一個來源** ——
    /// 兩邊各判一次的話，改了優先序只有一邊會跟著動，而且那種不一致在畫面上
    /// 看起來只像「這張圖選得怪怪的」，不會有人聯想到是兩份邏輯分岔。
    var icon: FoodIcon { FoodIcon.icon(for: self) }
}
