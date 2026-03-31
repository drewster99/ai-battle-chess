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
            print("[AppleIntelligence] ERROR: Apple Intelligence is not available on this device")
            throw AIError.appleIntelligenceUnavailable
        }

        var penalties: [AIPenalty] = []
        var retries = 0
        var lastActivityLog: AIActivityLog? = nil

        let systemPrompt = AIService.systemPrompt(for: color)

        print("[AppleIntelligence] ====== REQUEST ======")
        print("[AppleIntelligence] Color: \(color.displayName) | Turn: \(gameTurnIndex) | Game: \(gameID.uuidString.prefix(8))")
        print("[AppleIntelligence] --- SYSTEM PROMPT ---")
        print(systemPrompt)
        print("[AppleIntelligence] --- END SYSTEM PROMPT ---")

        for attempt in 0..<AIService.maxRetries {
            // Create a fresh session per attempt to avoid accumulating failed turns in context
            let session = LanguageModelSession(instructions: systemPrompt)

            do {
                let userPrompt = AIService.boardStatePrompt(
                    board: board,
                    moveHistory: moveHistory,
                    boardStates: boardStates
                )

                print("[AppleIntelligence] --- ATTEMPT \(attempt + 1)/\(AIService.maxRetries) ---")
                print("[AppleIntelligence] --- USER PROMPT ---")
                print(userPrompt)
                print("[AppleIntelligence] --- END USER PROMPT ---")
                print("[AppleIntelligence] Calling session.respond(generating: ChessMoveResponse.self)...")

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

                print("[AppleIntelligence] --- RESPONSE ---")
                print("[AppleIntelligence] Raw move field: \"\(generated.move)\"")
                print("[AppleIntelligence] Trimmed move:   \"\(moveText)\"")
                print("[AppleIntelligence] Thinking:       \"\(generated.thinkingLogic)\"")
                print("[AppleIntelligence] Comment:        \"\(generated.comment ?? "(nil)")\"")
                print("[AppleIntelligence] --- END RESPONSE ---")

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
                    let reason = "Apple Intelligence: could not parse '\(moveText)' (attempt \(attempt + 1))"
                    print("[AppleIntelligence] PARSE FAILURE: \(reason)")

                    // Also dump legal moves for debugging
                    let legalMoves = MoveValidator.allLegalMoves(for: board)
                    let legalDescriptions = legalMoves.map { "\($0.from)\($0.to)" }
                    print("[AppleIntelligence] Legal moves for \(color.displayName): \(legalDescriptions.joined(separator: ", "))")

                    let penalty = AIPenalty(
                        reason: reason,
                        severity: .warning,
                        timestamp: Date()
                    )
                    penalties.append(penalty)
                    retries += 1
                    continue
                }

                print("[AppleIntelligence] Parsed: from=\(parsed.from) to=\(parsed.to) promotion=\(parsed.promotion?.notation ?? "none")")

                // Validate legality
                guard let legalMove = MoveValidator.findLegalMove(
                    from: parsed.from,
                    to: parsed.to,
                    promotion: parsed.promotion,
                    on: board
                ) else {
                    let reason = "Apple Intelligence: illegal move '\(moveText)' from \(parsed.from) to \(parsed.to) (attempt \(attempt + 1))"
                    print("[AppleIntelligence] ILLEGAL MOVE: \(reason)")

                    let legalMoves = MoveValidator.allLegalMoves(for: board)
                    let legalDescriptions = legalMoves.map { "\($0.from)\($0.to)" }
                    print("[AppleIntelligence] Legal moves for \(color.displayName): \(legalDescriptions.joined(separator: ", "))")

                    let penalty = AIPenalty(
                        reason: reason,
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

                print("[AppleIntelligence] SUCCESS: \(legalMove.from)\(legalMove.to) (check=\(isCheck), checkmate=\(isCheckmate))")
                print("[AppleIntelligence] Penalties this turn: \(penalties.count), Retries: \(retries)")
                print("[AppleIntelligence] ====== END REQUEST ======")

                return (annotatedMove, penalties, retries, lastActivityLog)
            } catch {
                let reason = "Apple Intelligence error: \(error.localizedDescription) (attempt \(attempt + 1))"
                print("[AppleIntelligence] ERROR on attempt \(attempt + 1): \(error)")
                print("[AppleIntelligence] Error type: \(type(of: error))")
                print("[AppleIntelligence] Error description: \(error.localizedDescription)")

                let penalty = AIPenalty(
                    reason: reason,
                    severity: attempt >= AIService.maxRetries - 1 ? .critical : .major,
                    timestamp: Date()
                )
                penalties.append(penalty)
                retries += 1
                if attempt >= AIService.maxRetries - 1 {
                    print("[AppleIntelligence] FATAL: All \(AIService.maxRetries) attempts failed with errors")
                    print("[AppleIntelligence] All penalties: \(penalties.map(\.reason).joined(separator: "; "))")
                    print("[AppleIntelligence] ====== END REQUEST (FAILURE) ======")
                    throw AIServiceFailure(
                        underlyingError: error,
                        penalties: penalties,
                        retries: retries,
                        lastActivityLog: lastActivityLog
                    )
                }
            }
        }

        print("[AppleIntelligence] FATAL: Exhausted all \(AIService.maxRetries) attempts (parse/illegal failures)")
        print("[AppleIntelligence] All penalties: \(penalties.map(\.reason).joined(separator: "; "))")
        print("[AppleIntelligence] ====== END REQUEST (TOO MANY RETRIES) ======")

        throw AIServiceFailure(
            underlyingError: AIError.tooManyRetries,
            penalties: penalties,
            retries: retries,
            lastActivityLog: lastActivityLog
        )
    }
}
