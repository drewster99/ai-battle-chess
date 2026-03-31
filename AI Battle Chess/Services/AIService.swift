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

    static func systemPrompt(for color: PieceColor, isAppleIntelligence: Bool = false, board: ChessBoard? = nil) -> String {
        let yourPieces: String
        let theirPieces: String
        if color == .white {
            yourPieces = "Your pieces (White) are uppercase: K Q R B N P"
            theirPieces = "Black's pieces are lowercase: k q r b n p"
        } else {
            yourPieces = "Your pieces (Black) are lowercase: k q r b n p"
            theirPieces = "White's pieces are uppercase: K Q R B N P"
        }

        // Check if castling is still possible for this player
        let isCastlingAvailable: Bool
        if let board {
            if color == .white {
                isCastlingAvailable = board.whiteCanCastleKingside || board.whiteCanCastleQueenside
            } else {
                isCastlingAvailable = board.blackCanCastleKingside || board.blackCanCastleQueenside
            }
        } else {
            isCastlingAvailable = true // Default to true when no board is provided
        }

        let isAIAppleIntelligence = isAppleIntelligence

        let castlingExample = color == .white
            ? "e1g1 (kingside) or e1c1 (queenside)"
            : "e8g8 (kingside) or e8c8 (queenside)"

        let resignExample = color == .white
            ? "0-1 {white resigns}"
            : "1-0 {black resigns}"

        let outputResponseFormat = isAIAppleIntelligence
        ? """
        thoughtLogic String - your through process
        move String: A single line of text, no leading/trailing whitespace, in one of these two formats:
        - Format 1: <move>
        - Format 2: <move> {<optional comment>}
        
        Format 1 is preferred.
        
        Example using preferred format 1: b8c6
        Example using format 2 (with optional comment): e2d3 { capture knight }
        """
        : """
        Output one single line of text, no leading/trailing whitespace in one of these 2 formats:
        - Format 1: <move>
        - Format 2: <move> {<optional comment>}
        
        Format 1 is preferred.
        
        Example using preferred format 1: b8c6
        Example using format 2 (with optional comment): e2d3 { capture knight }
        """

        return """
        # You are playing chess as \(color.displayName).

        ## Playing Chess
        Here's a basic overview of how to play:

        ### Objective:
        The objective is to checkmate your opponent's king, meaning the
        king is in a position that cannot escape capture and is under threat
        of being captured, while keeping your own king safe.

        ### Setup:
        1. **Board and Pieces:**
        - The board is an 8x8 grid with alternating dark and light squares.
        - Each player starts with 16 pieces: one king, one queen, two
        rooks, two knights, two bishops, and eight pawns.

        2. **Initial Setup:**
        - Place the pieces on their starting squares:
            - **Back Row (from the player's perspective):** King on e1, Queen
        on d1, Rooks on a1 and h1, Bishops on c1 and g1, Knights on b1 and
        f1, and Pawns on e2, d2, c2, and b2.
            - White queen is on a white square, black queen is on a dark square

        ### Basic Rules:
        1. **Movement:**
        - **King:** Moves one square in any direction (horizontal, vertical or diagonal). The king cannot move to a square that puts it in "check", meaning it is under direct threat from an opponent's piece.
        - **Queen:** Moves any number of squares in any direction
        (horizontal, vertical, or diagonal).
        - **Rook:** Moves any number of squares along a rank or file (not diagonal)
        - **Bishop:** Moves any number of squares diagonally.
        - **Knight:** Moves in an "L" shape: two squares in one direction
        and then one square perpendicular, or vice versa. Knights can jump
        over other pieces.
        - **Pawn:** Moves forward one square, but captures diagonally forward. On
        its first move, a pawn can move two squares forward. Pans can never move backward.

        2. **Special Moves:**
        - **Castling:** Castling is a special move where both the king and a rock
        are moved.
          - What is castling?
            - The king moves two spaces toward the rook
            - The rook moves to the spot adjacent to king on the opposite side of the king
          - You can castle only if all of the following are true:
            - The king and the rook involved have never moved this game
            - All squares between the king and rook must be empty
            - The king cannot "pass through" a square which would put him in check
            - The king cannot land on a square that puts him in check
          - How to indicate castling
            - You indicate castling by indicating the King's move
        - **En Passant:** A pawn capture rule that allows a pawn to be
        captured as if it had moved two squares forward from its starting
        position, provided certain conditions are met.

        3. **Capturing Opponent's Pieces**
        - In general, a piece which moves to a square already occupied by an opponent's
        piece "captures" that piece -- removing it from the board.
        - Pawns can only capture when moving diagonally, and they can only move diagonally
        when capturing an opponent's piece
        - Approximate "values" of captured pieces
          - Chess does not keep points or assign values to pieces, but the comparative
        usefulness and power of pieces in chess have led to this generally accepted table
        of values for each piece. Consider these values as a rough guide when deciding
        which of your opponent's pieces to capture and which of your own to protect:
            - Pawn: 1
            - Knight: 3
            - Bishop: 3
            - Rook: 5
            - Queen: 9
            - King: 99999999 (priceless)
        
        4. **Promotion of Pawn**
        - If a pawn advances all the way across the board to the opponent's back row (row 8 when playing as black, or row 1 when playing as white), the pawn can be promoted to any other piece. Typically a Queen is chosen, since it has the combined power of all other pieces but the rook. 
        - Indicating pawn promotion
          - Append "=Q" to the end of the move.  Examples:
            - Move from e7 to e8 and promote to Queen: e7e8q
            - Move from b2 to a1 (capturing) and promoting to Knight: b2a1n
        
        5. **50 Move Rule**
        - If 50 consecutive turns by each player (100 total moves, which are called 'half moves') happen without the movement
        of any pawns and without any pieces being captured, the nextmove will automatically be indicated as a draw by, like this: "½–½ {50 move rule}" as their move.
        
        6. **Winning the Game:**
        - **Checkmate:** The king is in check and cannot escape capture.
        - **Stalemate:** A situation where the player cannot move legally
        or their king is in check but cannot be captured.
        - **Draw:** Possible through stalemate, threefold repetition,
        insufficient material, or agreed upon by players.

        ## PROMPT INPUT FORMAT
        - You'll receive the current layout of the board in a labeled 8x8 grid
          - \(yourPieces)
          - \(theirPieces)
        - You'll receive a list of valid moves
          - Example: VALID MOVES: e2e3, e2e4
        
        ## OUTPUT MOVE FORMAT — CRITICAL
        Your output is processed by an automated chess system, so your output MUST
        EXACTLY match the REQUIRED format.
        
        Move format is lowercase text "source square" + "destination square" + promotion piece (if applicable)
        - Examples: e7e5, g8f6, e2e1q
        \(isCastlingAvailable ? "- Castling examples: \(castlingExample)" : "")
        - Resigning: \(resignExample)
        - NEVER use algebraic notation (e.g. Nf6, Bxe5, O-O)

        ## OUTPUT RESPONSE FORMAT
        \(outputResponseFormat)
        """
    }

    static func boardStatePrompt(board: ChessBoard) -> String {
        var prompt = ""

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

        // 50-move rule counter
        if board.halfMoveClock > 0 {
            let fullMoves = board.halfMoveClock / 2
            prompt += "\n50-move rule: \(fullMoves)/50 consecutive move pairs without a pawn move or capture.\n"
        }

        // Legal moves list — the AI MUST pick one of these
        let moveStrings = legalMovesStringList(for: board)
        prompt += "\nYour legal moves: \(moveStrings.joined(separator: ", "))\n"
        prompt += "Reply with exactly one move from this list.\n"

        return prompt
    }

    /// Returns legal moves as coordinate notation strings for the active color.
    static func legalMovesStringList(for board: ChessBoard) -> [String] {
        MoveValidator.allLegalMoves(for: board).map { move -> String in
            var s = "\(move.from)\(move.to)"
            if let promo = move.promotionType {
                s += promo.notation.lowercased()
            }
            return s
        }
    }

    /// Builds a correction message to send back when the AI picks an illegal/unparseable move.
    static func correctionPrompt(badMove: String, reason: String, board: ChessBoard) -> String {
        let legalMoves = legalMovesStringList(for: board)
        return "Illegal move: \"\(badMove)\" — \(reason). Choose one of: \(legalMoves.joined(separator: ", "))"
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

    /// Requests a move from the AI using a multi-turn conversation.
    /// When the AI returns an illegal or unparseable move, a correction message is appended
    /// to the conversation so the AI can see its mistake and try again.
    func requestMove(
        configurationID: UUID,
        board: ChessBoard,
        color: PieceColor,
        gameID: UUID,
        gameTurnIndex: Int
    ) async throws -> (result: AIMoveResult, penalties: [AIPenalty], retries: Int, activityLog: AIActivityLog?) {
        var penalties: [AIPenalty] = []
        var retries = 0
        var lastActivityLog: AIActivityLog? = nil
        var attempts: [AITurnAttempt] = []

        // Look up configuration details
        let config = llmKit.configurations.first(where: { $0.id == configurationID })
        let provider = config.flatMap { c in llmKit.providers.first(where: { $0.id == c.providerID }) }
        let providerModel = "\(provider?.name ?? "unknown")_\(config?.modelID ?? "unknown")"
        let modelLabel = config?.name ?? providerModel

        let systemMessage = AIService.systemPrompt(for: color, board: board)
        let userMessage = AIService.boardStatePrompt(board: board)

        print("[AIService] ====== REQUEST ======")
        print("[AIService] \(modelLabel) | \(color.displayName) | Turn \(gameTurnIndex) | Game \(gameID.uuidString.prefix(8))")
        print("[AIService] --- SYSTEM PROMPT ---")
        print(systemMessage)
        print("[AIService] --- USER PROMPT ---")
        print(userMessage)
        print("[AIService] --- END PROMPTS ---")

        // Build conversation history — corrections append as assistant + user turns.
        // Reset every N turns to avoid context window overflow.
        var conversationMessages: [ConversationMessage] = [
            ConversationMessage(role: .user, content: userMessage)
        ]
        var turnsSinceReset = 0

        for attempt in 0..<AIService.maxRetries {
            do {
                // Reset conversation if we've accumulated too many correction turns
                if turnsSinceReset >= AIConstants.conversationResetInterval {
                    print("[AIService] Resetting conversation (hit \(AIConstants.conversationResetInterval)-turn limit)")
                    conversationMessages = [
                        ConversationMessage(role: .user, content: userMessage)
                    ]
                    turnsSinceReset = 0
                }

                let preparedRequest = try llmKit.prepareRequest(for: configurationID)

                let body = buildConversationBody(
                    prepared: preparedRequest,
                    systemMessage: systemMessage,
                    messages: conversationMessages
                )

                var request = preparedRequest.urlRequest
                let requestData: Data
                do {
                    requestData = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted])
                } catch {
                    throw AIError.invalidResponse("Failed to serialize request body: \(error.localizedDescription)")
                }
                request.httpBody = requestData

                AILogger.logRequest(
                    gameID: gameID,
                    color: color,
                    gameTurnIndex: gameTurnIndex,
                    providerModel: providerModel,
                    attemptIndex: attempt,
                    requestBody: requestData
                )

                print("[AIService] Attempt \(attempt + 1)/\(AIService.maxRetries) — sending request...")

                let (data, response) = try await URLSession.shared.data(for: request)

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
                    print("[AIService] HTTP \(statusCode) error")
                    throw AIError.httpError(statusCode: statusCode)
                }

                let extracted = try extractMoveText(from: data, providerType: preparedRequest.providerType)
                let moveText = extracted.move
                let moveComment = extracted.comment
                let tokenUsage = extractTokenUsage(from: data, providerType: preparedRequest.providerType)
                let rawResponseText = String(data: data, encoding: .utf8) ?? "(binary data)"

                print("[AIService] Response move: \"\(moveText)\" comment: \"\(moveComment ?? "(none)")\"")

                // Check for resignation or draw claim before parsing as a move
                if let specialResult = AIService.detectSpecialAction(rawResponseText, color: color) {
                    print("[AIService] SPECIAL ACTION detected: \(specialResult)")
                    print("[AIService] ====== END REQUEST ======")
                    attempts.append(AITurnAttempt(thinking: nil, moveText: moveText, comment: moveComment, isValid: true, errorMessage: nil))
                    let activityLog = AIActivityLog(
                        systemPrompt: systemMessage,
                        userPrompt: userMessage,
                        responseText: rawResponseText,
                        temperature: config?.temperature,
                        thinkingBudget: config?.thinkingBudget,
                        maxOutputTokens: config?.maxOutputTokens,
                        modelName: config?.name ?? "Unknown",
                        providerName: provider?.name ?? "Unknown",
                        tokenUsage: tokenUsage,
                        guidedGenerationResult: nil,
                        attempts: attempts
                    )
                    switch specialResult {
                    case .resignation(let winner):
                        return (.resignation(winner: winner), penalties, retries, activityLog)
                    default:
                        return (.drawClaim(specialResult), penalties, retries, activityLog)
                    }
                }

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
                    guidedGenerationResult: nil,
                    attempts: attempts
                )

                // Parse the move
                guard let parsed = PGNFormatter.parseAIMoveNotation(moveText, on: board) else {
                    let reason = "could not parse notation"
                    let correction = AIService.correctionPrompt(badMove: moveText, reason: reason, board: board)
                    print("[AIService] PARSE FAILURE: \"\(moveText)\" — sending correction")

                    attempts.append(AITurnAttempt(thinking: nil, moveText: moveText, comment: moveComment, isValid: false, errorMessage: reason))
                    conversationMessages.append(ConversationMessage(role: .assistant, content: moveText))
                    conversationMessages.append(ConversationMessage(role: .user, content: correction))

                    penalties.append(AIPenalty(reason: "Could not parse: '\(moveText)' (attempt \(attempt + 1))", severity: .warning, timestamp: Date()))
                    retries += 1
                    turnsSinceReset += 1
                    continue
                }

                // Validate legality
                guard let legalMove = MoveValidator.findLegalMove(
                    from: parsed.from,
                    to: parsed.to,
                    promotion: parsed.promotion,
                    on: board
                ) else {
                    let reason = "not a legal move"
                    let correction = AIService.correctionPrompt(badMove: moveText, reason: reason, board: board)
                    print("[AIService] ILLEGAL MOVE: \"\(moveText)\" (\(parsed.from)->\(parsed.to)) — sending correction")

                    attempts.append(AITurnAttempt(thinking: nil, moveText: moveText, comment: moveComment, isValid: false, errorMessage: reason))
                    conversationMessages.append(ConversationMessage(role: .assistant, content: moveText))
                    conversationMessages.append(ConversationMessage(role: .user, content: correction))

                    penalties.append(AIPenalty(reason: "Illegal: '\(moveText)' \(parsed.from)->\(parsed.to) (attempt \(attempt + 1))", severity: .minor, timestamp: Date()))
                    retries += 1
                    turnsSinceReset += 1
                    continue
                }

                // Success
                let newBoard = board.applyingMove(legalMove)
                let isCheck = MoveValidator.isKingInCheck(color: board.activeColor.opposite, on: newBoard)
                let isCheckmate = isCheck && MoveValidator.isCheckmate(on: newBoard)
                let annotatedMove = legalMove.withCheckStatus(isCheck: isCheck, isCheckmate: isCheckmate, comment: moveComment)

                attempts.append(AITurnAttempt(thinking: nil, moveText: moveText, comment: moveComment, isValid: true, errorMessage: nil))
                lastActivityLog?.attempts = attempts

                print("[AIService] SUCCESS: \(legalMove.from)\(legalMove.to) (check=\(isCheck), checkmate=\(isCheckmate))")
                print("[AIService] Penalties: \(penalties.count), Retries: \(retries)")
                print("[AIService] ====== END REQUEST ======")

                return (.move(annotatedMove), penalties, retries, lastActivityLog)

            } catch {
                let label = error is AIError ? "AI error" : "Network error"
                print("[AIService] ERROR attempt \(attempt + 1): \(label) — \(error.localizedDescription)")

                let penalty = AIPenalty(
                    reason: "\(label): \(error.localizedDescription) (attempt \(attempt + 1))",
                    severity: attempt >= AIService.maxRetries - 1 ? .critical : .major,
                    timestamp: Date()
                )
                penalties.append(penalty)
                retries += 1
                if attempt >= AIService.maxRetries - 1 {
                    print("[AIService] FATAL: All \(AIService.maxRetries) attempts failed")
                    print("[AIService] ====== END REQUEST (FAILURE) ======")
                    throw AIServiceFailure(
                        underlyingError: error,
                        penalties: penalties,
                        retries: retries,
                        lastActivityLog: lastActivityLog
                    )
                }
            }
        }

        print("[AIService] FATAL: Exhausted \(AIService.maxRetries) attempts (parse/illegal failures)")
        print("[AIService] All penalties: \(penalties.map(\.reason).joined(separator: "; "))")
        print("[AIService] ====== END REQUEST (TOO MANY RETRIES) ======")

        throw AIServiceFailure(
            underlyingError: AIError.tooManyRetries,
            penalties: penalties,
            retries: retries,
            lastActivityLog: lastActivityLog
        )
    }

    // MARK: - Conversation Message

    private struct ConversationMessage {
        enum Role { case user, assistant }
        let role: Role
        let content: String
    }

    // MARK: - Request Building

    private func buildConversationBody(prepared: PreparedRequest, systemMessage: String, messages: [ConversationMessage]) -> [String: Any] {
        var body = prepared.baseBody
        body["stream"] = false

        let apiMessages: [[String: Any]] = messages.map { msg in
            let role = msg.role == .user ? "user" : "assistant"
            return ["role": role, "content": msg.content]
        }

        switch prepared.providerType {
        case .anthropic:
            body["system"] = systemMessage
            body["messages"] = apiMessages
        case .gemini:
            // Gemini: prepend system to first user message, map roles
            var contents: [[String: Any]] = []
            var injectedSystem = false
            for msg in messages {
                let role = msg.role == .user ? "user" : "model"
                var content = msg.content
                if !injectedSystem && msg.role == .user {
                    content = systemMessage + "\n\n" + content
                    injectedSystem = true
                }
                contents.append(["role": role, "parts": [["text": content]]])
            }
            body["contents"] = contents
        default: // OpenAI-compatible, Ollama, Mistral, etc.
            var allMessages: [[String: Any]] = [["role": "system", "content": systemMessage]]
            allMessages.append(contentsOf: apiMessages)
            body["messages"] = allMessages
        }

        return body
    }

    // MARK: - Response Parsing

    private func extractMoveText(from data: Data, providerType: ProviderType) throws -> (move: String, comment: String?) {
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

    /// Checks if the AI response indicates a resignation or draw claim.
    /// Returns the game result if so, nil if it's a normal move.
    static func detectSpecialAction(_ text: String, color: PieceColor) -> GameResult? {
        let lower = text.lowercased()

        // Resignation: "0-1 {white resigns}" or "1-0 {black resigns}" or just "resign"
        if lower.contains("resign") || lower.contains("0-1") || lower.contains("1-0") {
            // The color playing is the one resigning
            return .resignation(winner: color.opposite)
        }

        // Draw claims: "½–½" or "1/2-1/2"
        if lower.contains("½–½") || lower.contains("½-½") || lower.contains("1/2-1/2") {
            if lower.contains("50 move") || lower.contains("50-move") || lower.contains("75 move") || lower.contains("75-move") {
                return .fiftyMoveRule
            }
            return .drawByAgreement
        }

        return nil
    }

    /// Extracts a move and optional comment from AI output.
    /// Returns (cleanedMove, comment).
    private func cleanMoveText(_ text: String) -> (move: String, comment: String?) {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract comment: "e2e4 { capture knight }" → move="e2e4", comment="capture knight"
        var comment: String? = nil
        if let openBrace = cleaned.range(of: "{"),
           let closeBrace = cleaned.range(of: "}") {
            let commentContent = String(cleaned[openBrace.upperBound..<closeBrace.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            if !commentContent.isEmpty {
                comment = commentContent
            }
            cleaned = String(cleaned[cleaned.startIndex..<openBrace.lowerBound])
                .trimmingCharacters(in: .whitespaces)
        } else if let openBrace = cleaned.range(of: "{") {
            // Unclosed brace — still extract
            let commentContent = String(cleaned[openBrace.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !commentContent.isEmpty {
                comment = commentContent
            }
            cleaned = String(cleaned[cleaned.startIndex..<openBrace.lowerBound])
                .trimmingCharacters(in: .whitespaces)
        }

        // Normalize promotion format: "e7e8=q" → "e7e8q"
        cleaned = cleaned.replacingOccurrences(of: "=", with: "")

        // If it's short and looks like a move, use it directly
        if cleaned.count <= 6 {
            return (cleaned, comment)
        }

        // Try to find coordinate notation pattern
        let coordPattern = /[a-h][1-8][a-h][1-8][qrbn]?/
        if let match = cleaned.firstMatch(of: coordPattern) {
            return (String(match.output), comment)
        }

        // Try to find SAN pattern (require word boundary to avoid matching substrings of longer text)
        let sanPattern = /\b[KQRBN][a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?[+#]?\b/
        if let match = cleaned.firstMatch(of: sanPattern) {
            return (String(match.output), comment)
        }

        // Castling
        if cleaned.contains("O-O-O") || cleaned.contains("0-0-0") { return ("O-O-O", comment) }
        if cleaned.contains("O-O") || cleaned.contains("0-0") { return ("O-O", comment) }

        // Return first line as fallback
        let fallback = cleaned.components(separatedBy: .newlines).first ?? cleaned
        return (fallback, comment)
    }
}

// MARK: - AI Constants

/// Nonisolated constants for AI configuration.
enum AIConstants {
    static let maxRetries = 100
    static let conversationResetInterval = 5
}

// MARK: - AI Service Failure

/// The result of an AI move request — either a chess move or a game-ending action.
enum AIMoveResult: Sendable {
    case move(ChessMove)
    case resignation(winner: PieceColor)
    case drawClaim(GameResult)
}

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
