//
//  AIManager.swift
//  Jot
//
//  Created by Ian O'Donnell on 8/7/25.
//
import Foundation
import Combine

func getAPIKey() -> String {
    guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
          let config = NSDictionary(contentsOfFile: path),
          let apiKey = config["AnthropicAPIKey"] as? String else {
        return ""
    }
    return apiKey
}

class AIManager: ObservableObject {
    @Published var isProcessing = false
    @Published var errorMessage = ""

    private let apiKey = getAPIKey()
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-haiku-4-5"
    private let anthropicVersion = "2023-06-01"

    // Lenient ISO-8601 decoder: accepts timestamps with or without fractional seconds.
    private static let analysisDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: string) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date format: \(string)"
            )
        }
        return decoder
    }()

    // MARK: - Capture-time analysis (single source of truth)

    /// Analyzes a captured thought in one structured call: category, task-ness,
    /// an optional due date, priority, and tags. Returns nil on transport/parse
    /// failure so the caller can fall back to a keyword heuristic.
    func analyzeThought(_ text: String) async -> ThoughtAnalysis? {
        let now = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        let nowString = dateFormatter.string(from: now)
        let timeZone = TimeZone.current.identifier

        let system = """
        You analyze a single quick-capture note and return structured JSON.

        The current date and time is \(nowString) (timezone: \(timeZone)).
        Resolve any relative time reference ("tomorrow", "next Friday at 3pm",
        "in 2 hours") to an absolute ISO-8601 date-time with timezone offset, and
        put it in dueDate. Omit dueDate entirely if the note mentions no time.

        Categories:
        - task: something to do, an errand, a person to contact, a reminder
        - idea: a thought, observation, brainstorm, or concept
        - info: a fact or reference to remember (codes, numbers, accounts, recommendations)

        Set isTask=true only for actionable items. cleanedText is the note with
        filler/disfluencies removed but meaning preserved. tags are 0–4 short
        lowercase keywords. priority is 1 (low) to 3 (high) when inferable.

        If the note enumerates several distinct things to get or do (a shopping
        list, a packing list, errands), return them as separate strings in items
        and give the list a short listTitle (e.g. "Grocery store"). For such a
        list set isTask=false (the items are checked off individually). Omit items
        and listTitle entirely for single thoughts.

        Examples:
        "I need to call mom about dinner tomorrow at 6" → category task, isTask true, a dueDate
        "what if we used AI for onboarding" → category idea, isTask false, no dueDate
        "my mariano's rewards number is 4023" → category info, isTask false, no dueDate
        "for the store I need milk, eggs and bread" → category task, isTask false, listTitle "Grocery store", items ["Milk", "Eggs", "Bread"]
        """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "category": ["type": "string", "enum": ["task", "idea", "info"]],
                "isTask": ["type": "boolean"],
                "cleanedText": ["type": "string"],
                "dueDate": ["type": "string", "format": "date-time"],
                "priority": ["type": "integer", "enum": [1, 2, 3]],
                "tags": ["type": "array", "items": ["type": "string"]],
                "listTitle": ["type": "string"],
                "items": ["type": "array", "items": ["type": "string"]]
            ],
            "required": ["category", "isTask", "cleanedText", "tags"],
            "additionalProperties": false
        ]

        let response = await callAnthropic(
            system: system,
            userText: text,
            maxTokens: 400,
            jsonSchema: schema
        )

        guard let data = response.data(using: .utf8),
              let analysis = try? Self.analysisDecoder.decode(ThoughtAnalysis.self, from: data) else {
            return nil
        }
        return analysis
    }

    private func extractKeywords(_ text: String) -> [String] {
        // Combine whitespace and punctuation character sets
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)

        return text.lowercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty && $0.count > 2 }
    }

    private func filterThoughtsForQuery(_ thoughts: [CapturedThought], queryType: QueryType) -> [CapturedThought] {
        switch queryType {
        case .informationRetrieval:
            return thoughts.filter { thought in
                let text = thought.text.lowercased()
                return text.contains("number") || text.contains("code") ||
                       text.contains("account") || text.contains("password") ||
                       thought.category == "info"
            }

        case .taskQuery:
            return getActiveTasks(thoughts)

        case .shoppingQuery:
            return thoughts // handled directly in queryThoughts via list items

        case .generalQuery:
            return thoughts
        }
    }

    private func buildPromptForQueryType(query: String, context: String, queryType: QueryType) -> String {
        switch queryType {
        case .informationRetrieval:
            return """
            Find specific information from my notes:
            \(context)

            Question: \(query)

            Give me just the answer, no extra text.
            """

        case .taskQuery:
            return """
            Here are my task-related thoughts, already filtered to remove completed items:
            \(context)

            Question: \(query)

            IMPORTANT: These have already been filtered - only show items that are still pending.
            If the filtered list is empty, respond with "All caught up!"

            Format as bullet points, be concise.
            """

        case .shoppingQuery:
            return """
            My shopping notes (already filtered for active items):
            \(context)

            Question: \(query)

            List items I still need to get. If none, say "Nothing needed!"
            """

        case .generalQuery:
            return """
            My notes: \(context)
            Question: \(query)

            Be helpful and concise.
            """
        }
    }

    private func getActiveTasks(_ thoughts: [CapturedThought]) -> [CapturedThought] {
        var activeTasks: [CapturedThought] = []

        // Get all task-related thoughts
        let taskThoughts = thoughts.filter { thought in
            thought.category == "task" || thought.text.lowercased().contains("need to") ||
            thought.text.lowercased().contains("remind me") || thought.text.lowercased().contains("book") ||
            thought.text.lowercased().contains("call") || thought.text.lowercased().contains("message")
        }

        // Check each task to see if it was completed later
        for task in taskThoughts {
            let isCompleted = isTaskCompleted(task, allThoughts: thoughts)
            if !isCompleted {
                activeTasks.append(task)
            }
        }

        return activeTasks
    }

    private func isTaskCompleted(_ task: CapturedThought, allThoughts: [CapturedThought]) -> Bool {
        let taskText = task.text.lowercased()

        // Get all thoughts after this task
        let laterThoughts = allThoughts.filter { $0.timestamp > task.timestamp }

        // Check if any later thought indicates completion
        return laterThoughts.contains { laterThought in
            let laterText = laterThought.text.lowercased()

            // Check for completion of specific tasks
            if taskText.contains("paris hotel") || taskText.contains("book") && taskText.contains("hotel") {
                return laterText.contains("booked") && (laterText.contains("paris") || laterText.contains("hotel"))
            }

            if taskText.contains("johnny") || taskText.contains("message") && taskText.contains("johnny") {
                return laterText.contains("sent") || laterText.contains("messaged") && laterText.contains("johnny")
            }

            if taskText.contains("car") && taskText.contains("serviced") {
                return laterText.contains("took car") || laterText.contains("car serviced") || laterText.contains("got car serviced")
            }

            // Generic completion patterns
            let completionKeywords = [
                "already ", "done ", "completed ", "finished ", "did ", "sent ",
                "called ", "booked ", "scheduled ", "messaged ", "texted "
            ]

            // Extract key terms from the original task
            let taskKeywords = extractTaskKeywords(taskText)

            return completionKeywords.contains { completionWord in
                taskKeywords.contains { keyword in
                    laterText.contains(completionWord + keyword) ||
                    laterText.contains(completionWord) && laterText.contains(keyword)
                }
            }
        }
    }

    private func extractTaskKeywords(_ text: String) -> [String] {
        let importantWords = text.components(separatedBy: .whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { word in
                word.count > 2 &&
                !["the", "and", "for", "with", "need", "remind", "get", "take"].contains(word.lowercased())
            }
        return importantWords
    }

    func queryThoughts(_ query: String, thoughts: [CapturedThought], queryType: QueryType, pendingTasks: [ChatMessage] = []) async -> String {
        if queryType == .taskQuery {
            // Use the passed-in pending tasks instead of trying to access dataManager
            if pendingTasks.isEmpty {
                return "All caught up! No pending tasks found. 🎉"
            }

            let taskList = pendingTasks
                .sorted { $0.timestamp < $1.timestamp }
                .enumerated()
                .map { index, task in
                    "\(index + 1). \(task.text)"
                }
                .joined(separator: "\n")

            return """
            Here are your pending tasks:

            \(taskList)

            Tap the checkmark next to any task to mark it complete!
            """
        }

        if queryType == .shoppingQuery {
            // Read directly from list items — no keyword guessing.
            let openItems = thoughts
                .compactMap { $0.items }
                .flatMap { $0 }
                .filter { !$0.isChecked }
            if openItems.isEmpty {
                return "Nothing needed! 🎉"
            }
            let list = openItems.map { "- \($0.text)" }.joined(separator: "\n")
            return "Here's what you still need:\n\n\(list)"
        }

        // Handle other query types as before...
        let relevantThoughts = filterThoughtsForQuery(thoughts, queryType: queryType)
        let contextText = relevantThoughts
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(20)
            .map { formatThoughtForQuery($0) }
            .joined(separator: "\n")

        let prompt = buildPromptForQueryType(query: query, context: contextText, queryType: queryType)
        let maxTokens = queryType == .informationRetrieval ? 200 : 400
        let system = """
        You are Jot, a concise assistant that answers questions about the user's
        own captured notes. When listing multiple items, format them as a Markdown
        bullet list. Keep answers brief and to the point.
        """

        return await callAnthropic(system: system, userText: prompt, maxTokens: maxTokens)
    }

    private func formatThoughtForQuery(_ thought: CapturedThought) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        let timeString = formatter.string(from: thought.timestamp)
        return "[\(timeString)] \(thought.text)"
    }

    private func callAnthropic(system: String?, userText: String, maxTokens: Int = 200, jsonSchema: [String: Any]? = nil) async -> String {
        guard !apiKey.isEmpty && apiKey != "your-anthropic-api-key-here" else {
            return "Error: Anthropic API key not configured"
        }

        DispatchQueue.main.async {
            self.isProcessing = true
            self.errorMessage = ""
        }

        defer {
            DispatchQueue.main.async {
                self.isProcessing = false
            }
        }

        var requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                [
                    "role": "user",
                    "content": userText
                ]
            ]
        ]
        if let system = system {
            requestBody["system"] = system
        }
        if let jsonSchema = jsonSchema {
            requestBody["output_config"] = ["format": ["type": "json_schema", "schema": jsonSchema]]
        }

        do {
            guard let url = URL(string: baseURL) else {
                throw AIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIError.invalidResponse
            }

            if httpResponse.statusCode == 401 {
                DispatchQueue.main.async {
                    self.errorMessage = "Invalid API key"
                }
                return "Error: Invalid Anthropic API key"
            }

            if httpResponse.statusCode != 200 {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("Anthropic API Error: \(httpResponse.statusCode) - \(errorBody)")
                throw AIError.apiError(httpResponse.statusCode)
            }

            // Anthropic returns { "content": [ { "type": "text", "text": "..." }, ... ] }
            let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard let content = jsonResponse?["content"] as? [[String: Any]],
                  let textBlock = content.first(where: { ($0["type"] as? String) == "text" }),
                  let text = textBlock["text"] as? String else {
                throw AIError.invalidResponse
            }

            return text.trimmingCharacters(in: .whitespacesAndNewlines)

        } catch {
            let errorMsg = "AI request failed: \(error.localizedDescription)"
            DispatchQueue.main.async {
                self.errorMessage = errorMsg
            }
            return errorMsg
        }
    }
}

// MARK: - Error Types
enum AIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from AI service"
        case .apiError(let code):
            return "API error with code: \(code)"
        }
    }
}
