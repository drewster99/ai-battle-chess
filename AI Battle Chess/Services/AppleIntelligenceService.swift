import Foundation
import FoundationModels

// MARK: - Chess Move Response (Guided Generation)

/// Structured output for Apple Intelligence chess move generation.
@available(macOS 26.0, *)
@Generable
struct ChessMoveResponse {
    @Guide(description: "Your step-by-step reasoning about the position and possible moves. Remember this is a game, so talk of capturing and protecting pieces and winning, never killing them.")
    var thinkingLogic: String

    @Guide(description: "The chosen chess move in coordinate notation, e.g. e2e4, g1f3, e7e8q. Must match a move from the given list of valid moves")
    var move: String
}

// MARK: - Apple Intelligence Service

/// Uses Apple's on-device Foundation Models framework for chess move generation.
@available(macOS 26.0, *)
@MainActor
final class AppleIntelligenceService {

    /// Maximum retries specifically for guardrail violations before giving up.
    private static let maxGuardrailRetries = 3

    /// Checks if Apple Intelligence / Foundation Models are available on this device.
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Returns true if the error is a FoundationModels guardrail violation.
    private func isGuardrailViolation(_ error: Error) -> Bool {
        if let genError = error as? LanguageModelSession.GenerationError,
           case .guardrailViolation = genError {
            return true
        }
        return false
    }

    /// Builds `GenerationOptions` from an `AppleIntelligenceConfig`.
    private func generationOptions(from config: AppleIntelligenceConfig) -> GenerationOptions {
        let sampling: GenerationOptions.SamplingMode
        switch config.samplingMode {
        case .greedy:
            sampling = .greedy
        case .randomMass(let threshold):
            sampling = .random(probabilityThreshold: threshold)
        case .randomTopN(let k):
            sampling = .random(top: k)
        }
        return GenerationOptions(
            sampling: sampling,
            temperature: config.temperature,
            maximumResponseTokens: config.maximumResponseTokens
        )
    }

