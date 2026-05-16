import Foundation

// MARK: - Watch UI Language

enum WatchAppLanguage: String {
    case english = "en"
    case traditionalChinese = "zh-Hant"
    
    nonisolated static var current: WatchAppLanguage {
        if let syncedCode = UserDefaults.standard.string(forKey: WatchAppConfiguration.DefaultsKey.languageCode),
           let syncedLanguage = WatchAppLanguage(rawValue: syncedCode) {
            return syncedLanguage
        }
        
        let languageCode = Locale.current.language.languageCode?.identifier.lowercased()
        return languageCode == "zh" ? .traditionalChinese : .english
    }
}

enum WatchAppText {
    nonisolated static var language: WatchAppLanguage { WatchAppLanguage.current }
    
    nonisolated static func stepName(_ step: WatchTimerStep) -> String {
        switch (language, step) {
        case (.english, .work1): return "Step 1"
        case (.english, .eyeCare): return "Step 2"
        case (.english, .work2): return "Step 3"
        case (.english, .longRest): return "Step 4"
        case (.traditionalChinese, .work1): return "第一階段"
        case (.traditionalChinese, .eyeCare): return "第二階段"
        case (.traditionalChinese, .work2): return "第三階段"
        case (.traditionalChinese, .longRest): return "第四階段"
        }
    }
    
    nonisolated static func activeTitle(_ step: WatchTimerStep) -> String {
        switch (language, step) {
        case (.english, .work1), (.english, .work2): return "Focus"
        case (.english, .eyeCare): return "Look Far"
        case (.english, .longRest): return "Long Rest"
        case (.traditionalChinese, .work1), (.traditionalChinese, .work2): return "專注工作"
        case (.traditionalChinese, .eyeCare): return "遠眺放鬆"
        case (.traditionalChinese, .longRest): return "深度休息"
        }
    }
    
    nonisolated static func completedTitle(_ step: WatchTimerStep) -> String {
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
}
