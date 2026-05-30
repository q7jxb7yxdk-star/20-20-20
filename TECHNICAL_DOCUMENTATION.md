# 20-20-20 Technical Documentation

This document explains how the `20-20-20` App works internally. The goal is to make the code easier to study, maintain, and extend.

## 1. App Overview

`20-20-20` is a SwiftUI eye-care timer for iOS, iPadOS, macOS, and watchOS. It guides the user through a fixed four-step cycle:

| Step | Purpose | Release Duration |
| --- | --- | --- |
| Step 1 | Focus work | 20 minutes |
| Step 2 | Look far away | 20 seconds |
| Step 3 | Focus work | 20 minutes |
| Step 4 | Long rest | 3 minutes |

After a step completes, the App enters an alarming state. The user confirms the alert, then the App moves to the next step. After Step 4, the cycle returns to Step 1 and waits.

## 2. User-Facing Features

- Circular countdown timer.
- Start, pause, reset, and confirm controls.
- Completion text for each step.
- Debug / Release run mode.
- English / Traditional Chinese UI language setting.
- iOS Live Activity on Lock Screen and Dynamic Island.
- iOS AlarmKit reminders.
- macOS local notifications and in-app sound.
- Apple Watch countdown with system haptic / smart alarm support.
- iPhone to Watch sync for run mode and preferred language.

## 3. File Responsibilities

| File or Folder | Responsibility |
| --- | --- |
| `EyeCareTimerApp.swift` | App entry, scene handling, notification delegate setup, WatchConnectivity sender. |
| `ContentView.swift` | Main SwiftUI layout, progress circle, buttons, step dots. |
| `TimerStep.swift` | Timer step enum and shared `AppConfiguration`. |
| `AppText.swift` | App UI strings and language selection logic. |
| `SettingsView.swift` | macOS Settings UI. |
| `TimerManager.swift` | Main countdown engine and platform alert behavior. |
| `NotificationPresenter.swift` | Foreground notification behavior. |
| `AlarmKitSupport.swift` | iOS AlarmKit metadata and stop intent. |
| `EyeCareTimerLiveActivity.swift` | App-side Live Activity creation, update, and ending. |
| `EyeCareLiveActivityIntents.swift` | Interactive Live Activity button intents in the App target. |
| `20-20-20LiveActivityExtension/` | Live Activity widget UI and extension-side types. |
| `20-20-20_AppleWatch Watch App/` | watchOS App UI, timer manager, steps, and WatchConnectivity receiver. |
| `Settings.bundle/Root.plist` | iOS Settings App options. |

## 4. App Entry

The App starts in `EyeCareTimerApp.swift`.

Important startup work:

- Register default settings with `AppConfiguration.registerDefaults()`.
- Set `UNUserNotificationCenter.current().delegate`.
- On iOS, activate `WatchRunModeSync`.
- On iOS, sync run mode and language to Watch when the App becomes active.
- On macOS, provide a SwiftUI `Settings` scene.

## 5. Countdown Model

The timer steps are defined by `TimerStep`:

```swift
enum TimerStep: Int, CaseIterable {
    case work1 = 0, eyeCare = 1, work2 = 2, longRest = 3
}
```

Each step provides:

- `name`
- `seconds`
- `icon`
- `themeColor`

This keeps the UI simple. `ContentView` does not need to know the duration or icon for each step; it reads them from `manager.currentStep`.

## 6. App Configuration

`AppConfiguration` stores shared settings:

- `app_run_mode`
- `app_language_code`
- Debug / Release durations.
- iOS AlarmKit sound configuration.

App run mode is not the same as Xcode build configuration.

| Setting | Meaning |
| --- | --- |
| Xcode Debug / Release | Compiler and build behavior. |
| App Debug / Release | User-facing timer duration mode. |

Debug mode uses short durations so notification, alarm, Live Activity, and Watch behavior can be tested quickly.

## 7. Language System

