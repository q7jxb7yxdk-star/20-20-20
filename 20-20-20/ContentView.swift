import SwiftUI
import UserNotifications
import Combine
import AVFoundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - 1. 護眼階段配置
/// 定義 20-20-20 法則的四個循環階段
enum TimerStep: Int, CaseIterable {
    case work1 = 0, eyeCare = 1, work2 = 2, longRest = 3
    
    /// 各階段顯示名稱
    var name: String {
        switch self {
        case .work1: return "第一階段：專注工作"
        case .eyeCare: return "第二階段：遠眺放鬆"
        case .work2: return "第三階段：專注工作"
        case .longRest: return "第四階段：深度休息"
        }
    }
    
    /// 各階段持續時間 (秒)
    var seconds: Int {
        switch self {
        case .work1, .work2:
            #if DEBUG
            return 10 // 測試模式使用 10 秒
            #else
            return 20 * 60 // 正式模式使用 20 分鐘
            #endif
        case .eyeCare:
            #if DEBUG
            return 5
            #else
            return 20 // 遠眺 20 秒
            #endif
        case .longRest:
            #if DEBUG
            return 8
            #else
            return 3 * 60 // 深度休息 3 分鐘
            #endif
        }
    }
    
    /// 階段對應圖示
    var icon: String {
        switch self {
        case .work1, .work2: return "laptopcomputer"
        case .eyeCare: return "eye.fill"
        case .longRest: return "cup.and.saucer.fill"
        }
    }
    
    /// 階段對應主題顏色
    var themeColor: Color {
        switch self {
        case .eyeCare: return .green
        case .longRest: return .orange
        default: return .blue
        }
    }
}

// MARK: - 2. 核心大腦 (處理計時邏輯、音訊與通知)
class TimerManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    
    // UI 觀察屬性
    @Published var currentStep: TimerStep = .work1      // 當前階段
    @Published var timeRemaining: Double = Double(TimerStep.work1.seconds) // 剩餘時間 (改為 Double 以支持順滑更新)
    @Published var isRunning = false                    // 是否正在計時
    @Published var isAlarming = false                   // 是否正在鬧鈴中
    
    private var targetDate: Date?                       // 目標結束時間
    private var alarmTimer: AnyCancellable?             // 鬧鈴循環計時器
    private var displayTimer: AnyCancellable?           // 畫面更新計時器
    private var cancellables = Set<AnyCancellable>()
    
    // --- 音樂播放組件 ---
    private var audioPlayer: AVAudioPlayer?
    private let soundFileName = "alarm"                 // 檔案名稱 (不含副檔名)
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupDisplayTimer()
        setupLifecycleObservers()
        prepareAudioPlayer()
    }
    
    /// App 啟動時的初始化設定
    func setupOnLaunch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.requestNotificationPermission()
            self.configureAudioSession()
        }
    }

    /// 配置音訊會話 (Audio Session)
    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback,
                                    mode: .default,
                                    options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Audio Session 設定失敗: \(error)")
        }
        #endif
    }
    
    /// 預先加載音樂檔案
    private func prepareAudioPlayer() {
        guard let url = Bundle.main.url(forResource: soundFileName, withExtension: "caf") else {
            print("找不到音樂檔案: \(soundFileName).caf")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.numberOfLoops = 0
            audioPlayer?.volume = 1.0
        } catch {
            print("無法初始化音樂播放器: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 計時邏輯區
    
    /// 設定高頻率更新計時器 (每 0.05 秒更新一次)
    /// 💡 優化：提高更新頻率讓圓環縮減更順滑
    private func setupDisplayTimer() {
        displayTimer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.syncRemainingTime() }
    }

    /// 同步計算剩餘時間 (精準計算法)
    private func syncRemainingTime() {
        guard isRunning, let target = targetDate else { return }
        let diff = target.timeIntervalSinceNow
        
        if diff > 0 {
            self.timeRemaining = diff
        } else {
            triggerAlarm()
        }
    }

    /// 監聽系統生命週期
    private func setupLifecycleObservers() {
        #if os(iOS)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.syncRemainingTime()
            }
            .store(in: &cancellables)
        #endif
    }

    // MARK: - 用戶動作處理
    
    func toggle() {
        if isRunning { pause() } else { start() }
        triggerHaptic()
    }

    func start() {
        targetDate = Date().addingTimeInterval(timeRemaining)
        isRunning = true
        isAlarming = false
        stopAlarmLoop()
        scheduleLocalNotification()
    }

    func pause() {
        isRunning = false
        targetDate = nil
        cancelNotifications()
    }

    func reset() {
        pause()
        stopAlarmLoop()
        isAlarming = false
        currentStep = .work1
        timeRemaining = Double(currentStep.seconds)
        triggerHaptic()
    }

    func triggerAlarm() {
        guard !isAlarming else { return }
        isRunning = false
        isAlarming = true
        timeRemaining = 0
        targetDate = nil
        startAlarmLoop()
    }

    func nextStep() {
        let isLastStep = currentStep == .longRest
        stopAlarmLoop()
        isAlarming = false
        
        let allSteps = TimerStep.allCases
        let nextIndex = (currentStep.rawValue + 1) % allSteps.count
        currentStep = allSteps[nextIndex]
        timeRemaining = Double(currentStep.seconds)
        
        if !isLastStep {
            start()
        } else {
            pause()
        }
        triggerHaptic()
    }

    // MARK: - 通知與音效系統
    
    private func scheduleLocalNotification() {
        cancelNotifications()
        let content = UNMutableNotificationContent()
        content.title = "時間到！"
        content.body = "「\(currentStep.name)」已完成，請按下按鈕開始下一階段。"
        content.sound = nil
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.1, timeRemaining), repeats: false)
        let request = UNNotificationRequest(identifier: "202020Notification", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private func startAlarmLoop() {
        playDeviceAlert()
        alarmTimer = Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.playDeviceAlert() }
    }

    private func stopAlarmLoop() {
        alarmTimer?.cancel()
        alarmTimer = nil
        audioPlayer?.stop()
    }

    private func playDeviceAlert() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        
        // 1. 播放自定義音效
        if let player = audioPlayer {
            player.volume = 1.0
            player.currentTime = 0
            player.play()
        }
        
        // 2. macOS 專屬：若沒有播放器，則嗶一聲
        #if os(macOS)
        if audioPlayer == nil {
            NSSound.beep()
        }
        #endif
        
        // 3. iOS 專屬：震動
        #if os(iOS)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        #endif
    }

    private func triggerHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        triggerAlarm()
        completionHandler([.banner, .list])
    }
}

