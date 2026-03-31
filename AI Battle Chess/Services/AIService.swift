import Foundation
import Observation
import SwiftLLMKit

// MARK: - AI Service

/// Manages AI interactions for chess move generation, supporting all SwiftLLMKit providers and Apple Intelligence.
@MainActor
@Observable
final class AIService {
    private let llmKit: LLMKitManager

    /// Maximum retries before forfeiting
    static var maxRetries: Int { AIConstants.maxRetries }

    init(llmKit: LLMKitManager) {
        self.llmKit = llmKit
    }

    // MARK: - System Prompt

    static func systemPrompt(for color: PieceColor) -> String {
        let yourPieces: String
        let theirPieces: String
        if color == .white {
            yourPieces = "Your pieces (White) are uppercase: K Q R B N P"
            theirPieces = "Black's pieces are lowercase: k q r b n p"
        } else {
            yourPieces = "Your pieces (Black) are lowercase: k q r b n p"
            theirPieces = "White's pieces are uppercase: K Q R B N P"
        }

        let castlingExample = color == .white
            ? "e1g1 (kingside) or e1c1 (queenside)"
            : "e8g8 (kingside) or e8c8 (queenside)"

        return """
        You are a chess engine playing as \(color.displayName). Play strong chess.

        YOUR MOVE FORMAT — CRITICAL
        Respond with exactly one move and nothing else. No explanation, no words, no punctuation.
        Use coordinate notation only: source square + destination square (+ promotion piece if needed).
        All letters must be lowercase. Examples: e7e5, g8f6, e2e1q
        Castling: \(castlingExample)
        NEVER use algebraic notation (e.g. Nf6, Bxe5, O-O). Coordinate notation ONLY.

        BOARD REFERENCE
        \(yourPieces)
        \(theirPieces)

        HOW TO RESPOND
        You will receive the board state, move history, and a list of your legal moves.
        You must pick a move from the legal moves list. Do not invent moves.
        Output that move and nothing else.

        STRATEGY
        Control the center. Develop pieces early. Keep your king safe. Look for tactics (forks, pins, skewers). In endgames, activate your king and advance passed pawns.
        """
    }

    static func boardStatePrompt(board: ChessBoard, moveHistory: [ChessMove], boardStates: [ChessBoard]) -> String {
        var prompt = ""

        // Move history — just the move text, no PGN headers
        if !moveHistory.isEmpty {
            prompt += "Move history: "
            var moveText = ""
            for (index, move) in moveHistory.enumerated() {
                guard index < boardStates.count else { break }
                let san = PGNFormatter.moveToSAN(move, on: boardStates[index])
                if index % 2 == 0 {
                    let moveNum = (index / 2) + 1
                    moveText += "\(moveNum). "
                }
                moveText += san
                if index < moveHistory.count - 1 {
                    moveText += " "
                }
            }
            prompt += moveText + "\n\n"
        }

        // ASCII board
        prompt += "Current board position:\n"
        prompt += asciiBoard(board)
        prompt += "\n"

        // Active color with piece case reminder
        let pieceCase = board.activeColor == .white ? "uppercase (K Q R B N P)" : "lowercase (k q r b n p)"
        prompt += "\(board.activeColor.displayName) to move. Your pieces are \(pieceCase).\n"

        // En passant
        if let ep = board.enPassantTarget {
            prompt += "En passant target: \(ep.description)\n"
        }

        // Check status
        if MoveValidator.isKingInCheck(color: board.activeColor, on: board) {
            prompt += "WARNING: Your king is in CHECK! You must resolve the check.\n"
        }

        // Legal moves list — the AI MUST pick one of these
        let legalMoves = MoveValidator.allLegalMoves(for: board)
        let moveStrings = legalMoves.map { move -> String in
            var s = "\(move.from)\(move.to)"
            if let promo = move.promotionType {
                s += promo.notation.lowercased()
            }
            return s
        }
        prompt += "\nYour legal moves: \(moveStrings.joined(separator: ", "))\n"
        prompt += "Reply with exactly one move from this list.\n"

        return prompt
    }

