import Foundation

// MARK: - Chess Board

/// Represents the 8x8 chess board with all piece positions and game state.
struct ChessBoard: Equatable, Sendable {
    /// 8x8 grid: squares[file][rank], nil means empty
    var squares: [[ChessPiece?]]

    /// Castling rights
    var whiteCanCastleKingside: Bool = true
    var whiteCanCastleQueenside: Bool = true
    var blackCanCastleKingside: Bool = true
    var blackCanCastleQueenside: Bool = true

    /// En passant target square (the square the capturing pawn moves to)
    var enPassantTarget: BoardPosition? = nil

    /// Half-move clock for 50-move rule (resets on pawn move or capture)
    var halfMoveClock: Int = 0

    /// Full move number (incremented after Black's move)
    var fullMoveNumber: Int = 1

    /// Current side to move
    var activeColor: PieceColor = .white

    // MARK: - Initialization

    init() {
        squares = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        setupInitialPosition()
    }

    init(empty: Bool) {
        squares = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        if !empty {
            setupInitialPosition()
        }
    }

    // MARK: - Board Access

    func piece(at position: BoardPosition) -> ChessPiece? {
        guard position.isValid else { return nil }
        return squares[position.file][position.rank]
    }

    mutating func setPiece(_ piece: ChessPiece?, at position: BoardPosition) {
        guard position.isValid else { return }
        squares[position.file][position.rank] = piece
    }

    func findKing(color: PieceColor) -> BoardPosition? {
        for file in 0..<8 {
            for rank in 0..<8 {
                if let piece = squares[file][rank],
                   piece.type == .king && piece.color == color {
                    return BoardPosition(file: file, rank: rank)
                }
            }
        }
        return nil
    }

    func allPieces(color: PieceColor) -> [(piece: ChessPiece, position: BoardPosition)] {
        var result: [(ChessPiece, BoardPosition)] = []
        for file in 0..<8 {
            for rank in 0..<8 {
                if let piece = squares[file][rank], piece.color == color {
                    result.append((piece, BoardPosition(file: file, rank: rank)))
                }
            }
        }
        return result
    }

    // MARK: - Setup

    private mutating func setupInitialPosition() {
        // White pieces (rank 0 = row 1)
        let backRankTypes: [PieceType] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for file in 0..<8 {
            squares[file][0] = ChessPiece(color: .white, type: backRankTypes[file])
            squares[file][1] = ChessPiece(color: .white, type: .pawn)
            squares[file][6] = ChessPiece(color: .black, type: .pawn)
            squares[file][7] = ChessPiece(color: .black, type: backRankTypes[file])
        }
    }

    // MARK: - Move Application

    /// Applies a move and returns a new board state. Does NOT validate legality.
    func applyingMove(_ move: ChessMove) -> ChessBoard {
        var newBoard = self

        // Remove piece from source
        newBoard.squares[move.from.file][move.from.rank] = nil

        // Handle promotion
        let placedPiece: ChessPiece
        if let promoType = move.promotionType {
            placedPiece = ChessPiece(color: move.piece.color, type: promoType)
        } else {
            placedPiece = move.piece
        }

        // Place piece at destination
        newBoard.squares[move.to.file][move.to.rank] = placedPiece

        // Handle en passant capture
        if move.isEnPassant {
            let capturedPawnRank = move.piece.color == .white ? move.to.rank - 1 : move.to.rank + 1
            newBoard.squares[move.to.file][capturedPawnRank] = nil
        }

        // Handle castling - move the rook
        if move.isCastleKingside {
            let rank = move.piece.color == .white ? 0 : 7
            let rook = newBoard.squares[7][rank]
            newBoard.squares[7][rank] = nil
            newBoard.squares[5][rank] = rook
        }
        if move.isCastleQueenside {
            let rank = move.piece.color == .white ? 0 : 7
            let rook = newBoard.squares[0][rank]
            newBoard.squares[0][rank] = nil
            newBoard.squares[3][rank] = rook
        }

        // Update castling rights
        if move.piece.type == .king {
            if move.piece.color == .white {
                newBoard.whiteCanCastleKingside = false
                newBoard.whiteCanCastleQueenside = false
            } else {
                newBoard.blackCanCastleKingside = false
                newBoard.blackCanCastleQueenside = false
            }
        }
        if move.piece.type == .rook {
            if move.from == BoardPosition(file: 0, rank: 0) { newBoard.whiteCanCastleQueenside = false }
            if move.from == BoardPosition(file: 7, rank: 0) { newBoard.whiteCanCastleKingside = false }
            if move.from == BoardPosition(file: 0, rank: 7) { newBoard.blackCanCastleQueenside = false }
            if move.from == BoardPosition(file: 7, rank: 7) { newBoard.blackCanCastleKingside = false }
        }
        // If a rook is captured on its starting square
        if move.to == BoardPosition(file: 0, rank: 0) { newBoard.whiteCanCastleQueenside = false }
        if move.to == BoardPosition(file: 7, rank: 0) { newBoard.whiteCanCastleKingside = false }
        if move.to == BoardPosition(file: 0, rank: 7) { newBoard.blackCanCastleQueenside = false }
        if move.to == BoardPosition(file: 7, rank: 7) { newBoard.blackCanCastleKingside = false }

        // Update en passant target
        if move.piece.type == .pawn && abs(move.to.rank - move.from.rank) == 2 {
            let epRank = (move.from.rank + move.to.rank) / 2
            newBoard.enPassantTarget = BoardPosition(file: move.from.file, rank: epRank)
        } else {
            newBoard.enPassantTarget = nil
        }

        // Update half-move clock
        if move.piece.type == .pawn || move.capturedPiece != nil {
            newBoard.halfMoveClock = 0
        } else {
            newBoard.halfMoveClock = halfMoveClock + 1
        }

        // Update full move number
        if move.piece.color == .black {
            newBoard.fullMoveNumber = fullMoveNumber + 1
        }

        // Switch active color
        newBoard.activeColor = activeColor.opposite

        return newBoard
    }

    // MARK: - Material Calculation

    func materialValue(for color: PieceColor) -> Int {
        allPieces(color: color).reduce(0) { $0 + $1.piece.type.value }
    }

    func capturedPieces(for color: PieceColor) -> [PieceType] {
        // Calculate based on what's missing from the starting set
        let startingPieces: [PieceType: Int] = [
            .pawn: 8, .knight: 2, .bishop: 2, .rook: 2, .queen: 1, .king: 1
        ]
        var currentCounts: [PieceType: Int] = [:]
        for (piece, _) in allPieces(color: color) {
            currentCounts[piece.type, default: 0] += 1
        }

        var captured: [PieceType] = []
        for (type, startCount) in startingPieces {
            let current = currentCounts[type, default: 0]
            let missing = max(0, startCount - current)
            for _ in 0..<missing {
                captured.append(type)
            }
        }
        return captured.sorted { $0.value > $1.value }
    }
}
