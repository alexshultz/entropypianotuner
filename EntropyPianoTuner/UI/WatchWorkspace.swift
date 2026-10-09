import SwiftUI

#if os(watchOS)
struct WatchWorkspace: View {
    @Bindable var session: TunerSession
    @State private var crown = Double(PianoLayout.a4)

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(PianoLayout.label(session.selectedKey))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("\(session.piano?.recordedCount ?? 0) of 88")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                Meter(cents: session.reading.cents, level: session.reading.level, compact: true)
                HStack {
                    Button {
                        session.select(max(0, session.selectedKey - 1))
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    Button("Capture") { session.captureNow() }
                    Button {
                        session.select(min(PianoLayout.keyCount - 1, session.selectedKey + 1))
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.bordered)
                if let target = session.piano?.targetFrequency(for: session.selectedKey) {
                    Text(String(format: "%.1f Hz", target))
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                    HStack {
                        Button("−1¢") { session.nudgeSelected(by: -1) }
                        Button("In tune") { session.markTuned() }
                        Button("+1¢") { session.nudgeSelected(by: 1) }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption2)
                }
                if session.piano?.recordedCount == PianoLayout.keyCount {
                    if session.calculating {
                        ProgressView(value: session.progress)
                        Button("Stop") { session.stopCalculation() }
                    } else {
                        Button("Calculate") { session.calculate() }
                    }
                }
                Text(session.status)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.muted)
            }
        }
        .navigationTitle(session.piano?.name ?? "Piano")
        .focusable()
        .digitalCrownRotation(
            $crown,
            from: 0,
            through: Double(PianoLayout.keyCount - 1),
            by: 1.0,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crown) { _, value in
            let key = Int(value.rounded())
            if key != session.selectedKey { session.select(key) }
        }
        .onChange(of: session.selectedKey) { _, key in
            if Int(crown.rounded()) != key { crown = Double(key) }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Pianos") { session.closePiano() }
            }
        }
        .onAppear {
            crown = Double(session.selectedKey)
            if !session.microphoneOn { Task { await session.start() } }
        }
        .onDisappear { session.stop() }
    }
}
#endif
