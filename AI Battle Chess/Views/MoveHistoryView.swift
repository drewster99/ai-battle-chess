import SwiftUI

// MARK: - Move History View

struct MoveHistoryView: View {
    @Bindable var engine: GameEngine

    private let columnsPerRow = 5

    /// The currently focused move (selected or last move in live view)
    private var focusedMove: ChessMove? {
        if let index = engine.viewingMoveIndex, index < engine.moveHistory.count {
            return engine.moveHistory[index]
        } else if !engine.isViewingHistory, let last = engine.moveHistory.last {
            return last
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top bar: comment/thinking for focused move + live indicator
            topBar

            Divider()

            // Move list in column-first layout
            ScrollViewReader { proxy in
                ScrollView {
                    let pairs = movePairs
                    let numRows = pairs.isEmpty ? 0 : (pairs.count + columnsPerRow - 1) / columnsPerRow

                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(0..<numRows, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<columnsPerRow, id: \.self) { col in
                                    let pairIndex = col * numRows + row
                                    if pairIndex < pairs.count {
                                        let pair = pairs[pairIndex]
                                        moveCell(number: pairIndex + 1, pair: pair)
                                    } else {
                                        Spacer()
                                            .frame(minWidth: 100)
                                    }
                                    if col < columnsPerRow - 1 {
                                        Divider()
                                            .frame(height: 16)
                                            .padding(.horizontal, 2)
                                    }
                                }
                                Spacer()
                            }
                            .id(row)
                        }

                        // Game result at end
                        if let result = engine.gameResult {
                            HStack(spacing: 6) {
                                Text(result.pgnResult)
                                    .font(.caption.monospaced().bold())
                                    .foregroundStyle(.orange)
                                Text(result.displayText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)
                            .id("gameResult")
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onChange(of: engine.moveHistory.count, initial: false) { _, _ in
                    if !engine.isViewingHistory {
                        let pairs = movePairs
                        let numRows = pairs.isEmpty ? 0 : (pairs.count + columnsPerRow - 1) / columnsPerRow
                        if numRows > 0 {
                            withAnimation {
                                proxy.scrollTo(numRows - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            // PGN export
            if !engine.moveHistory.isEmpty {
                Divider()
                pgnSection
            }
        }
        .padding(8)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {
            // Comment or thinking from focused move
            if let move = focusedMove {
                if let comment = move.comment, !comment.isEmpty {
                    Image(systemName: "text.bubble")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                } else if let thinking = move.thinking, !thinking.isEmpty {
                    Image(systemName: "brain")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text(thinking)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(2)
                }
            }

            Spacer()

            if engine.isViewingHistory {
                Text("Move \((engine.viewingMoveIndex ?? 0) + 1) of \(engine.moveHistory.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Return to Live") {
                    engine.returnToLive()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(.green)
            } else if engine.isGameActive {
                Text("Live")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }
        }
        .frame(minHeight: 20)
    }

    // MARK: - Move Pairs

    private struct MovePair {
        let whiteIndex: Int
        let whiteSAN: String
        let blackIndex: Int?
        let blackSAN: String?
    }

    private var movePairs: [MovePair] {
        var pairs: [MovePair] = []
        var i = 0
        while i < engine.moveHistory.count {
            let whiteSAN = sanForMove(at: i)
            var blackSAN: String? = nil
            var blackIndex: Int? = nil
            if i + 1 < engine.moveHistory.count {
                blackIndex = i + 1
                blackSAN = sanForMove(at: i + 1)
            }
            pairs.append(MovePair(whiteIndex: i, whiteSAN: whiteSAN, blackIndex: blackIndex, blackSAN: blackSAN))
            i += 2
        }
        return pairs
    }

    private func sanForMove(at index: Int) -> String {
        if index < engine.moveSANCache.count {
            return engine.moveSANCache[index]
        }
        guard index < engine.moveHistory.count && index < engine.boardStates.count else { return "?" }
        return PGNFormatter.moveToSAN(engine.moveHistory[index], on: engine.boardStates[index])
    }

    // MARK: - Move Cell

    private func moveCell(number: Int, pair: MovePair) -> some View {
        HStack(spacing: 0) {
            Text("\(number).")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 24, alignment: .trailing)

            moveButton(san: pair.whiteSAN, index: pair.whiteIndex)
                .frame(width: 58, alignment: .leading)

            if let blackSAN = pair.blackSAN, let blackIndex = pair.blackIndex {
                moveButton(san: blackSAN, index: blackIndex)
                    .frame(width: 58, alignment: .leading)
            } else {
                Spacer().frame(width: 58)
            }
        }
    }

    private func moveButton(san: String, index: Int) -> some View {
        let isViewing = engine.viewingMoveIndex == index
        let isLastMove = !engine.isViewingHistory && index == engine.moveHistory.count - 1
        let move = index < engine.moveHistory.count ? engine.moveHistory[index] : nil
        let hasComment = move?.comment != nil || move?.thinking != nil

        return Button {
            engine.navigateToMove(index)
        } label: {
            HStack(spacing: 2) {
                Text(san)
                    .font(.caption.monospaced())
                if hasComment {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.blue.opacity(0.5))
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isViewing ? Color.accentColor.opacity(0.3) :
                          isLastMove ? Color.accentColor.opacity(0.1) :
                          Color.clear)
            )
        }
        .buttonStyle(.plain)
        .frame(minWidth: 40, alignment: .leading)
    }

    // MARK: - PGN Section

    private var pgnSection: some View {
        HStack {
            Button {
                let pgn = engine.currentPGN
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pgn, forType: .string)
            } label: {
                Label("Copy PGN", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            Spacer()
        }
    }
}
