//
//  20-20-20_AppleWatchApp.swift
//  20-20-20_AppleWatch Watch App
//
//  Created by Sunny Yu on 9/5/2026.
//

import SwiftUI
@preconcurrency import UserNotifications
@preconcurrency import WatchConnectivity

@main
struct _0_20_20_AppleWatch_Watch_AppApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var manager = WatchTimerManager.shared
    
    init() {
        WatchRunModeReceiver.shared.activate()
        // Watch app 在前台時，系統預設未必會彈通知。
        // 指定 delegate 後，可以在倒數完成時要求 watchOS 顯示通知提示。
        UNUserNotificationCenter.current().delegate = WatchNotificationPresenter.shared
    }
    
    var body: some Scene {
        WindowGroup {
            WatchContentView(manager: manager)
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    manager.stopAlarmAlertAfterOpeningApp()
                }
        }
    }
}

// MARK: - Apple Watch 接收 iPhone 模式設定
final class WatchRunModeReceiver: NSObject {
    static let shared = WatchRunModeReceiver()
    
    private let runModeKey = WatchAppConfiguration.DefaultsKey.runMode
    
    private override init() {
        super.init()
    }
    
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    
    private func applyRunModePayload(_ payload: [String: Any]) {
        guard let rawValue = payload[runModeKey] as? String else { return }
        guard WatchAppConfiguration.RunMode(rawValue: rawValue) != nil else { return }
        guard UserDefaults.standard.string(forKey: runModeKey) != rawValue else { return }
        
        // Watch 有自己一份 UserDefaults；收到 iPhone 設定後先保存，再通知 manager 更新 idle 畫面。
        UserDefaults.standard.set(rawValue, forKey: runModeKey)
        WatchTimerManager.shared.reloadDurationIfIdle()
    }
}

extension WatchRunModeReceiver: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("WatchConnectivity 啟動失敗: \(error)")
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            WatchRunModeReceiver.shared.applyRunModePayload(applicationContext)
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            WatchRunModeReceiver.shared.applyRunModePayload(message)
        }
    }
}
