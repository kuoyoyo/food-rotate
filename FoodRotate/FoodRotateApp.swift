import SwiftData
import SwiftUI

/// 食物轉盤 Food Rotate
///
/// Claude Code 製作 · kuoyo 設計
@main
struct FoodRotateApp: App {
    /// 歷史紀錄壞掉時不應該讓整個 App 開不起來，所以退回記憶體內的 container。
    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: SpinRecord.self)
        } catch {
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: SpinRecord.self, configurations: fallback)
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                // 上一輪在產生途中被強制關閉的話，那張 Live Activity 不會自己消失，
                // 會留一個永遠在跑的進度條在鎖定畫面上。開 App 時先收乾淨。
                .task { await LoadingActivityController.endStaleActivities() }
                #if DEBUG
                // 缺圖示不會當掉也不會報錯，只會讓轉盤那一格空著。開 App 就講清楚缺哪幾張。
                //
                // **這段一定要在畫面出現之後才跑，不能放在 `App.init()`。**
                // `missingReport()` 會呼叫 `UIImage(named:)`，在 init 裡碰 asset catalog
                // 會早於 UIKit 套用全域主色，之後整個 App 的 `Color.accentColor` 會退回系統藍
                // （2026-08-11 實際發生過，S2 驗收擋下）。晚 0.1 秒印一行訊息沒有任何差別。
                .task {
                    if let report = FoodIconAssets.missingReport() {
                        print(report)
                    }
                }
                #endif
        }
        .modelContainer(container)
    }
}
