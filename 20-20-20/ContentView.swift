import SwiftUI
import UserNotifications
import Combine
import AVFoundation

// 根據不同的作業系統（iPhone 或 Mac）導入必要的工具箱
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - 1. 護眼階段配置 (設定工作與休息的時間)
/// 這裡定義了四個階段：工作1 -> 遠眺 -> 工作2 -> 長休息
enum TimerStep: Int, CaseIterable {
    case work1 = 0, eyeCare = 1, work2 = 2, longRest = 3
    
    /// 顯示在畫面上的標題文字
    var name: String {
        switch self {
        case .work1: return "第一階段：專注工作"
        case .eyeCare: return "第二階段：遠眺放鬆"
        case .work2: return "第三階段：專注工作"
        case .longRest: return "第四階段：深度休息"
        }
    }
    
    /// 每個階段的秒數 (isDebug 為 true 時是測試模式，秒數很短)
    var seconds: Int {
        let isDebug = true // 💡 如果要正式使用，請把這裡改為 false
        switch self {
        case .work1, .work2: return isDebug ? 10 : 20 * 60 // 測試 10 秒 / 正式 20 分鐘
        case .eyeCare:      return isDebug ? 5 : 20      // 測試 5 秒 / 正式 20 秒
        case .longRest:     return isDebug ? 8 : 3 * 60  // 測試 8 秒 / 正式 3 分鐘
        }
    }
    
    /// 顯示在圓圈中央的小圖示
    var icon: String {
        switch self {
        case .work1, .work2: return "laptopcomputer"
        case .eyeCare: return "eye.fill"
        case .longRest: return "cup.and.saucer.fill"
        }
    }
    
    /// 每個階段代表的顏色 (藍色工作、綠色保護、橘色休息)
    var themeColor: Color {
        switch self {
        case .eyeCare: return .green
        case .longRest: return .orange
        default: return .blue
        }
    }
}

