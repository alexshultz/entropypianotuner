import Foundation

func fail(_ message: String) -> Never {
    fputs("FAIL \(message)\n", stderr)
    exit(1)
}

let rate = 48_000.0
let count = 65_536
var samples = [Float](repeating: 0, count: count)
let tone = 440.0
for i in 0..<count {
    samples[i] = sin(2 * .pi * Float(tone) * Float(i) / Float(rate))
}
guard let linear = SpectrumFFT.magnitudes(samples: samples, sampleRate: rate) else {
    fail("fft")
}
let bin = Int((tone * Double(linear.fftSize) / rate).rounded())
let peak = linear.magnitudes.enumerated().max(by: { $0.element < $1.element })?.offset ?? -1
if abs(peak - bin) > 2 {
    fail("sine peak at \(peak), expected \(bin)")
}
print("sine peak bin \(peak) expected \(bin)")

let delta = [0.0, 0.0, 1.0, 0.0]
if abs(MathTools.shannonEntropy(delta)) > 1e-9 { fail("entropy of a spike") }

func spectrum(f1: Double, b: Double) -> [Double] {
    var row = [Double](repeating: 0, count: LogBin.numberOfBins)
    for n in 1...18 {
        let fn = NoteAnalysis.inharmonicPartial(Double(n), f1: f1, b: b)
        guard fn < 10_000 else { continue }
        let center = LogBin.frequencyToRealIndex(fn)
        let amp = 1.0 / Double(n)
        for m in 0..<LogBin.numberOfBins {
            let d = Double(m) - center
            if abs(d) < 8 { row[m] += amp * exp(-0.5 * d * d) }
        }
    }
    MathTools.normalize(&row)
    return row
}

let keys = PianoLayout.keyCount
var spectra: [[Double]] = []
var frequencies: [Double] = []
var bs: [Double] = []
for key in 0..<keys {
    let f = PianoLayout.frequency(key: key, cents: 0, concertPitch: 440)
    let b = NoteAnalysis.expectedInharmonicity(f)
    frequencies.append(f)
    bs.append(b)
    spectra.append(spectrum(f1: f, b: b))
}

let prepared: [AuditoryPreprocessing.PreparedKey]
do {
    prepared = try AuditoryPreprocessing.prepare(spectra: spectra, frequencies: frequencies, inharmonicities: bs, a4: PianoLayout.a4)
} catch {
    fail("prepare \(error)")
}
print("prepared \(prepared.count) keys")

let result = EntropyMinimizer.compute(
    keys: prepared,
    a4: PianoLayout.a4,
    concertPitch: 440,
    accuracy: .low,
    seed: 1,
    shouldCancel: { false },
    progress: { _ in }
)
if result.cents.count != keys { fail("cent count") }
if result.cents[PianoLayout.a4] != 0 { fail("A4 moved to \(result.cents[PianoLayout.a4])") }
if !result.entropy.isFinite || result.entropy <= 0 { fail("entropy \(result.entropy)") }
let bass = result.cents[0..<20].reduce(0, +) / 20
let treble = result.cents[70..<88].reduce(0, +) / 18
print(String(format: "entropy %.4f  bass %+.1f  treble %+.1f  A0 %+.1f  C8 %+.1f", result.entropy, bass, treble, result.cents[0], result.cents[87]))
if treble <= bass { fail("treble is not sharper than the bass") }
if treble < 2 { fail("treble stretch too small") }
if bass > -2 { fail("bass stretch too small") }

guard let raised = PitchRaise.compute(inharmonicities: prepared.map(\.inharmonicity), a4: PianoLayout.a4, bassBreak: 27) else {
    fail("pitch raise")
}
if raised[PianoLayout.a4] != 0 { fail("pitch raise moved A4") }
print(String(format: "pitch raise A0 %+.1f C8 %+.1f", raised[0], raised[87]))
print("OK")
