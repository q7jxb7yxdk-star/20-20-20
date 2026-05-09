import SwiftUI
import Combine
import WatchKit

// MARK: - Apple Watch 倒數核心
@MainActor
final class WatchTimerManager: ObservableObject {
    @Published var currentStep: WatchTimerStep = .work1
    @Published var timeRemaining = Double(WatchTimerStep.work1.seconds)
    @Published var isRunning = false
    @Published var isAlarming = false
    
    private var targetDate: Date?
    private var displayTimer: AnyCancellable?
    
    init() {
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
    }
    
    func pause() {
        isRunning = false
        targetDate = nil
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
    }
    
    private func playTapHaptic() {
        WKInterfaceDevice.current().play(.click)
    }
}
