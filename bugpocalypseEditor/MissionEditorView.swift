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
                    workspace: workspace,
                    playhead: playhead,
                    selectedEventIndex: workspace.selectedMissionEventIndex,
                    selectedMemberIndex: workspace.selectedFormationMemberIndex,
                    enemyAssetURL: workspace.enemyAssetURL,
                    selectEvent: selectTimelineEvent,
                    selectMember: selectFormationMember
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
            Button(action: workspace.playSelectedMission) {
                Label("Play Mission", systemImage: "play.fill")
            }
            .buttonStyle(.bordered)
            Menu {
                Button("Spawn Formation") {
                    workspace.addMissionEvent(.spawnFormation(Self.defaultSpawn))
                }
                Button("Play Choreography") {
                    if let choreography = workspace.choreographies.first,
                       let path = workspace.resourcePath(for: choreography.fileURL) {
                        workspace.addMissionEvent(.playChoreography(.init(choreographyReference: .init(resourcePath: path))))
                    }
                }
                .disabled(workspace.choreographies.isEmpty)
                Button("Spawn Boss") {
                    workspace.addMissionEvent(.spawnBoss(Self.defaultBossSpawn))
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
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(sortedEvents, id: \.offset) { item in
                            Button {
                                selectTimelineEvent(item.offset, item.element.at)
                                withAnimation { proxy.scrollTo(item.offset, anchor: .center) }
                            } label: {
                                TimelineEventCard(
                                    event: item.element,
                                    isSelected: workspace.selectedMissionEventIndex == item.offset
                                )
                            }
                            .buttonStyle(.plain)
                            .id(item.offset)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onChange(of: workspace.selectedMissionEventIndex) { _, index in
                    guard let index else { return }
                    withAnimation { proxy.scrollTo(index, anchor: .center) }
                }
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

    private func selectTimelineEvent(_ index: Int, _ at: Double) {
        workspace.selectMissionEvent(index)
        playhead = min(at + 2, missionDuration)
        isPlaying = false
    }

    private func selectFormationMember(_ index: Int, _ eventIndex: Int, _ at: Double) {
        selectTimelineEvent(eventIndex, at)
        workspace.selectedFormationMemberIndex = index
    }

    private static let defaultSpawn = SpawnFormationEvent(
        enemy: .init(id: "fly_basic", level: 1),
        formation: .line(.init(axis: .vertical, count: 3, spacing: 48)),
        path: .straight(.init(speed: 120)),
        spawnPosition: .init(edge: .right, xOffset: 24, y: 180)
    )
    private static let defaultBossSpawn = SpawnBossEvent(id: "boss1", level: 1, y: 180)
}

private struct TimelineEventCard: View {
    let event: MissionTimelineEvent
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.caption.bold()).lineLimit(1)
                switch event.action {
                case let .spawnFormation(value):
                    Text("Lv \(value.enemy.level)")
                        .font(.system(.caption2, design: .rounded).bold())
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .foregroundStyle(.white)
                        .background(color, in: Capsule())
                case let .spawnBoss(value):
                    Text("Lv \(value.level)")
                        .font(.system(.caption2, design: .rounded).bold())
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .foregroundStyle(.white)
                        .background(color, in: Capsule())
                default:
                    EmptyView()
                }
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
        case .playChoreography: "Choreography"
        case let .spawnBoss(value): "Boss: \(value.id)"
        case .zoomOut: "Zoom Out"
        case .zoomIn: "Zoom In"
        }
    }
    private var detail: String {
        switch event.action {
        case let .spawnFormation(value):
            if value.formationReference != nil || value.pathReference != nil {
                return [
                    value.formationReference == nil ? nil : "saved formation",
                    value.pathReference == nil ? nil : "saved path"
                ].compactMap { $0 }.joined(separator: " · ")
            }
            return "\(value.formation.offsets().count) × \(value.formation.kind.rawValue)"
        case let .playChoreography(value): return value.choreographyReference.resourcePath
        case let .spawnBoss(value): return "Enters at y \(Int(value.y))"
        case let .zoomOut(value): return String(format: "%.2f× · %.1f s", value.multiplier, value.duration)
        case let .zoomIn(value): return String(format: "%.2f× · %.1f s", value.multiplier, value.duration)
        }
    }
    private var icon: String {
        switch event.action {
        case .spawnFormation: "ant.fill"
        case .playChoreography: "square.stack.3d.up.fill"
        case .spawnBoss: "crown.fill"
        case .zoomOut, .zoomIn: "camera.fill"
        }
    }
    private var color: Color {
        switch event.action {
        case .spawnFormation: .orange
        case .playChoreography: .mint
        case .spawnBoss: .red
        case .zoomOut, .zoomIn: .blue
        }
    }
}

struct MissionPreview: View {
    /// Preview enemies are assumed defeated after this long, even when their
    /// authored path loops or ends by staying on screen.
    private let maximumPreviewLifetime: Double = 15

