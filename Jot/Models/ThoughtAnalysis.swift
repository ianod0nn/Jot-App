//
//  ThoughtAnalysis.swift
//  Jot
//
//  Structured result of the single AI analysis call made at capture time.
//  Replaces the three competing keyword/LLM categorization systems.
//

import Foundation

struct ThoughtAnalysis: Codable {
    enum Category: String, Codable {
        case task
        case idea
        case info
    }

    let category: Category
    let isTask: Bool
    let cleanedText: String   // lightly normalized version of the input
    let dueDate: Date?        // resolved absolute date if a time was mentioned
    let priority: Int?        // 1–3, optional
    let tags: [String]
}