    /// Requests a chess move using Apple Intelligence on-device model with guided generation.
    /// Uses a single session so correction messages are part of the conversation history.
    func requestMove(
        board: ChessBoard,
        color: PieceColor,
        config: AppleIntelligenceConfig,
        gameID: UUID,
        gameTurnIndex: Int,
        positionRepetitionCount: Int = 1,
        positionCounts: [ChessBoard.PositionKey: Int] = [:],
        allowResign: Bool = true,
        onError: ((String) -> Void)? = nil
    ) async throws -> (result: AIMoveResult, penalties: [AIPenalty], retries: Int, activityLog: AIActivityLog?) {
        guard AppleIntelligenceService.isAvailable else {
            print("[AppleIntelligence] ERROR: Apple Intelligence is not available on this device")
            throw AIError.appleIntelligenceUnavailable
        }

        var penalties: [AIPenalty] = []
        var retries = 0
        var consecutiveErrors = 0
        var lastActivityLog: AIActivityLog? = nil
        var attempts: [AITurnAttempt] = []

        let systemPrompt = AIService.systemPrompt(for: color, isAppleIntelligence: true, board: board)
        let userPrompt = AIService.boardStatePrompt(board: board, positionRepetitionCount: positionRepetitionCount, positionCounts: positionCounts, allowResign: allowResign)

        let options = generationOptions(from: config)
        let configLabel = "\(config.name) [\(config.samplingDescription), temp=\(config.temperature.map { String(format: "%.2f", $0) } ?? "default"), maxTokens=\(config.maximumResponseTokens.map(String.init) ?? "default")]"

        print("[AppleIntelligence] ====== REQUEST ======")
        print("[AppleIntelligence] Config: \(configLabel)")
        print("[AppleIntelligence] Color: \(color.displayName) | Turn: \(gameTurnIndex) | Game: \(gameID.uuidString.prefix(8))")
        print("[AppleIntelligence] --- SYSTEM PROMPT ---")
        print(systemPrompt)
        print("[AppleIntelligence] --- USER PROMPT ---")
        print(userPrompt)
        print("[AppleIntelligence] --- END PROMPTS ---")

        // Use permissive guardrails since chess naturally involves words like
        // "attack", "capture", "sacrifice" that can trigger safety filters.
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

        // Session for conversation — corrections accumulate in history.
        // Recreated every N turns or on actual errors to avoid context overflow.
        var session = LanguageModelSession(model: model, instructions: systemPrompt)
        var currentPrompt = userPrompt
        var turnsSinceReset = 0
        var guardrailViolationCount = 0

        for attempt in 0..<AIService.maxRetries {
            do {
                // Reset conversation if we've accumulated too many correction turns
                if turnsSinceReset >= AIConstants.conversationResetInterval {
                    print("[AppleIntelligence] Resetting session (hit \(AIConstants.conversationResetInterval)-turn limit)")
                    session = LanguageModelSession(model: model, instructions: systemPrompt)
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
                    generating: ChessMoveResponse.self,
                    options: options
                )

                consecutiveErrors = 0
                let generated = response.content
                let rawMove = generated.move.trimmingCharacters(in: .whitespacesAndNewlines)

                // Extract comment from move text (e.g. "e2e4 { developing }" → "e2e4", "developing")
                let moveText: String
                var moveComment: String? = nil
                if let openBrace = rawMove.range(of: "{"),
                   let closeBrace = rawMove.range(of: "}"),
                   closeBrace.lowerBound >= openBrace.upperBound {
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
                    temperature: config.temperature,
                    thinkingBudget: nil,
                    maxOutputTokens: config.maximumResponseTokens,
                    modelName: config.name,
                    providerName: "Apple Intelligence",
                    tokenUsage: nil,
                    guidedGenerationResult: guidedResult,
                    attempts: attempts
                )

                // Check for resignation or draw claim
                if let specialResult = AIService.detectSpecialAction(cleanedMoveText, color: color) {
                    // Block resignation if not allowed
                    if !allowResign, case .resignation = specialResult {
                        let reason = "resignation is not allowed"
                        let correction = AIService.correctionPrompt(badMove: cleanedMoveText, reason: reason, board: board)
                        print("[AppleIntelligence] BLOCKED RESIGNATION — sending correction")
                        attempts.append(AITurnAttempt(thinking: thinking, moveText: cleanedMoveText, comment: moveComment, isValid: false, errorMessage: reason))
                        lastActivityLog?.attempts = attempts
                        currentPrompt = correction
                        penalties.append(AIPenalty(reason: "Blocked resignation (attempt \(attempt + 1))", severity: .warning, timestamp: Date()))
                        retries += 1
                        turnsSinceReset += 1
                        continue
                    }
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
                let annotatedMove = legalMove.withCheckStatus(isCheck: isCheck, isCheckmate: isCheckmate, comment: moveComment, thinking: thinking)

                attempts.append(AITurnAttempt(thinking: thinking, moveText: cleanedMoveText, comment: moveComment, isValid: true, errorMessage: nil))
                lastActivityLog?.attempts = attempts

                print("[AppleIntelligence] SUCCESS: \(legalMove.from)\(legalMove.to) (check=\(isCheck), checkmate=\(isCheckmate), retries=\(retries))")
                print("[AppleIntelligence] ====== END REQUEST ======")

                return (.move(annotatedMove), penalties, retries, lastActivityLog)
            } catch is CancellationError {
                throw AIServiceFailure(
                    underlyingError: CancellationError(),
                    penalties: penalties,
                    retries: retries,
                    lastActivityLog: lastActivityLog
                )
            } catch where Task.isCancelled {
                throw AIServiceFailure(
                    underlyingError: CancellationError(),
                    penalties: penalties,
                    retries: retries,
                    lastActivityLog: lastActivityLog
                )
            } catch {
                print("[AppleIntelligence] ERROR attempt \(attempt + 1): \(type(of: error)) — \(error.localizedDescription)")

                onError?("\(error.localizedDescription) (attempt \(attempt + 1)/\(AIService.maxRetries))")

                // Detect safety guardrail violations — fail fast instead of retrying 100 times
                if isGuardrailViolation(error) {
                    guardrailViolationCount += 1
                    penalties.append(AIPenalty(
                        reason: "Safety guardrail triggered (attempt \(attempt + 1), violation \(guardrailViolationCount)/\(Self.maxGuardrailRetries))",
                        severity: .critical,
                        timestamp: Date()
                    ))
                    retries += 1

                    if guardrailViolationCount >= Self.maxGuardrailRetries {
                        print("[AppleIntelligence] GUARDRAIL: Safety filter triggered \(guardrailViolationCount) times — giving up")
                        print("[AppleIntelligence] ====== END REQUEST (GUARDRAIL) ======")
                        throw AIServiceFailure(
                            underlyingError: AIError.safetyGuardrail,
                            penalties: penalties,
                            retries: retries,
                            lastActivityLog: lastActivityLog
                        )
                    }

                    // Brief pause then retry with fresh session
                    print("[AppleIntelligence] GUARDRAIL: Retrying with fresh session (\(guardrailViolationCount)/\(Self.maxGuardrailRetries))...")
                    do {
                        try await Task.sleep(for: .seconds(1))
                    } catch {
                        throw AIServiceFailure(
                            underlyingError: CancellationError(),
                            penalties: penalties,
                            retries: retries,
                            lastActivityLog: lastActivityLog
                        )
                    }
                    session = LanguageModelSession(model: model, instructions: systemPrompt)
                    currentPrompt = userPrompt
                    turnsSinceReset = 0
                    continue
                }

                penalties.append(AIPenalty(
                    reason: "Error: \(error.localizedDescription) (attempt \(attempt + 1))",
                    severity: attempt >= AIService.maxRetries - 1 ? .critical : .major,
                    timestamp: Date()
                ))
                retries += 1
                consecutiveErrors += 1
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

                // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s, 60s max
                guard !Task.isCancelled else {
                    throw AIServiceFailure(
                        underlyingError: CancellationError(),
                        penalties: penalties,
                        retries: retries,
                        lastActivityLog: lastActivityLog
                    )
                }
                let delay = min(pow(2.0, Double(consecutiveErrors - 1)), 60.0)
                print("[AppleIntelligence] Backing off \(String(format: "%.0f", delay))s before retry...")
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    throw AIServiceFailure(
                        underlyingError: CancellationError(),
                        penalties: penalties,
                        retries: retries,
                        lastActivityLog: lastActivityLog
                    )
                }

                // On error, reset to a fresh session for next attempt
                session = LanguageModelSession(model: model, instructions: systemPrompt)
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
