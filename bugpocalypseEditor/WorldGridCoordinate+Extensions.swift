import BugpocalypseContent

extension WorldGridCoordinate {
    /// Returns the four orthogonal grid neighbours of this coordinate.
    var neighbours: [WorldGridCoordinate] {
        [
            WorldGridCoordinate(x: x + 1, y: y),
            WorldGridCoordinate(x: x - 1, y: y),
            WorldGridCoordinate(x: x, y: y + 1),
            WorldGridCoordinate(x: x, y: y - 1)
        ]
    }
}
