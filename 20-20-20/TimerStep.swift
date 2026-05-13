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
        switch self {
        case .work1: return "第一階段：專注工作"
        case .eyeCare: return "第二階段：遠眺放鬆"
        case .work2: return "第三階段：專注工作"
        case .longRest: return "第四階段：深度休息"
        }
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
            case .debug: return "Debug 測試模式"
            case .release: return "Release 正式模式"
            }
        }
        
        var description: String {
            switch self {
            case .debug: return "使用短時間，方便快速測試倒數、通知和響鈴。"
            case .release: return "使用正式時間，適合日常真正護眼使用。"
            }
        }
    }
    
    enum DefaultsKey {
        static let runMode = "app_run_mode"
    }
    
    // typealias 可以把一組複雜型別取一個好懂的名字。
    // 這裡代表「三種倒數時間」的設定集合，之後使用 AppConfiguration.duration.work 會比較直覺。
    typealias DurationConfiguration = (work: Int, eyeCare: Int, longRest: Int)
    
    static func registerDefaults() {
        // register(defaults:) 不會覆蓋使用者已經揀好的設定，只會提供第一次啟動時的預設值。
        UserDefaults.standard.register(defaults: [
            DefaultsKey.runMode: RunMode.release.rawValue
        ])
    }
    
    static var runMode: RunMode {
        let rawValue = UserDefaults.standard.string(forKey: DefaultsKey.runMode)
        return RunMode(rawValue: rawValue ?? "") ?? .release
    }
    
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
