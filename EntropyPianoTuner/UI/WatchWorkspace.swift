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
                Text("\(session.piano?.recordedCount ?? 0) of 88")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Meter(cents: session.reading.cents, level: session.reading.level, compact: true)
                HStack {
                    Button {
                        session.select(max(0, session.selectedKey - 1))
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Previous key")
                    Button {
                        session.select(min(PianoLayout.keyCount - 1, session.selectedKey + 1))
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel("Next key")
                }
                .buttonStyle(.bordered)
                Button("Capture") { session.captureNow() }
                    .buttonStyle(.borderedProminent)
                if let target = session.piano?.targetFrequency(for: session.selectedKey) {
                    Text(String(format: "%.1f Hz", target))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button("−1¢") { session.nudgeSelected(by: -1) }
                        .buttonStyle(.bordered)
                    Button("In tune") { session.markTuned() }
                        .buttonStyle(.borderedProminent)
                    Button("+1¢") { session.nudgeSelected(by: 1) }
                        .buttonStyle(.bordered)
                }
                if session.piano?.recordedCount == PianoLayout.keyCount {
                    if session.calculating {
                        ProgressView(value: session.progress)
                        Button("Stop") { session.stopCalculation() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Calculate") { session.calculate() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if !session.status.isEmpty {
                    Text(session.status)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    session.toggleMicrophone()
                } label: {
                    Image(systemName: session.microphoneOn ? "mic.fill" : "mic.slash")
                }
                .accessibilityLabel(session.microphoneOn ? "Stop microphone" : "Start microphone")
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
