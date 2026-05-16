import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Lock Screen Live Activity Widget

struct EyeCareTimerLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var stepName: String
        var themeName: String
        var endDate: Date
        var remainingSeconds: Double
        var isRunning: Bool
        var isAlarming: Bool
    }
    
    var title: String
}

struct EyeCareTimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EyeCareTimerLiveActivityAttributes.self) { context in
            LiveActivityLockScreenView(state: context.state)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(themeColor(context.state.themeName))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    LiveActivityCompactView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.isAlarming ? "bell.fill" : "eye.fill")
                    .foregroundStyle(themeColor(context.state.themeName))
            } compactTrailing: {
                timerText(for: context.state)
                    .monospacedDigit()
                    .foregroundStyle(themeColor(context.state.themeName))
            } minimal: {
                Image(systemName: "eye.fill")
                    .foregroundStyle(themeColor(context.state.themeName))
            }
        }
    }
}

private struct LiveActivityLockScreenView: View {
    let state: EyeCareTimerLiveActivityAttributes.ContentState
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.isAlarming ? "bell.fill" : "eye.fill")
                .font(.title2)
                .foregroundStyle(themeColor(state.themeName))
                .frame(width: 34, height: 34)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(state.isAlarming ? "時間到！" : state.stepName)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(state.isRunning ? "倒數進行中" : "已暫停")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            timerText(for: state)
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(themeColor(state.themeName))
                .contentTransition(.numericText())
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}

private struct LiveActivityCompactView: View {
    let state: EyeCareTimerLiveActivityAttributes.ContentState
    
    var body: some View {
        HStack {
            Text(state.stepName)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            timerText(for: state)
                .font(.headline.monospacedDigit())
        }
        .foregroundStyle(themeColor(state.themeName))
    }
}

@ViewBuilder
private func timerText(for state: EyeCareTimerLiveActivityAttributes.ContentState) -> some View {
    if state.isAlarming {
        Text("00:00")
    } else if state.isRunning {
        Text(timerInterval: Date()...state.endDate, countsDown: true)
    } else {
        Text(formattedTime(from: state.remainingSeconds))
    }
}

private func formattedTime(from seconds: Double) -> String {
    let totalSeconds = max(0, Int(ceil(seconds)))
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d:%02d", minutes, seconds)
}

private func themeColor(_ name: String) -> Color {
    switch name {
    case "green":
        return .green
    case "orange":
        return .orange
    default:
        return .blue
    }
}

@main
struct EyeCareTimerLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        EyeCareTimerLiveActivityWidget()
    }
}
