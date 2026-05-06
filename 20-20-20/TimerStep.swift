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
    // typealias 可以把一組複雜型別取一個好懂的名字。
    // 這裡代表「三種倒數時間」的設定集合，之後使用 AppConfiguration.duration.work 會比較直覺。
    typealias DurationConfiguration = (work: Int, eyeCare: Int, longRest: Int)
    
    // 每個階段的持續時間設定（秒）
    static let duration: DurationConfiguration = {
        #if DEBUG
        // 開發測試模式：縮短時間以便快速看到結果
        return (work: 10, eyeCare: 5, longRest: 8)
        #else
        // 正式模式：標準 20-20-20 護眼法則的時間
        return (work: 20 * 60, eyeCare: 20, longRest: 3 * 60)
        #endif
    }()
    
    #if os(iOS)
    // AlarmKit 使用自己的聲音設定型別。
    // DEBUG 使用系統預設聲音，避免開發時一直聽到正式鬧鐘聲；正式版才使用專案內的 alarm.caf。
    static var alarmKitSound: AlertConfiguration.AlertSound {
        #if DEBUG
        return .default
        #else
        return .named("alarm.caf")
        #endif
    }
    #endif
}
