import Foundation

enum PianoLayout {
    static let keyCount = 88
    static let a4 = 48
    static let names = ["A", "A♯", "B", "C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯"]

    static func isBlack(_ index: Int) -> Bool {
        let n = index % 12
        return n == 1 || n == 4 || n == 6 || n == 9 || n == 11
    }

    static func label(_ index: Int) -> String {
        let name = names[index % 12]
        let octave = index < 3 ? 0 : (index - 3) / 12 + 1
        return "\(name)\(octave)"
    }

    static func frequency(key: Int, cents: Double, concertPitch: Double) -> Double {
        concertPitch * pow(2.0, (Double(key - a4) + cents / 100.0) / 12.0)
    }
}

struct KeyMeasurement: Codable, Equatable {
    var recorded = false
    var frequency = 0.0
    var inharmonicity = 0.0
    var quality = 0.0
    var tuned = false
}

struct Piano: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var concertPitch: Double
    var bassBreak: Int
    var keys: [KeyMeasurement]
    var tuningCents: [Double]?
    var entropy: Double?
    var tuningConcertPitch: Double?
    var updated: Date

    var recordedCount: Int { keys.filter(\.recorded).count }
    var tuningIsCurrent: Bool {
        tuningCents != nil && tuningConcertPitch == concertPitch
    }

    static func make(name: String) -> Piano {
        Piano(
            id: UUID(),
            name: name,
            concertPitch: 440,
            bassBreak: 27,
            keys: Array(repeating: KeyMeasurement(), count: PianoLayout.keyCount),
            tuningCents: nil,
            entropy: nil,
            tuningConcertPitch: nil,
            updated: Date()
        )
    }

    func targetFrequency(for key: Int) -> Double? {
        guard let tuningCents, key >= 0, key < tuningCents.count else { return nil }
        return PianoLayout.frequency(key: key, cents: tuningCents[key], concertPitch: concertPitch)
    }
}


