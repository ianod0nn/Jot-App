//
//  ChatBubbleView.swift
//  Jot
//
//  Created by Ian O'Donnell on 8/8/25.
//


import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    @ObservedObject var dataManager: DataManager
    
    var body: some View {
        if let items = message.items, !items.isEmpty {
            HStack {
                ChecklistBubbleView(title: message.listTitle ?? "List", items: items) { itemId in
                    dataManager.toggleItem(messageId: message.id, itemId: itemId)
                }
                Spacer(minLength: 20)
            }
        } else {
            standardBubble
        }
    }

    private var standardBubble: some View {
        VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 8) {
            // Main message bubble
            HStack {
                if message.isFromUser {
                    Spacer(minLength: 50)
                    messageContent
                } else {
                    messageContent
                    Spacer(minLength: 50)
                }
            }

            // Timestamp and status
            HStack {
                if !message.isFromUser { Spacer() }
                
                HStack(spacing: 4) {
                    // Task status indicator
                    if let taskState = message.taskState {
                        taskStatusIcon(taskState)
                    }
                    
                    // Message type indicator
                    if message.messageType == .userQuery {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    Text(message.timeAgo)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                if message.isFromUser { Spacer() }
            }
        }
    }
    
    @ViewBuilder
    private var messageContent: some View {
        bubbleText
            .padding(12)
            .background(backgroundColor)
            .foregroundColor(textColor)
            .cornerRadius(16)
            .strikethrough(message.isCompletedTask, color: textColor)
            .opacity(message.isCompletedTask ? 0.7 : 1.0)
    }

    // AI responses are rendered as Markdown so lists/bold display properly.
    // User messages stay verbatim.
    private var bubbleText: Text {
        if !message.isFromUser,
           let attributed = try? AttributedString(
               markdown: message.text,
               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
           ) {
            return Text(attributed)
        }
        return Text(message.text)
    }
    
    @ViewBuilder
    private func taskStatusIcon(_ state: ChatMessage.TaskState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .foregroundColor(.orange)
                .font(.caption)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        case .notATask:
            Image(systemName: "note.text")
                .foregroundColor(.gray)
                .font(.caption)
        }
    }
    
    private var backgroundColor: Color {
        if message.isFromUser {
            return .blue
        } else {
            return Color(.systemGray5)
        }
    }
    
    private var textColor: Color {
        if message.isFromUser {
            return .white
        } else {
            return .primary
        }
    }
}
