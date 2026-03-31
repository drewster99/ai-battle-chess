import Foundation

// MARK: - Move Validator

/// Handles all chess move validation including special moves.
struct MoveValidator: Sendable {

    // MARK: - Public API

    /// Returns all legal moves for the active color on the given board.
    static func allLegalMoves(for board: ChessBoard) -> [ChessMove] {
        let color = board.activeColor
        var result: [ChessMove] = []

        for (piece, position) in board.allPieces(color: color) {
            let pieceMoves = legalMoves(for: piece, at: position, on: board)
            result.append(contentsOf: pieceMoves)
        }

        return result
    }

    /// Returns all legal moves for a specific piece at a position.
    static func legalMoves(for piece: ChessPiece, at position: BoardPosition, on board: ChessBoard) -> [ChessMove] {
        let pseudoLegal = pseudoLegalMoves(for: piece, at: position, on: board)

        // Filter out moves that leave the king in check
        return pseudoLegal.filter { move in
            let newBoard = board.applyingMove(move)
            return !isKingInCheck(color: piece.color, on: newBoard)
        }
    }

    /// Validates and finds a legal move matching the given from/to positions.
    static func findLegalMove(from: BoardPosition, to: BoardPosition, promotion: PieceType? = nil, on board: ChessBoard) -> ChessMove? {
        guard let piece = board.piece(at: from), piece.color == board.activeColor else {
            return nil
        }
        let moves = legalMoves(for: piece, at: from, on: board)
        return moves.first { move in
            move.to == to && (move.promotionType == promotion || (move.promotionType != nil && promotion == nil))
        }
    }

    /// Checks if the given color's king is in check.
    static func isKingInCheck(color: PieceColor, on board: ChessBoard) -> Bool {
        guard let kingPos = board.findKing(color: color) else { return false }
        return isSquareAttacked(kingPos, by: color.opposite, on: board)
    }

    /// Checks if a square is attacked by any piece of the given color.
    static func isSquareAttacked(_ square: BoardPosition, by attackerColor: PieceColor, on board: ChessBoard) -> Bool {
        for (piece, pos) in board.allPieces(color: attackerColor) {
            if canAttack(piece: piece, from: pos, target: square, on: board) {
                return true
            }
        }
        return false
    }

    // MARK: - Game State Detection

    /// Returns true if the active color has at least one legal move.
    /// Early-exits as soon as a single legal move is found, avoiding generating all moves.
    static func hasAnyLegalMove(for board: ChessBoard) -> Bool {
        for (piece, position) in board.allPieces(color: board.activeColor) {
            if !legalMoves(for: piece, at: position, on: board).isEmpty {
                return true
            }
        }
        return false
    }

    /// Detects checkmate for the active color.
    static func isCheckmate(on board: ChessBoard) -> Bool {
        let color = board.activeColor
        guard isKingInCheck(color: color, on: board) else { return false }
        return !hasAnyLegalMove(for: board)
    }

    /// Detects stalemate for the active color.
    static func isStalemate(on board: ChessBoard) -> Bool {
        let color = board.activeColor
        guard !isKingInCheck(color: color, on: board) else { return false }
        return !hasAnyLegalMove(for: board)
    }

    /// Detects insufficient material (K vs K, K+B vs K, K+N vs K, K+B vs K+B same color).
    static func isInsufficientMaterial(on board: ChessBoard) -> Bool {
        let whitePieces = board.allPieces(color: .white)
        let blackPieces = board.allPieces(color: .black)

        let whiteNonKing = whitePieces.filter { $0.piece.type != .king }
        let blackNonKing = blackPieces.filter { $0.piece.type != .king }

        // K vs K
        if whiteNonKing.isEmpty && blackNonKing.isEmpty {
            return true
        }

        // K+B vs K or K+N vs K
        if whiteNonKing.isEmpty && blackNonKing.count == 1 {
            let type = blackNonKing[0].piece.type
            if type == .bishop || type == .knight { return true }
        }
        if blackNonKing.isEmpty && whiteNonKing.count == 1 {
            let type = whiteNonKing[0].piece.type
            if type == .bishop || type == .knight { return true }
        }

        // K+B vs K+B (same colored squares)
        if whiteNonKing.count == 1 && blackNonKing.count == 1 &&
           whiteNonKing[0].piece.type == .bishop && blackNonKing[0].piece.type == .bishop {
            let wPos = whiteNonKing[0].position
            let bPos = blackNonKing[0].position
            let wSquareColor = (wPos.file + wPos.rank) % 2
            let bSquareColor = (bPos.file + bPos.rank) % 2
            if wSquareColor == bSquareColor { return true }
        }

        return false
    }

