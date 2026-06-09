//
//  JotTheme.swift
//  Jot
//
//  Design tokens, category metadata, and the wordmark for the redesign.
//

import SwiftUI

enum JotTheme {
    static let accent = Color(hex: 0x2C5CC5)
    static let pageBG = Color(hex: 0xF2F2F7)
    static let fieldBG = Color.white
    static let ink = Color(hex: 0x1C1C1E)
    static let secondary = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.6)
    static let tertiary = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.3)
    static let separator = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.13)
    static let overdue = Color(hex: 0xE5484D)

    static let radius: CGFloat = 16
}

/// The three categories the app sorts thoughts into. Differ by icon + label only.
enum JotCategory: String, CaseIterable, Identifiable {
    case task, idea, info
    var id: String { rawValue }

    init?(string: String?) {
        guard let s = string, let c = JotCategory(rawValue: s) else { return nil }
        self = c
    }

    var label: String {
        switch self {
        case .task: return "Tasks"
        case .idea: return "Ideas"
        case .info: return "Reference"
        }
    }

    var singular: String {
        switch self {
        case .task: return "Task"
        case .idea: return "Idea"
        case .info: return "Reference"
        }
    }

    var symbol: String {
        switch self {
        case .task: return "checkmark.circle"
        case .idea: return "lightbulb"
        case .info: return "bookmark"
        }
    }
}

/// The hand-feel lowercase "jot" wordmark, set in the system serif.
struct JotWordmark: View {
    var size: CGFloat = 46
    var color: Color = JotTheme.ink
    var body: some View {
        Text("jot")
            .font(.system(size: size, weight: .bold, design: .serif))
            .tracking(-1.5)
            .foregroundColor(color)
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Relative due-date label + urgency state, mirroring the prototype's dueLabel().
struct DueInfo {
    enum State { case overdue, today, upcoming }
    let label: String
    let state: State
}

func dueInfo(for date: Date?) -> DueInfo? {
    guard let date = date else { return nil }
    let cal = Calendar.current
    let now = Date()
    if cal.isDateInToday(date) { return DueInfo(label: "Today", state: .today) }
    let startToday = cal.startOfDay(for: now)
    let startDue = cal.startOfDay(for: date)
    let days = cal.dateComponents([.day], from: startToday, to: startDue).day ?? 0
    if days < 0 {
        let d = -days
        return DueInfo(label: d <= 1 ? "Yesterday" : "\(d)d overdue", state: .overdue)
    } else if days == 1 {
        return DueInfo(label: "Tomorrow", state: .upcoming)
    } else if days < 7 {
        return DueInfo(label: "In \(days) days", state: .upcoming)
    } else {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return DueInfo(label: f.string(from: date), state: .upcoming)
    }
}
