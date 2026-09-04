import AppKit
import BugpocalypseContent
import Combine
import Foundation

// Keep the editor's topology vocabulary concise while the shared content
// package names these specifically as edge neighbours.
extension WorldGridCoordinate {
    var neighbours: [WorldGridCoordinate] { edgeNeighbours }
}

enum EditorSection: String, CaseIterable, Hashable, Identifiable {
    case worlds, missions, formations, paths, backgrounds

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .worlds: "globe.americas.fill"
        case .missions: "flag.checkered"
        case .formations: "square.grid.3x3.fill"
        case .paths: "point.topleft.down.to.point.bottomright.curvepath"
        case .backgrounds: "photo.on.rectangle.angled"
        }
    }
}

enum EditorSelection: Hashable {
    case section(EditorSection)
    case world(URL)
    case mission(URL)
}

@MainActor
final class WorldDocument: ObservableObject, Identifiable {
    let fileURL: URL
    @Published var definition: WorldDefinition
    private(set) var savedDefinition: WorldDefinition

    var id: URL { fileURL }
    var isDirty: Bool { definition != savedDefinition }

    init(fileURL: URL, definition: WorldDefinition) {
        self.fileURL = fileURL
        self.definition = definition
        self.savedDefinition = definition
    }

    func markSaved() {
        savedDefinition = definition
        objectWillChange.send()
    }
}

@MainActor
final class MissionDocument: ObservableObject, Identifiable {
    let fileURL: URL
    @Published var definition: MissionDefinition
    private(set) var savedDefinition: MissionDefinition

    var id: URL { fileURL }
    var isDirty: Bool { definition != savedDefinition }

    init(fileURL: URL, definition: MissionDefinition) {
        self.fileURL = fileURL
        self.definition = definition
        self.savedDefinition = definition
    }

    func markSaved() {
        savedDefinition = definition
        objectWillChange.send()
    }
}

@MainActor
final class EditorWorkspace: ObservableObject {
    @Published var projectRoot: URL?
    @Published var worlds: [WorldDocument] = []
    @Published var missions: [MissionDocument] = []
    @Published var selection: EditorSelection?
    @Published var selectedCellID: String?
    @Published var selectedMissionEventIndex: Int?
    @Published var searchText = ""
    @Published var errorMessage: String?
    @Published var statusMessage = "No project open"

    private let fileManager = FileManager.default
    private let rememberedRootKey = "BugpocalypseEditor.projectRoot"

    var selectedWorld: WorldDocument? {
        guard case .world(let url) = selection else { return nil }
        return worldDocument(at: url)
    }

    var selectedMission: MissionDocument? {
        guard case .mission(let url) = selection else { return nil }
        return missionDocument(at: url)
    }

    var selectedCell: WorldCellDefinition? {
        guard let selectedCellID else { return nil }
        return selectedWorld?.definition.cell(id: selectedCellID)
    }

    var diagnostics: [ContentDiagnostic] {
        if let mission = selectedMission {
            return missionDiagnostics(for: mission.definition)
        }
        guard let document = selectedWorld else { return [] }
        do {
            try document.definition.validate()
            return []
        } catch {
            return [ContentDiagnostic(
                severity: .error,
                code: "world.invalid",
                message: error.localizedDescription,
                location: ContentLocation(documentID: document.definition.id)
            )]
        }
    }

    func openRememberedProjectIfNeeded() {
        guard projectRoot == nil else { return }

        if let path = UserDefaults.standard.string(forKey: rememberedRootKey) {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if isValidProjectRoot(url) {
                openProject(at: url)
                return
            }
        }

        let sibling = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .deletingLastPathComponent()
            .appendingPathComponent("Bugpocalypse", isDirectory: true)
        if isValidProjectRoot(sibling) { openProject(at: sibling) }
    }

    func chooseProject() {
        let panel = NSOpenPanel()
        panel.title = "Open Bugpocalypse Checkout"
        panel.message = "Choose the folder containing godot and BugpocalypseSwift."
        panel.prompt = "Open Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = projectRoot
        if panel.runModal() == .OK, let url = panel.url { openProject(at: url) }
    }

