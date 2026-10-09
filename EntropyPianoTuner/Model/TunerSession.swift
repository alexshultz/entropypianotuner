import Foundation
import SwiftData

@MainActor
@Observable
final class TunerSession {
    var pianos: [Piano] = []
    var piano: Piano?
    var spectra: [[Double]] = []
    var selectedKey = PianoLayout.a4
    var page: WorkspacePage = .record
    var reading = LiveReading(level: 0, cents: nil, detectedHz: nil, targetHz: nil)
    var microphoneOn = false
    var permissionDenied = false
    var status = ""
    var calculating = false
    var progress = 0.0
    var accuracy: CalculationAccuracy = .standard
    var seedText = "0"
    var usePitchRaise = false
    var autoCapture = true
    private var stableSince: Date?
    private var captureHold = 0
    private let engine = ToneEngine()
    private var calcToken = UUID()
    private var calcFlag = CalcFlag()
    private var refreshing = false
    private var refreshQueued = false
    @ObservationIgnored private var storeObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var cloudWatch: PianoCloudWatchBox?

    init() {
        PianoStore.prepare()
        pianos = PianoStore.list()
        watchStore()
        engine.onReading = { [weak self] reading in
            Task { @MainActor in
                self?.accept(reading)
            }
        }
    }

    var selectedMeasurement: KeyMeasurement? {
        guard let piano, selectedKey >= 0, selectedKey < piano.keys.count else { return nil }
        return piano.keys[selectedKey]
    }

    func open(_ piano: Piano) {
        guard let loaded = PianoStore.load(piano.id) else { return }
        self.piano = loaded.0
        spectra = loaded.1
        selectedKey = PianoLayout.a4
        page = loaded.0.recordedCount == PianoLayout.keyCount && loaded.0.tuningCents != nil ? .tune : .record
        status = ""
        syncEngineTarget()
    }

    func createPiano() {
        let count = pianos.count + 1
        let piano = Piano.make(name: "Piano \(count)")
        let empty = Array(repeating: [Double](), count: PianoLayout.keyCount)
        PianoStore.save(piano, spectra: empty)
        pianos = PianoStore.list()
        self.piano = piano
        spectra = empty
        selectedKey = 0
        page = .record
    }

    func closePiano() {
        stop()
        piano = nil
        spectra = []
        pianos = PianoStore.list()
    }

    func rename(_ name: String) {
        guard var piano else { return }
        piano.name = name
        piano.updated = Date()
        self.piano = piano
        persist()
    }

    func setConcertPitch(_ pitch: Double) {
        guard var piano else { return }
        piano.concertPitch = min(466, max(415, pitch))
        piano.updated = Date()
        self.piano = piano
        engine.concertPitch = piano.concertPitch
        persist()
        syncEngineTarget()
    }

    func setBassBreak(_ key: Int) {
        guard var piano else { return }
        piano.bassBreak = min(PianoLayout.keyCount - 1, max(1, key))
        piano.updated = Date()
        self.piano = piano
        persist()
    }

    func select(_ key: Int) {
        selectedKey = key
        stableSince = nil
        captureHold = 0
        syncEngineTarget()
    }

