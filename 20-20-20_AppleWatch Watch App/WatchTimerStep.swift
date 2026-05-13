import SwiftUI

// MARK: - Apple Watch 倒數階段
// Watch 有自己一份 UserDefaults；iPhone 前景時會用 WatchConnectivity 同步 app_run_mode 過來。
// 這樣 Watch 離線時仍可使用上一次同步到的模式。
enum WatchTimerStep: Int, CaseIterable {
    case work1 = 0
    case eyeCare = 1
    case work2 = 2
    case longRest = 3
    
    var name: String {
        switch self {
        case .work1: return "第一階段"
        case .eyeCare: return "第二階段"
        case .work2: return "第三階段"
        case .longRest: return "第四階段"
        }
    }
    
    var activeTitle: String {
        switch self {
        case .work1, .work2: return "專注工作"
        case .eyeCare: return "遠眺放鬆"
        case .longRest: return "深度休息"
        }
    }
    
    var completedTitle: String {
        switch self {
        case .work1: return "第一階段完成 🎉"
        case .eyeCare: return "第二階段完成 💪🏼"
        case .work2: return "第三階段完成 🎉"
        case .longRest: return "第四階段完成 💪🏼"
        }
    }
    
    var seconds: Int {
        switch self {
        case .work1, .work2: return WatchAppConfiguration.duration.work
        case .eyeCare: return WatchAppConfiguration.duration.eyeCare
        case .longRest: return WatchAppConfiguration.duration.longRest
        }
    }
    
    var icon: String {
        switch self {
        case .work1, .work2: return "laptopcomputer"
        case .eyeCare: return "eye.fill"
        case .longRest: return "cup.and.saucer.fill"
        }
    }
    
    var themeColor: Color {
        switch self {
        case .eyeCare: return .green
        case .longRest: return .orange
        case .work1, .work2: return .blue
        }
    }
}

enum WatchAppConfiguration {
    enum RunMode: String, CaseIterable, Identifiable {
        case debug
        case release
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .debug: return "Debug 測試模式"
            case .release: return "Release 正式模式"
            }
        }
    }
    
    enum DefaultsKey {
        static let runMode = "app_run_mode"
    }
    
    typealias DurationConfiguration = (work: Int, eyeCare: Int, longRest: Int)
    
    static func registerDefaults() {
        // 預設使用正式時間；如果 iPhone 有同步 app_run_mode，這個預設值就會被使用者設定取代。
        // 測試時如果想完全不靠 iPhone，也可以暫時把 .release 改成 .debug。
        UserDefaults.standard.register(defaults: [
            DefaultsKey.runMode: RunMode.release.rawValue
        ])
    }
    
    static var runMode: RunMode {
        let rawValue = UserDefaults.standard.string(forKey: DefaultsKey.runMode)
        return RunMode(rawValue: rawValue ?? "") ?? .release
    }
    
    static var duration: DurationConfiguration {
        switch runMode {
        case .debug:
            return (work: 10, eyeCare: 5, longRest: 8)
        case .release:
            return (work: 20 * 60, eyeCare: 20, longRest: 3 * 60)
        }
    }
}
