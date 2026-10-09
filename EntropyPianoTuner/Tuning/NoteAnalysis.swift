import Accelerate
import Foundation

struct LinearSpectrum {
    var magnitudes: [Double]
    var sampleRate: Double
    var fftSize: Int

    /// Bin index of a frequency. `magnitudes` holds the positive half of a complex FFT.
    var binScale: Double { Double(fftSize) / sampleRate }

    func frequency(ofBin q: Int) -> Double {
        Double(q) / binScale
    }
}

enum SpectrumFFT {
    static func magnitudes(samples: [Float], sampleRate: Double) -> LinearSpectrum? {
        let size = 1 << Int(floor(log2(Double(samples.count))))
        guard size >= 4_096 else { return nil }
        var windowed = Array(samples.prefix(size))
        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        vDSP_vmul(windowed, 1, window, 1, &windowed, 1, vDSP_Length(size))

        let log2n = vDSP_Length(log2(Double(size)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        var real = windowed
        var imag = [Float](repeating: 0, count: size)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }

        let half = size / 2
        var mags = [Double](repeating: 0, count: half)
        for i in 0..<half {
            mags[i] = Double(hypot(real[i], imag[i]))
        }
        return LinearSpectrum(magnitudes: mags, sampleRate: sampleRate, fftSize: size)
    }

    static func logSpectrum(from linear: LinearSpectrum) -> [Double] {
        var spectrum = [Double](repeating: 0, count: LogBin.numberOfBins)
        let b = linear.binScale
        MathTools.coarseGrainSpectrum(linear.magnitudes, into: &spectrum, map: { m in
            b * LogBin.indexToFrequency(m)
        }, exponent: 0.25)
        MathTools.normalize(&spectrum)
        return spectrum
    }
}

enum NoteAnalysis {
    static func expectedInharmonicity(_ f: Double) -> Double {
        f > 100 ? exp(-15.45 + 1.354 * log(f)) : 0.000099575
    }

    static func inharmonicPartial(_ n: Double, f1: Double, b: Double) -> Double {
        f1 * n * sqrt((1 + b * n * n) / (1 + b))
    }

    static func inharmonicIndex(_ f: Double, f1: Double, b: Double) -> Double {
        let x = f / f1
        if b == 0 { return x }
        return 0.7071067811865475 * sqrt((-1 + sqrt(1 + 4 * b * (1 + b) * x * x)) / b)
    }

    /// Rough expected frequency of a key, including an average stretch curve.
    static func estimateFrequency(key: Int, concertPitch: Double, a4: Int) -> Double {
        let d = Double(key - a4)
        let c = 0.000019394 + 0.079694594 * d - 0.003718646 * d * d
            + 0.000450934 * d * d * d + 0.000003724 * d * d * d * d
        return pow(2.0, d / 12.0 + c / 1_200.0) * concertPitch
    }

    static func locatePeak(_ spectrum: [Double], around m: Int, width: Int) -> Int {
        guard spectrum.count == LogBin.numberOfBins else { return 0 }
        if m < width || m > LogBin.numberOfBins - width { return 0 }
        return MathTools.findMaximum(spectrum, from: m - width, to: m + width)
    }

    static func findAccuratePeak(_ linear: LinearSpectrum, around f: Double, cents: Int = 15) -> Double {
        let factor = 1.0 + 0.000577623 * Double(cents)
        let b = linear.binScale
        let q1 = LogBin.roundToInt(b * f / factor)
        let q2 = LogBin.roundToInt(b * f * factor)
        guard q1 > 0, q2 < linear.magnitudes.count, q1 < q2 else { return f }
        var best = q1
        var bestValue = 0.0
        for q in q1..<q2 where linear.magnitudes[q] > bestValue {
            bestValue = linear.magnitudes[q]
            best = q
        }
        return Double(best) / b
    }

    struct Recording {
        var frequency: Double
        var inharmonicity: Double
        var quality: Double
        var spectrum: [Double]
    }

    static func analyze(samples: [Float], sampleRate: Double, key: Int, concertPitch: Double, a4: Int) -> Recording? {
        guard let linear = SpectrumFFT.magnitudes(samples: samples, sampleRate: sampleRate) else { return nil }
        return analyze(linear: linear, key: key, concertPitch: concertPitch, a4: a4)
    }