    func openProject(at root: URL) {
        guard isValidProjectRoot(root) else {
            errorMessage = "\(root.path) is not a Bugpocalypse checkout. Expected godot/project.godot, godot/assets, and BugpocalypseSwift/Package.swift."
            return
        }

        do {
            let worldsURL = root.appendingPathComponent("godot/assets/worlds", isDirectory: true)
            let fileURLs = try fileManager.contentsOfDirectory(
                at: worldsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension.lowercased() == "json" }

            worlds = try fileURLs.map { url in
                let data = try Data(contentsOf: url)
                return WorldDocument(fileURL: url, definition: try ContentJSON.decode(WorldDefinition.self, from: data))
            }.sorted { $0.definition.displayName.localizedStandardCompare($1.definition.displayName) == .orderedAscending }

            let missionsURL = root.appendingPathComponent("godot/assets/missions", isDirectory: true)
            let missionURLs = recursiveJSONFiles(at: missionsURL)
            missions = try missionURLs.map { url in
                let data = try Data(contentsOf: url)
                return MissionDocument(
                    fileURL: url,
                    definition: try ContentJSON.decode(MissionDefinition.self, from: data)
                )
            }.sorted { lhs, rhs in
                let a = lhs.definition.metadata
                let b = rhs.definition.metadata
                return a.locationId == b.locationId
                    ? a.missionNumber < b.missionNumber
                    : a.locationId.localizedStandardCompare(b.locationId) == .orderedAscending
            }

            projectRoot = root
            UserDefaults.standard.set(root.path, forKey: rememberedRootKey)
            selection = worlds.first.map { .world($0.fileURL) } ?? .section(.worlds)
            selectedCellID = nil
            statusMessage = "Loaded \(worlds.count) world\(worlds.count == 1 ? "" : "s") and \(missions.count) missions"
        } catch {
            errorMessage = "Could not load worlds: \(error.localizedDescription)"
        }
    }

    func worldDocument(at url: URL) -> WorldDocument? {
        worlds.first { $0.fileURL == url }
    }

    func missionDocument(at url: URL) -> MissionDocument? {
        missions.first { $0.fileURL == url }
    }

    func selectWorld(_ document: WorldDocument) {
        selection = .world(document.fileURL)
        selectedCellID = nil
    }

    func selectMission(_ document: MissionDocument) {
        selection = .mission(document.fileURL)
        selectedCellID = nil
        selectedMissionEventIndex = nil
    }

    func updateSelectedMission(_ change: (inout MissionDefinition) -> Void) {
        guard let document = selectedMission else { return }
        var value = document.definition
        change(&value)
        document.definition = value
        objectWillChange.send()
    }

    func updateSelectedMissionEvent(_ change: (inout MissionTimelineEvent) -> Void) {
        guard let index = selectedMissionEventIndex else { return }
        updateSelectedMission { mission in
            guard mission.timeline.indices.contains(index) else { return }
            change(&mission.timeline[index])
        }
    }

    func addMissionEvent(_ action: MissionTimelineEvent.Action) {
        guard let mission = selectedMission else { return }
        let at = ((mission.definition.timeline.map(\.at).max() ?? -2) + 2)
        updateSelectedMission { $0.timeline.append(.init(at: max(0, at), action: action)) }
        selectedMissionEventIndex = mission.definition.timeline.count - 1
    }

    func duplicateSelectedMissionEvent() {
        guard let mission = selectedMission,
              let index = selectedMissionEventIndex,
              mission.definition.timeline.indices.contains(index) else { return }
        var copy = mission.definition.timeline[index]
        copy.at += 1
        updateSelectedMission { $0.timeline.insert(copy, at: index + 1) }
        selectedMissionEventIndex = index + 1
    }

    func deleteSelectedMissionEvent() {
        guard let index = selectedMissionEventIndex else { return }
        updateSelectedMission { mission in
            guard mission.timeline.indices.contains(index) else { return }
            mission.timeline.remove(at: index)
        }
        selectedMissionEventIndex = nil
    }

