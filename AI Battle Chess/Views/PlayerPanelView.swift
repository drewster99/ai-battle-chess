import SwiftUI
import SwiftLLMKit

// MARK: - Player Panel View

/// Displays player info, captured pieces, statistics, and AI activity on one side of the board.
struct PlayerPanelView: View {
    @Bindable var engine: GameEngine
    let color: PieceColor
    @Environment(\.openWindow) private var openWindow

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

    private var totalTime: TimeInterval {
        (engine.statistics.perMoveDuration[color] ?? []).reduce(0, +)
    }

    private var aiConfig: ModelConfiguration? {
        guard let configID = player.aiConfigurationID else { return nil }
        return engine.llmKit.configurations.first(where: { $0.id == configID })
    }

    private var aiProvider: ModelProvider? {
        guard let config = aiConfig else { return nil }
        return engine.llmKit.providers.first(where: { $0.id == config.providerID })
    }

    private var appleIntelligenceConfig: AppleIntelligenceConfig? {
        guard let configID = player.appleIntelligenceConfigID else { return nil }
        return engine.appleIntelligenceConfigManager.config(byID: configID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed header (does not scroll)
            VStack(alignment: .leading, spacing: 10) {
                playerHeader

                if !player.isAI && engine.isGameActive {
                    Button("Resign") {
                        engine.resign(color: color)
                    }
                    .disabled(engine.isAIThinking)
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    statsCard

                    if player.isAI {
                        Divider()
                        aiActivitySection
                    }

                    Spacer()
                }
                .padding(10)
            }
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
            // Name + type badge
            HStack(spacing: 8) {
                Circle()
                    .fill(color == .white ? Color.white : Color.black)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle().strokeBorder(Color.gray, lineWidth: 1)
                    )

                Text(player.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(player.isAI ? "[AI]" : "[Human]")
                    .font(.caption.bold())
                    .foregroundStyle(player.isAI ? .blue : .green)

                Spacer()

                ZStack {
                    // Reserve consistent space
                    ProgressView()
                        .controlSize(.small)
                        .hidden()

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
            }

            // AI model config details
            if player.isAI {
                aiConfigDetails
            }

            // Stats row
            playerStatsRow
        }
    }

    // MARK: - AI Config Details

    @ViewBuilder
    private var aiConfigDetails: some View {
        if player.useAppleIntelligence, let aiCfg = appleIntelligenceConfig {
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 2) {
                configRow(label: "Model", value: aiCfg.name)
                configRow(label: "Sampling", value: aiCfg.samplingDescription)
                if let temp = aiCfg.temperature {
                    configRow(label: "Temp", value: String(format: "%.2f", temp))
                }
                if let maxTokens = aiCfg.maximumResponseTokens {
                    configRow(label: "Max tokens", value: "\(maxTokens)")
                }
                configRow(label: "Resign", value: player.allowResign ? "Allowed" : "Not allowed")
            }
            .font(.caption2)
        } else if player.useAppleIntelligence {
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 2) {
                configRow(label: "Model", value: "Apple Intelligence (on-device)")
                configRow(label: "Resign", value: player.allowResign ? "Allowed" : "Not allowed")
            }
            .font(.caption2)
        } else if let config = aiConfig {
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 2) {
                if let provider = aiProvider {
                    configRow(label: "Provider", value: provider.name)
                }
                configRow(label: "Model", value: config.modelID)
                configRow(label: "Temp", value: String(format: "%.1f", config.temperature))
                configRow(label: "Max tokens", value: "\(config.maxOutputTokens)")
                configRow(label: "Context", value: "\(config.maxContextTokens)")
                if let budget = config.thinkingBudget {
                    configRow(label: "Thinking", value: "\(budget)")
                }
                configRow(label: "Resign", value: player.allowResign ? "Allowed" : "Not allowed")
            }
            .font(.caption2)
        }
    }

    private func configRow(label: String, value: String) -> some View {
        GridRow {
            Text("\(label):")
                .foregroundStyle(.tertiary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
        }
    }

    // MARK: - Player Stats Row

    private var playerStatsRow: some View {
        HStack(spacing: 10) {
            let moves = engine.moveCount(for: color)
            Label("\(moves)", systemImage: "arrow.right")
                .instantHelp("Moves played this game")

            // Current move elapsed time (live) or viewed move duration (history)
            if let viewIndex = engine.viewingMoveIndex {
                // Viewing history — show the duration of the viewed move if it belongs to this player
                if viewIndex < engine.moveHistory.count,
                   engine.moveHistory[viewIndex].piece.color == color {
                    let durations = engine.statistics.perMoveDuration[color] ?? []
                    let moveNumber = engine.moveHistory.prefix(viewIndex + 1).filter({ $0.piece.color == color }).count
                    if moveNumber > 0, moveNumber <= durations.count {
                        let duration = durations[moveNumber - 1]
                        Label(formatDuration(duration), systemImage: "stopwatch")
                            .foregroundStyle(.primary)
                            .instantHelp("Time taken for this move")
                    }
                }
            } else if engine.isGameActive, !engine.isViewingPastGame,
                      engine.board.activeColor == color {
                // Live game, this player's turn — show live timer
                Text(engine.statistics.turnStartTime, style: .timer)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.primary)
                    .instantHelp("Time elapsed on current move")
            }

            if totalTime > 0 {
                Label(formatDuration(totalTime), systemImage: "timer")
                    .instantHelp("Total time for all moves this game")
            }

            let avgTime = engine.averageMoveTime(for: color)
            if avgTime > 0 {
                Label(formatDuration(avgTime), systemImage: "clock")
                    .instantHelp("Average time per move")
            }

            let totalGames = engine.gameHistoryManager.totalGamesForPlayer(id: player.humanPlayerID, name: player.name) + (engine.isGameActive ? 1 : 0)
            Label("\(totalGames)", systemImage: "number")
                .instantHelp("Total games played (includes current game)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    // MARK: - Combined Stats Card

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            capturedPiecesView

            let captures = engine.statistics.captureCount[color] ?? 0
            let checks = engine.statistics.checkCount[color] ?? 0
            let castled = engine.statistics.castled[color] ?? false
            let promos = engine.statistics.promotions[color] ?? 0

            HStack(spacing: 0) {
                miniStat(value: "\(captures)", label: "Captures", color: captures > 0 ? .orange : .secondary)
                miniStat(value: "\(checks)", label: "Checks", color: checks > 0 ? .red : .secondary)
                miniStat(value: castled ? "Yes" : "---", label: "Castled", color: castled ? .blue : .secondary)
                miniStat(value: "\(promos)", label: "Promos", color: promos > 0 ? .purple : .secondary)
            }
        }
    }

    private func miniStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.caption, design: .rounded).bold())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
                        .instantHelp("Material advantage (piece value points)")
                } else if materialAdvantage < 0 {
                    Text("\(materialAdvantage)")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                        .instantHelp("Material disadvantage (piece value points)")
                }
            }

            let captured = engine.capturedPieces(for: color.opposite)
            if captured.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 2) {
                    ForEach(Array(captured.enumerated()), id: \.offset) { _, type in
                        let piece = ChessPiece(color: color.opposite, type: type)
                        capturedPieceImage(piece)
                    }
                }
            }
        }
    }

    /// Renders a captured piece image with a contrast outline for visibility in both light and dark mode.
    @ViewBuilder
    private func capturedPieceImage(_ piece: ChessPiece) -> some View {
        let image = Image(piece.assetName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)

        if piece.color == .black {
            // Black pieces need a light outline to be visible on dark backgrounds
            image
                .shadow(color: .white.opacity(0.9), radius: 0.5)
                .opacity(0.85)
        } else {
            image
                .opacity(0.7)
        }
    }

    // MARK: - AI Activity Section

    @ViewBuilder
    private var aiActivitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Activity")
                .font(.caption)
                .foregroundStyle(.secondary)

            // All moves this game in a grid
            let history = engine.aiActivityHistory[color] ?? []
            if history.isEmpty {
                Text("No moves yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                aiMovesGrid(history)
            }

            // Current thinking text
            if let activity = engine.currentAIActivity[color],
               let lastAttempt = activity.attempts.last,
               let thinking = lastAttempt.thinking, !thinking.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thinking")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(thinking)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .textSelection(.enabled)
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue.opacity(0.05))
                        )
                }
            }
        }
    }

    // MARK: - AI Moves Grid

    private func aiMovesGrid(_ history: [AIActivityLog]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            // Header row
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 16)
                Text("Move")
                    .frame(width: 50, alignment: .leading)
                Text("Time")
                    .frame(width: 52, alignment: .trailing)
                Text("Tok In")
                    .frame(width: 52, alignment: .trailing)
                Text("Tok Out")
                    .frame(width: 52, alignment: .trailing)
                Text("t/s")
                    .frame(width: 36, alignment: .trailing)
            }
            .font(.system(size: 9).bold())
            .foregroundStyle(.tertiary)

            // Move rows
            let durations = engine.statistics.perMoveDuration[color] ?? []
            ForEach(Array(history.enumerated()), id: \.offset) { index, log in
                let successAttempt = log.attempts.last(where: { $0.isValid })
                let moveText = successAttempt?.moveText ?? "?"
                let retries = log.attempts.filter { !$0.isValid }.count
                let elapsed = index < durations.count ? durations[index] : 0
                let tokensIn = log.tokenUsage?.inputTokens
                let tokensOut = log.tokenUsage?.outputTokens
                let tokPerSec: Double? = {
                    guard let out = tokensOut, elapsed > 0 else { return nil }
                    return Double(out) / elapsed
                }()

                Button {
                    let detail = AIActivityDetail(from: log, moveNumber: index + 1, color: color, elapsed: elapsed)
                    openWindow(value: detail)
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        // Main move row
                        HStack(spacing: 0) {
                            Image(systemName: retries > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(retries > 0 ? .orange : .green)
                                .frame(width: 16)

                            Text(moveText)
                                .font(.caption2.monospaced().bold())
                                .frame(width: 50, alignment: .leading)

                            Text(formatDuration(elapsed))
                                .frame(width: 52, alignment: .trailing)

                            if let tokIn = tokensIn {
                                Text("\(tokIn)")
                                    .frame(width: 52, alignment: .trailing)
                            } else {
                                Text("--")
                                    .frame(width: 52, alignment: .trailing)
                            }

                            if let tokOut = tokensOut {
                                Text("\(tokOut)")
                                    .frame(width: 52, alignment: .trailing)
                            } else {
                                Text("--")
                                    .frame(width: 52, alignment: .trailing)
                            }

                            if let tps = tokPerSec {
                                Text(String(format: "%.0f", tps))
                                    .frame(width: 36, alignment: .trailing)
                            } else {
                                Text("--")
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.primary)

                        // Error details for invalid attempts
                        let invalidAttempts = log.attempts.filter { !$0.isValid }
                        ForEach(Array(invalidAttempts.enumerated()), id: \.offset) { _, attempt in
                            HStack(spacing: 4) {
                                Text(attempt.moveText)
                                    .italic()
                                if let error = attempt.errorMessage {
                                    Text("— \(error)")
                                        .italic()
                                }
                            }
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .padding(.leading, 18)
                        }
                    }
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index % 2 == 0 ? Color.clear : Color.primary.opacity(0.03))
                    )
                }
                .buttonStyle(.plain)
                .instantHelp("Click to view full details for this move")
            }

            // Totals row
            let totalIn = history.compactMap { $0.tokenUsage?.inputTokens }.reduce(0, +)
            let totalOut = history.compactMap { $0.tokenUsage?.outputTokens }.reduce(0, +)
            if totalIn > 0 || totalOut > 0 {
                Divider()
                HStack(spacing: 0) {
                    Text("")
                        .frame(width: 16)
                    Text("Total")
                        .font(.system(size: 10).bold())
                        .frame(width: 50, alignment: .leading)
                    Text(formatDuration(totalTime))
                        .frame(width: 52, alignment: .trailing)
                    Text("\(totalIn)")
                        .frame(width: 52, alignment: .trailing)
                    Text("\(totalOut)")
                        .frame(width: 52, alignment: .trailing)
                    Text("")
                        .frame(width: 36)
                }
                .font(.system(size: 10).monospacedDigit().bold())
                .foregroundStyle(.secondary)
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
