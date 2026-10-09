import Foundation

enum MathTools {
    static func norm(_ v: [Double]) -> Double {
        v.reduce(0, +)
    }

    static func normalize(_ v: inout [Double]) {
        let n = norm(v)
        guard n != 0 else { return }
        for i in v.indices { v[i] /= n }
    }

    static func normalized(_ v: [Double]) -> [Double] {
        var copy = v
        normalize(&copy)
        return copy
    }

    /// Shannon entropy. 0 log 0 is taken as 0. `v` must already be normalized.
    static func shannonEntropy(_ v: [Double]) -> Double {
        var sum = 0.0
        for x in v where x > 0 {
            sum -= x * log(x)
        }
        return sum
    }

    /// Rényi entropy. `q` near 0 emphasizes the support of the distribution.
    static func renyiEntropy(_ v: [Double], q: Double) -> Double {
        if q == 1 { return shannonEntropy(v) }
        var sum = 0.0
        for x in v where x > 0 {
            sum += pow(x, q)
        }
        guard sum > 0 else { return 0 }
        return log(sum) / (1 - q)
    }

    static func moment(_ v: [Double], n: Int) -> Double {
        var weight = 0.0
        var sum = 0.0
        for (i, x) in v.enumerated() {
            weight += x
            sum += x * pow(Double(i), Double(n))
        }
        guard weight > 0 else { return 0 }
        return sum / weight
    }

    static func findMaximum(_ x: [Double], from i: Int, to j: Int) -> Int {
        let lo = max(0, i)
        let hi = min(x.count, j)
        guard lo < hi else { return lo }
        var best = lo
        var bestValue = x[lo]
        for k in (lo + 1)..<hi where x[k] > bestValue {
            best = k
            bestValue = x[k]
        }
        return best
    }

    /// Map a linear magnitude spectrum onto a log-frequency grid.
    /// `f` converts a log-bin index to a linear-bin index. Ported from MathTools::coarseGrainSpectrum.
    static func coarseGrainSpectrum(_ x: [Double], into y: inout [Double], map f: (Double) -> Double, exponent: Double) {
        guard !x.isEmpty, !y.isEmpty else { return }
        var xs1 = f(-0.5)
        var x1 = max(0, LogBin.roundToInt(xs1))
        if x1 >= x.count { x1 = x.count - 1 }
        var leftArea = (Double(x1) - xs1 + 0.5) * x[x1]
        for yi in y.indices {
            let xs2 = f(Double(yi) + 0.5)
            var x2 = LogBin.roundToInt(xs2)
            if x2 >= x.count { x2 = x.count - 1 }
            if x2 < 0 { x2 = 0 }
            var sum = 0.0
            if x2 >= x1 + 1 {
                for xi in (x1 + 1)...x2 { sum += x[xi] }
            }
            let rightArea = (Double(x2) - xs2 + 0.5) * x[x2]
            let weight = pow(max(xs1 * xs2, 0), exponent)
            let value = (sum + leftArea - rightArea) * weight
            y[yi] = value > 0 ? value : 0
            x1 = x2
            xs1 = xs2
            leftArea = rightArea
        }
    }
}
