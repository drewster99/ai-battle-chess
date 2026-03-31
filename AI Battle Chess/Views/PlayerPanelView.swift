import SwiftUI
import SwiftLLMKit

// MARK: - Player Panel View

/// Displays player info, captured pieces, statistics, and AI activity on one side of the board.
struct PlayerPanelView: View {
    @Bindable var engine: GameEngine
    let color: PieceColor

    private var player: PlayerConfig {
        color == .white ? engine.whitePlayer : engine.blackPlayer
    }

    private var isCurrentTurn: Bool {
        engine.board.activeColor == color && engine.isGameActive
    }

    private var materialValue: Int {
        engine.statistics.materialValue[color] ?? 0
    }

    private var opponentMaterial: Int {
        engine.statistics.materialValue[color.opposite] ?? 0
    }

    private var materialAdvantage: Int {
        materialValue - opponentMaterial
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Player header
                playerHeader

                // Resign button (human players only)
                if !player.isAI && engine.isGameActive {
                    Button("Resign") {
                        engine.resign(color: color)
                    }
                    .disabled(engine.isAIThinking)
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }

                Divider()

                // Captured pieces
                capturedPiecesView

                Divider()

                // Statistics
                statisticsView

                // AI Status (if AI player)
                if player.isAI {
                    Divider()
                    aiStatusView

                    Divider()
                    aiActivitySection
                }

                Spacer()
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrentTurn && engine.isGameActive ?
                      Color.accentColor.opacity(0.08) :
                      Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isCurrentTurn && engine.isGameActive ?
                    Color.accentColor.opacity(0.5) :
                    Color.clear,
                    lineWidth: 2
                )
        )
    }

    // MARK: - Player Header

    private var playerHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Color indicator
                Circle()
                    .fill(color == .white ? Color.white : Color.black)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle().strokeBorder(Color.gray, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if player.isAI {
                            if player.useAppleIntelligence {
                                Label("Apple Intelligence", systemImage: "apple.intelligence")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let configID = player.aiConfigurationID,
                                      let config = engine.llmKit.configurations.first(where: { $0.id == configID }) {
                                Label(config.name, systemImage: "cpu")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Label("AI", systemImage: "cpu")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Label("Human", systemImage: "person.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if isCurrentTurn && engine.isGameActive {
                    if engine.isAIThinking && engine.currentAIColor == color {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrowtriangle.right.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.caption)
                    }
                }
            }

            // Player stats row
            playerStatsRow
        }
    }

    // MARK: - Player Stats Row

    private var playerStatsRow: some View {
        HStack(spacing: 12) {
            let moves = engine.moveCount(for: color)
            Label("\(moves)", systemImage: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)

            let avgTime = engine.averageMoveTime(for: color)
            if avgTime > 0 {
                Label(formatDuration(avgTime), systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            let totalGames = engine.gameHistoryManager.totalGamesForPlayer(id: player.humanPlayerID, name: player.name) + (engine.isGameActive ? 1 : 0)
            Label("\(totalGames)", systemImage: "number")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .help("Total games played (includes current game)")
        }
    }

    // MARK: - Captured Pieces

    private var capturedPiecesView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Captures")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if materialAdvantage > 0 {
                    Text("+\(materialAdvantage)")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }

            // Show pieces captured BY this player (from move history)
            let captured = engine.capturedPieces(for: color.opposite)
            if captured.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(20)), count: 8), spacing: 2) {
                    ForEach(Array(captured.enumerated()), id: \.offset) { _, type in
                        let piece = ChessPiece(color: color.opposite, type: type)
                        Image(piece.assetName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                            .opacity(0.7)
                    }
                }
            }
        }
    }

    // MARK: - Statistics

    private var statisticsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Stats")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                GridRow {
                    StatItem(label: "Captures", value: "\(engine.statistics.captureCount[color] ?? 0)")
                    StatItem(label: "Checks", value: "\(engine.statistics.checkCount[color] ?? 0)")
                }
                GridRow {
                    StatItem(label: "Castled", value: (engine.statistics.castled[color] ?? false) ? "Yes" : "---")
                    StatItem(label: "Promos", value: "\(engine.statistics.promotions[color] ?? 0)")
                }
            }
        }
    }

    // MARK: - AI Status

    private var aiStatusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI Status")
                .font(.caption)
                .foregroundStyle(.secondary)

            let penalties = engine.statistics.aiPenalties[color] ?? []
            let retries = engine.statistics.aiRetryCount[color] ?? 0

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                GridRow {
                    StatItem(label: "Retries", value: "\(retries)")
                    StatItem(label: "Penalties", value: "\(penalties.count)")
                }
            }

            if let lastPenalty = penalties.last {
                Text(lastPenalty.reason)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - AI Activity Section

    @ViewBuilder
    private var aiActivitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Activity")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Settings summary
            aiSettingsSummary

            // Token usage
            if let activity = engine.currentAIActivity[color],
               let tokens = activity.tokenUsage {
                tokenUsageView(tokens)
            }

            // Attempts for current turn
            if let activity = engine.currentAIActivity[color] {
                aiAttemptsView(activity.attempts)
            }

            // Disclosure groups for raw prompts/responses
            DisclosureGroup("System Prompt") {
                ScrollView {
                    Text(AIService.systemPrompt(for: color, isAppleIntelligence: player.useAppleIntelligence))
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }
            .font(.caption)

            DisclosureGroup("Last Prompt") {
                ScrollView {
                    Text(engine.currentAIActivity[color]?.userPrompt ?? "No prompt yet")
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }
            .font(.caption)

            DisclosureGroup("Last Response") {
                ScrollView {
                    Text(engine.currentAIActivity[color]?.responseText ?? "No response yet")
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }
            .font(.caption)
        }
    }

    // MARK: - AI Attempts View

    private func aiAttemptsView(_ attempts: [AITurnAttempt]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let invalidCount = attempts.filter { !$0.isValid }.count
            if invalidCount > 0 {
                Text("\(invalidCount) invalid response\(invalidCount == 1 ? "" : "s") this turn")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            // Show last 10 attempts to avoid performance issues with up to 100 retries
            let displayAttempts = attempts.count > 10 ? Array(attempts.suffix(10)) : attempts
            if attempts.count > 10 {
                Text("(\(attempts.count - 10) earlier attempts hidden)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            ForEach(displayAttempts) { attempt in
                VStack(alignment: .leading, spacing: 2) {
                    // Thinking (blue)
                    if let thinking = attempt.thinking, !thinking.isEmpty {
                        Text(thinking)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .textSelection(.enabled)
                    }

                    // Move with status indicator
                    HStack(spacing: 4) {
                        if attempt.isValid {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption2)
                        } else {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption2)
                        }

                        Text(attempt.moveText)
                            .font(.caption2.monospaced().bold())

                        if let comment = attempt.comment {
                            Text("{ \(comment) }")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Error message
                    if let error = attempt.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(attempt.isValid ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
                )
            }
        }
    }

    // MARK: - AI Settings Summary

    @ViewBuilder
    private var aiSettingsSummary: some View {
        if let activity = engine.currentAIActivity[color] {
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.modelName)
                    .font(.caption2.bold())
                HStack(spacing: 8) {
                    if let temp = activity.temperature {
                        Text("temp: \(temp, specifier: "%.1f")")
                    }
                    if let budget = activity.thinkingBudget {
                        Text("think: \(budget)")
                    }
                    if let maxTokens = activity.maxOutputTokens {
                        Text("max: \(maxTokens)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        } else if player.useAppleIntelligence {
            Text("Apple Intelligence (On-device)")
                .font(.caption2.bold())
        } else if let configID = player.aiConfigurationID,
                  let config = engine.llmKit.configurations.first(where: { $0.id == configID }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.caption2.bold())
                HStack(spacing: 8) {
                    Text("temp: \(config.temperature, specifier: "%.1f")")
                    Text("max: \(config.maxOutputTokens)")
                    if let budget = config.thinkingBudget {
                        Text("think: \(budget)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Token Usage

    private func tokenUsageView(_ tokens: TokenUsage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Token Usage")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if let input = tokens.inputTokens {
                    Text("In: \(input)")
                        .font(.caption2.monospacedDigit())
                }
                if let output = tokens.outputTokens {
                    Text("Out: \(output)")
                        .font(.caption2.monospacedDigit())
                }
                if let cache = tokens.cacheReadTokens, cache > 0 {
                    Text("Cache: \(cache)")
                        .font(.caption2.monospacedDigit())
                }
            }
        }
    }


    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return String(format: "%.0fms", seconds * 1000)
        } else if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let mins = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return "\(mins)m \(secs)s"
        }
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.callout.monospacedDigit().bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
