import SwiftUI

#if os(iOS)
import AlarmKit
import ActivityKit
#endif

// MARK: - 1. 護眼階段配置 (定義四個階段的屬性)
enum TimerStep: Int, CaseIterable {
    // 定義四個階段：工作1、護眼、工作2、長休息
    case work1 = 0, eyeCare = 1, work2 = 2, longRest = 3
    
    // 每個階段在介面上顯示的中文名稱
    var name: String {
        AppText.stepName(self)
    }
    
    // 每個階段的持續時間（秒）
    var seconds: Int {
        switch self {
        case .work1, .work2: return AppConfiguration.duration.work
        case .eyeCare: return AppConfiguration.duration.eyeCare
        case .longRest: return AppConfiguration.duration.longRest
        }
    }
    
    // 每個階段顯示的圖示名稱
    var icon: String {
        switch self {
        case .work1, .work2: return "laptopcomputer"
        case .eyeCare: return "eye.fill"
        case .longRest: return "cup.and.saucer.fill"
        }
    }
    
    // 每個階段的主題顏色
    var themeColor: Color {
        switch self {
        case .eyeCare: return .green
        case .longRest: return .orange
        default: return .blue
        }
    }
}

enum AppConfiguration {
    enum RunMode: String, CaseIterable, Identifiable {
        case debug
        case release
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .debug: return AppText.debugModeName
            case .release: return AppText.releaseModeName
            }
        }
        
        var description: String {
            switch self {
            case .debug: return AppText.debugModeDescription
            case .release: return AppText.releaseModeDescription
            }
        }
    }
    
    enum DefaultsKey {
        nonisolated static let runMode = "app_run_mode"
        nonisolated static let languageCode = "app_language_code"
        nonisolated static let languageSource = "app_language_source"
        nonisolated static let lastAutoLanguageCode = "app_last_auto_language_code"
    }
    
    // typealias 可以把一組複雜型別取一個好懂的名字。
    // 這裡代表「三種倒數時間」的設定集合，之後使用 AppConfiguration.duration.work 會比較直覺。
    typealias DurationConfiguration = (work: Int, eyeCare: Int, longRest: Int)
    
    static func registerDefaults() {
        // register(defaults:) 不會覆蓋使用者已經揀好的設定，只會提供第一次啟動時的預設值。
        // 語言設定不在這裡註冊，因為沒有手動選語言時應該即時跟隨系統語言。
        UserDefaults.standard.register(defaults: [
            DefaultsKey.runMode: RunMode.release.rawValue
        ])
        
        syncLanguageSettingWithSystem()
    }
    
    static func syncLanguageSettingWithSystem() {
        // iOS Settings.bundle 和 macOS Settings 都只顯示 English / 繁體中文。
        // App 自己在啟動/回前景時同步目前系統語言，讓 Settings 預設選中實際 UI 語言，
        // 但「未手動選過」時仍然可以真正跟隨系統語言。
        let defaults = UserDefaults.standard
        let systemLanguageCode = AppLanguage.systemPreferred.rawValue
        let source = defaults.string(forKey: DefaultsKey.languageSource)
        let storedLanguageCode = defaults.string(forKey: DefaultsKey.languageCode)
        let lastAutoLanguageCode = defaults.string(forKey: DefaultsKey.lastAutoLanguageCode)
        
        if source == nil {
            if storedLanguageCode == nil || storedLanguageCode == AppLanguage.systemPreferenceValue {
                defaults.set("auto", forKey: DefaultsKey.languageSource)
                defaults.set(systemLanguageCode, forKey: DefaultsKey.languageCode)
                defaults.set(systemLanguageCode, forKey: DefaultsKey.lastAutoLanguageCode)
            } else {
                // 舊版本如果已經有 English / 繁體中文，就當成使用者已手動選擇，避免覆蓋偏好。
                defaults.set("manual", forKey: DefaultsKey.languageSource)
            }
            
            return
        }
        
        guard source == "auto" else { return }
        
        if let storedLanguageCode,
           let lastAutoLanguageCode,
           storedLanguageCode != lastAutoLanguageCode {
            // 使用者在 iPhone Settings 改了 Language；App 下次回前景時將它視為手動選擇。
            defaults.set("manual", forKey: DefaultsKey.languageSource)
            return
        }
        
        defaults.set(systemLanguageCode, forKey: DefaultsKey.languageCode)
        defaults.set(systemLanguageCode, forKey: DefaultsKey.lastAutoLanguageCode)
    }
    
    static func markLanguageManuallySelected(_ languageCode: String) {
        // macOS Settings 在 App 內直接改 UserDefaults，所以可以即時標記成手動選擇。
        // iOS Settings.bundle 在系統 Settings App 內修改，會由 refreshFromSettingsApp() 偵測。
        UserDefaults.standard.set("manual", forKey: DefaultsKey.languageSource)
        UserDefaults.standard.set(languageCode, forKey: DefaultsKey.languageCode)
    }
    
    static var runMode: RunMode {
        let rawValue = UserDefaults.standard.string(forKey: DefaultsKey.runMode)
        return RunMode(rawValue: rawValue ?? "") ?? .release
    }
    
    #if os(iOS)
    static func refreshFromSettingsApp() {
        // iOS 的 Settings.bundle 是另一個系統 App 幫我們寫 UserDefaults。
        // 使用者由「設定」返回本 App 時，主動同步一次，避免讀到舊 cache。
        UserDefaults.standard.synchronize()
        syncLanguageSettingWithSystem()
    }
    #endif
    
    // 每個階段的持續時間設定（秒）
    static var duration: DurationConfiguration {
        switch runMode {
        case .debug:
            // Debug 測試模式：縮短時間以便快速看到結果。
            return (work: 10, eyeCare: 5, longRest: 8)
        case .release:
            // Release 正式模式：標準 20-20-20 護眼法則的時間。
            return (work: 20 * 60, eyeCare: 20, longRest: 3 * 60)
        }
    }
    
    #if os(iOS)
    // AlarmKit 使用自己的聲音設定型別。
    // Debug / Release 都使用專案內的 alarm.caf，方便測試時直接確認正式鈴聲是否生效。
    static var alarmKitSound: AlertConfiguration.AlertSound {
        .named("alarm.caf")
    }
    #endif
}
