import SwiftUI

// MARK: - Chess Board View

struct ChessBoardView: View {
    @Bindable var engine: GameEngine
    let squareSize: CGFloat

    private let lightSquareColor = Color(red: 0.94, green: 0.85, blue: 0.71)
    private let darkSquareColor = Color(red: 0.71, green: 0.53, blue: 0.39)
    private let selectedColor = Color.blue.opacity(0.4)
    private let legalMoveColor = Color.green.opacity(0.4)
    private let lastMoveColor = Color.yellow.opacity(0.35)
    private let checkColor = Color.red.opacity(0.5)

    var body: some View {
        VStack(spacing: 0) {
            // Rank labels + board
            HStack(spacing: 0) {
                // File labels spacer
                Color.clear.frame(width: 20, height: 0)

                // Board
                VStack(spacing: 0) {
                    ForEach((0..<8).reversed(), id: \.self) { rank in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { file in
                                squareView(file: file, rank: rank)
                            }
                        }
                    }
                }
                .border(Color.primary.opacity(0.3), width: 1)

                // Rank numbers on right
                VStack(spacing: 0) {
                    ForEach((0..<8).reversed(), id: \.self) { rank in
                        Text("\(rank + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: squareSize)
                    }
                }
            }

            // File labels at bottom
            HStack(spacing: 0) {
                Color.clear.frame(width: 20, height: 20)
                ForEach(0..<8, id: \.self) { file in
                    Text(String(Character(UnicodeScalar(97 + file) ?? UnicodeScalar(63))))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: squareSize, height: 20)
                }
                Color.clear.frame(width: 20, height: 20)
            }
        }
        .overlay {
            if engine.pendingPromotion != nil {
                promotionOverlay
            }
        }
    }

    // MARK: - Square View

    @ViewBuilder
    private func squareView(file: Int, rank: Int) -> some View {
        let position = BoardPosition(file: file, rank: rank)
        let isLight = (file + rank) % 2 != 0
        let displayBoard = engine.displayBoard
        let piece = displayBoard.piece(at: position)

        let isSelected = engine.selectedSquare == position
        let isLegalMove = engine.legalMovesForSelected.contains(position)
        let isLastMoveFrom = engine.lastMove?.from == position && !engine.isViewingHistory
        let isLastMoveTo = engine.lastMove?.to == position && !engine.isViewingHistory
        let isKingInCheck = isKingInCheckAt(position, on: displayBoard)

        ZStack {
            // Base square color
            Rectangle()
                .fill(isLight ? lightSquareColor : darkSquareColor)

            // Highlights
            if isSelected {
                Rectangle().fill(selectedColor)
            } else if isLastMoveFrom || isLastMoveTo {
                Rectangle().fill(lastMoveColor)
            }

            if isKingInCheck {
                Rectangle().fill(checkColor)
            }

            // Legal move indicator
            if isLegalMove {
                if piece != nil {
                    // Capture indicator - ring around the square
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(legalMoveColor, lineWidth: 3)
                } else {
                    // Empty square indicator - dot in center
                    Circle()
                        .fill(legalMoveColor)
                        .frame(width: squareSize * 0.3, height: squareSize * 0.3)
                }
            }

            // Piece rendering with animation
            if let piece {
                if let animating = engine.animatingMove {
                    if animating.to == position {
                        // Piece being animated TO this square — offset from source
                        PieceView(piece: piece, size: squareSize)
                            .offset(
                                x: CGFloat(engine.animatingFileDelta) * squareSize,
                                y: -CGFloat(engine.animatingRankDelta) * squareSize
                            )
                            .zIndex(10)
                    } else if animating.from == position {
                        // Source square during animation — empty
                        EmptyView()
                    } else {
                        PieceView(piece: piece, size: squareSize)
                    }
                } else {
                    PieceView(piece: piece, size: squareSize)
                }
            }
        }
        .frame(width: squareSize, height: squareSize)
        .clipped()
        .onTapGesture {
            engine.selectSquare(position)
        }
    }

    private func isKingInCheckAt(_ position: BoardPosition, on board: ChessBoard) -> Bool {
        guard let piece = board.piece(at: position),
              piece.type == .king else { return false }
        return MoveValidator.isKingInCheck(color: piece.color, on: board)
    }

    // MARK: - Promotion Overlay

    private var promotionOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)

            VStack(spacing: 16) {
                Text("Choose Promotion")
                    .font(.headline)
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
                    ForEach([PieceType.queen, .rook, .bishop, .knight], id: \.self) { type in
                        Button {
                            engine.selectPromotion(type)
                        } label: {
                            // Use the piece color of the pawn that is promoting (the player
                            // whose turn it was when promotion was triggered)
                            let promoColor: PieceColor = {
                                if let from = engine.pendingPromotion?.from,
                                   let piece = engine.board.piece(at: from) {
                                    return piece.color
                                }
                                return engine.board.activeColor
                            }()
                            let tempPiece = ChessPiece(color: promoColor, type: type)
                            PieceView(piece: tempPiece, size: squareSize * 1.2)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.ultraThinMaterial)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Cancel") {
                    engine.cancelPromotion()
                }
                .foregroundStyle(.white)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThickMaterial)
            )
        }
    }
}

// MARK: - Piece View

struct PieceView: View {
    let piece: ChessPiece
    let size: CGFloat

    var body: some View {
        Image(piece.assetName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size * 0.85, height: size * 0.85)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
    }
}
