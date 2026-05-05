import SwiftUI           // 負責：建立 App 的畫面（按鈕、圓圈、文字等 UI 元素）
import UserNotifications // 負責：發送系統通知（當倒計時結束時，手機頂部彈出的提醒）
import Combine           // 負責：資料流處理（讓「計時器大腦」與「畫面」之間的數據同步）
import AVFoundation      // 負責：播放音效（控制鬧鐘鈴聲的播放與暫停）

// 根據不同的作業系統，引入專屬的系統工具箱
#if os(iOS)
import UIKit             // 負責：iOS 系統的底層工具（如螢幕震動、系統背景管理）
#elseif os(macOS)
import AppKit            // 負責：macOS 系統的底層工具（如電腦視窗管理、觸控板反饋）
#endif

// MARK: - 1. 護眼階段配置 (定義四個階段的屬性)
enum TimerStep: Int, CaseIterable {
    // 定義四個階段：工作1、護眼、工作2、長休息
    case work1 = 0, eyeCare = 1, work2 = 2, longRest = 3
    
    // 每個階段在介面上顯示的中文名稱
    var name: String {
        switch self {
        case .work1: return "第一階段：專專注工作"
        case .eyeCare: return "第二階段：遠眺放鬆"
        case .work2: return "第三階段：專注工作"
        case .longRest: return "第四階段：深度休息"
        }
    }
    
    // 每個階段的持續時間（秒）
    var seconds: Int {
        #if DEBUG
        // 開發測試模式：縮短時間以便快速看到結果
        switch self {
        case .work1, .work2: return 10
        case .eyeCare: return 5
        case .longRest: return 8
        }
        #else
        // 正式模式：標準 20-20-20 護眼法則的時間
        switch self {
        case .work1, .work2: return 20 * 60 // 20 分鐘
        case .eyeCare: return 20            // 20 秒
        case .longRest: return 3 * 60       // 3 分鐘
        }
        #endif
    }
    
    // 每個階段顯示的圖示名稱
    var icon: String {
        switch self {
        case .work1, .work2: return "laptopcomputer"
        case .eyeCare: return "eye.fill"
        case .longRest: return "cup.and.saucer.fill"
        }
    }
    
    // 每個階段的主題顏色
    var themeColor: Color {
        switch self {
        case .eyeCare: return .green
        case .longRest: return .orange
        default: return .blue
        }
    }
}

