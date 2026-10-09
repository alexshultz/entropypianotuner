import Foundation

enum CalculationAccuracy: String, Codable, CaseIterable, Identifiable {
    case low, standard, high, infinite
    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Low"
        case .standard: return "Standard"
        case .high: return "High"
        case .infinite: return "Until stopped"
        }
    }

    var stepsToFinish: Int {
        switch self {
        case .low: return 50
        case .standard: return 100
        case .high: return 150
        case .infinite: return -1
        }
    }
}

struct TuningComputation {
    var cents: [Double]
    var entropy: Double
}

/// Zero-temperature Monte Carlo search from Entropy Piano Tuner.
/// A move is kept only when the Shannon entropy of the summed spectra falls.
enum EntropyMinimizer {
    static func compute(
        keys: [AuditoryPreprocessing.PreparedKey],
        a4: Int,
        concertPitch: Double,
        accuracy: CalculationAccuracy,
        seed: UInt64,
        shouldCancel: () -> Bool,
        progress: (Double) -> Void
    ) -> TuningComputation {
        let count = keys.count
        var pitches = [Double](repeating: 0, count: count)
        var initial = [Double](repeating: 0, count: count)
        let bs = keys.map(\.inharmonicity)

        func partialCents(_ key: Int, _ n: Int) -> Double {
            let b = bs[key]
            return 600.0 / LogBin.ln2 * log((1 + Double(n * n) * b) / (1 + b))
        }

        if a4 > 13, count - a4 > 13 {
            let a3 = a4 - 12
            let a5 = a4 + 12
            let pitchA5 = partialCents(a4, 2)
            let pitchA3 = partialCents(a4, 2) - partialCents(a3, 4)
            for k in a3..<a4 { initial[k] = pitchA3 * Double(a4 - k) / 12.0 }
            for k in (a4 + 1)...a5 { initial[k] = pitchA5 * Double(k - a4) / 12.0 }
            if a5 + 1 < count {
                for k in (a5 + 1)..<count {
                    let pitch42 = initial[k - 12] + partialCents(k - 12, 4) - partialCents(k, 2)
                    let pitch21 = initial[k - 12] + partialCents(k - 12, 2)
                    initial[k] = 0.3 * pitch42 + 0.7 * pitch21
                }
            }
            if a3 > 0 {
                for k in stride(from: a3 - 1, through: 0, by: -1) {
                    let pitch63 = initial[k + 12] + partialCents(k + 12, 3) - partialCents(k, 6)
                    let pitch105 = initial[k + 12] + partialCents(k + 12, 5) - partialCents(k, 10)
                    let fraction = Double(k) / Double(a3)
                    initial[k] = pitch63 * fraction + pitch105 * (1 - fraction)
                }
            }
        }
        pitches = initial.map { Double(LogBin.roundToInt($0)) }
        progress(0.08)

        let highest = concertPitch * pow(2.0, Double(count - 1 - a4) / 12.0) * 1.13
        let lowerCutoff = 100
        let upperCutoff = min(LogBin.numberOfBins - 100, LogBin.roundToInt(LogBin.frequencyToRealIndex(highest)))
        var recordedPitch = [Int](repeating: 0, count: count)
        for k in 0..<count {
            let et = concertPitch * pow(2.0, Double(k - a4) / 12.0)
            recordedPitch[k] = LogBin.roundToInt(LogBin.cents(from: et, to: keys[k].frequency))
        }

        var pitch = initial.map { LogBin.roundToInt($0) }
        var accumulator = [Double](repeating: 0, count: LogBin.numberOfBins)
        let spectra = keys.map(\.spectrum)

        func element(_ spectrum: [Double], _ m: Int) -> Double {
            (m > lowerCutoff && m < upperCutoff && m >= 0 && m < spectrum.count) ? spectrum[m] : 0
        }

        func add(_ spectrum: [Double], shift: Int, intensity: Double) {
            accumulator.withUnsafeMutableBufferPointer { buffer in
                for m in 0..<LogBin.numberOfBins {
                    buffer[m] += element(spectrum, m - shift) * intensity
                    if buffer[m] < 0, buffer[m] > -1e-10 { buffer[m] = 0 }
                }
            }
        }

        func rebuild() {
            accumulator = [Double](repeating: 0, count: LogBin.numberOfBins)
            for k in 0..<count {
                add(spectra[k], shift: pitch[k] - recordedPitch[k], intensity: 1)
            }
        }

        func entropy() -> Double {
            MathTools.shannonEntropy(MathTools.normalized(accumulator))
        }

        rebuild()
        var h = entropy()
        progress(0.12)

        var generator = MT19937(seed: seed == 0 ? UInt64.random(in: 1...UInt64.max) : seed)
        let centsWidth = 20
        var attempts = 0
        var updatesSinceLastChange = 0
        var methodRatio = 1.0
        var lastProgress = 0.0
        var velocity = 0.0
        let steps = accuracy.stepsToFinish

        func tolerance(_ key: Int) -> Double {
            let a0 = 30.0, a2 = 15.0, a4t = 5.0, a6 = 15.0, a7 = 30.0
            let a1 = (-a0 + 8 * a2 - 7 * a4t) / 2304.0
            let b1 = (-a0 + 4 * a2 - 3 * a4t) / 55296.0
            let a2c = (-19 * a4t + 27 * a6 - 8 * a7) / 5184.0
            let b2 = (5 * a4t - 9 * a6 + 4 * a7) / 62208.0
            let d = Double(key - a4)
            let (aa, bb) = d < 0 ? (a1, b1) : (a2c, b2)
            return a4t + aa * d * d + bb * d * d * d
        }

        while !shouldCancel() {
            attempts += 1
            updatesSinceLastChange += 1
            if steps > 0 {
                var shown = Double(updatesSinceLastChange) / Double(steps)
                shown = max(shown, lastProgress)
                let acc = min(1, max(-1, shown - lastProgress))
                velocity = max(0, velocity + acc)
                shown = velocity * 0.001
                lastProgress = shown
                progress(min(0.99, 0.12 + 0.88 * shown))
                if shown > 1 { break }
            } else if attempts % 20 == 0 {
                progress(min(0.99, 0.12 + 0.5 * (1 - exp(-Double(attempts) / 8_000))))
            }

            var key = generator.uniformInt(count)
            var guardCount = 0
            while key == a4 && guardCount < 8 {
                key = generator.uniformInt(count)
                guardCount += 1
            }
            if key == a4 { continue }

            if generator.uniform01() > methodRatio {
                let old = pitch[key]
                let band = tolerance(key)
                var proposed = old
                var tries = 0
                repeat {
                    proposed = old + generator.binomial(n: centsWidth) - centsWidth / 2
                    tries += 1
                } while tries < 40 && proposed != old && abs(Double(old) - initial[key]) < band
                    && abs(Double(proposed) - initial[key]) > band
                if proposed == old { continue }
                add(spectra[key], shift: old - recordedPitch[key], intensity: -1)
                add(spectra[key], shift: proposed - recordedPitch[key], intensity: 1)
                pitch[key] = proposed
                let next = entropy()
                if next < h {
                    h = next
                    updatesSinceLastChange /= 2
                } else {
                    add(spectra[key], shift: proposed - recordedPitch[key], intensity: -1)
                    add(spectra[key], shift: old - recordedPitch[key], intensity: 1)
                    pitch[key] = old
                }
            } else {
                let saved = pitch
                let sign = generator.uniform01() < 0.5 ? 1 : -1
                if key < a4 {
                    for k in 0...key { pitch[k] += sign }
                } else {
                    for k in key..<count { pitch[k] += sign }
                }
                rebuild()
                let next = entropy()
                if next < h {
                    h = next
                    updatesSinceLastChange /= 2
                    methodRatio *= 0.995
                } else {
                    pitch = saved
                    rebuild()
                }
            }
        }

        pitches = pitch.map(Double.init)
        return TuningComputation(cents: pitches, entropy: h)
    }
}

