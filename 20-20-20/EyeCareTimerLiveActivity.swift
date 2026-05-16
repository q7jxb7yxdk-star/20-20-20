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
    
    private func makeState(step: TimerStep, remainingSeconds: Double, endDate: Date, isRunning: Bool, isAlarming: Bool) -> EyeCareTimerLiveActivityAttributes.ContentState {
        EyeCareTimerLiveActivityAttributes.ContentState(
            stepName: step.name,
            themeName: themeName(for: step),
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
