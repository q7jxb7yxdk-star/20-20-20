import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Lock Screen Live Activity Widget

// This type must stay in sync with EyeCareTimerLiveActivityAttributes in the App target.
// The App target sends ContentState through ActivityKit, and the Widget Extension renders that state.
nonisolated struct EyeCareTimerLiveActivityAttributes: ActivityAttributes {
    // ContentState contains the values that the App updates during timer state changes.
    // While running, the widget uses endDate with the system timer renderer for live countdown text.
    // remainingSeconds is mainly used for paused text and AppIntent button calculations.
    public struct ContentState: Codable, Hashable {
        // Current step name, such as "Focus Work".
        var stepName: String
        // Current step index. AppIntent uses this to calculate the next step.
        var stepIndex: Int
        // Theme color as a simple string, such as blue / green / orange.
        var themeName: String
        // Start and end dates for the system timer renderer.
        // This lets the countdown continue after the App enters the background.
        var startDate: Date
        var endDate: Date
        // Paused state formats this value as m:ss.
        var remainingSeconds: Double
        // Whether the countdown is currently running.
        var isRunning: Bool
        // Whether the countdown has finished and entered the alarm state.
        var isAlarming: Bool
        // true means this Live Activity was created with debug test durations.
        var isDebugMode: Bool
        // AppIntent buttons write control commands here; the main App reads them and updates TimerManager.
        var controlCommand: String?
        // Each button press creates a new UUID so the main App does not process the same command twice.
        var controlCommandID: UUID?
    }
    
    // Static title used when the Activity is created.
    var title: String
}

struct EyeCareTimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        // ActivityConfiguration defines both:
        // 1. Lock Screen / Notification Center Live Activity UI.
        // 2. Dynamic Island compact / expanded / minimal UI.
        ActivityConfiguration(for: EyeCareTimerLiveActivityAttributes.self) { context in
            // context.state is the ContentState sent by the App target through ActivityKit.
            LiveActivityLockScreenView(state: context.state)
                // Lock Screen card background tint.
                .activityBackgroundTint(.black.opacity(0.62))
                // System action foreground color for system-provided highlights.
                .activitySystemActionForegroundColor(.orange)
                // Tapping empty Live Activity space opens the App.
                // The circular buttons use AppIntent, so they can control the timer without opening the App.
                .widgetURL(openURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    // expanded icon
                    Image(systemName: dynamicIslandIconName(for: context.state))
                        .foregroundStyle(themeColor(context.state.themeName))
                }
                
                DynamicIslandExpandedRegion(.center) {
                    LiveActivityExpandedView(state: context.state)
                }
            } compactLeading: {
                // compact icon
                // compact icon font size
                Image(systemName: dynamicIslandIconName(for: context.state))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(themeColor(context.state.themeName))
            } compactTrailing: {
                // compact time
                // Adjust compact time width and compact time font size in LiveActivityTimerText.Style.
                detailedTimerText(for: context.state, style: .dynamicIslandCompact)
                    .foregroundStyle(themeColor(context.state.themeName))
            } minimal: {
                // minimal icon
                // minimal icon font size
                Image(systemName: dynamicIslandIconName(for: context.state))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(themeColor(context.state.themeName))
            }
            // Tapping the rest of the Dynamic Island opens the App.
            .widgetURL(openURL)
        }
    }
}

// MARK: - Lock Screen UI

private struct LiveActivityLockScreenView: View {
    let state: EyeCareTimerLiveActivityAttributes.ContentState
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                liveActivityIconLink(
                    systemName: startPauseSystemName,
                    intent: ToggleEyeCareLiveActivityIntent(),
                    foreground: .orange,
                    // pause circle
                    background: .orange.opacity(0.34)
                )

                liveActivityIconLink(
                    systemName: "xmark",
                    intent: ResetEyeCareLiveActivityIntent(),
                    foreground: .white,
                    background: Color(.systemGray3).opacity(0.38)
                )
            }
            
            Spacer(minLength: 6)
            
            // ViewThatFits tries the horizontal layout first.
            // If Lock Screen width is tight, it falls back to a vertical layout to avoid clipped text.
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
        // Material background gives the card a translucent system-style surface.
        .background(.ultraThinMaterial.opacity(0.42), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }
    
    private var liveActivityTitle: some View {
        Text(state.isAlarming ? ExtensionAppText.timeUp : "20-20-20")
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(.orange)
    }
    
    private var liveActivityTime: some View {
        detailedTimerText(for: state, style: .lockScreen)
            .foregroundStyle(.orange)
    }
    
    private var startPauseSystemName: String {
        // Main Lock Screen button:
        // - Running: show pause and pause the timer.
        // - Paused or alarming: show play and start / advance the timer.
        state.isRunning ? "pause.fill" : "play.fill"
    }
}

