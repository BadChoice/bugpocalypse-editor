import AppKit
import BugpocalypseContent
import SwiftUI

struct WorldEditorView: View {
    @ObservedObject var workspace: EditorWorkspace
    @ObservedObject var document: WorldDocument

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.definition.displayName).font(.title2.bold())
                    Text("\(document.definition.cells.count) cells · \(document.definition.id)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: workspace.addCell) { Label("Add Cell", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
            Divider()
            WorldCanvas(
                world: document.definition,
                selectedCellID: $workspace.selectedCellID,
                assetURL: workspace.assetURL,
                missionNumber: { workspace.mission(for: $0)?.metadata.missionNumber },
                moveCell: workspace.moveCell
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct WorldCanvas: View {
    let world: WorldDefinition
    @Binding var selectedCellID: String?
    let assetURL: (String) -> URL?
    let missionNumber: (String?) -> Int?
    let moveCell: (String, WorldGridCoordinate) -> Void

    private let tileWidth: CGFloat = 96
    private let diamondHeight: CGFloat = 52
    @State private var zoom: CGFloat = 1

    var body: some View {
        let layout = CanvasLayout(cells: world.cells, tileWidth: tileWidth, diamondHeight: diamondHeight)
        ScrollView([.horizontal, .vertical]) {
            ZStack {
                Canvas { context, _ in
                    for cell in world.cells {
                        guard let from = layout.points[cell.id] else { continue }
                        for neighbour in world.edgeSharingCells(of: cell) where cell.id < neighbour.id {
                            guard let to = layout.points[neighbour.id] else { continue }
                            var path = Path()
                            path.move(to: from)
                            path.addLine(to: to)
                            context.stroke(path, with: .color(.teal.opacity(0.45)), lineWidth: 3)
                        }
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height)
                .allowsHitTesting(false)
                .zIndex(-10_000)

                ForEach(world.cells, id: \.id) { cell in
                    WorldCellTile(
                        cell: cell,
                        isSelected: selectedCellID == cell.id,
                        imageURL: assetURL(cell.tileName),
                        missionNumber: missionNumber(cell.missionResourcePath),
                        tileWidth: tileWidth,
                        diamondHeight: diamondHeight
                    )
                    .contentShape(WorldCellHitArea(diamondHeight: diamondHeight))
                    .onTapGesture { selectedCellID = cell.id }
                    .simultaneousGesture(DragGesture(minimumDistance: 8).onEnded { value in
                        let translation = CGSize(
                            width: value.translation.width / zoom,
                            height: value.translation.height / zoom
                        )
                        let dy = Int((-2 * translation.height / diamondHeight).rounded())
                        let dx = Int(((translation.width + (tileWidth * 0.5 * CGFloat(dy))) / tileWidth).rounded())
                        guard dx != 0 || dy != 0 else { return }
                        moveCell(cell.id, WorldGridCoordinate(x: cell.coordinate.x + dx, y: cell.coordinate.y + dy))
                    })
                    .position(layout.points[cell.id] ?? .zero)
                    // WorldScene renders cells by their anchor's screen Y.
                    // A smaller grid Y is visually closer, so it must also win
                    // hit testing where two isometric diamonds overlap.
                    .zIndex(-Double(cell.coordinate.y))
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .scaleEffect(zoom, anchor: .topLeading)
            .frame(width: layout.size.width * zoom, height: layout.size.height * zoom, alignment: .topLeading)
            .padding(40)
        }
        .background {
            Color(nsColor: .controlBackgroundColor)
                .overlay {
                    Image(systemName: "circle.grid.cross")
                        .font(.system(size: 320))
                        .foregroundStyle(.quaternary)
                }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                Button { changeZoom(by: -0.15) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("Zoom out")
                Text("\(Int((zoom * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 42)
                Button { changeZoom(by: 0.15) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom in")
                Button { zoom = 1 } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Reset zoom")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(12)
        }
    }

    private func changeZoom(by amount: CGFloat) {
        zoom = min(max(zoom + amount, 0.5), 2)
    }
}

private struct CanvasLayout {
    let points: [String: CGPoint]
    let size: CGSize

    init(cells: [WorldCellDefinition], tileWidth: CGFloat, diamondHeight: CGFloat) {
        let raw = Dictionary(uniqueKeysWithValues: cells.map { cell in
            (cell.id, CGPoint(
                x: CGFloat(cell.coordinate.x) * tileWidth - CGFloat(cell.coordinate.y) * tileWidth * 0.5,
                y: -CGFloat(cell.coordinate.y) * diamondHeight * 0.5
            ))
        })
        let xs = raw.values.map(\.x)
        let ys = raw.values.map(\.y)
        let minX = xs.min() ?? 0
        let minY = ys.min() ?? 0
        let maxX = xs.max() ?? 0
        let maxY = ys.max() ?? 0
        let inset = max(tileWidth, 100)
        points = raw.mapValues { CGPoint(x: $0.x - minX + inset, y: $0.y - minY + inset) }
        size = CGSize(width: max(maxX - minX + inset * 2, 640), height: max(maxY - minY + inset * 2, 520))
    }
}

private struct WorldCellTile: View {
    let cell: WorldCellDefinition
    let isSelected: Bool
    let imageURL: URL?
    let missionNumber: Int?
    let tileWidth: CGFloat
    let diamondHeight: CGFloat

    var body: some View {
        ZStack {
            Diamond()
                .fill(kindColor.opacity(0.28))
                .overlay(Diamond().stroke(isSelected ? Color.accentColor : .white.opacity(0.4), lineWidth: isSelected ? 4 : 1))
                .frame(width: tileWidth, height: diamondHeight)

            if let imageURL, let image = NSImage(contentsOf: imageURL) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: tileWidth, height: tileWidth)
                    .offset(y: -tileWidth * 0.25)
                    .allowsHitTesting(false)
            }

            Image(systemName: kindSymbol)
                .font(.body.bold())
                .padding(7)
                .background(kindSymbolColor, in: Circle())
                .foregroundStyle(.white)
                .allowsHitTesting(false)

            if let missionNumber {
                Text("M\(missionNumber)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.white.opacity(0.9), in: Capsule())
                    .offset(x: tileWidth * 0.30, y: -tileWidth * 0.30)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: tileWidth, height: tileWidth)
        .shadow(color: isSelected ? .accentColor.opacity(0.35) : .clear, radius: 8)
    }

    private var kindColor: Color {
        switch cell.kind {
        case .mission: .yellow
        case .eliteMission: .purple
        case .boss: .yellow
        case .supplyCache: .orange
        case .survivor: .green
        case .exploration: .teal
        case .terrain: .gray
        }
    }

    private var kindSymbol: String {
        switch cell.kind {
        case .mission: "flag.fill"
        case .eliteMission: "bolt.fill"
        case .boss: "ant.fill"
        case .supplyCache: "shippingbox.fill"
        case .survivor: "person.fill"
        case .exploration: "binoculars.fill"
        case .terrain: "leaf.fill"
        }
    }

    private var kindSymbolColor: Color {
        switch cell.kind {
        case .mission, .eliteMission, .boss: .yellow
        default: .black
        }
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// The cell view is square to make room for tall artwork, but only its ground
/// diamond should select it. Using the full square causes neighbouring cells'
/// invisible hit regions to overlap on the isometric grid.
private struct WorldCellHitArea: Shape {
    let diamondHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        let top = rect.midY - diamondHeight * 0.5
        let bottom = rect.midY + diamondHeight * 0.5
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: bottom))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

struct WorldInspector: View {
    @ObservedObject var workspace: EditorWorkspace

    var body: some View {
        Group {
            if workspace.selectedWorld == nil {
                ContentUnavailableView("No world selected", systemImage: "sidebar.right")
            } else {
                Form {
                    if workspace.selectedCell != nil { cellFields } else { worldFields }
                    diagnostics
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle(workspace.selectedCell == nil ? "World Inspector" : "Cell Inspector")
        .toolbar {
            if workspace.selectedCell != nil {
                ToolbarItem { Button("World") { workspace.selectedCellID = nil } }
            }
        }
    }

    @ViewBuilder private var worldFields: some View {
        Section("World") {
            TextField("Name", text: worldBinding(\.displayName, fallback: workspace.selectedWorld?.definition.displayName ?? ""))
            TextField("ID", text: worldBinding(\.id, fallback: workspace.selectedWorld?.definition.id ?? ""))
            Picker("Status", selection: worldBinding(\.authoringStatus, fallback: workspace.selectedWorld?.definition.authoringStatus ?? .draft)) {
                ForEach(AuthoringStatus.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Stepper("Initial scout energy: \(workspace.selectedWorld?.definition.initialScoutEnergy ?? 0)", value: worldBinding(\.initialScoutEnergy, fallback: workspace.selectedWorld?.definition.initialScoutEnergy ?? 0), in: 0...999)
            LabeledContent("Schema", value: "v\(workspace.selectedWorld?.definition.schemaVersion ?? 0)")
        }
        Section("Map") {
            LabeledContent("Cells", value: "\(workspace.selectedWorld?.definition.cells.count ?? 0)")
            Text("Select a cell on the canvas to edit it. Drag a cell to snap it to another grid coordinate.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var cellFields: some View {
        if let cell = workspace.selectedCell {
            Section("Identity") {
                TextField("Name", text: cellBinding(\.displayName, fallback: cell.displayName))
                TextField("ID", text: Binding(
                    get: { workspace.selectedCell?.id ?? "" },
                    set: workspace.renameSelectedCell
                ))
                Picker("Kind", selection: cellBinding(\.kind, fallback: cell.kind)) {
                    ForEach(WorldCellKind.allCases, id: \.self) { Text(kindTitle($0)).tag($0) }
                }
                Picker("Tile", selection: cellBinding(\.tileName, fallback: cell.tileName)) {
                    if !workspace.availableWorldTiles.contains(cell.tileName) {
                        Text("Missing: \(cell.tileName)").tag(cell.tileName)
                    }
                    ForEach(workspace.availableWorldTiles, id: \.self) { tileName in
                        Label(tileName.replacingOccurrences(of: "world/", with: ""), systemImage: "photo")
                            .tag(tileName)
                    }
                }
            }
            Section("Grid") {
                Stepper("X: \(cell.coordinate.x)", value: coordinateBinding(\.x, fallback: cell.coordinate.x), in: -100...100)
                Stepper("Y: \(cell.coordinate.y)", value: coordinateBinding(\.y, fallback: cell.coordinate.y), in: -100...100)
                let connectionCount = workspace.selectedWorld?.definition.edgeSharingCells(of: cell).count ?? 0
                Text("\(connectionCount) automatic connection\(connectionCount == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }
            Section("Discovery") {
                Toggle("Initially visible", isOn: cellBinding(\.isInitiallyRevealed, fallback: cell.isInitiallyRevealed))
                Stepper("Scout energy: \(cell.scoutEnergyCost)", value: cellBinding(\.scoutEnergyCost, fallback: cell.scoutEnergyCost), in: 0...999)
            }
            if cell.missionId != nil || [.mission, .eliteMission, .boss].contains(cell.kind) {
                Section("Mission") {
                    TextField("Mission ID", text: optionalCellBinding(\.missionId))
                    TextField("Resource path", text: optionalCellBinding(\.missionResourcePath))
                    if let mission = workspace.mission(for: cell.missionResourcePath) {
                        Label("Mission \(mission.metadata.missionNumber)", systemImage: "number.circle.fill")
                            .foregroundStyle(.secondary)
                    } else if [.mission, .boss].contains(cell.kind), cell.missionResourcePath == nil {
                        Button("Create Mission Definition", action: workspace.createMissionDefinitionForSelectedCell)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            Section {
                Button("Delete Cell", role: .destructive) { workspace.deleteSelectedCell() }
            }
        }
    }

    @ViewBuilder private var diagnostics: some View {
        Section("Diagnostics") {
            if workspace.diagnostics.isEmpty {
                Label("No structural errors", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                ForEach(workspace.diagnostics) { diagnostic in
                    Label(diagnostic.message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
        }
    }

    private func worldBinding<Value>(
        _ keyPath: WritableKeyPath<WorldDefinition, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { workspace.selectedWorld?.definition[keyPath: keyPath] ?? fallback },
            set: { value in
                guard workspace.selectedWorld != nil else { return }
                workspace.updateSelectedWorld { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func cellBinding<Value>(
        _ keyPath: WritableKeyPath<WorldCellDefinition, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { workspace.selectedCell?[keyPath: keyPath] ?? fallback },
            set: { value in
                guard workspace.selectedCell != nil else { return }
                workspace.updateSelectedCell { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func optionalCellBinding(_ keyPath: WritableKeyPath<WorldCellDefinition, String?>) -> Binding<String> {
        Binding(
            get: { workspace.selectedCell?[keyPath: keyPath] ?? "" },
            set: { value in workspace.updateSelectedCell { $0[keyPath: keyPath] = value.isEmpty ? nil : value } }
        )
    }

    private func coordinateBinding(
        _ keyPath: WritableKeyPath<WorldGridCoordinate, Int>,
        fallback: Int
    ) -> Binding<Int> {
        Binding(
            get: { workspace.selectedCell?.coordinate[keyPath: keyPath] ?? fallback },
            set: { value in
                guard let cell = workspace.selectedCell else { return }
                var coordinate = cell.coordinate
                coordinate[keyPath: keyPath] = value
                workspace.moveCell(id: cell.id, to: coordinate)
            }
        )
    }

    private func kindTitle(_ kind: WorldCellKind) -> String {
        String(describing: kind).reduce(into: "") { result, character in
            if character.isUppercase { result.append(" ") }
            result.append(character)
        }.capitalized
    }
}
