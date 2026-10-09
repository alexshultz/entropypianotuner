import SwiftData
import SwiftUI

private struct TunerSessionKey: FocusedValueKey {
    typealias Value = TunerSession
}

extension FocusedValues {
    var tunerSession: TunerSession? {
        get { self[TunerSessionKey.self] }
        set { self[TunerSessionKey.self] = newValue }
    }
}

@main
struct EntropyPianoTunerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 780)
        #elseif os(visionOS)
        .defaultSize(width: 1280, height: 800)
        #endif
        #if !os(watchOS)
        .commands { TunerCommands() }
        #endif
    }
}

#if !os(watchOS)
private struct TunerCommands: Commands {
    @FocusedValue(\.tunerSession) private var session

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Piano") { session?.createPiano() }
                .keyboardShortcut("n")
                .disabled(session == nil)
        }
        CommandMenu("Tuner") {
            Button("Pianos") { session?.closePiano() }
                .disabled(session?.piano == nil)
            Divider()
            Button("Record") { session?.page = .record }
                .keyboardShortcut("1")
                .disabled(session?.piano == nil)
            Button("Calculate") { session?.page = .calculate }
                .keyboardShortcut("2")
                .disabled(session?.piano == nil)
            Button("Tune") { session?.page = .tune }
                .keyboardShortcut("3")
                .disabled(session?.piano == nil)
            Divider()
            Button(session?.microphoneOn == true ? "Stop Microphone" : "Start Microphone") {
                session?.toggleMicrophone()
            }
            .disabled(session?.piano == nil)
        }
    }
}
#endif
