import SwiftUI
import Combine
import WatchKit
@preconcurrency import UserNotifications

// MARK: - Apple Watch 倒數核心
@MainActor
final class WatchTimerManager: NSObject, ObservableObject {
    static let shared = WatchTimerManager()
    
    @Published var currentStep: WatchTimerStep = .work1
    @Published var selectedStep: WatchTimerStep = .work1
    @Published var timeRemaining = Double(WatchTimerStep.work1.seconds)
    @Published var isRunning = false
    @Published var isAlarming = false
    private(set) var isAppActive = true
    
    private var targetDate: Date?
    private var stepRemainingSeconds = WatchTimerStep.allCases.map { Double($0.seconds) }
    private var shouldResetSelectedStepOnStart = false
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
    
    var displayStep: WatchTimerStep {
        selectedStep
    }
    
    var displayTimeRemaining: Double {
        timeRemaining
    }
    
    var displayIsRunning: Bool {
        isRunning && selectedStep == currentStep
    }
    
    var displayIsAlarming: Bool {
        isAlarming && selectedStep == currentStep
    }
    
    func toggle() {
        if isRunning && selectedStep == currentStep {
            pause()
        } else {
            start()
        }
        playTapHaptic()
    }
    
    func start() {
        if isRunning {
            if currentStep == selectedStep, let targetDate {
                setRemainingSeconds(targetDate.timeIntervalSinceNow, for: currentStep)
            } else {
                setRemainingSeconds(Double(currentStep.seconds), for: currentStep)
            }
        }
        
        currentStep = selectedStep
        
        if shouldResetSelectedStepOnStart {
            timeRemaining = Double(currentStep.seconds)
            setRemainingSeconds(timeRemaining, for: currentStep)
            shouldResetSelectedStepOnStart = false
        } else {
            timeRemaining = remainingSeconds(for: currentStep)
        }
        
        let finishDate = Date().addingTimeInterval(timeRemaining)
        targetDate = finishDate
        isRunning = true
        isAlarming = false
        scheduleSmartAlarmSession(at: finishDate)
    }
    
    func pause() {
        if isRunning, let targetDate {
            setRemainingSeconds(targetDate.timeIntervalSinceNow, for: currentStep)
            if selectedStep == currentStep {
                timeRemaining = remainingSeconds(for: currentStep)
            }
        }
        
        isRunning = false
        targetDate = nil
        cancelSmartAlarmSession(reason: "pause")
    }
    
    func reset() {
        pause()
        isAlarming = false
        currentStep = .work1
        selectedStep = .work1
        shouldResetSelectedStepOnStart = false
        stepRemainingSeconds = WatchTimerStep.allCases.map { Double($0.seconds) }
        timeRemaining = Double(currentStep.seconds)
        playTapHaptic()
    }
    
    func stopAlarmAlertAfterOpeningApp() {
        guard isAlarming else { return }
        
        // 用戶點擊 smart alarm 提示回到 App 後，停止 watchOS alarm session。
        // 這只負責停聲 / 停 haptic，不會自動進入下一階段，避免使用者還未確認就跳走。
        cancelSmartAlarmSession(reason: "opened app while alarming")
    }
    
    func updateAppActiveState(_ isActive: Bool) {
        isAppActive = isActive
    }
    
    func nextStep() {
        let isLastStep = currentStep == .longRest
        isAlarming = false
        
        let allSteps = WatchTimerStep.allCases
        let nextIndex = (currentStep.rawValue + 1) % allSteps.count
        currentStep = allSteps[nextIndex]
        selectedStep = currentStep
        shouldResetSelectedStepOnStart = false
        timeRemaining = Double(currentStep.seconds)
        setRemainingSeconds(timeRemaining, for: currentStep)
        
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
        // 即使倒數正在跑，語言同步後也要通知 SwiftUI 重畫標題文字。
        objectWillChange.send()
        // 如果倒數正在跑或正在響，不中途改時間，避免 targetDate 和 smart alarm session 被改亂。
        guard !isRunning, !isAlarming else { return }
        stepRemainingSeconds = WatchTimerStep.allCases.map { Double($0.seconds) }
        selectedStep = currentStep
        timeRemaining = Double(currentStep.seconds)
    }
    
