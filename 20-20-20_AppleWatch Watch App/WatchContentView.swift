import SwiftUI

// MARK: - Apple Watch 主畫面
struct WatchContentView: View {
    @StateObject private var manager = WatchTimerManager()
    
    var body: some View {
        VStack(spacing: 8) {
            Text(statusTitle)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .foregroundColor(manager.isAlarming ? .orange : .primary)
            
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 8)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        manager.isAlarming ? Color.orange : manager.currentStep.themeColor,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: manager.timeRemaining)
                
                VStack(spacing: 4) {
                    Image(systemName: manager.currentStep.icon)
                        .font(.title3)
                        .foregroundColor(manager.currentStep.themeColor)
                    
                    Text(timeString(from: Int(ceil(manager.timeRemaining))))
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(width: 105, height: 105)
            
            HStack(spacing: 12) {
                Button(action: primaryButtonAction) {
                    Image(systemName: primaryButtonIcon)
                        .font(.headline)
                }
                .tint(primaryButtonTint)
                
                Button(action: manager.reset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.headline)
                }
                .tint(.gray)
            }
            .buttonStyle(.borderedProminent)
            
            stepDots
        }
        .padding(.horizontal, 6)
    }
    
    private var progress: Double {
        guard manager.currentStep.seconds > 0 else { return 0 }
        return max(0, min(1, manager.timeRemaining / Double(manager.currentStep.seconds)))
    }
    
    private var statusTitle: String {
        manager.isAlarming ? manager.currentStep.completedTitle : manager.currentStep.activeTitle
    }
    
    private var primaryButtonIcon: String {
        if manager.isAlarming { return "checkmark" }
        return manager.isRunning ? "pause.fill" : "play.fill"
    }
    
    private var primaryButtonTint: Color {
        if manager.isAlarming { return .orange }
        return manager.isRunning ? .red : .blue
    }
    
    private var stepDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<WatchTimerStep.allCases.count, id: \.self) { index in
                Circle()
                    .fill(manager.currentStep.rawValue == index ? manager.currentStep.themeColor : Color.gray.opacity(0.35))
                    .frame(width: 5, height: 5)
            }
        }
    }
    
    private func primaryButtonAction() {
        if manager.isAlarming {
            manager.nextStep()
        } else {
            manager.toggle()
        }
    }
    
    private func timeString(from totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    WatchContentView()
}
