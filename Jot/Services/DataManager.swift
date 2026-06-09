//
//  DataManager.swift
//  Jot
//
//  Created by Ian O'Donnell on 8/7/25.
//
import Foundation
import Combine

class DataManager: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var thoughts: [CapturedThought] = []
    
    private let userDefaults = UserDefaults.standard
    private let messagesKey = "chat_messages"
    private let thoughtsKey = "saved_thoughts"
    private let maxThoughts = 100
    
    init() {
        loadMessages()
        loadThoughts()
    }
    
    // MARK: - Message Management
    
    /// Adds a user message (optimistically). Returns the new message id and, for
    /// thoughts, the captured-thought id so the caller can apply AI analysis later.
    @discardableResult
    func addUserMessage(_ text: String, type: ChatMessage.MessageType = .userThought) -> (messageId: UUID, thoughtId: UUID?) {
        // Optimistic task guess via keyword heuristic; AI analysis corrects it later.
        let possibleTaskState: ChatMessage.TaskState? = (type == .userThought && looksLikeTask(text)) ? .pending : nil

        let message = ChatMessage(
            text: text,
            timestamp: Date(),
            isFromUser: true,
            messageType: type,
            taskState: possibleTaskState
        )
        messages.append(message)

        var thoughtId: UUID? = nil
        // Only add to thoughts if it's actual content (not queries)
        if type == .userThought {
            var thought = CapturedThought(
                text: text,
                timestamp: Date(),
                category: nil // Populated by AI analysis via applyAnalysis(...)
            )
            thought.messageId = message.id
            thoughtId = thought.id
            thoughts.append(thought)

            // Smart retention for thoughts
            if thoughts.count > maxThoughts {
                let importantThoughts = thoughts.filter { shouldKeepForever($0) }
                let regularThoughts = thoughts.filter { !shouldKeepForever($0) }

                let availableSlots = maxThoughts - importantThoughts.count
                let recentRegular = Array(regularThoughts.suffix(max(0, availableSlots)))

                thoughts = (importantThoughts + recentRegular).sorted { $0.timestamp < $1.timestamp }
            }
        }

        saveData()
        return (message.id, thoughtId)
    }

    /// Applies the AI analysis result to the message and its captured thought.
    /// This is the single source of truth for categorization — it overwrites the
    /// optimistic keyword guess unless the user has already acted on the task.
    func applyAnalysis(_ analysis: ThoughtAnalysis, toMessageId messageId: UUID, thoughtId: UUID?) {
        let listItems: [ListItem]? = (analysis.items?.isEmpty == false)
            ? analysis.items!.map { ListItem(text: $0) }
            : nil

        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            var updated = messages[index]
            updated.category = analysis.category.rawValue
            updated.dueDate = analysis.dueDate
            if let listItems = listItems {
                // A checklist replaces the single-task controls.
                updated.items = listItems
                updated.listTitle = analysis.listTitle ?? "List"
                updated.taskState = nil
            } else if updated.taskState != .completed && updated.taskState != .notATask {
                // Don't override an explicit user decision.
                updated.taskState = analysis.isTask ? .pending : nil
            }
            messages[index] = updated
        }

        if let thoughtId = thoughtId,
           let index = thoughts.firstIndex(where: { $0.id == thoughtId }) {
            thoughts[index].category = analysis.category.rawValue
            thoughts[index].dueDate = analysis.dueDate
            thoughts[index].items = listItems
        }

        saveData()
    }

    /// Toggles a checklist item. When every item is checked, the list is removed
    /// from the database (option B) and replaced with a brief confirmation.
    func toggleItem(messageId: UUID, itemId: UUID) {
        guard let mIdx = messages.firstIndex(where: { $0.id == messageId }),
              var items = messages[mIdx].items,
              let iIdx = items.firstIndex(where: { $0.id == itemId }) else { return }

        items[iIdx].isChecked.toggle()
        messages[mIdx].items = items

        // Keep the linked thought in sync (drives "what's left at the store?").
        if let tIdx = thoughts.firstIndex(where: { $0.messageId == messageId }) {
            thoughts[tIdx].items = items
        }

        if items.allSatisfy({ $0.isChecked }) {
            messages.removeAll { $0.id == messageId }
            thoughts.removeAll { $0.messageId == messageId }
            addAIResponse("✓ Got everything — list cleared") // persists via saveData
            return
        }

        saveData()
    }
    
    func addAIResponse(_ text: String) {
        let message = ChatMessage(
            text: text,
            timestamp: Date(),
            isFromUser: false,
            messageType: .aiResponse,
            taskState: nil
        )
        messages.append(message)
        saveData()
    }
    
    // MARK: - Task Management
    
    func markTaskComplete(_ messageId: UUID) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            var updatedMessage = messages[index]
            updatedMessage.taskState = .completed
            messages[index] = updatedMessage
            saveData()
        }
    }
    
    func markAsNotATask(_ messageId: UUID) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            var updatedMessage = messages[index]
            updatedMessage.taskState = .notATask
            messages[index] = updatedMessage
            saveData()
        }
    }
    
    func markAsTask(_ messageId: UUID) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            var updatedMessage = messages[index]
            updatedMessage.taskState = .pending
            messages[index] = updatedMessage
            saveData()
        }
    }
    
    // Get all pending tasks
    func getPendingTasks() -> [ChatMessage] {
        return messages.filter { $0.taskState == .pending }
    }
    
    // Get completed tasks (for reference)
    func getCompletedTasks() -> [ChatMessage] {
        return messages.filter { $0.taskState == .completed }
    }
    
    // Get task statistics
    func getTaskStats() -> (pending: Int, completed: Int, total: Int) {
        let pending = messages.filter { $0.taskState == .pending }.count
        let completed = messages.filter { $0.taskState == .completed }.count
        return (pending: pending, completed: completed, total: pending + completed)
    }
    
    // MARK: - Task Detection
    
    private func looksLikeTask(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        
        // Clear task indicators
        let taskKeywords = [
            "need to", "have to", "should", "must", "remind me",
            "don't forget", "remember to", "call", "email", "text",
            "buy", "get", "pick up", "book", "schedule", "respond to",
            "follow up", "check", "ask", "tell", "send"
        ]
        
        // Exclude obvious non-tasks
        let nonTaskKeywords = [
            "i already", "i did", "i called", "i sent", "i bought",
            "thinking about", "wondering", "what if", "maybe"
        ]
        
        let hasTaskKeyword = taskKeywords.contains { lowercased.contains($0) }
        let hasNonTaskKeyword = nonTaskKeywords.contains { lowercased.contains($0) }
        
        return hasTaskKeyword && !hasNonTaskKeyword
    }
    
    // MARK: - Smart Retention (from before)
    
    private func shouldKeepForever(_ thought: CapturedThought) -> Bool {
        let text = thought.text.lowercased()
        
        let permanentKeywords = [
            "code", "password", "number", "account", "login",
            "confirmation", "reference", "id", "license",
            "mariano's", "loyalty", "member", "phone",
            "address", "email", "serial", "pin"
        ]
        
        let hasImportantKeyword = permanentKeywords.contains { text.contains($0) }
        let isInfoCategory = thought.category == "info"
        let hasCodePattern = text.range(of: "\\b\\d{4,}\\b", options: .regularExpression) != nil ||
                            text.range(of: "\\b[A-Z]{2,}\\d{2,}\\b", options: .regularExpression) != nil
        
        return hasImportantKeyword || isInfoCategory || hasCodePattern
    }
    
    // MARK: - Storage Methods
    
    private func saveData() {
        saveMessages()
        saveThoughts()
    }
    
    private func loadMessages() {
        guard let data = userDefaults.data(forKey: messagesKey),
              let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            messages = []
            return
        }
        messages = decoded
    }
    
    private func saveMessages() {
        guard let encoded = try? JSONEncoder().encode(messages) else { return }
        userDefaults.set(encoded, forKey: messagesKey)
    }
    
    private func loadThoughts() {
        guard let data = userDefaults.data(forKey: thoughtsKey),
              let decoded = try? JSONDecoder().decode([CapturedThought].self, from: data) else {
            thoughts = []
            return
        }
        thoughts = decoded
    }
    
    private func saveThoughts() {
        guard let encoded = try? JSONEncoder().encode(thoughts) else { return }
        userDefaults.set(encoded, forKey: thoughtsKey)
    }
    
    // MARK: - Utility Methods
    
    func clearAllData() {
        messages.removeAll()
        thoughts.removeAll()
        userDefaults.removeObject(forKey: messagesKey)
        userDefaults.removeObject(forKey: thoughtsKey)
    }
    
    func exportData() -> String {
        let thoughtsData = thoughts.map { "[\($0.timestamp)] \($0.text)" }.joined(separator: "\n")
        return thoughtsData
    }
}
