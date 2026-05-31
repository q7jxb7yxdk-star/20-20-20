import SwiftUI

// MARK: - Apple Watch 主畫面
struct WatchContentView: View {
    @ObservedObject var manager: WatchTimerManager
    
    var body: some View {
        VStack(spacing: 8) {
            Text(statusTitle)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .foregroundColor(manager.displayIsAlarming ? .orange : .primary)
            
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 8)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        manager.displayIsAlarming ? Color.orange : manager.displayStep.themeColor,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: manager.displayTimeRemaining)
                
                VStack(spacing: 4) {
                    Image(systemName: manager.displayStep.icon)
                        .font(.title3)
                        .foregroundColor(manager.displayStep.themeColor)
                    
                    Text(timeString(from: Int(ceil(manager.displayTimeRemaining))))
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
        .gesture(cycleSwipeGesture)
    }
    
    private var progress: Double {
        guard manager.displayStep.seconds > 0 else { return 0 }
        return max(0, min(1, manager.displayTimeRemaining / Double(manager.displayStep.seconds)))
    }
    
    private var statusTitle: String {
        manager.displayIsAlarming ? manager.displayStep.completedTitle : manager.displayStep.activeTitle
    }
    
    private var primaryButtonIcon: String {
        if manager.displayIsAlarming { return "checkmark" }
        return manager.displayIsRunning ? "pause.fill" : "play.fill"
    }
    
    private var primaryButtonTint: Color {
        if manager.displayIsAlarming { return .orange }
        return manager.displayIsRunning ? .red : .blue
    }
    
    private var stepDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<WatchTimerStep.allCases.count, id: \.self) { index in
                Circle()
                    .fill(manager.displayStep.rawValue == index ? manager.displayStep.themeColor : Color.gray.opacity(0.35))
                    .frame(width: 5, height: 5)
            }
        }
    }
    
    private func primaryButtonAction() {
        if manager.displayIsAlarming {
            manager.nextStep()
        } else {
            manager.toggle()
        }
    }
    
    private var cycleSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                let width = value.translation.width
                let height = value.translation.height
                guard abs(width) > abs(height) * 1.25, abs(width) > 24 else { return }
                
                if width < 0 {
                    manager.selectNextStep()
                } else {
                    manager.selectPreviousStep()
                }
            }
    }
    
    private func timeString(from totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
