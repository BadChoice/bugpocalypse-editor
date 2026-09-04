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
    case formation(URL)
    case path(URL)
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
final class FormationEditorDocument: ObservableObject, Identifiable {
    let fileURL: URL
    @Published var definition: FormationDocument
    private(set) var savedDefinition: FormationDocument

    var id: URL { fileURL }
    var isDirty: Bool { definition != savedDefinition }

    init(fileURL: URL, definition: FormationDocument) {
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
final class PathEditorDocument: ObservableObject, Identifiable {
    let fileURL: URL
    @Published var definition: PathDocument
    private(set) var savedDefinition: PathDocument

    var id: URL { fileURL }
    var isDirty: Bool { definition != savedDefinition }

    init(fileURL: URL, definition: PathDocument) {
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
    @Published var formations: [FormationEditorDocument] = []
    @Published var paths: [PathEditorDocument] = []
    @Published var selection: EditorSelection?
    @Published var selectedCellID: String?
    @Published var selectedMissionEventIndex: Int?
    @Published var selectedFormationMemberIndex: Int?
    @Published var selectedPathPointIndex: Int?
    @Published var searchText = ""
    @Published var errorMessage: String?
    @Published var statusMessage = "No project open"

    private let fileManager = FileManager.default
    private let rememberedRootKey = "BugpocalypseEditor.projectRoot"
    private let rememberedRootBookmarkKey = "BugpocalypseEditor.projectRootBookmark"

    var selectedWorld: WorldDocument? {
        guard case .world(let url) = selection else { return nil }
        return worldDocument(at: url)
    }

    var selectedMission: MissionDocument? {
        guard case .mission(let url) = selection else { return nil }
        return missionDocument(at: url)
    }

    var selectedFormation: FormationEditorDocument? {
        guard case .formation(let url) = selection else { return nil }
        return formationDocument(at: url)
    }

    var selectedPath: PathEditorDocument? {
        guard case .path(let url) = selection else { return nil }
        return pathDocument(at: url)
    }

    var selectedCell: WorldCellDefinition? {
        guard let selectedCellID else { return nil }
        return selectedWorld?.definition.cell(id: selectedCellID)
    }

    var diagnostics: [ContentDiagnostic] {
        if let path = selectedPath {
            return pathDiagnostics(for: path.definition)
        }
        if let formation = selectedFormation {
            return formationDiagnostics(for: formation.definition)
        }
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

        if let bookmark = UserDefaults.standard.data(forKey: rememberedRootBookmarkKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), isValidProjectRoot(url) {
                if isStale { rememberProjectRoot(url) }
                openProject(at: url)
                return
            }
        }

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

            let formationsURL = root.appendingPathComponent("godot/assets/formations", isDirectory: true)
            formations = try recursiveJSONFiles(at: formationsURL).map { url in
                let data = try Data(contentsOf: url)
                return FormationEditorDocument(
                    fileURL: url,
                    definition: try ContentJSON.decode(FormationDocument.self, from: data)
                )
            }.sorted {
                $0.definition.id.localizedStandardCompare($1.definition.id) == .orderedAscending
            }

            let pathsURL = root.appendingPathComponent("godot/assets/paths", isDirectory: true)
            paths = try recursiveJSONFiles(at: pathsURL).map { url in
                let data = try Data(contentsOf: url)
                return PathEditorDocument(
                    fileURL: url,
                    definition: try ContentJSON.decode(PathDocument.self, from: data)
                )
            }.sorted {
                $0.definition.id.localizedStandardCompare($1.definition.id) == .orderedAscending
            }

            let resolvedRoot = root.standardizedFileURL
            projectRoot = resolvedRoot
            rememberProjectRoot(resolvedRoot)
            selection = worlds.first.map { .world($0.fileURL) } ?? .section(.worlds)
            selectedCellID = nil
            selectedFormationMemberIndex = nil
            selectedPathPointIndex = nil
            statusMessage = "Loaded \(worlds.count) world\(worlds.count == 1 ? "" : "s"), \(missions.count) missions, \(formations.count) formations, and \(paths.count) paths"
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

    func formationDocument(at url: URL) -> FormationEditorDocument? {
        formations.first { $0.fileURL == url }
    }

    func pathDocument(at url: URL) -> PathEditorDocument? {
        paths.first { $0.fileURL == url }
    }

    func resourcePath(for fileURL: URL) -> String? {
        guard let projectRoot else { return nil }
        let godotRoot = projectRoot.appendingPathComponent("godot", isDirectory: true).standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(godotRoot + "/") else { return nil }
        return "res://" + String(filePath.dropFirst(godotRoot.count + 1))
    }

    func formation(for reference: FormationReference?) -> FormationDefinition? {
        guard let referencePath = reference?.resourcePath else { return nil }
        return formations.first { resourcePath(for: $0.fileURL) == referencePath }?.definition.formation
    }

    func path(for reference: PathReference?) -> MovementPathDefinition? {
        guard let referencePath = reference?.resourcePath else { return nil }
        return paths.first { resourcePath(for: $0.fileURL) == referencePath }?.definition.path
    }

    func mission(for resourcePath: String?) -> MissionDefinition? {
        guard let resourcePath else { return nil }
        return missions.first { self.resourcePath(for: $0.fileURL) == resourcePath }?.definition
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

    func selectFormation(_ document: FormationEditorDocument) {
        selection = .formation(document.fileURL)
        selectedCellID = nil
        selectedMissionEventIndex = nil
        selectedFormationMemberIndex = nil
    }

    func selectPath(_ document: PathEditorDocument) {
        selection = .path(document.fileURL)
        selectedCellID = nil
        selectedMissionEventIndex = nil
        selectedFormationMemberIndex = nil
        selectedPathPointIndex = nil
    }

    func updateSelectedPath(_ change: (inout PathDocument) -> Void) {
        guard let document = selectedPath else { return }
        var value = document.definition
        change(&value)
        document.definition = value
        objectWillChange.send()
    }

    func createPath() {
        guard let projectRoot else { return }
        let directory = projectRoot.appendingPathComponent("godot/assets/paths", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let existingIDs = Set(paths.map(\.definition.id))
            var suffix = paths.count + 1
            while existingIDs.contains("path_\(suffix)") { suffix += 1 }
            let id = "path_\(suffix)"
            let url = directory.appendingPathComponent("\(id).json")
            let definition = PathDocument(
                schemaVersion: 2,
                id: id,
                authoringStatus: .draft,
                path: .waypoints(.init(duration: 6, points: [
                    .init(x: 1.1, y: 0.5),
                    .init(x: 0.65, y: 0.3),
                    .init(x: -0.1, y: 0.5)
                ]))
            )
            try ContentJSON.encode(definition).write(to: url, options: .atomic)
            let document = PathEditorDocument(fileURL: url, definition: definition)
            paths.append(document)
            paths.sort { $0.definition.id.localizedStandardCompare($1.definition.id) == .orderedAscending }
            selectPath(document)
            statusMessage = "Created \(url.lastPathComponent)"
        } catch {
            errorMessage = "The path could not be created: \(error.localizedDescription)"
        }
    }

    func duplicateSelectedPath() {
        guard let source = selectedPath else { return }
        let directory = source.fileURL.deletingLastPathComponent()
        do {
            let existingIDs = Set(paths.map(\.definition.id))
            var suffix = 2
            var id = "\(source.definition.id)_copy"
            while existingIDs.contains(id) {
                id = "\(source.definition.id)_copy_\(suffix)"
                suffix += 1
            }
            let url = directory.appendingPathComponent("\(id).json")
            var definition = source.definition
            definition.id = id
            definition.authoringStatus = .draft
            try ContentJSON.encode(definition).write(to: url, options: .atomic)
            let document = PathEditorDocument(fileURL: url, definition: definition)
            paths.append(document)
            paths.sort { $0.definition.id.localizedStandardCompare($1.definition.id) == .orderedAscending }
            selectPath(document)
            statusMessage = "Created \(url.lastPathComponent)"
        } catch {
            errorMessage = "The path could not be duplicated: \(error.localizedDescription)"
        }
    }

    func updateSelectedFormation(_ change: (inout FormationDocument) -> Void) {
        guard let document = selectedFormation else { return }
        var value = document.definition
        change(&value)
        document.definition = value
        objectWillChange.send()
    }

    func createFormation() {
        guard let projectRoot else { return }
        let directory = projectRoot.appendingPathComponent("godot/assets/formations", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let existingIDs = Set(formations.map(\.definition.id))
            var suffix = formations.count + 1
            while existingIDs.contains("formation_\(suffix)") { suffix += 1 }
            let id = "formation_\(suffix)"
            let url = directory.appendingPathComponent("\(id).json")
            let definition = FormationDocument(
                schemaVersion: 2,
                id: id,
                authoringStatus: .draft,
                formation: .line(.init(axis: .vertical, count: 3, spacing: 48))
            )
            try ContentJSON.encode(definition).write(to: url, options: .atomic)
            let document = FormationEditorDocument(fileURL: url, definition: definition)
            formations.append(document)
            formations.sort { $0.definition.id.localizedStandardCompare($1.definition.id) == .orderedAscending }
            selectFormation(document)
            statusMessage = "Created \(url.lastPathComponent)"
        } catch {
            errorMessage = "The formation could not be created: \(error.localizedDescription)"
        }
    }

    func duplicateSelectedFormation() {
        guard let source = selectedFormation else { return }
        let directory = source.fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let existingIDs = Set(formations.map(\.definition.id))
            var suffix = 2
            var id = "\(source.definition.id)_copy"
            while existingIDs.contains(id) {
                id = "\(source.definition.id)_copy_\(suffix)"
                suffix += 1
            }
            let url = directory.appendingPathComponent("\(id).json")
            var definition = source.definition
            definition.id = id
            definition.authoringStatus = .draft
            try ContentJSON.encode(definition).write(to: url, options: .atomic)
            let document = FormationEditorDocument(fileURL: url, definition: definition)
            formations.append(document)
            formations.sort { $0.definition.id.localizedStandardCompare($1.definition.id) == .orderedAscending }
            selectFormation(document)
            statusMessage = "Created \(url.lastPathComponent)"
        } catch {
            errorMessage = "The formation could not be duplicated: \(error.localizedDescription)"
        }
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

    func createMissionDefinitionForSelectedCell() {
        guard let world = selectedWorld, let cell = selectedCell else { return }
        guard [.mission, .boss].contains(cell.kind), cell.missionResourcePath == nil else { return }

        let linkedMissions = world.definition.cells.compactMap { mission(for: $0.missionResourcePath) }
        let locationID = linkedMissions.first?.metadata.locationId ?? world.definition.id.lowercased()
        let missionNumber = (missions
            .filter { $0.definition.metadata.locationId == locationID }
            .map { $0.definition.metadata.missionNumber }
            .max() ?? 0) + 1
        let missionID = "\(locationID)_\(missionNumber)"
        let resourcePath = "res://assets/missions/\(locationID)/\(missionNumber).json"
        let fallbackBackground = resourcePathForFirstBackground() ?? "res://assets/backgrounds/location1_field.json"
        guard let projectRoot else { return }
        let fileURL = projectRoot
            .appendingPathComponent("godot/assets/missions/\(locationID)", isDirectory: true)
            .appendingPathComponent("\(missionNumber).json")

        guard !fileManager.fileExists(atPath: fileURL.path) else {
            errorMessage = "A mission definition already exists at \(resourcePath)."
            return
        }

        let definition = MissionDefinition(
            schemaVersion: 1,
            id: missionID,
            authoringStatus: .draft,
            background: .init(resourcePath: fallbackBackground),
            metadata: .init(
                locationId: locationID,
                missionNumber: missionNumber,
                displayName: cell.displayName,
                recommendedHeroLevel: missionNumber,
                starObjectives: [.init(kind: .completeMission), .init(kind: .finishWithHealth, minimumPercentage: 0.75), .init(kind: .defeatAllEnemies)]
            ),
            completion: .init(kind: .clearAllWaves),
            timeline: []
        )

        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ContentJSON.encode(definition).write(to: fileURL, options: .atomic)
            let document = MissionDocument(fileURL: fileURL, definition: definition)
            missions.append(document)
            missions.sort { lhs, rhs in
                let a = lhs.definition.metadata, b = rhs.definition.metadata
                return a.locationId == b.locationId ? a.missionNumber < b.missionNumber : a.locationId < b.locationId
            }
            updateSelectedCell {
                $0.missionId = missionID
                $0.missionResourcePath = resourcePath
            }
            saveSelectedWorld()
            selectMission(document)
            statusMessage = "Created and linked Mission \(missionNumber)."
        } catch {
            errorMessage = "Could not create the mission definition: \(error.localizedDescription)"
        }
    }

    private func resourcePathForFirstBackground() -> String? {
        guard let projectRoot else { return nil }
        let backgrounds = recursiveJSONFiles(at: projectRoot.appendingPathComponent("godot/assets/backgrounds", isDirectory: true))
        return backgrounds.sorted { $0.path < $1.path }.first.flatMap(resourcePath(for:))
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

    func saveSelectedFormation() {
        guard let document = selectedFormation else { return }
        let errors = formationDiagnostics(for: document.definition).filter { $0.severity == .error }
        guard errors.isEmpty else {
            errorMessage = "The formation was not saved: fix \(errors.count) structural error\(errors.count == 1 ? "" : "s") first."
            return
        }
        do {
            try ContentJSON.encode(document.definition).write(to: document.fileURL, options: .atomic)
            document.markSaved()
            formations.sort { $0.definition.id.localizedStandardCompare($1.definition.id) == .orderedAscending }
            objectWillChange.send()
            statusMessage = "Saved \(document.fileURL.lastPathComponent)"
        } catch {
            errorMessage = "The formation was not saved: \(error.localizedDescription)"
        }
    }

    func saveSelectedPath() {
        guard let document = selectedPath else { return }
        let errors = pathDiagnostics(for: document.definition).filter { $0.severity == .error }
        guard errors.isEmpty else {
            errorMessage = "The path was not saved: fix \(errors.count) structural error\(errors.count == 1 ? "" : "s") first."
            return
        }
        do {
            try ContentJSON.encode(document.definition).write(to: document.fileURL, options: .atomic)
            document.markSaved()
            paths.sort { $0.definition.id.localizedStandardCompare($1.definition.id) == .orderedAscending }
            objectWillChange.send()
            statusMessage = "Saved \(document.fileURL.lastPathComponent)"
        } catch {
            errorMessage = "The path was not saved: \(error.localizedDescription)"
        }
    }

    func saveSelectedDocument() {
        if selectedPath != nil { saveSelectedPath() }
        else if selectedFormation != nil { saveSelectedFormation() }
        else if selectedMission != nil { saveSelectedMission() }
        else { saveSelectedWorld() }
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

    /// Retains file-system identity as well as the path, so reopening still
    /// works after the checkout is moved or renamed.
    private func rememberProjectRoot(_ root: URL) {
        UserDefaults.standard.set(root.path, forKey: rememberedRootKey)
        guard let bookmark = try? root.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(bookmark, forKey: rememberedRootBookmarkKey)
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
                if let reference = spawn.formationReference, formation(for: reference) == nil {
                    add(.error, "mission.formation.reference", "Event \(index + 1) references a missing saved formation.", path + ["formationReference"])
                }
                if let reference = spawn.pathReference, self.path(for: reference) == nil {
                    add(.error, "mission.path.reference", "Event \(index + 1) references a missing saved path.", path + ["pathReference"])
                }
                let formationDefinition = formation(for: spawn.formationReference) ?? spawn.formation
                if formationDefinition.offsets().isEmpty {
                    add(.error, "mission.formation.empty", "A spawn formation needs at least one member.", path + ["formation"])
                }
            }
        }
        return result
    }

    private func formationDiagnostics(for document: FormationDocument) -> [ContentDiagnostic] {
        var result: [ContentDiagnostic] = []
        func add(_ code: String, _ message: String, _ path: [String]) {
            result.append(.init(
                severity: .error,
                code: code,
                message: message,
                location: .init(documentID: document.id, path: path)
            ))
        }
        if document.schemaVersion != 2 {
            add("formation.schema", "Reusable formations must use schema version 2.", ["schemaVersion"])
        }
        if document.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add("formation.id.empty", "Formation ID cannot be empty.", ["id"])
        }
        if document.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add("formation.name.empty", "Formation name cannot be empty.", ["name"])
        }
        func positive(_ value: Double, _ field: String) {
            if !value.isFinite || value <= 0 { add("formation.\(field).invalid", "\(field) must be greater than zero.", ["formation", field]) }
        }
        func positive(_ value: Int, _ field: String) {
            if value <= 0 { add("formation.\(field).invalid", "\(field) must be greater than zero.", ["formation", field]) }
        }
        switch document.formation {
        case let .line(value):
            positive(value.count, "count"); positive(value.spacing, "spacing")
        case let .slottedLine(value):
            positive(value.slotCount, "slotCount"); positive(value.spacing, "spacing")
            if value.occupiedSlots.isEmpty { add("formation.slots.empty", "Choose at least one occupied slot.", ["formation", "occupiedSlots"]) }
            if value.occupiedSlots != value.occupiedSlots.sorted() || Set(value.occupiedSlots).count != value.occupiedSlots.count {
                add("formation.slots.order", "Occupied slots must be unique and ascending.", ["formation", "occupiedSlots"])
            }
            if value.occupiedSlots.contains(where: { $0 < 0 || $0 >= value.slotCount }) {
                add("formation.slots.range", "Occupied slots must be between 0 and \(max(0, value.slotCount - 1)).", ["formation", "occupiedSlots"])
            }
        case let .v(value):
            positive(value.count, "count"); positive(value.spacing, "spacing"); positive(value.depth, "depth")
        case let .staggeredGrid(value):
            positive(value.rows, "rows"); positive(value.columns, "columns")
            positive(value.spacingX, "spacingX"); positive(value.spacingY, "spacingY")
            if let rowOffset = value.rowOffset, !rowOffset.isFinite {
                add("formation.rowOffset.invalid", "rowOffset must be finite.", ["formation", "rowOffset"])
            }
        case let .arc(value):
            positive(value.count, "count"); positive(value.radius, "radius")
            if !value.startAngle.isFinite { add("formation.startAngle.invalid", "startAngle must be finite.", ["formation", "startAngle"]) }
            if !value.endAngle.isFinite { add("formation.endAngle.invalid", "endAngle must be finite.", ["formation", "endAngle"]) }
        case let .freeform(value):
            if value.members.isEmpty { add("formation.members.empty", "A freeform formation needs at least one member.", ["formation", "members"]) }
            let ids = value.members.compactMap(\.id).filter { !$0.isEmpty }
            if Set(ids).count != ids.count { add("formation.members.ids", "Named member IDs must be unique.", ["formation", "members"]) }
            for (index, member) in value.members.enumerated() where !member.offset.x.isFinite || !member.offset.y.isFinite {
                add("formation.member.offset", "Member \(index + 1) needs a finite offset.", ["formation", "members", "\(index)"])
            }
        }
        return result
    }

    private func pathDiagnostics(for document: PathDocument) -> [ContentDiagnostic] {
        var result: [ContentDiagnostic] = []
        func add(_ code: String, _ message: String, _ path: [String]) {
            result.append(.init(
                severity: .error,
                code: code,
                message: message,
                location: .init(documentID: document.id, path: path)
            ))
        }
        if document.schemaVersion != 2 {
            add("path.schema", "Reusable paths must use schema version 2.", ["schemaVersion"])
        }
        if document.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add("path.id.empty", "Path ID cannot be empty.", ["id"])
        }
        if document.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add("path.name.empty", "Path name cannot be empty.", ["name"])
        }
        func positive(_ value: Double, _ field: String) {
            if !value.isFinite || value <= 0 {
                add("path.\(field).invalid", "\(field) must be greater than zero.", ["path", field])
            }
        }
        func validLoopStart(_ value: Double?, duration: Double) {
            guard let value else { return }
            if !value.isFinite || value < 0 || value >= duration {
                add("path.loopStart.invalid", "Repeat-from time must be at least zero and less than the duration.", ["path", "loopStart"])
            }
        }
        switch document.path {
        case let .straight(value):
            positive(value.speed, "speed")
        case let .sine(value):
            positive(value.speed, "speed")
            positive(value.amplitude, "amplitude")
            positive(value.frequency, "frequency")
            if !value.phaseOffset.isFinite {
                add("path.phaseOffset.invalid", "phaseOffset must be finite.", ["path", "phaseOffset"])
            }
        case let .waypoints(value):
            positive(value.duration, "duration")
            validLoopStart(value.loopStart, duration: value.duration)
            if let loopToPoint = value.loopToPoint, !value.points.indices.contains(loopToPoint) {
                add("path.loopToPoint.invalid", "Loop waypoint must be one of this path's waypoints.", ["path", "loopToPoint"])
            }
            if value.points.count < 2 {
                add("path.points.count", "A waypoint path needs at least two points.", ["path", "points"])
            }
            for (index, point) in value.points.enumerated() where !point.x.isFinite || !point.y.isFinite {
                add("path.point.invalid", "Waypoint \(index + 1) needs finite coordinates.", ["path", "points", "\(index)"])
            }
        case let .bezier(value):
            positive(value.duration, "duration")
            validLoopStart(value.loopStart, duration: value.duration)
            let points: [(String, MovementPathPointDefinition)] = [
                ("start", value.start), ("control1", value.control1),
                ("control2", value.control2), ("end", value.end)
            ]
            for (field, point) in points where !point.x.isFinite || !point.y.isFinite {
                add("path.bezier.point.invalid", "Bézier \(field) needs finite coordinates.", ["path", field])
            }
        }
        return result
    }

}