// MARK: - 2. 核心大腦 (處理所有的計時邏輯)
/// TimerManager 就像 App 的心臟，負責跳動、響鬧和計算時間
class TimerManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    
    // --- 這些變數會通知介面 (UI) 自動更新 ---
    @Published var currentStep: TimerStep = .work1      // 目前在哪個階段
    @Published var timeRemaining: Int = TimerStep.work1.seconds // 剩餘多少秒
    @Published var isRunning = false                    // 是否正在倒數中
    @Published var isAlarming = false                   // 是否正在震動響鈴中
    
    // --- 內部私密變數 (使用者看不到) ---
    private var targetDate: Date?              // 預計結束的時間點 (用來對準時間)
    private var alarmTimer: AnyCancellable?    // 控制「重複響鈴」的計時器
    private var displayTimer: AnyCancellable?  // 控制「畫面數字更新」的計時器
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupDisplayTimer()
        setupLifecycleObservers()
    }
    
    /// App 啟動時要做的事情 (要求通知權限、設定音效)
    func setupOnLaunch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.requestNotificationPermission()
            self.configureAudioSession()
        }
    }

    /// 設定音效系統 (確保在手機靜音時也能根據設定發聲)
    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        #endif
    }

    // MARK: - 計時邏輯區
    /// 啟動顯示計時器，每 0.5 秒檢查一次時間是否正確
    private func setupDisplayTimer() {
        displayTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.syncRemainingTime() }
    }

    /// 同步剩餘時間：這很重要，因為 App 進入背景後計時器會暫停，我們必須用「目標時間 - 現在時間」來校正
    private func syncRemainingTime() {
        guard isRunning, let target = targetDate else { return }
        let diff = Int(ceil(target.timeIntervalSinceNow))
        if diff > 0 {
            if self.timeRemaining != diff { self.timeRemaining = diff }
        } else {
            triggerAlarm() // 時間到了，啟動鬧鐘
        }
    }

    /// 監聽系統狀態 (例如回到前台時要重新校正時間)
    private func setupLifecycleObservers() {
        #if os(iOS)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.syncRemainingTime() }
            .store(in: &cancellables)
        #endif
    }

    // MARK: - 用戶動作處理 (對應畫面上的按鈕)
    
    /// 按下「播放/暫停」按鈕的動作
    func toggle() {
        if isRunning { pause() } else { start() }
        triggerHaptic() // 震動回饋
    }

    /// 啟動倒數
    func start() {
        // 設定一個未來的目標時間點
        targetDate = Date().addingTimeInterval(Double(timeRemaining))
        isRunning = true
        isAlarming = false
        stopAlarmLoop()
        scheduleLocalNotification() // 預約系統通知
    }

    /// 暫停倒數
    func pause() {
        isRunning = false
        targetDate = nil
        cancelNotifications() // 取消已預約的通知
    }

    /// 按下「重置」按鈕的動作
    func reset() {
        pause()
        stopAlarmLoop()
        isAlarming = false
        currentStep = .work1
        timeRemaining = TimerStep.work1.seconds
        triggerHaptic()
    }

    /// 觸發鬧鐘響鈴
    func triggerAlarm() {
        guard !isAlarming else { return }
        isRunning = false
        isAlarming = true
        timeRemaining = 0
        targetDate = nil
        startAlarmLoop() // 開始重複播放音效
    }

    /// 按下「打勾確認」跳往下一階段的動作
    func nextStep() {
        let isLastStep = currentStep == .longRest // 判斷是否為最後一個階段
        stopAlarmLoop()
        isAlarming = false
        
        // 切換到下一個編號的階段
        let allSteps = TimerStep.allCases
        let nextIndex = (currentStep.rawValue + 1) % allSteps.count
        currentStep = allSteps[nextIndex]
        timeRemaining = currentStep.seconds
        
        // 💡 邏輯：如果剛結束第四階段，回到第一階段時保持暫停，不自動開始
        if !isLastStep {
            start()
        } else {
            pause()
        }
        triggerHaptic()
    }

    // MARK: - 通知與音效系統
    
    /// 預約手機系統通知 (當時間到時，即使手機螢幕關閉也會彈出提醒)
    private func scheduleLocalNotification() {
        cancelNotifications()
        let content = UNMutableNotificationContent()
        content.title = "時間到！"
        content.body = "「\(currentStep.name)」已完成，請按下按鈕開始下一階段。"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.1, Double(timeRemaining)), repeats: false)
        let request = UNNotificationRequest(identifier: "202020Notification", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// 取消所有還沒發出的通知
    private func cancelNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// 開始鬧鐘循環 (每 2 秒響一次)
    private func startAlarmLoop() {
        playDeviceAlert()
        alarmTimer = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.playDeviceAlert() }
    }

    /// 停止鬧鐘循環
    private func stopAlarmLoop() {
        alarmTimer?.cancel()
        alarmTimer = nil
    }

    /// 執行系統音效與震動
    private func playDeviceAlert() {
        #if os(iOS)
        AudioServicesPlaySystemSound(1005) // 鬧鐘聲音碼
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) // 震動
        #elseif os(macOS)
        NSSound.beep() // Mac 嗶聲
        #endif
    }

    /// 產生輕微的按鈕按壓震動感 (僅限 iPhone)
    private func triggerHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    /// 詢問使用者是否允許傳送通知
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    
    /// 處理當 App 開啟時收到通知的行為
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        triggerAlarm()
        completionHandler([.banner, .list, .sound])
    }
}

// MARK: - 3. 介面外觀區 (決定畫面長什麼樣子)
struct ContentView: View {
    // 連結上面定義的大腦 (Manager)
    @StateObject private var manager = TimerManager()
    
    var body: some View {
        ZStack {
            // 最底層：背景顏色 (會自動填滿整個視窗)
            backgroundColor
                .ignoresSafeArea()
            
            // 中間層：垂直排列的所有組件
            VStack(spacing: 0) {
                Spacer() // 彈簧 1：把內容推向中間
                
                // 顯示目前階段名稱
                statusHeader
                    .padding(.bottom, 40)
                
                // 顯示大圓圈與倒數時間
                progressCircle
                    .padding(.bottom, 40)
                
                // 顯示控制按鈕
                actionControls
                
                Spacer() // 彈簧 2：保持中間位置
                
                // 顯示底部的四個進度小點
                stepDots
                
                Spacer() // 彈簧 3：這讓底部與頂部間距對稱一致
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // 讓內容區塊可以縮放
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 600) // Mac 專用：設定視窗最小尺寸
        #endif
        .onAppear { manager.setupOnLaunch() } // 畫面一出現就執行初始化
    }
}

// MARK: - 4. 介面組件詳解 (把複雜的介面拆開寫，方便閱讀)
extension ContentView {
    
