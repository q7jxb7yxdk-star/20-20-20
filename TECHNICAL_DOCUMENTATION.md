# 20-20-20 護眼助理技術文件

這份文件用來解釋 `20-20-20` App 的功能、架構，以及主要 Swift 代碼的職責。目標不是只記低「程式做了甚麼」，而是幫你理解每一個檔案為甚麼要這樣拆、每段核心代碼在整個 App 入面扮演甚麼角色。

## 1. App 功能介紹

`20-20-20 護眼助理` 是一個用 SwiftUI 寫成的倒數提醒 App，目的是幫使用者按 20-20-20 護眼法則定時休息眼睛。

### 1.1 主要功能

- 顯示目前倒數階段，例如「專注工作」、「遠眺放鬆」、「深度休息」。
- 用圓形進度圈顯示剩餘時間。
- 支援開始、暫停、重置。
- 倒數完成後進入響鈴狀態。
- 使用者確認後自動進入下一階段。
- 在 macOS 上播放 App 內的 `alarm.caf` 提醒聲。
- 在 macOS 上發送本地通知。
- 在 iOS 上使用 AlarmKit 排程系統鬧鐘。
- 在 iOS / macOS 上提供震動或觸感回饋。

### 1.2 四個倒數階段

App 目前有四個階段，由 `TimerStep` 定義：

| 階段 | 名稱 | 用途 | 時間 | 
| --- | --- | --- | --- |
| `work1` | 第一階段：專注工作 | 第一段工作時間 | 20 分鐘 |
| `eyeCare` | 第二階段：遠眺放鬆 | 護眼休息 | 20 秒 |
| `work2` | 第三階段：專注工作 | 第二段工作時間 | 20 分鐘 |
| `longRest` | 第四階段：深度休息 | 較長休息 | 3 分鐘 |

在 `DEBUG` 模式下，時間會被縮短，方便開發時快速測試倒數完成、通知、響鈴等流程。正式版則會使用較接近真實使用情境的時間設定。

## 2. 專案檔案分工

目前主要 Swift 檔案已經拆成以下幾個部分：

| 檔案 | 責任 |
| --- | --- |
| `EyeCareTimerApp.swift` | App 入口，建立第一個畫面，設定通知 delegate |
| `ContentView.swift` | SwiftUI 畫面、按鈕、圓圈、狀態文字、macOS 視窗大小 |
| `TimerStep.swift` | 倒數階段資料、App 共用設定 |
| `SettingsView.swift` | macOS App 內設定畫面 |
| `TimerManager.swift` | 倒數核心邏輯、開始/暫停/重置/下一階段、通知、音效、觸感 |
| `NotificationPresenter.swift` | App 在前台時如何顯示通知 |
| `AlarmKitSupport.swift` | iOS AlarmKit 所需 metadata 和停止鬧鐘 intent |
| `Settings.bundle/Root.plist` | iOS 系統設定 App 內顯示的 App 設定 |
| `20-20-20_AppleWatch Watch App/` | Apple Watch 版本 MVP 代碼 |

這樣拆的好處是：畫面、資料、業務邏輯、系統通知、iOS AlarmKit 不會全部塞在同一個檔案。當 App 變大時，這種分工會令閱讀和維護容易好多。

## 3. App 啟動流程

App 的起點在 `EyeCareTimerApp.swift`：

