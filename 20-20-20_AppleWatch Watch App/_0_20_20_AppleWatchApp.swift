//
//  _0_20_20_AppleWatchApp.swift
//  20-20-20_AppleWatch Watch App
//
//  Created by Sunny Yu on 9/5/2026.
//

import SwiftUI
@preconcurrency import UserNotifications

@main
struct _0_20_20_AppleWatch_Watch_AppApp: App {
    @StateObject private var manager = WatchTimerManager.shared
    
    init() {
        // Watch app 在前台時，系統預設未必會彈通知。
        // 指定 delegate 後，可以在倒數完成時要求 watchOS 顯示通知提示。
        UNUserNotificationCenter.current().delegate = WatchNotificationPresenter.shared
    }
    
    var body: some Scene {
        WindowGroup {
            WatchContentView(manager: manager)
        }
    }
}
