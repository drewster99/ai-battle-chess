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
    /// Uses a single session so correction messages are part of the conversation history.
    func requestMove(
        board: ChessBoard,
        color: PieceColor,
        gameID: UUID,
        gameTurnIndex: Int
    ) async throws -> (move: ChessMove, penalties: [AIPenalty], retries: Int, activityLog: AIActivityLog?) {
        guard AppleIntelligenceService.isAvailable else {
            print("[AppleIntelligence] ERROR: Apple Intelligence is not available on this device")
            throw AIError.appleIntelligenceUnavailable
        }

        var penalties: [AIPenalty] = []
        var retries = 0
        var lastActivityLog: AIActivityLog? = nil

        let systemPrompt = AIService.systemPrompt(for: color)
        let userPrompt = AIService.boardStatePrompt(board: board)

        print("[AppleIntelligence] ====== REQUEST ======")
        print("[AppleIntelligence] Color: \(color.displayName) | Turn: \(gameTurnIndex) | Game: \(gameID.uuidString.prefix(8))")
        print("[AppleIntelligence] --- SYSTEM PROMPT ---")
        print(systemPrompt)
        print("[AppleIntelligence] --- USER PROMPT ---")
        print(userPrompt)
        print("[AppleIntelligence] --- END PROMPTS ---")

        // Session for conversation — corrections accumulate in history.
        // Recreated every N turns or on actual errors to avoid context overflow.
        var session = LanguageModelSession(instructions: systemPrompt)
        var currentPrompt = userPrompt
        var turnsSinceReset = 0

        for attempt in 0..<AIService.maxRetries {
            do {
                // Reset conversation if we've accumulated too many correction turns
                if turnsSinceReset >= AIConstants.conversationResetInterval {
                    print("[AppleIntelligence] Resetting session (hit \(AIConstants.conversationResetInterval)-turn limit)")
                    session = LanguageModelSession(instructions: systemPrompt)
                    currentPrompt = userPrompt
                    turnsSinceReset = 0
                }

                print("[AppleIntelligence] --- ATTEMPT \(attempt + 1)/\(AIService.maxRetries) ---")
                if attempt > 0 {
                    print("[AppleIntelligence] Correction prompt: \(currentPrompt)")
                }

                // Log the request prompt to disk
                AILogger.logRequest(
                    gameID: gameID,
                    color: color,
                    gameTurnIndex: gameTurnIndex,
                    providerModel: "apple_intelligence",
                    attemptIndex: attempt,
                    requestBody: Data(currentPrompt.utf8)
                )

                let response = try await session.respond(
                    to: currentPrompt,
                    generating: ChessMoveResponse.self
                )

                let generated = response.content
                let moveText = generated.move.trimmingCharacters(in: .whitespacesAndNewlines)

                print("[AppleIntelligence] Response — move: \"\(moveText)\" | thinking: \"\(generated.thinkingLogic)\" | comment: \"\(generated.comment ?? "(nil)")\"")

                // Log the response to disk
                let responseString = "Move: \(generated.move)\nThinking: \(generated.thinkingLogic)\nComment: \(generated.comment ?? "none")"
                AILogger.logResponse(
                    gameID: gameID,
                    color: color,
                    gameTurnIndex: gameTurnIndex,
                    providerModel: "apple_intelligence",
                    attemptIndex: attempt,
                    responseBody: Data(responseString.utf8)
                )

                // Build activity log
                let guidedResult = AIGuidedGenerationResult(
                    thinkingLogic: generated.thinkingLogic,
                    move: generated.move,
                    comment: generated.comment
                )
                lastActivityLog = AIActivityLog(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    responseText: responseString,
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
                    let correction = AIService.correctionPrompt(badMove: moveText, reason: "could not parse notation", board: board)
                    print("[AppleIntelligence] PARSE FAILURE: \"\(moveText)\" — sending correction")

                    currentPrompt = correction
                    penalties.append(AIPenalty(
                        reason: "Could not parse: '\(moveText)' (attempt \(attempt + 1))",
                        severity: .warning,
                        timestamp: Date()
                    ))
                    retries += 1
                    turnsSinceReset += 1
                    continue
                }

                print("[AppleIntelligence] Parsed: \(parsed.from)->\(parsed.to) promotion=\(parsed.promotion?.notation ?? "none")")

                // Validate legality
                guard let legalMove = MoveValidator.findLegalMove(
                    from: parsed.from,
                    to: parsed.to,
                    promotion: parsed.promotion,
                    on: board
                ) else {
                    let correction = AIService.correctionPrompt(badMove: moveText, reason: "not a legal move", board: board)
                    print("[AppleIntelligence] ILLEGAL MOVE: \"\(moveText)\" — sending correction")

                    currentPrompt = correction
                    penalties.append(AIPenalty(
                        reason: "Illegal: '\(moveText)' \(parsed.from)->\(parsed.to) (attempt \(attempt + 1))",
                        severity: .minor,
                        timestamp: Date()
                    ))
                    retries += 1
                    turnsSinceReset += 1
                    continue
                }

                // Success
                let newBoard = board.applyingMove(legalMove)
                let isCheck = MoveValidator.isKingInCheck(color: board.activeColor.opposite, on: newBoard)
                let isCheckmate = isCheck && MoveValidator.isCheckmate(on: newBoard)
                let annotatedMove = legalMove.withCheckStatus(isCheck: isCheck, isCheckmate: isCheckmate)

                print("[AppleIntelligence] SUCCESS: \(legalMove.from)\(legalMove.to) (check=\(isCheck), checkmate=\(isCheckmate), retries=\(retries))")
                print("[AppleIntelligence] ====== END REQUEST ======")

                return (annotatedMove, penalties, retries, lastActivityLog)
            } catch {
                print("[AppleIntelligence] ERROR attempt \(attempt + 1): \(type(of: error)) — \(error.localizedDescription)")

                penalties.append(AIPenalty(
                    reason: "Error: \(error.localizedDescription) (attempt \(attempt + 1))",
                    severity: attempt >= AIService.maxRetries - 1 ? .critical : .major,
                    timestamp: Date()
                ))
                retries += 1
                if attempt >= AIService.maxRetries - 1 {
                    print("[AppleIntelligence] FATAL: All \(AIService.maxRetries) attempts failed")
                    print("[AppleIntelligence] ====== END REQUEST (FAILURE) ======")
                    throw AIServiceFailure(
                        underlyingError: error,
                        penalties: penalties,
                        retries: retries,
                        lastActivityLog: lastActivityLog
                    )
                }
                // On error, reset to a fresh session for next attempt
                session = LanguageModelSession(instructions: systemPrompt)
                currentPrompt = userPrompt
                turnsSinceReset = 0
            }
        }

        print("[AppleIntelligence] FATAL: Exhausted \(AIService.maxRetries) attempts")
        print("[AppleIntelligence] Penalties: \(penalties.map(\.reason).joined(separator: "; "))")
        print("[AppleIntelligence] ====== END REQUEST (TOO MANY RETRIES) ======")

        throw AIServiceFailure(
            underlyingError: AIError.tooManyRetries,
            penalties: penalties,
            retries: retries,
            lastActivityLog: lastActivityLog
        )
    }
}
