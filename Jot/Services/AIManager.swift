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
          let apiKey = config["OpenAIAPIKey"] as? String else {
        return ""
    }
    return apiKey
}

class AIManager: ObservableObject {
    @Published var isProcessing = false
    @Published var errorMessage = ""
    
    private let apiKey = getAPIKey()
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    func categorizeThought(_ text: String) async -> String {
        let prompt = """
        Categorize this voice note and add appropriate tags:
        "\(text)"
        
        Categories:
        - TASK: Things I need to do, people to contact, errands, reminders
        - IDEA: Random thoughts, brainstorming, observations, concepts
        - INFO: Facts, recommendations, things to remember, references
        
        Format your response as:
        [CATEGORY] Original text here
        
        Examples:
        "I need to call Mom about dinner" → [TASK] I need to call Mom about dinner
        "What if we used AI for customer support" → [IDEA] What if we used AI for customer support
        "Sarah recommended that Italian restaurant downtown" → [INFO] Sarah recommended that Italian restaurant downtown
        """
        
        return await callOpenAI(prompt: prompt, maxTokens: 150)
    }
    
    private func extractKeywords(_ text: String) -> [String] {
        // Combine whitespace and punctuation character sets
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        
        return text.lowercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty && $0.count > 2 }
    }

    private func extractShoppingItems(_ text: String) -> [String] {
        // Simple implementation - extract common grocery items
        let commonItems = ["milk", "eggs", "bread", "butter", "cheese", "meat", "chicken", "beef"]
        return commonItems.filter { text.lowercased().contains($0) }
    }

    private func filterThoughtsForQuery(_ thoughts: [CapturedThought], queryType: QueryType) -> [CapturedThought] {
        switch queryType {
        case .informationRetrieval:
            return thoughts.filter { thought in
                let text = thought.text.lowercased()
                return text.contains("number") || text.contains("code") ||
                       text.contains("account") || text.contains("password") ||
                       thought.category == "INFO"
            }
            
        case .taskQuery:
            return getActiveTasks(thoughts)
            
        case .shoppingQuery:
            return getActiveShoppingItems(thoughts)
            
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
            thought.category == "TASK" || thought.text.lowercased().contains("need to") ||
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

    private func getActiveShoppingItems(_ thoughts: [CapturedThought]) -> [CapturedThought] {
        return thoughts.filter { thought in
            let text = thought.text.lowercased()
            guard text.contains("need") || text.contains("buy") || text.contains("store") || text.contains("grocery") else { return false }
            
            // Check if items were purchased
            let items = extractShoppingItems(thought.text)
            let isCompleted = thoughts.filter { $0.timestamp > thought.timestamp }.contains { laterThought in
                let laterText = laterThought.text.lowercased()
                return items.contains { item in
                    laterText.contains("got \(item)") || laterText.contains("bought \(item)")
                }
            }
            
            return !isCompleted
        }
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
        
        // Handle other query types as before...
        let relevantThoughts = filterThoughtsForQuery(thoughts, queryType: queryType)
        let contextText = relevantThoughts
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(20)
            .map { formatThoughtForQuery($0) }
            .joined(separator: "\n")
        
        let prompt = buildPromptForQueryType(query: query, context: contextText, queryType: queryType)
        let maxTokens = queryType == .informationRetrieval ? 100 : 200
        
        return await callOpenAI(prompt: prompt, maxTokens: maxTokens)
    }
    
    private func formatThoughtForQuery(_ thought: CapturedThought) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        let timeString = formatter.string(from: thought.timestamp)
        return "[\(timeString)] \(thought.text)"
    }
    
    private func callOpenAI(prompt: String, maxTokens: Int = 150) async -> String {
        guard !apiKey.isEmpty && apiKey != "your-openai-api-key-here" else {
            return "Error: OpenAI API key not configured"
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
        
        let requestBody: [String: Any] = [
            "model": "gpt-4.1-nano",
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "max_tokens": maxTokens,
            "temperature": 0.7
        ]
        
        do {
            guard let url = URL(string: baseURL) else {
                throw AIError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
                return "Error: Invalid OpenAI API key"
            }
            
            if httpResponse.statusCode != 200 {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("OpenAI API Error: \(httpResponse.statusCode) - \(errorBody)")
                throw AIError.apiError(httpResponse.statusCode)
            }
            
            let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let choices = jsonResponse?["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw AIError.invalidResponse
            }
            
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
            
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