```swift
@main
struct EyeCareTimerApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

重點：

- `@main` 表示這個 struct 是整個 App 的入口。
- `WindowGroup` 建立 App 的第一個視窗。
- `ContentView()` 是第一個顯示出來的 SwiftUI 畫面。
- `UNUserNotificationCenter.current().delegate = NotificationPresenter.shared` 用來指定通知代理，讓 App 在前台時都可以決定如何呈現通知。

在 macOS 上，App 亦設定了：

```swift
.windowStyle(.hiddenTitleBar)
```

這會令 macOS 視窗隱藏標題列，介面看起來更簡潔。

## 4. 畫面層：ContentView.swift

`ContentView` 負責畫面，不負責實際倒數邏輯。它透過 `TimerManager` 取得狀態，然後把狀態變成 UI。

```swift
@StateObject private var manager = TimerManager()
```

`@StateObject` 的意思是：這個 View 會持有 `TimerManager` 的生命週期。畫面重繪時，SwiftUI 不會隨便重新建立 manager，所以倒數狀態不會突然遺失。

### 4.1 畫面主要結構

`body` 入面主要是：

- `ZStack`：疊放背景和內容。
- `VStack`：由上至下排列標題、圓圈、按鈕、進度點。
- `statusHeader`：目前階段文字。
- `progressCircle`：圓形倒數。
- `actionControls`：開始/暫停/確認、重置按鈕。
- `stepDots`：顯示目前進度階段的小圓點。

### 4.2 SwiftUI 的核心想法

這個 App 很多 UI 都是由狀態推導出來：

```swift
if manager.isAlarming { return "checkmark" }
return manager.isRunning ? "pause.fill" : "play.fill"
```

意思是：

- 如果正在響鈴，主按鈕變成確認圖示。
- 如果正在倒數，主按鈕變成暫停圖示。
- 如果未開始，主按鈕變成播放圖示。

這是 SwiftUI 常見寫法：不要手動控制畫面每一個細節，而是先保持資料狀態正確，畫面自然跟著狀態更新。

### 4.3 圓形進度圈

進度圈使用 `Circle().trim(from:to:)`：

```swift
.trim(from: 0, to: manager.timeRemaining / Double(manager.currentStep.seconds))
```

這行會計算剩餘時間比例。例如還有一半時間，彩色圓圈就只畫一半。`rotationEffect(.degrees(-90))` 則把圓圈起點轉到正上方，視覺上會比較像一般倒數器。

### 4.4 macOS 視窗大小

`WindowInitialSizeConfigurator` 是 SwiftUI 和 AppKit 的橋接器。SwiftUI 本身不太方便直接設定 macOS 視窗初始大小，所以用一個隱形 `NSView` 取得 `window`，然後設定：

```swift
window.minSize = size
window.setContentSize(size)
```

這部分只會在 macOS 編譯，因為它被包在：

```swift
#if os(macOS)
...
#endif
```

## 5. 資料層：TimerStep.swift

`TimerStep` 定義倒數有哪些階段，以及每個階段在畫面上應該顯示甚麼。

```swift
enum TimerStep: Int, CaseIterable {
    case work1 = 0, eyeCare = 1, work2 = 2, longRest = 3
}
```

### 5.1 為甚麼用 enum

這裡用 `enum` 很適合，因為倒數階段是固定選項，不是任意字串。用 enum 有幾個好處：

- 不容易打錯階段名稱。
- 可以用 `switch` 清楚列出每個階段的行為。
- `CaseIterable` 令我們可以用 `TimerStep.allCases` 取得全部階段。

### 5.2 每個階段的資料

每個階段都有：

- `name`：顯示名稱。
- `seconds`：倒數秒數。
- `icon`：SF Symbols 圖示名稱。
- `themeColor`：主題顏色。

例如：

```swift
var icon: String {
    switch self {
    case .work1, .work2: return "laptopcomputer"
    case .eyeCare: return "eye.fill"
    case .longRest: return "cup.and.saucer.fill"
    }
}
```

這種寫法的好處是：UI 不需要知道每個階段應該用甚麼 icon，只要問 `manager.currentStep.icon` 就可以。

### 5.3 AppConfiguration

`AppConfiguration` 集中放 App 共用設定：

```swift
static var duration: DurationConfiguration {
    switch runMode {
    case .debug:
        return (work: 10, eyeCare: 5, longRest: 8)
    case .release:
        return (work: 20 * 60, eyeCare: 20, longRest: 3 * 60)
    }
}
```

`Debug 測試模式` 時間短，`Release 正式模式` 時間長。這樣不用重新編譯 App，都可以即時切換測試時間和正式時間。

目前模式不是再靠 `#if DEBUG` 編譯旗標決定，而是讀取 `UserDefaults`：