    static func analyze(linear: LinearSpectrum, key: Int, concertPitch: Double, a4: Int) -> Recording? {
        let spectrum = SpectrumFFT.logSpectrum(from: linear)
        let distance = a4 - key
        let octaves = distance > 36 ? 2 : (distance > 24 ? 1 : 0)
        let factor = pow(2.0, Double(octaves))
        let guess = factor * estimateFrequency(key: key, concertPitch: concertPitch, a4: a4)
        let peak = locatePeak(spectrum, around: LogBin.frequencyToIndex(guess), width: 40)
        guard peak > 0 else { return nil }
        var frequency = LogBin.indexToFrequency(Double(peak)) / factor
        guard frequency > 20, frequency < 6_000 else { return nil }

        let fit = estimateInharmonicity(linear: linear, spectrum: spectrum, f: frequency)
        let accurate = findAccuratePeak(linear, around: factor * frequency, cents: 15)
        frequency = accurate / factor / sqrt((1 + fit.b * factor * factor) / (1 + fit.b))
        guard frequency > 20, frequency < 6_000 else { return nil }

        var quality = 0.0
        if frequency < 2_200 {
            quality = estimateQuality(fit.superposition)
        }
        return Recording(frequency: frequency, inharmonicity: fit.b, quality: quality, spectrum: spectrum)
    }

    struct InharmonicityFit {
        var b: Double
        var superposition: [Double]
    }

    static func estimateInharmonicity(linear: LinearSpectrum, spectrum: [Double], f: Double) -> InharmonicityFit {
        if spectrum.isEmpty || f < 20 || f > 2_250 {
            return InharmonicityFit(b: 0, superposition: [])
        }
        if f > 1_000 {
            let f2 = findAccuratePeak(linear, around: 2.0174 * f, cents: 15)
            let z = f2 * f2 / f / f
            if z > 4.4 || z < 4 { return InharmonicityFit(b: 0, superposition: []) }
            return InharmonicityFit(b: (4 - z) / (z - 16), superposition: [])
        }

        let nPartials = LogBin.roundToInt(4 * (8 - log(f)))
        let expected = expectedInharmonicity(f)
        let radius = 80
        var bestB = 0.0
        var bestH = Double.greatestFiniteMagnitude
        var bestShape: [Double] = []
        var scan = expected / 5
        while scan <= expected * 5 {
            var superposition = [Double](repeating: 0, count: radius)
            for n in 1...max(1, nPartials) {
                let fn = Double(n) * f * sqrt((1 + scan * Double(n * n)) / (1 + scan))
                let mn = LogBin.frequencyToRealIndex(fn)
                guard mn - Double(radius) / 2 > 0, mn + Double(radius) / 2 < Double(LogBin.numberOfBins) else { continue }
                var partial = [Double](repeating: 0, count: radius)
                for r in 0..<radius {
                    let m = Int(mn) + r - radius / 2
                    if m >= 0, m < spectrum.count { partial[r] = spectrum[m] * spectrum[m] }
                }
                MathTools.normalize(&partial)
                for r in 0..<radius { superposition[r] += partial[r] }
            }
            MathTools.normalize(&superposition)
            let h = abs(MathTools.renyiEntropy(superposition, q: 0.1))
            if h < bestH {
                bestH = h
                bestB = scan
                bestShape = superposition
            }
            scan *= 1.03
        }
        return InharmonicityFit(b: bestB, superposition: bestShape)
    }

    static func estimateQuality(_ superposition: [Double]) -> Double {
        guard superposition.count > 24 else { return 0 }
        let cut = superposition.count / 2 - 10
        var vec = Array(superposition[cut..<(superposition.count - cut)])
        let kept = MathTools.norm(vec)
        guard kept > 0 else { return 0 }
        MathTools.normalize(&vec)
        let m1 = MathTools.moment(vec, n: 1)
        let m2 = MathTools.moment(vec, n: 2)
        let variance = m2 - m1 * m1
        return kept / (1 + 0.1 * pow(max(variance, 0), 1.5))
    }

    /// Cents by which the sounding partial sits above its target.
    static func deviationCents(linear: LinearSpectrum, fundamentalTarget: Double, inharmonicity: Double, key: Int, a4: Int) -> Double? {
        guard fundamentalTarget > 20 else { return nil }
        let distance = a4 - key
        let partial: Double = distance > 36 ? 4 : (distance > 24 ? 2 : 1)
        let target = inharmonicPartial(partial, f1: fundamentalTarget, b: inharmonicity)
        let spectrum = SpectrumFFT.logSpectrum(from: linear)
        let center = LogBin.frequencyToIndex(target)
        let peak = locatePeak(spectrum, around: center, width: 80)
        guard peak > 0 else { return nil }
        let detected = findAccuratePeak(linear, around: LogBin.indexToFrequency(Double(peak)), cents: 20)
        return LogBin.cents(from: target, to: detected)
    }
}
