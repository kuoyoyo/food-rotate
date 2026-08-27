import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

extension Color {
    /// App 的橘色 —— **讀 token，不再手抄。**
    ///
    /// 問題還是原來那一個：asset catalog 只屬於 App target，extension 讀不到，
    /// `Color.accentColor` 在這裡會退回系統藍（實測島上的進度條真的變成藍色）。
    /// 但以前的解法是在這裡寫死一組數字並註明出處，於是同一組橘色在專案裡有三份
    /// 手抄本，靠一句「改一邊就要改另一邊」的註解維持同步。
    ///
    /// 2026-08-27 改成：`DesignTokens.swift` 加進這個 target 的編譯來源
    /// （它只 import Foundation，跨 target 沒有障礙），直接讀
    /// `DesignTokens.accent`。色票 JSON 那一份則由
    /// `AccentColorTests.資產本身正確()` 跟 token 釘在一起。
    ///
    /// 所以現在**沒有任何一份是手抄的**，那句要人記得的註解可以刪掉了。
    static let brand = Color(uiColor: UIColor { traits in
        let token = traits.userInterfaceStyle == .dark
            ? DesignTokens.Dark.accent
            : DesignTokens.accent
        return UIColor(red: token.red, green: token.green, blue: token.blue, alpha: 1)
    })
}

@main
struct FoodRotateWidgetBundle: WidgetBundle {
    var body: some Widget {
        LoadingLiveActivity()
    }
}

/// 搜尋附近店家時的 Live Activity：鎖定畫面一張卡，Dynamic Island 三種尺寸。
struct LoadingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GenerationActivityAttributes.self) { context in
            LockScreenView(prompt: context.attributes.prompt, state: context.state)
                .activityBackgroundTint(Color.brand.opacity(0.12))
                .activitySystemActionForegroundColor(Color.brand)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("📍")
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.prompt.isEmpty ? "附近的店" : context.attributes.prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressBar(state: context.state)
                        Label(context.state.stage.title, systemImage: context.state.stage.symbolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Text("📍")
            } compactTrailing: {
                // 緊湊模式只有很窄的一條，固定寬度才不會被系統壓成一點點。
                ProgressBar(state: context.state)
                    .frame(width: 44)
            } minimal: {
                Image(systemName: context.state.stage.symbolName)
                    .foregroundStyle(Color.brand)
            }
            .keylineTint(Color.brand)
        }
    }
}

/// 進度條。跑的時候交給系統依時間畫，結束後換成靜態的滿格或空格。
///
/// `ProgressView(timerInterval:)` 是這裡的關鍵：它在系統端自己動，
/// App 不需要（也不被允許）每秒推一次更新。
private struct ProgressBar: View {
    let state: GenerationActivityAttributes.ContentState

    var body: some View {
        if state.stage.isRunning, state.estimatedFinish > state.startedAt {
            ProgressView(
                timerInterval: state.startedAt...state.estimatedFinish,
                countsDown: false,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .progressViewStyle(.linear)
            .tint(Color.brand)
        } else {
            ProgressView(value: isDone ? 1 : 0)
                .progressViewStyle(.linear)
                .tint(isDone ? Color.brand : .secondary)
        }
    }

    private var isDone: Bool {
        if case .done = state.stage { return true }
        return false
    }
}

/// 鎖定畫面與不支援 Dynamic Island 的機型看到的樣子。
private struct LockScreenView: View {
    let prompt: String
    let state: GenerationActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Text("📍")
                .font(.system(size: 34))

            VStack(alignment: .leading, spacing: 6) {
                Text(prompt.isEmpty ? "附近的店" : prompt)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                ProgressBar(state: state)

                Label(state.stage.title, systemImage: state.stage.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}