```swift
static var runMode: RunMode {
    let rawValue = UserDefaults.standard.string(forKey: DefaultsKey.runMode)
    return RunMode(rawValue: rawValue ?? "") ?? .release
}
```

好處是同一個安裝好的 App，可以隨時在設定入面切換模式。

### 5.4 Debug / Release 模式設定

App 使用同一個 UserDefaults key：

```swift
app_run_mode
```

macOS 版本由 `SettingsView.swift` 提供 App 內設定畫面。使用者可以在 App 選單打開 Settings，然後選擇：

- `Debug 測試模式`
- `Release 正式模式`

iOS 版本由 `Settings.bundle/Root.plist` 提供系統設定畫面。安裝 App 後，可以去：

```text
iPhone 設定 > 20-20-20 > 模式
```

選擇 Debug 或 Release。因為 iOS Settings.bundle 也是寫入同一個 `app_run_mode`，所以 App 重新回到前台或下一次讀設定時，就會用新模式。

`TimerManager` 亦監聽 `UserDefaults.didChangeNotification`。如果計時器目前停低，切換模式後會即時更新畫面上的剩餘時間；如果倒數正在跑，App 不會臨時改動當前倒數，避免 targetDate 被中途改亂。

## 6. 核心邏輯：TimerManager.swift

`TimerManager` 是整個 App 的核心大腦。它負責：

- 保存目前階段。
- 保存剩餘時間。
- 開始、暫停、重置。
- 倒數完觸發提醒。
- 切換到下一階段。
- 發送通知。
- 播放 macOS 音效。
- 處理 iOS AlarmKit。

### 6.1 為甚麼加 @MainActor

```swift
@MainActor
class TimerManager: NSObject, ObservableObject
```

因為 `TimerManager` 入面有多個 `@Published` 狀態：

```swift
@Published var currentStep: TimerStep
@Published var timeRemaining: Double
@Published var isRunning: Bool
@Published var isAlarming: Bool
```

這些狀態會直接影響 SwiftUI 畫面。SwiftUI UI 狀態最好在主執行緒更新，所以將整個 `TimerManager` 標成 `@MainActor` 可以減少 concurrency warning，也避免背景 callback 不小心直接改 UI 狀態。

### 6.2 使用 targetDate 而不是單純每秒扣一

這個 App 不是每次 timer tick 就 `timeRemaining -= 1`，而是保存一個目標完成時間：

```swift
private var targetDate: Date?
```

開始時：

```swift
targetDate = Date().addingTimeInterval(timeRemaining)
```

同步時間時：

```swift
let diff = target.timeIntervalSinceNow
```

這樣做比較準確。即使 App 一瞬間卡住、系統暫停 timer、或者使用者切到背景再回來，App 都可以用「現在時間」和「目標時間」重新計算真正剩餘秒數。

### 6.3 畫面更新 Timer

```swift
displayTimer = Timer.publish(every: 0.2, on: .main, in: .common)
    .autoconnect()
    .sink { [weak self] _ in self?.syncRemainingTime() }
```

這個 timer 每 0.2 秒更新一次畫面。畫面雖然只顯示秒數，但圓形進度圈會比較順滑，所以用 0.2 秒是一個平衡：比 0.05 秒省資源，又比 1 秒更順眼。

`[weak self]` 是為了避免 timer 強引用 `TimerManager`，造成記憶體無法釋放。

### 6.4 開始、暫停、重置

`start()`：

- 計算 `targetDate`。
- 將 `isRunning` 設為 `true`。
- 將 `isAlarming` 設為 `false`。
- iOS 排程 AlarmKit。
- macOS 清走舊通知。

`pause()`：

- 停止倒數。
- 清除 `targetDate`。
- 取消尚未響的提醒。

