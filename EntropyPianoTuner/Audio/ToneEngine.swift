import AVFoundation
import Foundation

struct LiveReading: Equatable {
    var level: Double
    var cents: Double?
    var detectedHz: Double?
    var targetHz: Double?
}

final class ToneEngine {
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "tuner.audio", qos: .userInitiated)
    private var ring: [Float] = []
    private let ringLock = NSLock()
    private(set) var sampleRate: Double = 48_000
    private(set) var isRunning = false

    var onReading: ((LiveReading) -> Void)?

    var listenKey: Int = 0
    var concertPitch: Double = 440
    var targetHz: Double?
    var inharmonicity: Double = 0
    var expectsPitch = false

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    func start() throws {
        guard !isRunning else { return }
        try activateSession()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw EngineError.noInput
        }
        sampleRate = format.sampleRate
        ring.removeAll(keepingCapacity: true)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        deactivateSession()
        isRunning = false
    }

    private func activateSession() throws {
        #if os(macOS)
        return
        #else
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = []
        #if os(iOS) || os(visionOS)
        options = [.defaultToSpeaker, .allowBluetoothA2DP]
        #elseif os(watchOS)
        options = [.allowBluetoothA2DP]
        #endif
        try session.setCategory(.playAndRecord, mode: .measurement, options: options)
        #if !os(watchOS)
        try session.setPreferredSampleRate(48_000)
        #endif
        try session.setActive(true)
        if session.sampleRate > 0 { sampleRate = session.sampleRate }
        #endif
    }

    private func deactivateSession() {
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }

    func captureWindow() -> [Float] {
        ringLock.lock()
        defer { ringLock.unlock() }
        let need = 65_536
        guard ring.count >= need else { return [] }
        return Array(ring.suffix(need))
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        var chunk = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let s = channel[i]
            chunk[i] = s
            sum += s * s
        }
        let level = min(1, Double(sqrt(sum / Float(max(count, 1))) * 8))
        ringLock.lock()
        ring.append(contentsOf: chunk)
        let cap = Int(sampleRate * 3)
        if ring.count > cap { ring.removeFirst(ring.count - cap) }
        let window = ring.count >= 32_768 ? Array(ring.suffix(32_768)) : []
        ringLock.unlock()

        let key = listenKey
        let concert = concertPitch
        let target = targetHz
        let b = inharmonicity
        let wants = expectsPitch
        queue.async { [weak self] in
            guard let self else { return }
            var reading = LiveReading(level: level, cents: nil, detectedHz: nil, targetHz: target)
            if wants, window.count >= 16_384,
               let linear = SpectrumFFT.magnitudes(samples: window, sampleRate: self.sampleRate) {
                let goal = target ?? PianoLayout.frequency(key: key, cents: 0, concertPitch: concert)
                reading.cents = NoteAnalysis.deviationCents(
                    linear: linear,
                    fundamentalTarget: goal,
                    inharmonicity: b,
                    key: key,
                    a4: PianoLayout.a4
                )
                if let cents = reading.cents {
                    reading.detectedHz = goal * pow(2.0, cents / 1_200.0)
                }
                reading.targetHz = goal
            }
            DispatchQueue.main.async {
                self.onReading?(reading)
            }
        }
    }

    enum EngineError: LocalizedError {
        case noInput
        var errorDescription: String? { "No microphone is available." }
    }
}
