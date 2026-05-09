import SwiftUI

// MARK: - Apple Watch 倒數階段
// Watch 版本先保持獨立，避免一開始就同 iPhone 版本互相牽連。
// 之後如果要同步 iPhone 設定，可以再用 WatchConnectivity 將資料傳過來。
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
    typealias DurationConfiguration = (work: Int, eyeCare: Int, longRest: Int)
    
    // Watch 初版先用短時間，方便你在手錶上測試整個循環。
    // 確認流程穩定後，可以改成正式時間，或之後同 iPhone 設定同步。
    static let duration: DurationConfiguration = (work: 10, eyeCare: 5, longRest: 8)
}
