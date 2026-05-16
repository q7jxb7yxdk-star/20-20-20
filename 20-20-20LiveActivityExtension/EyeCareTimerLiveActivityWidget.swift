import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Lock Screen Live Activity Widget

// 這個型別要和 App target 裡的 EyeCareTimerLiveActivityAttributes 保持一致。
// App target 會把 ContentState 傳給 ActivityKit；Widget Extension 會收到同一份 state 來畫 UI。
nonisolated struct EyeCareTimerLiveActivityAttributes: ActivityAttributes {
    // ContentState 是會被 App 不斷更新的資料。
    // Live Activity 不是自己跑 Timer，而是靠 App 定期推送新的 remainingSeconds。
    public struct ContentState: Codable, Hashable {
        // 目前階段名稱，例如「專注工作」。
        var stepName: String
        // 目前階段 index，AppIntent 會用它計算下一階段。
        var stepIndex: Int
        // 簡單字串形式的主題色，例如 blue / green / orange。
        var themeName: String
        // 保留開始與結束時間，方便日後如果要改用系統 timer renderer。
        var startDate: Date
        var endDate: Date
        // 目前主要用這個值格式化成 m:ss。
        var remainingSeconds: Double
        // 是否正在倒數。
        var isRunning: Bool
        // 是否已經倒數完成並進入響鈴狀態。
        var isAlarming: Bool
        // true 代表目前 Live Activity 用 Debug 測試時間。
        var isDebugMode: Bool
        // AppIntent 按鈕會把控制命令寫入這裡，主 App 再讀取並真正控制 TimerManager。
        var controlCommand: String?
        // 每次按鈕產生新的 UUID，避免同一個命令被主 App 重複處理。
        var controlCommandID: UUID?
    }
    
    // 建立 Activity 時固定的標題。
    var title: String
}

struct EyeCareTimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        // ActivityConfiguration 會同時定義：
        // 1. Lock Screen / Notification Center 的 Live Activity UI。
        // 2. Dynamic Island 的 compact / expanded / minimal UI。
        ActivityConfiguration(for: EyeCareTimerLiveActivityAttributes.self) { context in
            // context.state 就是 App target 透過 ActivityKit 傳過來的 ContentState。
            LiveActivityLockScreenView(state: context.state)
                // Lock Screen 卡片背景色。這裡用半透明黑色接近 iOS Clock timer 的感覺。
                .activityBackgroundTint(.black.opacity(0.62))
                // 系統 action 前景色，例如某些系統按鈕或強調色。
                .activitySystemActionForegroundColor(.orange)
                // 點擊 Live Activity 空白區域時打開 App。
                // 兩個圓形按鈕改用 AppIntent，所以按下按鈕時可以直接控制，不需要打開 App。
                .widgetURL(openURL)
        } dynamicIsland: { context in
            DynamicIsland {
                // 展開 Dynamic Island 後，左側放一個狀態 icon。
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isAlarming ? "bell.fill" : "timer")
                        .foregroundStyle(themeColor(context.state.themeName))
                }
                
                // 展開 Dynamic Island 後，中間顯示完整倒數和 App 名稱。
                DynamicIslandExpandedRegion(.center) {
                    LiveActivityExpandedView(state: context.state)
                }
            } compactLeading: {
                // compact 狀態左邊只放 icon，避免 Dynamic Island 過長。
                Image(systemName: context.state.isAlarming ? "bell.fill" : "timer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeColor(context.state.themeName))
            } compactTrailing: {
                // compact 狀態右邊顯示完整 m:ss。
                // 字體和寬度要控制，否則可能遮住狀態列時間、訊號和電量。
                detailedTimerText(for: context.state)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 52, alignment: .trailing)
                    .foregroundStyle(themeColor(context.state.themeName))
            } minimal: {
                // minimal 狀態空間極少，只顯示 icon。
                Image(systemName: context.state.isAlarming ? "bell.fill" : "timer")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(themeColor(context.state.themeName))
            }
            // 點擊 Dynamic Island 其他位置時打開 App。
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
        // material 背景令卡片有 Liquid Glass 類似的半透明質感。
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
        detailedTimerText(for: state)
            // monospacedDigit 令每個數字等寬，倒數跳秒時文字不會左右抖動。
            .font(.system(size: 52, weight: .light, design: .rounded).monospacedDigit())
            // 如果某些機型寬度不足，允許文字縮細，避免被截斷。
            .minimumScaleFactor(0.64)
            .lineLimit(1)
            // 固定一個最小寬度並靠右，倒數時間視覺上會更像系統 Clock app。
            .frame(minWidth: 118, alignment: .trailing)
            .foregroundStyle(.orange)
    }
    
    private var startPauseSystemName: String {
        // Live Activity 左邊主按鈕：
        // - 倒數中：顯示 pause，按下會暫停。
        // - 已暫停或時間到：顯示 play，按下會開始 / 進入下一階段。
        state.isRunning ? "pause.fill" : "play.fill"
    }
}

// MARK: - Dynamic Island UI

private struct LiveActivityCompactView: View {
    let state: EyeCareTimerLiveActivityAttributes.ContentState
    
    var body: some View {
        VStack(spacing: 2) {
            detailedTimerText(for: state)
                .font(.title3.monospacedDigit().weight(.semibold))
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
            // 展開 Dynamic Island 時空間比較多，可以用較大的完整秒數倒數。
            detailedTimerText(for: state)
                .font(.title2.monospacedDigit().weight(.semibold))
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

private func liveActivityIconLink<Intent: AppIntent>(systemName: String, intent: Intent, foreground: Color, background: Color) -> some View {
    // Button(intent:) 會直接執行 AppIntent，不會像 Link 一樣打開 App。
    // 這是 iOS 互動式 Widget / Live Activity 的原生做法。
    Button(intent: intent) {
        Image(systemName: systemName)
            .font(.system(size: 28, weight: .semibold))
            .frame(width: 56, height: 56)
            .foregroundStyle(foreground)
            .background(background, in: Circle())
    }
    .buttonStyle(.plain)
}

// MARK: - Formatting

@ViewBuilder
private func detailedTimerText(for state: EyeCareTimerLiveActivityAttributes.ContentState) -> some View {
    if state.isAlarming {
        // 已經響鈴時固定顯示 0:00，避免倒數完成後繼續顯示負數或舊時間。
        Text("0:00")
    } else {
        Text(detailedLiveActivityTimeText(from: state.remainingSeconds))
    }
}

private func detailedLiveActivityTimeText(from seconds: Double) -> String {
    // ceil 代表 59.2 秒會顯示 1:00 / 60 秒，視覺上比較接近倒數器。
    // max(0, ...) 避免時間過了之後出現負數。
    let totalSeconds = max(0, Int(ceil(seconds)))
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
}

private func themeColor(_ name: String) -> Color {
    // App target 傳過來的是簡單字串；Widget target 在這裡轉成 SwiftUI Color。
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
