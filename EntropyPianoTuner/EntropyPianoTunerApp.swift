import SwiftData
import SwiftUI

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
    }
}