// MARK: - 3. 介面外觀區 (View)
struct ContentView: View {
    @StateObject private var manager = TimerManager()
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                statusHeader.padding(.bottom, 40)
                progressCircle.padding(.bottom, 40)
                actionControls
                Spacer()
                stepDots
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 600)
        #endif
        .onAppear { manager.setupOnLaunch() }
    }
}

// MARK: - 4. 介面組件詳解
extension ContentView {
    
    private var statusHeader: some View {
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
                .animation(.easeInOut, value: manager.isAlarming)
        }
    }
    
    /// 中央進度圓環
    /// 💡 優化：使用 .linear 動畫與高頻率數據同步，讓圓環縮減變得絲滑
    private var progressCircle: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.1), lineWidth: 15)
            
            Circle()
                .trim(from: 0, to: manager.timeRemaining / Double(manager.currentStep.seconds))
                .stroke(
                    manager.isAlarming ? Color.red : manager.currentStep.themeColor,
                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                // 💡 使用線性動畫處理進度變化，消除頓挫感
                .animation(.linear(duration: 0.05), value: manager.timeRemaining)
            
            VStack(spacing: 10) {
                Image(systemName: manager.currentStep.icon)
                    .font(.largeTitle)
                    .foregroundColor(manager.isAlarming ? .red : manager.currentStep.themeColor)
                
                // 數字部分依然顯示整數秒，保持簡潔
                Text(timeString(from: Int(ceil(manager.timeRemaining))))
                    .font(.system(size: 55, weight: .bold, design: .monospaced))
            }
        }
        .frame(width: 250, height: 250)
    }
    
    private var actionControls: some View {
        HStack(spacing: 40) {
            Button(action: {
                if manager.isAlarming {
                    manager.nextStep()
                } else {
                    manager.toggle()
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
    
    private var mainButtonIcon: String {
        if manager.isAlarming { return "checkmark" }
        return manager.isRunning ? "pause.fill" : "play.fill"
    }
    
    private var mainButtonColor: Color {
        if manager.isAlarming { return .orange }
        return manager.isRunning ? .red : .blue
    }
    
    private var backgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }
    
    private func timeString(from totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - 5. App 入口
@main
struct EyeCareTimerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
