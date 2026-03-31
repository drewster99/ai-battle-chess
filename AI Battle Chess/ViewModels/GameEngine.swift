import Foundation
import SwiftUI
import SwiftLLMKit
import Observation

// MARK: - Game Engine

/// Central game state manager. Handles game flow, move execution, AI turns, and navigation.
@Observable
@MainActor
final class GameEngine {
    // MARK: - Game State

    var board: ChessBoard = ChessBoard()
    var moveHistory: [ChessMove] = []
    var boardStates: [ChessBoard] = [] // Board state BEFORE each move
    var gameResult: GameResult? = nil
    var isGameActive: Bool = false
    var currentGameID: UUID = UUID()

    // MARK: - Players

    var whitePlayer: PlayerConfig = PlayerConfig(name: "White", color: .white)
    var blackPlayer: PlayerConfig = PlayerConfig(name: "Black", color: .black)
    var gameMode: GameMode = .playerVsAI

    // MARK: - Navigation

    /// Index into moveHistory for viewing historical positions. nil = live.
    var viewingMoveIndex: Int? = nil
    var isViewingHistory: Bool { viewingMoveIndex != nil }

    /// Index into gameHistoryManager.gameRecords for viewing past games. nil = current game.
    var viewingGameIndex: Int? = nil
    var isViewingPastGame: Bool { viewingGameIndex != nil }

    // MARK: - AI State

    var isAIThinking: Bool = false
    var currentAIColor: PieceColor? = nil
    var statistics: GameStatistics = GameStatistics()
    var currentAIActivity: [PieceColor: AIActivityLog] = [:]

    // MARK: - Animation

    var selectedSquare: BoardPosition? = nil
    var legalMovesForSelected: [BoardPosition] = []
    var lastMove: ChessMove? = nil
    var animatingMove: ChessMove? = nil
    var animatingFileDelta: Int = 0
    var animatingRankDelta: Int = 0
    var pendingPromotion: (from: BoardPosition, to: BoardPosition)? = nil
    var errorMessage: String? = nil
    var statusMessage: String = "Ready to play"

    // MARK: - Session Timing

    var totalHumanTime: TimeInterval = 0
    var totalAITime: TimeInterval = 0

    // MARK: - Services

    private let aiService: AIService
    private let appleIntelligenceService: AppleIntelligenceService?
    let llmKit: LLMKitManager
    let gameHistoryManager: GameHistoryManager
    private var aiTask: Task<Void, Never>? = nil
    private var animationTask: Task<Void, Never>? = nil
    private var gameFinalized: Bool = false

    // MARK: - Init

