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
        }
        .modelContainer(container)
    }
}
