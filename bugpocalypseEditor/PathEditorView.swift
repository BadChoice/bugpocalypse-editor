import BugpocalypseContent
import SwiftUI

struct PathEditorView: View {
    @ObservedObject var workspace: EditorWorkspace
    @ObservedObject var document: PathEditorDocument
    @State private var zoom: CGFloat = 1
    @State private var showTrace = true
    @State private var showSampledTimes = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            PathCanvas(
                pathDefinition: document.definition.path,
                selectedPointIndex: $workspace.selectedPathPointIndex,
                zoom: zoom,
                showTrace: showTrace,
                showSampledTimes: showSampledTimes,
                movePoint: movePoint
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
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Trace", isOn: $showTrace).toggleStyle(.button)
            Toggle("Times", isOn: $showSampledTimes).toggleStyle(.button)
            HStack(spacing: 8) {
                Button { zoom = max(0.25, zoom - 0.25) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                Text("\(Int(zoom * 100))%")
                    .font(.caption.monospacedDigit()).frame(width: 42)
                Button { zoom = min(2, zoom + 0.25) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                Button("Duplicate", action: workspace.duplicateSelectedPath)
                Button(action: workspace.createPath) { Label("New Path", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
    }

    private var summary: String {
        switch document.definition.path {
        case let .straight(value): "Straight · \(value.speed.formatted()) px/s"
        case let .sine(value): "Sine · \(value.speed.formatted()) px/s · \(value.amplitude.formatted()) px amplitude"
        case let .waypoints(value): "Waypoints · \(value.points.count) points · \(value.duration.formatted()) s\(value.loopStart == nil ? "" : " · loops")"
        case let .bezier(value): "Bézier · \(value.segmentCount) segment\(value.segmentCount == 1 ? "" : "s") · \(value.duration.formatted()) s\(value.loopStart == nil ? "" : " · loops")"
        }
    }

    private func movePoint(_ index: Int, _ point: MovementPathPointDefinition) {
        workspace.updateSelectedPath { document in
            switch document.path {
            case var .waypoints(value):
                guard value.points.indices.contains(index) else { return }
                value.points[index] = point
                document.path = .waypoints(value)
            case var .bezier(value):
                switch index {
                case 0: value.start = point
                case 1: value.control1 = point
                case 2: value.control2 = point
                case 3: value.end = point
                default:
                    let segmentIndex = (index - 4) / 3
                    let controlIndex = (index - 4) % 3
                    guard value.additionalSegments.indices.contains(segmentIndex) else { return }
                    switch controlIndex {
                    case 0: value.additionalSegments[segmentIndex].control1 = point
                    case 1: value.additionalSegments[segmentIndex].control2 = point
                    case 2: value.additionalSegments[segmentIndex].end = point
                    default: return
                    }
                }
                document.path = .bezier(value)
            default: return
            }
        }
    }
}

private struct PathCanvas: View {
    let pathDefinition: MovementPathDefinition
    @Binding var selectedPointIndex: Int?
    let zoom: CGFloat
    let showTrace: Bool
    let showSampledTimes: Bool
    let movePoint: (Int, MovementPathPointDefinition) -> Void
    @State private var draggedWaypointIndex: Int?

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
                if showTrace { trace(origin: origin, scale: scale) }
                if showSampledTimes { sampleMarkers(origin: origin, scale: scale) }
                ForEach(editablePoints) { point in
                    controlPoint(point, origin: origin, scale: scale)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("GAMEPLAY SPACE")
                    Text("640 × 360 px · normalized waypoint coordinates")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .padding(10)
            }
            .coordinateSpace(name: "pathCanvas")
            .contentShape(Rectangle())
            .gesture(waypointGesture(origin: origin, scale: scale))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func grid(origin: CGPoint, scale: CGFloat) -> some View {
        Canvas { context, _ in
            let rect = CGRect(origin: origin, size: .init(width: designSize.width * scale, height: designSize.height * scale))
            context.fill(Path(rect), with: .color(.black.opacity(0.18)))
            context.stroke(Path(rect), with: .color(.white.opacity(0.3)), lineWidth: 1)
            for x in stride(from: 0.0, through: 640.0, by: 80.0) {
                var line = Path()
                line.move(to: .init(x: origin.x + x * scale, y: origin.y))
                line.addLine(to: .init(x: origin.x + x * scale, y: origin.y + 360 * scale))
                context.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 1)
            }
            for y in stride(from: 0.0, through: 360.0, by: 60.0) {
                var line = Path()
                line.move(to: .init(x: origin.x, y: origin.y + y * scale))
                line.addLine(to: .init(x: origin.x + 640 * scale, y: origin.y + y * scale))
                context.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: 1)
            }
        }
    }

    private func trace(origin: CGPoint, scale: CGFloat) -> some View {
        Canvas { context, _ in
            let samples = routeSamples
            guard let first = samples.first else { return }
            var route = Path()
            route.move(to: canvasPoint(first.point, origin: origin, scale: scale))
            for sample in samples.dropFirst() {
                route.addLine(to: canvasPoint(sample.point, origin: origin, scale: scale))
            }
            context.stroke(route, with: .color(.cyan.opacity(0.85)), style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    private func sampleMarkers(origin: CGPoint, scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(labelledSamples.enumerated()), id: \.offset) { _, sample in
                let position = canvasPoint(sample.point, origin: origin, scale: scale)
                ZStack {
                    Circle().fill(.cyan).frame(width: 7, height: 7)
                    Text(sample.label)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white)
                        .offset(x: 4, y: -12)
                }
                .position(position)
            }
        }
    }

    private func controlPoint(_ point: EditablePathPoint, origin: CGPoint, scale: CGFloat) -> some View {
        let selected = selectedPointIndex == point.id
        return ZStack {
            Circle()
                .fill(selected ? Color.accentColor : Color.orange)
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: selected ? 3 : 1))
            Text(point.label).font(.caption2.bold()).foregroundStyle(.black)
        }
        .frame(width: max(20, 28 * scale), height: max(20, 28 * scale))
        .position(canvasPoint(point.value, origin: origin, scale: scale))
        .help("\(point.accessibilityLabel): (\(point.value.x.formatted()), \(point.value.y.formatted()))")
    }

    /// Handles live in a ZStack, so independent gestures are hit-tested from
    /// front to back and the final handle wins. Resolve the nearest waypoint
    /// once from the canvas instead, then retain that selection for the drag.
    private func waypointGesture(origin: CGPoint, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("pathCanvas"))
            .onChanged { value in
                let points = editablePoints
                guard !points.isEmpty, scale > 0 else { return }
                if draggedWaypointIndex == nil {
                    guard let index = closestWaypoint(
                        to: value.startLocation,
                        points: points,
                        origin: origin,
                        scale: scale
                    ) else { return }
                    draggedWaypointIndex = index
                    selectedPointIndex = index
                }
                guard let index = draggedWaypointIndex,
                      abs(value.translation.width) > 2 || abs(value.translation.height) > 2 else { return }
                movePoint(index, .init(
                    x: (value.location.x - origin.x) / (640 * scale),
                    y: (value.location.y - origin.y) / (360 * scale)
                ))
            }
            .onEnded { _ in
                draggedWaypointIndex = nil
            }
    }

