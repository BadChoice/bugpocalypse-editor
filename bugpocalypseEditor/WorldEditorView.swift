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
    let moveCell: (String, WorldGridCoordinate) -> Void

    private let tileWidth: CGFloat = 96
    private let diamondHeight: CGFloat = 52

    var body: some View {
        let layout = CanvasLayout(cells: world.cells, tileWidth: tileWidth, diamondHeight: diamondHeight)
        ScrollView([.horizontal, .vertical]) {
            ZStack {
                Canvas { context, _ in
                    for cell in world.cells {
                        guard let from = layout.points[cell.id] else { continue }
                        for neighbourID in cell.neighbourIDs where cell.id < neighbourID {
                            guard let to = layout.points[neighbourID] else { continue }
                            var path = Path()
                            path.move(to: from)
                            path.addLine(to: to)
                            context.stroke(path, with: .color(.teal.opacity(0.45)), lineWidth: 3)
                        }
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height)

                ForEach(world.cells, id: \.id) { cell in
                    WorldCellTile(
                        cell: cell,
                        isSelected: selectedCellID == cell.id,
                        imageURL: assetURL(cell.tileName),
                        tileWidth: tileWidth,
                        diamondHeight: diamondHeight
                    )
                    .position(layout.points[cell.id] ?? .zero)
                    .onTapGesture { selectedCellID = cell.id }
                    .gesture(DragGesture(minimumDistance: 8).onEnded { value in
                        let dy = Int((-2 * value.translation.height / diamondHeight).rounded())
                        let dx = Int(((value.translation.width + (tileWidth * 0.5 * CGFloat(dy))) / tileWidth).rounded())
                        guard dx != 0 || dy != 0 else { return }
                        moveCell(cell.id, WorldGridCoordinate(x: cell.coordinate.x + dx, y: cell.coordinate.y + dy))
                    })
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
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
    let tileWidth: CGFloat
    let diamondHeight: CGFloat

    var body: some View {
        VStack(spacing: 2) {
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
                    .background(.black.opacity(0.65), in: Circle())
                    .foregroundStyle(.white)
            }
            Text(cell.displayName)
                .font(.caption.bold())
                .lineLimit(1)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.regularMaterial, in: Capsule())
            Text("\(cell.coordinate.x), \(cell.coordinate.y)")
                .font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
        .frame(width: tileWidth + 36, height: tileWidth + 45)
        .contentShape(Rectangle())
        .shadow(color: isSelected ? .accentColor.opacity(0.35) : .clear, radius: 8)
    }

    private var kindColor: Color {
        switch cell.kind {
        case .mission: .blue
        case .eliteMission: .purple
        case .boss: .red
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
            TextField("Name", text: worldBinding(\.displayName))
            TextField("ID", text: worldBinding(\.id))
            Picker("Status", selection: worldBinding(\.authoringStatus)) {
                ForEach(AuthoringStatus.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Stepper("Initial scout energy: \(workspace.selectedWorld?.definition.initialScoutEnergy ?? 0)", value: worldBinding(\.initialScoutEnergy), in: 0...999)
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
                TextField("Name", text: cellBinding(\.displayName))
                TextField("ID", text: Binding(
                    get: { workspace.selectedCell?.id ?? "" },
                    set: workspace.renameSelectedCell
                ))
                Picker("Kind", selection: cellBinding(\.kind)) {
                    ForEach(WorldCellKind.allCases, id: \.self) { Text(kindTitle($0)).tag($0) }
                }
                TextField("Tile", text: cellBinding(\.tileName))
            }
            Section("Grid") {
                Stepper("X: \(cell.coordinate.x)", value: coordinateBinding(\.x), in: -100...100)
                Stepper("Y: \(cell.coordinate.y)", value: coordinateBinding(\.y), in: -100...100)
                Text("\(cell.neighbourIDs.count) automatic connection\(cell.neighbourIDs.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }
            Section("Discovery") {
                Toggle("Initially visible", isOn: cellBinding(\.isInitiallyRevealed))
                Stepper("Scout energy: \(cell.scoutEnergyCost)", value: cellBinding(\.scoutEnergyCost), in: 0...999)
            }
            if cell.missionId != nil || [.mission, .eliteMission, .boss].contains(cell.kind) {
                Section("Mission") {
                    TextField("Mission ID", text: optionalCellBinding(\.missionId))
                    TextField("Resource path", text: optionalCellBinding(\.missionResourcePath))
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

    private func worldBinding<Value>(_ keyPath: WritableKeyPath<WorldDefinition, Value>) -> Binding<Value> {
        Binding(
            get: { workspace.selectedWorld!.definition[keyPath: keyPath] },
            set: { value in workspace.updateSelectedWorld { $0[keyPath: keyPath] = value } }
        )
    }

    private func cellBinding<Value>(_ keyPath: WritableKeyPath<WorldCellDefinition, Value>) -> Binding<Value> {
        Binding(
            get: { workspace.selectedCell![keyPath: keyPath] },
            set: { value in workspace.updateSelectedCell { $0[keyPath: keyPath] = value } }
        )
    }

    private func optionalCellBinding(_ keyPath: WritableKeyPath<WorldCellDefinition, String?>) -> Binding<String> {
        Binding(
            get: { workspace.selectedCell?[keyPath: keyPath] ?? "" },
            set: { value in workspace.updateSelectedCell { $0[keyPath: keyPath] = value.isEmpty ? nil : value } }
        )
    }

    private func coordinateBinding(_ keyPath: WritableKeyPath<WorldGridCoordinate, Int>) -> Binding<Int> {
        Binding(
            get: { workspace.selectedCell!.coordinate[keyPath: keyPath] },
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
