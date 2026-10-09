import Foundation
import SwiftData

/// Private iCloud database for this app. The entitlements file is on the target
/// now that team N8D3Z8U4Y9 is a paid Developer Program membership.
enum PianoCloud {
    static let containerIdentifier = "iCloud.com.alex.entropypianotuner"
    static let storeName = "EntropyPianoTuner"
    static let legacyImportedKey = "EntropyPianoTuner.legacyLibraryImported"
}

@Model
final class PianoRecord {
    var pianoID: String = ""
    var name: String = ""
    var concertPitch: Double = 440
    var bassBreak: Int = 27
    var tuningCents: Data = Data()
    var entropy: Double? = nil
    var tuningConcertPitch: Double? = nil
    var modifiedAt: Date = Date.distantPast

    init(
        pianoID: String,
        name: String,
        concertPitch: Double,
        bassBreak: Int,
        tuningCents: Data,
        entropy: Double?,
        tuningConcertPitch: Double?,
        modifiedAt: Date
    ) {
        self.pianoID = pianoID
        self.name = name
        self.concertPitch = concertPitch
        self.bassBreak = bassBreak
        self.tuningCents = tuningCents
        self.entropy = entropy
        self.tuningConcertPitch = tuningConcertPitch
        self.modifiedAt = modifiedAt
    }

    @MainActor
    static func reconcile(in context: ModelContext) -> Bool {
        let records = (try? context.fetch(FetchDescriptor<PianoRecord>())) ?? []
        return deleteLosers(Dictionary(grouping: records, by: \.pianoID), in: context)
    }

    fileprivate static func prefer(_ lhs: PianoRecord, over rhs: PianoRecord) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return String(describing: lhs.persistentModelID) > String(describing: rhs.persistentModelID)
    }
}

@Model
final class KeySpectrumRecord {
    var keyID: String = ""
    var pianoID: String = ""
    var keyIndex: Int = 0
    var recorded: Bool = false
    var frequency: Double = 0
    var inharmonicity: Double = 0
    var quality: Double = 0
    var tuned: Bool = false
    @Attribute(.externalStorage) var spectrum: Data = Data()
    var modifiedAt: Date = Date.distantPast

    init(
        keyID: String,
        pianoID: String,
        keyIndex: Int,
        measurement: KeyMeasurement,
        spectrum: Data,
        modifiedAt: Date
    ) {
        self.keyID = keyID
        self.pianoID = pianoID
        self.keyIndex = keyIndex
        self.recorded = measurement.recorded
        self.frequency = measurement.frequency
        self.inharmonicity = measurement.inharmonicity
        self.quality = measurement.quality
        self.tuned = measurement.tuned
        self.spectrum = spectrum
        self.modifiedAt = modifiedAt
    }

    var measurement: KeyMeasurement {
        KeyMeasurement(
            recorded: recorded,
            frequency: frequency,
            inharmonicity: inharmonicity,
            quality: quality,
            tuned: tuned
        )
    }

    @MainActor
    static func reconcile(in context: ModelContext) -> Bool {
        let records = (try? context.fetch(FetchDescriptor<KeySpectrumRecord>())) ?? []
        return deleteLosers(Dictionary(grouping: records, by: \.keyID), in: context)
    }

    fileprivate static func prefer(_ lhs: KeySpectrumRecord, over rhs: KeySpectrumRecord) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return String(describing: lhs.persistentModelID) > String(describing: rhs.persistentModelID)
    }
}

@MainActor
enum PianoStore {
    static var syncsWithICloud = false
    private static var container: ModelContainer?
    private static var context: ModelContext?
    private static var prepared = false

    static func prepare() {
        guard !prepared else { return }
        prepared = true
        let schema = Schema([PianoRecord.self, KeySpectrumRecord.self])
        let opened = makeContainer(schema: schema)
        let context = opened.container.mainContext
        context.autosaveEnabled = false
        container = opened.container
        self.context = context
        syncsWithICloud = opened.syncing
        importLegacyLibrary()
        reconcile()
    }

    static func list() -> [Piano] {
        prepare()
        guard let context else { return [] }
        reconcile()
        let records = (try? context.fetch(FetchDescriptor<PianoRecord>())) ?? []
        let winners = Dictionary(grouping: records, by: \.pianoID).compactMap { $0.value.max(by: { !PianoRecord.prefer($0, over: $1) }) }
        return winners.map { piano(from: $0) }.sorted { $0.updated > $1.updated }
    }

    static func load(_ id: UUID) -> (Piano, [[Double]])? {
        prepare()
        guard let context else { return nil }
        reconcile()
        let pianoID = id.uuidString
        let records = ((try? context.fetch(FetchDescriptor<PianoRecord>())) ?? []).filter { $0.pianoID == pianoID }
        guard let record = records.max(by: { !PianoRecord.prefer($0, over: $1) }) else { return nil }
        let keys = ((try? context.fetch(FetchDescriptor<KeySpectrumRecord>())) ?? []).filter { $0.pianoID == pianoID }
        return (piano(from: record, keys: keys), spectra(from: keys))
    }