    private func closestWaypoint(
        to location: CGPoint,
        points: [EditablePathPoint],
        origin: CGPoint,
        scale: CGFloat
    ) -> Int? {
        let hitRadius = max(20, 28 * scale) / 2 + 8
        return points
            .map { point -> (index: Int, distance: CGFloat) in
                let position = canvasPoint(point.value, origin: origin, scale: scale)
                return (point.id, hypot(location.x - position.x, location.y - position.y))
            }
            .filter { $0.distance <= hitRadius }
            .min { $0.distance < $1.distance }?
            .index
    }

    private func canvasPoint(_ point: MovementPathPointDefinition, origin: CGPoint, scale: CGFloat) -> CGPoint {
        .init(x: origin.x + point.x * 640 * scale, y: origin.y + point.y * 360 * scale)
    }

    private var editablePoints: [EditablePathPoint] {
        switch pathDefinition {
        case let .waypoints(value):
            return value.points.enumerated().map { .init(id: $0.offset, label: "\($0.offset + 1)", accessibilityLabel: "Waypoint \($0.offset + 1)", value: $0.element) }
        case let .bezier(value):
            let firstSegment: [EditablePathPoint] = [
                EditablePathPoint(id: 0, label: "S", accessibilityLabel: "Start", value: value.start),
                EditablePathPoint(id: 1, label: "1", accessibilityLabel: "Control 1", value: value.control1),
                EditablePathPoint(id: 2, label: "2", accessibilityLabel: "Control 2", value: value.control2),
                EditablePathPoint(id: 3, label: "E", accessibilityLabel: "End", value: value.end)
            ]
            let additional = value.additionalSegments.enumerated().flatMap { segmentIndex, segment in
                let id = 4 + segmentIndex * 3
                let number = segmentIndex + 2
                return [
                    EditablePathPoint(id: id, label: "\(number)·1", accessibilityLabel: "Segment \(number) control 1", value: segment.control1),
                    EditablePathPoint(id: id + 1, label: "\(number)·2", accessibilityLabel: "Segment \(number) control 2", value: segment.control2),
                    EditablePathPoint(id: id + 2, label: "\(number)·E", accessibilityLabel: "Segment \(number) end", value: segment.end)
                ]
            }
            return firstSegment + additional
        case .straight, .sine: return []
        }
    }

