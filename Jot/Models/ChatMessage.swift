//
//  ChatMessage.swift
//  Jot
//
//  Created by Ian O'Donnell on 8/8/25.
//

import Foundation

struct ChatMessage: Identifiable, Codable {
    let id = UUID()
    let text: String
    let timestamp: Date
    let isFromUser: Bool
    let messageType: MessageType
    var taskState: TaskState? // NEW: track if this is a task
    var category: String? = nil    // AI-assigned: "task" | "idea" | "info"
    var dueDate: Date? = nil       // AI-extracted due date, if any
    var listTitle: String? = nil   // title when this message is a checklist
    var items: [ListItem]? = nil   // checkable rows when this message is a list
    var listKind: ListKind? = nil  // how checking an item is persisted
    
    enum MessageType: String, Codable {
        case userThought = "thought"
        case userQuery = "query"
        case aiResponse = "response"
    }
    
    enum TaskState: String, Codable {
        case pending = "pending"
        case completed = "completed"
        case notATask = "not_a_task" // User said this isn't a task
    }

    enum ListKind: String, Codable {
        case shopping  // items map to captured-thought list items
        case tasks     // items map to pending task messages (by id)
    }
    
    var displayText: String {
        return text
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    // Helper properties
    var isTask: Bool {
        return taskState == .pending || taskState == .completed
    }
    
    var isPendingTask: Bool {
        return taskState == .pending
    }
    
    var isCompletedTask: Bool {
        return taskState == .completed
    }
}
