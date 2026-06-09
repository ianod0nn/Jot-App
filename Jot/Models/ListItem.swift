//
//  ListItem.swift
//  Jot
//
//  A single checkable row inside a list-type capture (e.g. a grocery list).
//

import Foundation

struct ListItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var isChecked: Bool

    init(id: UUID = UUID(), text: String, isChecked: Bool = false) {
        self.id = id
        self.text = text
        self.isChecked = isChecked
    }
}
