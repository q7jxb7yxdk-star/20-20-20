#if os(iOS)
import AlarmKit
import AppIntents

// MARK: - AlarmKit 資料

// AlarmKit 要求我們提供一個符合 AlarmMetadata 的資料型別。
// 這份 metadata 會跟著系統鬧鐘一起保存，之後可以用來知道是哪個階段觸發提醒。
nonisolated struct EyeCareAlarmMetadata: AlarmMetadata {
    let stepName: String
}

// LiveActivityIntent 是給系統鬧鐘畫面上的按鈕使用的動作。
// 使用者即使不打開 App，也可以在系統介面上按「停止」，然後執行這段程式。
struct StopEyeCareAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource {
        "Stop Eye Care Reminder"
    }
    static var supportedModes: IntentModes = .background
    
    @Parameter(title: "Alarm ID")
    var alarmID: String
    
    init() {
        // AppIntents 需要一個無參數 init，系統才能建立這個 Intent。
        alarmID = ""
    }
    
    init(alarmID: Alarm.ID) {
        // Alarm.ID 本質上是 UUID；轉成字串後才能放進 @Parameter。
        self.alarmID = alarmID.uuidString
    }
    
    func perform() async throws -> some IntentResult {
        // 系統按鈕回傳的是字串，所以這裡要先轉回 UUID 才能找到原本排程的鬧鐘。
        if let id = UUID(uuidString: alarmID) {
            // stop 用於停止正在響的鬧鐘；cancel 用於取消尚未響的鬧鐘。
            // 兩個都嘗試，讓按鈕在不同狀態下都能盡量生效。
            try? AlarmManager.shared.stop(id: id)
            try? AlarmManager.shared.cancel(id: id)
        }
        return .result()
    }
}
#endif
