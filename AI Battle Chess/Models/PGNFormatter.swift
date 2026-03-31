import Foundation

// MARK: - PGN Formatter

/// Formats chess moves in Standard Algebraic Notation (SAN) and full PGN format.
struct PGNFormatter {

    /// Converts a ChessMove to SAN notation given the board state BEFORE the move.
    static func moveToSAN(_ move: ChessMove, on board: ChessBoard) -> String {
        // Castling
        if move.isCastleKingside { return addCheckSuffix("O-O", move: move) }
        if move.isCastleQueenside { return addCheckSuffix("O-O-O", move: move) }

        var san = ""

        if move.piece.type == .pawn {
            // Pawn moves
            if move.capturedPiece != nil || move.isEnPassant {
                if let scalar = UnicodeScalar(97 + move.from.file) {
                    san += String(Character(scalar))
                }
                san += "x"
            }
            san += move.to.description

            // Promotion
            if let promoType = move.promotionType {
                san += "=\(promoType.notation)"
            }
        } else {
            // Piece moves
            san += move.piece.type.notation

            // Disambiguation: check if other pieces of the same type can reach the same square
            let disambiguation = disambiguationString(for: move, on: board)
            san += disambiguation

            // Capture
            if move.capturedPiece != nil {
                san += "x"
            }

            san += move.to.description
        }

        return addCheckSuffix(san, move: move)
    }

    /// Generates a full PGN string for the game.
    static func generatePGN(
        moves: [ChessMove],
        boardStates: [ChessBoard],
        result: GameResult?,
        whiteName: String = "White",
        blackName: String = "Black",
        event: String = "AI Battle Chess",
        date: Date = Date(),
        gameID: UUID? = nil
    ) -> String {
        var pgn = ""

        // Headers
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy.MM.dd"
        let dateString = dateFormatter.string(from: date)

        pgn += "[Event \"\(event)\"]\n"
        pgn += "[Site \"AI Battle Chess App\"]\n"
        pgn += "[Date \"\(dateString)\"]\n"
        pgn += "[White \"\(escapePGNString(whiteName))\"]\n"
        pgn += "[Black \"\(escapePGNString(blackName))\"]\n"
        pgn += "[Result \"\(result?.pgnResult ?? "*")\"]\n"

        // Extended headers
        if let gameID {
            pgn += "[GameID \"\(gameID.uuidString)\"]\n"
        }
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        pgn += "[AppVersion \"\(appVersion)\"]\n"
        pgn += "[Platform \"\(ProcessInfo.processInfo.operatingSystemVersionString)\"]\n"
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        pgn += "[System \"\(ramGB)GB RAM\"]\n"

        pgn += "\n"

        // Moves
        for (index, move) in moves.enumerated() {
            guard index < boardStates.count else { break }
            let boardBefore = boardStates[index]
            let san = moveToSAN(move, on: boardBefore)

            if index % 2 == 0 {
                let moveNum = (index / 2) + 1
                pgn += "\(moveNum). "
            }
            pgn += san

            if index < moves.count - 1 {
                pgn += " "
            }
        }

        // Result
        if let result {
            if let comment = result.pgnResultComment {
                pgn += " {\(comment)}"
            }
            pgn += " \(result.pgnResult)"
        }

        return pgn
    }

    /// Parses a simple move notation string (e.g. "e2e4", "e7e8q", "Nf3") into from/to positions.
    /// Returns (from, to, promotionType) or nil if parse fails.
    static func parseAIMoveNotation(_ notation: String, on board: ChessBoard) -> (from: BoardPosition, to: BoardPosition, promotion: PieceType?)? {
        let trimmed = notation.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "#", with: "")

        // Try coordinate notation first: e2e4, e7e8q
        if trimmed.count >= 4 && trimmed.count <= 5 {
            let chars = Array(trimmed.lowercased())
            if chars[0] >= "a" && chars[0] <= "h" && chars[1] >= "1" && chars[1] <= "8" &&
               chars[2] >= "a" && chars[2] <= "h" && chars[3] >= "1" && chars[3] <= "8" {
                let fromStr = String(chars[0...1])
                let toStr = String(chars[2...3])
                if let from = BoardPosition(algebraic: fromStr), let to = BoardPosition(algebraic: toStr) {
                    var promotion: PieceType? = nil
                    if chars.count == 5 {
                        promotion = pieceTypeFromChar(chars[4])
                    }
                    return (from, to, promotion)
                }
            }
        }