`reset()`：

- 先暫停。
- 停止響鈴聲。
- 回到第一階段。
- 重設剩餘時間。

### 6.5 觸發響鈴

倒數到 0 時會呼叫：

```swift
triggerAlarm()
```

它會：

- 防止重複觸發。
- 停止倒數。
- 將 `isAlarming` 設為 `true`。
- 將剩餘時間設為 0。
- macOS 播放 `alarm.caf`。
- macOS 立即送出通知。
- iOS 交由 AlarmKit 處理聲音。
- 觸發震動或觸感回饋。

### 6.6 下一階段

```swift
let nextIndex = (currentStep.rawValue + 1) % allSteps.count
currentStep = allSteps[nextIndex]
```

這行用 `%` 取餘數，令最後一個階段之後可以回到第一個階段。

目前邏輯是：

- 如果不是最後階段，確認後自動開始下一階段。
- 如果已經完成 `longRest`，就停止。

### 6.7 macOS 音效

macOS 使用 `NSSound` 播放專案內的 `alarm.caf`：

```swift
alarmSound = NSSound(contentsOf: url, byReference: false)
```

iOS 版本不再使用 `AVAudioPlayer`。iOS 的聲音交給 AlarmKit，避免 App 內聲音和系統鬧鐘聲重疊。

### 6.8 通知權限

macOS 會使用：

```swift
requestNotificationPermission()
```

向使用者請求通知權限。若權限未決定，就會呼叫：

```swift
requestAuthorization(options: [.alert, .sound, .badge])
```

App 亦有 `logNotificationSettings(context:)` 幫助除錯通知設定，但正式使用時 `isVerboseLoggingEnabled` 預設是 `false`，所以不會一直印 console。

## 7. 通知呈現：NotificationPresenter.swift

`NotificationPresenter` 是 `UNUserNotificationCenterDelegate`。

它的主要任務是：當 App 正在前台時，如果通知到達，要不要仍然彈出通知。

```swift
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate
```

它用 singleton：

```swift
static let shared = NotificationPresenter()
```

原因是 `UNUserNotificationCenter.current().delegate` 不會幫你強力保存 delegate。若 delegate 物件太快被釋放，通知 callback 可能收不到。用 `static shared` 可以確保它常駐。

### 7.1 前台通知

核心方法：

```swift
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
)
```

macOS 使用 raw value 設定通知顯示選項。iOS 則使用 `.banner` 和 `.list`，而聲音交由 AlarmKit 處理。

## 8. iOS AlarmKit：AlarmKitSupport.swift

這個檔案只在 iOS 編譯：

```swift
#if os(iOS)
...
#endif
```

### 8.1 EyeCareAlarmMetadata

```swift
nonisolated struct EyeCareAlarmMetadata: AlarmMetadata {
    let stepName: String
}
```

AlarmKit 需要 metadata 來保存鬧鐘相關資料。這裡保存 `stepName`，即是哪一個階段觸發提醒。

### 8.2 StopEyeCareAlarmIntent

```swift
struct StopEyeCareAlarmIntent: LiveActivityIntent
```

這個 intent 是給系統鬧鐘畫面上的按鈕使用。使用者即使不打開 App，也可以在系統介面按停止。

`perform()` 會嘗試：

```swift
try? AlarmManager.shared.stop(id: id)
try? AlarmManager.shared.cancel(id: id)
```

`stop` 用於停止正在響的鬧鐘，`cancel` 用於取消未響的鬧鐘。兩個都嘗試，可以令按鈕在不同狀態下都盡量生效。

## 9. 平台差異設計

這個 App 同時支援 iOS 和 macOS，所以有很多條件編譯：

```swift
#if os(iOS)
...
#elseif os(macOS)
...
#endif
```

主要差異：

