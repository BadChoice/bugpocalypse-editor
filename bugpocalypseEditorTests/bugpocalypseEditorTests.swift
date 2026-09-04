//
//  bugpocalypseEditorTests.swift
//  bugpocalypseEditorTests
//
//  Created by Jordi Puigdellívol on 04/09/2026.
//

import BugpocalypseContent
import Foundation
import Testing
@testable import bugpocalypseEditor

struct bugpocalypseEditorTests {
    @MainActor
    @Test func loadsAndEditsAWorldCheckout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("godot/assets/worlds", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("BugpocalypseSwift", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: root.appendingPathComponent("godot/project.godot"))
        try Data().write(to: root.appendingPathComponent("BugpocalypseSwift/Package.swift"))
        try Data(worldJSON.utf8).write(to: root.appendingPathComponent("godot/assets/worlds/Test.json"))

        let workspace = EditorWorkspace()
        workspace.openProject(at: root)

        #expect(workspace.worlds.count == 1)
        #expect(workspace.selectedWorld?.definition.displayName == "Test World")
        #expect(workspace.diagnostics.isEmpty)

        workspace.addCell()
        #expect(workspace.selectedWorld?.definition.cells.count == 2)
        #expect(workspace.selectedWorld?.isDirty == true)
    }

    @MainActor
    @Test func addCellNextToSelectedCell() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("godot/assets/worlds", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("BugpocalypseSwift", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: root.appendingPathComponent("godot/project.godot"))
        try Data().write(to: root.appendingPathComponent("BugpocalypseSwift/Package.swift"))
        try Data(worldJSON.utf8).write(to: root.appendingPathComponent("godot/assets/worlds/Test.json"))

        let workspace = EditorWorkspace()
        workspace.openProject(at: root)

        // Select the initial "start" cell located at (0, 0)
        workspace.selectedCellID = "start"
        guard let startCell = workspace.selectedCell else {
            Issue.record("Start cell not found")
            return
        }

        // Add a new cell; since "start" is selected, it should pick an available neighbour of (0, 0)
        workspace.addCell()
        #expect(workspace.selectedWorld?.definition.cells.count == 2)
        guard let addedCell1 = workspace.selectedCell else {
            Issue.record("Added cell not selected")
            return
        }
        #expect(startCell.coordinate.neighbours.contains(addedCell1.coordinate))

        // Since addedCell1 is now selected, adding another cell should pick an available neighbour of addedCell1
        let addedCell1Coordinate = addedCell1.coordinate
        workspace.addCell()
        #expect(workspace.selectedWorld?.definition.cells.count == 3)
        guard let addedCell2 = workspace.selectedCell else {
            Issue.record("Second added cell not selected")
            return
        }
        #expect(addedCell1Coordinate.neighbours.contains(addedCell2.coordinate))
    }

    @MainActor
    @Test func addCellFallbackWhenNeighboursOccupied() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("godot/assets/worlds", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("BugpocalypseSwift", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: root.appendingPathComponent("godot/project.godot"))
        try Data().write(to: root.appendingPathComponent("BugpocalypseSwift/Package.swift"))
        try Data(worldJSON.utf8).write(to: root.appendingPathComponent("godot/assets/worlds/Test.json"))

        let workspace = EditorWorkspace()
        workspace.openProject(at: root)

        // Select "start" at (0, 0)
        workspace.selectedCellID = "start"

        // Occupy all neighbours of "start"
        let startNeighbours = workspace.selectedCell!.coordinate.neighbours
        for (index, neighbourCoord) in startNeighbours.enumerated() {
            let cell = WorldCellDefinition(
                id: "occupier_\(index)", coordinate: neighbourCoord, tileName: "world/road.png",
                kind: .exploration, displayName: "Occupier", isInitiallyRevealed: false,
                scoutEnergyCost: 1, neighbourIDs: []
            )
            workspace.updateSelectedWorld { world in
                world.cells.append(cell)
            }
        }

        // Re-select "start" whose neighbours are now all occupied
        workspace.selectedCellID = "start"
        workspace.addCell()

        // New cell should be placed using the fallback logic (starting at (0,0) incrementing x)
        guard let fallbackCell = workspace.selectedCell else {
            Issue.record("Fallback cell not selected")
            return
        }
        #expect(!startNeighbours.contains(fallbackCell.coordinate))
    }

    private var worldJSON: String {
        """
        {
          "schemaVersion": 1,
          "id": "test_world",
          "displayName": "Test World",
          "initialScoutEnergy": 3,
          "cells": [{
            "id": "start",
            "coordinate": [0, 0],
            "tileName": "world/road.png",
            "kind": "exploration",
            "displayName": "Start",
            "isInitiallyRevealed": true,
            "scoutEnergyCost": 0,
            "neighbourIDs": []
          }]
        }
        """
    }
}