        // Try SAN notation
        return parseSAN(trimmed, on: board)
    }

    /// Parses SAN notation (e.g., "Nf3", "exd5", "O-O", "e8=Q") and resolves to from/to.
    static func parseSAN(_ san: String, on board: ChessBoard) -> (from: BoardPosition, to: BoardPosition, promotion: PieceType?)? {
        var s = san.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "#", with: "")

        // Castling
        if s == "O-O" || s == "0-0" {
            let rank = board.activeColor == .white ? 0 : 7
            return (BoardPosition(file: 4, rank: rank), BoardPosition(file: 6, rank: rank), nil)
        }
        if s == "O-O-O" || s == "0-0-0" {
            let rank = board.activeColor == .white ? 0 : 7
            return (BoardPosition(file: 4, rank: rank), BoardPosition(file: 2, rank: rank), nil)
        }

        // Promotion (with = separator, e.g. "e8=Q")
        var promotion: PieceType? = nil
        if let eqIndex = s.firstIndex(of: "=") {
            let promoCharIndex = s.index(after: eqIndex)
            if promoCharIndex < s.endIndex {
                promotion = pieceTypeFromChar(Character(s[promoCharIndex].lowercased()))
            }
            s = String(s[s.startIndex..<eqIndex])
        }

        // Promotion without = separator (e.g. "e8Q")
        if promotion == nil, let lastChar = s.last, "QRBNqrbn".contains(String(lastChar)) {
            let withoutLast = String(s.dropLast())
            if withoutLast.count >= 2 {
                let potentialDest = String(withoutLast.suffix(2))
                if let dest = BoardPosition(algebraic: potentialDest) {
                    let promoRank = board.activeColor == .white ? 7 : 0
                    if dest.rank == promoRank {
                        promotion = pieceTypeFromChar(Character(lastChar.lowercased()))
                        s = withoutLast
                    }
                }
            }
        }

        // Remove capture symbol
        let isCapture = s.contains("x")
        s = s.replacingOccurrences(of: "x", with: "")

        guard !s.isEmpty else { return nil }

        // Determine piece type
        let pieceType: PieceType
        var remaining = s
        guard let first = remaining.first else { return nil }
        if first.isUppercase {
            guard let pt = pieceTypeFromNotation(first) else { return nil }
            pieceType = pt
            remaining = String(remaining.dropFirst())
        } else {
            pieceType = .pawn
        }

        guard remaining.count >= 2 else { return nil }

        // The destination square is the last 2 characters
        let destStr = String(remaining.suffix(2))
        guard let dest = BoardPosition(algebraic: destStr) else { return nil }

        // Disambiguation characters (if any) are whatever's left before the destination
        let disambig = String(remaining.dropLast(2))

        // Find matching legal move
        let allMoves = MoveValidator.allLegalMoves(for: board)
        let candidates = allMoves.filter { move in
            move.piece.type == pieceType &&
            move.piece.color == board.activeColor &&
            move.to == dest &&
            (promotion == nil || move.promotionType == promotion)
        }

        if candidates.count == 1 {
            let m = candidates[0]
            return (m.from, m.to, m.promotionType ?? promotion)
        }

        // Apply disambiguation
        if !disambig.isEmpty {
            let filtered = candidates.filter { move in
                for ch in disambig {
                    if ch >= "a" && ch <= "h" {
                        guard let ascii = ch.asciiValue else { return false }
                        let fileVal = Int(ascii) - 97
                        if move.from.file != fileVal { return false }
                    } else if ch >= "1" && ch <= "8" {
                        guard let rankVal = ch.wholeNumberValue else { return false }
                        if move.from.rank != rankVal - 1 { return false }
                    }
                }
                return true
            }
            if filtered.count == 1 {
                let m = filtered[0]
                return (m.from, m.to, m.promotionType ?? promotion)
            }
        }

        // For pawn captures, first char might be the source file
        if pieceType == .pawn && isCapture && !disambig.isEmpty,
           let firstChar = disambig.first,
           firstChar >= "a" && firstChar <= "h",
           let ascii = firstChar.asciiValue {
            let sourceFile = Int(ascii) - 97
            let match = candidates.first { $0.from.file == sourceFile }
            if let m = match {
                return (m.from, m.to, m.promotionType ?? promotion)
            }
        }

        // Genuinely ambiguous — return nil to force the caller to request clarification
        return nil
    }

    // MARK: - Helpers

    private static func addCheckSuffix(_ san: String, move: ChessMove) -> String {
        if move.isCheckmate { return san + "#" }
        if move.isCheck { return san + "+" }
        return san
    }

    private static func disambiguationString(for move: ChessMove, on board: ChessBoard) -> String {
        // Find other pieces of the same type and color that can reach the same square
        let sameTypePieces = board.allPieces(color: move.piece.color).filter {
            $0.piece.type == move.piece.type && $0.position != move.from
        }

        let competing = sameTypePieces.filter { (piece, pos) in
            let moves = MoveValidator.legalMoves(for: piece, at: pos, on: board)
            return moves.contains { $0.to == move.to }
        }

        guard !competing.isEmpty else { return "" }

        let sameFile = competing.contains { $0.position.file == move.from.file }
        let sameRank = competing.contains { $0.position.rank == move.from.rank }

        if !sameFile, let scalar = UnicodeScalar(97 + move.from.file) {
            return String(Character(scalar))
        } else if !sameRank {
            return "\(move.from.rank + 1)"
        } else {
            return move.from.description
        }
    }

    private static func pieceTypeFromChar(_ ch: Character) -> PieceType? {
        switch ch {
        case "q": return .queen
        case "r": return .rook
        case "b": return .bishop
        case "n": return .knight
        case "k": return .king
        default: return nil
        }
    }

    private static func pieceTypeFromNotation(_ ch: Character) -> PieceType? {
        switch ch {
        case "Q": return .queen
        case "R": return .rook
        case "B": return .bishop
        case "N": return .knight
        case "K": return .king
        default: return nil
        }
    }

    private static func escapePGNString(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\")
              .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