| 功能 | iOS | macOS |
| --- | --- | --- |
| 畫面框架 | SwiftUI + UIKit 輔助 | SwiftUI + AppKit 輔助 |
| 提醒聲 | AlarmKit 處理 | App 內 NSSound 播放 |
| 通知 | AlarmKit 為主 | UserNotifications 本地通知 |
| 觸感 | UIImpactFeedbackGenerator | NSHapticFeedbackManager |
| 視窗大小 | 不需要手動設定 | 使用 NSViewRepresentable 設定 |

這樣寫可以共用大部分 SwiftUI 畫面和倒數邏輯，同時保留每個平台需要的原生能力。

### 9.1 Apple Watch 版本

Apple Watch 版本目前以獨立 MVP 方式設計，代碼放在：

```text
20-20-20_AppleWatch Watch App/
```

主要檔案：

| 檔案 | 責任 |
| --- | --- |
| `_0_20_20_AppleWatchApp.swift` | Watch App 入口 |
| `WatchContentView.swift` | Watch 主畫面 |
| `WatchTimerManager.swift` | Watch 倒數核心邏輯 |
| `WatchTimerStep.swift` | Watch 階段資料和測試時間 |
| `WatchNotificationPresenter.swift` | Watch 前台通知 delegate |
| `20-20-20-Watch-Info.plist` | Watch App 的 Info.plist，包含背景 alarm mode |

Watch MVP 的功能：

- 顯示目前階段。
- 顯示圓形倒數。
- 支援開始、暫停、重置。
- 倒數完成後顯示「第 X 階段完成」提示。
- 使用 Apple Watch haptic 提醒。
- 使用 `WKExtendedRuntimeSession` 的 smart alarm 機制，支援背景提醒。
- 點擊確認後進入下一階段。

目前 Watch 版本先不和 iPhone App 同步設定，原因是初版應先確認 Watch 上的倒數體驗和 UI 是否穩定。之後如要同步，可以加入 `WatchConnectivity`，由 iPhone 傳送目前模式、倒數時間或階段狀態到 Watch。

#### 9.1.1 Watch 背景提醒：Smart Alarm

Apple Watch 版本不能只靠 Swift timer 處理背景提醒。當 Watch App 退到背景後，`Timer.publish` 可能會暫停或延遲，所以背景倒數完成時未必能準時執行普通 Swift 代碼。

目前 Watch 版本使用：

```swift
WKExtendedRuntimeSession
```

並在 Watch App 的 Info.plist 加入：

```xml
<key>WKBackgroundModes</key>
<array>
    <string>alarm</string>
</array>
```

這個設定放在：

```text
20-20-20-Watch-Info.plist
```

不要把 Watch `Info.plist` 放在 `20-20-20_AppleWatch Watch App/` 資料夾內，因為目前 project 使用 Xcode 的 folder-synced target，資料夾內檔案可能會自動加入 Resources，導致 `Info.plist` 被複製兩次，出現 duplicate output error。

倒數開始時，`WatchTimerManager` 會建立 smart alarm session：

```swift
let session = WKExtendedRuntimeSession()
session.delegate = self
session.start(at: finishDate)
```

當 watchOS 到時間啟動 session 時，delegate 會呼叫：

```swift
extendedRuntimeSessionDidStart(_:)
```

之後 App 會執行：

```swift
session.notifyUser(hapticType: .notification) { nextHapticType in
    nextHapticType.pointee = .notification
    return 2
}
```

這樣背景時就由 watchOS 的 smart alarm alert / haptic 負責提醒，而不是靠本地通知倒數。

#### 9.1.2 為甚麼不用預先排程本地通知

曾經測試過 `UNTimeIntervalNotificationTrigger`，背景提醒可靠，但會造成兩套倒數：

- App 畫面自己的倒數。
- 系統 pending notification 的倒數 / 排程。

這不符合目前設計，所以 Watch 版本改用 smart alarm session。它仍然需要向 watchOS 排一個 smart alarm，但不會在使用者介面上產生另一個普通 notification 倒數。

#### 9.1.3 WatchTimerManager 的生命週期

