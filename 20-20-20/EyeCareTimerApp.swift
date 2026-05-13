import SwiftUI
@preconcurrency import UserNotifications // 負責：設定系統通知代理，讓 App 前台時都可以顯示提醒。

#if os(iOS)
@preconcurrency import WatchConnectivity
#endif

// MARK: - App 入口 (整個程式的出發點)
@main
struct EyeCareTimerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        AppConfiguration.registerDefaults()
        #if os(iOS)
        WatchRunModeSync.shared.activate()
        #endif
        // App 一啟動就指定通知代理。
        // 這樣通知到達時，NotificationPresenter 就能決定要不要彈出 banner、播放提示等。
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView() // 啟動畫面
                #if os(iOS)
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    AppConfiguration.refreshFromSettingsApp()
                    // iPhone App 回到前景時，把目前 Debug / Release 模式同步到 Apple Watch。
                    WatchRunModeSync.shared.syncCurrentRunModeToWatch()
                }
                #endif
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

#if os(iOS)
// MARK: - iPhone -> Apple Watch 模式同步
final class WatchRunModeSync: NSObject {
    static let shared = WatchRunModeSync()
    
    private let runModeKey = AppConfiguration.DefaultsKey.runMode
    
    private override init() {
        super.init()
    }
    
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    
    func syncCurrentRunModeToWatch() {
        guard WCSession.isSupported() else { return }
        
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        
        let payload = [runModeKey: AppConfiguration.runMode.rawValue]
        
        // updateApplicationContext 會保存最新設定；Watch 不在線時，下次連上仍可收到。
        do {
            try session.updateApplicationContext(payload)
        } catch {
            print("同步模式到 Apple Watch 失敗: \(error)")
        }
        
        // 如果 Watch 此刻可即時通訊，額外 sendMessage 讓畫面可以即刻刷新。
        guard session.isReachable else { return }
        session.sendMessage(payload, replyHandler: nil) { error in
            print("即時同步模式到 Apple Watch 失敗: \(error)")
        }
    }
}

extension WatchRunModeSync: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("WatchConnectivity 啟動失敗: \(error)")
            return
        }
        
        guard activationState == .activated else { return }
        Task { @MainActor in
            WatchRunModeSync.shared.syncCurrentRunModeToWatch()
        }
    }
    
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
    }
    
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
#endif
