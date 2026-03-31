import SwiftUI

// MARK: - AI Activity Detail

/// Data passed to the detail window for a single AI turn.
struct AIActivityDetail: Codable, Hashable, Identifiable {
    let id: UUID
    let moveNumber: Int
    let color: PieceColor
    let modelName: String
    let systemPrompt: String
    let userPrompt: String
    let responseText: String
    let attempts: [AITurnAttemptSnapshot]
    let tokenUsage: TokenUsage?
    let temperature: Double?
    let thinkingBudget: Int?
    let maxOutputTokens: Int?
    let elapsed: TimeInterval

    init(from log: AIActivityLog, moveNumber: Int, color: PieceColor, elapsed: TimeInterval) {
        self.id = UUID()
        self.moveNumber = moveNumber
        self.color = color
        self.modelName = log.modelName
        self.systemPrompt = log.systemPrompt
        self.userPrompt = log.userPrompt
        self.responseText = log.responseText
        self.attempts = log.attempts.map { AITurnAttemptSnapshot(from: $0) }
        self.tokenUsage = log.tokenUsage
        self.temperature = log.temperature
        self.thinkingBudget = log.thinkingBudget
        self.maxOutputTokens = log.maxOutputTokens
        self.elapsed = elapsed
    }
}

/// Codable/Hashable snapshot of AITurnAttempt for passing to the detail window.
struct AITurnAttemptSnapshot: Codable, Hashable, Identifiable {
    let id: UUID
    let thinking: String?
    let moveText: String
    let comment: String?
    let isValid: Bool
    let errorMessage: String?

    init(from attempt: AITurnAttempt) {
        self.id = attempt.id
        self.thinking = attempt.thinking
        self.moveText = attempt.moveText
        self.comment = attempt.comment
        self.isValid = attempt.isValid
        self.errorMessage = attempt.errorMessage
    }
}

// MARK: - Detail View

struct AIActivityDetailView: View {
    let detail: AIActivityDetail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                header

                Divider()

                // Attempts
                attemptsSection

                Divider()

                // System Prompt
                promptSection(title: "System Prompt", content: detail.systemPrompt)

                Divider()

                // User Prompt (conversation for this turn)
                promptSection(title: "User Prompt", content: detail.userPrompt)

                Divider()

                // Raw Response
                promptSection(title: "Response", content: detail.responseText)
            }
            .padding(16)
        }
        .frame(minWidth: 500, idealWidth: 650, minHeight: 400, idealHeight: 600)
        .navigationTitle("Move \(detail.moveNumber) — \(detail.color.displayName)")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Move \(detail.moveNumber)")
                    .font(.title2.bold())
                Text("(\(detail.color.displayName))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()

                let successMove = detail.attempts.last(where: { $0.isValid })?.moveText ?? "?"
                Text(successMove)
                    .font(.title2.monospaced().bold())
                    .foregroundStyle(.green)
            }

            HStack(spacing: 16) {
                Label(detail.modelName, systemImage: "cpu")
                Label(formatDuration(detail.elapsed), systemImage: "clock")
                if let temp = detail.temperature {
                    Label(String(format: "%.1f", temp), systemImage: "thermometer.medium")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Token usage
            if let tokens = detail.tokenUsage {
                HStack(spacing: 12) {
                    if let input = tokens.inputTokens {
                        HStack(spacing: 2) {
                            Text("In:")
                                .foregroundStyle(.secondary)
                            Text("\(input)")
                        }
                    }
                    if let output = tokens.outputTokens {
                        HStack(spacing: 2) {
                            Text("Out:")
                                .foregroundStyle(.secondary)
                            Text("\(output)")
                        }
                    }
                    if let cache = tokens.cacheReadTokens, cache > 0 {
                        HStack(spacing: 2) {
                            Text("Cache:")
                                .foregroundStyle(.secondary)
                            Text("\(cache)")
                        }
                    }
                }
                .font(.caption.monospacedDigit())
            }
        }
    }

    // MARK: - Attempts

    private var attemptsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            let invalidCount = detail.attempts.filter { !$0.isValid }.count
            Text("Attempts (\(detail.attempts.count) total, \(invalidCount) invalid)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ForEach(Array(detail.attempts.enumerated()), id: \.element.id) { index, attempt in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: attempt.isValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(attempt.isValid ? .green : .red)
                            .font(.caption)

                        Text("#\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)

                        Text(attempt.moveText)
                            .font(.caption.monospaced().bold())

                        if let comment = attempt.comment {
                            Text("{ \(comment) }")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let thinking = attempt.thinking, !thinking.isEmpty {
                        Text(thinking)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .textSelection(.enabled)
                            .padding(.leading, 20)
                    }

                    if let error = attempt.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .italic()
                            .padding(.leading, 20)
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(attempt.isValid ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
                )
            }
        }
    }

    // MARK: - Prompt Section

    private func promptSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }

            Text(content)
                .font(.caption2.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.textBackgroundColor))
                )
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
