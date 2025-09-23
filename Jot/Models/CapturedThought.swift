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
    let category: String? // "TASK", "IDEA", "INFO"
    var isCompleted: Bool = false
    
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

