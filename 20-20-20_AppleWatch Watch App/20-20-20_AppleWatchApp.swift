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
    @WKApplicationDelegateAdaptor(WatchApplicationDelegate.self) private var applicationDelegate
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
                    let isActive = newPhase == .active
                    manager.updateAppActiveState(isActive)
                    
                    guard isActive else { return }
                    manager.stopAlarmAlertAfterOpeningApp()
                }
        }
    }
}

final class WatchApplicationDelegate: NSObject, WKApplicationDelegate {
    func handle(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        WatchTimerManager.shared.recoverSmartAlarmSession(extendedRuntimeSession)
    }
}

// MARK: - Apple Watch 接收 iPhone 模式設定
final class WatchRunModeReceiver: NSObject {
    static let shared = WatchRunModeReceiver()
    
    private let runModeKey = WatchAppConfiguration.DefaultsKey.runMode
    private let languageCodeKey = WatchAppConfiguration.DefaultsKey.languageCode
    
    private override init() {
        super.init()
    }
    
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    
    private func applyRunModePayload(_ payload: [String: Any]) {
        var didChange = false
        
        if let rawValue = payload[runModeKey] as? String,
           WatchAppConfiguration.RunMode(rawValue: rawValue) != nil,
           UserDefaults.standard.string(forKey: runModeKey) != rawValue {
            // Watch 有自己一份 UserDefaults；收到 iPhone 設定後先保存，再通知 manager 更新 idle 畫面。
            UserDefaults.standard.set(rawValue, forKey: runModeKey)
            didChange = true
        }
        
        if let languageCode = payload[languageCodeKey] as? String,
           WatchAppLanguage(rawValue: languageCode) != nil,
           UserDefaults.standard.string(forKey: languageCodeKey) != languageCode {
            // iPhone 會把目前系統語言判斷結果同步到 Watch。
            // Watch UI 因此可以跟 iPhone 使用同一套英文 / 繁中選擇。
            UserDefaults.standard.set(languageCode, forKey: languageCodeKey)
            didChange = true
        }
        
        guard didChange else { return }
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
