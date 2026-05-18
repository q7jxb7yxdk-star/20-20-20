import SwiftUI

#if os(macOS)
struct SettingsView: View {
    // @AppStorage 會直接讀寫 UserDefaults。
    // 這裡使用同一個 key，所以 macOS App Settings 和 iOS Settings.bundle 都會影響 AppConfiguration.runMode。
    @AppStorage(AppConfiguration.DefaultsKey.runMode) private var runMode = AppConfiguration.RunMode.release.rawValue
    @AppStorage(AppConfiguration.DefaultsKey.languageCode) private var languageCode = AppLanguage.systemPreferred.rawValue
    
    private var selectedMode: AppConfiguration.RunMode {
        AppConfiguration.RunMode(rawValue: runMode) ?? .release
    }
    
    private var languageSelection: Binding<String> {
        Binding(
            get: {
                languageCode
            },
            set: { newValue in
                // Picker 寫入語言前，先標記成手動選擇。
                // 這樣 AppText.current 重新計算時會立即使用新語言，而不是仍然按 auto/system 判斷。
                AppConfiguration.markLanguageManuallySelected(newValue)
                languageCode = newValue
            }
        )
    }
    
    var body: some View {
        Form {
            Picker(AppText.runModeLabel, selection: $runMode) {
                ForEach(AppConfiguration.RunMode.allCases) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
            
            Text(selectedMode.description)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Divider()
            
            Picker(AppText.languageLabel, selection: languageSelection) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
        }
        .padding(24)
        .frame(width: 360)
    }
}
#endif