// MARK: - Dynamic Island UI

private struct LiveActivityCompactView: View {
    let state: EyeCareTimerLiveActivityAttributes.ContentState
    
    var body: some View {
        VStack(spacing: 2) {
            detailedTimerText(for: state, style: .dynamicIslandCompactExpanded)
                .frame(maxWidth: .infinity, alignment: .trailing)
            
            Text(state.isAlarming ? ExtensionAppText.timeUp : state.stepName)
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
            // Dynamic Island expanded time
            detailedTimerText(for: state, style: .dynamicIslandExpanded)
                .frame(maxWidth: .infinity, alignment: .trailing)
            
            Text(state.isAlarming ? ExtensionAppText.timeUp : "20-20-20")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(themeColor(state.themeName))
    }
}

// MARK: - URL Actions

private var openURL: URL {
    URL(string: "eyecaretimer://live-activity/open")!
}

private func dynamicIslandIconName(for state: EyeCareTimerLiveActivityAttributes.ContentState) -> String {
    if state.isAlarming { return "bell.fill" }
    if state.isRunning { return "timer" }
    return "pause.circle"
}

private func liveActivityIconLink<Intent: AppIntent>(systemName: String, intent: Intent, foreground: Color, background: Color) -> some View {
    // Button(intent:) runs the AppIntent directly instead of opening the App like Link.
    // This is the native iOS pattern for interactive widgets and Live Activities.
    Button(intent: intent) {
        Image(systemName: systemName)
            // Lock Screen button icon size
            .font(.system(size: 28, weight: .semibold))
            // Lock Screen button icon frame width / height
            .frame(width: 56, height: 56)
            .foregroundStyle(foreground)
            .background(background, in: Circle())
    }
    .buttonStyle(.plain)
}

// MARK: - Formatting

@ViewBuilder
private func detailedTimerText(for state: EyeCareTimerLiveActivityAttributes.ContentState, style: LiveActivityTimerText.Style) -> some View {
    LiveActivityTimerText(state: state, style: style)
}

private struct LiveActivityTimerText: View {
    enum Style {
        case lockScreen
        case dynamicIslandCompact
        case dynamicIslandCompactExpanded
        case dynamicIslandExpanded
        
        var width: CGFloat {
            switch self {
            case .lockScreen:
                // Lock Screen time width
                return 140
            case .dynamicIslandCompact:
                // Dynamic Island compact time width
                return 42
            case .dynamicIslandCompactExpanded:
                // Dynamic Island compact-expanded time width
                return 72
            case .dynamicIslandExpanded:
                // Dynamic Island expanded time width
                return 86
            }
        }
        
        var minimumScaleFactor: CGFloat {
            switch self {
            case .lockScreen:
                return 0.64
            default:
                return 0.7
            }
        }
        
        var height: CGFloat? {
            switch self {
            case .lockScreen:
                // Lock Screen time height
                return 62
            default:
                return nil
            }
        }
    }
    
    let state: EyeCareTimerLiveActivityAttributes.ContentState
    let style: Style
    
    var body: some View {
        ZStack(alignment: .trailing) {
            if state.isAlarming {
                // Alarming state uses fixed 0:00 to avoid negative or stale countdown text.
                Text("0:00")
            } else if state.isRunning {
                // Running state uses the system timer renderer for active / inactive Lock Screen countdown.
                Text(timerInterval: state.startDate...state.endDate, countsDown: true)
            } else {
                // Paused state uses fixed remaining time so the display stops ticking.
                Text(detailedLiveActivityTimeText(from: state.remainingSeconds))
            }
        }
        .font(font)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(style.minimumScaleFactor)
        .frame(width: style.width, height: style.height, alignment: .trailing)
    }
    
    private var font: Font {
        switch style {
        case .lockScreen:
            // Lock Screen time font size
            return .system(size: 52, weight: .light, design: .rounded).monospacedDigit()
        case .dynamicIslandCompact:
            // Dynamic Island compact time font size
            return .system(size: 20, weight: .semibold, design: .rounded).monospacedDigit()
        case .dynamicIslandCompactExpanded:
            // Dynamic Island compact-expanded time font size
            return .title3.monospacedDigit().weight(.semibold)
        case .dynamicIslandExpanded:
            // Dynamic Island expanded time font size
            return .title2.monospacedDigit().weight(.semibold)
        }
    }
}

private func detailedLiveActivityTimeText(from seconds: Double) -> String {
    // ceil makes 59.2 seconds display as 1:00 / 60 seconds, which feels closer to a countdown timer.
    // max(0, ...) prevents negative time after the target date has passed.
    let totalSeconds = max(0, Int(ceil(seconds)))
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
}

private func themeColor(_ name: String) -> Color {
    // The App target sends a simple string; the Widget target converts it back to a SwiftUI Color here.
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