    func updateSelectedWorld(_ change: (inout WorldDefinition) -> Void) {
        guard let document = selectedWorld else { return }
        var value = document.definition
        change(&value)
        document.definition = value
        objectWillChange.send()
    }

    func updateSelectedCell(_ change: (inout WorldCellDefinition) -> Void) {
        guard let selectedCellID else { return }
        updateSelectedWorld { world in
            guard let index = world.cells.firstIndex(where: { $0.id == selectedCellID }) else { return }
            change(&world.cells[index])
        }
    }

    func renameSelectedCell(to newID: String) {
        guard let oldID = selectedCellID, !newID.isEmpty, newID != oldID else { return }
        guard selectedWorld?.definition.cell(id: newID) == nil else {
            statusMessage = "A cell with ID '\(newID)' already exists"
            return
        }
        updateSelectedWorld { world in
            guard let index = world.cells.firstIndex(where: { $0.id == oldID }) else { return }
            world.cells[index].id = newID
            for cellIndex in world.cells.indices {
                world.cells[cellIndex].neighbourIDs = world.cells[cellIndex].neighbourIDs.map { $0 == oldID ? newID : $0 }
            }
        }
        selectedCellID = newID
    }

    func moveCell(id: String, to coordinate: WorldGridCoordinate) {
        guard selectedWorld?.definition.cell(at: coordinate) == nil else {
            statusMessage = "That grid coordinate is already occupied"
            return
        }
        updateSelectedWorld { world in
            guard let index = world.cells.firstIndex(where: { $0.id == id }) else { return }
            world.cells[index].coordinate = coordinate
        }
    }

    func addCell() {
        guard let document = selectedWorld else { return }
        let occupied = Set(document.definition.cells.map(\.coordinate))
        let coordinate: WorldGridCoordinate
        if let selectedCell,
           let available = selectedCell.coordinate.neighbours.first(where: { !occupied.contains($0) }) {
            coordinate = available
        } else {
            var fallback = WorldGridCoordinate(x: 0, y: 0)
            while occupied.contains(fallback) { fallback.x += 1 }
            coordinate = fallback
        }
        var suffix = document.definition.cells.count + 1
        while document.definition.cell(id: "cell_\(suffix)") != nil { suffix += 1 }
        let cell = WorldCellDefinition(
            id: "cell_\(suffix)", coordinate: coordinate, tileName: "world/road.png",
            kind: .exploration, displayName: "New Cell", isInitiallyRevealed: false,
            scoutEnergyCost: 1, neighbourIDs: []
        )
        updateSelectedWorld { world in
            world.cells.append(cell)
        }
        selectedCellID = cell.id
    }

    func deleteSelectedCell() {
        guard let selectedCellID else { return }
        updateSelectedWorld { world in
            world.cells.removeAll { $0.id == selectedCellID }
            for index in world.cells.indices {
                world.cells[index].neighbourIDs.removeAll { $0 == selectedCellID }
            }
        }
        self.selectedCellID = nil
    }

    func saveSelectedWorld() {
        guard let document = selectedWorld else { return }
        do {
            try document.definition.validate()
            let data = try ContentJSON.encode(document.definition)
            try data.write(to: document.fileURL, options: .atomic)
            document.markSaved()
            objectWillChange.send()
            statusMessage = "Saved \(document.fileURL.lastPathComponent)"
        } catch {
            errorMessage = "The world was not saved: \(error.localizedDescription)"
        }
    }

    func saveSelectedMission() {
        guard let document = selectedMission else { return }
        let errors = missionDiagnostics(for: document.definition).filter { $0.severity == .error }
        guard errors.isEmpty else {
            errorMessage = "The mission was not saved: fix \(errors.count) structural error\(errors.count == 1 ? "" : "s") first."
            return
        }
        do {
            let data = try ContentJSON.encode(document.definition)
            try data.write(to: document.fileURL, options: .atomic)
            document.markSaved()
            objectWillChange.send()
            statusMessage = "Saved \(document.fileURL.lastPathComponent)"
        } catch {
            errorMessage = "The mission was not saved: \(error.localizedDescription)"
        }
    }

