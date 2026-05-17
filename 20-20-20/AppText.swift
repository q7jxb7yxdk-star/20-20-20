import Foundation

// MARK: - App UI Language

/// App 內部使用的簡單語言選擇。
///
/// 規則：
/// - 如果使用者在 App Settings 選了 English / 中文，就使用該設定。
/// - 如果使用者從未選過，就按系統語言自動選擇。
/// - 系統語言是中文：顯示繁體中文。
/// - 系統語言是英文或其他非中文：顯示英文。
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case traditionalChinese = "zh-Hant"
    
    /// macOS Settings 使用這個值代表「跟隨系統語言」。
    ///
    /// 它不是一種真正的 UI 語言；App 會在讀到這個值時再用 `systemPreferred` 判斷實際顯示英文或繁體中文。
    nonisolated static let systemPreferenceValue = "system"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .traditionalChinese: return "繁體中文"
        }
    }
    
    /// 按系統偏好語言自動判斷 App 初始語言。
    ///
    /// 使用 `Locale.preferredLanguages` 比只讀 `Locale.current` 更貼近使用者在系統設定入面的語言排序。
    nonisolated static var systemPreferred: AppLanguage {
        let preferredLanguages = Locale.preferredLanguages.map { $0.lowercased() }
        let hasChinesePreference = preferredLanguages.contains { language in
            language == "zh" || language.hasPrefix("zh-") || language.hasPrefix("zh_")
        }
        
        return hasChinesePreference ? .traditionalChinese : .english
    }
    
    nonisolated static var current: AppLanguage {
        // 這裡直接使用 literal key，是為了避開 Swift 6 default MainActor isolation
        // 對 static property 的限制；這個 key 必須和 AppConfiguration.DefaultsKey.languageCode 相同。
        let rawValue = UserDefaults.standard.string(forKey: "app_language_code")
        
        // 沒有手動選擇語言，或選了「跟隨系統」時，才真正按 macOS / iOS 系統語言決定 UI。
        if rawValue == nil || rawValue == systemPreferenceValue {
            return systemPreferred
        }
        
        return AppLanguage(rawValue: rawValue ?? "") ?? systemPreferred
    }
}

/// 集中管理 App UI 文字。
///
/// 學習用重點：SwiftUI 的 `Text` 可以直接顯示這些 String。
/// 先用這種小型文字表，比一開始就建立大量 `.strings` 檔更容易看懂。
enum AppText {
    nonisolated static var language: AppLanguage { AppLanguage.current }
    
    nonisolated static var appTitle: String {
        switch language {
        case .english: return "20-20-20 Eye Care"
        case .traditionalChinese: return "20-20-20 護眼助理"
        }
    }
    
    nonisolated static var timeUp: String {
        switch language {
        case .english: return "Time's up"
        case .traditionalChinese: return "時間到"
        }
    }
    
    nonisolated static func stepName(_ step: TimerStep) -> String {
        switch (language, step) {
        case (.english, .work1): return "Step 1: Focus"
        case (.english, .eyeCare): return "Step 2: Look Far"
        case (.english, .work2): return "Step 3: Focus"
        case (.english, .longRest): return "Step 4: Long Rest"
        case (.traditionalChinese, .work1): return "第一階段：專注工作"
        case (.traditionalChinese, .eyeCare): return "第二階段：遠眺放鬆"
        case (.traditionalChinese, .work2): return "第三階段：專注工作"
        case (.traditionalChinese, .longRest): return "第四階段：深度休息"
        }
    }
    
    nonisolated static func completedTitle(_ step: TimerStep) -> String {
        switch (language, step) {
        case (.english, .work1): return "Step 1 complete 🎉"
        case (.english, .eyeCare): return "Step 2 complete 💪🏼"
        case (.english, .work2): return "Step 3 complete 🎉"
        case (.english, .longRest): return "Step 4 complete 💪🏼"
        case (.traditionalChinese, .work1): return "第一階段完成 🎉"
        case (.traditionalChinese, .eyeCare): return "第二階段完成 💪🏼"
        case (.traditionalChinese, .work2): return "第三階段完成 🎉"
        case (.traditionalChinese, .longRest): return "第四階段完成 💪🏼"
        }
    }
    
    nonisolated static var runModeLabel: String {
        switch language {
        case .english: return "Run Mode"
        case .traditionalChinese: return "運行模式"
        }
    }
    
    nonisolated static var languageLabel: String {
        switch language {
        case .english: return "Language"
        case .traditionalChinese: return "語言"
        }
    }
    
    nonisolated static var followSystemLanguageName: String {
        switch language {
        case .english: return "Follow System"
        case .traditionalChinese: return "跟隨系統"
        }
    }
    
    nonisolated static var debugModeName: String {
        switch language {
        case .english: return "Debug Test Mode"
        case .traditionalChinese: return "Debug 測試模式"
        }
    }
    
    nonisolated static var releaseModeName: String {
        switch language {
        case .english: return "Release Mode"
        case .traditionalChinese: return "Release 正式模式"
        }
    }
    
    nonisolated static var debugModeDescription: String {
        switch language {
        case .english: return "Uses short durations for quickly testing countdowns, notifications, and alarms."
        case .traditionalChinese: return "使用短時間，方便快速測試倒數、通知和響鈴。"
        }
    }
    
    nonisolated static var releaseModeDescription: String {
        switch language {
        case .english: return "Uses normal 20-20-20 durations for daily eye care."
        case .traditionalChinese: return "使用正式時間，適合日常真正護眼使用。"
        }
    }
    
    nonisolated static var notificationTitle: String {
        switch language {
        case .english: return "Time's up!"
        case .traditionalChinese: return "時間到！"
        }
    }
    
    nonisolated static func notificationBody(for step: TimerStep) -> String {
        let stepTitle = stepName(step)
        
        switch language {
        case .english:
            return "\(stepTitle) is complete. Please start the next step."
        case .traditionalChinese:
            return "「\(stepTitle)」已完成，請開始下一階段。"
        }
    }
    
    nonisolated static var stopEyeCareReminder: String {
        switch language {
        case .english: return "Stop Eye Care Reminder"
        case .traditionalChinese: return "停止護眼提醒"
        }
    }
    
    nonisolated static var toggleLiveActivityTitle: String {
        switch language {
        case .english: return "Start or Pause 20-20-20"
        case .traditionalChinese: return "開始或暫停 20-20-20"
        }
    }
    
    nonisolated static var toggleLiveActivityDescription: String {
        switch language {
        case .english: return "Start, pause, or continue to the next step directly from the Lock Screen Live Activity."
        case .traditionalChinese: return "在 Lock Screen Live Activity 直接開始、暫停，或在時間到後進入下一階段。"
        }
    }
    
    nonisolated static var resetLiveActivityTitle: String {
        switch language {
        case .english: return "End 20-20-20"
        case .traditionalChinese: return "結束 20-20-20"
        }
    }
    
    nonisolated static var resetLiveActivityDescription: String {
        switch language {
        case .english: return "End the current Lock Screen Live Activity directly."
        case .traditionalChinese: return "直接結束目前的 Lock Screen Live Activity。"
        }
    }
}