    static func save(_ piano: Piano, spectra: [[Double]]) {
        prepare()
        guard let context else { return }
        reconcile()
        let pianoID = piano.id.uuidString
        let records = ((try? context.fetch(FetchDescriptor<PianoRecord>())) ?? []).filter { $0.pianoID == pianoID }
        let record = records.max(by: { !PianoRecord.prefer($0, over: $1) }) ?? PianoRecord(
            pianoID: pianoID,
            name: piano.name,
            concertPitch: piano.concertPitch,
            bassBreak: piano.bassBreak,
            tuningCents: Data(),
            entropy: nil,
            tuningConcertPitch: nil,
            modifiedAt: piano.updated
        )
        if records.isEmpty { context.insert(record) }
        record.name = piano.name
        record.concertPitch = piano.concertPitch
        record.bassBreak = piano.bassBreak
        record.tuningCents = SpectrumCodec.centsData(piano.tuningCents)
        record.entropy = piano.entropy
        record.tuningConcertPitch = piano.tuningConcertPitch
        record.modifiedAt = piano.updated

        var existing = Dictionary(grouping: ((try? context.fetch(FetchDescriptor<KeySpectrumRecord>())) ?? []).filter { $0.pianoID == pianoID }, by: \.keyIndex)
        for index in 0..<PianoLayout.keyCount {
            let measurement = index < piano.keys.count ? piano.keys[index] : KeyMeasurement()
            let row = index < spectra.count ? spectra[index] : []
            let spectrum = SpectrumCodec.spectrumData(row)
            let keyID = "\(pianoID)-\(index)"
            if let kept = existing[index]?.max(by: { !KeySpectrumRecord.prefer($0, over: $1) }) {
                let changed = kept.measurement != measurement || kept.spectrum != spectrum
                if changed {
                    kept.recorded = measurement.recorded
                    kept.frequency = measurement.frequency
                    kept.inharmonicity = measurement.inharmonicity
                    kept.quality = measurement.quality
                    kept.tuned = measurement.tuned
                    kept.spectrum = spectrum
                    kept.modifiedAt = piano.updated
                }
            } else {
                context.insert(KeySpectrumRecord(
                    keyID: keyID,
                    pianoID: pianoID,
                    keyIndex: index,
                    measurement: measurement,
                    spectrum: spectrum,
                    modifiedAt: piano.updated
                ))
            }
            existing[index] = nil
        }
        try? context.save()
    }

    static func delete(_ id: UUID) {
        prepare()
        guard let context else { return }
        let pianoID = id.uuidString
        for record in (try? context.fetch(FetchDescriptor<PianoRecord>())) ?? [] where record.pianoID == pianoID {
            context.delete(record)
        }
        for record in (try? context.fetch(FetchDescriptor<KeySpectrumRecord>())) ?? [] where record.pianoID == pianoID {
            context.delete(record)
        }
        try? context.save()
    }

    static func reconcile() {
        guard let context else { return }
        let removed = PianoRecord.reconcile(in: context) || KeySpectrumRecord.reconcile(in: context)
        if removed { try? context.save() }
    }

    static func watchContext() -> ModelContext? {
        prepare()
        return context
    }

    private static func makeContainer(schema: Schema) -> (container: ModelContainer, syncing: Bool) {
        let url = root().appendingPathComponent("\(storeName).store")
        let cloud = ModelConfiguration(
            storeName,
            schema: schema,
            url: url,
            cloudKitDatabase: .private(PianoCloud.containerIdentifier)
        )
        if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
            return (container, true)
        }
        let local = ModelConfiguration(
            storeName,
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        do {
            return (try ModelContainer(for: schema, configurations: [local]), false)
        } catch {
            fatalError("Entropy Piano Tuner could not open its library. \(error.localizedDescription)")
        }
    }

    private static var storeName: String { PianoCloud.storeName }

