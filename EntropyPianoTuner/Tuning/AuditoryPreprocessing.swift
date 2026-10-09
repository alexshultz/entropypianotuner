import Foundation

/// Prepares recorded log spectra the way Entropy Piano Tuner does before the search.
enum AuditoryPreprocessing {
    struct PreparedKey {
        var spectrum: [Double]
        var frequency: Double
        var inharmonicity: Double
    }

    enum Failure: Error, CustomStringConvertible {
        case noData
        case missingKeys(Int)
        case inconsistent(String)

        var description: String {
            switch self {
            case .noData: return "Record the piano before calculating a tuning."
            case .missingKeys(let n): return "\(n) keys still need a recording."
            case .inconsistent(let message): return message
            }
        }
    }

    static func prepare(spectra: [[Double]], frequencies: [Double], inharmonicities: [Double], a4: Int) throws -> [PreparedKey] {
        let count = frequencies.count
        guard count > 0, spectra.count == count, inharmonicities.count == count else {
            throw Failure.inconsistent("The recording is incomplete.")
        }
        var recorded = 0
        for (spectrum, frequency) in zip(spectra, frequencies) {
            if spectrum.count == LogBin.numberOfBins, frequency > 0 { recorded += 1 }
        }
        if recorded == 0 { throw Failure.noData }
        if recorded != count { throw Failure.missingKeys(count - recorded) }

        var keys: [PreparedKey] = []
        keys.reserveCapacity(count)
        for i in 0..<count {
            let f = frequencies[i]
            let b = inharmonicities[i]
            if f < 20 || f > 20_000 {
                throw Failure.inconsistent("Key \(i + 1) was recorded at an impossible pitch.")
            }
            if b < 0 || b > 1 {
                throw Failure.inconsistent("Key \(i + 1) has an impossible inharmonicity.")
            }
            var spectrum = spectra[i]
            if MathTools.norm(spectrum) == 0 {
                throw Failure.inconsistent("Key \(i + 1) has a silent recording.")
            }
            MathTools.normalize(&spectrum)
            clean(&spectrum, frequency: f, inharmonicity: b)
            cutLow(&spectrum, frequency: f)
            keys.append(PreparedKey(spectrum: spectrum, frequency: f, inharmonicity: b))
        }

        let weights = splaWeights()
        for i in keys.indices {
            applySPLA(&keys[i].spectrum, weights: weights)
        }
        _ = weights

        var bs = keys.map(\.inharmonicity)
        extrapolateInharmonicity(&bs, frequencies: frequencies, a4: a4)
        for i in keys.indices { keys[i].inharmonicity = bs[i] }
        improveHighFrequencyPeaks(&keys, a4: a4)
        for i in keys.indices { mollify(&keys[i].spectrum) }
        return keys
    }

    private static func clean(_ spectrum: inout [Double], frequency f: Double, inharmonicity b: Double) {
        for m in spectrum.indices {
            let hz = LogBin.indexToFrequency(Double(m))
            let wave = cos(Double.pi * NoteAnalysis.inharmonicIndex(hz, f1: f, b: b))
            let exponent = 200.0 / pow(max(hz / f, 1e-6), 1.5)
            spectrum[m] *= pow(abs(wave), exponent)
        }
    }

    private static func cutLow(_ spectrum: inout [Double], frequency f: Double) {
        let low = min(Int(5 * LogBin.frequencyToRealIndex(f)) / 6, LogBin.numberOfBins)
        if low > 0 { spectrum.replaceSubrange(0..<low, with: repeatElement(0, count: low)) }
    }

    private static func splaWeights() -> [Double] {
        (0..<LogBin.numberOfBins).map { m in
            let f = LogBin.indexToFrequency(Double(m))
            let f2 = f * f
            let ra = 12200.0 * 12200.0 * f2 * f2 / (f2 + 20.6 * 20.6)
                / sqrt((f2 + 107.7 * 107.7) * (f2 + 737.9 * 737.9))
                / (f2 + 12200.0 * 12200.0)
            return 2.0 + 20 * log10(max(ra, 1e-30))
        }
    }

    private static func applySPLA(_ spectrum: inout [Double], weights: [Double]) {
        let i0 = 1e-7
        for m in spectrum.indices {
            let spla = 10 * log10(max(spectrum[m], 0) / i0 + 1e-30) + weights[m]
            if spla < 0 || spectrum[m] <= 0 {
                spectrum[m] = 0
            } else {
                spectrum[m] = i0 * pow(10.0, spla / 10.0)
            }
        }
    }

    private static func extrapolateInharmonicity(_ bs: inout [Double], frequencies: [Double], a4: Int) {
        let first = max(0, a4 - 8)
        var kSum = 0.0, ySum = 0.0, kk = 0.0, ky = 0.0, n = 0.0, estimate = 0.0
        for k in first..<bs.count {
            if n > 1 {
                let denom = n * kk - kSum * kSum
                if denom != 0 {
                    let a = (n * ky - kSum * ySum) / denom
                    let b = (kk * ySum - kSum * ky) / denom
                    estimate = exp(a * Double(k) + b)
                }
            }
            let value = bs[k]
            var valid = value > 0
            if value > 0, estimate > 0, n > 5, abs(log(value / estimate)) > 0.2 {
                valid = false
            }
            if valid {
                let y = log(value)
                kSum += Double(k)
                ySum += y
                kk += Double(k * k)
                ky += Double(k) * y
                n += 1
            } else {
                if estimate == 0 {
                    estimate = NoteAnalysis.expectedInharmonicity(frequencies[k])
                }
                bs[k] = estimate
            }
        }
    }

    private static func improveHighFrequencyPeaks(_ keys: inout [PreparedKey], a4: Int) {
        guard a4 < keys.count else { return }
        for k in a4..<keys.count {
            let f = keys[k].frequency
            let b = keys[k].inharmonicity
            guard f > 0, b > 0 else { continue }
            let m = LogBin.roundToInt(LogBin.frequencyToRealIndex(f))
            guard m >= 0, m < LogBin.numberOfBins else { continue }
            let factor = Double(k - a4) / Double(keys.count - a4)
            let intensity = keys[k].spectrum[m] * factor
            for n in 2...6 {
                let fn = NoteAnalysis.inharmonicPartial(Double(n), f1: f, b: b)
                if fn < 20 || fn > 10_000 { continue }
                let mn = LogBin.roundToInt(LogBin.frequencyToRealIndex(fn))
                for i in (mn - 10)...(mn + 10) where i >= 0 && i < LogBin.numberOfBins {
                    keys[k].spectrum[i] = intensity * pow(4, Double(-n)) * exp(-0.1 * Double((i - mn) * (i - mn)))
                }
            }
        }
    }

    private static func mollify(_ spectrum: inout [Double]) {
        let copy = spectrum
        let count = spectrum.count
        for m in 0..<count {
            let f = LogBin.indexToFrequency(Double(m))
            let df = 55.0 / f + f / 2_000.0
            let dm = max(1, LogBin.roundToInt(LogBin.frequencyToRealIndex(f + df)) - m)
            let lo = max(1, m - 3 * dm)
            let hi = min(m + 3 * dm, count - 1)
            var sum = 0.0
            var weightSum = 0.0
            let dm2 = Double(dm * dm)
            for ms in lo...hi {
                let weight = exp(-1.0 * Double((ms - m) * (ms - m)) / dm2)
                weightSum += weight
                sum += copy[ms] * weight
            }
            if weightSum > 0 { spectrum[m] = sum / weightSum }
        }
    }
}
