import BugpocalypseContent
import SwiftUI

struct ContentView: View {
    @StateObject private var workspace = EditorWorkspace()

    var body: some View {
        NavigationSplitView {
            ProjectSidebar(workspace: workspace)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } content: {
            editorContent
                .navigationSplitViewColumnWidth(min: 520, ideal: 760)
        } detail: {
            inspector
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        }
        .frame(minWidth: 1040, minHeight: 680)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EditorStatusBar(workspace: workspace)
        }
        .alert("Couldn’t complete that action", isPresented: errorIsPresented) {
            Button("OK") { workspace.errorMessage = nil }
        } message: {
            Text(workspace.errorMessage ?? "Unknown error")
        }
        .task { workspace.openRememberedProjectIfNeeded() }
        .onChange(of: workspace.selection) { oldSelection, newSelection in
            guard oldSelection != newSelection else { return }
            workspace.selectedMissionEventIndex = nil
            workspace.selectedFormationMemberIndex = nil
            workspace.selectedPathPointIndex = nil
            if case .world = newSelection { workspace.selectedCellID = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveWorld)) { _ in
            workspace.saveSelectedDocument()
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        switch workspace.selection {
        case .world(let url):
            if let document = workspace.worldDocument(at: url) {
                WorldEditorView(workspace: workspace, document: document)
                    .id(url)
            } else {
                ContentUnavailableView("World not found", systemImage: "globe")
            }
        case .section(.worlds):
            WorldWelcomeView(workspace: workspace)
        case .mission(let url):
            if let document = workspace.missionDocument(at: url) {
                MissionEditorView(workspace: workspace, document: document)
                    .id(url)
            } else {
                ContentUnavailableView("Mission not found", systemImage: "flag.checkered")
            }
        case .section(.missions):
            MissionWelcomeView(workspace: workspace)
        case .formation(let url):
            if let document = workspace.formationDocument(at: url) {
                FormationEditorView(workspace: workspace, document: document)
                    .id(url)
            } else {
                ContentUnavailableView("Formation not found", systemImage: "square.grid.3x3.fill")
            }
        case .section(.formations):
            FormationWelcomeView(workspace: workspace)
        case .path(let url):
            if let document = workspace.pathDocument(at: url) {
                PathEditorView(workspace: workspace, document: document)
                    .id(url)
            } else {
                ContentUnavailableView("Path not found", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
        case .section(.paths):
            PathWelcomeView(workspace: workspace)
        case .section(let section):
            ContentUnavailableView(
                "\(section.title) editor coming next",
                systemImage: section.systemImage,
                description: Text("This first pass focuses on world authoring.")
            )
        case nil:
            ContentUnavailableView(
                "Open a Bugpocalypse project",
                systemImage: "folder.badge.plus",
                description: Text("Choose the game checkout that contains Godot and BugpocalypseSwift.")
            )
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if workspace.selectedPath != nil {
            PathInspector(workspace: workspace)
        } else if workspace.selectedFormation != nil {
            FormationInspector(workspace: workspace)
        } else if workspace.selectedMission != nil {
            MissionInspector(workspace: workspace)
        } else {
            WorldInspector(workspace: workspace)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } }
        )
    }
}

private struct PathWelcomeView: View {
    @ObservedObject var workspace: EditorWorkspace

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 48))
                .foregroundStyle(.cyan)
            Text("Paths").font(.largeTitle.bold())
            Text(workspace.paths.isEmpty
                 ? "Create a reusable movement path to use across missions."
                 : "Select a path to edit its motion and preview its route.")
                .foregroundStyle(.secondary)
            if let first = workspace.paths.first {
                Button("Open \(first.definition.name)") { workspace.selectPath(first) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Create Path", action: workspace.createPath)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FormationWelcomeView: View {
    @ObservedObject var workspace: EditorWorkspace

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)
            Text("Formations").font(.largeTitle.bold())
            Text(workspace.formations.isEmpty
                 ? "Create a reusable enemy layout to use across missions."
                 : "Select a formation to edit its layout and member positions.")
                .foregroundStyle(.secondary)
            if let first = workspace.formations.first {
                Button("Open \(first.definition.name)") { workspace.selectFormation(first) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Create Formation", action: workspace.createFormation)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MissionWelcomeView: View {
    @ObservedObject var workspace: EditorWorkspace

    var body: some View {
        if workspace.missions.isEmpty {
            ContentUnavailableView(
                "No missions found",
                systemImage: "flag.checkered",
                description: Text("Mission JSON files will appear here from godot/assets/missions.")
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "flag.checkered").font(.system(size: 48)).foregroundStyle(.orange)
                Text("Missions").font(.largeTitle.bold())
                Text("Select a mission to edit its timeline and preview its encounters.")
                    .foregroundStyle(.secondary)
                Button("Open \(workspace.missions[0].definition.metadata.displayName)") {
                    workspace.selectMission(workspace.missions[0])
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct WorldWelcomeView: View {
    @ObservedObject var workspace: EditorWorkspace

    var body: some View {
        if workspace.worlds.isEmpty {
            ContentUnavailableView(
                "No worlds found",
                systemImage: "globe.badge.chevron.backward",
                description: Text("World JSON files will appear here from godot/assets/worlds.")
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.teal)
                Text("Worlds").font(.largeTitle.bold())
                Text("Select a world in the sidebar to edit its map and cells.")
                    .foregroundStyle(.secondary)
                Button("Open \(workspace.worlds[0].definition.displayName)") {
                    workspace.selectWorld(workspace.worlds[0])
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    ContentView()
}
