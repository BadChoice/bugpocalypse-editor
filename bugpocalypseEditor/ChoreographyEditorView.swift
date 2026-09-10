import BugpocalypseContent
import Combine
import SwiftUI

struct ChoreographyEditorView: View {
    @ObservedObject var workspace: EditorWorkspace
    @ObservedObject var document: ChoreographyEditorDocument
    @State private var playhead: Double = 0
    @State private var isPlaying = false
    @State private var playbackSpeed = 1.0
    private let ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(document.definition.name).font(.title2.bold())
                    Text("Local timeline · \(document.definition.timeline.count) formation spawns · \(document.definition.id)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: workspace.createChoreography) { Label("New", systemImage: "plus") }
                Button(action: workspace.addChoreographySpawn) { Label("Add Formation", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            Divider()
            VStack(spacing: 12) {
                MissionPreview(
                    mission: previewMission,
                    workspace: workspace,
                    playhead: playhead,
                    selectedEventIndex: workspace.selectedChoreographyEventIndex,
                    selectedMemberIndex: nil,
                    enemyPreviewImage: workspace.enemyPreviewImage,
                    selectEvent: selectTimelineEvent,
                    selectMember: { _, index, at in selectTimelineEvent(index, at) }
                )
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxHeight: 430)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                playbackControls
                Divider()
                timeline
            }
            .padding(14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(ticker) { _ in
            guard isPlaying else { return }
            playhead += (1.0 / 30.0) * playbackSpeed
            if playhead >= choreographyDuration { playhead = 0 }
        }
        .onChange(of: workspace.selectedChoreographyEventIndex) { _, index in
            guard let index, document.definition.timeline.indices.contains(index) else { return }
            playhead = min(document.definition.timeline[index].at + 2, choreographyDuration)
            isPlaying = false
        }
    }

    private var previewMission: MissionDefinition {
        MissionDefinition(
            schemaVersion: 1,
            id: document.definition.id,
            authoringStatus: document.definition.authoringStatus,
            background: .init(resourcePath: ""),
            metadata: .init(locationId: "preview", missionNumber: 0, displayName: document.definition.name, recommendedHeroLevel: 1, starObjectives: []),
            completion: .init(kind: .clearAllWaves),
            timeline: document.definition.timeline.map { .init(at: $0.at, action: .spawnFormation($0.spawn)) }
        )
    }

    private var playbackControls: some View {
        HStack(spacing: 10) {
            Button { if playhead >= choreographyDuration { playhead = 0 }; isPlaying.toggle() } label: { Image(systemName: isPlaying ? "pause.fill" : "play.fill") }
            Button { playhead = 0; isPlaying = false } label: { Image(systemName: "backward.end.fill") }
            Text(timeText(playhead)).font(.system(.caption, design: .monospaced)).frame(width: 58)
            Slider(value: $playhead, in: 0...choreographyDuration)
            Picker("Speed", selection: $playbackSpeed) {
                Text("½×").tag(0.5); Text("1×").tag(1.0); Text("2×").tag(2.0)
            }.labelsHidden().frame(width: 72)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LOCAL TIMELINE").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("Overlaps are intentional: scrub to inspect the resulting stack.").font(.caption).foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(sortedEvents, id: \.offset) { item in
                        Button { selectTimelineEvent(item.offset, item.element.at) } label: {
                            ChoreographyTimelineCard(event: item.element, formation: formation(for: item.element.spawn), isSelected: workspace.selectedChoreographyEventIndex == item.offset)
                        }
                        .buttonStyle(.plain)
                    }
                }.padding(.vertical, 2)
            }
        }.frame(minHeight: 100)
    }

    private var sortedEvents: [(offset: Int, element: ChoreographyTimelineEvent)] {
        document.definition.timeline.enumerated().sorted { $0.element.at == $1.element.at ? $0.offset < $1.offset : $0.element.at < $1.element.at }
    }

    private var choreographyDuration: Double { max(10, (document.definition.timeline.map(\.at).max() ?? 0) + 10) }
    private func timeText(_ value: Double) -> String { String(format: "%05.2f", value) }
    private func selectTimelineEvent(_ index: Int, _ at: Double) {
        workspace.selectedChoreographyEventIndex = index
        playhead = min(at + 2, choreographyDuration)
        isPlaying = false
    }

    private func formation(for spawn: SpawnFormationEvent) -> FormationDefinition {
        workspace.formation(for: spawn.formationReference) ?? spawn.formation
    }
}