    private func syncRemainingTime() {
        guard isRunning, let targetDate else { return }
        let diff = targetDate.timeIntervalSinceNow
        
        if diff > 0 {
            setRemainingSeconds(diff, for: currentStep)
            if selectedStep == currentStep {
                timeRemaining = diff
            }
        } else {
            triggerAlarm()
        }
    }
    
    private func setRemainingSeconds(_ seconds: Double, for step: WatchTimerStep) {
        stepRemainingSeconds[step.rawValue] = max(0, seconds)
    }
    
    private func remainingSeconds(for step: WatchTimerStep) -> Double {
        stepRemainingSeconds[step.rawValue]
    }
    
    func selectStep(_ step: WatchTimerStep) {
        if isRunning, let targetDate {
            setRemainingSeconds(targetDate.timeIntervalSinceNow, for: currentStep)
        }
        
        selectedStep = step
        shouldResetSelectedStepOnStart = step != currentStep
        timeRemaining = remainingSeconds(for: step)
        playTapHaptic()
    }
    
    func selectPreviousStep() {
        let allSteps = WatchTimerStep.allCases
        let previousIndex = (selectedStep.rawValue - 1 + allSteps.count) % allSteps.count
        selectStep(allSteps[previousIndex])
    }
    
    func selectNextStep() {
        let allSteps = WatchTimerStep.allCases
        let nextIndex = (selectedStep.rawValue + 1) % allSteps.count
        selectStep(allSteps[nextIndex])
    }
    
    private func triggerAlarm() {
        guard !isAlarming else { return }
        
        // Do not invalidate the scheduled smart alarm here.
        // watchOS may treat a just-in-time invalidation as a missed scheduled alarm.
        setRemainingSeconds(0, for: currentStep)
        selectedStep = currentStep
        shouldResetSelectedStepOnStart = false
        isRunning = false
        isAlarming = true
        timeRemaining = 0
        targetDate = nil
        WKInterfaceDevice.current().play(.notification)
    }
    
    private func scheduleSmartAlarmSession(at date: Date) {
        cancelSmartAlarmSession(reason: "reschedule")
        
        // Smart alarm extended runtime session 是 watchOS 背景鬧鐘機制。
        // 它不是本地通知倒數；畫面上仍然只有 app 自己的一個倒數。
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        alarmSession = session
        print("Watch smart alarm scheduled at \(date)")
        session.start(at: date)
    }
    
    private func cancelSmartAlarmSession(reason: String) {
        guard let alarmSession else { return }
        print("Watch smart alarm cancelled: \(reason)")
        invalidatingAlarmSessions.append(alarmSession)
        alarmSession.invalidate()
        self.alarmSession = nil
    }
    
    func recoverSmartAlarmSession(_ session: WKExtendedRuntimeSession) {
        print("Watch smart alarm recovered with state: \(session.state.rawValue)")
        alarmSession = session
        session.delegate = self
        
        if session.state == .running {
            startSmartAlarmNotification(for: session)
            finishSmartAlarmStateIfNeeded()
        }
    }
    
    nonisolated private func startSmartAlarmNotification(for session: WKExtendedRuntimeSession) {
        // If the app is in the background, watchOS expects the alarm session to notify the user immediately.
        // Keep this outside the MainActor hop so the scheduled alarm is not marked as missed by the system.
        print("Watch smart alarm started; notifying user")
        session.notifyUser(hapticType: .notification) { nextHapticType in
            nextHapticType.pointee = .notification
            return 2
        }
    }
    
    private func finishSmartAlarmStateIfNeeded() {
        guard !isAlarming else { return }
        
        setRemainingSeconds(0, for: currentStep)
        selectedStep = currentStep
        shouldResetSelectedStepOnStart = false
        isRunning = false
        isAlarming = true
        timeRemaining = 0
        targetDate = nil
        WKInterfaceDevice.current().play(.notification)
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
        startSmartAlarmNotification(for: extendedRuntimeSession)
        Task { @MainActor in
            guard self.alarmSession === extendedRuntimeSession else { return }
            self.finishSmartAlarmStateIfNeeded()
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
