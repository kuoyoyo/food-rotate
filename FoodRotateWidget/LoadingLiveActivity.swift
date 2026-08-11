import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

extension Color {
    /// App 的橘色。
    ///
    /// **這是 `Assets.xcassets/AccentColor` 的複本，改一邊就要改另一邊。**
    /// asset catalog 只屬於 App target，extension 讀不到，`Color.accentColor`
    /// 在這裡會退回系統藍——實測島上的進度條真的變成藍色。
    /// 把整個 catalog 複製一份到 extension 是更大的重複，所以選擇在這裡寫死並註明出處。
    static let brand = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.000, green: 0.478, blue: 0.263, alpha: 1)
            : UIColor(red: 0.937, green: 0.396, blue: 0.176, alpha: 1)
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
