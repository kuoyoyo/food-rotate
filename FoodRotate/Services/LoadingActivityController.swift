import ActivityKit
import Foundation
import UIKit

/// 搜尋附近店家期間的 Live Activity 生命週期，以及一起附上的背景執行時間。
///
/// 兩件事綁在一起是刻意的：Live Activity 的意義就是讓人**可以離開 App 去做別的事**，
/// 但一離開，定位與地圖搜尋就會被系統暫停，島上的進度條卻還在跑。
/// 進度條跑完回到 App 才發現請求根本沒動，那比沒有這個功能還糟。
/// 所以只要開了 Live Activity，就一定要同時申請背景執行時間，兩者一起開一起收。
///
/// **只有「去哪吃」模式會用到這個。** 「吃什麼」模式是本地查表，瞬間就有結果，
/// 硬要在島上顯示一條進度條就是在演戲。
@MainActor
final class LoadingActivityController {
    /// 只留 id，不留 `Activity` 本身。
    ///
    /// `ActivityKit.Activity` 沒有宣告 `Sendable`（確認過 SDK 的 `.swiftinterface`），
    /// 而 `update`／`end` 都是 nonisolated async。把它存成 MainActor 隔離的屬性再送進去，
    /// Swift 6 會直接擋下來（sending main actor-isolated value）。
    /// 存 id、要用的時候在 nonisolated 情境下從 `Activity.activities` 查回來，
    /// 就完全不需要 `nonisolated(unsafe)` 這種開後門的寫法。
    private var activityID: String?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var startedAt: Date = .now
    private var estimatedFinish: Date = .now

    /// 開始一輪。使用者關掉 Live Activity 權限時整個安靜地不做事，不能讓產生流程因此失敗。
    func start(prompt: String, estimate: TimeInterval) {
        beginBackgroundTask()

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activityID == nil else { return }

        startedAt = .now
        estimatedFinish = startedAt.addingTimeInterval(estimate)

        let state = GenerationActivityAttributes.ContentState(
            stage: .locating,
            startedAt: startedAt,
            estimatedFinish: estimatedFinish
        )
        // staleDate 給估計時間的兩倍：App 被殺掉時系統至少知道這張卡已經不可信，
        // 不會留一個永遠在跑的進度條在鎖定畫面上。
        let content = ActivityContent(state: state, staleDate: startedAt.addingTimeInterval(estimate * 2))

        activityID = try? Activity.request(
            attributes: GenerationActivityAttributes(prompt: prompt),
            content: content
        ).id
    }

    /// 真實階段轉換時才呼叫。刻意不做定時更新——Live Activity 的更新有頻率限制，
    /// 進度條本來就交給系統依 `timerInterval` 自己畫。
    func update(stage: GenerationActivityAttributes.Stage) {
        guard let id = activityID else { return }
        let state = makeState(stage: stage)
        Task.detached {
            await Self.activity(id: id)?.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    /// 收尾。終態先顯示幾秒再自己消失，讓使用者在鎖定畫面上也看得到結果。
    func end(stage: GenerationActivityAttributes.Stage) {
        endBackgroundTask()

        guard let id = activityID else { return }
        activityID = nil

        let state = makeState(stage: stage)
        Task.detached {
            await Self.activity(id: id)?.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(.now + 4)
            )
        }
    }

    /// 使用者自己放棄了這一輪（切換模式、改條件重搜）。
    ///
    /// **跟 `end(stage: .failed)` 不一樣，這件事要分開。** 那個會在鎖定畫面上
    /// 留一張寫著「失敗」的卡四秒 —— 但沒有任何事情失敗，是使用者改變主意。
    /// 把使用者的取消說成失敗，跟把「附近沒有店」說成「服務故障」是同一種錯。
    /// 這裡直接讓卡消失，不留終態。
    func cancel() {
        endBackgroundTask()

        guard let id = activityID else { return }
        activityID = nil

        Task.detached {
            await Self.activity(id: id)?.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// 收掉上次留下的孤兒。App 在產生途中被強制關閉時，那張卡不會自己消失。
    nonisolated static func endStaleActivities() async {
        for activity in Activity<GenerationActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func makeState(stage: GenerationActivityAttributes.Stage) -> GenerationActivityAttributes.ContentState {
        GenerationActivityAttributes.ContentState(
            stage: stage,
            startedAt: startedAt,
            estimatedFinish: estimatedFinish
        )
    }

    private nonisolated static func activity(id: String) -> Activity<GenerationActivityAttributes>? {
        Activity<GenerationActivityAttributes>.activities.first { $0.id == id }
    }

    // MARK: - 背景執行時間

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "搜尋附近店家") { [weak self] in
            // 系統要收回時間了。這裡只做釋放，搜尋本身會照原本的逾時處理失敗。
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
