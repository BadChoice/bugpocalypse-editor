import AppKit
import BugpocalypseContent
import Combine
import SwiftUI

struct MissionEditorView: View {
    @ObservedObject var workspace: EditorWorkspace
    @ObservedObject var document: MissionDocument
    @State private var playhead: Double = 0
    @State private var isPlaying = false
    @State private var playbackSpeed = 1.0
    private let ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 12) {
                MissionPreview(
                    mission: document.definition,
                    playhead: playhead,
                    selectedEventIndex: workspace.selectedMissionEventIndex,
                    enemyAssetURL: workspace.enemyAssetURL
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
            if playhead >= missionDuration { playhead = 0 }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.definition.metadata.displayName).font(.title2.bold())
                Text("Mission \(document.definition.metadata.missionNumber) · \(document.definition.timeline.count) events · \(document.definition.id)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Spawn Formation") {
                    workspace.addMissionEvent(.spawnFormation(Self.defaultSpawn))
                }
                Button("Zoom Out") {
                    workspace.addMissionEvent(.zoomOut(.init(multiplier: 0.8, duration: 1.0)))
                }
                Button("Zoom In") {
                    workspace.addMissionEvent(.zoomIn(.init(multiplier: 1.0, duration: 1.0)))
                }
            } label: {
                Label("Add Event", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
    }

    private var playbackControls: some View {
        HStack(spacing: 10) {
            Button {
                if playhead >= missionDuration { playhead = 0 }
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            Button { playhead = 0; isPlaying = false } label: { Image(systemName: "backward.end.fill") }
            Text(timeText(playhead)).font(.system(.caption, design: .monospaced)).frame(width: 58)
            Slider(value: $playhead, in: 0...missionDuration)
            Picker("Speed", selection: $playbackSpeed) {
                Text("½×").tag(0.5); Text("1×").tag(1.0); Text("2×").tag(2.0)
            }
            .labelsHidden().frame(width: 72)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TIMELINE").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("Select an event to edit it in the inspector")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(sortedEvents, id: \.offset) { item in
                        Button {
                            workspace.selectedMissionEventIndex = item.offset
                            playhead = item.element.at
                            isPlaying = false
                        } label: {
                            TimelineEventCard(
                                event: item.element,
                                isSelected: workspace.selectedMissionEventIndex == item.offset
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(minHeight: 100)
    }

    private var sortedEvents: [(offset: Int, element: MissionTimelineEvent)] {
        document.definition.timeline.enumerated().sorted {
            $0.element.at == $1.element.at ? $0.offset < $1.offset : $0.element.at < $1.element.at
        }
    }

    private var missionDuration: Double {
        max(10, (document.definition.timeline.map(\.at).max() ?? 0) + 10)
    }

    private func timeText(_ value: Double) -> String { String(format: "%05.2f", value) }

    private static let defaultSpawn = SpawnFormationEvent(
        enemy: .init(id: "fly_basic", level: 1),
        formation: .line(.init(axis: .vertical, count: 3, spacing: 48)),
        path: .straight(.init(speed: 120)),
        spawnPosition: .init(edge: .right, xOffset: 24, y: 180)
    )
}

private struct TimelineEventCard: View {
    let event: MissionTimelineEvent
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.caption.bold()).lineLimit(1)
            }
            Text(String(format: "%.2f s", event.at))
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(9)
        .frame(width: 150, height: 78, alignment: .leading)
        .background(isSelected ? color.opacity(0.22) : Color(nsColor: .controlBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSelected ? color : .gray.opacity(0.25), lineWidth: isSelected ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var title: String {
        switch event.action {
        case let .spawnFormation(value): EnemyCatalogue.entry(for: value.enemy.id)?.displayName ?? value.enemy.id
        case .zoomOut: "Zoom Out"
        case .zoomIn: "Zoom In"
        }
    }
    private var detail: String {
        switch event.action {
        case let .spawnFormation(value): "\(value.formation.offsets().count) × \(value.formation.kind.rawValue)"
        case let .zoomOut(value): String(format: "%.2f× · %.1f s", value.multiplier, value.duration)
        case let .zoomIn(value): String(format: "%.2f× · %.1f s", value.multiplier, value.duration)
        }
    }
    private var icon: String { if case .spawnFormation = event.action { "ant.fill" } else { "camera.fill" } }
    private var color: Color { if case .spawnFormation = event.action { .orange } else { .blue } }
}

private struct MissionPreview: View {
    let mission: MissionDefinition
    let playhead: Double
    let selectedEventIndex: Int?
    let enemyAssetURL: (String) -> URL?

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 640, geometry.size.height / 360)
            let origin = CGPoint(x: (geometry.size.width - 640 * scale) / 2, y: (geometry.size.height - 360 * scale) / 2)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.03, green: 0.08, blue: 0.15), Color(red: 0.08, green: 0.16, blue: 0.18)], startPoint: .top, endPoint: .bottom)
                previewGrid(origin: origin, scale: scale)
                ForEach(Array(mission.timeline.enumerated()), id: \.offset) { index, event in
                    if case let .spawnFormation(spawn) = event.action, event.at <= playhead {
                        formation(spawn, elapsed: playhead - event.at, selected: selectedEventIndex == index, origin: origin, scale: scale)
                    }
                }
                Text("640 × 360  •  t = \(playhead, specifier: "%.2f") s")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                    .padding(8)
            }
            .clipped()
        }
    }

    private func previewGrid(origin: CGPoint, scale: CGFloat) -> some View {
        Canvas { context, _ in
            let rect = CGRect(x: origin.x, y: origin.y, width: 640 * scale, height: 360 * scale)
            context.stroke(Path(rect), with: .color(.white.opacity(0.35)), lineWidth: 1)
            for x in stride(from: 80.0, to: 640.0, by: 80.0) {
                var path = Path(); path.move(to: .init(x: origin.x + x * scale, y: origin.y)); path.addLine(to: .init(x: origin.x + x * scale, y: origin.y + 360 * scale))
                context.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 1)
            }
            for y in stride(from: 60.0, to: 360.0, by: 60.0) {
                var path = Path(); path.move(to: .init(x: origin.x, y: origin.y + y * scale)); path.addLine(to: .init(x: origin.x + 640 * scale, y: origin.y + y * scale))
                context.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func formation(_ spawn: SpawnFormationEvent, elapsed: Double, selected: Bool, origin: CGPoint, scale: CGFloat) -> some View {
        let anchorX = spawn.spawnPosition.edge == .right ? 640 + spawn.spawnPosition.xOffset : -spawn.spawnPosition.xOffset
        let path = sampledPath(spawn.path, elapsed: elapsed)
        ForEach(Array(spawn.formation.offsets().enumerated()), id: \.offset) { index, offset in
            let position = CGPoint(
                x: origin.x + (anchorX + offset.x + path.x) * scale,
                y: origin.y + (spawn.spawnPosition.y + offset.y + path.y) * scale
            )
            EnemyPreviewSprite(url: enemyAssetURL(spawn.enemy.id), name: spawn.enemy.id, selected: selected)
                .frame(width: 42 * scale, height: 42 * scale)
                .position(position)
                .overlay(alignment: .bottom) {
                    if selected { Text("\(index)").font(.system(size: 8)).foregroundStyle(.white).offset(y: 12 * scale) }
                }
        }
    }

    private func sampledPath(_ path: MovementPathDefinition, elapsed: Double) -> ContentPoint {
        switch path {
        case .straight, .sine:
            return path.offset(elapsed: elapsed)
        case let .waypoints(value):
            guard value.points.count >= 2, value.duration > 0 else { return .init(x: 0, y: 0) }
            let progress = min(max(elapsed / value.duration, 0), 1)
            let segmentCount = value.points.count - 1
            let route = progress * Double(segmentCount)
            let index = min(Int(route), segmentCount - 1)
            let amount = route - Double(index)
            let start = value.points[index], end = value.points[index + 1], first = value.points[0]
            return .init(
                x: ((start.x + (end.x - start.x) * amount) - first.x) * 640,
                y: ((start.y + (end.y - start.y) * amount) - first.y) * 360
            )
        }
    }
}

private struct EnemyPreviewSprite: View {
    let url: URL?
    let name: String
    let selected: Bool

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
            } else {
                ZStack {
                    Circle().fill(.orange.opacity(0.8))
                    Text(String(name.prefix(1)).uppercased()).font(.caption.bold()).foregroundStyle(.black)
                }
            }
        }
        .padding(3)
        .background(selected ? Color.accentColor.opacity(0.35) : .clear, in: Circle())
    }
}