    private static func asciiBoard(_ board: ChessBoard) -> String {
        var result = "  a b c d e f g h\n"
        for rank in stride(from: 7, through: 0, by: -1) {
            result += "\(rank + 1) "
            for file in 0..<8 {
                if let piece = board.squares[file][rank] {
                    let symbol: String
                    switch (piece.color, piece.type) {
                    case (.white, .king): symbol = "K"
                    case (.white, .queen): symbol = "Q"
                    case (.white, .rook): symbol = "R"
                    case (.white, .bishop): symbol = "B"
                    case (.white, .knight): symbol = "N"
                    case (.white, .pawn): symbol = "P"
                    case (.black, .king): symbol = "k"
                    case (.black, .queen): symbol = "q"
                    case (.black, .rook): symbol = "r"
                    case (.black, .bishop): symbol = "b"
                    case (.black, .knight): symbol = "n"
                    case (.black, .pawn): symbol = "p"
                    }
                    result += "\(symbol) "
                } else {
                    result += ". "
                }
            }
            result += "\(rank + 1)\n"
        }
        result += "  a b c d e f g h"
        return result
    }

    // MARK: - Request AI Move

    /// Requests a move from the AI, handling retries and error penalties.
    func requestMove(
        configurationID: UUID,
        board: ChessBoard,
        moveHistory: [ChessMove],
        boardStates: [ChessBoard],
        color: PieceColor,
        gameID: UUID,
        gameTurnIndex: Int
    ) async throws -> (move: ChessMove, penalties: [AIPenalty], retries: Int, activityLog: AIActivityLog?) {
        var penalties: [AIPenalty] = []
        var retries = 0
        var lastActivityLog: AIActivityLog? = nil

        // Look up configuration details for the activity log
        let config = llmKit.configurations.first(where: { $0.id == configurationID })
        let provider = config.flatMap { c in llmKit.providers.first(where: { $0.id == c.providerID }) }
        let providerModel = "\(provider?.name ?? "unknown")_\(config?.modelID ?? "unknown")"

        for attempt in 0..<AIService.maxRetries {
            do {
                let preparedRequest = try llmKit.prepareRequest(for: configurationID)

                // Build messages
                let systemMessage = AIService.systemPrompt(for: color)
                let userMessage = AIService.boardStatePrompt(
                    board: board,
                    moveHistory: moveHistory,
                    boardStates: boardStates
                )

                let body = buildRequestBody(
                    prepared: preparedRequest,
                    systemMessage: systemMessage,
                    userMessage: userMessage
                )

                var request = preparedRequest.urlRequest
                let requestData: Data
                do {
                    requestData = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted])
                } catch {
                    throw AIError.invalidResponse("Failed to serialize request body: \(error.localizedDescription)")
                }
                request.httpBody = requestData

                // Log the request
                AILogger.logRequest(
                    gameID: gameID,
                    color: color,
                    gameTurnIndex: gameTurnIndex,
                    providerModel: providerModel,
                    attemptIndex: attempt,
                    requestBody: requestData
                )

                let (data, response) = try await URLSession.shared.data(for: request)

                // Log the response
                AILogger.logResponse(
                    gameID: gameID,
                    color: color,
                    gameTurnIndex: gameTurnIndex,
                    providerModel: providerModel,
                    attemptIndex: attempt,
                    responseBody: data
                )

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw AIError.httpError(statusCode: statusCode)
                }

                let moveText = try extractMoveText(from: data, providerType: preparedRequest.providerType)
                let tokenUsage = extractTokenUsage(from: data, providerType: preparedRequest.providerType)
                let rawResponseText = String(data: data, encoding: .utf8) ?? "(binary data)"

                // Build activity log
                lastActivityLog = AIActivityLog(
                    systemPrompt: systemMessage,
                    userPrompt: userMessage,
                    responseText: rawResponseText,
                    temperature: config?.temperature,
                    thinkingBudget: config?.thinkingBudget,
                    maxOutputTokens: config?.maxOutputTokens,
                    modelName: config?.name ?? "Unknown",
                    providerName: provider?.name ?? "Unknown",
                    tokenUsage: tokenUsage,
                    guidedGenerationResult: nil
                )

