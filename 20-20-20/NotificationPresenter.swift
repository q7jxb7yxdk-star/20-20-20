@preconcurrency import UserNotifications

extension Notification.Name {
    static let alarmNotificationWasOpened = Notification.Name("alarmNotificationWasOpened")
}

// MARK: - 通知呈現代理
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    // 使用 singleton，確保整個 App 只有一個通知代理物件。
    // 如果 delegate 被釋放，通知回呼可能就收不到，所以用 static shared 讓它常駐。
    static let shared = NotificationPresenter()
    
    private override init() {
        super.init()
    }
    
    // 設定當 App 開啟時，通知彈窗也能在螢幕頂部顯示
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        #if os(macOS)
        // 這裡用 rawValue 是為了相容不同 macOS SDK 的通知選項。
        // 4/8/16 分別對應 banner、list、sound 類似的呈現能力。
        let presentationOptions = UNNotificationPresentationOptions(rawValue: 4 | 8 | 16)
        completionHandler(presentationOptions)
        #else
        if #available(iOS 14.0, macOS 11.0, *) {
            // iOS 的提醒聲由 AlarmKit 處理，通知只顯示畫面，避免聲音重疊。
            completionHandler([.banner, .list])
        } else {
            completionHandler([.alert])
        }
        #endif
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        #if os(macOS)
        // macOS 通知被點擊後，通知 delegate 未必知道 TimerManager 是哪一個實例。
        // 用 App 內部通知廣播出去，讓 TimerManager 自己決定如何停止鈴聲。
        NotificationCenter.default.post(name: .alarmNotificationWasOpened, object: nil)
        #endif
        completionHandler()
    }
}
