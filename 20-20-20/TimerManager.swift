import SwiftUI
@preconcurrency import UserNotifications
import Combine

#if os(iOS)
import AlarmKit
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - 2. 核心大腦 (處理計時邏輯、音效與通知)
@MainActor
class TimerManager: NSObject, ObservableObject {
    
    // 被標註為 @Published 的變數，一旦改變，畫面就會跟著重新繪製
    @Published var currentStep: TimerStep = .work1      // 當前階段
    @Published var timeRemaining: Double = Double(TimerStep.work1.seconds) // 剩餘秒數
    @Published var isRunning = false                    // 是否正在跑
    @Published var isAlarming = false                   // 是否正在響鈴
    
    // targetDate 是「絕對時間點」，不是每秒遞減的計數器。
    // 好處：App 暫時卡住或進入背景後，回來時仍可用現在時間重新算出準確剩餘秒數。
    private var targetDate: Date?                       // 預計結束的時間點
    // AnyCancellable 是 Combine 的訂閱憑證；保存它，Timer 才會持續發送事件。
    private var displayTimer: AnyCancellable?           // 控制畫面跳動的定時器
    // 用 Set 收集多個訂閱，TimerManager 釋放時這些訂閱也會一起取消。
    private var cancellables = Set<AnyCancellable>()    // 系統清理記憶體用
    // 記住上一次使用的模式，避免 App 回到前景時因為 UserDefaults 通知而誤把暫停中的倒數重設。
    private var lastRunMode = AppConfiguration.runMode
    
    #if os(macOS)
    // macOS 沒有使用 AlarmKit，所以仍由 App 內的 NSSound 播放提醒聲。
    private var alarmSound: NSSound?
    #endif
    private let soundFileName = "alarm"                 // 預備播放的檔案名稱
    private let scheduledNotificationIdentifier = "202020Notification.scheduled"
    private let deliveredNotificationIdentifierPrefix = "202020Notification.alarm"
    nonisolated private static let isVerboseLoggingEnabled = false
    
