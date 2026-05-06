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
    
    var body: some View {
        ZStack { // 堆疊層：由下往上蓋
            backgroundColor.ignoresSafeArea() // 最底層的背景色
            
            VStack(spacing: 0) { // 垂直排列
                Spacer()
                statusHeader.padding(.bottom, 40)    // 顯示標題
                progressCircle.padding(.bottom, 40)  // 顯示計時圓圈
                actionControls                       // 顯示操作按鈕
                Spacer()
                stepDots                             // 顯示進度小點
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 600) // Mac 版視窗大小
        .background(WindowInitialSizeConfigurator(width: 400, height: 600))
        #endif
        .onAppear { manager.setupOnLaunch() } // 畫面加載完成後進行權限請求
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
    
    // 標題顯示組件
    private var statusHeader: some View {
        // 把畫面拆成多個 private computed property，body 會更短，也更容易閱讀與維護。
        VStack(spacing: 12) {
            Text("20-20-20 護眼助理")
                .font(.system(.caption, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.1)))
            
            Text(manager.currentStep.name)
                .font(.title2.bold())
                .foregroundColor(manager.isAlarming ? .red : .primary)
                // value 指定動畫只在 isAlarming 改變時觸發，避免所有狀態更新都套動畫。
                .animation(.easeInOut, value: manager.isAlarming)
        }
    }
    
    // 中間的進度圓圈組件
    private var progressCircle: some View {
        ZStack {
            // 背景灰圈
            Circle()
                .stroke(Color.gray.opacity(0.1), lineWidth: 15)
            
            // 彩色進度圈
            Circle()
                // trim 只畫出圓的一部分；剩餘秒數越少，彩色弧線越短。
                .trim(from: 0, to: manager.timeRemaining / Double(manager.currentStep.seconds))
                .stroke(
                    manager.isAlarming ? Color.red : manager.currentStep.themeColor,
                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                )
                .rotationEffect(.degrees(-90)) // 起點修正到正上方
                .animation(.linear(duration: 0.2), value: manager.timeRemaining)
            
            VStack(spacing: 10) {
                // 圖示
                Image(systemName: manager.currentStep.icon)
                    .font(.largeTitle)
                    .foregroundColor(manager.isAlarming ? .red : manager.currentStep.themeColor)
                
                // 時間文字（例如 19:59）
                Text(timeString(from: Int(ceil(manager.timeRemaining))))
                    .font(.system(size: 55, weight: .bold, design: .monospaced))
            }
        }
        .frame(width: 250, height: 250)
    }
    
    // 下方按鈕組件
    private var actionControls: some View {
        HStack(spacing: 40) {
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
                        .frame(width: 80, height: 80)
                        .shadow(color: mainButtonColor.opacity(0.3), radius: 10, y: 5)
                    
                    Image(systemName: mainButtonIcon)
                        .font(.title.bold())
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
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
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
}
