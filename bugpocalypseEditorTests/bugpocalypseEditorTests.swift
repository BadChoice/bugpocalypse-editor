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