    private static func importLegacyLibrary() {
        guard let context else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: PianoCloud.legacyImportedKey) else { return }
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root(),
            includingPropertiesForKeys: nil
        )) ?? []
        let known = Set(((try? context.fetch(FetchDescriptor<PianoRecord>())) ?? []).map(\.pianoID))
        for folder in folders {
            let note = folder.appendingPathComponent("piano.json")
            guard let piano = SpectrumCodec.loadPiano(at: note), !known.contains(piano.id.uuidString) else { continue }
            let stamped = fileDate(note)
            var imported = piano
            imported.updated = stamped
            let spectra = SpectrumCodec.loadSpectra(at: folder.appendingPathComponent("spectra.bin"))
            save(imported, spectra: spectra)
        }
        defaults.set(true, forKey: PianoCloud.legacyImportedKey)
    }

    private static func root() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("EntropyPianoTuner", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func fileDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func piano(from record: PianoRecord, keys: [KeySpectrumRecord]? = nil) -> Piano {
        var measurements = Array(repeating: KeyMeasurement(), count: PianoLayout.keyCount)
        if let keys {
            for (index, key) in winners(keys) {
                measurements[index] = key.measurement
            }
        }
        return Piano(
            id: UUID(uuidString: record.pianoID) ?? UUID(),
            name: record.name,
            concertPitch: record.concertPitch,
            bassBreak: record.bassBreak,
            keys: measurements,
            tuningCents: SpectrumCodec.cents(record.tuningCents),
            entropy: record.entropy,
            tuningConcertPitch: record.tuningConcertPitch,
            updated: record.modifiedAt
        )
    }

    private static func spectra(from keys: [KeySpectrumRecord]) -> [[Double]] {
        var rows = Array(repeating: [Double](), count: PianoLayout.keyCount)
        for (index, key) in winners(keys) {
            rows[index] = SpectrumCodec.spectrum(key.spectrum)
        }
        return rows
    }

    private static func winners(_ keys: [KeySpectrumRecord]) -> [Int: KeySpectrumRecord] {
        var newest: [Int: KeySpectrumRecord] = [:]
        for key in keys where key.keyIndex >= 0 && key.keyIndex < PianoLayout.keyCount {
            if let kept = newest[key.keyIndex] {
                if KeySpectrumRecord.prefer(key, over: kept) { newest[key.keyIndex] = key }
            } else {
                newest[key.keyIndex] = key
            }
        }
        return newest
    }
}

@MainActor
private func deleteLosers(_ groups: [String: [PianoRecord]], in context: ModelContext) -> Bool {
    var removed = false
    for group in groups.values where group.count > 1 {
        let ranked = group.sorted { PianoRecord.prefer($0, over: $1) }
        for extra in ranked.dropFirst() {
            context.delete(extra)
            removed = true
        }
    }
    return removed
}

@MainActor
private func deleteLosers(_ groups: [String: [KeySpectrumRecord]], in context: ModelContext) -> Bool {
    var removed = false
    for group in groups.values where group.count > 1 {
        let ranked = group.sorted { KeySpectrumRecord.prefer($0, over: $1) }
        for extra in ranked.dropFirst() {
            context.delete(extra)
            removed = true
        }
    }
    return removed
}

enum SpectrumCodec {
    static func spectrumData(_ row: [Double]) -> Data {
        guard row.count == LogBin.numberOfBins else { return Data() }
        var floats = row.map { Float($0) }
        return floats.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return Data() }
            return Data(bytes: base, count: buffer.count * MemoryLayout<Float>.size)
        }
    }

    static func spectrum(_ data: Data) -> [Double] {
        guard data.count == LogBin.numberOfBins * MemoryLayout<Float>.size else { return [] }
        var row = [Double](repeating: 0, count: LogBin.numberOfBins)
        var energy = 0.0
        data.withUnsafeBytes { raw in
            let floats = raw.bindMemory(to: Float.self)
            for index in 0..<LogBin.numberOfBins {
                let value = Double(floats[index])
                row[index] = value
                energy += value
            }
        }
        return energy > 0 ? row : []
    }

    static func centsData(_ cents: [Double]?) -> Data {
        guard let cents, cents.count == PianoLayout.keyCount else { return Data() }
        var copy = cents
        return copy.withUnsafeBytes { Data($0) }
    }

    static func cents(_ data: Data) -> [Double]? {
        guard data.count == PianoLayout.keyCount * MemoryLayout<Double>.size else { return nil }
        var cents = [Double](repeating: 0, count: PianoLayout.keyCount)
        _ = cents.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return cents
    }

    static func loadPiano(at url: URL) -> Piano? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Piano.self, from: data)
    }

    static func loadSpectra(at url: URL) -> [[Double]] {
        guard let data = try? Data(contentsOf: url) else {
            return Array(repeating: [], count: PianoLayout.keyCount)
        }
        return stride(from: 0, to: PianoLayout.keyCount, by: 1).map { key in
            let size = LogBin.numberOfBins * MemoryLayout<Float>.size
            let start = key * size
            guard start + size <= data.count else { return [] }
            return spectrum(data.subdata(in: start..<(start + size)))
        }
    }
}

@available(iOS 27, macOS 27, watchOS 27, visionOS 27, *)
@MainActor
final class PianoCloudWatch {
    private var pianoResults: ResultsObserver<PianoRecord, Never>?
    private var keyResults: ResultsObserver<KeySpectrumRecord, Never>?
    private var token: ObservationTracking.Token?
    private let onChange: () -> Void

    init(context: ModelContext, onChange: @escaping () -> Void) {
        self.onChange = onChange
        do {
            pianoResults = try ResultsObserver(modelContext: context)
            keyResults = try ResultsObserver(modelContext: context)
            token = withContinuousObservation(options: .didSet) { [weak self] event in
                guard let self else { return }
                _ = self.pianoResults?.results
                _ = self.keyResults?.results
                guard event.kind == .didSet else { return }
                self.onChange()
            }
        } catch {
            pianoResults = nil
            keyResults = nil
        }
    }
}
