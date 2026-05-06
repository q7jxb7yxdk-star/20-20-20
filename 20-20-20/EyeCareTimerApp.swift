import SwiftUI
@preconcurrency import UserNotifications // 負責：設定系統通知代理，讓 App 前台時都可以顯示提醒。

// MARK: - App 入口 (整個程式的出發點)
@main
struct EyeCareTimerApp: App {
    init() {
        AppConfiguration.registerDefaults()
        // App 一啟動就指定通知代理。
        // 這樣通知到達時，NotificationPresenter 就能決定要不要彈出 banner、播放提示等。
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView() // 啟動畫面
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar) // Mac 版隱藏頂部標題列
        #endif
        
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
