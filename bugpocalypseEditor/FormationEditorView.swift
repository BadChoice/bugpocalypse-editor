import BugpocalypseContent
import SwiftUI

struct FormationEditorView: View {
    @ObservedObject var workspace: EditorWorkspace
    @ObservedObject var document: FormationEditorDocument
    @State private var zoom: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            FormationCanvas(
                formation: document.definition.formation,
                selectedMemberIndex: $workspace.selectedFormationMemberIndex,
                zoom: zoom,
                moveFreeformMember: moveFreeformMember
            )
            .padding(14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.definition.name).font(.title2.bold())
                if document.definition.name != document.definition.id {
                    Text(document.definition.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Text("\(humanize(document.definition.formation.kind.rawValue)) · \(document.definition.formation.offsets().count) members")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button { zoom = max(0.5, zoom - 0.25) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                Text("\(Int(zoom * 100))%")
                    .font(.caption.monospacedDigit()).frame(width: 42)
                Button { zoom = min(2, zoom + 0.25) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                Button("Duplicate", action: workspace.duplicateSelectedFormation)
                Button(action: workspace.createFormation) { Label("New Formation", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
    }

    private func moveFreeformMember(_ index: Int, _ offset: ContentPoint) {
        workspace.updateSelectedFormation { document in
            guard case var .freeform(value) = document.formation,
                  value.members.indices.contains(index) else { return }
            value.members[index].offset = offset
            document.formation = .freeform(value)
        }
    }

    private func humanize(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            if character.isUppercase { result.append(" ") }
            result.append(character)
        }.capitalized
    }
}

private struct FormationCanvas: View {
    let formation: FormationDefinition
    @Binding var selectedMemberIndex: Int?
    let zoom: CGFloat
    let moveFreeformMember: (Int, ContentPoint) -> Void

    private let designSize = CGSize(width: 640, height: 360)

    var body: some View {
        GeometryReader { geometry in
            let availableScale = min(geometry.size.width / designSize.width, geometry.size.height / designSize.height)
            let scale = availableScale * zoom
            let origin = CGPoint(
                x: geometry.size.width / 2 - designSize.width * scale / 2,
                y: geometry.size.height / 2 - designSize.height * scale / 2
            )
            ZStack(alignment: .topLeading) {
                Color(red: 0.035, green: 0.055, blue: 0.085)
                grid(origin: origin, scale: scale)
                ForEach(Array(formation.offsets().enumerated()), id: \.offset) { index, offset in
                    member(index: index, offset: offset, origin: origin, scale: scale)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("FORMATION SPACE")
                    Text("640 × 360 px · anchor (0, 0)")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .padding(10)
            }
            .coordinateSpace(name: "formationCanvas")
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func grid(origin: CGPoint, scale: CGFloat) -> some View {
        Canvas { context, _ in
            let rect = CGRect(origin: origin, size: .init(width: designSize.width * scale, height: designSize.height * scale))
            context.fill(Path(rect), with: .color(.black.opacity(0.18)))
            context.stroke(Path(rect), with: .color(.white.opacity(0.3)), lineWidth: 1)
            for x in stride(from: 0.0, through: 640.0, by: 40.0) {
                var path = Path()
                path.move(to: CGPoint(x: origin.x + x * scale, y: origin.y))
                path.addLine(to: CGPoint(x: origin.x + x * scale, y: origin.y + designSize.height * scale))
                context.stroke(path, with: .color(.white.opacity(x == 320 ? 0.25 : 0.055)), lineWidth: 1)
            }
            for y in stride(from: 0.0, through: 360.0, by: 40.0) {
                var path = Path()
                path.move(to: CGPoint(x: origin.x, y: origin.y + y * scale))
                path.addLine(to: CGPoint(x: origin.x + designSize.width * scale, y: origin.y + y * scale))
                context.stroke(path, with: .color(.white.opacity(y == 160 || y == 200 ? 0.12 : 0.055)), lineWidth: 1)
            }
            let anchor = CGPoint(x: origin.x + 320 * scale, y: origin.y + 180 * scale)
            var horizontal = Path(); horizontal.move(to: .init(x: anchor.x - 8, y: anchor.y)); horizontal.addLine(to: .init(x: anchor.x + 8, y: anchor.y))
            var vertical = Path(); vertical.move(to: .init(x: anchor.x, y: anchor.y - 8)); vertical.addLine(to: .init(x: anchor.x, y: anchor.y + 8))
            context.stroke(horizontal, with: .color(.mint.opacity(0.9)), lineWidth: 2)
            context.stroke(vertical, with: .color(.mint.opacity(0.9)), lineWidth: 2)
        }
    }

    private func member(index: Int, offset: ContentPoint, origin: CGPoint, scale: CGFloat) -> some View {
        let selected = selectedMemberIndex == index
        let position = CGPoint(
            x: origin.x + (320 + offset.x) * scale,
            y: origin.y + (180 + offset.y) * scale
        )
        return ZStack {
            Circle()
                .fill(selected ? Color.accentColor : Color.orange)
                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: selected ? 3 : 1))
            Text("\(index + 1)")
                .font(.caption2.bold()).foregroundStyle(.black)
        }
        .frame(width: max(18, 30 * scale), height: max(18, 30 * scale))
        .position(position)
        .contentShape(Circle())
        .onTapGesture { selectedMemberIndex = index }
        .gesture(DragGesture(coordinateSpace: .named("formationCanvas")).onChanged { value in
            guard case .freeform = formation, scale > 0 else { return }
            selectedMemberIndex = index
            moveFreeformMember(index, .init(
                x: (value.location.x - origin.x) / scale - 320,
                y: (value.location.y - origin.y) / scale - 180
            ))
        })
        .help(caseIsFreeform ? "Drag to reposition this member" : "Member \(index + 1): (\(Int(offset.x)), \(Int(offset.y)))")
    }

    private var caseIsFreeform: Bool {
        if case .freeform = formation { true } else { false }
    }
}

struct FormationInspector: View {
    @ObservedObject var workspace: EditorWorkspace

    var body: some View {
        Group {
            if let document = workspace.selectedFormation?.definition {
                Form {
                    identity(document)
                    geometry(document.formation)
                    if case let .freeform(value) = document.formation { members(value) }
                    diagnostics
                    Section("Actions") {
                        Button("Duplicate and Edit", action: workspace.duplicateSelectedFormation)
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("No formation selected", systemImage: "sidebar.right")
            }
        }
        .navigationTitle("Formation Inspector")
    }

    private func identity(_ document: FormationDocument) -> some View {
        Section("Formation") {
            LabeledContent("ID", value: document.id)
            TextField("Name", text: documentBinding(\.name, fallback: document.name))
            Picker("Status", selection: documentBinding(\.authoringStatus, fallback: document.authoringStatus)) {
                ForEach(AuthoringStatus.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Picker("Kind", selection: kindBinding) {
                ForEach(FormationKind.allCases, id: \.self) { Text(humanize($0.rawValue)).tag($0) }
            }
            LabeledContent("Schema", value: "v\(document.schemaVersion)")
        }
    }

    @ViewBuilder private func geometry(_ formation: FormationDefinition) -> some View {
        Section("Geometry") {
            switch formation {
            case let .line(value):
                axisPicker(lineBinding(\.axis, fallback: value.axis))
                Stepper("Members: \(value.count)", value: lineBinding(\.count, fallback: value.count), in: 1...100)
                pixels("Spacing", lineBinding(\.spacing, fallback: value.spacing))
            case let .slottedLine(value):
                axisPicker(slottedBinding(\.axis, fallback: value.axis))
                Stepper("Slots: \(value.slotCount)", value: slottedBinding(\.slotCount, fallback: value.slotCount), in: 1...100)
                pixels("Spacing", slottedBinding(\.spacing, fallback: value.spacing))
                TextField("Occupied slots", text: occupiedSlotsBinding)
                Text("Zero-based, comma-separated slot numbers.").font(.caption).foregroundStyle(.secondary)
            case let .v(value):
                Stepper("Members: \(value.count)", value: vBinding(\.count, fallback: value.count), in: 1...100)
                pixels("Leg spacing", vBinding(\.spacing, fallback: value.spacing))
                pixels("Depth per step", vBinding(\.depth, fallback: value.depth))
            case let .staggeredGrid(value):
                Stepper("Rows: \(value.rows)", value: gridBinding(\.rows, fallback: value.rows), in: 1...30)
                Stepper("Columns: \(value.columns)", value: gridBinding(\.columns, fallback: value.columns), in: 1...30)
                pixels("Horizontal spacing", gridBinding(\.spacingX, fallback: value.spacingX))
                pixels("Vertical spacing", gridBinding(\.spacingY, fallback: value.spacingY))
                Toggle("Custom row offset", isOn: rowOffsetEnabled)
                if value.rowOffset != nil { pixels("Row offset", rowOffsetBinding) }
            case let .arc(value):
                Stepper("Members: \(value.count)", value: arcBinding(\.count, fallback: value.count), in: 1...100)
                pixels("Radius", arcBinding(\.radius, fallback: value.radius))
                degrees("Start angle", arcBinding(\.startAngle, fallback: value.startAngle))
                degrees("End angle", arcBinding(\.endAngle, fallback: value.endAngle))
            case let .trail(value):
                Stepper("Members: \(value.count)", value: trailBinding(\.count, fallback: value.count), in: 1...100)
                TextField("Follow delay (seconds)", value: trailBinding(\.followDelay, fallback: value.followDelay), format: .number)
                Text("Members follow the same path in sequence. Preview the result in a mission.")
                    .font(.caption).foregroundStyle(.secondary)
            case let .freeform(value):
                LabeledContent("Members", value: "\(value.members.count)")
                Text("Drag members on the canvas or edit exact offsets below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func members(_ value: FreeformFormation) -> some View {
        Section("Members") {
            ForEach(Array(value.members.enumerated()), id: \.offset) { index, member in
                DisclosureGroup(isExpanded: memberExpanded(index)) {
                    TextField("Member ID", text: memberIDBinding(index, fallback: member.id ?? ""))
                    pixels("X offset", memberOffsetBinding(index, \.x, fallback: member.offset.x))
                    pixels("Y offset", memberOffsetBinding(index, \.y, fallback: member.offset.y))
                    Button("Remove Member", role: .destructive) { removeMember(index) }
                } label: {
                    Text(member.id?.isEmpty == false ? member.id! : "Member \(index + 1)")
                }
            }
            Button("Add Member", action: addMember)
        }
    }

    private var diagnostics: some View {
        Section("Diagnostics") {
            if workspace.diagnostics.isEmpty {
                Label("No issues", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                ForEach(workspace.diagnostics) { diagnostic in
                    Label(diagnostic.message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                }
            }
        }
    }

    private func documentBinding<Value>(_ keyPath: WritableKeyPath<FormationDocument, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { workspace.selectedFormation?.definition[keyPath: keyPath] ?? fallback },
            set: { value in workspace.updateSelectedFormation { $0[keyPath: keyPath] = value } }
        )
    }

    private var kindBinding: Binding<FormationKind> {
        Binding(
            get: { workspace.selectedFormation?.definition.formation.kind ?? .line },
            set: { kind in
                workspace.selectedFormationMemberIndex = nil
                workspace.updateSelectedFormation { $0.formation = defaultFormation(kind) }
            }
        )
    }

    private func formationBinding<Value, Payload>(
        _ extract: @escaping (FormationDefinition) -> Payload?,
        _ wrap: @escaping (Payload) -> FormationDefinition,
        _ keyPath: WritableKeyPath<Payload, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(get: {
            guard let formation = workspace.selectedFormation?.definition.formation,
                  let payload = extract(formation) else { return fallback }
            return payload[keyPath: keyPath]
        }, set: { newValue in
            workspace.updateSelectedFormation { document in
                guard var payload = extract(document.formation) else { return }
                payload[keyPath: keyPath] = newValue
                document.formation = wrap(payload)
            }
        })
    }

    private func lineBinding<Value>(_ kp: WritableKeyPath<LineFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .line(v) = $0 { v } else { nil } }, FormationDefinition.line, kp, fallback: fallback) }
    private func slottedBinding<Value>(_ kp: WritableKeyPath<SlottedLineFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .slottedLine(v) = $0 { v } else { nil } }, FormationDefinition.slottedLine, kp, fallback: fallback) }
    private func vBinding<Value>(_ kp: WritableKeyPath<VFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .v(v) = $0 { v } else { nil } }, FormationDefinition.v, kp, fallback: fallback) }
    private func gridBinding<Value>(_ kp: WritableKeyPath<StaggeredGridFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .staggeredGrid(v) = $0 { v } else { nil } }, FormationDefinition.staggeredGrid, kp, fallback: fallback) }
    private func arcBinding<Value>(_ kp: WritableKeyPath<ArcFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .arc(v) = $0 { v } else { nil } }, FormationDefinition.arc, kp, fallback: fallback) }
    private func trailBinding<Value>(_ kp: WritableKeyPath<TrailFormation, Value>, fallback: Value) -> Binding<Value> { formationBinding({ if case let .trail(v) = $0 { v } else { nil } }, FormationDefinition.trail, kp, fallback: fallback) }

    private func axisPicker(_ selection: Binding<FormationAxis>) -> some View {
        Picker("Axis", selection: selection) {
            ForEach(FormationAxis.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
    }

    private func pixels(_ title: String, _ value: Binding<Double>) -> some View {
        TextField("\(title) (px)", value: value, format: .number.precision(.fractionLength(0...2)))
    }

    private func degrees(_ title: String, _ value: Binding<Double>) -> some View {
        TextField("\(title) (°)", value: value, format: .number.precision(.fractionLength(0...2)))
    }

    private var occupiedSlotsBinding: Binding<String> {
        Binding(get: {
            guard let formation = workspace.selectedFormation?.definition.formation,
                  case let .slottedLine(value) = formation else { return "" }
            return value.occupiedSlots.map(String.init).joined(separator: ", ")
        }, set: { text in
            workspace.updateSelectedFormation { document in
                guard case var .slottedLine(value) = document.formation else { return }
                value.occupiedSlots = text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                document.formation = .slottedLine(value)
            }
        })
    }

    private var rowOffsetEnabled: Binding<Bool> {
        Binding(get: {
            workspace.selectedFormation?.definition.formation.rowOffset != nil
        }, set: { enabled in
            workspace.updateSelectedFormation { document in
                guard case var .staggeredGrid(value) = document.formation else { return }
                value.rowOffset = enabled ? value.spacingX / 2 : nil
                document.formation = .staggeredGrid(value)
            }
        })
    }

    private var rowOffsetBinding: Binding<Double> {
        Binding(get: {
            workspace.selectedFormation?.definition.formation.rowOffset ?? 0
        }, set: { newValue in
            workspace.updateSelectedFormation { document in
                guard case var .staggeredGrid(value) = document.formation else { return }
                value.rowOffset = newValue
                document.formation = .staggeredGrid(value)
            }
        })
    }

    private func memberExpanded(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { workspace.selectedFormationMemberIndex == index },
            set: { workspace.selectedFormationMemberIndex = $0 ? index : nil }
        )
    }

    private func memberIDBinding(_ index: Int, fallback: String) -> Binding<String> {
        Binding(get: {
            guard let formation = workspace.selectedFormation?.definition.formation,
                  case let .freeform(value) = formation,
                  value.members.indices.contains(index) else { return fallback }
            return value.members[index].id ?? ""
        }, set: { newValue in
            mutateMember(index) { $0.id = newValue.isEmpty ? nil : newValue }
        })
    }

    private func memberOffsetBinding(_ index: Int, _ keyPath: WritableKeyPath<ContentPoint, Double>, fallback: Double) -> Binding<Double> {
        Binding(get: {
            guard let formation = workspace.selectedFormation?.definition.formation,
                  case let .freeform(value) = formation,
                  value.members.indices.contains(index) else { return fallback }
            return value.members[index].offset[keyPath: keyPath]
        }, set: { newValue in
            mutateMember(index) { $0.offset[keyPath: keyPath] = newValue }
        })
    }

    private func mutateMember(_ index: Int, _ change: (inout FormationMember) -> Void) {
        workspace.updateSelectedFormation { document in
            guard case var .freeform(value) = document.formation,
                  value.members.indices.contains(index) else { return }
            change(&value.members[index])
            document.formation = .freeform(value)
        }
    }

    private func addMember() {
        workspace.updateSelectedFormation { document in
            guard case var .freeform(value) = document.formation else { return }
            let index = value.members.count
            value.members.append(.init(id: "member_\(index + 1)", offset: .init(x: Double(index) * 40, y: 0)))
            document.formation = .freeform(value)
            workspace.selectedFormationMemberIndex = index
        }
    }

    private func removeMember(_ index: Int) {
        workspace.updateSelectedFormation { document in
            guard case var .freeform(value) = document.formation,
                  value.members.indices.contains(index) else { return }
            value.members.remove(at: index)
            document.formation = .freeform(value)
        }
        workspace.selectedFormationMemberIndex = nil
    }

    private func defaultFormation(_ kind: FormationKind) -> FormationDefinition {
        switch kind {
        case .line: .line(.init(axis: .vertical, count: 3, spacing: 48))
        case .slottedLine: .slottedLine(.init(axis: .vertical, slotCount: 5, spacing: 48, occupiedSlots: [0, 2, 4]))
        case .v: .v(.init(count: 5, spacing: 36, depth: 28))
        case .staggeredGrid: .staggeredGrid(.init(rows: 2, columns: 3, spacingX: 48, spacingY: 48))
        case .arc: .arc(.init(count: 5, radius: 80, startAngle: 120, endAngle: 240))
        case .trail: .trail(.init(count: 5, followDelay: 0.35))
        case .freeform: .freeform(.init(members: [.init(id: "member_1", offset: .init(x: 0, y: 0))]))
        }
    }

    private func humanize(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            if character.isUppercase { result.append(" ") }
            result.append(character)
        }.capitalized
    }
}