private struct ChoreographyTimelineCard: View {
    let event: ChoreographyTimelineEvent
    let formation: FormationDefinition
    let isSelected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: "ant.fill").foregroundStyle(.orange)
                Text(EnemyCatalogue.entry(for: event.spawn.enemy.id)?.displayName ?? event.spawn.enemy.id).font(.caption.bold()).lineLimit(1)
                if !(event.spawn.drops ?? []).isEmpty { Image(systemName: "gift.fill").foregroundStyle(.yellow) }
            }
            Text(String(format: "%.2f s", event.at)).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            Text("Lv \(event.spawn.enemy.level) · \(formation.offsets().count) × \(formation.kind.rawValue)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(9).frame(width: 150, height: 78, alignment: .leading)
        .background(isSelected ? Color.orange.opacity(0.22) : Color(nsColor: .controlBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSelected ? .orange : .gray.opacity(0.25), lineWidth: isSelected ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct ChoreographyInspector: View {
    @ObservedObject var workspace: EditorWorkspace

    private var document: ChoreographyEditorDocument? { workspace.selectedChoreography }
    private var selectedIndex: Int? { workspace.selectedChoreographyEventIndex }
    private var selectedEvent: ChoreographyTimelineEvent? {
        guard let document, let selectedIndex, document.definition.timeline.indices.contains(selectedIndex) else { return nil }
        return document.definition.timeline[selectedIndex]
    }

    var body: some View {
        Form {
            if let document {
                documentFields(document)
                if let event = selectedEvent { eventFields(event) }
                ContentUsageSection(usages: workspace.usages(ofChoreography: document), open: workspace.open)
            } else { ContentUnavailableView("No choreography selected", systemImage: "sidebar.right") }
        }
        .formStyle(.grouped)
        .navigationTitle("Choreography Inspector")
    }

    private func documentFields(_ document: ChoreographyEditorDocument) -> some View {
        Section("Choreography") {
            TextField("Name", text: documentBinding(\.name, fallback: document.definition.name))
            TextField("ID", text: documentBinding(\.id, fallback: document.definition.id))
            Picker("Status", selection: documentBinding(\.authoringStatus, fallback: document.definition.authoringStatus)) {
                ForEach(AuthoringStatus.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Text("A choreography has only a local spawn timeline. Drops remain on each formation spawn.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func eventFields(_ event: ChoreographyTimelineEvent) -> some View {
        Section("Timing") {
            TextField("Time (seconds)", value: eventTimeBinding, format: .number.precision(.fractionLength(2)))
        }
        Section("Enemy") {
            Picker("Type", selection: spawnBinding(\.enemy.id, fallback: event.spawn.enemy.id)) {
                ForEach(EnemyCatalogue.all) { Text($0.displayName).tag($0.id) }
            }
            Stepper("Level: \(event.spawn.enemy.level)", value: spawnBinding(\.enemy.level, fallback: event.spawn.enemy.level), in: 1...100)
        }
        Section("Formation Attack") {
            FormationAttackEditor(attack: spawnBinding(\.attack, fallback: event.spawn.attack))
        }
        Section("Reusable Sources") {
            Picker("Formation source", selection: formationIsSavedBinding) {
                Text("Inline").tag(false)
                Text("Saved formation").tag(true)
            }
            if event.spawn.formationReference == nil {
                Picker("Kind", selection: inlineFormationKindBinding) { ForEach(FormationKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                InlineFormationFields(formation: inlineFormationBinding)
            } else {
                Picker("Formation", selection: formationPathBinding) {
                    ForEach(workspace.formations) { Text($0.definition.name).tag(workspace.resourcePath(for: $0.fileURL) ?? "") }
                }
            }
            Picker("Path", selection: pathPathBinding) {
                Text("Inline default").tag("")
                ForEach(workspace.paths) { Text($0.definition.name).tag(workspace.resourcePath(for: $0.fileURL) ?? "") }
            }
            Text("Select a saved formation or path for reusable encounter geometry and movement.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Path Transform") {
            Toggle("Mirror vertically", isOn: mirrorYBinding)
            TextField("Horizontal shift", value: xOffsetBinding, format: .number)
            TextField("Vertical shift", value: yOffsetBinding, format: .number)
            Text("Mirror around the gameplay centre, then shift the complete formation and route. Reuse one path at different positions.")
                .font(.caption).foregroundStyle(.secondary)
        }
        dropsFields(event)
        Section("Actions") {
            Button("Duplicate Spawn", action: workspace.duplicateSelectedChoreographySpawn)
            Button("Delete Formation", role: .destructive) { workspace.deleteSelectedChoreographyEvent() }
        }
    }

    @ViewBuilder private func dropsFields(_ event: ChoreographyTimelineEvent) -> some View {
        let memberCount = (workspace.formation(for: event.spawn.formationReference) ?? event.spawn.formation).offsets().count
        Section("Drops") {
            if let drop = event.spawn.drops?.first {
                Picker("Kind", selection: dropKindBinding(fallback: drop.kind)) { ForEach(DropKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                TextField("Amount", value: dropAmountBinding(fallback: drop.amount), format: .number)
                Picker("Member", selection: dropMemberBinding(fallback: drop.memberIndex)) {
                    ForEach(0..<max(1, memberCount), id: \.self) { Text("Enemy \($0 + 1)").tag($0) }
                }
                Button("Remove Drop", role: .destructive) { mutateSpawn { $0.drops = nil } }
            } else {
                Button("Add Drop to Enemy 1") { mutateSpawn { $0.drops = [.init(kind: .rage, amount: 1, memberIndex: 0)] } }
                    .disabled(memberCount == 0)
            }
        }
    }

    private func documentBinding<Value>(_ keyPath: WritableKeyPath<ChoreographyDocument, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { document?.definition[keyPath: keyPath] ?? fallback }, set: { value in workspace.updateSelectedChoreography { $0[keyPath: keyPath] = value } })
    }
    private var eventTimeBinding: Binding<Double> { Binding(get: { selectedEvent?.at ?? 0 }, set: { value in mutateEvent { $0.at = value } }) }
    private func spawnBinding<Value>(_ keyPath: WritableKeyPath<SpawnFormationEvent, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { selectedEvent?.spawn[keyPath: keyPath] ?? fallback }, set: { value in mutateSpawn { $0[keyPath: keyPath] = value } })
    }
    private var formationPathBinding: Binding<String> { Binding(get: { selectedEvent?.spawn.formationReference?.resourcePath ?? "" }, set: { path in mutateSpawn { $0.formationReference = path.isEmpty ? nil : .init(resourcePath: path) } }) }
    private var formationIsSavedBinding: Binding<Bool> { Binding(get: { selectedEvent?.spawn.formationReference != nil }, set: { saved in mutateSpawn { spawn in
        if saved, let document = workspace.formations.first, let path = workspace.resourcePath(for: document.fileURL) { spawn.formationReference = .init(resourcePath: path) }
        if !saved { spawn.formationReference = nil }
    } }) }
    private var inlineFormationBinding: Binding<FormationDefinition> { Binding(get: { selectedEvent?.spawn.formation ?? .line(.init(axis: .vertical, count: 3, spacing: 48)) }, set: { value in mutateSpawn { $0.formation = value } }) }
    private var inlineFormationKindBinding: Binding<FormationKind> { Binding(get: { selectedEvent?.spawn.formation.kind ?? .line }, set: { kind in mutateSpawn { $0.formation = InlineFormationFields.defaultFormation(kind) } }) }
    private var pathPathBinding: Binding<String> { Binding(get: { selectedEvent?.spawn.pathReference?.resourcePath ?? "" }, set: { path in mutateSpawn { $0.pathReference = path.isEmpty ? nil : .init(resourcePath: path) } }) }
    private var mirrorYBinding: Binding<Bool> { Binding(get: { selectedEvent?.spawn.pathTransform?.mirrorY ?? false }, set: { value in mutateSpawn { spawn in var transform = spawn.pathTransform ?? .init(); transform.mirrorY = value; spawn.pathTransform = transform.isIdentity ? nil : transform } }) }
    private var xOffsetBinding: Binding<Double> { Binding(get: { selectedEvent?.spawn.pathTransform?.xOffset ?? 0 }, set: { value in mutateSpawn { spawn in var transform = spawn.pathTransform ?? .init(); transform.xOffset = value; spawn.pathTransform = transform.isIdentity ? nil : transform } }) }
    private var yOffsetBinding: Binding<Double> { Binding(get: { selectedEvent?.spawn.pathTransform?.yOffset ?? 0 }, set: { value in mutateSpawn { spawn in var transform = spawn.pathTransform ?? .init(); transform.yOffset = value; spawn.pathTransform = transform.isIdentity ? nil : transform } }) }
    private func dropKindBinding(fallback: DropKind) -> Binding<DropKind> { Binding(get: { selectedEvent?.spawn.drops?.first?.kind ?? fallback }, set: { value in mutateSpawn { $0.drops?[0].kind = value } }) }
    private func dropAmountBinding(fallback: Int) -> Binding<Int> { Binding(get: { selectedEvent?.spawn.drops?.first?.amount ?? fallback }, set: { value in mutateSpawn { $0.drops?[0].amount = value } }) }
    private func dropMemberBinding(fallback: Int) -> Binding<Int> { Binding(get: { selectedEvent?.spawn.drops?.first?.memberIndex ?? fallback }, set: { value in mutateSpawn { $0.drops?[0].memberIndex = value } }) }
    private func mutateEvent(_ change: (inout ChoreographyTimelineEvent) -> Void) {
        guard let index = selectedIndex else { return }
        workspace.updateSelectedChoreography { guard $0.timeline.indices.contains(index) else { return }; change(&$0.timeline[index]) }
    }
    private func mutateSpawn(_ change: (inout SpawnFormationEvent) -> Void) { mutateEvent { change(&$0.spawn) } }
}

private struct InlineFormationFields: View {
    @Binding var formation: FormationDefinition

    var body: some View {
        switch formation {
        case let .line(value):
            Picker("Axis", selection: lineBinding(\.axis, fallback: value.axis)) { ForEach(FormationAxis.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
            Stepper("Count: \(value.count)", value: lineBinding(\.count, fallback: value.count), in: 1...50)
            TextField("Spacing", value: lineBinding(\.spacing, fallback: value.spacing), format: .number)
        case let .slottedLine(value):
            Picker("Axis", selection: slottedBinding(\.axis, fallback: value.axis)) { ForEach(FormationAxis.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
            Stepper("Slots: \(value.slotCount)", value: slottedBinding(\.slotCount, fallback: value.slotCount), in: 1...50)
            TextField("Spacing", value: slottedBinding(\.spacing, fallback: value.spacing), format: .number)
            TextField("Occupied slots", text: slottedSlotsBinding)
        case let .v(value):
            Stepper("Count: \(value.count)", value: vBinding(\.count, fallback: value.count), in: 1...50)
            TextField("Spacing", value: vBinding(\.spacing, fallback: value.spacing), format: .number)
            TextField("Depth", value: vBinding(\.depth, fallback: value.depth), format: .number)
        case let .staggeredGrid(value):
            Stepper("Rows: \(value.rows)", value: gridBinding(\.rows, fallback: value.rows), in: 1...20)
            Stepper("Columns: \(value.columns)", value: gridBinding(\.columns, fallback: value.columns), in: 1...20)
            TextField("Horizontal spacing", value: gridBinding(\.spacingX, fallback: value.spacingX), format: .number)
            TextField("Vertical spacing", value: gridBinding(\.spacingY, fallback: value.spacingY), format: .number)
        case let .arc(value):
            Stepper("Count: \(value.count)", value: arcBinding(\.count, fallback: value.count), in: 1...50)
            TextField("Radius", value: arcBinding(\.radius, fallback: value.radius), format: .number)
            TextField("Start angle", value: arcBinding(\.startAngle, fallback: value.startAngle), format: .number)
            TextField("End angle", value: arcBinding(\.endAngle, fallback: value.endAngle), format: .number)
        case let .ring(value):
            Stepper("Count: \(value.count)", value: ringBinding(\.count, fallback: value.count), in: 1...50)
            TextField("Horizontal radius", value: ringBinding(\.radiusX, fallback: value.radiusX), format: .number)
            TextField("Vertical radius", value: ringBinding(\.radiusY, fallback: value.radiusY), format: .number)
            TextField("Rotation", value: ringBinding(\.rotation, fallback: value.rotation), format: .number)
            TextField("Orbit speed (°/s)", value: ringBinding(\.orbitSpeed, fallback: value.orbitSpeed), format: .number)
        case let .trail(value):
            Stepper("Count: \(value.count)", value: trailBinding(\.count, fallback: value.count), in: 1...50)
            TextField("Follow delay", value: trailBinding(\.followDelay, fallback: value.followDelay), format: .number)
        case let .freeform(value):
            LabeledContent("Members", value: "\(value.members.count)")
            Text("Edit freeform member positions in the Formations editor.").font(.caption).foregroundStyle(.secondary)
        }
    }

    static func defaultFormation(_ kind: FormationKind) -> FormationDefinition {
        switch kind {
        case .line: .line(.init(axis: .vertical, count: 3, spacing: 48))
        case .slottedLine: .slottedLine(.init(axis: .vertical, slotCount: 5, spacing: 48, occupiedSlots: [0, 2, 4]))
        case .v: .v(.init(count: 5, spacing: 36, depth: 24))
        case .staggeredGrid: .staggeredGrid(.init(rows: 2, columns: 3, spacingX: 44, spacingY: 48))
        case .arc: .arc(.init(count: 5, radius: 80, startAngle: 120, endAngle: 240))
        case .ring: .ring(.init(count: 5, radiusX: 80, radiusY: 56, rotation: 0, orbitSpeed: 0))
        case .trail: .trail(.init(count: 4, followDelay: 0.2))
        case .freeform: .freeform(.init(members: [.init(offset: .init(x: 0, y: 0))]))
        }
    }

    private func edit<T, Value>(_ keyPath: WritableKeyPath<T, Value>, fallback: Value, extract: @escaping (FormationDefinition) -> T?, wrap: @escaping (T) -> FormationDefinition) -> Binding<Value> {
        Binding(get: { extract(formation)?[keyPath: keyPath] ?? fallback }, set: { value in guard var item = extract(formation) else { return }; item[keyPath: keyPath] = value; formation = wrap(item) })
    }
    private func lineBinding<Value>(_ keyPath: WritableKeyPath<LineFormation, Value>, fallback: Value) -> Binding<Value> { edit(keyPath, fallback: fallback, extract: { if case let .line(v) = $0 { v } else { nil } }, wrap: FormationDefinition.line) }
    private func slottedBinding<Value>(_ keyPath: WritableKeyPath<SlottedLineFormation, Value>, fallback: Value) -> Binding<Value> { edit(keyPath, fallback: fallback, extract: { if case let .slottedLine(v) = $0 { v } else { nil } }, wrap: FormationDefinition.slottedLine) }
    private func vBinding<Value>(_ keyPath: WritableKeyPath<VFormation, Value>, fallback: Value) -> Binding<Value> { edit(keyPath, fallback: fallback, extract: { if case let .v(v) = $0 { v } else { nil } }, wrap: FormationDefinition.v) }
    private func gridBinding<Value>(_ keyPath: WritableKeyPath<StaggeredGridFormation, Value>, fallback: Value) -> Binding<Value> { edit(keyPath, fallback: fallback, extract: { if case let .staggeredGrid(v) = $0 { v } else { nil } }, wrap: FormationDefinition.staggeredGrid) }
    private func arcBinding<Value>(_ keyPath: WritableKeyPath<ArcFormation, Value>, fallback: Value) -> Binding<Value> { edit(keyPath, fallback: fallback, extract: { if case let .arc(v) = $0 { v } else { nil } }, wrap: FormationDefinition.arc) }
    private func ringBinding<Value>(_ keyPath: WritableKeyPath<RingFormation, Value>, fallback: Value) -> Binding<Value> { edit(keyPath, fallback: fallback, extract: { if case let .ring(v) = $0 { v } else { nil } }, wrap: FormationDefinition.ring) }
    private func trailBinding<Value>(_ keyPath: WritableKeyPath<TrailFormation, Value>, fallback: Value) -> Binding<Value> { edit(keyPath, fallback: fallback, extract: { if case let .trail(v) = $0 { v } else { nil } }, wrap: FormationDefinition.trail) }
    private var slottedSlotsBinding: Binding<String> { Binding(get: { if case let .slottedLine(value) = formation { value.occupiedSlots.map(String.init).joined(separator: ", ") } else { "" } }, set: { text in guard case var .slottedLine(value) = formation else { return }; value.occupiedSlots = text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }; formation = .slottedLine(value) }) }
}