struct MissionInspector: View {
    @ObservedObject var workspace: EditorWorkspace

    var body: some View {
        Group {
            if workspace.selectedMission == nil {
                ContentUnavailableView("No mission selected", systemImage: "sidebar.right")
            } else {
                Form {
                    if selectedEvent != nil { eventFields } else { missionFields }
                    diagnostics
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle(selectedEvent == nil ? "Mission Inspector" : "Event Inspector")
        .toolbar {
            if selectedEvent != nil {
                ToolbarItem { Button("Mission") { workspace.selectedMissionEventIndex = nil } }
            }
        }
    }

    private var selectedEvent: MissionTimelineEvent? {
        guard let mission = workspace.selectedMission,
              let index = workspace.selectedMissionEventIndex,
              mission.definition.timeline.indices.contains(index) else { return nil }
        return mission.definition.timeline[index]
    }

    @ViewBuilder private var missionFields: some View {
        if let mission = workspace.selectedMission?.definition {
            Section("Mission") {
                TextField("Name", text: missionBinding(\.metadata.displayName, fallback: mission.metadata.displayName))
                TextField("ID", text: missionBinding(\.id, fallback: mission.id))
                Picker("Status", selection: missionBinding(\.authoringStatus, fallback: mission.authoringStatus)) {
                    ForEach(AuthoringStatus.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Stepper("Number: \(mission.metadata.missionNumber)", value: missionBinding(\.metadata.missionNumber, fallback: mission.metadata.missionNumber), in: 1...999)
                Stepper("Hero level: \(mission.metadata.recommendedHeroLevel)", value: missionBinding(\.metadata.recommendedHeroLevel, fallback: mission.metadata.recommendedHeroLevel), in: 1...999)
                TextField("Location ID", text: missionBinding(\.metadata.locationId, fallback: mission.metadata.locationId))
            }
            Section("Presentation") {
                TextField("Background", text: missionBinding(\.background.resourcePath, fallback: mission.background.resourcePath))
                Stepper("Seed: \(mission.background.seed ?? 0)", value: optionalSeedBinding, in: 0...9999)
                Picker("Completion", selection: missionBinding(\.completion.kind, fallback: mission.completion.kind)) {
                    ForEach(MissionCompletionKind.allCases, id: \.self) { Text(humanize($0.rawValue)).tag($0) }
                }
            }
            Section("Star Objectives") {
                ForEach(Array(mission.metadata.starObjectives.enumerated()), id: \.offset) { index, objective in
                    VStack(alignment: .leading) {
                        Picker("Star \(index + 1)", selection: objectiveKindBinding(index, fallback: objective.kind)) {
                            ForEach(StarObjectiveKind.allCases, id: \.self) { Text(humanize($0.rawValue)).tag($0) }
                        }
                        if objective.kind == .finishWithHealth {
                            HStack {
                                Slider(value: objectiveHealthBinding(index, fallback: objective.minimumPercentage ?? 0.75), in: 0.05...1, step: 0.05)
                                Text("\(Int((objective.minimumPercentage ?? 0.75) * 100))%")
                                    .monospacedDigit().frame(width: 42)
                            }
                        }
                    }
                    .contextMenu { Button("Remove", role: .destructive) { removeObjective(index) } }
                }
                Button("Add Objective") { addObjective() }
                    .disabled(mission.metadata.starObjectives.count >= 3)
            }
        }
    }

    @ViewBuilder private var eventFields: some View {
        if let event = selectedEvent {
            Section("Event") {
                TextField("Time (seconds)", value: eventTimeBinding, format: .number.precision(.fractionLength(2)))
                Picker("Type", selection: eventTypeBinding) {
                    Text("Spawn Formation").tag(EventEditorKind.spawnFormation)
                    Text("Zoom Out").tag(EventEditorKind.zoomOut)
                    Text("Zoom In").tag(EventEditorKind.zoomIn)
                }
            }
            switch event.action {
            case let .spawnFormation(spawn): spawnFields(spawn)
            case let .zoomOut(zoom): zoomFields(zoom)
            case let .zoomIn(zoom): zoomFields(zoom)
            }
            Section {
                Button("Duplicate Event") { workspace.duplicateSelectedMissionEvent() }
                Button("Delete Event", role: .destructive) { workspace.deleteSelectedMissionEvent() }
            }
        }
    }

    @ViewBuilder private func spawnFields(_ spawn: SpawnFormationEvent) -> some View {
        Section("Enemy") {
            Picker("Type", selection: spawnBinding(\.enemy.id, fallback: spawn.enemy.id)) {
                ForEach(EnemyCatalogue.all) { enemy in Text(enemy.displayName).tag(enemy.id) }
            }
            Stepper("Level: \(spawn.enemy.level)", value: spawnBinding(\.enemy.level, fallback: spawn.enemy.level), in: 1...100)
        }
        Section("Spawn") {
            Picker("Edge", selection: spawnBinding(\.spawnPosition.edge, fallback: spawn.spawnPosition.edge)) {
                ForEach(SpawnEdge.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            TextField("Edge offset", value: spawnBinding(\.spawnPosition.xOffset, fallback: spawn.spawnPosition.xOffset), format: .number)
            TextField("Y", value: spawnBinding(\.spawnPosition.y, fallback: spawn.spawnPosition.y), format: .number)
        }
        Section("Formation") {
            Picker("Kind", selection: formationKindBinding) {
                ForEach(FormationKind.allCases, id: \.self) { Text(humanize($0.rawValue)).tag($0) }
            }
            formationSpecificFields(spawn.formation)
        }
        Section("Movement Path") {
            Picker("Kind", selection: pathKindBinding) {
                ForEach(MovementPathKind.allCases, id: \.self) { Text(humanize($0.rawValue)).tag($0) }
            }
            pathSpecificFields(spawn.path)
        }
    }

    @ViewBuilder private func formationSpecificFields(_ formation: FormationDefinition) -> some View {
        switch formation {
        case let .line(value):
            Picker("Axis", selection: lineBinding(\.axis, fallback: value.axis)) { ForEach(FormationAxis.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
            Stepper("Count: \(value.count)", value: lineBinding(\.count, fallback: value.count), in: 1...50)
            TextField("Spacing", value: lineBinding(\.spacing, fallback: value.spacing), format: .number)
        case let .slottedLine(value):
            Picker("Axis", selection: slottedBinding(\.axis, fallback: value.axis)) { ForEach(FormationAxis.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
            Stepper("Slots: \(value.slotCount)", value: slottedBinding(\.slotCount, fallback: value.slotCount), in: 1...50)
            TextField("Spacing", value: slottedBinding(\.spacing, fallback: value.spacing), format: .number)
            TextField("Occupied slots", text: occupiedSlotsBinding)
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
        case let .freeform(value):
            LabeledContent("Members", value: "\(value.members.count)")
            Text("Freeform point editing will use draggable preview handles in the next pass.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func pathSpecificFields(_ path: MovementPathDefinition) -> some View {
        switch path {
        case let .straight(value):
            TextField("Speed (px/s)", value: straightBinding(\.speed, fallback: value.speed), format: .number)
        case let .sine(value):
            TextField("Speed (px/s)", value: sineBinding(\.speed, fallback: value.speed), format: .number)
            TextField("Amplitude (px)", value: sineBinding(\.amplitude, fallback: value.amplitude), format: .number)
            TextField("Frequency (Hz)", value: sineBinding(\.frequency, fallback: value.frequency), format: .number)
            TextField("Member phase", value: sineBinding(\.phaseOffset, fallback: value.phaseOffset), format: .number)
        case let .waypoints(value):
            TextField("Duration (seconds)", value: waypointBinding(\.duration, fallback: value.duration), format: .number)
            LabeledContent("Points", value: "\(value.points.count)")
            Text("Waypoint handles will become draggable in the path-authoring pass.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func zoomFields<Zoom>(_ zoom: Zoom) -> some View where Zoom: Sendable {
        Section("Camera") {
            TextField("Multiplier", value: zoomMultiplierBinding, format: .number.precision(.fractionLength(2)))
            TextField("Duration", value: zoomDurationBinding, format: .number.precision(.fractionLength(2)))
        }
    }

    @ViewBuilder private var diagnostics: some View {
        Section("Diagnostics") {
            if workspace.diagnostics.isEmpty {
                Label("No issues", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                ForEach(workspace.diagnostics) { diagnostic in
                    Label(diagnostic.message, systemImage: diagnostic.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(diagnostic.severity == .error ? .red : .orange)
                }
            }
        }
    }

    private enum EventEditorKind: Hashable { case spawnFormation, zoomOut, zoomIn }
    private var eventTypeBinding: Binding<EventEditorKind> {
        Binding(get: {
            switch selectedEvent?.action {
            case .spawnFormation: .spawnFormation
            case .zoomOut: .zoomOut
            case .zoomIn: .zoomIn
            case nil: .spawnFormation
            }
        }, set: { kind in
            workspace.updateSelectedMissionEvent { event in
                switch kind {
                case .spawnFormation: event.action = .spawnFormation(.init(enemy: .init(id: "fly_basic", level: 1), formation: .line(.init(axis: .vertical, count: 3, spacing: 48)), path: .straight(.init(speed: 120)), spawnPosition: .init(edge: .right, xOffset: 24, y: 180)))
                case .zoomOut: event.action = .zoomOut(.init(multiplier: 0.8, duration: 1))
                case .zoomIn: event.action = .zoomIn(.init(multiplier: 1, duration: 1))
                }
            }
        })
    }

    private func missionBinding<Value>(
        _ keyPath: WritableKeyPath<MissionDefinition, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { workspace.selectedMission?.definition[keyPath: keyPath] ?? fallback },
            set: { value in
                guard workspace.selectedMission != nil else { return }
                workspace.updateSelectedMission { $0[keyPath: keyPath] = value }
            }
        )
    }
    private var eventTimeBinding: Binding<Double> { Binding(get: { selectedEvent?.at ?? 0 }, set: { value in workspace.updateSelectedMissionEvent { $0.at = max(0, value) } }) }
    private func spawnBinding<Value>(
        _ keyPath: WritableKeyPath<SpawnFormationEvent, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                guard case let .spawnFormation(value)? = selectedEvent?.action else { return fallback }
                return value[keyPath: keyPath]
            },
            set: { value in mutateSpawn { $0[keyPath: keyPath] = value } }
        )
    }
    private func mutateSpawn(_ change: (inout SpawnFormationEvent) -> Void) { workspace.updateSelectedMissionEvent { event in guard case var .spawnFormation(value) = event.action else { return }; change(&value); event.action = .spawnFormation(value) } }

    private var formationKindBinding: Binding<FormationKind> { Binding(get: { if case let .spawnFormation(v)? = selectedEvent?.action { v.formation.kind } else { .line } }, set: { kind in mutateSpawn { $0.formation = defaultFormation(kind) } }) }
    private var pathKindBinding: Binding<MovementPathKind> { Binding(get: { if case let .spawnFormation(v)? = selectedEvent?.action { v.path.kind } else { .straight } }, set: { kind in mutateSpawn { $0.path = defaultPath(kind) } }) }

    private func formationBinding<Value, Payload>(_ extract: @escaping (FormationDefinition) -> Payload?, _ wrap: @escaping (Payload) -> FormationDefinition, _ keyPath: WritableKeyPath<Payload, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { guard case let .spawnFormation(spawn)? = selectedEvent?.action, let value = extract(spawn.formation) else { return fallback }; return value[keyPath: keyPath] }, set: { newValue in mutateSpawn { spawn in guard var value = extract(spawn.formation) else { return }; value[keyPath: keyPath] = newValue; spawn.formation = wrap(value) } })
    }
    private func lineBinding<Value>(_ kp: WritableKeyPath<LineFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .line(v) = $0 { v } else { nil } }, FormationDefinition.line, kp, fallback: fallback) }
    private func slottedBinding<Value>(_ kp: WritableKeyPath<SlottedLineFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .slottedLine(v) = $0 { v } else { nil } }, FormationDefinition.slottedLine, kp, fallback: fallback) }
    private func vBinding<Value>(_ kp: WritableKeyPath<VFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .v(v) = $0 { v } else { nil } }, FormationDefinition.v, kp, fallback: fallback) }
    private func gridBinding<Value>(_ kp: WritableKeyPath<StaggeredGridFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .staggeredGrid(v) = $0 { v } else { nil } }, FormationDefinition.staggeredGrid, kp, fallback: fallback) }
    private func arcBinding<Value>(_ kp: WritableKeyPath<ArcFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .arc(v) = $0 { v } else { nil } }, FormationDefinition.arc, kp, fallback: fallback) }

    private func pathBinding<Value, Payload>(_ extract: @escaping (MovementPathDefinition) -> Payload?, _ wrap: @escaping (Payload) -> MovementPathDefinition, _ kp: WritableKeyPath<Payload, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { guard case let .spawnFormation(spawn)? = selectedEvent?.action, let value = extract(spawn.path) else { return fallback }; return value[keyPath: kp] }, set: { newValue in mutateSpawn { spawn in guard var value = extract(spawn.path) else { return }; value[keyPath: kp] = newValue; spawn.path = wrap(value) } })
    }
    private func straightBinding<Value>(_ kp: WritableKeyPath<StraightPath, Value>, fallback: Value) -> Binding<Value> { pathBinding({ if case let .straight(v) = $0 { v } else { nil } }, MovementPathDefinition.straight, kp, fallback: fallback) }
    private func sineBinding<Value>(_ kp: WritableKeyPath<SinePath, Value>, fallback: Value) -> Binding<Value> { pathBinding({ if case let .sine(v) = $0 { v } else { nil } }, MovementPathDefinition.sine, kp, fallback: fallback) }
    private func waypointBinding<Value>(_ kp: WritableKeyPath<WaypointPath, Value>, fallback: Value) -> Binding<Value> { pathBinding({ if case let .waypoints(v) = $0 { v } else { nil } }, MovementPathDefinition.waypoints, kp, fallback: fallback) }

    private var occupiedSlotsBinding: Binding<String> { Binding(get: { if case let .spawnFormation(spawn)? = selectedEvent?.action, case let .slottedLine(v) = spawn.formation { v.occupiedSlots.map(String.init).joined(separator: ", ") } else { "" } }, set: { text in mutateSpawn { spawn in guard case var .slottedLine(v) = spawn.formation else { return }; v.occupiedSlots = text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }; spawn.formation = .slottedLine(v) } }) }
    private var optionalSeedBinding: Binding<Int> { Binding(
        get: { Int(workspace.selectedMission?.definition.background.seed ?? 0) },
        set: { value in workspace.updateSelectedMission { $0.background.seed = UInt64(max(0, value)) } }
    ) }
    private func objectiveKindBinding(_ index: Int, fallback: StarObjectiveKind) -> Binding<StarObjectiveKind> { Binding(get: { guard let objectives = workspace.selectedMission?.definition.metadata.starObjectives, objectives.indices.contains(index) else { return fallback }; return objectives[index].kind }, set: { kind in workspace.updateSelectedMission { guard $0.metadata.starObjectives.indices.contains(index) else { return }; $0.metadata.starObjectives[index] = .init(kind: kind, minimumPercentage: kind == .finishWithHealth ? 0.75 : nil) } }) }
    private func objectiveHealthBinding(_ index: Int, fallback: Double) -> Binding<Double> { Binding(get: { guard let objectives = workspace.selectedMission?.definition.metadata.starObjectives, objectives.indices.contains(index) else { return fallback }; return objectives[index].minimumPercentage ?? fallback }, set: { value in workspace.updateSelectedMission { guard $0.metadata.starObjectives.indices.contains(index) else { return }; $0.metadata.starObjectives[index].minimumPercentage = value } }) }
    private func addObjective() { workspace.updateSelectedMission { $0.metadata.starObjectives.append(.init(kind: .defeatAllEnemies)) } }
    private func removeObjective(_ index: Int) { workspace.updateSelectedMission { guard $0.metadata.starObjectives.indices.contains(index) else { return }; $0.metadata.starObjectives.remove(at: index) } }

    private var zoomMultiplierBinding: Binding<Double> { Binding(get: { switch selectedEvent?.action { case let .zoomOut(v): v.multiplier; case let .zoomIn(v): v.multiplier; default: 1 } }, set: { value in workspace.updateSelectedMissionEvent { event in switch event.action { case var .zoomOut(v): v.multiplier = value; event.action = .zoomOut(v); case var .zoomIn(v): v.multiplier = value; event.action = .zoomIn(v); default: break } } }) }
    private var zoomDurationBinding: Binding<Double> { Binding(get: { switch selectedEvent?.action { case let .zoomOut(v): v.duration; case let .zoomIn(v): v.duration; default: 1 } }, set: { value in workspace.updateSelectedMissionEvent { event in switch event.action { case var .zoomOut(v): v.duration = max(0, value); event.action = .zoomOut(v); case var .zoomIn(v): v.duration = max(0, value); event.action = .zoomIn(v); default: break } } }) }

    private func defaultFormation(_ kind: FormationKind) -> FormationDefinition { switch kind { case .line: .line(.init(axis: .vertical, count: 3, spacing: 48)); case .slottedLine: .slottedLine(.init(axis: .vertical, slotCount: 5, spacing: 48, occupiedSlots: [0, 2, 4])); case .v: .v(.init(count: 5, spacing: 36, depth: 28)); case .staggeredGrid: .staggeredGrid(.init(rows: 2, columns: 3, spacingX: 48, spacingY: 48)); case .arc: .arc(.init(count: 5, radius: 80, startAngle: -60, endAngle: 60)); case .freeform: .freeform(.init(members: [.init(id: "member_1", offset: .init(x: 0, y: 0))])) } }
    private func defaultPath(_ kind: MovementPathKind) -> MovementPathDefinition { switch kind { case .straight: .straight(.init(speed: 120)); case .sine: .sine(.init(speed: 120, amplitude: 40, frequency: 0.5)); case .waypoints: .waypoints(.init(duration: 6, points: [.init(x: 1.1, y: 0.5), .init(x: 0.65, y: 0.3), .init(x: -0.1, y: 0.5)])) } }
    private func humanize(_ text: String) -> String { text.reduce(into: "") { result, character in if character.isUppercase { result.append(" ") }; result.append(character) }.capitalized }
}
