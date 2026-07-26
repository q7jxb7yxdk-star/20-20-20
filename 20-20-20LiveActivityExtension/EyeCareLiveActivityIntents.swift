import ActivityKit
import AppIntents
import Foundation

// MARK: - Live Activity Interactive Button Intents

// 這個檔案只放 Widget / Live Activity 按鈕用的 AppIntent。
// Button(intent:) 會在 extension / intent 環境直接執行 perform()，不需要打開 App。
//
// 注意：AppIntent 不是 App 畫面裡的 TimerManager。
// 它可以直接更新 Live Activity 的 ContentState，但不能直接操作 App 記憶體中的 TimerManager instance。

struct ToggleEyeCareLiveActivityIntent: LiveActivityIntent {
    nonisolated static var title: LocalizedStringResource {
        "Start / Pause"
    }
    nonisolated static var description: IntentDescription {
        "Start, pause, or confirm the current 20-20-20 timer step."
    }
    nonisolated static let openAppWhenRun = false
    
    nonisolated init() {}
    
    func perform() async throws -> some IntentResult {
        for activity in Activity<EyeCareTimerLiveActivityAttributes>.activities {
            let state = activity.content.state
            let newState: EyeCareTimerLiveActivityAttributes.ContentState
            
            if state.isAlarming {
                // 時間到之後，按下 play 代表「確認並停在下一階段」。
                newState = Self.nextPausedState(from: state)
            } else if state.isRunning {
                // 正在倒數時，按下 pause 代表暫停。
                newState = Self.pausedState(from: state)
            } else {
                // 已暫停時，按下 play 代表用剩餘時間繼續倒數。
                newState = Self.runningState(from: state)
            }
            
            await activity.update(ActivityContent(state: Self.state(newState, withCommand: "toggle"), staleDate: nil))
        }
        
        return .result()
    }
    
    private static func pausedState(from state: EyeCareTimerLiveActivityAttributes.ContentState) -> EyeCareTimerLiveActivityAttributes.ContentState {
        let remainingSeconds = max(0, state.endDate.timeIntervalSinceNow)
        let endDate = Date().addingTimeInterval(remainingSeconds)
        
        return EyeCareTimerLiveActivityAttributes.ContentState(
            stepName: state.stepName,
            stepIndex: state.stepIndex,
            themeName: state.themeName,
            startDate: endDate.addingTimeInterval(-max(1, remainingSeconds)),
            endDate: endDate,
            remainingSeconds: remainingSeconds,
            isRunning: false,
            isAlarming: false,
            isDebugMode: state.isDebugMode,
            controlCommand: state.controlCommand,
            controlCommandID: state.controlCommandID
        )
    }
    
    private static func runningState(from state: EyeCareTimerLiveActivityAttributes.ContentState) -> EyeCareTimerLiveActivityAttributes.ContentState {
        let remainingSeconds = max(1, state.remainingSeconds)
        let endDate = Date().addingTimeInterval(remainingSeconds)
        
        return EyeCareTimerLiveActivityAttributes.ContentState(
            stepName: state.stepName,
            stepIndex: state.stepIndex,
            themeName: state.themeName,
            startDate: Date(),
            endDate: endDate,
            remainingSeconds: remainingSeconds,
            isRunning: true,
            isAlarming: false,
            isDebugMode: state.isDebugMode,
            controlCommand: state.controlCommand,
            controlCommandID: state.controlCommandID
        )
    }
    
    private static func nextPausedState(from state: EyeCareTimerLiveActivityAttributes.ContentState) -> EyeCareTimerLiveActivityAttributes.ContentState {
        let nextStepIndex = (state.stepIndex + 1) % Self.stepCount
        let duration = Self.duration(for: nextStepIndex, isDebugMode: state.isDebugMode)
        let endDate = Date().addingTimeInterval(duration)
        
        return EyeCareTimerLiveActivityAttributes.ContentState(
            stepName: Self.stepName(for: nextStepIndex),
            stepIndex: nextStepIndex,
            themeName: Self.themeName(for: nextStepIndex),
            startDate: endDate.addingTimeInterval(-duration),
            endDate: endDate,
            remainingSeconds: duration,
            isRunning: false,
            isAlarming: false,
            isDebugMode: state.isDebugMode,
            controlCommand: state.controlCommand,
            controlCommandID: state.controlCommandID
        )
    }
    
    private nonisolated static let stepCount = 4
    
    private nonisolated static func stepName(for index: Int) -> String {
        switch index {
        case 0:
            return ExtensionAppText.stepName(for: 0)
        case 1:
            return ExtensionAppText.stepName(for: 1)
        case 2:
            return ExtensionAppText.stepName(for: 2)
        default:
            return ExtensionAppText.stepName(for: 3)
        }
    }
    
    private nonisolated static func themeName(for index: Int) -> String {
        switch index {
        case 1:
            return "green"
        case 3:
            return "orange"
        default:
            return "blue"
        }
    }
    
    private nonisolated static func duration(for index: Int, isDebugMode: Bool) -> Double {
        if isDebugMode {
            switch index {
            case 0, 2:
                return 10
            case 1:
                return 5
            default:
                return 8
            }
        } else {
            switch index {
            case 0, 2:
                return 20 * 60
            case 1:
                return 20
            default:
                return 3 * 60
            }
        }
    }
    
    private static func state(
        _ state: EyeCareTimerLiveActivityAttributes.ContentState,
        withCommand command: String
    ) -> EyeCareTimerLiveActivityAttributes.ContentState {
        EyeCareTimerLiveActivityAttributes.ContentState(
            stepName: state.stepName,
            stepIndex: state.stepIndex,
            themeName: state.themeName,
            startDate: state.startDate,
            endDate: state.endDate,
            remainingSeconds: state.remainingSeconds,
            isRunning: state.isRunning,
            isAlarming: state.isAlarming,
            isDebugMode: state.isDebugMode,
            controlCommand: command,
            controlCommandID: UUID()
        )
    }
}

struct ResetEyeCareLiveActivityIntent: LiveActivityIntent {
    nonisolated static var title: LocalizedStringResource {
        "End"
    }
    nonisolated static var description: IntentDescription {
        "End the current 20-20-20 timer."
    }
    nonisolated static let openAppWhenRun = false
    
    nonisolated init() {}
    
    func perform() async throws -> some IntentResult {
        for activity in Activity<EyeCareTimerLiveActivityAttributes>.activities {
            let state = activity.content.state
            let commandState = EyeCareTimerLiveActivityAttributes.ContentState(
                stepName: state.stepName,
                stepIndex: state.stepIndex,
                themeName: state.themeName,
                startDate: state.startDate,
                endDate: state.endDate,
                remainingSeconds: state.remainingSeconds,
                isRunning: false,
                isAlarming: false,
                isDebugMode: state.isDebugMode,
                controlCommand: "reset",
                controlCommandID: UUID()
            )
            await activity.update(ActivityContent(state: commandState, staleDate: nil))
        }
        
        return .result()
    }
}
