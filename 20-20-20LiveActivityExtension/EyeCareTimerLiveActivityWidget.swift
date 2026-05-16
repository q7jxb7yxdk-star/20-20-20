import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Lock Screen Live Activity Widget

struct EyeCareTimerLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var stepName: String
        var themeName: String
        var startDate: Date
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
                .activityBackgroundTint(.black.opacity(0.62))
                .activitySystemActionForegroundColor(.orange)
                .widgetURL(openURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isAlarming ? "bell.fill" : "timer")
                        .foregroundStyle(themeColor(context.state.themeName))
                }
                
                DynamicIslandExpandedRegion(.center) {
                    LiveActivityExpandedView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.isAlarming ? "bell.fill" : "timer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeColor(context.state.themeName))
            } compactTrailing: {
                detailedTimerText(for: context.state)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 52, alignment: .trailing)
                    .foregroundStyle(themeColor(context.state.themeName))
            } minimal: {
                Image(systemName: context.state.isAlarming ? "bell.fill" : "timer")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(themeColor(context.state.themeName))
            }
            .widgetURL(openURL)
        }
    }
}

private struct LiveActivityLockScreenView: View {
    let state: EyeCareTimerLiveActivityAttributes.ContentState
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                liveActivityIconLink(
                    systemName: "pause.fill",
                    url: pauseURL,
                    foreground: .orange,
                    background: .orange.opacity(0.34)
                )

                liveActivityIconLink(
                    systemName: "xmark",
                    url: resetURL,
                    foreground: .white,
                    background: Color(.systemGray3).opacity(0.38)
                )
            }
            
            Spacer(minLength: 6)
            
            // ViewThatFits 會先嘗試橫向排版；如果 Lock Screen 寬度不足，
            // 就自動改成上下排，避免「20-20-20」或倒數時間被截走。
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    liveActivityTitle
                    liveActivityTime
                }
                
                VStack(alignment: .trailing, spacing: 2) {
                    liveActivityTitle
                    liveActivityTime
                }
            }
            .layoutPriority(1)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(.ultraThinMaterial.opacity(0.42), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }
    
    private var liveActivityTitle: some View {
        Text(state.isAlarming ? "時間到" : "20-20-20")
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(.orange)
    }
    
    private var liveActivityTime: some View {
        detailedTimerText(for: state)
            .font(.system(size: 52, weight: .light, design: .rounded).monospacedDigit())
            .minimumScaleFactor(0.64)
            .lineLimit(1)
            .frame(minWidth: 118, alignment: .trailing)
            .foregroundStyle(.orange)
    }
}

private struct LiveActivityCompactView: View {
    let state: EyeCareTimerLiveActivityAttributes.ContentState
    
    var body: some View {
        VStack(spacing: 2) {
            detailedTimerText(for: state)
                .font(.title3.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
            
            Text(state.isAlarming ? "時間到" : state.stepName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(themeColor(state.themeName))
    }
}

private struct LiveActivityExpandedView: View {
    let state: EyeCareTimerLiveActivityAttributes.ContentState
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            detailedTimerText(for: state)
                .font(.title2.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
            
            Text(state.isAlarming ? "時間到" : "20-20-20")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(themeColor(state.themeName))
    }
}

private var pauseURL: URL {
    URL(string: "eyecaretimer://live-activity/pause")!
}

private var resetURL: URL {
    URL(string: "eyecaretimer://live-activity/reset")!
}

private var openURL: URL {
    URL(string: "eyecaretimer://live-activity/open")!
}

private func liveActivityIconLink(systemName: String, url: URL, foreground: Color, background: Color) -> some View {
    Link(destination: url) {
        Image(systemName: systemName)
            .font(.system(size: 28, weight: .semibold))
            .frame(width: 56, height: 56)
            .foregroundStyle(foreground)
            .background(background, in: Circle())
    }
}

@ViewBuilder
private func detailedTimerText(for state: EyeCareTimerLiveActivityAttributes.ContentState) -> some View {
    if state.isAlarming {
        Text("0:00")
    } else {
        Text(detailedLiveActivityTimeText(from: state.remainingSeconds))
    }
}

private func detailedLiveActivityTimeText(from seconds: Double) -> String {
    let totalSeconds = max(0, Int(ceil(seconds)))
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
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
