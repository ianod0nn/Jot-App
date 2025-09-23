//
//  ChatView.swift
//  Jot
//
//  Created by Ian O'Donnell on 8/8/25.
//


import SwiftUI

enum QueryType {
    case informationRetrieval  // "What's my Mariano's number?"
    case taskQuery            // "What do I need to do?"
    case shoppingQuery        // "What do I need at the store?"
    case generalQuery         // Everything else
}

enum ThoughtType {
    case task, idea, referenceInfo, simpleNote, reminder
}

struct ChatView: View {
    @StateObject private var dataManager = DataManager()
    @StateObject private var speechManager = SpeechManager()
    @StateObject private var aiManager = AIManager()
    
    @State private var messageText = ""
    @State private var isRecording = false
    @State private var showingVoiceInput = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Chat Messages
                ScrollViewReader { proxy in
                    // In ChatView, update the ScrollView section:
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(dataManager.messages) { message in
                                ChatBubbleView(message: message, dataManager: dataManager) // Pass dataManager
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: dataManager.messages.count) { _ in
                        // Auto-scroll to bottom when new message arrives
                        if let lastMessage = dataManager.messages.last {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Input Area
                VStack(spacing: 12) {
                    // Voice Recording Indicator
                    if speechManager.isRecording {
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundColor(.red)
                            Text("Recording... Tap to stop")
                                .font(.caption)
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                    
                    // Message Input
                    HStack(spacing: 12) {
                        // Voice Button
                        Button(action: toggleVoiceRecording) {
                            Image(systemName: speechManager.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(speechManager.isRecording ? .red : .blue)
                        }
                        .disabled(!speechManager.isAuthorized)
                        
                        // Text Input
                        TextField("Type a thought or ask a question...", text: $messageText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit {
                                sendMessage()
                            }
                        
                        // Send Button
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(messageText.isEmpty ? .gray : .blue)
                        }
                        .disabled(messageText.isEmpty)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                }
            }
            .navigationTitle("QuickCapture")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                speechManager.requestPermissions()
            }
        }
    }
    
    // MARK: - Voice Recording
    private func toggleVoiceRecording() {
        if speechManager.isRecording {
            speechManager.stopRecording()
            // Use transcribed text as message
            if !speechManager.transcribedText.isEmpty {
                messageText = speechManager.transcribedText
            }
        } else {
            speechManager.reset()
            speechManager.startRecording()
        }
    }
    
    // MARK: - Send Message
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Determine if this is a query or a thought
        let messageType: ChatMessage.MessageType = isQuery(trimmedText) ? .userQuery : .userThought
        
        // Add user message to chat
        dataManager.addUserMessage(trimmedText, type: messageType)
        
        // Clear input
        messageText = ""
        speechManager.reset()
        
        // Process based on type
        if messageType == .userQuery {
            handleQuery(trimmedText)
        } else {
            handleThought(trimmedText)
        }
    }
    
    private func isQuery(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        
        // Explicit query patterns
        let queryPatterns = [
            "what do i need", "what should i", "what's my", "what is my",
            "where is", "when is", "how do i", "show me", "find",
            "what was", "what were", "remind me about", "tell me about"
        ]
        
        // Question words at start
        let questionStarters = ["what", "where", "when", "how", "why", "who", "which"]
        let startsWithQuestion = questionStarters.contains { lowercased.hasPrefix($0 + " ") }
        
        // Ends with question mark
        let endsWithQuestion = text.hasSuffix("?")
        
        // Explicit patterns match
        let hasQueryPattern = queryPatterns.contains { lowercased.contains($0) }
        
        return startsWithQuestion || endsWithQuestion || hasQueryPattern
    }
    
    private func classifyQuery(_ query: String) -> QueryType {
        let lowercased = query.lowercased()
        
        // Information retrieval (codes, numbers, references)
        if lowercased.contains("number") || lowercased.contains("code") ||
           lowercased.contains("what's my") || lowercased.contains("what is my") {
            return .informationRetrieval
        }
        
        // Task/todo queries
        if lowercased.contains("need to do") || lowercased.contains("should i") ||
           lowercased.contains("remind me") || lowercased.contains("tasks") {
            return .taskQuery
        }
        
        // Shopping/grocery specific
        if lowercased.contains("store") || lowercased.contains("grocery") ||
           lowercased.contains("buy") || lowercased.contains("shop") {
            return .shoppingQuery
        }
        
        // Default to general
        return .generalQuery
    }

    private func classifyThought(_ text: String) -> ThoughtType {
        let lowercased = text.lowercased()
        
        if lowercased.contains("code") || lowercased.contains("number") ||
           lowercased.contains("password") || lowercased.contains("account") {
            return .referenceInfo
        }
        
        if lowercased.contains("need to") || lowercased.contains("should") ||
           lowercased.contains("remind") || lowercased.contains("call") {
            return .task
        }
        
        if lowercased.contains("idea") || lowercased.contains("what if") ||
           lowercased.contains("maybe") || lowercased.contains("thinking") {
            return .idea
        }
        
        return .simpleNote
    }
    
    private func handleThought(_ text: String) {
        // Determine thought type before sending to AI
        let thoughtType = classifyThought(text)
        
        // For simple thoughts, just acknowledge without AI response
        if thoughtType == .simpleNote || thoughtType == .reminder {
            // Show brief acknowledgment
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dataManager.addAIResponse("✓ Saved")
            }
        }
        
        // Still categorize with AI for context, but don't always respond
        Task {
            let categorizedText = await aiManager.categorizeThought(text)
            // Update the thought with category if needed
        }
    }
    
    private func handleQuery(_ text: String) {
        let queryType = classifyQuery(text)
        
        Task {
            // Pass pending tasks to AIManager for task queries
            let pendingTasks = queryType == .taskQuery ? dataManager.getPendingTasks() : []
            
            let response = await aiManager.queryThoughts(
                text,
                thoughts: dataManager.thoughts,
                queryType: queryType,
                pendingTasks: pendingTasks
            )
            
            DispatchQueue.main.async {
                dataManager.addAIResponse(response)
            }
        }
    }
}