    #if os(iOS)
    private let alarmManager = AlarmManager.shared
    // 保存目前排程中的 Alarm ID，之後暫停、重置、停止響鈴時才知道要操作哪一個系統鬧鐘。
    private var scheduledAlarmID: Alarm.ID?
    // token 用來避免非同步排程的競態問題：
    // 如果使用者快速按開始/暫停，舊的 Task 完成時不能覆蓋新的狀態。
    private var alarmSchedulingToken = UUID()
    // 保存監聽 AlarmKit 更新的 Task，之後如需重新監聽或物件釋放時可以取消。
    private var alarmUpdatesTask: Task<Void, Never>?
    #endif
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared // 讓常駐物件處理通知彈窗
        setupDisplayTimer()       // 啟動 0.2 秒一次的畫面更新機制
        setupLifecycleObservers() // 監聽 App 進入背景或回到前台
        #if os(iOS)
        observeAlarmKitUpdates()   // 監聽 AlarmKit 的系統鬧鐘狀態
        #endif
        #if os(macOS)
        prepareAudio()            // 預先載入鈴聲檔案
        #endif
    }
    
    // App 開啟時的初始化設置
    func setupOnLaunch() {
        #if os(iOS)
        Task { await requestAlarmKitPermissionIfNeeded() }
        #else
        requestNotificationPermission() // 向用戶請求允許發送通知
        #endif
    }
    
    #if os(macOS)
    // 預載音效檔案到記憶體
    private func prepareAudio() {
        guard let url = Bundle.main.url(forResource: soundFileName, withExtension: "caf") else {
            print("找不到音效文件: \(soundFileName).caf")
            return
        }

        // NSSound 是 macOS 的聲音播放類別；byReference: false 代表把聲音資料載入記憶體。
        alarmSound = NSSound(contentsOf: url, byReference: false)
        if alarmSound == nil {
            print("音訊初始化失敗: 無法載入 \(soundFileName).caf")
        }
    }
    #endif

    // 建立一個持續運轉的計時器，每 0.2 秒執行一次 syncRemainingTime 函數
    private func setupDisplayTimer() {
        // Timer.publish 建立一個 Combine publisher。
        // autoconnect 代表一有人訂閱就自動開始，不需要手動 connect。
        displayTimer = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            // weak self 避免 Timer 強引用 TimerManager，造成物件永遠無法釋放。
            .sink { [weak self] _ in self?.syncRemainingTime() }
    }

    // 計算「現在」與「目標時間」差了幾秒
    private func syncRemainingTime() {
        // guard 提早退出：只有正在倒數且有目標時間時，才需要更新畫面。
        guard isRunning, let target = targetDate else { return }
        let diff = target.timeIntervalSinceNow // 計算秒數差
        
        if diff > 0 {
            timeRemaining = diff // 更新剩餘時間
        } else if isRunning {
            // diff <= 0 表示已經到達或超過目標時間；此時切到響鈴狀態。
            triggerAlarm() // 歸零，觸發鬧鐘
        }
    }

    // 處理當 App 從後台回到前台時的情況
    private func setupLifecycleObservers() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.handleConfigurationDidChange()
            }
            .store(in: &cancellables)
        
        #if os(iOS)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.handleWillEnterForeground() // 立即重新對時，並在從 Alarm 回來時停止系統鬧鐘
            }
            .store(in: &cancellables)
        #endif
    }
    
    private func handleConfigurationDidChange() {
        let newRunMode = AppConfiguration.runMode
        // UserDefaults.didChangeNotification 有時會在 App 回到前景時觸發，
        // 即使使用者沒有真正改 Debug / Release 模式。
        // 所以先比較模式是否真的不同，避免暫停中的倒數被重設成完整時間。
        guard newRunMode != lastRunMode else { return }
        lastRunMode = newRunMode
        
        // 如果倒數正在跑，臨時改時間會令 targetDate 變得不清楚，所以不改動當前倒數。
        // 當計時器停低時，就即時用新模式的秒數更新畫面，方便測試 Debug / Release 切換。
        guard !isRunning, !isAlarming else { return }
        timeRemaining = Double(currentStep.seconds)
    }
    
    #if os(iOS)
    private func handleWillEnterForeground() {
        if isAlarming || (isRunning && (targetDate?.timeIntervalSinceNow ?? 1) <= 0) {
            stopAlarmKitTimer()
            isRunning = false
            isAlarming = true
            timeRemaining = 0
            targetDate = nil
            triggerHaptic()
        } else {
            handleConfigurationDidChange()
            syncRemainingTime()
        }
    }
    #endif

    // MARK: - 用戶動作處理
    
    // 開始/暫停按鈕的切換
    func toggle() {
        if isRunning { pause() } else { start() }
        triggerHaptic() // 點擊時的手感反饋
    }

    // 開始計時：紀錄未來的結束時間點並預約系統通知
    func start() {
        // 用目前剩餘秒數加上現在時間，得到這輪倒數真正應該結束的時刻。
        targetDate = Date().addingTimeInterval(timeRemaining)
        isRunning = true
        isAlarming = false
        #if os(macOS)
        cancelNotifications()
        #else
        let token = UUID()
        alarmSchedulingToken = token
        // AlarmKit API 是 async，所以放進 Task。
        // expectedToken 讓排程完成時能確認它仍然是最新那次開始操作。
        Task { await scheduleAlarmKitTimer(expectedToken: token) }
        #endif
    }

    // 暫停計時
    func pause() {
        isRunning = false
        // 暫停時清掉 targetDate；下次 start 會用目前 timeRemaining 重新建立新的結束時間。
        targetDate = nil
        cancelScheduledAlarm() // 暫停時取消預約的提醒
    }

    // 重置到最初狀態
    func reset() {
        pause()
        isAlarming = false
        stopAlarmSound()
        currentStep = .work1
        timeRemaining = Double(currentStep.seconds)
        triggerHaptic()
    }

    // 觸發鬧鈴
    func triggerAlarm() {
        // 防止重複觸發：Timer 會定期跑一次，如果不擋住，可能會連續呼叫多次。
        guard !isAlarming else { return }
        isRunning = false
        isAlarming = true
        timeRemaining = 0
        targetDate = nil
        
        // macOS 不論 App 是否在前景，都明確送出通知；自訂聲音由 App 內播放。
        #if os(macOS)
        playAlarmSound()
        deliverAlarmNotificationImmediately()
        #else
        // iOS 的聲音交給 AlarmKit，App 內不再另外播放 alarm.caf，避免聲音重疊。
        debugLog("iOS 提醒已由 AlarmKit 處理")
        #endif
        triggerHaptic()  // 讓機器震動
    }

    // 前往下一階段
    func nextStep() {
        // 先記住目前是不是最後一關，因為下面會立刻改 currentStep。
        let isLastStep = currentStep == .longRest
        isAlarming = false
        stopScheduledAlarm()
        stopAlarmSound()
        
        let allSteps = TimerStep.allCases
        // rawValue + 1 代表往下一階段；% allSteps.count 讓最後一階段之後回到第一階段。
        let nextIndex = (currentStep.rawValue + 1) % allSteps.count
        currentStep = allSteps[nextIndex]
        timeRemaining = Double(currentStep.seconds)
        
        if !isLastStep {
            start() // 自動開始下一個循環
        } else {
            pause() // 到最後一個休息就停止
        }
        triggerHaptic()
    }

    // 播放提醒聲
    private func playAlarmSound() {
        #if os(macOS)
        alarmSound?.stop()
        alarmSound?.volume = 1
        alarmSound?.play()
        #endif
    }
    
    private func stopAlarmSound() {
        #if os(macOS)
        alarmSound?.stop()
        #endif
    }

    // MARK: - 通知系統
    
    private func cancelScheduledAlarm() {
        #if os(iOS)
        alarmSchedulingToken = UUID()
        if isAlarming {
            stopAlarmKitTimer()
        } else {
            cancelAlarmKitTimer()
        }
        #else
        cancelNotifications()
        #endif
    }
    
    private func stopScheduledAlarm() {
        #if os(iOS)
        stopAlarmKitTimer()
        #else
        cancelNotifications()
        #endif
    }
    
    #if os(iOS)
    private func requestAlarmKitPermissionIfNeeded() async {
        switch alarmManager.authorizationState {
        case .notDetermined:
            do {
                let state = try await alarmManager.requestAuthorization()
                debugLog("AlarmKit 權限請求結果: \(state)")
            } catch {
                print("AlarmKit 權限請求失敗: \(error)")
            }
        case .authorized:
            debugLog("AlarmKit 已授權")
        case .denied:
            print("AlarmKit 權限被拒絕，無法排程系統鬧鐘")
        @unknown default:
            print("未知的 AlarmKit 權限狀態")
        }
    }
    
    private func scheduleAlarmKitTimer(expectedToken: UUID) async {
        // 如果沒有權限，直接停止倒數，避免畫面顯示正在跑但系統其實不會提醒。
        guard await isAlarmKitAuthorized() else {
            await MainActor.run {
                isRunning = false
                targetDate = nil
            }
            return
        }
        
        // 再次確認 token 和狀態，避免「舊的非同步排程」在使用者暫停後仍成功建立鬧鐘。
        guard expectedToken == alarmSchedulingToken, isRunning else { return }
        cancelAlarmKitTimer()
        
        let id = Alarm.ID()
        // 至少 1 秒後才觸發，避免系統不接受 0 秒或負數排程。
        let fireDate = Date().addingTimeInterval(max(1, timeRemaining))
        let alert = AlarmPresentation.Alert(title: "時間到！")
        // attributes 定義系統鬧鐘畫面上要呈現的文字、顏色與自訂資料。
        let attributes = AlarmAttributes<EyeCareAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: EyeCareAlarmMetadata(stepName: currentStep.name),
            tintColor: currentStep.themeColor
        )
        
        do {
            _ = try await alarmManager.schedule(
                id: id,
                configuration: .alarm(
                    schedule: .fixed(fireDate),
                    attributes: attributes,
                    stopIntent: StopEyeCareAlarmIntent(alarmID: id),
                    sound: AppConfiguration.alarmKitSound
                )
            )
            await MainActor.run {
                scheduledAlarmID = id
                debugLog("AlarmKit timer 已排程: \(id)")
            }
        } catch {
            await MainActor.run {
                isRunning = false
                targetDate = nil
            }
            print("AlarmKit timer 排程失敗: \(error)")
        }
    }
    
    private func isAlarmKitAuthorized() async -> Bool {
        switch alarmManager.authorizationState {
        case .authorized:
            return true
        case .notDetermined:
            do {
                return try await alarmManager.requestAuthorization() == .authorized
            } catch {
                print("AlarmKit 權限請求失敗: \(error)")
                return false
            }
        case .denied:
            print("AlarmKit 權限被拒絕，無法排程系統鬧鐘")
            return false
        @unknown default:
            return false
        }
    }
    
    private func cancelAlarmKitTimer() {
        guard let id = scheduledAlarmID else { return }
        do {
            try alarmManager.cancel(id: id)
            scheduledAlarmID = nil
        } catch {
            print("AlarmKit timer 取消失敗: \(error)")
        }
    }
    
    private func stopAlarmKitTimer() {
        guard let id = scheduledAlarmID else { return }
        do {
            try alarmManager.stop(id: id)
            scheduledAlarmID = nil
        } catch {
            cancelAlarmKitTimer()
            print("AlarmKit timer 停止失敗，已改用取消: \(error)")
        }
    }
    
    private func observeAlarmKitUpdates() {
        alarmUpdatesTask?.cancel()
        alarmUpdatesTask = Task { [weak self] in
            guard let self else { return }
            // alarmUpdates 是 AsyncSequence；只要系統鬧鐘狀態改變，這個 for-await 就會收到新資料。
            for await alarms in AlarmManager.shared.alarmUpdates {
                await MainActor.run {
                    // UI 狀態必須在主執行緒更新，所以包在 MainActor.run。
                    guard let id = self.scheduledAlarmID else { return }
                    guard let alarm = alarms.first(where: { $0.id == id }) else {
                        // 找不到原本的鬧鐘，代表它可能已被系統或使用者取消。
                        self.scheduledAlarmID = nil
                        return
                    }
                    
                    if alarm.state == .alerting {
                        // AlarmKit 告訴我們系統鬧鐘正在響，App 內也同步切成「響鈴」狀態。
                        self.triggerAlarm()
                    }
                }
            }
        }
    }
    #endif
    
    // 當 macOS App 在背景仍然活著並自行倒數到零時，補發一則立即通知
    private func deliverAlarmNotificationImmediately() {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationPresenter.shared
        center.removePendingNotificationRequests(withIdentifiers: [scheduledNotificationIdentifier])
        logNotificationSettings(context: "立即送出通知前")
        let identifier = "\(deliveredNotificationIdentifierPrefix).\(UUID().uuidString)"
        
        #if os(macOS)
        let trigger: UNNotificationTrigger? = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        #else
        let trigger: UNNotificationTrigger? = nil
        #endif
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: makeAlarmNotificationContent(),
            trigger: trigger
        )
        let requestIdentifier = request.identifier
        
        center.add(request) { error in
            if let error {
                print("立即通知發送失敗: \(error)")
            } else {
                #if os(macOS)
                self.debugLog("macOS 原生通知已排程: \(requestIdentifier)")
                #else
                self.debugLog("立即通知已加入: \(requestIdentifier)")
                #endif
            }
        }
    }
    private func makeAlarmNotificationContent() -> UNMutableNotificationContent {
        // UNMutableNotificationContent 是系統通知的內容物件。
        // title/body/sound 都在這裡設定，再交給 UNNotificationRequest 排程或立即送出。
        let content = UNMutableNotificationContent()
        content.title = "時間到！"
        content.body = "「\(currentStep.name)」已完成，請開始下一階段。"
        if #available(iOS 15.0, macOS 12.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        
        #if os(macOS)
        // macOS 的提示音由 App 內播放，通知本身保持安靜，避免雙重聲音。
        content.sound = nil
        #else
        if let soundURL = Bundle.main.url(forResource: soundFileName, withExtension: "caf") {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: soundURL.lastPathComponent))
        } else {
            content.sound = .default
        }
        #endif
        
        return content
    }
    
    private func logNotificationSettings(context: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            // getNotificationSettings 是非同步回呼；這裡只做除錯輸出，不影響主流程。
            let baseMessage = "\(context) - authorization: \(settings.authorizationStatus.rawValue), alerts: \(settings.alertSetting.rawValue), sounds: \(settings.soundSetting.rawValue), notificationCenter: \(settings.notificationCenterSetting.rawValue)"
            
            #if os(macOS)
            if #available(iOS 15.0, macOS 12.0, *) {
                self.debugLog("\(baseMessage), alertStyle: \(settings.alertStyle.rawValue), timeSensitive: \(settings.timeSensitiveSetting.rawValue)")
            } else {
                self.debugLog("\(baseMessage), alertStyle: \(settings.alertStyle.rawValue)")
            }
            #else
            self.debugLog(baseMessage)
            #endif
        }
    }

    // 清除所有排隊中或已顯示的通知
    private func cancelNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [scheduledNotificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [scheduledNotificationIdentifier])
        center.getDeliveredNotifications { [deliveredNotificationIdentifierPrefix] notifications in
            let ids = notifications
                .map(\.request.identifier)
                .filter { $0.hasPrefix(deliveredNotificationIdentifierPrefix) }
            
            if !ids.isEmpty {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
    }

    // 根據裝置發出不同的物理震動反饋
    private func triggerHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }

    // 詢問用戶是否給予發送通知的權限
    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                self.debugLog("通知權限狀態: \(Self.authorizationStatusDescription(settings.authorizationStatus))")
                return
            }
            
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    print("通知權限請求失敗: \(error)")
                } else {
                    self.debugLog("通知權限請求結果: \(granted)")
                }
            }
        }
    }
    
    nonisolated private func debugLog(_ message: String) {
        // 統一由這個開關控制除錯訊息，正式使用時可以保持 Console 乾淨。
        guard Self.isVerboseLoggingEnabled else { return }
        print(message)
    }
    
    nonisolated private static func authorizationStatusDescription(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined (0)"
        case .denied: return "denied (1)"
        case .authorized: return "authorized (2)"
        case .provisional: return "provisional (3)"
        case .ephemeral: return "ephemeral (4)"
        @unknown default: return "unknown (\(status.rawValue))"
        }
    }
}
