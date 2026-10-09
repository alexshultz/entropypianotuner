import Foundation

/// One-cent logarithmic spectrum used by Entropy Piano Tuner.
/// Bin 0 is 20.601722 Hz and each bin is one cent, nine octaves in all.
enum LogBin {
    static let numberOfBins = 10_800
    static let binsPerOctave = 1_200.0
    static let fmin = 20.601722
    static let ln2 = 0.693147180559945309417

    static func frequencyToRealIndex(_ f: Double) -> Double {
        guard f > 0 else { return 0 }
        return binsPerOctave * (log(f) - log(fmin)) / ln2
    }

    static func frequencyToIndex(_ f: Double) -> Int {
        roundToInt(frequencyToRealIndex(f))
    }

    static func indexToFrequency(_ m: Double) -> Double {
        fmin * pow(2.0, m / binsPerOctave)
    }

    static func roundToInt(_ x: Double) -> Int {
        Int(x >= 0 ? floor(x + 0.5) : ceil(x - 0.5))
    }

    static func cents(from: Double, to: Double) -> Double {
        guard from > 0, to > 0 else { return 0 }
        return 1_200.0 * log(to / from) / ln2
    }
}
