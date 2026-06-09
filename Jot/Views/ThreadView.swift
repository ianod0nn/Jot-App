//
//  ThreadView.swift
//  Jot
//
//  The "All thoughts" chat thread: user bubbles (task thoughts checkable inline),
//  saved-note confirmations, AI answers, and checkable list cards.
//

import SwiftUI

struct ThreadView: View {
    let messages: [ChatMessage]
    @ObservedObject var dataManager: DataManager

    var body: some View {
        VStack(spacing: 0) {
            ForEach(messages) { message in
                row(for: message)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 8, trailing: 16))
    }

    @ViewBuilder
    private func row(for message: ChatMessage) -> some View {
        switch message.messageType {
        case .savedNote:
            SavedNoteBubble(category: JotCategory(string: message.category) ?? .info)
        case .aiResponse:
            if let items = message.items, !items.isEmpty {
                ChecklistCard(message: message, dataManager: dataManager)
            } else {
                AnswerBubble(text: message.text)
            }
        case .userThought, .userQuery:
            UserBubble(message: message, dataManager: dataManager)
        }
    }
}

// MARK: - Check control

struct TaskCheckButton: View {
    var checked: Bool
    var overdue: Bool = false
    var size: CGFloat = 26
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if checked {
                    Circle().fill(JotTheme.accent)
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Circle()
                        .strokeBorder(overdue ? JotTheme.overdue : JotTheme.tertiary, lineWidth: 1.7)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}

struct DueChip: View {
    let due: DueInfo
    var completed: Bool

    private var color: Color {
        if completed { return JotTheme.tertiary }
        switch due.state {
        case .overdue: return JotTheme.overdue
        case .today: return JotTheme.accent
        case .upcoming: return JotTheme.secondary
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock").font(.system(size: 11, weight: .medium))
            Text(due.label).font(.system(size: 12.5, weight: .medium))
        }
        .foregroundColor(color)
    }
}

// MARK: - Bubbles

struct UserBubble: View {
    let message: ChatMessage
    @ObservedObject var dataManager: DataManager

    private var isTaskThought: Bool {
        message.category == "task" && message.taskState != nil && message.items == nil
    }

    var body: some View {
        if isTaskThought {
            HStack(alignment: .center, spacing: 10) {
                Spacer(minLength: 40)
                TaskCheckButton(checked: message.isCompletedTask) {
                    if message.isCompletedTask { dataManager.markAsTask(message.id) }
                    else { dataManager.markTaskComplete(message.id) }
                }
                bubble
            }
            .padding(.bottom, 14)
        } else {
            HStack {
                Spacer(minLength: 50)
                bubble
            }
            .padding(.bottom, 14)
        }
    }

    private var bubble: some View {
        HStack(spacing: 0) {
            if message.messageType == .userQuery {
                Text("?").fontWeight(.semibold).foregroundColor(.white.opacity(0.7))
                    .padding(.trailing, 6)
            }
            Text(message.text)
                .foregroundColor(.white)
        }
        .font(.system(size: 16))
        .tracking(-0.2)
        .lineSpacing(2)
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20,
                                   bottomTrailingRadius: 7, topTrailingRadius: 20)
                .fill(JotTheme.accent)
        )
        .opacity(message.isCompletedTask ? 0.55 : 1)
        .strikethrough(message.isCompletedTask, color: .white)
        .frame(maxWidth: 280, alignment: .trailing)
    }
}

struct SavedNoteBubble: View {
    let category: JotCategory
    var body: some View {
        HStack(spacing: 6) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14)).foregroundColor(JotTheme.accent)
            Text("Saved to").foregroundColor(JotTheme.secondary)
            HStack(spacing: 3) {
                Image(systemName: category.symbol).font(.system(size: 12, weight: .semibold))
                Text(category.singular)
            }
            .foregroundColor(JotTheme.ink)
        }
        .font(.system(size: 12.5, weight: .medium))
        .padding(.trailing, 4)
        .padding(.bottom, 16)
    }
}

struct AnswerBubble: View {
    let text: String

    private var rendered: AttributedString {
        (try? AttributedString(markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            sparkleAvatar
            Text(rendered)
                .font(.system(size: 16))
                .tracking(-0.2)
                .foregroundColor(JotTheme.ink)
                .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 20,
                                           bottomTrailingRadius: 20, topTrailingRadius: 20)
                        .fill(Color.white)
                        .overlay(UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 20,
                                           bottomTrailingRadius: 20, topTrailingRadius: 20)
                            .stroke(Color.black.opacity(0.05), lineWidth: 0.5))
                )
                .frame(maxWidth: 290, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 16)
    }
}

var sparkleAvatar: some View {
    Image(systemName: "sparkles")
        .font(.system(size: 16))
        .foregroundColor(JotTheme.accent)
        .frame(width: 28, height: 28)
        .background(Circle().fill(JotTheme.accent.opacity(0.12)))
}

// MARK: - Checklist card (task-list answers + shopping lists)

struct ChecklistCard: View {
    let message: ChatMessage
    @ObservedObject var dataManager: DataManager

    private func due(for item: ListItem) -> DueInfo? {
        guard message.listKind == .tasks else { return nil }
        let date = dataManager.messages.first(where: { $0.id == item.id })?.dueDate
        return dueInfo(for: date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            sparkleAvatar
            VStack(alignment: .leading, spacing: 8) {
                if let title = message.listTitle {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(JotTheme.secondary)
                        .padding(.leading, 2)
                }
                VStack(spacing: 0) {
                    let items = message.items ?? []
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 {
                            Rectangle().fill(JotTheme.separator).frame(height: 0.5)
                                .padding(.leading, 52)
                        }
                        ChecklistRow(item: item, due: due(for: item)) {
                            dataManager.toggleItem(messageId: message.id, itemId: item.id)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: JotTheme.radius).fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: JotTheme.radius)
                            .stroke(Color.black.opacity(0.05), lineWidth: 0.5))
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 16)
    }
}

struct ChecklistRow: View {
    let item: ListItem
    var due: DueInfo?
    var onToggle: () -> Void

    private var overdue: Bool { (due?.state == .overdue) && !item.isChecked }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 13) {
                TaskCheckButton(checked: item.isChecked, overdue: overdue, size: 23, action: onToggle)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.text)
                        .font(.system(size: 16))
                        .tracking(-0.2)
                        .foregroundColor(item.isChecked ? JotTheme.tertiary : JotTheme.ink)
                        .strikethrough(item.isChecked, color: JotTheme.tertiary)
                    if let due = due {
                        DueChip(due: due, completed: item.isChecked)
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