                // Parse the move
                guard let parsed = PGNFormatter.parseAIMoveNotation(moveText, on: board) else {
                    let penalty = AIPenalty(
                        reason: "Could not parse move notation: '\(moveText)' (attempt \(attempt + 1))",
                        severity: .warning,
                        timestamp: Date()
                    )
                    penalties.append(penalty)
                    retries += 1
                    continue
                }

                // Validate legality
                guard let legalMove = MoveValidator.findLegalMove(
                    from: parsed.from,
                    to: parsed.to,
                    promotion: parsed.promotion,
                    on: board
                ) else {
                    let penalty = AIPenalty(
                        reason: "Illegal move: '\(moveText)' from \(parsed.from) to \(parsed.to) (attempt \(attempt + 1))",
                        severity: .minor,
                        timestamp: Date()
                    )
                    penalties.append(penalty)
                    retries += 1
                    continue
                }

                // Check/checkmate annotation
                let newBoard = board.applyingMove(legalMove)
                let isCheck = MoveValidator.isKingInCheck(color: board.activeColor.opposite, on: newBoard)
                let isCheckmate = isCheck && MoveValidator.isCheckmate(on: newBoard)
                let annotatedMove = legalMove.withCheckStatus(isCheck: isCheck, isCheckmate: isCheckmate)

