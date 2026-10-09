import SwiftUI

struct LibraryView: View {
    @Bindable var session: TunerSession
    var selection: Binding<UUID?>?

    var body: some View {
        List(selection: selection) {
            Section {
                Text("Record each note, then let the entropy search find the tuning for this piano.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
                    #if !os(watchOS)
                    .listRowSeparator(.hidden)
                    #endif
            }
            ForEach(session.pianos) { piano in
                row(piano)
                    .tag(piano.id)
                    .listRowBackground(Color.clear)
                    #if !os(watchOS)
                    .listRowSeparator(.hidden)
                    #endif
                    #if os(watchOS)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            delete(piano)
                        }
                    }
                    #else
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            delete(piano)
                        }
                    }
                    #endif
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Entropy Piano Tuner")
        .toolbar {
            Button("New piano", systemImage: "plus") { session.createPiano() }
        }
    }

    private func delete(_ piano: Piano) {
        let open = piano.id == session.piano?.id
        PianoStore.delete(piano.id)
        session.pianos = PianoStore.list()
        if open { session.closePiano() }
    }

    @ViewBuilder
    private func row(_ piano: Piano) -> some View {
        let label = HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(piano.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("\(piano.recordedCount) of 88 recorded")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if piano.tuningCents != nil {
                Text(piano.tuningIsCurrent ? "Tuned" : "Stale")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(piano.tuningIsCurrent ? Theme.inTune : Theme.amber)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        if selection != nil {
            label
        } else {
            Button { session.open(piano) } label: { label }
                .buttonStyle(.plain)
        }
    }
}

struct WorkspaceView: View {
    @Bindable var session: TunerSession
    @State private var name = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("Page", selection: $session.page) {
                ForEach(WorkspacePage.allCases) { page in
                    Text(page.label).tag(page)
                }
            }
            #if os(watchOS)
            .pickerStyle(.navigationLink)
            #else
            .pickerStyle(.segmented)
            #endif
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Group {
                switch session.page {
                case .record: RecordPage(session: session)
                case .calculate: CalculatePage(session: session)
                case .tune: TunePage(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .dockedKeyboard {
            PianoKeyboard(
                selected: session.selectedKey,
                recorded: { session.piano?.keys[$0].recorded ?? false },
                tuned: { session.piano?.keys[$0].tuned ?? false },
                onSelect: { session.select($0) }
            )
        }
        .background(Theme.background)
        .navigationTitle(session.piano?.name ?? "Piano")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Pianos") { session.closePiano() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(session.microphoneOn ? "Stop mic" : "Mic") {
                    session.toggleMicrophone()
                }
            }
        }
        .onAppear {
            name = session.piano?.name ?? ""
            if !session.microphoneOn { Task { await session.start() } }
        }
        .onDisappear { session.stop() }
        .onChange(of: session.page) { _, _ in session.select(session.selectedKey) }
    }
}

struct RecordPage: View {
    @Bindable var session: TunerSession

