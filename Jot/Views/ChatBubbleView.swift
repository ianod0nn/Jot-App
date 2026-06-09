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
            
            // Task controls for user messages
            if message.isFromUser && shouldShowTaskControls(for: message) {
                taskControlButtons
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
    private var taskControlButtons: some View {
        HStack(spacing: 12) {
            if message.taskState == .pending {
                // Task is pending - show completion options
                Button(action: { dataManager.markTaskComplete(message.id) }) {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                Button(action: { dataManager.markAsNotATask(message.id) }) {
                    Label("Not a Task", systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
            } else if message.taskState == .notATask {
                // Marked as not a task - show option to make it a task
                Button(action: { dataManager.markAsTask(message.id) }) {
                    Label("Make Task", systemImage: "plus.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
            } else if message.taskState == .completed {
                // Task completed - show option to undo
                Button(action: { dataManager.markAsTask(message.id) }) {
                    Label("Undo", systemImage: "arrow.uturn.backward.circle")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.trailing, message.isFromUser ? 16 : 0)
        .padding(.leading, message.isFromUser ? 0 : 16)
    }
    
    private func shouldShowTaskControls(for message: ChatMessage) -> Bool {
        // Show controls if it has a task state or if it looks like it could be a task
        return message.taskState != nil || message.messageType == .userThought
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
