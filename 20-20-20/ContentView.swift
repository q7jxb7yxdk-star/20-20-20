import SwiftUI           // 負責：建立 App 的畫面（按鈕、圓圈、文字等 UI 元素）

// 根據不同的作業系統，引入專屬的系統工具箱
#if os(iOS)
import UIKit             // 負責：iOS 系統的底層工具（如螢幕震動、系統背景管理）
#elseif os(macOS)
import AppKit            // 負責：macOS 系統的底層工具（如電腦視窗管理、觸控板反饋）
#endif

// MARK: - 3. 介面外觀區 (使用 SwiftUI 繪製)
struct ContentView: View {
    // @StateObject 代表 SwiftUI 會替這個 View 持有 TimerManager 的生命週期。
    // 如果改用 @ObservedObject，畫面重建時可能會重新建立 manager，導致倒數狀態遺失。
    @StateObject private var manager = TimerManager() // 引用核心大腦
    @AppStorage(AppConfiguration.DefaultsKey.languageCode) private var appLanguageCode = AppLanguage.systemPreferred.rawValue
    
    var body: some View {
        let _ = appLanguageCode
        
        GeometryReader { proxy in
            let safeSize = proxy.size
            let isLandscape = safeSize.width > safeSize.height
            let circleSize = progressCircleSize(for: safeSize, isLandscape: isLandscape)
            let buttonSize = actionButtonSize(for: safeSize, isLandscape: isLandscape)
            
            ZStack { // 堆疊層：由下往上蓋
                backgroundColor.ignoresSafeArea() // 最底層的背景色
                
                if isLandscape {
                    landscapeLayout(circleSize: circleSize, buttonSize: buttonSize)
                } else {
                    portraitLayout(circleSize: circleSize, buttonSize: buttonSize)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 600) // Mac 版視窗大小
        .background(WindowInitialSizeConfigurator(width: 400, height: 600))
        #endif
        .onAppear { manager.setupOnLaunch() } // 畫面加載完成後進行權限請求
        #if os(iOS)
        .onOpenURL { url in
            handleLiveActivityURL(url)
        }
        #endif
    }
}

#if os(macOS)
// NSViewRepresentable 是 SwiftUI 與 AppKit 之間的橋接器。
// SwiftUI 本身不好直接控制 macOS 視窗初始大小，所以放一個隱形 NSView 來取得 window。
struct WindowInitialSizeConfigurator: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat
    
    func makeCoordinator() -> Coordinator {
        // Coordinator 用來保存跨 updateNSView 呼叫的狀態。
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSView {
        // 這個 NSView 不顯示任何東西，只是為了拿到它所屬的 window。
        NSView()
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // updateNSView 可能被 SwiftUI 呼叫很多次，所以用 didConfigure 確保只設定一次視窗大小。
        guard !context.coordinator.didConfigure else { return }
        context.coordinator.didConfigure = true
        
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            let size = NSSize(width: width, height: height)
            window.minSize = size
            window.setContentSize(size)
        }
    }
    
    class Coordinator {
        var didConfigure = false
    }
}
#endif

extension ContentView {
    // 直向排列：保留原本由上至下的閱讀順序，但改用較細 spacing，避免細螢幕被擠爆。
    private func portraitLayout(circleSize: CGFloat, buttonSize: CGFloat) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)
            statusHeader
            progressCircle(size: circleSize)
            actionControls(buttonSize: buttonSize)
            stepDots
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // 橫向排列：高度變矮時，改成左右分欄，避免標題、圓圈、按鈕、進度點互相遮住。
    private func landscapeLayout(circleSize: CGFloat, buttonSize: CGFloat) -> some View {
        HStack(spacing: 28) {
            progressCircle(size: circleSize)
                .frame(maxWidth: .infinity)
            
            VStack(spacing: 20) {
                statusHeader
                actionControls(buttonSize: buttonSize)
                stepDots
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // 標題顯示組件
    private var statusHeader: some View {
        // 把畫面拆成多個 private computed property，body 會更短，也更容易閱讀與維護。
        VStack(spacing: 12) {
            Text(AppText.appTitle)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.1)))
            
            Text(statusTitle)
                .font(.title2.bold())
                .foregroundColor(manager.isAlarming ? .red : .primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
                // value 指定動畫只在 isAlarming 改變時觸發，避免所有狀態更新都套動畫。
                .animation(.easeInOut, value: manager.isAlarming)
        }
        .frame(maxWidth: .infinity)
    }
    
    // 中間的進度圓圈組件
    private func progressCircle(size: CGFloat) -> some View {
        let lineWidth = max(9, size * 0.06)
        let timeFontSize = max(34, size * 0.22)
        
        return ZStack {
            // 背景灰圈
            Circle()
                .stroke(Color.gray.opacity(0.1), lineWidth: lineWidth)
            
            // 彩色進度圈
            Circle()
                // trim 只畫出圓的一部分；剩餘秒數越少，彩色弧線越短。
                .trim(from: 0, to: progress)
                .stroke(
                    manager.isAlarming ? Color.red : manager.currentStep.themeColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90)) // 起點修正到正上方
                .animation(.linear(duration: 0.2), value: manager.timeRemaining)
            
            VStack(spacing: 10) {
                // 圖示
                Image(systemName: manager.currentStep.icon)
                    .font(.system(size: max(24, size * 0.14), weight: .regular))
                    .foregroundColor(manager.isAlarming ? .red : manager.currentStep.themeColor)
                
                // 時間文字（例如 19:59）
                Text(timeString(from: Int(ceil(manager.timeRemaining))))
                    .font(.system(size: timeFontSize, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
    }
    
    // 下方按鈕組件
    private func actionControls(buttonSize: CGFloat) -> some View {
        HStack(spacing: max(24, buttonSize * 0.45)) {
            Button(action: {
                // 同一顆主按鈕在不同狀態下做不同事：
                // 響鈴時是「確認並進下一階段」，平常是「開始/暫停」。
                if manager.isAlarming {
                    manager.nextStep() // 響鈴時點一下進入下一關
                } else {
                    manager.toggle()   // 平常點一下切換暫停/開始
                }
            }) {
                ZStack {
                    Circle()
                        .fill(mainButtonColor)
                        .frame(width: buttonSize, height: buttonSize)
                        .shadow(color: mainButtonColor.opacity(0.3), radius: 10, y: 5)
                    
                    Image(systemName: mainButtonIcon)
                        .font(.system(size: buttonSize * 0.34, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(manager.isAlarming ? 1.15 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: manager.isAlarming)
            
            // 重置按鈕
            Button(action: manager.reset) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: buttonSize, height: buttonSize)
                    
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: buttonSize * 0.28, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(height: buttonSize * 1.2)
    }
    
    // 進度圓點組件
    private var stepDots: some View {
        HStack(spacing: 10) {
            // ForEach 會依序產生四個小點，對應 TimerStep 的四個階段。
            ForEach(0..<TimerStep.allCases.count, id: \.self) { index in
                Circle()
                    .fill(manager.currentStep.rawValue == index ? manager.currentStep.themeColor : Color.gray.opacity(0.2))
                    .frame(width: 8, height: 8)
                    .animation(.spring(), value: manager.currentStep)
            }
        }
    }
    
    // 控制按鈕圖示變換
    private var mainButtonIcon: String {
        // 用狀態推導 UI，而不是在按鈕裡手動記錄圖示。
        // 這是 SwiftUI 常見做法：資料狀態改變，畫面自然跟著改變。
        if manager.isAlarming { return "checkmark" }
        return manager.isRunning ? "pause.fill" : "play.fill"
    }
    
    // 控制按鈕顏色變換
    private var mainButtonColor: Color {
        // 將顏色邏輯集中在這裡，Button 的 View 宣告就能保持乾淨。
        if manager.isAlarming { return .orange }
        return manager.isRunning ? .red : .blue
    }
    
    private var progress: Double {
        let totalSeconds = manager.currentStep.seconds
        guard totalSeconds > 0 else { return 0 }
        return max(0, min(1, manager.timeRemaining / Double(totalSeconds)))
    }
    
    // 標題文字會隨狀態改變：
    // 平常顯示目前階段名稱；倒數完成並響鈴時，改成更明確的「第幾階段完成」提示。
    private var statusTitle: String {
        guard manager.isAlarming else { return manager.currentStep.name }
        
        switch manager.currentStep {
        case .work1:
            return AppText.completedTitle(.work1)
        case .eyeCare:
            return AppText.completedTitle(.eyeCare)
        case .work2:
            return AppText.completedTitle(.work2)
        case .longRest:
            return AppText.completedTitle(.longRest)
        }
    }
    
    // 獲取背景色
    private var backgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }
    
    // 數學計算：將秒數格式化為 00:00 顯示
    private func timeString(from totalSeconds: Int) -> String {
        // 整數除法取得分鐘，取餘數取得秒數。
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
    
    private func progressCircleSize(for size: CGSize, isLandscape: Bool) -> CGFloat {
        if isLandscape {
            // 橫向時高度是限制，所以用高度計算，並預留上下 safe area / padding。
            return min(240, max(150, size.height - 64))
        } else {
            return min(250, max(190, size.width * 0.68))
        }
    }
    
    private func actionButtonSize(for size: CGSize, isLandscape: Bool) -> CGFloat {
        if isLandscape {
            return min(72, max(56, size.height * 0.2))
        } else {
            return 80
        }
    }
    
    #if os(iOS)
    private func handleLiveActivityURL(_ url: URL) {
        guard url.scheme == "eyecaretimer", url.host == "live-activity" else { return }
        
        switch url.lastPathComponent {
        case "toggle":
            manager.toggleOrAdvanceFromLiveActivity()
        case "pause":
            // 舊版 Live Activity 曾經使用 pause URL；保留這條路徑，避免系統暫存舊 widget 時按鈕失效。
            manager.toggleOrAdvanceFromLiveActivity()
        case "reset":
            manager.reset()
        default:
            break
        }
    }
    #endif
}