    /// 頂部：狀態與階段文字
    private var statusHeader: some View {
        VStack(spacing: 12) {
            // 小標籤
            Text("20-20-20 護眼助理")
                .font(.system(.caption, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.1)))
            
            // 階段大標題
            Text(manager.currentStep.name)
                .font(.title2.bold())
                .foregroundColor(manager.isAlarming ? .red : .primary)
                .animation(.easeInOut, value: manager.isAlarming)
        }
    }
    
    /// 中央：進度圓環與時間數字
    private var progressCircle: some View {
        ZStack {
            // 底色圓環 (淺灰色)
            Circle()
                .stroke(Color.gray.opacity(0.1), lineWidth: 15)
            
            // 動態進度條 (會隨時間變短)
            Circle()
                .trim(from: 0, to: CGFloat(manager.timeRemaining) / CGFloat(manager.currentStep.seconds))
                .stroke(
                    manager.isAlarming ? Color.red : manager.currentStep.themeColor,
                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                )
                .rotationEffect(.degrees(-90)) // 從 12 點鐘方向開始
                .animation(.easeInOut(duration: 0.5), value: manager.timeRemaining)
            
            // 圓圈內部的圖示與時間
            VStack(spacing: 10) {
                Image(systemName: manager.currentStep.icon)
                    .font(.largeTitle)
                    .foregroundColor(manager.isAlarming ? .red : manager.currentStep.themeColor)
                
                // 顯示時間 mm:ss
                Text(timeString(from: manager.timeRemaining))
                    .font(.system(size: 55, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText()) // 讓數字變換更有質感
            }
        }
        .frame(width: 250, height: 250)
    }
    
    /// 按鈕區域：包含「主要控制按鈕」與「重置按鈕」
    private var actionControls: some View {
        HStack(spacing: 40) {
            
            // --- 按鈕 A: 主要控制按鈕 (播放 / 暫停 / 完成) ---
            Button(action: {
                if manager.isAlarming {
                    manager.nextStep() // 如果正在響，按下就代表「我完成了，去下一關」
                } else {
                    manager.toggle()   // 如果沒在響，就是「開始或暫停」
                }
            }) {
                ZStack {
                    Circle()
                        .fill(mainButtonColor)
                        .frame(width: 80, height: 80)
                        .shadow(color: mainButtonColor.opacity(0.3), radius: 10, y: 5)
                    
                    // 根據狀態顯示不同圖標 (打勾 / 暫停 / 播放)
                    Image(systemName: mainButtonIcon)
                        .font(.title.bold())
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(manager.isAlarming ? 1.15 : 1.0) // 響鈴時按鈕會稍微放大，提醒你去按它
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: manager.isAlarming)
            
            // --- 按鈕 B: 重置按鈕 (回到第一關最一開始) ---
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
    
    /// 底部：進度指示圓點 (告知現在是第幾個階段)
    private var stepDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<TimerStep.allCases.count, id: \.self) { index in
                Circle()
                    .fill(manager.currentStep.rawValue == index ? manager.currentStep.themeColor : Color.gray.opacity(0.2))
                    .frame(width: 8, height: 8)
                    .animation(.spring(), value: manager.currentStep)
            }
        }
    }
    
    // MARK: - 小工具 (小邏輯輔助)
    
    // 決定主按鈕要顯示什麼圖案
    private var mainButtonIcon: String {
        if manager.isAlarming { return "checkmark" } // 響鈴時顯示打勾
        return manager.isRunning ? "pause.fill" : "play.fill" // 計時中顯示暫停，停止時顯示播放
    }
    
    // 決定主按鈕的顏色
    private var mainButtonColor: Color {
        if manager.isAlarming { return .orange } // 響鈴時變成橘色提醒
        return manager.isRunning ? .red : .blue // 計時中紅色、暫停中藍色
    }
    
    // 取得系統背景顏色 (適應深色模式)
    private var backgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }
    
    // 將總秒數轉換成 00:00 格式
    private func timeString(from totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - 5. App 入口 (App 從這裡開始跑)
@main
struct EyeCareTimerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView() // 啟動畫面
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar) // Mac 專用：隱藏標題列讓畫面更美
        #endif
    }
}
