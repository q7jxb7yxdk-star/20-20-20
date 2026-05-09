@preconcurrency import UserNotifications

// MARK: - Apple Watch 前台通知顯示
final class WatchNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchNotificationPresenter()
    
    private override init() {
        super.init()
    }
    
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // App 正在前台時，watchOS 通常不會自動彈出通知。
        // 這裡明確要求顯示 banner、播放聲音，亦保留在通知列表。
        completionHandler([.banner, .sound, .list])
    }
}
