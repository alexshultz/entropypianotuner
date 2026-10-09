import SwiftUI

struct LibraryView: View {
    @Bindable var session: TunerSession
    var selection: Binding<UUID?>?
    @State private var pendingDelete: Piano?

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(session.pianos) { piano in
                    row(piano)
                        .tag(piano.id)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                pendingDelete = piano
                            }
                        }
                        #if !os(watchOS)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                pendingDelete = piano
                            }
                        }
                        #endif
                }
            } footer: {
                Text("Record each note, then let the entropy search find the tuning for this piano.")
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #elseif os(macOS)
        .listStyle(.sidebar)
        #endif
        .navigationTitle("Pianos")
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "this piano")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { delete(pendingDelete) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This removes the piano and its recordings.")
        }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(piano.name)
                Text("\(piano.recordedCount) of 88 recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if piano.tuningCents != nil {
                Text(piano.tuningIsCurrent ? "Tuned" : "Stale")
                    .font(.caption)
                    .foregroundStyle(piano.tuningIsCurrent ? Color.green : Color.orange)
            }
        }

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

    var body: some View {
        VStack(spacing: 0) {
            #if !os(macOS)
            pagePicker
                .padding(.horizontal, 16)
                .padding(.top, 8)
            #endif
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
        .navigationTitle(session.piano?.name ?? "Piano")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Pianos") { session.closePiano() }
            }
            #if os(macOS)
            ToolbarItem(placement: .principal) {
                pagePicker
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                microphoneButton
            }
        }
        .onAppear {
            if !session.microphoneOn { Task { await session.start() } }
        }
        .onDisappear { session.stop() }
        .onChange(of: session.page) { _, _ in session.select(session.selectedKey) }
    }

    private var pagePicker: some View {
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
    }

    private var microphoneButton: some View {
        Button {
            session.toggleMicrophone()
        } label: {
            Image(systemName: session.microphoneOn ? "mic.fill" : "mic.slash")
        }
        .accessibilityLabel(session.microphoneOn ? "Stop microphone" : "Start microphone")
    }
}

struct RecordPage: View {
    @Bindable var session: TunerSession

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(PianoLayout.label(session.selectedKey))
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("\(session.piano?.recordedCount ?? 0) of 88 recorded")
                    .foregroundStyle(.secondary)
                Meter(cents: session.reading.cents, level: session.reading.level)
                Text(session.status.isEmpty ? "Play the selected note and hold it." : session.status)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                HStack(spacing: actionSpacing) {
                    autoCapture
                    Button("Capture") { session.captureNow() }
                        .buttonStyle(.borderedProminent)
                    Button("Clear") { session.clearKey() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var autoCapture: some View {
        #if os(macOS)
        Toggle("Auto capture", isOn: $session.autoCapture)
            .toggleStyle(.checkbox)
        #else
        if session.autoCapture {
            Button {
                session.autoCapture = false
            } label: {
                Label("Auto capture", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityValue("On")
        } else {
            Button {
                session.autoCapture = true
            } label: {
                Label("Auto capture", systemImage: "circle")
            }
            .buttonStyle(.bordered)
            .accessibilityValue("Off")
        }
        #endif
    }

    private var actionSpacing: CGFloat {
        #if os(visionOS)
        20
        #else
        12
        #endif
    }
}

struct CalculatePage: View {
    @Bindable var session: TunerSession
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            Section {
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
                    LabeledContent("Seed") {
                        TextField("0", text: $session.seedText)
                            #if os(iOS) || os(visionOS)
                            .keyboardType(.numberPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                    }
                }
            } footer: {
                Text("The search shifts each note until the combined overtones overlap as much as they can. A4 stays at the concert pitch.")
            }

            Section("Piano") {
                TextField("Name", text: $nameDraft)
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                Stepper(value: concertPitch, in: 415...466, step: 1) {
                    Text("A4 at \(Int((session.piano?.concertPitch ?? 440).rounded())) Hz")
                        .monospacedDigit()
                }
                Stepper(value: bassBreak, in: 8...40) {
                    Text("Bass break at \(PianoLayout.label(session.piano?.bassBreak ?? 27))")
                }
            }

            Section {
                if session.calculating {
                    ProgressView(value: session.progress)
                    Button("Stop") { session.stopCalculation() }
                        .buttonStyle(.bordered)
                } else {
                    Button("Calculate tuning") { session.calculate() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if let cents = session.piano?.tuningCents {
                Section("Tuning curve") {
                    TuningCurve(cents: cents, selected: session.selectedKey) { session.select($0) }
                        .frame(height: 180)
                    Text(session.piano?.tuningIsCurrent == true
                         ? "Curve matches the current concert pitch."
                         : "Concert pitch changed. Calculate again before tuning.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if !session.status.isEmpty {
                    Text(session.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Pull a string only a little at a time. A large pitch raise can break a string.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { nameDraft = session.piano?.name ?? "" }
        .onDisappear { commitName() }
        .onChange(of: nameFocused) { _, focused in
            if !focused { commitName() }
        }
        .onChange(of: session.piano?.name) { _, name in
            if !nameFocused { nameDraft = name ?? "" }
        }
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != session.piano?.name else {
            if trimmed.isEmpty { nameDraft = session.piano?.name ?? "" }
            return
        }
        session.rename(trimmed)
    }

    private var concertPitch: Binding<Double> {
        Binding(
            get: { session.piano?.concertPitch ?? 440 },
            set: { session.setConcertPitch($0) }
        )
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
        ScrollView {
            VStack(spacing: 16) {
                Text(PianoLayout.label(session.selectedKey))
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let target = session.piano?.targetFrequency(for: session.selectedKey) {
                    Text(String(format: "Target %.2f Hz", target))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("Calculate a tuning first.")
                        .foregroundStyle(.secondary)
                }
                Meter(cents: session.reading.cents, level: session.reading.level)
                HStack(spacing: actionSpacing) {
                    Button("−1¢") { session.nudgeSelected(by: -1) }
                        .buttonStyle(.bordered)
                    Button("In tune") { session.markTuned() }
                        .buttonStyle(.borderedProminent)
                    Button("+1¢") { session.nudgeSelected(by: 1) }
                        .buttonStyle(.bordered)
                }
                if let verdict {
                    Text(verdict.label)
                        .font(.headline)
                        .foregroundStyle(verdict.color)
                }
                Text("Mute the other strings of this note, match the center string, then tune the unisons to it.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }

    private var verdict: PitchVerdict? {
        guard session.piano?.targetFrequency(for: session.selectedKey) != nil else { return nil }
        return PitchVerdict.from(cents: session.reading.cents)
    }

    private var actionSpacing: CGFloat {
        #if os(visionOS)
        20
        #else
        12
        #endif
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
        .focusedSceneValue(\.tunerSession, session)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.refreshFromStore() }
        }
        #if os(macOS)
        .frame(minWidth: 880, minHeight: 680)
        #endif
    }
}
