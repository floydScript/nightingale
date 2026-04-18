//
//  Item.swift
//  Nightingale
//
//  Created by eason-air on 2026/4/18.
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
