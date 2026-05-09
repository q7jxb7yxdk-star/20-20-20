import SwiftUI
import Combine
import WatchKit
@preconcurrency import UserNotifications

// MARK: - Apple Watch 倒數核心
@MainActor
final class WatchTimerManager: ObservableObject {
    @Published var currentStep: WatchTimerStep = .work1
    @Published var timeRemaining = Double(WatchTimerStep.work1.seconds)
    @Published var isRunning = false
    @Published var isAlarming = false
    
    private var targetDate: Date?
    private var displayTimer: AnyCancellable?
    private let scheduledNotificationIdentifier = "202020WatchNotification.scheduled"
    private let notificationIdentifierPrefix = "202020WatchNotification.alarm"
    
    init() {
        requestNotificationPermission()
        setupDisplayTimer()
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
        targetDate = Date().addingTimeInterval(timeRemaining)
        isRunning = true
        isAlarming = false
        scheduleAlarmNotification()
    }
    
    func pause() {
        isRunning = false
        targetDate = nil
        cancelScheduledNotification()
    }
    
    func reset() {
        pause()
        isAlarming = false
        currentStep = .work1
        timeRemaining = Double(currentStep.seconds)
        playTapHaptic()
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
        cancelScheduledNotification()
        deliverAlarmNotificationImmediately()
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
    
    private func deliverAlarmNotificationImmediately() {
        let center = UNUserNotificationCenter.current()
        center.delegate = WatchNotificationPresenter.shared
        
        let request = UNNotificationRequest(
            identifier: "\(notificationIdentifierPrefix).\(UUID().uuidString)",
            content: makeAlarmNotificationContent(),
            trigger: nil
        )
        
        center.add(request)
    }
    
    private func scheduleAlarmNotification() {
        let center = UNUserNotificationCenter.current()
        center.delegate = WatchNotificationPresenter.shared
        
        // Watch app 進入背景後，Swift timer 可能會暫停或被系統延後。
        // 所以開始倒數時就先排一個系統通知，背景時由 watchOS 負責準時提醒。
        let content = makeAlarmNotificationContent()
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, timeRemaining), repeats: false)
        let request = UNNotificationRequest(
            identifier: scheduledNotificationIdentifier,
            content: content,
            trigger: trigger
        )
        
        center.removePendingNotificationRequests(withIdentifiers: [scheduledNotificationIdentifier])
        center.add(request)
    }
    
    private func makeAlarmNotificationContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = currentStep.completedTitle
        content.body = "請打開 20-20-20，點擊橘色打勾進入下一個階段。"
        content.sound = .default
        return content
    }
    
    private func cancelScheduledNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [scheduledNotificationIdentifier])
    }
}
