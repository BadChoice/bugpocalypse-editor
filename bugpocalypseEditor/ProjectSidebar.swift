import BugpocalypseContent
import SwiftUI

struct ProjectSidebar: View {
    @ObservedObject var workspace: EditorWorkspace

    var body: some View {
        List(selection: $workspace.selection) {
            Section("Project") {
                ForEach(EditorSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(EditorSelection.section(section))

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
                        ForEach(filteredMissions) { document in
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
                            .padding(.leading, 16)
                            .tag(EditorSelection.mission(document.fileURL))
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
        }
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
        case .waypoints: "point.topleft.down.to.point.bottomright.curvepath"
        case .bezier: "skew"
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
        (workspace.selectedPath?.fileURL ?? workspace.selectedFormation?.fileURL ?? workspace.selectedMission?.fileURL ?? workspace.selectedWorld?.fileURL)?.path(percentEncoded: false)
    }

    private var selectedStatus: AuthoringStatus? {
        workspace.selectedPath?.definition.authoringStatus ?? workspace.selectedFormation?.definition.authoringStatus ?? workspace.selectedMission?.definition.authoringStatus ?? workspace.selectedWorld?.definition.authoringStatus
    }

    private var isDirty: Bool {
        workspace.selectedPath?.isDirty ?? workspace.selectedFormation?.isDirty ?? workspace.selectedMission?.isDirty ?? workspace.selectedWorld?.isDirty ?? false
    }
}