struct MT19937 {
    private var state = [UInt32](repeating: 0, count: 624)
    private var index = 624

    init(seed: UInt64) {
        state[0] = UInt32(truncatingIfNeeded: seed)
        for i in 1..<624 {
            state[i] = 1_812_433_253 &* (state[i - 1] ^ (state[i - 1] >> 30)) &+ UInt32(i)
        }
    }

    mutating func nextUInt32() -> UInt32 {
        if index >= 624 {
            for i in 0..<624 {
                let y = (state[i] & 0x8000_0000) &+ (state[(i + 1) % 624] & 0x7fff_ffff)
                state[i] = state[(i + 397) % 624] ^ (y >> 1)
                if y & 1 == 1 { state[i] ^= 2_568_625_764 }
            }
            index = 0
        }
        var y = state[index]
        index += 1
        y ^= y >> 11
        y ^= (y << 7) & 2_636_928_640
        y ^= (y << 15) & 4_022_730_752
        y ^= y >> 18
        return y
    }

    mutating func uniform01() -> Double {
        Double(nextUInt32()) / 4_294_967_296.0
    }

    mutating func uniformInt(_ n: Int) -> Int {
        guard n > 0 else { return 0 }
        return Int(nextUInt32() % UInt32(n))
    }

    mutating func binomial(n: Int) -> Int {
        var sum = 0
        for _ in 0..<n where uniform01() < 0.5 { sum += 1 }
        return sum
    }
}
