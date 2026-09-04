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
        if workspace.selectedMission != nil {
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