`WKExtendedRuntimeSession` 需要被強引用保存。如果持有它的物件被釋放，Debug Area 可能會出現：

```text
WKExtendedRuntimeObject was dealloced while scheduled
```

所以目前 `WatchTimerManager` 使用 singleton：

```swift
static let shared = WatchTimerManager()
```

並由 Watch App entry 持有：

```swift
@StateObject private var manager = WatchTimerManager.shared
```

`WatchContentView` 只接收：

```swift
@ObservedObject var manager: WatchTimerManager
```

這樣可以避免畫面退到背景或被 SwiftUI 重建時，smart alarm session 跟著消失。

#### 9.1.4 測試真 Apple Watch

用真 Apple Watch 測試時，建議流程如下：

1. 確認 iPhone 已經和 Apple Watch 配對。
2. 用 USB 將 iPhone 連接 Mac，第一次測試用 USB 最穩。
3. iPhone、Apple Watch、Mac 使用同一 Apple ID 會較少 provisioning 問題。
4. iPhone 開啟 Developer Mode：

```text
iPhone Settings > Privacy & Security > Developer Mode
```

5. Apple Watch 如有 Developer Mode，也要開啟：

```text
Apple Watch Settings > Privacy & Security > Developer Mode
```

6. Xcode 左上角選擇真機 iPhone 或 paired Apple Watch destination。
7. Apple Watch 保持解鎖。
8. 按 Run，等 Xcode 安裝 App 到 iPhone / Watch。
9. 在 Watch 上開始倒數。
10. 按 Digital Crown 回到錶面，測試背景 smart alarm 是否準時提醒。

如果 Xcode 見到 iPhone 但見不到 Apple Watch，可以到：

```text
Xcode > Window > Devices and Simulators
```

確認 iPhone 右邊是否顯示 paired Apple Watch。

要真正編譯 Watch App，需要在 Xcode 加入 watchOS target：

```text
File > New > Target > watchOS > Watch App
```

建立 target 後，再將 `20-20-20_AppleWatch Watch App/` 內的 Swift 檔加入 Watch App target membership。

## 10. 主要流程總結

### 10.1 使用者按開始

1. `ContentView` 的按鈕呼叫 `manager.toggle()`。
2. `toggle()` 判斷目前未開始，所以呼叫 `start()`。
3. `start()` 設定 `targetDate` 和 `isRunning`。
4. iOS 排程 AlarmKit；macOS 清除舊通知。
5. `displayTimer` 每 0.2 秒呼叫 `syncRemainingTime()` 更新畫面。

### 10.2 倒數到零

1. `syncRemainingTime()` 發現 `diff <= 0`。
2. 呼叫 `triggerAlarm()`。
3. `isRunning = false`，`isAlarming = true`。
4. macOS 播放聲音並發通知。
5. iOS 由 AlarmKit 處理系統鬧鐘。
6. 畫面主按鈕變成確認圖示。

### 10.3 使用者確認進入下一階段

1. `ContentView` 發現 `manager.isAlarming == true`。
2. 主按鈕呼叫 `manager.nextStep()`。
3. `nextStep()` 停止提醒，切換到下一個 `TimerStep`。
4. 如果未到最後階段，自動 `start()` 下一段倒數。
5. 如果已完成長休息，App 停止等待使用者再次開始。

## 11. 學習重點

這個專案包含幾個很值得學的 Swift / SwiftUI 概念：

- `@main`：App 入口。
- `App` protocol：SwiftUI App 的基本結構。
- `View`：畫面宣告。
- `@StateObject`：讓 View 持有一個狀態物件。
- `ObservableObject` + `@Published`：資料改變時通知 SwiftUI 重畫畫面。
- `@MainActor`：保證 UI 狀態在主執行緒更新。
- `Combine Timer.publish`：建立定時事件。
- `Date` 和 `timeIntervalSinceNow`：用絕對時間計算倒數。
- `UserNotifications`：本地通知。
- `UNUserNotificationCenterDelegate`：控制前台通知呈現。
- `#if os(iOS)` / `#if os(macOS)`：平台條件編譯。
- `AlarmKit`：iOS 系統鬧鐘整合。
- `NSViewRepresentable`：SwiftUI 和 AppKit 橋接。

