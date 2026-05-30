#if os(iOS)
import ActivityKit
import SwiftUI

// MARK: - iOS Lock Screen Live Activity 資料

// Live Activity 分成兩邊：
// 1. App target：負責建立 Activity、定期更新倒數資料、結束 Activity。
// 2. Widget Extension target：負責把這些資料畫成 Lock Screen / Dynamic Island UI。
//
// 兩邊都要宣告相同名稱、相同欄位的 Attributes 型別。
// ActivityKit 會用這個型別把 App 傳出的資料交給 Widget Extension。
nonisolated struct EyeCareTimerLiveActivityAttributes: ActivityAttributes {
    // ContentState 是「會隨時間改變」的資料。
    // 例如剩餘秒數、是否正在響鈴、目前階段名稱，都會在倒數途中更新。
    public struct ContentState: Codable, Hashable {
        // 顯示目前階段，例如「專注工作」、「遠眺放鬆」。
        var stepName: String
        // 目前階段的 index，讓 Live Activity 按鈕不用打開 App 也知道下一階段是哪一個。
        var stepIndex: Int
        // Widget Extension 不直接認識 TimerStep enum，所以用簡單字串傳主題色。
        var themeName: String
        // 倒數開始時間；Widget 會連同 endDate 交給系統 timer renderer 顯示持續倒數。
        var startDate: Date
        // 倒數目標結束時間；App 進入背景後，Live Activity 仍可靠這個時間點繼續倒數。
        var endDate: Date
        // 剩餘秒數。Widget 在暫停狀態和按鈕 intent 會用它計算 / 格式化成 m:ss。
        var remainingSeconds: Double
        // true 代表計時器正在跑；false 代表暫停或已完成。
        var isRunning: Bool
        // true 代表倒數已完成並進入響鈴 / 等待確認狀態。
        var isAlarming: Bool
        // 記錄建立 Live Activity 時使用 Debug 還是 Release 時間，讓 AppIntent 可計算下一階段秒數。
        var isDebugMode: Bool
        // Live Activity 按鈕不能直接碰 App 內的 TimerManager。
        // 所以按鈕會先把 command 寫入 Activity state，TimerManager 再讀取並執行。
        var controlCommand: String?
        // 每次按鈕都產生新的 UUID；TimerManager 用它分辨「新命令」和「已處理過的命令」。
        var controlCommandID: UUID?
    }
    
    // Attributes 本身是「建立 Activity 後通常不變」的資料。
    // 這裡只放標題，真正會跳動的資料放在 ContentState。
    var title: String
}

@MainActor
final class EyeCareLiveActivityManager {
    // Live Activity 管理器用 singleton，讓 TimerManager 可以集中呼叫同一個入口。
    static let shared = EyeCareLiveActivityManager()
    
    private init() {}
    
    // 建立或更新 Live Activity。
    // TimerManager 每次開始、暫停、每秒倒數更新時，都會呼叫這個方法同步狀態。
    func startOrUpdate(step: TimerStep, remainingSeconds: Double, endDate: Date, isRunning: Bool, isAlarming: Bool) {
        // 使用者可以在系統設定關閉 Live Activities。
        // 如果關閉，就不要嘗試建立，避免無謂工作或錯誤。
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        // 先把 App 內部的 TimerStep / timeRemaining 轉成 ActivityKit 能傳給 Widget 的 ContentState。
        let state = makeState(
            step: step,
            remainingSeconds: remainingSeconds,
            endDate: endDate,
            isRunning: isRunning,
            isAlarming: isAlarming
        )
        
        Task {
            // 同一時間這個 App 只需要一個 Live Activity。
            // 如果已經存在，就更新它；如果不存在，才建立新的。
            if let activity = Activity<EyeCareTimerLiveActivityAttributes>.activities.first {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            } else {
                do {
                    // attributes 是固定資料；content 裡面的 state 才是會持續更新的倒數狀態。
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
    
    // 立即結束所有 20-20-20 Live Activity。
    // 重置計時器、進入下一階段時會用到，避免 Lock Screen 留住舊倒數。
    func end() {
        Task {
            for activity in Activity<EyeCareTimerLiveActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
    
    // 倒數完成時呼叫。
    // 這裡不直接 dismiss，而是先把 Live Activity 更新成「時間到」狀態。
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
    
    // 將 App 內部的 TimerStep 和倒數秒數，整理成 Widget Extension 使用的 ContentState。
    private func makeState(step: TimerStep, remainingSeconds: Double, endDate: Date, isRunning: Bool, isAlarming: Bool) -> EyeCareTimerLiveActivityAttributes.ContentState {
        // startDate 用 endDate 減去 duration 推算。
        // max(1, remainingSeconds) 避免剩餘時間為 0 時產生 startDate == endDate 的邊界問題。
        let duration = max(1, remainingSeconds)
        let startDate = endDate.addingTimeInterval(-duration)
        
        return EyeCareTimerLiveActivityAttributes.ContentState(
            stepName: step.name,
            stepIndex: step.rawValue,
            themeName: themeName(for: step),
            startDate: startDate,
            endDate: endDate,
            remainingSeconds: remainingSeconds,
            isRunning: isRunning,
            isAlarming: isAlarming,
            isDebugMode: AppConfiguration.runMode == .debug,
            controlCommand: nil,
            controlCommandID: nil
        )
    }
    
    // Widget Extension 只收到字串 themeName，再由 themeColor(_:) 轉成 Color。
    // 這樣可以避免在 extension target 重複依賴 App 內的 TimerStep enum 實作細節。
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
