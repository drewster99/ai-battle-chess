import SwiftUI

// MARK: - Move History View

struct MoveHistoryView: View {
    @Bindable var engine: GameEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Navigation controls
            navigationControls

            Divider()

            // Move list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(movePairs.enumerated()), id: \.offset) { index, pair in
                            moveRow(number: index + 1, pair: pair, proxy: proxy)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onChange(of: engine.moveHistory.count) { _, _ in
                    if !engine.isViewingHistory, let lastIndex = movePairs.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
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

    // MARK: - Navigation Controls

    private var navigationControls: some View {
        HStack(spacing: 8) {
            Button { engine.navigateFirst() } label: {
                Image(systemName: "backward.end.fill")
            }
            .disabled(engine.moveHistory.isEmpty)

            Button { engine.navigatePrevious() } label: {
                Image(systemName: "backward.fill")
            }
            .disabled(engine.moveHistory.isEmpty)

            Spacer()

            if engine.isViewingHistory {
                Text("Move \((engine.viewingMoveIndex ?? 0) + 1) of \(engine.moveHistory.count)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text("Live")
                    .font(.body.bold())
                    .foregroundStyle(.green)
            }

            Spacer()

            if engine.isViewingHistory {
                // Replace forward buttons with "Return to Live"
                Button("Return to Live") {
                    engine.returnToLive()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.green)
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
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
        // Fallback to dynamic computation if cache is not yet populated
        guard index < engine.moveHistory.count && index < engine.boardStates.count else { return "?" }
        return PGNFormatter.moveToSAN(engine.moveHistory[index], on: engine.boardStates[index])
    }

    // MARK: - Move Row

    private func moveRow(number: Int, pair: MovePair, proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 4) {
            Text("\(number).")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            moveButton(san: pair.whiteSAN, index: pair.whiteIndex)

            if let blackSAN = pair.blackSAN, let blackIndex = pair.blackIndex {
                moveButton(san: blackSAN, index: blackIndex)
            }

            Spacer()
        }
        .id(number - 1)
    }

    private func moveButton(san: String, index: Int) -> some View {
        let isViewing = engine.viewingMoveIndex == index
        let isLastMove = !engine.isViewingHistory && index == engine.moveHistory.count - 1

        return Button {
            engine.navigateToMove(index)
        } label: {
            Text(san)
                .font(.caption.monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isViewing ? Color.accentColor.opacity(0.3) :
                              isLastMove ? Color.accentColor.opacity(0.1) :
                              Color.clear)
                )
        }
        .buttonStyle(.plain)
        .frame(minWidth: 48, alignment: .leading)
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