    private var routeSamples: [(time: Double, point: MovementPathPointDefinition)] {
        switch pathDefinition {
        case let .waypoints(value):
            guard value.points.count >= 2 else { return value.points.enumerated().map { (Double($0.offset), $0.element) } }
            let count = 80
            return (0...count).map { index in
                let elapsed = value.duration * Double(index) / Double(count)
                return (elapsed, normalizedPosition(elapsed: elapsed))
            }
        case let .bezier(value):
            let count = 80
            return (0...count).map { index in
                let elapsed = value.duration * Double(index) / Double(count)
                return (elapsed, normalizedPosition(elapsed: elapsed))
            }
        case .straight, .sine:
            let count = 80
            return (0...count).map { index in
                let elapsed = 5 * Double(index) / Double(count)
                return (elapsed, normalizedPosition(elapsed: elapsed))
            }
        }
    }

    private var labelledSamples: [(label: String, point: MovementPathPointDefinition)] {
        let duration: Double
        switch pathDefinition {
        case let .waypoints(value): duration = max(0, value.duration)
        case let .bezier(value): duration = max(0, value.duration)
        case .straight, .sine: duration = 5
        }
        guard duration > 0 else { return [] }
        let count = min(10, max(1, Int(ceil(duration))))
        return (0...count).map { index in
            let time = duration * Double(index) / Double(count)
            return ("\(time.formatted(.number.precision(.fractionLength(0...1))))s", normalizedPosition(elapsed: time))
        }
    }

    private func normalizedPosition(elapsed: Double) -> MovementPathPointDefinition {
        switch pathDefinition {
        case let .waypoints(value):
            guard value.points.count >= 2, value.duration > 0 else { return value.points.first ?? .init(x: 0, y: 0) }
            return value.point(at: elapsed)
        case let .bezier(value):
            guard value.duration > 0 else { return value.start }
            return value.point(at: value.effectiveElapsed(at: elapsed) / value.duration)
        case .straight, .sine:
            let offset = pathDefinition.offset(elapsed: elapsed)
            return .init(x: 0.95 + offset.x / 640, y: 0.5 + offset.y / 360)
        }
    }
}

private struct EditablePathPoint: Identifiable {
    let id: Int
    let label: String
    let accessibilityLabel: String
    let value: MovementPathPointDefinition
}

struct PathInspector: View {
    @ObservedObject var workspace: EditorWorkspace

