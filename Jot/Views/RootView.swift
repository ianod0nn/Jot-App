//
//  RootView.swift
//  Jot
//
//  App shell: owns the managers and the home ↔ chat navigation, the capture/
//  query routing, and the filtered chat body.
//

import SwiftUI

struct RootView: View {
    @StateObject private var dataManager = DataManager()
    @StateObject private var speechManager = SpeechManager()
    @StateObject private var aiManager = AIManager()

    private enum Screen { case home, chat }
    @State private var screen: Screen = .home
    @State private var filter: JotCategory? = nil
    @State private var draft = ""
    @State private var collapsed: Set<String> = []

    // MARK: Derived data

    // Plain to-do tasks: captures the AI flagged as actionable (taskState set).
    private var taskMessages: [ChatMessage] {
        dataManager.messages.filter { $0.messageType == .userThought && $0.taskState != nil }
    }
    // List captures filed under task (e.g. a grocery list) — rendered as checklists.
    private var taskListThoughts: [CapturedThought] {
        dataManager.thoughts.filter { $0.category == "task" && ($0.items?.isEmpty == false) }
    }
    private var counts: [JotCategory: Int] {
        [
            .task: taskMessages.count + taskListThoughts.count,
            .idea: dataManager.thoughts.filter { $0.category == "idea" }.count,
            .info: dataManager.thoughts.filter { $0.category == "info" }.count,
        ]
    }

    var body: some View {
        Group {
            if screen == .home {
                HomeView(
                    draft: $draft,
                    savedCount: dataManager.thoughts.count,
                    isRecording: speechManager.isRecording,
                    onSend: handleSend,
                    onMic: toggleVoice,
                    onSeeSaved: { filter = nil; screen = .chat }
                )
            } else {
                chatScreen
            }
        }
        .onAppear { speechManager.requestPermissions() }
    }

    // MARK: Chat screen

    private var chatScreen: some View {
        VStack(spacing: 0) {
            ChatHeader(title: filter?.label ?? "All thoughts") { screen = .home }
            FilterBar(active: filter, counts: counts) { cat in
                filter = (filter == cat ? nil : cat)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    chatBody
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: dataManager.messages.count) { _ in
                    scrollToBottom(proxy)
                }
                .onAppear { scrollToBottom(proxy) }
                .onChange(of: filter) { _ in if filter == nil { scrollToBottom(proxy) } }
            }

            JotComposer(text: $draft, placeholder: "Type a thought or ask a question…",
                        onMic: toggleVoice, isRecording: speechManager.isRecording, onSend: handleSend)
                .padding(EdgeInsets(top: 8, leading: 14, bottom: 10, trailing: 14))
                .background(JotTheme.pageBG.opacity(0.94)
                    .overlay(Rectangle().fill(JotTheme.separator).frame(height: 0.5), alignment: .top))
        }
        .background(JotTheme.pageBG.ignoresSafeArea())
    }

    @ViewBuilder
    private var chatBody: some View {
        switch filter {
        case .task:
            TasksFilterView(tasks: taskMessages, lists: taskListThoughts, dataManager: dataManager)
        case .idea:
            GroupedFilterView(category: .idea,
                              items: dataManager.thoughts.filter { $0.category == "idea" },
                              collapsed: $collapsed)
        case .info:
            GroupedFilterView(category: .info,
                              items: dataManager.thoughts.filter { $0.category == "info" },
                              collapsed: $collapsed)
        case nil:
            ThreadView(messages: dataManager.messages, dataManager: dataManager)
                .id("thread")
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard filter == nil, let last = dataManager.messages.last else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    // MARK: Capture / query routing

    private func handleSend() {
        let v = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        screen = .chat
        filter = nil
        draft = ""
        speechManager.reset()

        let isQ = isQuery(v)
        let ids = dataManager.addUserMessage(v, type: isQ ? .userQuery : .userThought)
        if isQ { handleQuery(v) }
        else { handleThought(v, messageId: ids.messageId, thoughtId: ids.thoughtId) }
    }

    private func handleThought(_ text: String, messageId: UUID, thoughtId: UUID?) {
        Task {
            let analysis = await aiManager.analyzeThought(text)
            await MainActor.run {
                guard let analysis = analysis else {
                    let isTask = dataManager.messages.first(where: { $0.id == messageId })?.taskState != nil
                    dataManager.addSavedNote(category: isTask ? "task" : "info")
                    return
                }
                if analysis.isCompletion, let done = analysis.completedItems, !done.isEmpty {
                    // Don't save the statement — check matching items off existing lists/tasks.
                    if let thoughtId = thoughtId { dataManager.removeThought(thoughtId) }
                    let checked = dataManager.completeItems(matching: done)
                    dataManager.addAIResponse(checked.isEmpty
                        ? "Got it — nothing matching found on your lists."
                        : "✓ Checked off: " + checked.joined(separator: ", "))
                } else {
                    dataManager.applyAnalysis(analysis, toMessageId: messageId, thoughtId: thoughtId)
                    dataManager.addSavedNote(category: analysis.category.rawValue)
                }
            }
        }
    }

    private func handleQuery(_ text: String) {
        let qt = classifyQuery(text)
        if qt == .shoppingQuery { dataManager.addShoppingListResponse(); return }
        if qt == .taskQuery { dataManager.addTaskListResponse(); return }
        Task {
            let resp = await aiManager.queryThoughts(text, thoughts: dataManager.thoughts, queryType: qt)
            await MainActor.run { dataManager.addAIResponse(resp) }
        }
    }

    private func toggleVoice() {
        if speechManager.isRecording {
            speechManager.stopRecording()
            if !speechManager.transcribedText.isEmpty { draft = speechManager.transcribedText }
        } else {
            speechManager.reset()
            speechManager.startRecording()
        }
    }

    // MARK: Classification (ported from the old ChatView)

    private func isQuery(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let queryPatterns = [
            "what do i need", "what should i", "what's my", "what is my",
            "where is", "when is", "how do i", "show me", "find",
            "what was", "what were", "remind me about", "tell me about"
        ]
        let questionStarters = ["what", "where", "when", "how", "why", "who", "which"]
        let startsWithQuestion = questionStarters.contains { lowercased.hasPrefix($0 + " ") }
        let endsWithQuestion = text.hasSuffix("?")
        let hasQueryPattern = queryPatterns.contains { lowercased.contains($0) }
        return startsWithQuestion || endsWithQuestion || hasQueryPattern
    }

    private func classifyQuery(_ query: String) -> QueryType {
        let lowercased = query.lowercased()
        if lowercased.contains("number") || lowercased.contains("code") ||
           lowercased.contains("what's my") || lowercased.contains("what is my") {
            return .informationRetrieval
        }
        if lowercased.contains("store") || lowercased.contains("grocery") ||
           lowercased.contains("buy") || lowercased.contains("shop") {
            return .shoppingQuery
        }
        if lowercased.contains("need to do") || lowercased.contains("should i") ||
           lowercased.contains("remind me") || lowercased.contains("task") ||
           lowercased.contains("to do") || lowercased.contains("to-do") ||
           lowercased.contains("todo") {
            return .taskQuery
        }
        return .generalQuery
    }
}