UI text is centralized in `AppText.swift`.

The App uses:

```text
app_language_code
```

Supported values:

| Value | Language |
| --- | --- |
| `en` | English |
| `zh-Hant` | Traditional Chinese |

If the user has not chosen a language yet, `AppLanguage.systemPreferred` checks `Locale.preferredLanguages`:

- Chinese preference: Traditional Chinese.
- English or non-Chinese preference: English.

On iOS, the language can be changed in:

```text
iPhone Settings > 20-20-20 > Preferred Language
```

On macOS, the language can be changed in the App Settings window.

The Apple Watch app has its own `WatchAppText.swift`. iPhone syncs the selected language to Watch using WatchConnectivity.

## 8. Main UI

`ContentView.swift` is the main UI layer. It owns the timer manager:

```swift
@StateObject private var manager = TimerManager()
```

`@StateObject` is used because the view should own the timer manager for the lifetime of the screen. If the manager were recreated during view redraws, countdown state could be lost.

The UI is split into smaller computed views:

- `statusHeader`
- `progressCircle`
- `actionControls`
- `stepDots`
- portrait and landscape layouts

The progress circle is based on:

```swift
Circle().trim(from: 0, to: progress)
```

This draws only part of the circle based on remaining time.

## 9. TimerManager

`TimerManager` is the core countdown engine.

It is marked `@MainActor` because its `@Published` properties directly update SwiftUI:

```swift
@Published var currentStep: TimerStep
@Published var timeRemaining: Double
@Published var isRunning: Bool
@Published var isAlarming: Bool
```

Main responsibilities:

- Start countdown.
- Pause countdown.
- Reset countdown.
- Move to next step.
- Trigger alert state.
- Schedule or cancel platform alerts.
- Update Live Activity.
- React to Live Activity control commands.
- Play platform-specific sound or haptic.

## 10. Target Date Countdown

The App uses a `targetDate` approach instead of subtracting one second every tick.

When the timer starts:

```swift
targetDate = Date().addingTimeInterval(timeRemaining)
```

When the UI updates:

```swift
let diff = target.timeIntervalSinceNow
```

This is more accurate than `timeRemaining -= 1`, especially when the App pauses, enters background, or the system delays timer events.

The display timer currently updates every `0.2` seconds. This keeps the circular progress smooth without updating as aggressively as `0.05` seconds.

## 11. Completion Flow

When countdown reaches zero:

1. `syncRemainingTime()` detects that remaining time is finished.
2. `triggerAlarm()` is called.
3. `isRunning` becomes `false`.
4. `isAlarming` becomes `true`.
5. Platform-specific alert behavior runs.
6. The main button becomes a confirmation / next-step button.

When the user confirms:

1. `nextStep()` stops the current alert.
2. The next `TimerStep` is selected.
3. If the cycle is not finished, the next step starts.
4. If Step 4 has completed, the timer returns to Step 1 and waits.

## 12. Platform Alert Strategy

| Platform | Foreground | Background | Custom Sound |
| --- | --- | --- | --- |
| iOS / iPadOS | AlarmKit and Live Activity | AlarmKit | `alarm.caf` through AlarmKit |
| macOS | App sound plus local notification | Local notification, if allowed by system | `alarm.caf` through `NSSound` |
| watchOS | System haptic / alert | Smart alarm session | Not used; system haptic is more reliable |

macOS does not have a public AlarmKit equivalent. It uses `UserNotifications` plus in-app sound.

watchOS background audio is limited. The watchOS app uses system haptic / smart alarm behavior rather than trying to play a custom CAF file.

## 13. iOS AlarmKit

`AlarmKitSupport.swift` contains:

- `EyeCareAlarmMetadata`
- `StopEyeCareAlarmIntent`

AlarmKit handles system-level timer alert behavior on iOS. It is closer to the system Clock app experience than a normal local notification.

The stop intent uses a static English metadata title because AppIntents metadata extraction requires literal strings. Runtime App UI text still uses `AppText`.