## 12. 專案特色與開發筆記

這一節只保留較零散、但開發時常會查閱的筆記。核心功能、平台差異和 Watch 背景提醒已經分別在第 1、5、6、9 章解釋，這裡不再重複。

### 12.1 一般註解：`//`

一般註解用 `//`：

```swift
// 這裡用 targetDate 計算剩餘時間，避免 App 進入背景後時間不準。
```

常見用途：

- 解釋這行程式碼為甚麼要這樣寫。
- 記錄某段邏輯的原因。
- 暫時把不想執行的代碼關掉，也就是「註解掉」。

### 12.2 文件註解：`///`

文件註解用 `///`：

```swift
/// 將秒數轉換成 00:00 格式的時間文字。
/// - Parameter totalSeconds: 總秒數。
/// - Returns: 格式化後的分鐘和秒數。
private func timeString(from totalSeconds: Int) -> String
```

`///` 適合用來描述：

- 一個功能做甚麼。
- 變數代表甚麼。
- 類型的用途。
- 參數是甚麼。
- 回傳值是甚麼。

在 Xcode 中，如果你按住 `Option` 並點擊有 `///` 註解的功能，Xcode 會彈出 Quick Help 視窗，顯示你寫的說明。

### 12.3 Convert MP3 to CAF

如果要將 MP3 轉成 CAF，可以用：

```bash
afconvert -f caff -d ima4 -c 1 input.mp3 alarm.caf
```

參數意思：

- `-f caff`：輸出 CAF 格式。
- `-d ima4`：使用 IMA4 壓縮格式。
- `-c 1`：轉成單聲道。
- `input.mp3`：原始 MP3。
- `alarm.caf`：輸出的 CAF 檔案。

### 12.4 Release Mode

如果想在 Xcode 由 Debug 切到 Release：

```text
Product > Scheme > Edit Scheme
Run > Info > Build Configuration
Debug / Release
```

注意：Xcode 的 Debug / Release build configuration 和 App 內的 `Debug 測試模式` / `Release 正式模式` 是兩件事。

- Xcode Debug / Release：影響編譯優化、符號、發佈方式。
- App 內 Debug / Release：影響倒數時間長短，方便測試。

### 12.5 安裝 App 到 macOS

macOS 可以透過 Archive 封裝 App：

```text
Product > Archive > Distribute App > Custom > Copy App
```

流程意思：

- `Archive`：編譯並封裝 App。
- `Distribute App`：選擇發佈方式。
- `Custom > Copy App`：輸出一個可以複製到其他位置的 `.app`。

### 12.6 安裝 App 到 iPhone

開發測試時，可以使用 Xcode 偵錯模式：

```text
USB 連接 iPhone
Xcode 選擇實體 iPhone
按 Run
```

第一次安裝到實體 iPhone 時，可能需要在 iPhone 上信任開發者帳號。

## 13. Xcode Debug Area 常見訊息

這一節整理開發過程中可能看到的 Xcode Debug Area 訊息。很多都屬於 Apple 系統框架、Simulator 或 sandbox 的 log，不一定代表 App 本身有 bug。

### 13.1 AddInstanceForFactory

```text
AddInstanceForFactory: No factory registered for id <CFUUID ...> F8BB1C28-BAE8-11D6-9C31-00039315CD46
```

CoreAudio / AudioToolbox 在初始化音訊元件時找不到某個 factory。常見於 iOS Simulator，或者使用 `AVFoundation`、`AVAudioSession`、`AVAudioPlayer`、通知聲音、系統音效時。

避免 App 啟動時就初始化音訊，可以改成需要播放聲音時才設定音訊相關物件。目前版本已移除 iOS 的 `AVAudioPlayer` 分支，iOS 聲音交由 AlarmKit 處理。