    /// Detects automatic draw under the 50-move rule (100 half-moves without a pawn move or capture).
    static func isFiftyMoveRule(on board: ChessBoard) -> Bool {
        board.halfMoveClock >= 100
    }

    /// Detects any game-ending condition and returns the result.
    static func detectGameResult(on board: ChessBoard) -> GameResult? {
        if isCheckmate(on: board) {
            return .checkmate(winner: board.activeColor.opposite)
        }
        if isStalemate(on: board) {
            return .stalemate
        }
        if isInsufficientMaterial(on: board) {
            return .insufficientMaterial
        }
        if isFiftyMoveRule(on: board) {
            return .fiftyMoveRule
        }
        return nil
    }

    // MARK: - Pseudo-Legal Move Generation

    private static func pseudoLegalMoves(for piece: ChessPiece, at position: BoardPosition, on board: ChessBoard) -> [ChessMove] {
        switch piece.type {
        case .pawn: return pawnMoves(piece: piece, at: position, on: board)
        case .knight: return knightMoves(piece: piece, at: position, on: board)
        case .bishop: return slidingMoves(piece: piece, at: position, on: board, directions: bishopDirections)
        case .rook: return slidingMoves(piece: piece, at: position, on: board, directions: rookDirections)
        case .queen: return slidingMoves(piece: piece, at: position, on: board, directions: queenDirections)
        case .king: return kingMoves(piece: piece, at: position, on: board)
        }
    }

    // MARK: - Direction Vectors

    private static let bishopDirections = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let rookDirections = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    private static let queenDirections = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let knightOffsets = [(2, 1), (2, -1), (-2, 1), (-2, -1), (1, 2), (1, -2), (-1, 2), (-1, -2)]

    // MARK: - Piece-Specific Move Generation

    private static func pawnMoves(piece: ChessPiece, at position: BoardPosition, on board: ChessBoard) -> [ChessMove] {
        var moves: [ChessMove] = []
        let direction = piece.color == .white ? 1 : -1
        let startRank = piece.color == .white ? 1 : 6
        let promotionRank = piece.color == .white ? 7 : 0

        // Single push
        let oneStep = BoardPosition(file: position.file, rank: position.rank + direction)
        if oneStep.isValid && board.piece(at: oneStep) == nil {
            if oneStep.rank == promotionRank {
                for promoType: PieceType in [.queen, .rook, .bishop, .knight] {
                    moves.append(ChessMove(piece: piece, from: position, to: oneStep, promotionType: promoType))
                }
            } else {
                moves.append(ChessMove(piece: piece, from: position, to: oneStep))
            }

            // Double push from starting rank
            if position.rank == startRank {
                let twoStep = BoardPosition(file: position.file, rank: position.rank + 2 * direction)
                if twoStep.isValid && board.piece(at: twoStep) == nil {
                    moves.append(ChessMove(piece: piece, from: position, to: twoStep))
                }
            }
        }

        // Captures (diagonal)
        for df in [-1, 1] {
            let capturePos = BoardPosition(file: position.file + df, rank: position.rank + direction)
            guard capturePos.isValid else { continue }

            if let target = board.piece(at: capturePos), target.color != piece.color {
                if capturePos.rank == promotionRank {
                    for promoType: PieceType in [.queen, .rook, .bishop, .knight] {
                        moves.append(ChessMove(piece: piece, from: position, to: capturePos, capturedPiece: target, promotionType: promoType))
                    }
                } else {
                    moves.append(ChessMove(piece: piece, from: position, to: capturePos, capturedPiece: target))
                }
            }

            // En passant
            if let epTarget = board.enPassantTarget, capturePos == epTarget {
                let capturedPawnPos = BoardPosition(file: capturePos.file, rank: position.rank)
                let capturedPawn = board.piece(at: capturedPawnPos)
                moves.append(ChessMove(
                    piece: piece,
                    from: position,
                    to: capturePos,
                    capturedPiece: capturedPawn,
                    isEnPassant: true
                ))
            }
        }

        return moves
    }

    private static func knightMoves(piece: ChessPiece, at position: BoardPosition, on board: ChessBoard) -> [ChessMove] {
        var moves: [ChessMove] = []
        for (df, dr) in knightOffsets {
            let target = BoardPosition(file: position.file + df, rank: position.rank + dr)
            guard target.isValid else { continue }
            let targetPiece = board.piece(at: target)
            if let targetPiece {
                guard targetPiece.color != piece.color else { continue }
                moves.append(ChessMove(piece: piece, from: position, to: target, capturedPiece: targetPiece))
            } else {
                moves.append(ChessMove(piece: piece, from: position, to: target))
            }
        }
        return moves
    }