    let mission: MissionDefinition
    @ObservedObject var workspace: EditorWorkspace
    let playhead: Double
    let selectedEventIndex: Int?
    let selectedMemberIndex: Int?
    let enemyAssetURL: (String) -> URL?
    let selectEvent: (Int, Double) -> Void
    let selectMember: (Int, Int, Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 640, geometry.size.height / 360)
            let origin = CGPoint(x: (geometry.size.width - 640 * scale) / 2, y: (geometry.size.height - 360 * scale) / 2)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.03, green: 0.08, blue: 0.15), Color(red: 0.08, green: 0.16, blue: 0.18)], startPoint: .top, endPoint: .bottom)
                previewGrid(origin: origin, scale: scale)
                ForEach(Array(mission.timeline.enumerated()), id: \.offset) { index, event in
                    if case let .spawnFormation(spawn) = event.action,
                       event.at <= playhead,
                       playhead - event.at <= maximumPreviewLifetime {
                        formation(spawn, eventIndex: index, eventTime: event.at, elapsed: playhead - event.at, selected: selectedEventIndex == index, selectedMember: selectedEventIndex == index ? selectedMemberIndex : nil, origin: origin, scale: scale)
                    }
                    if case let .playChoreography(play) = event.action {
                        choreography(play, missionEventIndex: index, missionEventTime: event.at, origin: origin, scale: scale)
                    }
                    if case let .spawnBoss(spawn) = event.action,
                       event.at <= playhead,
                       playhead - event.at <= maximumPreviewLifetime {
                        boss(spawn, eventIndex: index, eventTime: event.at, elapsed: playhead - event.at, selected: selectedEventIndex == index, origin: origin, scale: scale)
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
    private func choreography(_ play: PlayChoreographyEvent, missionEventIndex: Int, missionEventTime: Double, origin: CGPoint, scale: CGFloat) -> some View {
        if let choreography = workspace.choreography(for: play.choreographyReference) {
            ForEach(Array(choreography.timeline.enumerated()), id: \.offset) { _, child in
                let spawnTime = missionEventTime + child.at
                if spawnTime <= playhead, playhead - spawnTime <= maximumPreviewLifetime {
                    formation(adjustedSpawn(child.spawn, by: play.enemyLevelOffset ?? 0), eventIndex: missionEventIndex, eventTime: spawnTime, elapsed: playhead - spawnTime, selected: selectedEventIndex == missionEventIndex, selectedMember: nil, origin: origin, scale: scale)
                }
            }
        }
    }

    private func adjustedSpawn(_ spawn: SpawnFormationEvent, by offset: Int) -> SpawnFormationEvent {
        var result = spawn
        let (level, overflow) = spawn.enemy.level.addingReportingOverflow(offset)
        result.enemy.level = overflow ? (offset >= 0 ? Int.max : 1) : max(1, level)
        return result
    }

    @ViewBuilder
    private func formation(_ spawn: SpawnFormationEvent, eventIndex: Int, eventTime: Double, elapsed: Double, selected: Bool, selectedMember: Int?, origin: CGPoint, scale: CGFloat) -> some View {
        let pathDefinition = workspace.path(for: spawn.pathReference) ?? spawn.path
        let formation = workspace.formation(for: spawn.formationReference) ?? spawn.formation
        let dropDiagnostics = DropAuthoring.diagnostics(for: spawn.drops, memberCount: formation.offsets().count)
        ForEach(Array(formation.offsets().enumerated()), id: \.offset) { index, offset in
            let legacyAnchorX = spawn.spawnPosition.edge == .right ? 640 + spawn.spawnPosition.xOffset : -spawn.spawnPosition.xOffset
            let usesAuthoredStart = pathDefinition.usesAuthoredStart
            let path = sampledPath(
                pathDefinition,
                elapsed: max(0, elapsed - Double(index) * (formation.followDelay ?? 0))
            )
            let rawY = (usesAuthoredStart ? 0 : spawn.spawnPosition.y) + offset.y + path.y
            let transformedY = spawn.pathTransform?.mirrorY == true ? 360 - rawY : rawY
            let position = CGPoint(
                x: origin.x + ((usesAuthoredStart ? 0 : legacyAnchorX) + offset.x + path.x) * scale,
                y: origin.y + (transformedY + (spawn.pathTransform?.yOffset ?? 0)) * scale
            )
            let spriteSize = enemyPreviewSize(for: spawn.enemy.id)
            EnemyPreviewSprite(url: enemyAssetURL(spawn.enemy.id), name: spawn.enemy.id, selected: selected && selectedMember == index)
                .frame(width: spriteSize.width * scale, height: spriteSize.height * scale)
                .overlay(alignment: .top) {
                    Text("Lv \(spawn.enemy.level)")
                        .font(.system(size: max(7, 9 * scale), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, max(3, 4 * scale))
                        .padding(.vertical, max(1, 2 * scale))
                        .background(.black.opacity(0.78), in: Capsule())
                        .offset(y: -max(14, spriteSize.height * scale / 2 + 8 * scale))
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    if selected { Text("\(index)").font(.system(size: 8)).foregroundStyle(.white).offset(y: 12 * scale) }
                }
                .overlay(alignment: .topTrailing) {
                    if let drop = DropAuthoring.drop(for: index, in: spawn.drops) {
                        DropBadge(drop: drop, scale: scale)
                            .offset(x: max(8, spriteSize.width * scale / 2 - 4), y: -max(8, spriteSize.height * scale / 2 - 4))
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Circle())
                .onTapGesture { selectMember(index, eventIndex, eventTime) }
                .position(position)
        }
        if !dropDiagnostics.isEmpty {
            Label("\(dropDiagnostics.count) invalid drop\(dropDiagnostics.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.bold()).foregroundStyle(.orange)
                .padding(5).background(.black.opacity(0.8), in: Capsule())
                .position(x: origin.x + 580 * scale, y: origin.y + 20 * scale)
        }
    }

    /// Mirrors `BossEnemy`'s authored components and entrance: it starts 145
    /// pixels beyond the right edge, then stops at x = 510.
    @ViewBuilder
    private func boss(_ spawn: SpawnBossEvent, eventIndex: Int, eventTime: Double, elapsed: Double, selected: Bool, origin: CGPoint, scale: CGFloat) -> some View {
        let routePosition = bossPosition(for: spawn, elapsed: elapsed)
        let position = CGPoint(x: origin.x + routePosition.x * scale, y: origin.y + routePosition.y * scale)
        let bossSize = CGSize(width: 330, height: 250)
        ZStack {
            BossComponentSprite(url: workspace.assetURL(for: "enemies/boss1/body.png"), name: spawn.id)
                .frame(width: 246 * scale, height: 224 * scale)
            BossComponentSprite(url: workspace.assetURL(for: "enemies/boss1/weapon.png"), name: spawn.id)
                .frame(width: 217 * scale, height: 113 * scale)
                .offset(x: -58 * scale, y: 49 * scale)
            BossComponentSprite(url: workspace.assetURL(for: "enemies/boss1/weapon.png"), name: spawn.id, flipVertically: true)
                .frame(width: 217 * scale, height: 113 * scale)
                .offset(x: 52 * scale, y: 43 * scale)
            BossComponentSprite(url: workspace.assetURL(for: "enemies/boss1/head.png"), name: spawn.id)
                .frame(width: 149 * scale, height: 75 * scale)
                .offset(x: -3 * scale, y: -54 * scale)
            Text("Lv \(spawn.level)")
                .font(.system(size: max(7, 9 * scale), weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, max(3, 4 * scale)).padding(.vertical, max(1, 2 * scale))
                .background(.black.opacity(0.78), in: Capsule())
                .offset(y: -max(14, bossSize.height * scale / 2 + 8 * scale))
        }
        .frame(width: bossSize.width * scale, height: bossSize.height * scale)
        .background(selected ? Color.accentColor.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { selectEvent(eventIndex, eventTime) }
        .position(position)
    }

    private func bossPosition(for spawn: SpawnBossEvent, elapsed: Double) -> ContentPoint {
        guard let path = spawn.path else {
            return .init(x: max(640 + 145 - 110 * elapsed, 510.0), y: spawn.y)
        }
        switch path {
        case .straight, .sine:
            let offset = path.offset(elapsed: elapsed)
            return .init(x: 640 + 145 + offset.x, y: spawn.y + offset.y)
        case .waypoints, .bezier:
            return sampledPath(path, elapsed: elapsed)
        }
    }

    /// Runtime sprites use their atlas dimensions without a common size
    /// normalization. Preserve those dimensions in the editor so bosses and
    /// heavy enemies read at their intended scale.
    private func enemyPreviewSize(for enemyID: String) -> CGSize {
        guard let url = enemyAssetURL(enemyID), let image = NSImage(contentsOf: url) else {
            return CGSize(width: 42, height: 42)
        }
        return CGSize(width: max(1, image.size.width), height: max(1, image.size.height))
    }

    private func sampledPath(_ path: MovementPathDefinition, elapsed: Double) -> ContentPoint {
        switch path {
        case .straight, .sine:
            return path.offset(elapsed: elapsed)
        case let .waypoints(value):
            guard value.points.count >= 2, value.duration > 0 else { return .init(x: 0, y: 0) }
            let point = value.point(at: elapsed)
            return .init(
                x: point.x * 640,
                y: point.y * 360
            )
        case let .bezier(value):
            guard value.duration > 0 else { return .init(x: 0, y: 0) }
            let point = value.point(at: value.effectiveElapsed(at: elapsed) / value.duration)
            return .init(
                x: point.x * 640,
                y: point.y * 360
            )
        }
    }
}

private struct DropBadge: View {
    let drop: DropDefinition
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "gift.fill").font(.system(size: max(7, 10 * scale)))
            Text("\(drop.amount)").font(.system(size: max(7, 9 * scale), weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 3).padding(.vertical, 2)
        .background(color, in: Capsule())
    }

    private var color: Color {
        switch drop.kind { case .health: .green; case .overdrive: .cyan; case .rage: .red; case .coins: .yellow }
    }
}

private extension MovementPathDefinition {
    /// Normalized routes include their own entry point; the older pixel paths
    /// continue to use the event's left/right spawn anchor.
    var usesAuthoredStart: Bool {
        switch self {
        case .waypoints, .bezier: true
        case .straight, .sine: false
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

private struct BossComponentSprite: View {
    let url: URL?
    let name: String
    var flipVertically = false

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
                    .scaleEffect(x: 1, y: flipVertically ? -1 : 1)
            } else {
                Rectangle().fill(.red.opacity(0.7)).overlay {
                    Text(String(name.prefix(1)).uppercased()).font(.caption.bold()).foregroundStyle(.white)
                }
            }
        }
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
                    Text("Play Choreography").tag(EventEditorKind.playChoreography)
                    Text("Spawn Boss").tag(EventEditorKind.spawnBoss)
                    Text("Zoom Out").tag(EventEditorKind.zoomOut)
                    Text("Zoom In").tag(EventEditorKind.zoomIn)
                }
            }
            switch event.action {
            case let .spawnFormation(spawn): spawnFields(spawn)
            case let .playChoreography(play): choreographyFields(play)
            case let .spawnBoss(spawn): bossFields(spawn)
            case let .zoomOut(zoom): zoomFields(zoom)
            case let .zoomIn(zoom): zoomFields(zoom)
            }
            Section {
                Button("Duplicate Event") { workspace.duplicateSelectedMissionEvent() }
                Button("Delete Event", role: .destructive) { workspace.deleteSelectedMissionEvent() }
            }
        }
    }

    @ViewBuilder private func choreographyFields(_ play: PlayChoreographyEvent) -> some View {
        Section("Choreography") {
            Picker("Resource", selection: choreographyReferencePathBinding) {
                ForEach(workspace.choreographies) { document in
                    Text(document.definition.name).tag(workspace.resourcePath(for: document.fileURL) ?? "")
                }
            }
            Text("Runs this reusable local formation timeline at the event time.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Difficulty") {
            Stepper("Enemy level offset: \(play.enemyLevelOffset ?? 0)", value: choreographyLevelOffsetBinding, in: -99...99)
            Text("This offset applies to every formation spawn while preserving their authored level differences.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func bossFields(_ spawn: SpawnBossEvent) -> some View {
        Section("Boss") {
            Picker("Type", selection: bossBinding(\.id, fallback: spawn.id)) {
                Text("Boss 1").tag("boss1")
            }
            Stepper("Level: \(spawn.level)", value: bossBinding(\.level, fallback: spawn.level), in: 1...100)
        }
        Section("Spawn") {
            TextField("Y", value: bossBinding(\.y, fallback: spawn.y), format: .number)
            Text("Without a path, the preview shows the runtime entrance and final x position.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Movement Path") {
            Toggle("Use authored path", isOn: bossHasPathBinding)
            if let path = spawn.path {
                Picker("Kind", selection: bossPathKindBinding) {
                    ForEach(MovementPathKind.allCases, id: \.self) { Text(humanize($0.rawValue)).tag($0) }
                }
                bossPathFields(path)
            }
        }
    }

    @ViewBuilder private func bossPathFields(_ path: MovementPathDefinition) -> some View {
        switch path {
        case let .straight(value):
            TextField("Speed (px/s)", value: bossStraightBinding(\.speed, fallback: value.speed), format: .number)
        case let .sine(value):
            TextField("Speed (px/s)", value: bossSineBinding(\.speed, fallback: value.speed), format: .number)
            TextField("Amplitude (px)", value: bossSineBinding(\.amplitude, fallback: value.amplitude), format: .number)
            TextField("Frequency (Hz)", value: bossSineBinding(\.frequency, fallback: value.frequency), format: .number)
        case let .waypoints(value):
            TextField("Travel duration (seconds)", value: bossWaypointBinding(\.duration, fallback: value.duration), format: .number)
            Toggle("Loop after completion", isOn: bossWaypointLoopBinding)
            if value.loopToPoint != nil {
                Picker("Loop to waypoint", selection: bossWaypointLoopToBinding) {
                    ForEach(value.points.indices, id: \.self) { Text("Point \($0 + 1)").tag($0) }
                }
            }
            ForEach(Array(value.points.enumerated()), id: \.offset) { index, point in
                LabeledContent("Point \(index + 1)") {
                    HStack {
                        TextField("X", value: bossWaypointPointBinding(index, \.x, fallback: point.x), format: .number)
                        TextField("Y", value: bossWaypointPointBinding(index, \.y, fallback: point.y), format: .number)
                        TextField("Stay", value: bossWaypointPointBinding(index, \.stayDuration, fallback: point.stayDuration), format: .number)
                    }
                }
            }
        case let .bezier(value):
            TextField("Duration (seconds)", value: bossBezierBinding(\.duration, fallback: value.duration), format: .number)
            Text("Use this for a custom curved entrance or loop.").font(.caption).foregroundStyle(.secondary)
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
            Picker("Source", selection: formationSourceBinding) {
                Text("Inline").tag(EncounterSource.inline)
                Text("Saved formation").tag(EncounterSource.saved)
            }
            if spawn.formationReference == nil {
                Picker("Kind", selection: formationKindBinding) {
                    ForEach(FormationKind.allCases, id: \.self) { Text(humanize($0.rawValue)).tag($0) }
                }
                formationSpecificFields(spawn.formation)
            } else {
                Picker("Formation", selection: formationReferencePathBinding) {
                    ForEach(workspace.formations) { document in
                        Text(document.definition.name).tag(workspace.resourcePath(for: document.fileURL) ?? "")
                    }
                }
                Text("This event uses the saved formation at runtime.").font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Movement Path") {
            Picker("Source", selection: pathSourceBinding) {
                Text("Inline").tag(EncounterSource.inline)
                Text("Saved path").tag(EncounterSource.saved)
            }
            if spawn.pathReference == nil {
                Picker("Kind", selection: pathKindBinding) {
                    ForEach(MovementPathKind.allCases, id: \.self) { Text(humanize($0.rawValue)).tag($0) }
                }
                pathSpecificFields(spawn.path)
            } else {
                Picker("Path", selection: pathReferencePathBinding) {
                    ForEach(workspace.paths) { document in
                        Text(document.definition.name).tag(workspace.resourcePath(for: document.fileURL) ?? "")
                    }
                }
                Text("This event uses the saved path at runtime.").font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Path Transform") {
            Toggle("Mirror vertically", isOn: mirrorYBinding)
            TextField("Vertical shift", value: yOffsetBinding, format: .number)
            Text("Mirror around the gameplay centre, then apply the vertical shift. This affects the formation and its complete route.")
                .font(.caption).foregroundStyle(.secondary)
        }
        dropsFields(spawn)
    }

    @ViewBuilder private func dropsFields(_ spawn: SpawnFormationEvent) -> some View {
        let formation = workspace.formation(for: spawn.formationReference) ?? spawn.formation
        let memberCount = formation.offsets().count
        let diagnostics = DropAuthoring.diagnostics(for: spawn.drops, memberCount: memberCount)
        Section("Drops") {
            Text("Assign one guaranteed pickup to a selected formation member.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array((spawn.drops ?? []).sorted { $0.memberIndex < $1.memberIndex }.enumerated()), id: \.offset) { _, drop in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Button("Enemy \(drop.memberIndex + 1)") { workspace.selectedFormationMemberIndex = drop.memberIndex }
                            .buttonStyle(.link)
                        Spacer()
                        Button("Remove", role: .destructive) { removeDrop(for: drop.memberIndex) }.controlSize(.small)
                    }
                    Picker("Kind", selection: dropKindBinding(for: drop.memberIndex, fallback: drop.kind)) {
                        ForEach(DropKind.allCases, id: \.self) { Text(humanize($0.rawValue)).tag($0) }
                    }
                    TextField("Amount", value: dropAmountBinding(for: drop.memberIndex, fallback: drop.amount), format: .number)
                    if let diagnostic = diagnostics.first(where: { $0.memberIndex == drop.memberIndex }) {
                        Label(diagnostic.message, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 2)
            }
            Button("Add Drop") { addDrop() }.disabled(!canAddDrop)
            if workspace.selectedFormationMemberIndex == nil {
                Text("Select an enemy in the preview to add a drop.").font(.caption).foregroundStyle(.secondary)
            } else if !canAddDrop {
                Text("The selected enemy already has a drop or is outside this formation.").font(.caption).foregroundStyle(.secondary)
            }
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
        case let .ring(value):
            Stepper("Count: \(value.count)", value: ringBinding(\.count, fallback: value.count), in: 1...50)
            TextField("Horizontal radius", value: ringBinding(\.radiusX, fallback: value.radiusX), format: .number)
            TextField("Vertical radius", value: ringBinding(\.radiusY, fallback: value.radiusY), format: .number)
            TextField("Rotation", value: ringBinding(\.rotation, fallback: value.rotation), format: .number)
        case let .trail(value):
            Stepper("Count: \(value.count)", value: trailBinding(\.count, fallback: value.count), in: 1...50)
            TextField("Follow delay (seconds)", value: trailBinding(\.followDelay, fallback: value.followDelay), format: .number)
            Text("Each member follows the same route after this delay.").font(.caption).foregroundStyle(.secondary)
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
            Toggle("Loop after completion", isOn: waypointLoopBinding)
            if value.loopToPoint != nil {
                Picker("Loop to waypoint", selection: waypointLoopToBinding) {
                    ForEach(value.points.indices, id: \.self) { Text("Point \($0 + 1)").tag($0) }
                }
            }
            LabeledContent("Points", value: "\(value.points.count)")
            Text("Edit handles and the loop start in the Paths editor.").font(.caption).foregroundStyle(.secondary)
        case let .bezier(value):
            TextField("Duration (seconds)", value: bezierBinding(\.duration, fallback: value.duration), format: .number)
            Toggle("Loop after completion", isOn: bezierLoopBinding)
            if value.loopStart != nil {
                TextField("Repeat from (seconds)", value: bezierLoopStartBinding(fallback: value.loopStart ?? 0), format: .number)
            }
            Text("Edit this curve's handles in the Paths editor.").font(.caption).foregroundStyle(.secondary)
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

    private enum EventEditorKind: Hashable { case spawnFormation, playChoreography, spawnBoss, zoomOut, zoomIn }
    private enum EncounterSource: Hashable { case inline, saved }
    private var eventTypeBinding: Binding<EventEditorKind> {
        Binding(get: {
            switch selectedEvent?.action {
            case .spawnFormation: .spawnFormation
            case .playChoreography: .playChoreography
            case .spawnBoss: .spawnBoss
            case .zoomOut: .zoomOut
            case .zoomIn: .zoomIn
            case nil: .spawnFormation
            }
        }, set: { kind in
            workspace.updateSelectedMissionEvent { event in
                switch kind {
                case .spawnFormation: event.action = .spawnFormation(.init(enemy: .init(id: "fly_basic", level: 1), formation: .line(.init(axis: .vertical, count: 3, spacing: 48)), path: .straight(.init(speed: 120)), spawnPosition: .init(edge: .right, xOffset: 24, y: 180)))
                case .playChoreography:
                    if let document = workspace.choreographies.first, let path = workspace.resourcePath(for: document.fileURL) { event.action = .playChoreography(.init(choreographyReference: .init(resourcePath: path))) }
                case .spawnBoss: event.action = .spawnBoss(.init(id: "boss1", level: 1, y: 180))
                case .zoomOut: event.action = .zoomOut(.init(multiplier: 0.8, duration: 1))
                case .zoomIn: event.action = .zoomIn(.init(multiplier: 1, duration: 1))
                }
            }
        })
    }

    private var choreographyReferencePathBinding: Binding<String> {
        Binding(get: {
            guard case let .playChoreography(value)? = selectedEvent?.action else { return "" }
            return value.choreographyReference.resourcePath
        }, set: { path in
            workspace.updateSelectedMissionEvent { event in
                guard !path.isEmpty else { return }
                event.action = .playChoreography(.init(choreographyReference: .init(resourcePath: path)))
            }
        })
    }

    private var choreographyLevelOffsetBinding: Binding<Int> {
        Binding(get: {
            guard case let .playChoreography(value)? = selectedEvent?.action else { return 0 }
            return value.enemyLevelOffset ?? 0
        }, set: { offset in
            workspace.updateSelectedMissionEvent { event in
                guard case var .playChoreography(value) = event.action else { return }
                value.enemyLevelOffset = offset == 0 ? nil : offset
                event.action = .playChoreography(value)
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
    private var mirrorYBinding: Binding<Bool> {
        Binding(get: { if case let .spawnFormation(value)? = selectedEvent?.action { value.pathTransform?.mirrorY ?? false } else { false } }, set: { enabled in
            mutateSpawn { spawn in
                var transform = spawn.pathTransform ?? .init()
                transform.mirrorY = enabled
                spawn.pathTransform = transform.isIdentity ? nil : transform
            }
        })
    }
    private var yOffsetBinding: Binding<Double> {
        Binding(get: { if case let .spawnFormation(value)? = selectedEvent?.action { value.pathTransform?.yOffset ?? 0 } else { 0 } }, set: { offset in
            mutateSpawn { spawn in
                var transform = spawn.pathTransform ?? .init()
                transform.yOffset = offset
                spawn.pathTransform = transform.isIdentity ? nil : transform
            }
        })
    }
    private func bossBinding<Value>(
        _ keyPath: WritableKeyPath<SpawnBossEvent, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                guard case let .spawnBoss(value)? = selectedEvent?.action else { return fallback }
                return value[keyPath: keyPath]
            },
            set: { value in
                workspace.updateSelectedMissionEvent { event in
                    guard case var .spawnBoss(boss) = event.action else { return }
                    boss[keyPath: keyPath] = value
                    event.action = .spawnBoss(boss)
                }
            }
        )
    }
    private var bossHasPathBinding: Binding<Bool> {
        Binding(get: {
            guard case let .spawnBoss(boss)? = selectedEvent?.action else { return false }
            return boss.path != nil
        }, set: { enabled in
            workspace.updateSelectedMissionEvent { event in
                guard case var .spawnBoss(boss) = event.action else { return }
                boss.path = enabled ? Self.defaultBossPath : nil
                event.action = .spawnBoss(boss)
            }
        })
    }
    private var bossPathKindBinding: Binding<MovementPathKind> {
        Binding(get: {
            guard case let .spawnBoss(boss)? = selectedEvent?.action else { return .waypoints }
            return boss.path?.kind ?? .waypoints
        }, set: { kind in mutateBossPath { $0 = defaultPath(kind) } })
    }
    private func mutateBossPath(_ change: (inout MovementPathDefinition) -> Void) {
        workspace.updateSelectedMissionEvent { event in
            guard case var .spawnBoss(boss) = event.action, var path = boss.path else { return }
            change(&path)
            boss.path = path
            event.action = .spawnBoss(boss)
        }
    }
    private func bossPathBinding<Value, Payload>(_ extract: @escaping (MovementPathDefinition) -> Payload?, _ wrap: @escaping (Payload) -> MovementPathDefinition, _ keyPath: WritableKeyPath<Payload, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: {
            guard case let .spawnBoss(boss)? = selectedEvent?.action, let path = boss.path, let value = extract(path) else { return fallback }
            return value[keyPath: keyPath]
        }, set: { newValue in
            mutateBossPath { path in
                guard var value = extract(path) else { return }
                value[keyPath: keyPath] = newValue
                path = wrap(value)
            }
        })
    }
    private func bossStraightBinding<Value>(_ keyPath: WritableKeyPath<StraightPath, Value>, fallback: Value) -> Binding<Value> { bossPathBinding({ if case let .straight(value) = $0 { value } else { nil } }, MovementPathDefinition.straight, keyPath, fallback: fallback) }
    private func bossSineBinding<Value>(_ keyPath: WritableKeyPath<SinePath, Value>, fallback: Value) -> Binding<Value> { bossPathBinding({ if case let .sine(value) = $0 { value } else { nil } }, MovementPathDefinition.sine, keyPath, fallback: fallback) }
    private func bossWaypointBinding<Value>(_ keyPath: WritableKeyPath<WaypointPath, Value>, fallback: Value) -> Binding<Value> { bossPathBinding({ if case let .waypoints(value) = $0 { value } else { nil } }, MovementPathDefinition.waypoints, keyPath, fallback: fallback) }
    private func bossBezierBinding<Value>(_ keyPath: WritableKeyPath<BezierPath, Value>, fallback: Value) -> Binding<Value> { bossPathBinding({ if case let .bezier(value) = $0 { value } else { nil } }, MovementPathDefinition.bezier, keyPath, fallback: fallback) }
    private var bossWaypointLoopBinding: Binding<Bool> {
        Binding(get: { if case let .spawnBoss(boss)? = selectedEvent?.action, case let .waypoints(path)? = boss.path { path.loopToPoint != nil } else { false } }, set: { enabled in
            mutateBossPath { path in guard case var .waypoints(value) = path else { return }; value.loopToPoint = enabled ? (value.loopToPoint ?? 1) : nil; path = .waypoints(value) }
        })
    }
    private var bossWaypointLoopToBinding: Binding<Int> {
        Binding(get: { if case let .spawnBoss(boss)? = selectedEvent?.action, case let .waypoints(path)? = boss.path { path.loopToPoint ?? 0 } else { 0 } }, set: { index in
            mutateBossPath { path in guard case var .waypoints(value) = path else { return }; value.loopToPoint = index; path = .waypoints(value) }
        })
    }
    private func bossWaypointPointBinding(_ index: Int, _ keyPath: WritableKeyPath<MovementPathPointDefinition, Double>, fallback: Double) -> Binding<Double> {
        Binding(get: {
            guard case let .spawnBoss(boss)? = selectedEvent?.action,
                  case let .waypoints(path)? = boss.path,
                  path.points.indices.contains(index) else { return fallback }
            return path.points[index][keyPath: keyPath]
        }, set: { value in
            mutateBossPath { path in
                guard case var .waypoints(waypoints) = path,
                      waypoints.points.indices.contains(index) else { return }
                waypoints.points[index][keyPath: keyPath] = value
                path = .waypoints(waypoints)
            }
        })
    }

    private var resolvedFormationMemberCount: Int {
        guard case let .spawnFormation(spawn)? = selectedEvent?.action else { return 0 }
        return (workspace.formation(for: spawn.formationReference) ?? spawn.formation).offsets().count
    }
    private var canAddDrop: Bool {
        guard let memberIndex = workspace.selectedFormationMemberIndex,
              (0..<resolvedFormationMemberCount).contains(memberIndex),
              case let .spawnFormation(spawn)? = selectedEvent?.action else { return false }
        return DropAuthoring.drop(for: memberIndex, in: spawn.drops) == nil
    }
    private func addDrop() {
        guard let memberIndex = workspace.selectedFormationMemberIndex, canAddDrop else { return }
        mutateSpawn { $0.drops = DropAuthoring.addingDefaultDrop(to: memberIndex, in: $0.drops) }
    }
    private func removeDrop(for memberIndex: Int) {
        mutateSpawn { $0.drops = DropAuthoring.removingDrop(for: memberIndex, in: $0.drops) }
    }
    private func dropKindBinding(for memberIndex: Int, fallback: DropKind) -> Binding<DropKind> {
        Binding(get: {
            guard case let .spawnFormation(spawn)? = selectedEvent?.action else { return fallback }
            return DropAuthoring.drop(for: memberIndex, in: spawn.drops)?.kind ?? fallback
        }, set: { kind in
            mutateSpawn { spawn in
                guard var drop = DropAuthoring.drop(for: memberIndex, in: spawn.drops) else { return }
                drop.kind = kind
                spawn.drops = DropAuthoring.updatingDrop(drop, in: spawn.drops)
            }
        })
    }
    private func dropAmountBinding(for memberIndex: Int, fallback: Int) -> Binding<Int> {
        Binding(get: {
            guard case let .spawnFormation(spawn)? = selectedEvent?.action else { return fallback }
            return DropAuthoring.drop(for: memberIndex, in: spawn.drops)?.amount ?? fallback
        }, set: { amount in
            mutateSpawn { spawn in
                guard var drop = DropAuthoring.drop(for: memberIndex, in: spawn.drops) else { return }
                drop.amount = amount
                spawn.drops = DropAuthoring.updatingDrop(drop, in: spawn.drops)
            }
        })
    }

    private var formationKindBinding: Binding<FormationKind> { Binding(get: { if case let .spawnFormation(v)? = selectedEvent?.action { v.formation.kind } else { .line } }, set: { kind in mutateSpawn { $0.formation = defaultFormation(kind) } }) }
    private var pathKindBinding: Binding<MovementPathKind> { Binding(get: { if case let .spawnFormation(v)? = selectedEvent?.action { v.path.kind } else { .straight } }, set: { kind in mutateSpawn { $0.path = defaultPath(kind) } }) }
    private var formationSourceBinding: Binding<EncounterSource> { Binding(get: { if case let .spawnFormation(value)? = selectedEvent?.action, value.formationReference != nil { .saved } else { .inline } }, set: { source in mutateSpawn { spawn in switch source { case .inline: spawn.formationReference = nil; case .saved: if let document = workspace.formations.first, let path = workspace.resourcePath(for: document.fileURL) { spawn.formationReference = .init(resourcePath: path) } } } }) }
    private var pathSourceBinding: Binding<EncounterSource> { Binding(get: { if case let .spawnFormation(value)? = selectedEvent?.action, value.pathReference != nil { .saved } else { .inline } }, set: { source in mutateSpawn { spawn in switch source { case .inline: spawn.pathReference = nil; case .saved: if let document = workspace.paths.first, let path = workspace.resourcePath(for: document.fileURL) { spawn.pathReference = .init(resourcePath: path) } } } }) }
    private var formationReferencePathBinding: Binding<String> { Binding(get: { if case let .spawnFormation(value)? = selectedEvent?.action { value.formationReference?.resourcePath ?? "" } else { "" } }, set: { path in mutateSpawn { $0.formationReference = .init(resourcePath: path) } }) }
    private var pathReferencePathBinding: Binding<String> { Binding(get: { if case let .spawnFormation(value)? = selectedEvent?.action { value.pathReference?.resourcePath ?? "" } else { "" } }, set: { path in mutateSpawn { $0.pathReference = .init(resourcePath: path) } }) }

    private func formationBinding<Value, Payload>(_ extract: @escaping (FormationDefinition) -> Payload?, _ wrap: @escaping (Payload) -> FormationDefinition, _ keyPath: WritableKeyPath<Payload, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { guard case let .spawnFormation(spawn)? = selectedEvent?.action, let value = extract(spawn.formation) else { return fallback }; return value[keyPath: keyPath] }, set: { newValue in mutateSpawn { spawn in guard var value = extract(spawn.formation) else { return }; value[keyPath: keyPath] = newValue; spawn.formation = wrap(value) } })
    }
    private func lineBinding<Value>(_ kp: WritableKeyPath<LineFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .line(v) = $0 { v } else { nil } }, FormationDefinition.line, kp, fallback: fallback) }
    private func slottedBinding<Value>(_ kp: WritableKeyPath<SlottedLineFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .slottedLine(v) = $0 { v } else { nil } }, FormationDefinition.slottedLine, kp, fallback: fallback) }
    private func vBinding<Value>(_ kp: WritableKeyPath<VFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .v(v) = $0 { v } else { nil } }, FormationDefinition.v, kp, fallback: fallback) }
    private func gridBinding<Value>(_ kp: WritableKeyPath<StaggeredGridFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .staggeredGrid(v) = $0 { v } else { nil } }, FormationDefinition.staggeredGrid, kp, fallback: fallback) }
    private func arcBinding<Value>(_ kp: WritableKeyPath<ArcFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .arc(v) = $0 { v } else { nil } }, FormationDefinition.arc, kp, fallback: fallback) }
    private func ringBinding<Value>(_ kp: WritableKeyPath<RingFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .ring(v) = $0 { v } else { nil } }, FormationDefinition.ring, kp, fallback: fallback) }
    private func trailBinding<Value>(_ kp: WritableKeyPath<TrailFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .trail(v) = $0 { v } else { nil } }, FormationDefinition.trail, kp, fallback: fallback) }

    private func pathBinding<Value, Payload>(_ extract: @escaping (MovementPathDefinition) -> Payload?, _ wrap: @escaping (Payload) -> MovementPathDefinition, _ kp: WritableKeyPath<Payload, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { guard case let .spawnFormation(spawn)? = selectedEvent?.action, let value = extract(spawn.path) else { return fallback }; return value[keyPath: kp] }, set: { newValue in mutateSpawn { spawn in guard var value = extract(spawn.path) else { return }; value[keyPath: kp] = newValue; spawn.path = wrap(value) } })
    }
    private func straightBinding<Value>(_ kp: WritableKeyPath<StraightPath, Value>, fallback: Value) -> Binding<Value> { pathBinding({ if case let .straight(v) = $0 { v } else { nil } }, MovementPathDefinition.straight, kp, fallback: fallback) }
    private func sineBinding<Value>(_ kp: WritableKeyPath<SinePath, Value>, fallback: Value) -> Binding<Value> { pathBinding({ if case let .sine(v) = $0 { v } else { nil } }, MovementPathDefinition.sine, kp, fallback: fallback) }
    private func waypointBinding<Value>(_ kp: WritableKeyPath<WaypointPath, Value>, fallback: Value) -> Binding<Value> { pathBinding({ if case let .waypoints(v) = $0 { v } else { nil } }, MovementPathDefinition.waypoints, kp, fallback: fallback) }
    private func bezierBinding<Value>(_ kp: WritableKeyPath<BezierPath, Value>, fallback: Value) -> Binding<Value> { pathBinding({ if case let .bezier(v) = $0 { v } else { nil } }, MovementPathDefinition.bezier, kp, fallback: fallback) }

    private var waypointLoopBinding: Binding<Bool> { Binding(get: { if case let .spawnFormation(spawn)? = selectedEvent?.action, case let .waypoints(value) = spawn.path { value.loopToPoint != nil } else { false } }, set: { enabled in mutateSpawn { spawn in guard case var .waypoints(value) = spawn.path else { return }; value.loopToPoint = enabled ? (value.loopToPoint ?? 0) : nil; spawn.path = .waypoints(value) } }) }
    private var waypointLoopToBinding: Binding<Int> { Binding(get: { if case let .spawnFormation(spawn)? = selectedEvent?.action, case let .waypoints(value) = spawn.path { value.loopToPoint ?? 0 } else { 0 } }, set: { index in mutateSpawn { spawn in guard case var .waypoints(value) = spawn.path else { return }; value.loopToPoint = index; spawn.path = .waypoints(value) } }) }
    private var bezierLoopBinding: Binding<Bool> { Binding(get: { if case let .spawnFormation(spawn)? = selectedEvent?.action, case let .bezier(value) = spawn.path { value.loopStart != nil } else { false } }, set: { enabled in mutateSpawn { spawn in guard case var .bezier(value) = spawn.path else { return }; value.loopStart = enabled ? (value.loopStart ?? 0) : nil; spawn.path = .bezier(value) } }) }
    private func waypointLoopStartBinding(fallback: Double) -> Binding<Double> { Binding(get: { if case let .spawnFormation(spawn)? = selectedEvent?.action, case let .waypoints(value) = spawn.path { value.loopStart ?? fallback } else { fallback } }, set: { newValue in mutateSpawn { spawn in guard case var .waypoints(value) = spawn.path else { return }; value.loopStart = newValue; spawn.path = .waypoints(value) } }) }
    private func bezierLoopStartBinding(fallback: Double) -> Binding<Double> { Binding(get: { if case let .spawnFormation(spawn)? = selectedEvent?.action, case let .bezier(value) = spawn.path { value.loopStart ?? fallback } else { fallback } }, set: { newValue in mutateSpawn { spawn in guard case var .bezier(value) = spawn.path else { return }; value.loopStart = newValue; spawn.path = .bezier(value) } }) }

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

    private static let defaultBossPath = MovementPathDefinition.waypoints(.init(duration: 8, points: [.init(x: 1.2, y: 0.5), .init(x: 0.72, y: 0.25), .init(x: 0.58, y: 0.72), .init(x: 0.72, y: 0.5)], loopToPoint: 1))
    private func defaultFormation(_ kind: FormationKind) -> FormationDefinition { switch kind { case .line: .line(.init(axis: .vertical, count: 3, spacing: 48)); case .slottedLine: .slottedLine(.init(axis: .vertical, slotCount: 5, spacing: 48, occupiedSlots: [0, 2, 4])); case .v: .v(.init(count: 5, spacing: 36, depth: 28)); case .staggeredGrid: .staggeredGrid(.init(rows: 2, columns: 3, spacingX: 48, spacingY: 48)); case .arc: .arc(.init(count: 5, radius: 80, startAngle: -60, endAngle: 60)); case .ring: .ring(.init(count: 6, radiusX: 92, radiusY: 64, rotation: 0)); case .trail: .trail(.init(count: 5, followDelay: 0.35)); case .freeform: .freeform(.init(members: [.init(id: "member_1", offset: .init(x: 0, y: 0))])) } }
    private func defaultPath(_ kind: MovementPathKind) -> MovementPathDefinition { switch kind { case .straight: .straight(.init(speed: 120)); case .sine: .sine(.init(speed: 120, amplitude: 40, frequency: 0.5)); case .waypoints: .waypoints(.init(duration: 6, points: [.init(x: 1.1, y: 0.5), .init(x: 0.65, y: 0.3), .init(x: -0.1, y: 0.5)])); case .bezier: .bezier(.init(duration: 4, start: .init(x: 1.1, y: 0.5), control1: .init(x: 0.8, y: 0.05), control2: .init(x: 0.2, y: 0.95), end: .init(x: -0.1, y: 0.5))) } }
    private func humanize(_ text: String) -> String { text.reduce(into: "") { result, character in if character.isUppercase { result.append(" ") }; result.append(character) }.capitalized }
}