### 13.2 LoudnessManager plist

```text
LoudnessManager.mm:1755 ReadPListFile: unable to open stream for LoudnessManager plist
```

Apple 的音訊框架想讀取某個響度 / 聲學設定 plist，但目前環境找不到。這在 iOS Simulator、使用 `AVAudioSession`、`AVAudioPlayer` 或通知聲音時很常見。

通常可以忽略。

### 13.3 DetachedSignatures

```text
cannot open file at line 51044 of [f0ca7bba1c]
os_unix.c:51044: (2) open(/private/var/db/DetachedSignatures) - No such file or directory
```

macOS 系統安全 / 簽章機制嘗試讀取 `/private/var/db/DetachedSignatures`，但該檔案不存在。這不是 App 自己開檔失敗，亦與 `ContentView.swift` 無關。

通常可以忽略。

### 13.4 audioanalyticsd sandbox precondition failure

```text
PRECONDITION FAILURE: Process is sandboxed but 'com.apple.security.exception.mach-lookup.global-name' doesn't contain 'com.apple.audioanalyticsd'.
```

macOS App 在 sandbox 裡播放音效時，系統音訊框架嘗試連到 `com.apple.audioanalyticsd`，但 App 的 sandbox entitlements 沒有允許這個 mach service。

早前的處理方式是新增 Debug 專用 entitlements，加入：

```text
com.apple.security.exception.mach-lookup.global-name
com.apple.audioanalyticsd
```

然後在 macOS Debug build 套用這個 entitlements。這類設定通常只適合 Debug 測試，不建議隨便帶到正式發佈版本。

### 13.5 Reporter disconnected

```text
Reporter disconnected. { function=sendMessage, reporterID=107554571026433 }
```

通常是音訊分析 reporter 連線失敗或中斷後的後續訊息，和 `audioanalyticsd` 相關。

如果 App 功能正常，可以先忽略。

### 13.6 CoreAnalytics app launch measurements

```text
Failed to send CA Event for app launch measurements for ca_event_type: 0 event_name: com.apple.app_launch_measurement.FirstFramePresentationMetric
```

```text
Failed to send CA Event for app launch measurements for ca_event_type: 1 event_name: com.apple.app_launch_measurement.ExtendedLaunchMetrics
```

Apple 的 CoreAnalytics 嘗試送出 App 啟動效能統計失敗。常見於 Xcode Debug / Simulator。這不是 UI 第一幀真的失敗，也通常不是 App 內部 bug。

通常可以忽略。如果只是想令 Debug Area 乾淨，可以考慮在 Xcode Scheme 加環境變數隱藏部分系統 log。

### 13.7 HALC ProxyIOContext overload

```text
HALC_ProxyIOContext.cpp:1623 HALC_ProxyIOContext::IOWorkLoop: skipping cycle due to overload
```

音訊 I/O 某一輪負載過高，常在響鈴、通知、UI 狀態切換同時發生時出現。

如果只是偶爾出現，而且提醒聲和 UI 都正常，可以先觀察。若大量出現，就要檢查是否有重複播放音效、短時間內多次初始化音訊、或同時觸發太多通知 / 音效操作。

## 14. 之後可以優化的方向

以下是將來可以考慮的優化，不一定要馬上做：

- 將倒數時間改成使用者可自訂。
- 加入設定頁面，例如聲音、通知、是否自動開始下一階段。
- 將 `TimerManager` 的通知邏輯再拆成獨立 service。
- 為 `TimerStep` 和倒數流程加 unit tests。
- 儲存使用者上次設定，例如用 `UserDefaults`。
- 加入狀態恢復，App 重開後可以知道上次倒數是否仍然有效。

目前的架構已經比單一巨大 `ContentView.swift` 清楚好多，下一步如果 App 繼續變大，最值得拆的是 `TimerManager` 入面的通知 / AlarmKit / 音效部分。
