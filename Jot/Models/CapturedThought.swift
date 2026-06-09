//
//  CapturedThought.swift
//  Jot
//
//  Created by Ian O'Donnell on 8/7/25.
//
import Foundation

struct CapturedThought: Identifiable, Codable {
    let id = UUID()
    let text: String
    let timestamp: Date
    var category: String?      // AI-assigned: "task" | "idea" | "info"
    var isCompleted: Bool = false
    var messageId: UUID? = nil   // links back to the originating ChatMessage
    var dueDate: Date? = nil     // AI-extracted due date, if any
    var items: [ListItem]? = nil // checkable rows when this thought is a list
    var topic: String? = nil     // AI grouping label for ideas/reference
    
    // For easy display in UI
    var displayText: String {
        if let category = category {
            return "[\(category)] \(text)"
        }
        return text
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

