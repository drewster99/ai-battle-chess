import Foundation
import FoundationModels

// MARK: - Chess Move Response (Guided Generation)

/// Structured output for Apple Intelligence chess move generation.
@available(macOS 26.0, *)
@Generable
struct ChessMoveResponse {
    @Guide(description: "Your step-by-step reasoning about the position and possible moves")
    var thinkingLogic: String

    @Guide(description: "The chosen chess move in coordinate notation, e.g. e2e4, g1f3, e7e8q. Must match a move from the given list of valid moves")
    var move: String
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
        gameTurnIndex: Int,
        positionRepetitionCount: Int = 1
    ) async throws -> (result: AIMoveResult, penalties: [AIPenalty], retries: Int, activityLog: AIActivityLog?) {
        guard AppleIntelligenceService.isAvailable else {
            print("[AppleIntelligence] ERROR: Apple Intelligence is not available on this device")
            throw AIError.appleIntelligenceUnavailable
        }

        var penalties: [AIPenalty] = []
        var retries = 0
        var lastActivityLog: AIActivityLog? = nil
        var attempts: [AITurnAttempt] = []

        let systemPrompt = AIService.systemPrompt(for: color, isAppleIntelligence: true, board: board)
        let userPrompt = AIService.boardStatePrompt(board: board, positionRepetitionCount: positionRepetitionCount)

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
                let rawMove = generated.move.trimmingCharacters(in: .whitespacesAndNewlines)

                // Extract comment from move text (e.g. "e2e4 { developing }" → "e2e4", "developing")
                let moveText: String
                var moveComment: String? = nil
                if let openBrace = rawMove.range(of: "{"),
                   let closeBrace = rawMove.range(of: "}") {
                    moveComment = String(rawMove[openBrace.upperBound..<closeBrace.lowerBound]).trimmingCharacters(in: .whitespaces)
                    moveText = String(rawMove[rawMove.startIndex..<openBrace.lowerBound]).trimmingCharacters(in: .whitespaces)
                } else {
                    moveText = rawMove
                }
                // Normalize "e7e8=q" → "e7e8q"
                let cleanedMoveText = moveText.replacingOccurrences(of: "=", with: "")

                let thinking = generated.thinkingLogic

                print("[AppleIntelligence] Response — move: \"\(cleanedMoveText)\" comment: \"\(moveComment ?? "(none)")\" | thinking: \"\(thinking)\"")

                // Log the response to disk
                let responseString = "Move: \(generated.move)\nThinking: \(thinking)\n"
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
                    thinkingLogic: thinking,
                    move: cleanedMoveText
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
                    guidedGenerationResult: guidedResult,
                    attempts: attempts
                )

                // Check for resignation or draw claim
                if let specialResult = AIService.detectSpecialAction(cleanedMoveText, color: color) {
                    print("[AppleIntelligence] SPECIAL ACTION detected: \(specialResult)")
                    print("[AppleIntelligence] ====== END REQUEST ======")
                    attempts.append(AITurnAttempt(thinking: thinking, moveText: cleanedMoveText, comment: moveComment, isValid: true, errorMessage: nil))
                    lastActivityLog?.attempts = attempts
                    switch specialResult {
                    case .resignation(let winner):
                        return (.resignation(winner: winner), penalties, retries, lastActivityLog)
                    default:
                        return (.drawClaim(specialResult), penalties, retries, lastActivityLog)
                    }
                }

                // Parse the move
                guard let parsed = PGNFormatter.parseAIMoveNotation(cleanedMoveText, on: board) else {
                    let reason = "could not parse notation"
                    let correction = AIService.correctionPrompt(badMove: cleanedMoveText, reason: reason, board: board)
                    print("[AppleIntelligence] PARSE FAILURE: \"\(cleanedMoveText)\" — sending correction")

                    attempts.append(AITurnAttempt(thinking: thinking, moveText: cleanedMoveText, comment: moveComment, isValid: false, errorMessage: reason))
                    lastActivityLog?.attempts = attempts
                    currentPrompt = correction
                    penalties.append(AIPenalty(reason: "Could not parse: '\(cleanedMoveText)' (attempt \(attempt + 1))", severity: .warning, timestamp: Date()))
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
                    let reason = "not a legal move"
                    let correction = AIService.correctionPrompt(badMove: cleanedMoveText, reason: reason, board: board)
                    print("[AppleIntelligence] ILLEGAL MOVE: \"\(cleanedMoveText)\" — sending correction")

                    attempts.append(AITurnAttempt(thinking: thinking, moveText: cleanedMoveText, comment: moveComment, isValid: false, errorMessage: reason))
                    lastActivityLog?.attempts = attempts
                    currentPrompt = correction
                    penalties.append(AIPenalty(reason: "Illegal: '\(cleanedMoveText)' \(parsed.from)->\(parsed.to) (attempt \(attempt + 1))", severity: .minor, timestamp: Date()))
                    retries += 1
                    turnsSinceReset += 1
                    continue
                }

                // Success
                let newBoard = board.applyingMove(legalMove)
                let isCheck = MoveValidator.isKingInCheck(color: board.activeColor.opposite, on: newBoard)
                let isCheckmate = isCheck && MoveValidator.isCheckmate(on: newBoard)
                let annotatedMove = legalMove.withCheckStatus(isCheck: isCheck, isCheckmate: isCheckmate, comment: moveComment)

                attempts.append(AITurnAttempt(thinking: thinking, moveText: cleanedMoveText, comment: moveComment, isValid: true, errorMessage: nil))
                lastActivityLog?.attempts = attempts

                print("[AppleIntelligence] SUCCESS: \(legalMove.from)\(legalMove.to) (check=\(isCheck), checkmate=\(isCheckmate), retries=\(retries))")
                print("[AppleIntelligence] ====== END REQUEST ======")

                return (.move(annotatedMove), penalties, retries, lastActivityLog)
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
