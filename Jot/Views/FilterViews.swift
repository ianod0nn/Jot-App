//
//  FilterViews.swift
//  Jot
//
//  Chat header, the single-select filter bar, and the per-filter bodies:
//  Tasks (checkable rows, overdue/completed handling) and the collapsible
//  Grouped view for Ideas / Reference.
//

import SwiftUI

// MARK: - Header

struct ChatHeader: View {
    let title: String
    var onBack: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(JotTheme.accent)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.3)
                .foregroundColor(JotTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.trailing, 40)
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .background(JotTheme.pageBG.opacity(0.92))
    }
}

// MARK: - Filter bar

struct FilterBar: View {
    var active: JotCategory?
    var counts: [JotCategory: Int]
    var onSelect: (JotCategory) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(JotCategory.allCases) { cat in
                chip(cat)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 10, trailing: 16))
        .background(JotTheme.pageBG.opacity(0.92))
        .overlay(Rectangle().fill(JotTheme.separator).frame(height: 0.5), alignment: .bottom)
    }

    private func chip(_ cat: JotCategory) -> some View {
        let on = active == cat
        return Button(action: { onSelect(cat) }) {
            HStack(spacing: 6) {
                Image(systemName: cat.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(on ? .white : JotTheme.secondary)
                Text(cat.label)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundColor(on ? .white : JotTheme.ink)
                Text("\(counts[cat] ?? 0)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(on ? .white.opacity(0.85) : JotTheme.tertiary)
            }
            .padding(EdgeInsets(top: 7, leading: 11, bottom: 7, trailing: 13))
            .background(
                Capsule()
                    .fill(on ? JotTheme.accent : Color.white)
                    .overlay(Capsule().stroke(on ? JotTheme.accent : Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.16), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tasks filter

struct TasksFilterView: View {
    let tasks: [ChatMessage]   // category == task, userThought, items == nil
    @ObservedObject var dataManager: DataManager

    private var open: [ChatMessage] {
        tasks.filter { !$0.isCompletedTask }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    private var done: [ChatMessage] {
        tasks.filter { $0.isCompletedTask }
            .sorted { ($0.dueDate ?? .distantPast) > ($1.dueDate ?? .distantPast) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if open.isEmpty && done.isEmpty {
                EmptyNote(label: "No tasks yet")
            }
            if !open.isEmpty { card(open) }
            if !done.isEmpty {
                Text("Completed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(JotTheme.secondary)
                    .padding(EdgeInsets(top: 20, leading: 6, bottom: 8, trailing: 6))
                card(done)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
    }

    private func card(_ rows: [ChatMessage]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, t in
                if idx > 0 {
                    Rectangle().fill(JotTheme.separator).frame(height: 0.5).padding(.leading, 52)
                }
                TaskFilterRow(task: t) {
                    if t.isCompletedTask { dataManager.markAsTask(t.id) }
                    else { dataManager.markTaskComplete(t.id) }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: JotTheme.radius).fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: JotTheme.radius)
                    .stroke(Color.black.opacity(0.05), lineWidth: 0.5))
        )
    }
}

struct TaskFilterRow: View {
    let task: ChatMessage
    var onToggle: () -> Void

    private var due: DueInfo? { dueInfo(for: task.dueDate) }
    private var overdue: Bool { (due?.state == .overdue) && !task.isCompletedTask }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 13) {
                TaskCheckButton(checked: task.isCompletedTask, overdue: overdue, size: 23, action: onToggle)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.text)
                        .font(.system(size: 16)).tracking(-0.2)
                        .foregroundColor(task.isCompletedTask ? JotTheme.tertiary : JotTheme.ink)
                        .strikethrough(task.isCompletedTask, color: JotTheme.tertiary)
                    if let due = due {
                        DueChip(due: due, completed: task.isCompletedTask)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Grouped filter (ideas + reference)

struct GroupedFilterView: View {
    let category: JotCategory
    let items: [CapturedThought]
    @Binding var collapsed: Set<String>

    private var groups: [(topic: String, items: [CapturedThought])] {
        var order: [String] = []
        var map: [String: [CapturedThought]] = [:]
        for it in items {
            let t = it.topic ?? "Other"
            if map[t] == nil { order.append(t) }
            map[t, default: []].append(it)
        }
        return order.sorted().map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if items.isEmpty {
                EmptyNote(label: "Nothing here yet")
            }
            ForEach(groups, id: \.topic) { group in
                let key = category.rawValue + ":" + group.topic
                CollapsibleGroup(
                    topic: group.topic, items: group.items,
                    isOpen: !collapsed.contains(key),
                    onToggle: {
                        if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
                    }
                )
            }
        }
        .padding(EdgeInsets(top: 6, leading: 16, bottom: 16, trailing: 16))
    }
}

struct CollapsibleGroup: View {
    let topic: String
    let items: [CapturedThought]
    var isOpen: Bool
    var onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(JotTheme.secondary)
                        .rotationEffect(.degrees(isOpen ? 0 : -90))
                    Text(topic)
                        .font(.system(size: 15, weight: .semibold)).tracking(-0.2)
                        .foregroundColor(JotTheme.ink)
                    Text("\(items.count)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(JotTheme.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(Capsule().fill(Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.08)))
                    Spacer(minLength: 0)
                }
                .padding(EdgeInsets(top: 10, leading: 6, bottom: 10, trailing: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, it in
                        if idx > 0 {
                            Rectangle().fill(JotTheme.separator).frame(height: 0.5).padding(.leading, 16)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(it.text)
                                .font(.system(size: 16)).tracking(-0.2)
                                .foregroundColor(JotTheme.ink)
                                .lineSpacing(2)
                            Spacer(minLength: 0)
                            Text(it.timeAgo)
                                .font(.system(size: 12))
                                .foregroundColor(JotTheme.tertiary)
                                .fixedSize()
                        }
                        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: JotTheme.radius).fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: JotTheme.radius)
                            .stroke(Color.black.opacity(0.05), lineWidth: 0.5))
                )
            }
        }
    }
}

struct EmptyNote: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 15))
            .foregroundColor(JotTheme.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }
}