## 14. Notifications

`NotificationPresenter.swift` implements `UNUserNotificationCenterDelegate`.

Its purpose is to control how notifications appear while the App is in the foreground.

The App sets:

```swift
UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
```

`NotificationPresenter.shared` is a singleton so the notification center delegate is not accidentally released.

## 15. Live Activity

iOS uses Live Activity to show countdown state on the Lock Screen and Dynamic Island.

Main files:

| File | Purpose |
| --- | --- |
| `EyeCareTimerLiveActivity.swift` | Starts, updates, and ends the Activity. |
| `20-20-20LiveActivityExtension/EyeCareTimerLiveActivityWidget.swift` | Lock Screen / Dynamic Island UI. |
| `EyeCareLiveActivityIntents.swift` | Interactive button behavior. |

Current display behavior:

- Normal and inactive Lock Screen / Dynamic Island: full `m:ss` countdown.
- Paused state: fixed remaining time.
- Alarming state: fixed `0:00`.

Running Live Activity time is based on `startDate` and `endDate`. The widget uses SwiftUI's system timer renderer:

```swift
Text(timerInterval: state.startDate...state.endDate, countsDown: true)
```

This lets the Lock Screen continue counting down after the App process enters the background. The App should not push a new Live Activity state every second while running, because repeated ActivityKit updates can make the Lock Screen timer redraw or flash.

`remainingSeconds` is still kept in the Activity state for paused display and interactive button calculations.

The time UI is centralized in `LiveActivityTimerText`. It owns:

- Normal countdown text.
- Paused and alarming text.
- Fixed-width right alignment for Lock Screen and Dynamic Island variants.
- A fixed Lock Screen time container height to reduce visual jumps between running and paused text.
- Separate style values for Lock Screen, Dynamic Island compact, and Dynamic Island expanded layouts.

Keeping these states inside one component keeps Lock Screen and Dynamic Island timer layout consistent.

Time size and width are intentionally marked in `EyeCareTimerLiveActivityWidget.swift` so they are easy to tune later:

- `Lock Screen time width`: `LiveActivityTimerText.Style.width`, `.lockScreen`.
- `Lock Screen time height`: `LiveActivityTimerText.Style.height`, `.lockScreen`.
- `Lock Screen time font size`: `LiveActivityTimerText.font`, `.lockScreen`.
- `Dynamic Island compact time width`: `LiveActivityTimerText.Style.width`, `.dynamicIslandCompact`.
- `Dynamic Island compact time font size`: `LiveActivityTimerText.font`, `.dynamicIslandCompact`.
- `Dynamic Island compact-expanded time width`: `LiveActivityTimerText.Style.width`, `.dynamicIslandCompactExpanded`.
- `Dynamic Island compact-expanded time font size`: `LiveActivityTimerText.font`, `.dynamicIslandCompactExpanded`.
- `Dynamic Island expanded time width`: `LiveActivityTimerText.Style.width`, `.dynamicIslandExpanded`.
- `Dynamic Island expanded time font size`: `LiveActivityTimerText.font`, `.dynamicIslandExpanded`.

Icon size is controlled outside `LiveActivityTimerText`:

- `compact icon font size`: the `Image` in `compactLeading`.
- `minimal icon font size`: the `Image` in `minimal`.
- `expanded icon`: the `Image` in `DynamicIslandExpandedRegion(.leading)`.
- `Lock Screen button icon size`: the `Image` inside `liveActivityIconLink`.
- `Lock Screen button icon frame width / height`: the `.frame(width:height:)` inside `liveActivityIconLink`.

Dynamic Island keeps using `Text(timerInterval:)` for running time so the compact countdown remains system-rendered. Lock Screen also uses the system timer renderer for running time, while paused and alarming states use fixed text.

Dynamic Island icon state is centralized through `dynamicIslandIconName(for:)`:

