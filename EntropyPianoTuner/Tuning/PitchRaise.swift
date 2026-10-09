import Foundation

/// The original pitch-raise curve: a partial-matching stretch from the measured inharmonicity,
/// without the Monte Carlo search. Useful as a first pass when a piano is far from pitch.
enum PitchRaise {
    static func compute(inharmonicities: [Double], a4: Int, bassBreak: Int) -> [Double]? {
        let count = inharmonicities.count
        guard a4 > 13, count - a4 > 13 else { return nil }
        var x = [0.0, 0.0]
        var y = [0.0, 0.0]
        var xx = [0.0, 0.0]
        var xy = [0.0, 0.0]
        var n = [0.0, 0.0]
        for i in 0..<count where inharmonicities[i] > 1e-10 {
            let section = i < bassBreak ? 0 : 1
            let xi = Double(i)
            let yi = -log(inharmonicities[i])
            n[section] += 1
            x[section] += xi
            y[section] += yi
            xx[section] += xi * xi
            xy[section] += xi * yi
        }
        guard n[0] >= 2, n[1] >= 2 else { return nil }
        var intercept = [0.0, 0.0]
        var slope = [0.0, 0.0]
        for s in 0...1 {
            let denom = n[s] * xx[s] - x[s] * x[s]
            guard denom != 0 else { return nil }
            intercept[s] = (xx[s] * y[s] - x[s] * xy[s]) / denom
            slope[s] = (n[s] * xy[s] - x[s] * y[s]) / denom
        }
        func estimatedB(_ k: Int) -> Double {
            let s = k < bassBreak ? 0 : 1
            return exp(-(intercept[s] + Double(k) * slope[s]))
        }
        func cents(_ key: Int, _ partial: Int) -> Double {
            let b = estimatedB(key)
            return 600.0 / LogBin.ln2 * log((1 + Double(partial * partial) * b) / (1 + b))
        }

        var pitch = [Double](repeating: 0, count: count)
        let a3 = a4 - 12
        let a5 = a4 + 12
        let pitchA5 = 0.5 * cents(a4, 3) + 0.5 * cents(a4, 2)
        let pitchA3 = cents(a4, 2) - cents(a3, 4)
        for k in a3..<a4 { pitch[k] = pitchA3 * Double(a4 - k) / 12.0 }
        for k in (a4 + 1)...a5 { pitch[k] = pitchA5 * Double(k - a4) / 12.0 }
        if a5 + 1 < count {
            for k in (a5 + 1)..<count {
                let pitch42 = pitch[k - 12] + cents(k - 12, 4) - cents(k, 2)
                let pitch21 = pitch[k - 12] + cents(k - 12, 2)
                pitch[k] = 0.3 * pitch42 + 0.7 * pitch21
            }
        }
        if a3 > 0 {
            for k in stride(from: a3 - 1, through: 0, by: -1) {
                let pitch42 = pitch[k + 12] + cents(k + 12, 2) - cents(k, 4)
                let pitch105 = pitch[k + 12] + cents(k + 12, 5) - cents(k, 10)
                let fraction = Double(k) / Double(a3)
                pitch[k] = pitch42 * fraction + pitch105 * (1 - fraction)
            }
        }
        return pitch
    }
}
