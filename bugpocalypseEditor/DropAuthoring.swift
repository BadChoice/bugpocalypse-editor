import BugpocalypseContent

/// Content-only operations for deterministic formation drops. Keeping these
/// independent of SwiftUI makes assignment and validation testable.
enum DropAuthoring {
    struct Diagnostic: Equatable {
        let memberIndex: Int
        let message: String
    }

    static func drop(for memberIndex: Int, in drops: [DropDefinition]?) -> DropDefinition? {
        drops?.first { $0.memberIndex == memberIndex }
    }

    static func addingDefaultDrop(to memberIndex: Int, in drops: [DropDefinition]?) -> [DropDefinition]? {
        guard drop(for: memberIndex, in: drops) == nil else { return drops }
        return ((drops ?? []) + [.init(kind: .overdrive, amount: 1, memberIndex: memberIndex)])
            .sorted { $0.memberIndex < $1.memberIndex }
    }

    static func removingDrop(for memberIndex: Int, in drops: [DropDefinition]?) -> [DropDefinition]? {
        let remaining = (drops ?? []).filter { $0.memberIndex != memberIndex }
        return remaining.isEmpty ? nil : remaining
    }

    static func updatingDrop(_ replacement: DropDefinition, in drops: [DropDefinition]?) -> [DropDefinition]? {
        guard let drops, let index = drops.firstIndex(where: { $0.memberIndex == replacement.memberIndex }) else { return drops }
        var updated = drops
        updated[index] = replacement
        return updated.sorted { $0.memberIndex < $1.memberIndex }
    }

    static func diagnostics(for drops: [DropDefinition]?, memberCount: Int) -> [Diagnostic] {
        var seen = Set<Int>()
        return (drops ?? []).compactMap { drop in
            let isDuplicate = !seen.insert(drop.memberIndex).inserted
            if drop.amount <= 0 {
                return .init(memberIndex: drop.memberIndex, message: "Drop for member \(drop.memberIndex) must have a positive whole-number amount.")
            }
            guard (0..<memberCount).contains(drop.memberIndex) else {
                return .init(memberIndex: drop.memberIndex, message: "Drop targets member \(drop.memberIndex), but this formation has \(memberCount) member\(memberCount == 1 ? "" : "s").")
            }
            guard !isDuplicate else {
                return .init(memberIndex: drop.memberIndex, message: "Member \(drop.memberIndex) has more than one drop.")
            }
            return nil
        }
    }
}
