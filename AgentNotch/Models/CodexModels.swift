//
//  CodexModels.swift
//  AgentNotch
//
//  Created for OpenAI Codex CLI JSONL integration
//

import Foundation

// MARK: - Session Discovery

/// Represents an active Codex CLI session from ~/.codex/sessions/
struct CodexSession: Identifiable, Equatable {
    let id: String  // session_id from session_meta
    let cwd: String
    let cliVersion: String
    let modelProvider: String
    let gitBranch: String?
    let gitCommit: String?
    let timestamp: Date
    let jsonlFile: URL

    /// Display name for UI (last folder component of cwd)
    var displayName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
}

// MARK: - Token Usage

/// Token usage data from Codex token_count event
struct CodexTokenUsage: Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cachedInputTokens: Int = 0
    var reasoningOutputTokens: Int = 0
    var totalTokens: Int = 0
    var modelContextWindow: Int = 200_000

    var contextPercentage: Double {
        guard modelContextWindow > 0 else { return 0 }
        return min(100, Double(totalTokens) / Double(modelContextWindow) * 100)
    }

    // OpenAI pricing (GPT-4 Turbo estimates)
    struct ModelPricing {
        let inputPerMillion: Double
        let outputPerMillion: Double
        let cachedPerMillion: Double
    }

    static let gpt4Pricing = ModelPricing(
        inputPerMillion: 10.0,
        outputPerMillion: 30.0,
        cachedPerMillion: 2.5
    )

    func estimatedCost(model: String) -> Double {
        let pricing = Self.gpt4Pricing

        let inputCost = Double(inputTokens) / 1_000_000 * pricing.inputPerMillion
        let outputCost = Double(outputTokens) / 1_000_000 * pricing.outputPerMillion
        let cachedCost = Double(cachedInputTokens) / 1_000_000 * pricing.cachedPerMillion

        return inputCost + outputCost + cachedCost
    }
}

// MARK: - Tool Execution

/// Represents a Codex function call in progress or completed
struct CodexToolExecution: Identifiable, Equatable {
    let id: String  // call_id from function_call
    let toolName: String
    let argument: String?
    let startTime: Date
    var endTime: Date?
    var isRunning: Bool { endTime == nil }

    // Additional info
    var workdir: String?
    var output: String?
    var exitCode: Int?

    var durationMs: Int? {
        guard let end = endTime else { return nil }
        return Int(end.timeIntervalSince(startTime) * 1000)
    }

    var formattedDuration: String {
        guard let ms = durationMs else {
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            return formatMs(elapsed)
        }
        return formatMs(ms)
    }

    private func formatMs(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else if ms < 60000 {
            return String(format: "%.1fs", Double(ms) / 1000.0)
        } else {
            let seconds = ms / 1000
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return "\(minutes)m \(remainingSeconds)s"
        }
    }
}

// MARK: - Complete State

/// Complete Codex session state for display
struct CodexState: Equatable {
    var sessionId: String = ""
    var model: String = ""
    var cwd: String = ""
    var gitBranch: String = ""

    var tokenUsage: CodexTokenUsage = CodexTokenUsage()

    var activeTools: [CodexToolExecution] = []
    var recentTools: [CodexToolExecution] = []

    var isConnected: Bool = false
    var lastUpdateTime: Date?

    /// True when Codex is actively thinking/reasoning
    var isThinking: Bool = false

    /// Last reasoning text
    var lastReasoningText: String?

    /// Rate limit info
    var rateLimitUsedPercent: Double = 0

    // Convenience accessors
    var contextPercentage: Double { tokenUsage.contextPercentage }
    var hasActiveTools: Bool { !activeTools.isEmpty }
    var currentToolName: String? { activeTools.first?.toolName }

    /// True when actively processing
    var isActive: Bool { isThinking || hasActiveTools }
}