- Running: `timer`
- Paused: `pause.circle`
- Alarming: `bell.fill`

Dynamic Island compact width is not directly configurable. The system sizes the island from the compact leading and compact trailing content. The App can only influence it indirectly through:

- Compact icon font size.
- Compact time font size.
- Compact time frame width.
- Visual offsets such as `offset(x:)`, which move drawing but do not change the layout size.

The App only updates the Live Activity at state transitions such as start, pause, resume, reset, next step, and time up. It does not update the Activity every display tick.

## 16. Live Activity Buttons

The Live Activity has interactive buttons:

- Start / Pause / Next
- End

They use:

```swift
Button(intent: ToggleEyeCareLiveActivityIntent()) { ... }
Button(intent: ResetEyeCareLiveActivityIntent()) { ... }
```

This lets the user control the timer without opening the App.

Because a Live Activity intent cannot directly access the active `TimerManager` instance, the App uses a command token mechanism:

1. Button intent updates the Activity state.
2. It writes `controlCommand` and `controlCommandID`.
3. `TimerManager` polls the current Activity state.
4. If it sees a new command ID, it performs the command.
5. Already-handled command IDs are ignored.

This avoids requiring App Groups for this feature.

## 17. Apple Watch App

The watchOS code lives in:

```text
20-20-20_AppleWatch Watch App/
```

Main files:

| File | Purpose |
| --- | --- |
| `20-20-20_AppleWatchApp.swift` | Watch App entry and WatchConnectivity receiver. |
| `WatchContentView.swift` | Watch UI. |
| `WatchTimerManager.swift` | Watch countdown engine. |
| `WatchTimerStep.swift` | Watch step and duration configuration. |
| `WatchAppText.swift` | Watch UI text and language selection. |
| `WatchNotificationPresenter.swift` | Watch foreground notification behavior. |

The Watch app receives these values from iPhone:

- `app_run_mode`
- `app_language_code`

If the Watch timer is idle when new settings arrive, it refreshes the displayed duration immediately.

## 18. Watch Smart Alarm

The Watch app uses `WKExtendedRuntimeSession` for background smart alarm behavior.

The Watch Info.plist includes:

```xml
<key>WKBackgroundModes</key>
<array>
    <string>alarm</string>
</array>
```

The session must be strongly retained. The app uses:

```swift
static let shared = WatchTimerManager()
```

and the Watch App entry owns it with `@StateObject`.

If the session object is released too early, Xcode may show messages such as:

```text
WKExtendedRuntimeObject was dealloced while scheduled
```

## 19. Settings

iOS Settings are defined in:

```text
20-20-20/Settings.bundle/Root.plist
```

Current iOS Settings UI:

```text
Run Mode
Mode
    Debug
    Release
Preferred Language
Language
    English
    繁體中文
```

The iOS Settings page title and system-managed settings such as Mobile Data are controlled by iOS and cannot be removed from `Root.plist`.

macOS settings are implemented in:

```text
20-20-20/SettingsView.swift
```

## 20. Xcode Debug Area Notes

Some Xcode Debug Area messages come from Apple frameworks or Simulator behavior. They do not always mean the App has a bug.

| Message Keyword | Meaning | Action |
| --- | --- | --- |
| `AddInstanceForFactory` | CoreAudio / AudioToolbox initialization log. | Usually ignore if sound works. |
| `LoudnessManager` | Audio framework tried to load loudness configuration. | Usually ignore in Simulator. |
| `DetachedSignatures` | macOS signing/security file lookup. | Usually ignore. |
| `audioanalyticsd` | Sandbox audio analytics service lookup. | Usually ignore in Debug. |
| `Failed to send CA Event` | Apple CoreAnalytics launch metric failed. | Usually ignore. |
| `HALC_ProxyIOContext ... overload` | Audio cycle overload. | Observe if frequent. |
| `Application context data is nil` | WatchConnectivity has no saved context yet. | Open iPhone app once or rely on Watch local defaults. |