    private static func slidingMoves(piece: ChessPiece, at position: BoardPosition, on board: ChessBoard, directions: [(Int, Int)]) -> [ChessMove] {
        var moves: [ChessMove] = []
        for (df, dr) in directions {
            var f = position.file + df
            var r = position.rank + dr
            while f >= 0 && f < 8 && r >= 0 && r < 8 {
                let target = BoardPosition(file: f, rank: r)
                let targetPiece = board.piece(at: target)
                if let targetPiece {
                    if targetPiece.color != piece.color {
                        moves.append(ChessMove(piece: piece, from: position, to: target, capturedPiece: targetPiece))
                    }
                    break // Blocked
                } else {
                    moves.append(ChessMove(piece: piece, from: position, to: target))
                }
                f += df
                r += dr
            }
        }
        return moves
    }

    private static func kingMoves(piece: ChessPiece, at position: BoardPosition, on board: ChessBoard) -> [ChessMove] {
        var moves: [ChessMove] = []

        // Normal moves
        for df in -1...1 {
            for dr in -1...1 {
                if df == 0 && dr == 0 { continue }
                let target = BoardPosition(file: position.file + df, rank: position.rank + dr)
                guard target.isValid else { continue }
                let targetPiece = board.piece(at: target)
                if let targetPiece {
                    guard targetPiece.color != piece.color else { continue }
                    moves.append(ChessMove(piece: piece, from: position, to: target, capturedPiece: targetPiece))
                } else {
                    moves.append(ChessMove(piece: piece, from: position, to: target))
                }
            }
        }

        // Castling
        let rank = piece.color == .white ? 0 : 7
        let enemy = piece.color.opposite

        // Can't castle out of check
        if !isSquareAttacked(position, by: enemy, on: board) {
            // Kingside
            let canKingside = piece.color == .white ? board.whiteCanCastleKingside : board.blackCanCastleKingside
            if canKingside {
                let f5 = BoardPosition(file: 5, rank: rank)
                let g = BoardPosition(file: 6, rank: rank)
                if board.piece(at: f5) == nil && board.piece(at: g) == nil &&
                   !isSquareAttacked(f5, by: enemy, on: board) &&
                   !isSquareAttacked(g, by: enemy, on: board) {
                    moves.append(ChessMove(piece: piece, from: position, to: g, isCastleKingside: true))
                }
            }

            // Queenside
            let canQueenside = piece.color == .white ? board.whiteCanCastleQueenside : board.blackCanCastleQueenside
            if canQueenside {
                let d = BoardPosition(file: 3, rank: rank)
                let c = BoardPosition(file: 2, rank: rank)
                let b = BoardPosition(file: 1, rank: rank)
                if board.piece(at: d) == nil && board.piece(at: c) == nil && board.piece(at: b) == nil &&
                   !isSquareAttacked(d, by: enemy, on: board) &&
                   !isSquareAttacked(c, by: enemy, on: board) {
                    moves.append(ChessMove(piece: piece, from: position, to: c, isCastleQueenside: true))
                }
            }
        }

        return moves
    }

    // MARK: - Attack Detection (for check/pin detection)

    private static func canAttack(piece: ChessPiece, from: BoardPosition, target: BoardPosition, on board: ChessBoard) -> Bool {
        switch piece.type {
        case .pawn:
            let direction = piece.color == .white ? 1 : -1
            return abs(target.file - from.file) == 1 && target.rank - from.rank == direction
        case .knight:
            let df = abs(target.file - from.file)
            let dr = abs(target.rank - from.rank)
            return (df == 2 && dr == 1) || (df == 1 && dr == 2)
        case .bishop:
            return canSlideAttack(from: from, to: target, directions: bishopDirections, on: board)
        case .rook:
            return canSlideAttack(from: from, to: target, directions: rookDirections, on: board)
        case .queen:
            return canSlideAttack(from: from, to: target, directions: queenDirections, on: board)
        case .king:
            return abs(target.file - from.file) <= 1 && abs(target.rank - from.rank) <= 1
        }
    }

    private static func canSlideAttack(from: BoardPosition, to: BoardPosition, directions: [(Int, Int)], on board: ChessBoard) -> Bool {
        for (df, dr) in directions {
            var f = from.file + df
            var r = from.rank + dr
            while f >= 0 && f < 8 && r >= 0 && r < 8 {
                if f == to.file && r == to.rank { return true }
                if board.piece(at: BoardPosition(file: f, rank: r)) != nil { break }
                f += df
                r += dr
            }
        }
        return false
    }
}
