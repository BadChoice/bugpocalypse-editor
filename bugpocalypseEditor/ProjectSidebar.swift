import BugpocalypseContent
import SwiftUI

private struct MissionWorldGroup: Identifiable {
    let id: String
    let name: String
    let missions: [MissionDocument]
}

struct ProjectSidebar: View {
    @ObservedObject var workspace: EditorWorkspace
    @State private var expandedSections = Set(EditorSection.allCases)
    @State private var expandedMissionWorldIDs = Set<String>()

    var body: some View {
        List(selection: $workspace.selection) {
            Section("Project") {
                ForEach(EditorSection.allCases) { section in
                    DisclosureGroup(isExpanded: expansionBinding(for: section)) {

                    if section == .worlds {
                        ForEach(filteredWorlds) { document in
                            HStack(spacing: 7) {
                                Image(systemName: "map.fill").foregroundStyle(.secondary)
                                Text(document.definition.displayName).lineLimit(1)
                                Spacer(minLength: 4)
                                if document.definition.authoringStatus == .draft {
                                    Text("DRAFT").font(.caption2.bold()).foregroundStyle(.orange)
                                }
                                if document.isDirty {
                                    Circle().fill(.orange).frame(width: 7, height: 7)
                                }
                            }
                            .padding(.leading, 16)
                            .tag(EditorSelection.world(document.fileURL))
                        }
                    }
                    if section == .missions {
                        ForEach(missionWorldGroups) { group in
                            DisclosureGroup(isExpanded: missionWorldExpansionBinding(for: group.id)) {
                                ForEach(group.missions) { document in
                                    missionRow(document)
                                        .padding(.leading, 32)
                                        .tag(EditorSelection.mission(document.fileURL))
                                }
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "globe.americas.fill").foregroundStyle(.secondary)
                                    Text(group.name).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("\(group.missions.count)")
                                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.leading, 16)
                        }
                    }
                    if section == .choreographies {
                        ForEach(filteredChoreographies) { document in
                            HStack(spacing: 7) {
                                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.secondary)
                                Text(document.definition.name).lineLimit(1)
                                Spacer(minLength: 4)
                                Text("\(document.definition.timeline.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                if document.definition.authoringStatus == .draft { Text("DRAFT").font(.caption2.bold()).foregroundStyle(.orange) }
                                if document.isDirty { Circle().fill(.orange).frame(width: 7, height: 7) }
                            }
                            .padding(.leading, 16)
                            .tag(EditorSelection.choreography(document.fileURL))
                        }
                    }
                    if section == .formations {
                        ForEach(filteredFormations) { document in
                            HStack(spacing: 7) {
                                Image(systemName: formationSymbol(document.definition.formation.kind))
                                    .foregroundStyle(.secondary)
                                Text(document.definition.name).lineLimit(1)
                                Spacer(minLength: 4)
                                Text("\(document.definition.formation.offsets().count)")
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                if document.definition.authoringStatus == .draft {
                                    Text("DRAFT").font(.caption2.bold()).foregroundStyle(.orange)
                                }
                                if document.isDirty {
                                    Circle().fill(.orange).frame(width: 7, height: 7)
                                }
                            }
                            .padding(.leading, 16)
                            .tag(EditorSelection.formation(document.fileURL))
                        }
                    }
                    if section == .paths {
                        ForEach(filteredPaths) { document in
                            HStack(spacing: 7) {
                                Image(systemName: pathSymbol(document.definition.path.kind))
                                    .foregroundStyle(.secondary)
                                Text(document.definition.name).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(document.definition.path.kind.rawValue.capitalized)
                                    .font(.caption2).foregroundStyle(.secondary)
                                if document.definition.authoringStatus == .draft {
                                    Text("DRAFT").font(.caption2.bold()).foregroundStyle(.orange)
                                }
                                if document.isDirty {
                                    Circle().fill(.orange).frame(width: 7, height: 7)
                                }
                            }
                            .padding(.leading, 16)
                            .tag(EditorSelection.path(document.fileURL))
                        }
                    }
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                            .tag(EditorSelection.section(section))
                    }
                }
            }
        }
        .searchable(text: $workspace.searchText, placement: .sidebar, prompt: "Search content")
        .navigationTitle(workspace.projectRoot?.lastPathComponent ?? "Bugpocalypse")
        .toolbar {
            ToolbarItem {
                Button(action: workspace.chooseProject) {
                    Label("Open Project", systemImage: "folder")
                }
                .help("Open a Bugpocalypse checkout")
            }
            if isFormationContext {
                ToolbarItem {
                    Button(action: workspace.createFormation) {
                        Label("New Formation", systemImage: "plus")
                    }
                    .help("Create a reusable formation")
                    .disabled(workspace.projectRoot == nil)
                }
            }
            if isPathContext {
                ToolbarItem {
                    Button(action: workspace.createPath) {
                        Label("New Path", systemImage: "plus")
                    }
                    .help("Create a reusable path")
                    .disabled(workspace.projectRoot == nil)
                }
            }
            ToolbarItem {
                Button(action: workspace.createChoreography) { Label("New Choreography", systemImage: "plus") }
                    .help("Create a reusable choreography")
                    .disabled(workspace.projectRoot == nil)
            }
        }
    }

    private func expansionBinding(for section: EditorSection) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(section) },
            set: { isExpanded in
                if isExpanded { expandedSections.insert(section) }
                else { expandedSections.remove(section) }
            }
        )
    }

    private func missionWorldExpansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedMissionWorldIDs.contains(id) },
            set: { isExpanded in
                if isExpanded { expandedMissionWorldIDs.insert(id) }
                else { expandedMissionWorldIDs.remove(id) }
            }
        )
    }

    private var filteredWorlds: [WorldDocument] {
        guard !workspace.searchText.isEmpty else { return workspace.worlds }
        return workspace.worlds.filter {
            $0.definition.displayName.localizedCaseInsensitiveContains(workspace.searchText) ||
            $0.definition.id.localizedCaseInsensitiveContains(workspace.searchText)
        }
    }

    private var filteredMissions: [MissionDocument] {
        guard !workspace.searchText.isEmpty else { return workspace.missions }
        return workspace.missions.filter {
            $0.definition.metadata.displayName.localizedCaseInsensitiveContains(workspace.searchText) ||
            $0.definition.id.localizedCaseInsensitiveContains(workspace.searchText)
        }
    }

    private var missionWorldGroups: [MissionWorldGroup] {
        let isFiltering = !workspace.searchText.isEmpty
        var assignedMissionURLs = Set<URL>()
        var groups: [MissionWorldGroup] = []

        for world in workspace.worlds {
            let linkedPaths = Set(world.definition.cells.compactMap(\.missionResourcePath))
            let missions = filteredMissions.filter { mission in
                guard !assignedMissionURLs.contains(mission.fileURL) else { return false }
                let isLinked = workspace.resourcePath(for: mission.fileURL)
                    .map(linkedPaths.contains) ?? false
                return isLinked ||
                    mission.definition.metadata.locationId == world.definition.id
            }
            assignedMissionURLs.formUnion(missions.map { $0.fileURL })
            if !isFiltering || !missions.isEmpty {
                groups.append(.init(
                    id: "world:\(world.definition.id)",
                    name: world.definition.displayName,
                    missions: missions
                ))
            }
        }

        let unassigned = filteredMissions.filter { !assignedMissionURLs.contains($0.fileURL) }
        let locationIDs = Set(unassigned.map { $0.definition.metadata.locationId })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        groups.append(contentsOf: locationIDs.compactMap { locationID in
            let missions = unassigned.filter { $0.definition.metadata.locationId == locationID }
            guard !missions.isEmpty else { return nil }
            return .init(id: "location:\(locationID)", name: locationID, missions: missions)
        })
        return groups
    }

    @ViewBuilder
    private func missionRow(_ document: MissionDocument) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "flag.fill").foregroundStyle(.secondary)
            Text(document.definition.metadata.displayName).lineLimit(1)
            Spacer(minLength: 4)
            Text("M\(document.definition.metadata.missionNumber)")
                .font(.caption2.bold()).foregroundStyle(.secondary)
            Text("\(document.definition.timeline.count)")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            if document.definition.authoringStatus == .draft {
                Text("DRAFT").font(.caption2.bold()).foregroundStyle(.orange)
            }
            if document.isDirty {
                Circle().fill(.orange).frame(width: 7, height: 7)
            }
        }
    }

    private var filteredFormations: [FormationEditorDocument] {
        guard !workspace.searchText.isEmpty else { return workspace.formations }
        return workspace.formations.filter {
            $0.definition.name.localizedCaseInsensitiveContains(workspace.searchText) ||
            $0.definition.id.localizedCaseInsensitiveContains(workspace.searchText) ||
            $0.definition.formation.kind.rawValue.localizedCaseInsensitiveContains(workspace.searchText)
        }
    }

    private var filteredPaths: [PathEditorDocument] {
        guard !workspace.searchText.isEmpty else { return workspace.paths }
        return workspace.paths.filter {
            $0.definition.name.localizedCaseInsensitiveContains(workspace.searchText) ||
            $0.definition.id.localizedCaseInsensitiveContains(workspace.searchText) ||
            $0.definition.path.kind.rawValue.localizedCaseInsensitiveContains(workspace.searchText)
        }
    }

    private var filteredChoreographies: [ChoreographyEditorDocument] {
        guard !workspace.searchText.isEmpty else { return workspace.choreographies }
        return workspace.choreographies.filter { $0.definition.name.localizedCaseInsensitiveContains(workspace.searchText) || $0.definition.id.localizedCaseInsensitiveContains(workspace.searchText) }
    }

    private var isFormationContext: Bool {
        switch workspace.selection {
        case .formation, .section(.formations): true
        default: false
        }
    }

    private var isPathContext: Bool {
        switch workspace.selection {
        case .path, .section(.paths): true
        default: false
        }
    }

    private func pathSymbol(_ kind: MovementPathKind) -> String {
        switch kind {
        case .straight: "arrow.left"
        case .sine: "waveform.path"
        case .waypoints: "point.3.connected.trianglepath.dotted"
        case .bezier: "point.topleft.down.to.point.bottomright.curvepath"
        }
    }

    private func formationSymbol(_ kind: FormationKind) -> String {
        switch kind {
        case .line, .slottedLine: "ellipsis"
        case .v: "chevron.right"
        case .staggeredGrid: "square.grid.3x3"
        case .arc: "rainbow"
        case .trail: "point.3.connected.trianglepath.dotted"
        case .freeform: "point.3.connected.trianglepath.dotted"
        case .ring: "circle.grid.cross"
        }
    }
}

