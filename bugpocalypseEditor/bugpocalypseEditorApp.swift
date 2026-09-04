//
//  bugpocalypseEditorApp.swift
//  bugpocalypseEditor
//
//  Created by Jordi Puigdellívol on 04/09/2026.
//

import SwiftUI

@main
struct bugpocalypseEditorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .saveWorld, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let saveWorld = Notification.Name("BugpocalypseEditor.saveWorld")
}