    var body: some View {
        Group {
            if let document = workspace.selectedPath?.definition {
                Form {
                    identity(document)
                    parameters(document.path)
                    if case let .waypoints(value) = document.path { waypoints(value) }
                    if case let .bezier(value) = document.path { bezierControls(value) }
                    diagnostics
                    Section("Actions") {
                        Button("Duplicate and Edit", action: workspace.duplicateSelectedPath)
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("No path selected", systemImage: "sidebar.right")
            }
        }
        .navigationTitle("Path Inspector")
    }

    private func identity(_ document: PathDocument) -> some View {
        Section("Path") {
            LabeledContent("ID", value: document.id)
            TextField("Name", text: documentBinding(\.name, fallback: document.name))
            Picker("Status", selection: documentBinding(\.authoringStatus, fallback: document.authoringStatus)) {
                ForEach(AuthoringStatus.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Picker("Kind", selection: kindBinding) {
                ForEach(MovementPathKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            LabeledContent("Schema", value: "v\(document.schemaVersion)")
        }
    }

    @ViewBuilder private func parameters(_ path: MovementPathDefinition) -> some View {
        Section("Parameters") {
            switch path {
            case let .straight(value):
                number("Speed (px/s)", straightBinding(\.speed, fallback: value.speed))
            case let .sine(value):
                number("Speed (px/s)", sineBinding(\.speed, fallback: value.speed))
                number("Amplitude (px)", sineBinding(\.amplitude, fallback: value.amplitude))
                number("Frequency (Hz)", sineBinding(\.frequency, fallback: value.frequency))
                number("Member phase (rad)", sineBinding(\.phaseOffset, fallback: value.phaseOffset))
            case let .waypoints(value):
                number("Duration (s)", waypointBinding(\.duration, fallback: value.duration))
                Toggle("Loop after completion", isOn: waypointLoopBinding)
                if value.loopToPoint != nil {
                    Picker("Loop to waypoint", selection: waypointLoopToBinding) {
                        ForEach(value.points.indices, id: \.self) { Text("Point \($0 + 1)").tag($0) }
                    }
                    Text("After the final point, the route travels back to this waypoint before repeating.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Segments", value: "\(max(0, value.points.count - 1))")
                Text("Segments currently share the duration equally.")
                    .font(.caption).foregroundStyle(.secondary)
            case let .bezier(value):
                number("Duration (s)", bezierBinding(\.duration, fallback: value.duration))
                Toggle("Loop after completion", isOn: bezierLoopBinding)
                if value.loopStart != nil {
                    number("Repeat from (s)", bezierLoopStartBinding(fallback: value.loopStart ?? 0))
                    Text("For a seamless loop, the curve endpoint should meet the curve at this time.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Drag start, end, and the two control handles on the canvas.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func waypoints(_ value: WaypointPath) -> some View {
        Section("Waypoints") {
            ForEach(Array(value.points.enumerated()), id: \.offset) { index, point in
                DisclosureGroup(isExpanded: pointExpanded(index)) {
                    number("X (normalized)", pointBinding(index, \.x, fallback: point.x))
                    number("Y (normalized)", pointBinding(index, \.y, fallback: point.y))
                    HStack {
                        Button("Move Up") { movePoint(index, by: -1) }.disabled(index == 0)
                        Button("Move Down") { movePoint(index, by: 1) }.disabled(index == value.points.count - 1)
                    }
                    Button("Remove Waypoint", role: .destructive) { removePoint(index) }
                        .disabled(value.points.count <= 2)
                } label: {
                    Text("Point \(index + 1)  (\(point.x.formatted()), \(point.y.formatted()))")
                }
            }
            Button("Add Waypoint", action: addPoint)
            Text("Values outside 0…1 are valid and place points off-screen.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func bezierControls(_ value: BezierPath) -> some View {
        Section("Bézier Controls") {
            bezierPoint("Start", index: 0, point: value.start)
            bezierPoint("Control 1", index: 1, point: value.control1)
            bezierPoint("Control 2", index: 2, point: value.control2)
            bezierPoint("End", index: 3, point: value.end)
            ForEach(Array(value.additionalSegments.enumerated()), id: \.offset) { index, segment in
                Text("Segment \(index + 2) — drag its controls directly on the canvas.")
                    .font(.caption).foregroundStyle(.secondary)
                bezierPoint("Segment \(index + 2) Control 1", index: 4 + index * 3, point: segment.control1)
                bezierPoint("Segment \(index + 2) Control 2", index: 5 + index * 3, point: segment.control2)
                bezierPoint("Segment \(index + 2) End", index: 6 + index * 3, point: segment.end)
            }
            Button("Add Curve Segment", action: addBezierSegment)
            if !value.additionalSegments.isEmpty {
                Button("Remove Last Segment", role: .destructive, action: removeBezierSegment)
            }
            Text("Coordinates are normalized; values beyond 0…1 place points off-screen.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func bezierPoint(_ label: String, index: Int, point: MovementPathPointDefinition) -> some View {
        DisclosureGroup(isExpanded: pointExpanded(index)) {
            number("X (normalized)", bezierPointBinding(index, \.x, fallback: point.x))
            number("Y (normalized)", bezierPointBinding(index, \.y, fallback: point.y))
        } label: {
            Text("\(label)  (\(point.x.formatted()), \(point.y.formatted()))")
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

    private func documentBinding<Value>(_ keyPath: WritableKeyPath<PathDocument, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { workspace.selectedPath?.definition[keyPath: keyPath] ?? fallback },
            set: { value in workspace.updateSelectedPath { $0[keyPath: keyPath] = value } }
        )
    }

    private var kindBinding: Binding<MovementPathKind> {
        Binding(
            get: { workspace.selectedPath?.definition.path.kind ?? .straight },
            set: { kind in
                workspace.selectedPathPointIndex = nil
                workspace.updateSelectedPath { $0.path = defaultPath(kind) }
            }
        )
    }

    private func pathBinding<Value, Payload>(
        _ extract: @escaping (MovementPathDefinition) -> Payload?,
        _ wrap: @escaping (Payload) -> MovementPathDefinition,
        _ keyPath: WritableKeyPath<Payload, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(get: {
            guard let path = workspace.selectedPath?.definition.path,
                  let payload = extract(path) else { return fallback }
            return payload[keyPath: keyPath]
        }, set: { newValue in
            workspace.updateSelectedPath { document in
                guard var payload = extract(document.path) else { return }
                payload[keyPath: keyPath] = newValue
                document.path = wrap(payload)
            }
        })
    }

    private func straightBinding<Value>(_ kp: WritableKeyPath<StraightPath, Value>, fallback: Value) -> Binding<Value> { pathBinding({ if case let .straight(v) = $0 { v } else { nil } }, MovementPathDefinition.straight, kp, fallback: fallback) }
    private func sineBinding<Value>(_ kp: WritableKeyPath<SinePath, Value>, fallback: Value) -> Binding<Value> { pathBinding({ if case let .sine(v) = $0 { v } else { nil } }, MovementPathDefinition.sine, kp, fallback: fallback) }
    private func waypointBinding<Value>(_ kp: WritableKeyPath<WaypointPath, Value>, fallback: Value) -> Binding<Value> { pathBinding({ if case let .waypoints(v) = $0 { v } else { nil } }, MovementPathDefinition.waypoints, kp, fallback: fallback) }
    private func bezierBinding<Value>(_ kp: WritableKeyPath<BezierPath, Value>, fallback: Value) -> Binding<Value> { pathBinding({ if case let .bezier(v) = $0 { v } else { nil } }, MovementPathDefinition.bezier, kp, fallback: fallback) }

    private var waypointLoopBinding: Binding<Bool> {
        Binding(get: {
            if case let .waypoints(value)? = workspace.selectedPath?.definition.path { value.loopToPoint != nil } else { false }
        }, set: { enabled in
            workspace.updateSelectedPath { document in
                guard case var .waypoints(value) = document.path else { return }
                value.loopToPoint = enabled ? (value.loopToPoint ?? 0) : nil
                document.path = .waypoints(value)
            }
        })
    }

    private var waypointLoopToBinding: Binding<Int> {
        Binding(get: {
            if case let .waypoints(value)? = workspace.selectedPath?.definition.path { value.loopToPoint ?? 0 } else { 0 }
        }, set: { index in
            workspace.updateSelectedPath { document in
                guard case var .waypoints(value) = document.path else { return }
                value.loopToPoint = index
                document.path = .waypoints(value)
            }
        })
    }

    private var bezierLoopBinding: Binding<Bool> {
        Binding(get: {
            if case let .bezier(value)? = workspace.selectedPath?.definition.path { value.loopStart != nil } else { false }
        }, set: { enabled in
            workspace.updateSelectedPath { document in
                guard case var .bezier(value) = document.path else { return }
                value.loopStart = enabled ? (value.loopStart ?? 0) : nil
                document.path = .bezier(value)
            }
        })
    }

    private func waypointLoopStartBinding(fallback: Double) -> Binding<Double> {
        Binding(get: {
            if case let .waypoints(value)? = workspace.selectedPath?.definition.path { value.loopStart ?? fallback } else { fallback }
        }, set: { newValue in
            workspace.updateSelectedPath { document in
                guard case var .waypoints(value) = document.path else { return }
                value.loopStart = newValue
                document.path = .waypoints(value)
            }
        })
    }

    private func bezierLoopStartBinding(fallback: Double) -> Binding<Double> {
        Binding(get: {
            if case let .bezier(value)? = workspace.selectedPath?.definition.path { value.loopStart ?? fallback } else { fallback }
        }, set: { newValue in
            workspace.updateSelectedPath { document in
                guard case var .bezier(value) = document.path else { return }
                value.loopStart = newValue
                document.path = .bezier(value)
            }
        })
    }

    private func pointExpanded(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { workspace.selectedPathPointIndex == index },
            set: { workspace.selectedPathPointIndex = $0 ? index : nil }
        )
    }

    private func pointBinding(_ index: Int, _ keyPath: WritableKeyPath<MovementPathPointDefinition, Double>, fallback: Double) -> Binding<Double> {
        Binding(get: {
            guard let path = workspace.selectedPath?.definition.path,
                  case let .waypoints(value) = path,
                  value.points.indices.contains(index) else { return fallback }
            return value.points[index][keyPath: keyPath]
        }, set: { newValue in
            mutatePoints { points in
                guard points.indices.contains(index) else { return }
                points[index][keyPath: keyPath] = newValue
            }
        })
    }

    private func bezierPointBinding(_ index: Int, _ keyPath: WritableKeyPath<MovementPathPointDefinition, Double>, fallback: Double) -> Binding<Double> {
        Binding(get: {
            guard let path = workspace.selectedPath?.definition.path,
                  case let .bezier(value) = path else { return fallback }
                switch index {
                case 0: return value.start[keyPath: keyPath]
                case 1: return value.control1[keyPath: keyPath]
                case 2: return value.control2[keyPath: keyPath]
                case 3: return value.end[keyPath: keyPath]
                default:
                    let segmentIndex = (index - 4) / 3
                    let controlIndex = (index - 4) % 3
                    guard value.additionalSegments.indices.contains(segmentIndex) else { return fallback }
                    switch controlIndex {
                    case 0: return value.additionalSegments[segmentIndex].control1[keyPath: keyPath]
                    case 1: return value.additionalSegments[segmentIndex].control2[keyPath: keyPath]
                    case 2: return value.additionalSegments[segmentIndex].end[keyPath: keyPath]
                    default: return fallback
                    }
            }
        }, set: { newValue in
            workspace.updateSelectedPath { document in
                guard case var .bezier(value) = document.path else { return }
                switch index {
                case 0: value.start[keyPath: keyPath] = newValue
                case 1: value.control1[keyPath: keyPath] = newValue
                case 2: value.control2[keyPath: keyPath] = newValue
                case 3: value.end[keyPath: keyPath] = newValue
                default:
                    let segmentIndex = (index - 4) / 3
                    let controlIndex = (index - 4) % 3
                    guard value.additionalSegments.indices.contains(segmentIndex) else { return }
                    switch controlIndex {
                    case 0: value.additionalSegments[segmentIndex].control1[keyPath: keyPath] = newValue
                    case 1: value.additionalSegments[segmentIndex].control2[keyPath: keyPath] = newValue
                    case 2: value.additionalSegments[segmentIndex].end[keyPath: keyPath] = newValue
                    default: return
                    }
                }
                document.path = .bezier(value)
            }
        })
    }

    private func addBezierSegment() {
        workspace.updateSelectedPath { document in
            guard case var .bezier(value) = document.path else { return }
            let previous = value.additionalSegments.last
            let start = previous?.end ?? value.end
            // New segments should be immediately editable. Aim their initial
            // handles back toward the playable area rather than extending an
            // exit tangent farther off-screen.
            let target = MovementPathPointDefinition(x: 0.5, y: 0.5)
            let deltaX = target.x - start.x
            let deltaY = target.y - start.y
            let length = max((deltaX * deltaX + deltaY * deltaY).squareRoot(), 0.001)
            let step = MovementPathPointDefinition(x: deltaX / length * 0.12, y: deltaY / length * 0.12)
            value.additionalSegments.append(.init(
                control1: .init(x: start.x + step.x, y: start.y + step.y),
                control2: .init(x: start.x + step.x * 2, y: start.y + step.y * 2),
                end: .init(x: start.x + step.x * 3, y: start.y + step.y * 3)
            ))
            document.path = .bezier(value)
        }
    }

    private func removeBezierSegment() {
        workspace.updateSelectedPath { document in
            guard case var .bezier(value) = document.path, !value.additionalSegments.isEmpty else { return }
            value.additionalSegments.removeLast()
            document.path = .bezier(value)
        }
    }

    private func addPoint() {
        mutatePoints { points in
            let newPoint: MovementPathPointDefinition
            if let last = points.last, points.count > 1 {
                let previous = points[points.count - 2]
                newPoint = .init(x: last.x + (last.x - previous.x), y: last.y + (last.y - previous.y))
            } else {
                newPoint = .init(x: 0.5, y: 0.5)
            }
            points.append(newPoint)
            workspace.selectedPathPointIndex = points.count - 1
        }
    }

    private func removePoint(_ index: Int) {
        mutatePoints { points in
            guard points.count > 2, points.indices.contains(index) else { return }
            points.remove(at: index)
        }
        workspace.selectedPathPointIndex = nil
    }

    private func movePoint(_ index: Int, by offset: Int) {
        mutatePoints { points in
            let destination = index + offset
            guard points.indices.contains(index), points.indices.contains(destination) else { return }
            points.swapAt(index, destination)
            workspace.selectedPathPointIndex = destination
        }
    }

    private func mutatePoints(_ change: (inout [MovementPathPointDefinition]) -> Void) {
        workspace.updateSelectedPath { document in
            guard case var .waypoints(value) = document.path else { return }
            change(&value.points)
            document.path = .waypoints(value)
        }
    }

    private func number(_ title: String, _ value: Binding<Double>) -> some View {
        TextField(title, value: value, format: .number.precision(.fractionLength(0...3)))
    }

    private func defaultPath(_ kind: MovementPathKind) -> MovementPathDefinition {
        switch kind {
        case .straight: .straight(.init(speed: 120))
        case .sine: .sine(.init(speed: 120, amplitude: 40, frequency: 0.5))
        case .waypoints: .waypoints(.init(duration: 6, points: [
            .init(x: 1.1, y: 0.5), .init(x: 0.65, y: 0.3), .init(x: -0.1, y: 0.5)
        ]))
        case .bezier: .bezier(.init(
            duration: 4,
            start: .init(x: 1.1, y: 0.5),
            control1: .init(x: 0.8, y: 0.05),
            control2: .init(x: 0.2, y: 0.95),
            end: .init(x: -0.1, y: 0.5)
        ))
        }
    }
}
