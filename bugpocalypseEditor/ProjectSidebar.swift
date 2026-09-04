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
        (workspace.selectedMission?.fileURL ?? workspace.selectedWorld?.fileURL)?.path(percentEncoded: false)
    }

    private var selectedStatus: AuthoringStatus? {
        workspace.selectedMission?.definition.authoringStatus ?? workspace.selectedWorld?.definition.authoringStatus
    }

    private var isDirty: Bool {
        workspace.selectedMission?.isDirty ?? workspace.selectedWorld?.isDirty ?? false
    }
}
