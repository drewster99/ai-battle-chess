import Foundation
import FoundationModels

// MARK: - Chess Move Response (Guided Generation)

/// Structured output for Apple Intelligence chess move generation.
@available(macOS 26.0, *)
@Generable
struct ChessMoveResponse {
    @Guide(description: "Your step-by-step thinking and reasoning about the position and candidate moves")
    var thinkingLogic: String

    @Guide(description: "The chosen chess move in coordinate notation, e.g. e2e4, g1f3, e7e8q")
    var move: String

    @Guide(description: "Brief comment about the move, e.g. 'Developing the knight to control the center'")
    var comment: String?
}

// MARK: - Apple Intelligence Service

/// Uses Apple's on-device Foundation Models framework for chess move generation.
@available(macOS 26.0, *)
@MainActor
final class AppleIntelligenceService {

    /// Checks if Apple Intelligence / Foundation Models are available on this device.
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Requests a chess move using Apple Intelligence on-device model with guided generation.
    func requestMove(
        board: ChessBoard,
        moveHistory: [ChessMove],
        boardStates: [ChessBoard],
        color: PieceColor,
        gameID: UUID,
        gameTurnIndex: Int
    ) async throws -> (move: ChessMove, penalties: [AIPenalty], retries: Int, activityLog: AIActivityLog?) {
        guard AppleIntelligenceService.isAvailable else {
            throw AIError.appleIntelligenceUnavailable
        }

        var penalties: [AIPenalty] = []
        var retries = 0
        var lastActivityLog: AIActivityLog? = nil

        let systemPrompt = AIService.systemPrompt(for: color)

        for attempt in 0..<AIService.maxRetries {
            // Create a fresh session per attempt to avoid accumulating failed turns in context
            let session = LanguageModelSession(instructions: systemPrompt)

            do {
                let userPrompt = AIService.boardStatePrompt(
                    board: board,
                    moveHistory: moveHistory,
                    boardStates: boardStates
                )

                // Log the request prompt to disk
                let promptData = Data(userPrompt.utf8)
                AILogger.logRequest(
                    gameID: gameID,
                    color: color,
                    gameTurnIndex: gameTurnIndex,
                    providerModel: "apple_intelligence",
                    attemptIndex: attempt,
                    requestBody: promptData
                )

                let response = try await session.respond(
                    to: userPrompt,
                    generating: ChessMoveResponse.self
                )

                let generated = response.content
                let moveText = generated.move.trimmingCharacters(in: .whitespacesAndNewlines)

                // Log the response to disk
                let responseString = "Move: \(generated.move)\nThinking: \(generated.thinkingLogic)\nComment: \(generated.comment ?? "none")"
                let responseData = Data(responseString.utf8)
                AILogger.logResponse(
                    gameID: gameID,
                    color: color,
                    gameTurnIndex: gameTurnIndex,
                    providerModel: "apple_intelligence",
                    attemptIndex: attempt,
                    responseBody: responseData
                )

                // Build guided generation result
                let guidedResult = AIGuidedGenerationResult(
                    thinkingLogic: generated.thinkingLogic,
                    move: generated.move,
                    comment: generated.comment
                )

                // Build activity log
                lastActivityLog = AIActivityLog(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    responseText: "Move: \(generated.move)\nThinking: \(generated.thinkingLogic)\nComment: \(generated.comment ?? "none")",
                    temperature: nil,
                    thinkingBudget: nil,
                    maxOutputTokens: nil,
                    modelName: "Apple Intelligence",
                    providerName: "Apple",
                    tokenUsage: nil,
                    guidedGenerationResult: guidedResult
                )

                // Parse the move
                guard let parsed = PGNFormatter.parseAIMoveNotation(moveText, on: board) else {
                    let penalty = AIPenalty(
                        reason: "Apple Intelligence: could not parse '\(moveText)' (attempt \(attempt + 1))",
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
                        reason: "Apple Intelligence: illegal move '\(moveText)' (attempt \(attempt + 1))",
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
                let penalty = AIPenalty(
                    reason: "Apple Intelligence error: \(error.localizedDescription) (attempt \(attempt + 1))",
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
}
