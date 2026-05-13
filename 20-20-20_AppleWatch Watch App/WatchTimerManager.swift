import SwiftUI
import Combine
import WatchKit
@preconcurrency import UserNotifications

// MARK: - Apple Watch 倒數核心
@MainActor
final class WatchTimerManager: NSObject, ObservableObject {
    static let shared = WatchTimerManager()
    
    @Published var currentStep: WatchTimerStep = .work1
    @Published var timeRemaining = Double(WatchTimerStep.work1.seconds)
    @Published var isRunning = false
    @Published var isAlarming = false
    
    private var targetDate: Date?
    private var displayTimer: AnyCancellable?
    private var settingsObserver: AnyCancellable?
    private var alarmSession: WKExtendedRuntimeSession?
    private var invalidatingAlarmSessions: [WKExtendedRuntimeSession] = []
    
    private override init() {
        super.init()
        WatchAppConfiguration.registerDefaults()
        requestNotificationPermission()
        setupDisplayTimer()
        observeSettingsChanges()
    }
    
    func toggle() {
        if isRunning {
            pause()
        } else {
            start()
        }
        playTapHaptic()
    }
    
    func start() {
        let finishDate = Date().addingTimeInterval(timeRemaining)
        targetDate = finishDate
        isRunning = true
        isAlarming = false
        scheduleSmartAlarmSession(at: finishDate)
    }
    
    func pause() {
        isRunning = false
        targetDate = nil
        cancelSmartAlarmSession()
    }
    
    func reset() {
        pause()
        isAlarming = false
        currentStep = .work1
        timeRemaining = Double(currentStep.seconds)
        playTapHaptic()
    }
    
    func stopAlarmAlertAfterOpeningApp() {
        guard isAlarming else { return }
        
        // 用戶點擊 smart alarm 提示回到 App 後，停止 watchOS alarm session。
        // 這只負責停聲 / 停 haptic，不會自動進入下一階段，避免使用者還未確認就跳走。
        cancelSmartAlarmSession()
    }
    
    func nextStep() {
        let isLastStep = currentStep == .longRest
        isAlarming = false
        
        let allSteps = WatchTimerStep.allCases
        let nextIndex = (currentStep.rawValue + 1) % allSteps.count
        currentStep = allSteps[nextIndex]
        timeRemaining = Double(currentStep.seconds)
        
        if isLastStep {
            pause()
        } else {
            start()
        }
        playTapHaptic()
    }
    
    private func setupDisplayTimer() {
        displayTimer = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.syncRemainingTime() }
    }
    
    private func observeSettingsChanges() {
        settingsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadDurationIfIdle() }
    }
    
    func reloadDurationIfIdle() {
        // 如果倒數正在跑或正在響，不中途改時間，避免 targetDate 和 smart alarm session 被改亂。
        guard !isRunning, !isAlarming else { return }
        timeRemaining = Double(currentStep.seconds)
    }
    
    private func syncRemainingTime() {
        guard isRunning, let targetDate else { return }
        let diff = targetDate.timeIntervalSinceNow
        
        if diff > 0 {
            timeRemaining = diff
        } else {
            triggerAlarm()
        }
    }
    
    private func triggerAlarm() {
        guard !isAlarming else { return }
        isRunning = false
        isAlarming = true
        timeRemaining = 0
        targetDate = nil
        WKInterfaceDevice.current().play(.notification)
    }
    
    private func scheduleSmartAlarmSession(at date: Date) {
        cancelSmartAlarmSession()
        
        // Smart alarm extended runtime session 是 watchOS 背景鬧鐘機制。
        // 它不是本地通知倒數；畫面上仍然只有 app 自己的一個倒數。
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        alarmSession = session
        print("Watch smart alarm scheduled at \(date)")
        session.start(at: date)
    }
    
    private func cancelSmartAlarmSession() {
        guard let alarmSession else { return }
        print("Watch smart alarm cancelled")
        invalidatingAlarmSessions.append(alarmSession)
        alarmSession.invalidate()
        self.alarmSession = nil
    }
    
    private func triggerAlarmFromSmartAlarmSession(_ session: WKExtendedRuntimeSession) {
        guard alarmSession === session else { return }
        
        if !isAlarming {
            isRunning = false
            isAlarming = true
            timeRemaining = 0
            targetDate = nil
        }
        WKInterfaceDevice.current().play(.notification)
        
        // 如果 app 在背景，notifyUser 會顯示 watchOS 系統 alarm alert / haptic。
        // Watch 版不使用自訂鈴聲，避免背景音訊被系統拒絕。
        print("Watch smart alarm started; notifying user")
        session.notifyUser(hapticType: .notification) { nextHapticType in
            nextHapticType.pointee = .notification
            return 2
        }
    }
    
    private func playTapHaptic() {
        WKInterfaceDevice.current().play(.click)
    }
    
    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = WatchNotificationPresenter.shared
        
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            
            // 第一次啟動 Watch app 時，系統會問你是否允許通知。
            // 未允許之前，倒數完成仍會有 haptic，但不會有系統通知。
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }
}

extension WatchTimerManager: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("Watch smart alarm session did start")
        Task { @MainActor in
            self.triggerAlarmFromSmartAlarmSession(extendedRuntimeSession)
        }
    }
    
    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        print("Watch smart alarm session will expire")
        extendedRuntimeSession.invalidate()
    }
    
    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        print("Watch smart alarm session invalidated: \(reason), error: \(String(describing: error))")
        Task { @MainActor in
            if self.alarmSession === extendedRuntimeSession {
                self.alarmSession = nil
            }
            
            self.invalidatingAlarmSessions.removeAll { $0 === extendedRuntimeSession }
        }
    }
}
