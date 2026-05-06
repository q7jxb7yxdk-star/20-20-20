import SwiftUI

#if os(macOS)
struct SettingsView: View {
    // @AppStorage 會直接讀寫 UserDefaults。
    // 這裡使用同一個 key，所以 macOS App Settings 和 iOS Settings.bundle 都會影響 AppConfiguration.runMode。
    @AppStorage(AppConfiguration.DefaultsKey.runMode) private var runMode = AppConfiguration.RunMode.release.rawValue
    
    private var selectedMode: AppConfiguration.RunMode {
        AppConfiguration.RunMode(rawValue: runMode) ?? .release
    }
    
    var body: some View {
        Form {
            Picker("運行模式", selection: $runMode) {
                ForEach(AppConfiguration.RunMode.allCases) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
            
            Text(selectedMode.description)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 360)
    }
}
#endif