                return (annotatedMove, penalties, retries, lastActivityLog)

            } catch {
                let label = error is AIError ? "AI error" : "Network error"
                let penalty = AIPenalty(
                    reason: "\(label): \(error.localizedDescription) (attempt \(attempt + 1))",
                    severity: attempt >= AIService.maxRetries - 1 ? .critical : .major,
                    timestamp: Date()
                )
                penalties.append(penalty)
                retries += 1
                if attempt >= AIService.maxRetries - 1 {
                    throw AIServiceFailure(
                        underlyingError: error,
                        penalties: penalties,
                        retries: retries,
                        lastActivityLog: lastActivityLog
                    )
                }
            }
        }

        throw AIServiceFailure(
            underlyingError: AIError.tooManyRetries,
            penalties: penalties,
            retries: retries,
            lastActivityLog: lastActivityLog
        )
    }

    // MARK: - Request Building

    private func buildRequestBody(prepared: PreparedRequest, systemMessage: String, userMessage: String) -> [String: Any] {
        var body = prepared.baseBody
        body["stream"] = false // We don't use streaming for move requests

        switch prepared.providerType {
        case .anthropic:
            body["system"] = systemMessage
            body["messages"] = [
                ["role": "user", "content": userMessage]
            ]
        case .gemini:
            body["contents"] = [
                ["role": "user", "parts": [["text": "\(systemMessage)\n\n\(userMessage)"]]]
            ]
        case .ollama:
            body["messages"] = [
                ["role": "system", "content": systemMessage],
                ["role": "user", "content": userMessage]
            ]
        default: // OpenAI-compatible, Mistral, etc.
            body["messages"] = [
                ["role": "system", "content": systemMessage],
                ["role": "user", "content": userMessage]
            ]
        }

        return body
    }

    // MARK: - Response Parsing

    private func extractMoveText(from data: Data, providerType: ProviderType) throws -> String {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AIError.invalidResponse("Could not parse JSON response: \(error.localizedDescription)")
        }
        guard let json = jsonObject as? [String: Any] else {
            throw AIError.invalidResponse("JSON response is not a dictionary")
        }

        let text: String?

        switch providerType {
        case .anthropic:
            if let content = json["content"] as? [[String: Any]],
               let firstBlock = content.first,
               let blockText = firstBlock["text"] as? String {
                text = blockText
            } else {
                text = nil
            }
        case .gemini:
            if let candidates = json["candidates"] as? [[String: Any]],
               let first = candidates.first,
               let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let firstPart = parts.first,
               let partText = firstPart["text"] as? String {
                text = partText
            } else {
                text = nil
            }
        default:
            if let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                text = content
            } else {
                text = nil
            }
        }

        guard let moveText = text?.trimmingCharacters(in: .whitespacesAndNewlines), !moveText.isEmpty else {
            throw AIError.invalidResponse("Empty or missing move text in response")
        }

        return cleanMoveText(moveText)
    }

    // MARK: - Token Usage Extraction

    private func extractTokenUsage(from data: Data, providerType: ProviderType) -> TokenUsage? {
        let json: [String: Any]
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            guard let dict = jsonObject as? [String: Any] else { return nil }
            json = dict
        } catch {
            print("[AIService] Failed to parse token usage JSON: \(error)")
            return nil
        }

        switch providerType {
        case .anthropic:
            guard let usage = json["usage"] as? [String: Any] else { return nil }
            return TokenUsage(
                inputTokens: usage["input_tokens"] as? Int,
                outputTokens: usage["output_tokens"] as? Int,
                totalTokens: nil,
                cacheReadTokens: usage["cache_read_input_tokens"] as? Int,
                cacheCreationTokens: usage["cache_creation_input_tokens"] as? Int,
                thinkingTokens: nil
            )
        case .gemini:
            guard let metadata = json["usageMetadata"] as? [String: Any] else { return nil }
            let input = metadata["promptTokenCount"] as? Int
            let output = metadata["candidatesTokenCount"] as? Int
            return TokenUsage(
                inputTokens: input,
                outputTokens: output,
                totalTokens: (input ?? 0) + (output ?? 0),
                cacheReadTokens: nil,
                cacheCreationTokens: nil,
                thinkingTokens: nil
            )
        case .ollama:
            let evalCount = json["eval_count"] as? Int
            let promptEvalCount = json["prompt_eval_count"] as? Int
            if evalCount != nil || promptEvalCount != nil {
                return TokenUsage(
                    inputTokens: promptEvalCount,
                    outputTokens: evalCount,
                    totalTokens: (promptEvalCount ?? 0) + (evalCount ?? 0),
                    cacheReadTokens: nil,
                    cacheCreationTokens: nil,
                    thinkingTokens: nil
                )
            }
            return nil
        default:
            guard let usage = json["usage"] as? [String: Any] else { return nil }
            return TokenUsage(
                inputTokens: usage["prompt_tokens"] as? Int,
                outputTokens: usage["completion_tokens"] as? Int,
                totalTokens: usage["total_tokens"] as? Int,
                cacheReadTokens: nil,
                cacheCreationTokens: nil,
                thinkingTokens: nil
            )
        }
    }

    /// Extracts a move from potentially noisy AI output.
    private func cleanMoveText(_ text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it's short and looks like a move, use it directly
        if cleaned.count <= 6 {
            return cleaned
        }

        // Try to find coordinate notation pattern
        let coordPattern = /[a-h][1-8][a-h][1-8][qrbn]?/
        if let match = cleaned.firstMatch(of: coordPattern) {
            return String(match.output)
        }

        // Try to find SAN pattern (require word boundary to avoid matching substrings of longer text)
        let sanPattern = /\b[KQRBN][a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?[+#]?\b/
        if let match = cleaned.firstMatch(of: sanPattern) {
            return String(match.output)
        }

        // Castling
        if cleaned.contains("O-O-O") || cleaned.contains("0-0-0") { return "O-O-O" }
        if cleaned.contains("O-O") || cleaned.contains("0-0") { return "O-O" }

        // Return first line as fallback
        return cleaned.components(separatedBy: .newlines).first ?? cleaned
    }
}

// MARK: - AI Constants

/// Nonisolated constants for AI configuration.
enum AIConstants {
    static let maxRetries = 3
}

// MARK: - AI Service Failure

/// Wraps the underlying error along with all accumulated retry state so the caller
/// can display penalties, retry counts, and the last activity log even when the service fails.
struct AIServiceFailure: Error, LocalizedError {
    let underlyingError: Error
    let penalties: [AIPenalty]
    let retries: Int
    let lastActivityLog: AIActivityLog?

    var errorDescription: String? {
        underlyingError.localizedDescription
    }
}

// MARK: - AI Errors

enum AIError: Error, LocalizedError {
    case httpError(statusCode: Int)
    case invalidResponse(String)
    case tooManyRetries
    case noConfigurationSelected
    case appleIntelligenceUnavailable

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "HTTP error: \(code)"
        case .invalidResponse(let msg): return "Invalid response: \(msg)"
        case .tooManyRetries: return "AI failed after \(AIConstants.maxRetries) attempts"
        case .noConfigurationSelected: return "No AI model configuration selected"
        case .appleIntelligenceUnavailable: return "Apple Intelligence is not available"
        }
    }
}