    func saveSelectedDocument() {
        if selectedMission != nil { saveSelectedMission() } else { saveSelectedWorld() }
    }

    func assetURL(for tileName: String) -> URL? {
        guard let projectRoot else { return nil }
        let url = projectRoot.appendingPathComponent("assets").appendingPathComponent(tileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func enemyAssetURL(for enemyID: String) -> URL? {
        guard let entry = EnemyCatalogue.entry(for: enemyID) else { return nil }
        return assetURL(for: entry.previewAssetName + ".png")
    }

    /// Tile resources the world editor can author. Paths stay relative to the
    /// game's `assets` folder so they match the runtime atlas naming scheme.
    var availableWorldTiles: [String] {
        guard let projectRoot else { return [] }
        let directory = projectRoot.appendingPathComponent("assets/world", isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let supportedExtensions = Set(["png", "jpg", "jpeg", "webp"])
        return files
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .map { "world/\($0.lastPathComponent)" }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func isValidProjectRoot(_ url: URL) -> Bool {
        ["godot/project.godot", "godot/assets", "BugpocalypseSwift/Package.swift"]
            .allSatisfy { fileManager.fileExists(atPath: url.appendingPathComponent($0).path) }
    }

    private func recursiveJSONFiles(at directory: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "json" }
    }

    private func missionDiagnostics(for mission: MissionDefinition) -> [ContentDiagnostic] {
        var result: [ContentDiagnostic] = []
        func add(_ severity: ContentSeverity, _ code: String, _ message: String, _ path: [String] = []) {
            result.append(.init(
                severity: severity,
                code: code,
                message: message,
                location: .init(documentID: mission.id, path: path)
            ))
        }
        if mission.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.error, "mission.id.empty", "Mission ID cannot be empty.", ["id"])
        }
        if mission.metadata.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(.error, "mission.name.empty", "Mission name cannot be empty.", ["metadata", "displayName"])
        }
        if mission.metadata.missionNumber < 1 {
            add(.error, "mission.number.invalid", "Mission number must be at least 1.", ["metadata", "missionNumber"])
        }
        if mission.metadata.starObjectives.isEmpty {
            add(.warning, "mission.objectives.empty", "Add star objectives before marking this mission ready.", ["metadata", "starObjectives"])
        }
        if mission.authoringStatus == .ready && mission.metadata.starObjectives.count != 3 {
            add(.error, "mission.objectives.count", "Ready missions must define exactly three star objectives.", ["metadata", "starObjectives"])
        }
        if mission.authoringStatus == .ready && !mission.metadata.starObjectives.contains(where: { $0.kind == .completeMission }) {
            add(.error, "mission.objectives.completion", "A ready mission must award a star for completion.", ["metadata", "starObjectives"])
        }
        if mission.timeline.isEmpty {
            add(mission.authoringStatus == .ready ? .error : .warning, "mission.timeline.empty", "The mission timeline is empty.", ["timeline"])
        }
        for (index, event) in mission.timeline.enumerated() {
            let path = ["timeline", "\(index)"]
            if !event.at.isFinite || event.at < 0 {
                add(.error, "mission.event.time", "Event \(index + 1) has an invalid time.", path + ["at"])
            }
            if case let .spawnFormation(spawn) = event.action {
                if EnemyCatalogue.entry(for: spawn.enemy.id) == nil {
                    add(.error, "mission.enemy.unknown", "Event \(index + 1) uses unknown enemy '\(spawn.enemy.id)'.", path + ["enemy"])
                }
                if spawn.enemy.level < 1 {
                    add(.error, "mission.enemy.level", "Enemy level must be at least 1.", path + ["enemy", "level"])
                }
                if spawn.formation.offsets().isEmpty {
                    add(.error, "mission.formation.empty", "A spawn formation needs at least one member.", path + ["formation"])
                }
            }
        }
        return result
    }

}
