import Foundation

// MARK: - Live Activity UI Language

enum ExtensionAppLanguage {
    case english
    case traditionalChinese
    
    nonisolated static var current: ExtensionAppLanguage {
        let languageCode = Locale.current.language.languageCode?.identifier.lowercased()
        return languageCode == "zh" ? .traditionalChinese : .english
    }
}

enum ExtensionAppText {
    nonisolated static var language: ExtensionAppLanguage { ExtensionAppLanguage.current }
    
    nonisolated static var timeUp: String {
        switch language {
        case .english: return "Time's up"
        case .traditionalChinese: return "時間到"
        }
    }
    
    nonisolated static func stepName(for index: Int) -> String {
        switch (language, index) {
        case (.english, 0): return "Step 1: Focus"
        case (.english, 1): return "Step 2: Look Far"
        case (.english, 2): return "Step 3: Focus"
        case (.english, _): return "Step 4: Long Rest"
        case (.traditionalChinese, 0): return "第一階段：專注工作"
        case (.traditionalChinese, 1): return "第二階段：遠眺放鬆"
        case (.traditionalChinese, 2): return "第三階段：專注工作"
        case (.traditionalChinese, _): return "第四階段：深度休息"
        }
    }
    
    nonisolated static var toggleTitle: String {
        switch language {
        case .english: return "Start or Pause 20-20-20"
        case .traditionalChinese: return "開始或暫停 20-20-20"
        }
    }
    
    nonisolated static var toggleDescription: String {
        switch language {
        case .english: return "Start, pause, or continue to the next step directly from the Lock Screen Live Activity."
        case .traditionalChinese: return "在 Lock Screen Live Activity 直接開始、暫停，或在時間到後進入下一階段。"
        }
    }
    
    nonisolated static var resetTitle: String {
        switch language {
        case .english: return "End 20-20-20"
        case .traditionalChinese: return "結束 20-20-20"
        }
    }
    
    nonisolated static var resetDescription: String {
        switch language {
        case .english: return "End the current Lock Screen Live Activity directly."
        case .traditionalChinese: return "直接結束目前的 Lock Screen Live Activity。"
        }
    }
}