    func toggleMicrophone() {
        if microphoneOn {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        guard let piano else { return }
        if await engine.requestPermission() == false {
            permissionDenied = true
            status = "Microphone access is off. Enable it in Settings to record the piano."
            return
        }
        permissionDenied = false
        engine.concertPitch = piano.concertPitch
        syncEngineTarget()
        do {
            try engine.start()
            microphoneOn = true
            status = page == .tune ? "Play the open string." : "Play \(PianoLayout.label(selectedKey)) and hold it."
        } catch {
            status = error.localizedDescription
        }
    }

    func stop() {
        engine.stop()
        microphoneOn = false
        reading.level = 0
        reading.cents = nil
    }

    func captureNow() {
        guard let piano else { return }
        let samples = engine.captureWindow()
        guard samples.count >= 32_768 else {
            status = "Hold the note a little longer."
            return
        }
        let key = selectedKey
        let concert = piano.concertPitch
        let rate = engine.sampleRate
        status = "Measuring \(PianoLayout.label(key))…"
        Task.detached(priority: .userInitiated) {
            let recording = NoteAnalysis.analyze(
                samples: samples,
                sampleRate: rate,
                key: key,
                concertPitch: concert,
                a4: PianoLayout.a4
            )
            await MainActor.run {
                self.store(recording, for: key)
            }
        }
    }

    func clearKey() {
        guard var piano, selectedKey < piano.keys.count else { return }
        piano.keys[selectedKey] = KeyMeasurement()
        piano.tuningCents = nil
        piano.entropy = nil
        piano.updated = Date()
        self.piano = piano
        if selectedKey < spectra.count { spectra[selectedKey] = [] }
        persist()
        status = "\(PianoLayout.label(selectedKey)) cleared."
    }

    func nudgeSelected(by cents: Double) {
        guard var piano, var tuning = piano.tuningCents, selectedKey < tuning.count else { return }
        tuning[selectedKey] = min(80, max(-80, tuning[selectedKey] + cents))
        piano.tuningCents = tuning
        piano.keys[selectedKey].tuned = false
        piano.updated = Date()
        self.piano = piano
        persist()
        syncEngineTarget()
    }

    func markTuned() {
        guard var piano, selectedKey < piano.keys.count else { return }
        piano.keys[selectedKey].tuned = true
        piano.updated = Date()
        self.piano = piano
        persist()
        if selectedKey < PianoLayout.keyCount - 1 { select(selectedKey + 1) }
    }

    func calculate() {
        guard let piano, !calculating else { return }
        calculating = true
        progress = 0
        status = usePitchRaise ? "Building the pitch-raise curve…" : "Minimizing spectral entropy…"
        let token = UUID()
        calcToken = token
        let flag = CalcFlag()
        calcFlag = flag
        let spectra = self.spectra
        let frequencies = piano.keys.map(\.frequency)
        let bs = piano.keys.map(\.inharmonicity)
        let concert = piano.concertPitch
        let bassBreak = piano.bassBreak
        let accuracy = self.accuracy
        let seed = UInt64(seedText) ?? 0
        let pitchRaise = usePitchRaise
        Task.detached(priority: .userInitiated) {
            do {
                let prepared = try AuditoryPreprocessing.prepare(
                    spectra: spectra,
                    frequencies: frequencies,
                    inharmonicities: bs,
                    a4: PianoLayout.a4
                )
                let result: TuningComputation
                if pitchRaise {
                    guard let cents = PitchRaise.compute(
                        inharmonicities: prepared.map(\.inharmonicity),
                        a4: PianoLayout.a4,
                        bassBreak: bassBreak
                    ) else {
                        throw AuditoryPreprocessing.Failure.inconsistent("Pitch raise needs recorded notes on both sides of the bass break.")
                    }
                    result = TuningComputation(cents: cents, entropy: 0)
                } else {
                    result = EntropyMinimizer.compute(
                        keys: prepared,
                        a4: PianoLayout.a4,
                        concertPitch: concert,
                        accuracy: accuracy,
                        seed: seed,
                        shouldCancel: { flag.cancelled },
                        progress: { value in
                            Task { @MainActor in
                                if self.calcToken == token { self.progress = value }
                            }
                        }
                    )
                }
                let bs = prepared.map(\.inharmonicity)
                await MainActor.run {
                    guard self.calcToken == token else { return }
                    self.finish(result, inharmonicities: bs, concert: concert)
                }
            } catch {
                await MainActor.run {
                    guard self.calcToken == token else { return }
                    self.calculating = false
                    self.status = (error as? AuditoryPreprocessing.Failure)?.description ?? error.localizedDescription
                }
            }
        }
    }

    func stopCalculation() {
        calcFlag.cancelled = true
        calcToken = UUID()
        calculating = false
        status = "Calculation stopped."
    }

    private func finish(_ result: TuningComputation, inharmonicities: [Double], concert: Double) {
        guard var piano else { return }
        piano.tuningCents = result.cents
        piano.entropy = result.entropy
        piano.tuningConcertPitch = concert
        for i in piano.keys.indices where i < inharmonicities.count {
            piano.keys[i].inharmonicity = inharmonicities[i]
            piano.keys[i].tuned = false
        }
        piano.updated = Date()
        self.piano = piano
        calculating = false
        progress = 1
        persist()
        let entropy = result.entropy
        status = entropy > 0
            ? String(format: "Tuning ready. Entropy %.4f.", entropy)
            : "Pitch-raise curve ready."
        page = .tune
        syncEngineTarget()
    }

    private func store(_ recording: NoteAnalysis.Recording?, for key: Int) {
        guard var piano, key < piano.keys.count else { return }
        guard let recording else {
            status = "Could not find \(PianoLayout.label(key)). Play it again, closer to the microphone."
            stableSince = nil
            return
        }
        piano.keys[key].recorded = true
        piano.keys[key].frequency = recording.frequency
        piano.keys[key].inharmonicity = recording.inharmonicity
        piano.keys[key].quality = recording.quality
        piano.keys[key].tuned = false
        piano.tuningCents = nil
        piano.entropy = nil
        piano.tuningConcertPitch = nil
        piano.updated = Date()
        self.piano = piano
        if spectra.count != PianoLayout.keyCount {
            spectra = Array(repeating: [], count: PianoLayout.keyCount)
        }
        spectra[key] = recording.spectrum
        persist()
        let cents = LogBin.cents(
            from: PianoLayout.frequency(key: key, cents: 0, concertPitch: piano.concertPitch),
            to: recording.frequency
        )
        status = String(format: "%@  %.1f Hz   %+.1f cents   B %.5f", PianoLayout.label(key), recording.frequency, cents, recording.inharmonicity)
        stableSince = nil
        captureHold = 0
        if autoCapture, key < PianoLayout.keyCount - 1 {
            select(key + 1)
        }
    }

    private func accept(_ reading: LiveReading) {
        self.reading = reading
        guard microphoneOn, autoCapture, page == .record, !calculating else { return }
        guard reading.level > 0.08, let cents = reading.cents, abs(cents) < 40 else {
            stableSince = nil
            captureHold = 0
            return
        }
        let now = Date()
        if stableSince == nil { stableSince = now }
        captureHold += 1
        if captureHold > 8, let stableSince, now.timeIntervalSince(stableSince) > 0.7 {
            captureHold = 0
            self.stableSince = nil
            captureNow()
        }
    }

    private func syncEngineTarget() {
        guard let piano else { return }
        engine.listenKey = selectedKey
        engine.concertPitch = piano.concertPitch
        engine.inharmonicity = selectedMeasurement?.inharmonicity ?? 0
        engine.expectsPitch = true
        if page == .tune, let target = piano.targetFrequency(for: selectedKey) {
            engine.targetHz = target
        } else {
            engine.targetHz = nil
        }
    }

    private func persist() {
        guard let piano else { return }
        PianoStore.save(piano, spectra: spectra)
        if let index = pianos.firstIndex(where: { $0.id == piano.id }) {
            pianos[index] = piano
        } else {
            pianos.insert(piano, at: 0)
        }
    }

    func refreshFromStore() {
        if refreshing {
            refreshQueued = true
            return
        }
        refreshing = true
        defer {
            refreshing = false
            if refreshQueued {
                refreshQueued = false
                refreshFromStore()
            }
        }
        guard let context = PianoStore.watchContext() else { return }
        context.processPendingChanges()
        PianoStore.reconcile()
        let listed = PianoStore.list()
        pianos = listed
        guard let piano else { return }
        guard let loaded = PianoStore.load(piano.id) else {
            self.piano = nil
            spectra = []
            return
        }
        guard loaded.0.updated > piano.updated else { return }
        self.piano = loaded.0
        spectra = loaded.1
        syncEngineTarget()
    }

    private func watchStore() {
        guard let context = PianoStore.watchContext() else { return }
        let center = NotificationCenter.default
        let refresh: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromStore()
            }
        }
        storeObservers.append(center.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main,
            using: refresh
        ))
        if #available(iOS 18, macOS 15, watchOS 11, visionOS 2, *) {
            storeObservers.append(center.addObserver(
                forName: ModelContext.didSave,
                object: context,
                queue: .main,
                using: refresh
            ))
        }
        if #available(iOS 27, macOS 27, watchOS 27, visionOS 27, *) {
            cloudWatch = PianoCloudWatchBox(context: context) { [weak self] in
                self?.refreshFromStore()
            }
        }
    }
}

/// Holds the OS 27 results observer without making TunerSession require that OS.
@MainActor
final class PianoCloudWatchBox {
    private let watch: Any

    @available(iOS 27, macOS 27, watchOS 27, visionOS 27, *)
    init(context: ModelContext, onChange: @escaping () -> Void) {
        watch = PianoCloudWatch(context: context, onChange: onChange)
    }
}

final class CalcFlag: @unchecked Sendable {
    var cancelled = false
}

enum WorkspacePage: String, CaseIterable, Identifiable {
    case record, calculate, tune
    var id: String { rawValue }
    var label: String {
        switch self {
        case .record: return "Record"
        case .calculate: return "Calculate"
        case .tune: return "Tune"
        }
    }
}