// MARK: - 2. 核心大腦 (處理計時邏輯、音效與通知)
class TimerManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    
    // 被標註為 @Published 的變數，一旦改變，畫面就會跟著重新繪製
    @Published var currentStep: TimerStep = .work1      // 當前階段
    @Published var timeRemaining: Double = Double(TimerStep.work1.seconds) // 剩餘秒數
    @Published var isRunning = false                    // 是否正在跑
    @Published var isAlarming = false                   // 是否正在響鈴
    
    private var targetDate: Date?                       // 預計結束的時間點
    private var displayTimer: AnyCancellable?           // 控制畫面跳動的定時器
    private var cancellables = Set<AnyCancellable>()    // 系統清理記憶體用
    
    // 音訊播放器物件
    private var audioPlayer: AVAudioPlayer?
    private let soundFileName = "alarm"                 // 預備播放的檔案名稱
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self // 讓這個類別處理通知彈窗
        setupDisplayTimer()       // 啟動 0.05 秒一次的畫面更新機制
        setupLifecycleObservers() // 監聽 App 進入背景或回到前台
        prepareAudio()            // 預先載入鈴聲檔案
    }
    
    // App 開啟時的初始化設置
    func setupOnLaunch() {
        requestNotificationPermission() // 向用戶請求允許發送通知
        #if os(iOS)
        configureAudioSession()         // 設定 iOS 的聲音播放模式
        #endif
    }
    
    // 預載音效檔案到記憶體
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
    // 專為 iOS 設置：讓聲音在靜音模式下也能播放，或壓低背景音樂
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        } catch {
            print("Audio Session 配置失敗: \(error)")
        }
    }
    #endif

    // 建立一個持續運轉的計時器，每 0.05 秒執行一次 syncRemainingTime 函數
    private func setupDisplayTimer() {
        displayTimer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.syncRemainingTime() }
    }

    // 計算「現在」與「目標時間」差了幾秒
    private func syncRemainingTime() {
        guard isRunning, let target = targetDate else { return }
        let diff = target.timeIntervalSinceNow // 計算秒數差
        
        if diff > 0 {
            self.timeRemaining = diff // 更新剩餘時間
        } else {
            triggerAlarm()            // 歸零，觸發鬧鐘
        }
    }

    // 處理當 App 從後台回到前台時的情況
    private func setupLifecycleObservers() {
        #if os(iOS)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.syncRemainingTime() // 立即重新對時，防止計時跑偏
            }
            .store(in: &cancellables)
        #endif
    }

    // MARK: - 用戶動作處理
    
    // 開始/暫停按鈕的切換
    func toggle() {
        if isRunning { pause() } else { start() }
        triggerHaptic() // 點擊時的手感反饋
    }

    // 開始計時：紀錄未來的結束時間點並預約系統通知
    func start() {
        targetDate = Date().addingTimeInterval(timeRemaining)
        isRunning = true
        isAlarming = false
        scheduleLocalNotification()
    }

    // 暫停計時
    func pause() {
        isRunning = false
        targetDate = nil
        cancelNotifications() // 暫停時取消預約的通知
    }

    // 重置到最初狀態
    func reset() {
        pause()
        isAlarming = false
        audioPlayer?.stop()
        currentStep = .work1
        timeRemaining = Double(currentStep.seconds)
        triggerHaptic()
    }

    // 觸發鬧鈴
    func triggerAlarm() {
        guard !isAlarming else { return }
        isRunning = false
        isAlarming = true
        timeRemaining = 0
        targetDate = nil
        
        playAlarmSound() // 播放音效
        triggerHaptic()  // 讓機器震動
    }

    // 前往下一階段
    func nextStep() {
        let isLastStep = currentStep == .longRest
        isAlarming = false
        audioPlayer?.stop()
        
        let allSteps = TimerStep.allCases
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
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        audioPlayer?.currentTime = 0
        audioPlayer?.play()
    }

    // MARK: - 通知系統
    
    // 預約一則在未來的通知（當倒計時歸零時由系統顯示）
    private func scheduleLocalNotification() {
        cancelNotifications()
        let content = UNMutableNotificationContent()
        content.title = "時間到！"
        content.body = "「\(currentStep.name)」已完成，請開始下一階段。"
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(soundFileName).caf"))
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.1, timeRemaining), repeats: false)
        let request = UNNotificationRequest(identifier: "202020Notification", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }

    // 清除所有排隊中或已顯示的通知
    private func cancelNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    
    // 設定當 App 開啟時，通知彈窗也能在螢幕頂部顯示
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}

// MARK: - 3. 介面外觀區 (使用 SwiftUI 繪製)
struct ContentView: View {
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
        #endif
        .onAppear { manager.setupOnLaunch() } // 畫面加載完成後進行權限請求
    }
}

extension ContentView {
    
    // 標題顯示組件
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
    
    // 中間的進度圓圈組件
    private var progressCircle: some View {
        ZStack {
            // 背景灰圈
            Circle()
                .stroke(Color.gray.opacity(0.1), lineWidth: 15)
            
            // 彩色進度圈
            Circle()
                .trim(from: 0, to: manager.timeRemaining / Double(manager.currentStep.seconds))
                .stroke(
                    manager.isAlarming ? Color.red : manager.currentStep.themeColor,
                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                )
                .rotationEffect(.degrees(-90)) // 起點修正到正上方
                .animation(.linear(duration: 0.05), value: manager.timeRemaining)
            
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
        if manager.isAlarming { return "checkmark" }
        return manager.isRunning ? "pause.fill" : "play.fill"
    }
    
    // 控制按鈕顏色變換
    private var mainButtonColor: Color {
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
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - 4. App 入口 (整個程式的出發點)
@main
struct EyeCareTimerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView() // 啟動畫面
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar) // Mac 版隱藏頂部標題列
        #endif
    }
}