    init(llmKit: LLMKitManager, gameHistoryManager: GameHistoryManager) {
        self.llmKit = llmKit
        self.gameHistoryManager = gameHistoryManager
        self.aiService = AIService(llmKit: llmKit)
        if #available(macOS 26.0, *) {
            self.appleIntelligenceService = AppleIntelligenceService()
        } else {
            self.appleIntelligenceService = nil
        }
    }

    // MARK: - Computed Helpers

    /// Number of moves made by a specific color in the current game.
    func moveCount(for color: PieceColor) -> Int {
        moveHistory.filter { $0.piece.color == color }.count
    }

    /// Average time per move for a specific color in the current game.
    func averageMoveTime(for color: PieceColor) -> TimeInterval {
        let durations = statistics.perMoveDuration[color] ?? []
        guard !durations.isEmpty else { return 0 }
        return durations.reduce(0, +) / Double(durations.count)
    }

    /// Elapsed time since the game started.
    var elapsedTime: TimeInterval {
        Date().timeIntervalSince(statistics.gameStartTime)
    }

    /// The current player whose turn it is.
    var currentPlayer: PlayerConfig {
        board.activeColor == .white ? whitePlayer : blackPlayer
    }

    /// Player name for a given color.
    func playerName(for color: PieceColor) -> String {
        (color == .white ? whitePlayer : blackPlayer).name
    }

    /// Turn display text for the status bar.
    var turnDisplayText: String {
        if isViewingPastGame, let index = viewingGameIndex {
            let records = gameHistoryManager.gameRecords
            if index < records.count {
                let gameID = records[index].id.uuidString.prefix(8)
                return "Viewing game #\(gameID)"
            }
        }

        if let result = gameResult {
            return result.displayText
        }

        if isGameActive {
            let name = currentPlayer.name
            return "\(board.activeColor.displayName)'s turn (\(name))"
        }

        return statusMessage
    }

    // MARK: - New Game

    func startNewGame() {
        // Finalize the current game if it was active
        finalizeCurrentGame()

        aiTask?.cancel()
        aiTask = nil

        currentGameID = UUID()
        board = ChessBoard()
        moveHistory = []
        boardStates = []
        gameResult = nil
        isGameActive = true
        liveGameSnapshot = nil
        viewingMoveIndex = nil
        viewingGameIndex = nil
        selectedSquare = nil
        legalMovesForSelected = []
        lastMove = nil
        animatingMove = nil
        animatingFileDelta = 0
        animatingRankDelta = 0
        pendingPromotion = nil
        errorMessage = nil
        isAIThinking = false
        currentAIColor = nil
        currentAIActivity = [:]
        gameFinalized = false
        statistics = GameStatistics()
        statistics.gameStartTime = Date()
        statistics.turnStartTime = Date()

        // Update material values
        statistics.materialValue[.white] = board.materialValue(for: .white)
        statistics.materialValue[.black] = board.materialValue(for: .black)

        statusMessage = "\(board.activeColor.displayName)'s turn"

        // If the first player is AI, trigger their move
        triggerAIMoveIfNeeded()
    }

    // MARK: - Game Finalization

    private func finalizeCurrentGame() {
        guard !gameFinalized else { return }
        guard !moveHistory.isEmpty else { return }
        guard let result = gameResult else { return }
        gameFinalized = true

        // Compute human and AI time for this game
        var humanTime: TimeInterval = 0
        var aiTime: TimeInterval = 0
        for color in PieceColor.allCases {
            let player = color == .white ? whitePlayer : blackPlayer
            let totalForColor = (statistics.perMoveDuration[color] ?? []).reduce(0, +)
            if player.isAI {
                aiTime += totalForColor
            } else {
                humanTime += totalForColor
            }
        }

        totalHumanTime += humanTime
        totalAITime += aiTime

        let record = GameRecord(
            id: currentGameID,
            startTime: statistics.gameStartTime,
            endTime: Date(),
            whitePlayerName: whitePlayer.name,
            blackPlayerName: blackPlayer.name,
            gameMode: gameMode,
            result: result,
            moveCount: moveHistory.count,
            pgnText: currentPGN,
            statistics: statistics,
            humanTime: humanTime,
            aiTime: aiTime
        )

        gameHistoryManager.save(record)
    }

    // MARK: - Square Selection & Human Move

    func selectSquare(_ position: BoardPosition) {
        guard isGameActive, gameResult == nil else { return }
        guard !isAIThinking else { return }

        // If viewing history, return to live
        if isViewingHistory {
            returnToLive()
        }

        // Current player must be human
        let player = board.activeColor == .white ? whitePlayer : blackPlayer
        guard !player.isAI else { return }

        if let selected = selectedSquare {
            // Try to make a move
            if position == selected {
                // Deselect
                selectedSquare = nil
                legalMovesForSelected = []
                return
            }

            if legalMovesForSelected.contains(position) {
                // Check if this is a pawn promotion
                if let piece = board.piece(at: selected), piece.type == .pawn {
                    let promoRank = piece.color == .white ? 7 : 0
                    if position.rank == promoRank {
                        pendingPromotion = (from: selected, to: position)
                        return
                    }
                }

                executeHumanMove(from: selected, to: position, promotion: nil)
                return
            }

            // Select a different piece
            if let piece = board.piece(at: position), piece.color == board.activeColor {
                selectedSquare = position
                let moves = MoveValidator.legalMoves(for: piece, at: position, on: board)
                legalMovesForSelected = moves.map(\.to)
                return
            }

            // Click on empty/enemy square that's not a legal move
            selectedSquare = nil
            legalMovesForSelected = []
        } else {
            // Select a piece
            if let piece = board.piece(at: position), piece.color == board.activeColor {
                selectedSquare = position
                let moves = MoveValidator.legalMoves(for: piece, at: position, on: board)
                legalMovesForSelected = moves.map(\.to)
            }
        }
    }

    func selectPromotion(_ type: PieceType) {
        guard let promo = pendingPromotion else { return }
        pendingPromotion = nil
        executeHumanMove(from: promo.from, to: promo.to, promotion: type)
    }

    func cancelPromotion() {
        pendingPromotion = nil
        selectedSquare = nil
        legalMovesForSelected = []
    }

    private func executeHumanMove(from: BoardPosition, to: BoardPosition, promotion: PieceType?) {
        guard let move = MoveValidator.findLegalMove(from: from, to: to, promotion: promotion, on: board) else {
            errorMessage = "Illegal move"
            selectedSquare = nil
            legalMovesForSelected = []
            return
        }

        applyMove(move)
    }

    // MARK: - Move Application

    private func applyMove(_ move: ChessMove) {
        selectedSquare = nil
        legalMovesForSelected = []

        // Annotate with check status
        let newBoard = board.applyingMove(move)
        let isCheck = MoveValidator.isKingInCheck(color: board.activeColor.opposite, on: newBoard)
        let isCheckmate = isCheck && MoveValidator.isCheckmate(on: newBoard)
        let annotatedMove = move.withCheckStatus(isCheck: isCheck, isCheckmate: isCheckmate)

        // Record timing
        let now = Date()
        let moveDuration = now.timeIntervalSince(statistics.turnStartTime)
        statistics.perMoveDuration[move.piece.color, default: []].append(moveDuration)
        statistics.moveTimestamps.append(now)
        statistics.turnStartTime = now

        // Store board state before the move
        boardStates.append(board)

        // Set up animation: piece starts at source offset, animates to zero
        animatingMove = annotatedMove
        animatingFileDelta = move.from.file - move.to.file
        animatingRankDelta = move.from.rank - move.to.rank

        // Apply board state
        board = newBoard
        moveHistory.append(annotatedMove)
        lastMove = annotatedMove

        // Update statistics
        updateStatistics(for: annotatedMove)

        // Check game end
        if let result = MoveValidator.detectGameResult(on: board) {
            gameResult = result
            isGameActive = false
            statusMessage = result.displayText

            let distance = max(abs(annotatedMove.to.file - annotatedMove.from.file),
                             abs(annotatedMove.to.rank - annotatedMove.from.rank))
            let duration = max(Double(distance) / 5.0, 0.15)
            let moveID = annotatedMove.id
            startMoveAnimation(moveID: moveID, duration: duration)

            finalizeCurrentGame()
            return
        }

        statusMessage = "\(board.activeColor.displayName)'s turn"

        let distance = max(abs(annotatedMove.to.file - annotatedMove.from.file),
                         abs(annotatedMove.to.rank - annotatedMove.from.rank))
        let duration = max(Double(distance) / 5.0, 0.15)
        let moveID = annotatedMove.id
        startMoveAnimation(moveID: moveID, duration: duration)

        // Trigger AI if needed
        triggerAIMoveIfNeeded()
    }

    // MARK: - AI Move

    private func triggerAIMoveIfNeeded() {
        guard isGameActive, gameResult == nil else { return }

        let player = board.activeColor == .white ? whitePlayer : blackPlayer
        guard player.isAI else { return }

        isAIThinking = true
        currentAIColor = board.activeColor

        let boardSnapshot = board
        let color = board.activeColor
        let gameTurnIndex = moveCount(for: color)
        let gameID = currentGameID

        aiTask = Task { [weak self] in
            guard let self else { return }

            do {
                let result: (move: ChessMove, penalties: [AIPenalty], retries: Int, activityLog: AIActivityLog?)

                if player.useAppleIntelligence, let appleService = appleIntelligenceService {
                    let appleResult = try await appleService.requestMove(
                        board: boardSnapshot,
                        color: color,
                        gameID: gameID,
                        gameTurnIndex: gameTurnIndex
                    )
                    result = (appleResult.move, appleResult.penalties, appleResult.retries, appleResult.activityLog)
                } else if let configID = player.aiConfigurationID {
                    let llmResult = try await aiService.requestMove(
                        configurationID: configID,
                        board: boardSnapshot,
                        color: color,
                        gameID: gameID,
                        gameTurnIndex: gameTurnIndex
                    )
                    result = (llmResult.move, llmResult.penalties, llmResult.retries, llmResult.activityLog)
                } else {
                    throw AIError.noConfigurationSelected
                }

                guard !Task.isCancelled else { return }

                // Record penalties
                for penalty in result.penalties {
                    statistics.aiPenalties[color, default: []].append(penalty)
                }
                statistics.aiRetryCount[color, default: 0] += result.retries

                // Store activity log
                if let log = result.activityLog {
                    currentAIActivity[color] = log
                }

                isAIThinking = false
                currentAIColor = nil
                applyMove(result.move)

            } catch {
                guard !Task.isCancelled else { return }

                isAIThinking = false
                currentAIColor = nil

                // Extract accumulated retry state from the service failure
                let failure = error as? AIServiceFailure
                let actualError = failure?.underlyingError ?? error

                if let failure {
                    for penalty in failure.penalties {
                        statistics.aiPenalties[color, default: []].append(penalty)
                    }
                    statistics.aiRetryCount[color, default: 0] += failure.retries
                    if let log = failure.lastActivityLog {
                        currentAIActivity[color] = log
                    }
                }

                if let aiError = actualError as? AIError, case .tooManyRetries = aiError {
                    // AI forfeits — all retry details are already recorded above
                    let penalty = AIPenalty(
                        reason: "AI forfeited after \(AIService.maxRetries) failed attempts",
                        severity: .critical,
                        timestamp: Date()
                    )
                    statistics.aiPenalties[color, default: []].append(penalty)
                    let result = GameResult.resignation(winner: color.opposite)
                    gameResult = result
                    isGameActive = false
                    statusMessage = result.displayText
                    finalizeCurrentGame()
                } else {
                    errorMessage = "AI Error: \(actualError.localizedDescription)"
                    statusMessage = "AI error - \(color.displayName) turn"
                }
            }
        }
    }

    // MARK: - Statistics

    private func updateStatistics(for move: ChessMove) {
        statistics.totalMoves += 1

        if move.capturedPiece != nil {
            statistics.captureCount[move.piece.color, default: 0] += 1
        }

        if move.isCheck {
            statistics.checkCount[move.piece.color, default: 0] += 1
        }

        if move.isCastleKingside || move.isCastleQueenside {
            statistics.castled[move.piece.color] = true
        }

        if move.promotionType != nil {
            statistics.promotions[move.piece.color, default: 0] += 1
        }

        statistics.materialValue[.white] = board.materialValue(for: .white)
        statistics.materialValue[.black] = board.materialValue(for: .black)
    }

    // MARK: - Move Navigation

    func navigateToMove(_ index: Int) {
        guard index >= 0 && index < moveHistory.count else { return }
        viewingMoveIndex = index
    }

    func navigateFirst() {
        guard !moveHistory.isEmpty else { return }
        viewingMoveIndex = 0
    }

    func navigatePrevious() {
        if let current = viewingMoveIndex {
            if current > 0 {
                viewingMoveIndex = current - 1
            }
        } else if !moveHistory.isEmpty {
            viewingMoveIndex = moveHistory.count - 1
        }
    }

    func navigateNext() {
        if let current = viewingMoveIndex {
            if current < moveHistory.count - 1 {
                viewingMoveIndex = current + 1
            } else {
                viewingMoveIndex = nil // Return to live
            }
        }
    }

    func navigateLast() {
        viewingMoveIndex = nil
    }

    func returnToLive() {
        if isViewingPastGame {
            viewingGameIndex = nil
            restoreLiveGameSnapshot()
        } else {
            viewingMoveIndex = nil
        }
    }

    /// Navigates to the next move with animation (triggered by space bar).
    func navigateNextAnimated() {
        guard isViewingHistory, let currentIndex = viewingMoveIndex else { return }
        let nextIndex = currentIndex + 1
        guard nextIndex < moveHistory.count else {
            returnToLive()
            return
        }

        let move = moveHistory[nextIndex]

        // Set animation state: piece starts offset at source position
        animatingMove = move
        animatingFileDelta = move.from.file - move.to.file
        animatingRankDelta = move.from.rank - move.to.rank

        // Advance the viewed position so the piece exists on the display board
        viewingMoveIndex = nextIndex

        let distance = max(abs(move.to.file - move.from.file), abs(move.to.rank - move.from.rank))
        let duration = max(Double(distance) / 5.0, 0.15)
        startMoveAnimation(moveID: move.id, duration: duration)
    }

    /// Defers the offset-to-zero animation to the next run loop tick so SwiftUI
    /// renders the initial offset state first, then animates to zero.
    private func startMoveAnimation(moveID: UUID, duration: Double) {
        animationTask?.cancel()
        animationTask = Task { [weak self] in
            // Yield to allow SwiftUI to render the initial offset state
            await Task.yield()
            guard let self, !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: duration)) {
                self.animatingFileDelta = 0
                self.animatingRankDelta = 0
            }

            do {
                try await Task.sleep(for: .seconds(duration + 0.05))
            } catch is CancellationError {
                return
            } catch {
                // Unexpected error
            }
            guard !Task.isCancelled else { return }
            if self.animatingMove?.id == moveID {
                self.animatingMove = nil
            }
        }
    }

    // MARK: - Game Navigation (Up/Down arrows)

    /// Snapshot of live game state, saved before viewing past games.
    private struct LiveGameSnapshot {
        let board: ChessBoard
        let moveHistory: [ChessMove]
        let boardStates: [ChessBoard]
        let gameResult: GameResult?
        let isGameActive: Bool
        let statistics: GameStatistics
        let lastMove: ChessMove?
        let statusMessage: String
        let currentGameID: UUID
    }

    private var liveGameSnapshot: LiveGameSnapshot? = nil

    /// Navigate to the previous (older) completed game.
    func navigateToPreviousGame() {
        let records = gameHistoryManager.gameRecords
        guard !records.isEmpty else { return }

        let nextIndex: Int
        if let current = viewingGameIndex {
            nextIndex = current + 1
            guard nextIndex < records.count else { return }
        } else {
            // Save live game state before navigating away
            saveLiveGameSnapshot()
            nextIndex = 0
        }

        viewingGameIndex = nextIndex
        loadGameRecord(records[nextIndex])
    }

    /// Navigate to the next (newer) completed game, or return to the live game.
    func navigateToNextGame() {
        guard let current = viewingGameIndex else { return }

        if current == 0 {
            // Return to live game — restore saved state
            viewingGameIndex = nil
            restoreLiveGameSnapshot()
        } else {
            let nextIndex = current - 1
            viewingGameIndex = nextIndex
            let records = gameHistoryManager.gameRecords
            if nextIndex < records.count {
                loadGameRecord(records[nextIndex])
            }
        }
    }

    private func saveLiveGameSnapshot() {
        liveGameSnapshot = LiveGameSnapshot(
            board: board,
            moveHistory: moveHistory,
            boardStates: boardStates,
            gameResult: gameResult,
            isGameActive: isGameActive,
            statistics: statistics,
            lastMove: lastMove,
            statusMessage: statusMessage,
            currentGameID: currentGameID
        )
    }

    private func restoreLiveGameSnapshot() {
        guard let snapshot = liveGameSnapshot else {
            viewingMoveIndex = nil
            return
        }
        board = snapshot.board
        moveHistory = snapshot.moveHistory
        boardStates = snapshot.boardStates
        gameResult = snapshot.gameResult
        isGameActive = snapshot.isGameActive
        statistics = snapshot.statistics
        lastMove = snapshot.lastMove
        statusMessage = snapshot.statusMessage
        currentGameID = snapshot.currentGameID
        viewingMoveIndex = nil
        animatingMove = nil
        animatingFileDelta = 0
        animatingRankDelta = 0
        liveGameSnapshot = nil
    }

    private func loadGameRecord(_ record: GameRecord) {
        loadGame(pgn: record.pgnText)
        statusMessage = "Viewing game #\(record.id.uuidString.prefix(8))"
    }

    /// The board state to display (either historical or live).
    var displayBoard: ChessBoard {
        if let index = viewingMoveIndex {
            if index < boardStates.count && index < moveHistory.count {
                // Show board AFTER the move at this index
                return boardStates[index].applyingMove(moveHistory[index])
            }
        }
        return board
    }

    // MARK: - Game Loading

    /// Loads a game from PGN notation.
    func loadGame(pgn: String) {
        aiTask?.cancel()
        aiTask = nil

        board = ChessBoard()
        moveHistory = []
        boardStates = []
        gameResult = nil
        isGameActive = false
        viewingMoveIndex = nil
        selectedSquare = nil
        legalMovesForSelected = []
        lastMove = nil
        animatingMove = nil
        animatingFileDelta = 0
        animatingRankDelta = 0
        errorMessage = nil
        isAIThinking = false
        statistics = GameStatistics()

        // Parse PGN moves
        let moves = parsePGNMoves(pgn)

        for moveStr in moves {
            guard let parsed = PGNFormatter.parseSAN(moveStr, on: board) else {
                errorMessage = "Failed to parse move: \(moveStr)"
                break
            }

            guard let legalMove = MoveValidator.findLegalMove(
                from: parsed.from,
                to: parsed.to,
                promotion: parsed.promotion,
                on: board
            ) else {
                errorMessage = "Illegal move in PGN: \(moveStr)"
                break
            }

            let newBoard = board.applyingMove(legalMove)
            let isCheck = MoveValidator.isKingInCheck(color: board.activeColor.opposite, on: newBoard)
            let isCheckmate = isCheck && MoveValidator.isCheckmate(on: newBoard)
            let annotatedMove = legalMove.withCheckStatus(isCheck: isCheck, isCheckmate: isCheckmate)

            boardStates.append(board)
            board = newBoard
            moveHistory.append(annotatedMove)
            updateStatistics(for: annotatedMove)
        }

        // Check for game result
        if let result = MoveValidator.detectGameResult(on: board) {
            gameResult = result
            statusMessage = result.displayText
        } else {
            statusMessage = "Game loaded - \(moveHistory.count) moves"
        }

        if !moveHistory.isEmpty {
            viewingMoveIndex = 0
        }
    }

    private func parsePGNMoves(_ pgn: String) -> [String] {
        // Remove headers (lines starting with [)
        let lines = pgn.components(separatedBy: .newlines)
        let moveText = lines.filter { !$0.hasPrefix("[") && !$0.isEmpty }.joined(separator: " ")

        // Remove comments {}, variations (), and result
        var cleaned = moveText
        cleaned = cleaned.replacing(/\{[^}]*\}/, with: "")
        cleaned = cleaned.replacing(/\([^)]*\)/, with: "")
        cleaned = cleaned.replacingOccurrences(of: "1-0", with: "")
        cleaned = cleaned.replacingOccurrences(of: "0-1", with: "")
        cleaned = cleaned.replacingOccurrences(of: "1/2-1/2", with: "")
        cleaned = cleaned.replacingOccurrences(of: "*", with: "")

        // Remove move numbers
        cleaned = cleaned.replacing(/\d+\.+\s*/, with: "")

        // Split into individual moves
        return cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }

    // MARK: - Resign

    func resign(color: PieceColor) {
        guard isGameActive else { return }
        aiTask?.cancel()
        aiTask = nil
        isAIThinking = false
        let result = GameResult.resignation(winner: color.opposite)
        gameResult = result
        isGameActive = false
        statusMessage = result.displayText
        finalizeCurrentGame()
    }

    // MARK: - PGN Export

    var currentPGN: String {
        PGNFormatter.generatePGN(
            moves: moveHistory,
            boardStates: boardStates,
            result: gameResult,
            whiteName: whitePlayer.name,
            blackName: blackPlayer.name,
            gameID: currentGameID
        )
    }

    // MARK: - System Info

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    static var macOSVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    static var systemDescription: String {
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        return "\(ramGB)GB RAM"
    }
}