Prioritize messages that break user-facing behavior, such as failed AlarmKit scheduling, no notification, no Watch smart alarm, or a real crash.

## 21. Useful Commands

Convert MP3 to CAF:

```bash
afconvert -f caff -d ima4 -c 1 input.mp3 alarm.caf
```

Build iOS from terminal:

```bash
xcodebuild -project /Users/sunnyyu/Documents/Xcode/20-20-20/20-20-20.xcodeproj -scheme 20-20-20 -destination 'generic/platform=iOS' build
```

Build macOS from terminal:

```bash
xcodebuild -project /Users/sunnyyu/Documents/Xcode/20-20-20/20-20-20.xcodeproj -scheme 20-20-20 -destination 'generic/platform=macOS' build
```

## 22. Git Workflow Notes

This project currently keeps the local branch name as `main`, while the GitHub remote branch is `master`.

That is allowed, but it means a plain `git push` may fail with a warning that the upstream branch name does not match the local branch name.

Use this command when pushing:

```bash
git push origin HEAD:master
```

Meaning:

- `origin`: the GitHub remote.
- `HEAD`: the latest commit on the current local branch.
- `master`: the remote branch to update.

### Check What Changed

Use the full status command when learning:

```bash
git status
```

It explains the current branch, staged files, unstaged files, untracked files, and suggested next commands.

Use the short version when you want a compact view:

```bash
git status --short --branch
```

Example output:

```text
## main...origin/master
 M 20-20-20/AppText.swift
 M 20-20-20/SettingsView.swift
```

Common short status symbols:

| Symbol | Meaning |
| --- | --- |
| ` M file` | Modified, not staged yet. |
| `M  file` | Modified and already staged. |
| `A  file` | New file staged. |
| `D  file` | Deleted file. |
| `?? file` | New file not tracked by Git yet. |

### Add Files Safely

To stage only specific files:

```bash
git add 20-20-20/AppText.swift 20-20-20/SettingsView.swift 20-20-20/TimerStep.swift
```

This is safer when you only want to commit a known set of files.

To stage every change in the repository:

```bash
git add -A
```

`git add -A` includes:

- modified files
- newly created files
- deleted files
- renamed or moved files

Use it only after checking `git status`, because it can include unrelated changes.

### Commit and Push

Typical safe Terminal flow:

```bash
git status
git add <changed-file-path>
git status
git commit -m "Short commit message"
git push origin HEAD:master
```

Example:

```bash
git add 20-20-20/AppText.swift 20-20-20/SettingsView.swift 20-20-20/TimerStep.swift
git commit -m "Fix language preference sync"
git push origin HEAD:master
```

Xcode's Commit and Push UI uses Git underneath. If Xcode commits locally but GitHub does not update, check whether the local branch and remote branch names are different.

## 23. Installation Notes

macOS archive flow:

```text
Product > Archive > Distribute App > Custom > Copy App
```

iPhone development install:

```text
Connect iPhone by USB > choose device in Xcode > Run
```

Watch development install:

1. Pair Apple Watch with iPhone.
2. Keep Watch unlocked.
3. Prefer USB connection to iPhone for first install.
4. Select the paired Watch destination in Xcode.
5. Run the Watch app scheme or the main app scheme with embedded Watch app.

## 24. Comment Style

Use `//` for normal comments:

```swift
// Use targetDate so the countdown remains accurate after background pauses.
```

Use `///` for documentation comments:

```swift
/// Converts a remaining second count into display text.
/// - Parameter seconds: Remaining seconds.
/// - Returns: A formatted timer string.
```

In Xcode, hold `Option` and click a documented symbol to see Quick Help.

## 25. Future Improvements

Possible future work:

- Let users customize step durations.
- Add unit tests for step transitions.
- Split `TimerManager` alert code into smaller services.
- Add more robust state restoration after app relaunch.
- Expand Watch settings support.
- Improve documentation with screenshots.
