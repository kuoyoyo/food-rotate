import Foundation

/// 轉盤上一格的文字排版規則。
///
/// 抽成不依賴 SwiftUI 的純資料，理由跟 `WheelGeometry` 一樣：這段最容易在改版時
/// 悄悄退化成「看起來還好但其實截斷了」，必須測得到。
///
/// 值的來源：`Design/設計規格-Theme-v1.md` 第七節（S1a，已核可）。
enum WheelLabel {

    /// 把菜名斷成一到兩行。**永遠不截斷。**
    ///
    /// 舊的做法是超過 5 字就砍掉補省略號，於是「西班牙海鮮燉飯」變成「西班牙海…」——
    /// 轉盤上看不出那是什麼，等於這一格白給。改成兩行之後，資料庫最長的 7 字
    /// 用兩行（4+3）放得下，容量是 8 字。
    static func lines(for name: String) -> [String] {
        let characters = Array(name)
        guard characters.count >= 5 else { return [name] }

        // 前面那行取一半（奇數字時前行多一個）。前行長一點比後行長一點好看，
        // 因為文字是沿半徑排的，外圈那行本來就有比較多空間。
        let split = (characters.count + 1) / 2
        return [
            String(characters[..<split]),
            String(characters[split...]),
        ]
    }

    /// 一格的尺寸規格。字級與圖示尺寸以**半徑 150pt**（360pt 轉盤）為基準，
    /// 實作時依 `radius / 150` 等比縮放。
    struct Metrics: Equatable, Sendable {
        /// 菜名字級。
        let fontSize: Double
        /// 行距倍率（兩行時才用得到）。
        let lineSpacing: Double
        /// 圖示邊長。
        let iconSize: Double
        /// 文字中心離圓心多遠，比例。
        let textRadiusRatio: Double
        /// 圖示中心離圓心多遠，比例。
        let iconRadiusRatio: Double
    }

    /// 這個格數該用哪一組尺寸。
    ///
    /// 格數理論上只會是 4／6／8／10／12，但轉盤實際畫幾格是看**抽到幾道菜**，
    /// 條件太嚴時可能只有 3 道。沒列在表裡的就取「不小於它的最近格數」——
    /// 格數越少扇形越寬，用比較寬鬆那組一定放得下。
    static func metrics(forSlotCount count: Int) -> Metrics {
        switch count {
        case ..<5: table[4]!
        case 5...6: table[6]!
        case 7...8: table[8]!
        case 9...10: table[10]!
        default: table[12]!
        }
    }

    private static let table: [Int: Metrics] = [
        4: Metrics(fontSize: 17, lineSpacing: 1.15, iconSize: 30, textRadiusRatio: 0.72, iconRadiusRatio: 0.42),
        6: Metrics(fontSize: 15, lineSpacing: 1.15, iconSize: 26, textRadiusRatio: 0.74, iconRadiusRatio: 0.43),
        8: Metrics(fontSize: 13.5, lineSpacing: 1.12, iconSize: 22, textRadiusRatio: 0.76, iconRadiusRatio: 0.44),
        10: Metrics(fontSize: 12, lineSpacing: 1.10, iconSize: 19, textRadiusRatio: 0.77, iconRadiusRatio: 0.45),
        12: Metrics(fontSize: 11, lineSpacing: 1.08, iconSize: 17, textRadiusRatio: 0.78, iconRadiusRatio: 0.46),
    ]

    /// 規格的基準半徑。實際半徑除以它就是縮放倍率。
    static let referenceRadius: Double = 150

    /// 字級的下限。轉盤放在小螢幕上時不讓字跟著縮到看不見 —— 沿用改版前的下限。
    static let minimumFontSize: Double = 10
}
