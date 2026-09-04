//
//  Item.swift
//  bugpocalypseEditor
//
//  Created by Jordi Puigdellívol on 04/09/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
