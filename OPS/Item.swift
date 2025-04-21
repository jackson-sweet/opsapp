//
//  Item.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
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