struct EditorStatusBar: View {
    @ObservedObject var workspace: EditorWorkspace

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: workspace.diagnostics.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(workspace.diagnostics.isEmpty ? .green : .red)
            Text(selectedFilePath ?? workspace.statusMessage)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let status = selectedStatus {
                Text(status.rawValue.capitalized)
                if isDirty { Text("Unsaved").foregroundStyle(.orange) }
                if !workspace.diagnostics.isEmpty {
                    Text("\(workspace.diagnostics.count) error\(workspace.diagnostics.count == 1 ? "" : "s")")
                        .foregroundStyle(.red)
                }
                Button("Save") { workspace.saveSelectedDocument() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!isDirty || workspace.diagnostics.contains { $0.severity == .error })
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }


    private var selectedFilePath: String? {
        (workspace.selectedPath?.fileURL ?? workspace.selectedFormation?.fileURL ?? workspace.selectedChoreography?.fileURL ?? workspace.selectedMission?.fileURL ?? workspace.selectedWorld?.fileURL)?.path(percentEncoded: false)
    }

    private var selectedStatus: AuthoringStatus? {
        workspace.selectedPath?.definition.authoringStatus ?? workspace.selectedFormation?.definition.authoringStatus ?? workspace.selectedChoreography?.definition.authoringStatus ?? workspace.selectedMission?.definition.authoringStatus ?? workspace.selectedWorld?.definition.authoringStatus
    }

    private var isDirty: Bool {
        workspace.selectedPath?.isDirty ?? workspace.selectedFormation?.isDirty ?? workspace.selectedChoreography?.isDirty ?? workspace.selectedMission?.isDirty ?? workspace.selectedWorld?.isDirty ?? false
    }
}
