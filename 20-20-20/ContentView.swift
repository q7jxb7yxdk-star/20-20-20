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
enum TimerStep: Int, CaseIterable {
    case work1 = 0, eyeCare = 1, work2 = 2, longRest = 3
    
    var name: String {
        switch self {
        case .work1: return "第一階段：專注工作"
        case .eyeCare: return "第二階段：遠眺放鬆"
        case .work2: return "第三階段：專注工作"
        case .longRest: return "第四階段：深度休息"
        }
    }
    
    var seconds: Int {
        #if DEBUG
        switch self {
        case .work1, .work2: return 10
        case .eyeCare: return 5
        case .longRest: return 8
        }
        #else
        switch self {
        case .work1, .work2: return 20 * 60
        case .eyeCare: return 20
        case .longRest: return 3 * 60
        }
        #endif
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
        default: return .blue
        }
    }
}

// MARK: - 2. 核心大腦
class TimerManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    
    @Published var currentStep: TimerStep = .work1
    @Published var timeRemaining: Double = Double(TimerStep.work1.seconds)
    @Published var isRunning = false
    @Published var isAlarming = false
    
    private var targetDate: Date?
    private var displayTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    
    // 音訊播放器（專門用於前台提醒）
    private var audioPlayer: AVAudioPlayer?
    private let soundFileName = "alarm"
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupDisplayTimer()
        setupLifecycleObservers()
        prepareAudio()
    }
    
    func setupOnLaunch() {
        requestNotificationPermission()
        #if os(iOS)
        configureAudioSession()
        #endif
    }
    
    private func prepareAudio() {
        guard let url = Bundle.main.url(forResource: soundFileName, withExtension: "caf") else {
            print("找不到音效文件: \(soundFileName).caf")
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
        } catch {
            print("音訊初始化失敗: \(error)")
        }
    }

    #if os(iOS)
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // 修正處：Category 為 .playback，Options 包含 .duckOthers
            try session.setCategory(.playback, mode: .default, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        } catch {
            print("Audio Session 配置失敗: \(error)")
        }
    }
    #endif

    private func setupDisplayTimer() {
        displayTimer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.syncRemainingTime() }
    }

    private func syncRemainingTime() {
        guard isRunning, let target = targetDate else { return }
        let diff = target.timeIntervalSinceNow
        
        if diff > 0 {
            self.timeRemaining = diff
        } else {
            triggerAlarm()
        }
    }

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
        scheduleLocalNotification()
    }

    func pause() {
        isRunning = false
        targetDate = nil
        cancelNotifications()
    }

    func reset() {
        pause()
        isAlarming = false
        audioPlayer?.stop()
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
        
        playAlarmSound()
        triggerHaptic()
    }

    func nextStep() {
        let isLastStep = currentStep == .longRest
        isAlarming = false
        audioPlayer?.stop()
        
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

    private func playAlarmSound() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        audioPlayer?.currentTime = 0
        audioPlayer?.play()
    }

    // MARK: - 通知系統
    
    private func scheduleLocalNotification() {
        cancelNotifications()
        let content = UNMutableNotificationContent()
        content.title = "時間到！"
        content.body = "「\(currentStep.name)」已完成，請開始下一階段。"
        
        // 指定專案內的音效文件
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(soundFileName).caf"))
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.1, timeRemaining), repeats: false)
        let request = UNNotificationRequest(identifier: "202020Notification", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    private func triggerHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}

// MARK: - 3. 介面外觀區
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
                .animation(.linear(duration: 0.05), value: manager.timeRemaining)
            
            VStack(spacing: 10) {
                Image(systemName: manager.currentStep.icon)
                    .font(.largeTitle)
                    .foregroundColor(manager.isAlarming ? .red : manager.currentStep.themeColor)
                
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

// MARK: - 4. App 入口
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
