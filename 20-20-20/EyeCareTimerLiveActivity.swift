#if os(iOS)
import ActivityKit
import SwiftUI

// MARK: - iOS Lock Screen Live Activity 資料

// Live Activity 的 attributes 要同 Widget Extension 使用同一個型別名稱和欄位。
// App 負責建立 / 更新資料；Widget Extension 負責把資料畫到 Lock Screen。
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

@MainActor
final class EyeCareLiveActivityManager {
    static let shared = EyeCareLiveActivityManager()
    
    private init() {}
    
    func startOrUpdate(step: TimerStep, remainingSeconds: Double, endDate: Date, isRunning: Bool, isAlarming: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let state = makeState(
            step: step,
            remainingSeconds: remainingSeconds,
            endDate: endDate,
            isRunning: isRunning,
            isAlarming: isAlarming
        )
        
        Task {
            if let activity = Activity<EyeCareTimerLiveActivityAttributes>.activities.first {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            } else {
                do {
                    let attributes = EyeCareTimerLiveActivityAttributes(title: "20-20-20")
                    _ = try Activity.request(
                        attributes: attributes,
                        content: ActivityContent(state: state, staleDate: nil),
                        pushType: nil
                    )
                } catch {
                    print("Live Activity 建立失敗: \(error)")
                }
            }
        }
    }
    
    func end() {
        Task {
            for activity in Activity<EyeCareTimerLiveActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
    
    func finishAndEnd(step: TimerStep) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        // 倒數剛完成時先更新成一個穩定的 00:00 狀態。
        // 這比同一刻直接 .immediate dismiss 更溫和，可避開 Simulator SpringBoard 在邊界時間 render Live Activity 時崩潰。
        let finishedState = makeState(
            step: step,
            remainingSeconds: 0,
            endDate: Date(),
            isRunning: false,
            isAlarming: true
        )
        
        Task {
            for activity in Activity<EyeCareTimerLiveActivityAttributes>.activities {
                await activity.update(ActivityContent(state: finishedState, staleDate: nil))
            }
        }
    }
    
    private func makeState(step: TimerStep, remainingSeconds: Double, endDate: Date, isRunning: Bool, isAlarming: Bool) -> EyeCareTimerLiveActivityAttributes.ContentState {
        let duration = max(1, remainingSeconds)
        let startDate = endDate.addingTimeInterval(-duration)
        
        return EyeCareTimerLiveActivityAttributes.ContentState(
            stepName: step.name,
            themeName: themeName(for: step),
            startDate: startDate,
            endDate: endDate,
            remainingSeconds: remainingSeconds,
            isRunning: isRunning,
            isAlarming: isAlarming
        )
    }
    
    private func themeName(for step: TimerStep) -> String {
        switch step {
        case .eyeCare:
            return "green"
        case .longRest:
            return "orange"
        case .work1, .work2:
            return "blue"
        }
    }
}
#endif