    var body: some View {
        VStack(spacing: 18) {
            Text(PianoLayout.label(session.selectedKey))
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("\(session.piano?.recordedCount ?? 0) of 88 recorded")
                .foregroundStyle(Theme.muted)
            Meter(cents: session.reading.cents, level: session.reading.level)
            Text(session.status.isEmpty ? "Play the selected note and hold it." : session.status)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 24)
            HStack(spacing: 12) {
                Button(session.autoCapture ? "Auto capture on" : "Auto capture off") {
                    session.autoCapture.toggle()
                }
                .buttonStyle(FilledButton(prominent: session.autoCapture))
                Button("Capture") { session.captureNow() }
                    .buttonStyle(FilledButton(prominent: false))
                Button("Clear") { session.clearKey() }
                    .buttonStyle(FilledButton(prominent: false))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
    }
}

struct CalculatePage: View {
    @Bindable var session: TunerSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("The search shifts each note until the combined overtones overlap as much as they can. A4 stays at the concert pitch.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Picker("Method", selection: $session.usePitchRaise) {
                    Text("Entropy").tag(false)
                    Text("Pitch raise").tag(true)
                }
                #if os(watchOS)
            .pickerStyle(.navigationLink)
            #else
            .pickerStyle(.segmented)
            #endif
                if !session.usePitchRaise {
                    Picker("Accuracy", selection: $session.accuracy) {
                        ForEach(CalculationAccuracy.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    HStack {
                        Text("Seed")
                        TextField("0", text: $session.seedText)
                            #if os(iOS) || os(visionOS)
                            .keyboardType(.numberPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Stepper(value: bassBreak, in: 8...40) {
                    Text("Bass break at \(PianoLayout.label(session.piano?.bassBreak ?? 27))")
                }
                if session.calculating {
                    ProgressView(value: session.progress)
                    Button("Stop") { session.stopCalculation() }
                        .buttonStyle(FilledButton(prominent: false))
                } else {
                    Button("Calculate tuning") { session.calculate() }
                        .buttonStyle(FilledButton(prominent: true))
                }
                if let cents = session.piano?.tuningCents {
                    TuningCurve(cents: cents, selected: session.selectedKey) { session.select($0) }
                        .frame(height: 180)
                        .padding(8)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text(session.piano?.tuningIsCurrent == true ? "Curve matches the current concert pitch." : "Concert pitch changed. Calculate again before tuning.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Text(session.status)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                Text("Pull a string only a little at a time. A large pitch raise can break a string.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .padding(20)
            .foregroundStyle(Theme.ink)
        }
    }

    private var bassBreak: Binding<Int> {
        Binding(
            get: { session.piano?.bassBreak ?? 27 },
            set: { session.setBassBreak($0) }
        )
    }
}

struct TunePage: View {
    @Bindable var session: TunerSession

    var body: some View {
        VStack(spacing: 16) {
            Text(PianoLayout.label(session.selectedKey))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            if let target = session.piano?.targetFrequency(for: session.selectedKey) {
                Text(String(format: "Target %.2f Hz", target))
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
            } else {
                Text("Calculate a tuning first.")
                    .foregroundStyle(Theme.amber)
            }
            Meter(cents: session.reading.cents, level: session.reading.level)
            HStack(spacing: 10) {
                Button("−1¢") { session.nudgeSelected(by: -1) }
                Button("In tune") { session.markTuned() }
                Button("+1¢") { session.nudgeSelected(by: 1) }
            }
            .buttonStyle(FilledButton(prominent: false))
            Text(verdict)
                .font(.headline)
                .foregroundStyle(verdictColor)
            Text("Mute the other strings of this note, match the center string, then tune the unisons to it.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var verdict: String {
        guard session.piano?.targetFrequency(for: session.selectedKey) != nil else { return "" }
        guard let cents = session.reading.cents else { return "Listening" }
        if abs(cents) < 1 { return "In tune" }
        return cents < 0 ? "Flat" : "Sharp"
    }

    private var verdictColor: Color {
        guard let cents = session.reading.cents else { return Theme.muted }
        if abs(cents) < 1 { return Theme.inTune }
        return cents < 0 ? Theme.flat : Theme.sharp
    }
}

struct FilledButton: ButtonStyle {
    var prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(prominent ? Color.black : Theme.ink)
            .background(prominent ? Theme.amber : Theme.card, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = TunerSession()
    @State private var selection: UUID?

    var body: some View {
        Group {
            #if os(watchOS)
            NavigationStack {
                if session.piano == nil {
                    LibraryView(session: session)
                } else {
                    WatchWorkspace(session: session)
                }
            }
            #else
            NavigationSplitView {
                LibraryView(session: session, selection: $selection)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
            } detail: {
                if session.piano == nil {
                    ContentUnavailableView(
                        "No piano open",
                        systemImage: "music.note",
                        description: Text("Choose a piano, or add one.")
                    )
                } else {
                    WorkspaceView(session: session)
                }
            }
            .onChange(of: selection) { _, id in
                guard id != session.piano?.id else { return }
                if let id, let piano = session.pianos.first(where: { $0.id == id }) {
                    session.open(piano)
                } else if session.piano != nil {
                    session.closePiano()
                }
            }
            .onChange(of: session.piano?.id) { _, id in
                if selection != id { selection = id }
            }
            #endif
        }
        .preferredColorScheme(.dark)
        .tint(Theme.amber)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.refreshFromStore() }
        }
        #if os(macOS)
        .frame(minWidth: 880, minHeight: 680)
        #endif
    }
}
