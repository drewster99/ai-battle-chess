import SwiftUI

// MARK: - Head-to-Head Bar

/// Compact, expandable bar showing head-to-head stats between two players.
struct HeadToHeadBar: View {
    let whiteName: String
    let blackName: String
    let games: [GameRecord]

    @State private var isExpanded = false

    // MARK: - Aggregated Stats

    private var totalGames: Int { games.count }

    private var winsForWhiteName: Int {
        games.filter { record in
            switch record.result {
            case .checkmate(let winner), .resignation(let winner):
                if record.whitePlayerName == whiteName {
                    return winner == .white
                } else {
                    return winner == .black
                }
            default:
                return false
            }
        }.count
    }

    private var winsForBlackName: Int {
        games.filter { record in
            switch record.result {
            case .checkmate(let winner), .resignation(let winner):
                if record.whitePlayerName == blackName {
                    return winner == .white
                } else {
                    return winner == .black
                }
            default:
                return false
            }
        }.count
    }

    private var draws: Int {
        totalGames - winsForWhiteName - winsForBlackName
    }

    private func pct(_ n: Int) -> String {
        guard totalGames > 0 else { return "0%" }
        return String(format: "%.0f%%", Double(n) / Double(totalGames) * 100)
    }

    private var totalElapsed: TimeInterval {
        games.reduce(0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
    }

    private var totalMoves: Int {
        games.reduce(0) { $0 + $1.moveCount }
    }

    private var avgMovesPerGame: Double {
        guard totalGames > 0 else { return 0 }
        return Double(totalMoves) / Double(totalGames)
    }

    // Per-player aggregate stats (mapped to whiteName / blackName regardless of which color they played)
    private func totalMovesFor(playerName: String) -> Int {
        games.reduce(0) { total, record in
            if record.whitePlayerName == playerName {
                return total + (record.statistics.perMoveDuration[.white]?.count ?? 0)
            } else {
                return total + (record.statistics.perMoveDuration[.black]?.count ?? 0)
            }
        }
    }

    private func totalTimeFor(playerName: String) -> TimeInterval {
        games.reduce(0) { total, record in
            if record.whitePlayerName == playerName {
                return total + (record.statistics.perMoveDuration[.white] ?? []).reduce(0, +)
            } else {
                return total + (record.statistics.perMoveDuration[.black] ?? []).reduce(0, +)
            }
        }
    }

    private func avgTimePerMoveFor(playerName: String) -> TimeInterval {
        let moves = totalMovesFor(playerName: playerName)
        guard moves > 0 else { return 0 }
        return totalTimeFor(playerName: playerName) / Double(moves)
    }

    private func totalCapturesFor(playerName: String) -> Int {
        games.reduce(0) { total, record in
            let color: PieceColor = record.whitePlayerName == playerName ? .white : .black
            return total + (record.statistics.captureCount[color] ?? 0)
        }
    }

    private func totalChecksFor(playerName: String) -> Int {
        games.reduce(0) { total, record in
            let color: PieceColor = record.whitePlayerName == playerName ? .white : .black
            return total + (record.statistics.checkCount[color] ?? 0)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Compact summary row (always visible)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)

                    Text("\(totalGames) prior \(totalGames == 1 ? "game" : "games") between these opponents")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Win bar visualization
                    winBar

                    Spacer()

                    HStack(spacing: 10) {
                        HStack(spacing: 3) {
                            Circle().fill(Color.blue).frame(width: 6, height: 6)
                            Text("\(winsForWhiteName)")
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(.blue)
                            Text(pct(winsForWhiteName))
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 3) {
                            Circle().fill(Color.red).frame(width: 6, height: 6)
                            Text("\(winsForBlackName)")
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(.red)
                            Text(pct(winsForBlackName))
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if draws > 0 {
                            HStack(spacing: 3) {
                                Circle().fill(Color.gray).frame(width: 6, height: 6)
                                Text("\(draws)")
                                    .font(.caption.monospacedDigit().bold())
                                    .foregroundStyle(.gray)
                                Text(pct(draws))
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            // Expanded detail section
            if isExpanded {
                expandedStats
                    .padding(.top, 6)
            }
        }
    }

    // MARK: - Win Bar

    private var winBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let wPct = totalGames > 0 ? CGFloat(winsForWhiteName) / CGFloat(totalGames) : 0
            let bPct = totalGames > 0 ? CGFloat(winsForBlackName) / CGFloat(totalGames) : 0

            HStack(spacing: 1) {
                if winsForWhiteName > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue.opacity(0.6))
                        .frame(width: max(width * wPct, 2))
                }
                if draws > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: max(width * (1 - wPct - bPct), 2))
                }
                if winsForBlackName > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red.opacity(0.6))
                        .frame(width: max(width * bPct, 2))
                }
            }
        }
        .frame(width: 80, height: 6)
    }

    // MARK: - Stat Badge

    private func statBadge(label: String, value: String, pctText: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(color)
            Text(pctText)
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Expanded Stats

    private var expandedStats: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left: aggregate totals
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                aggRow("Games", "\(totalGames)")
                aggRow("Total moves", "\(totalMoves)")
                aggRow("Avg moves/game", String(format: "%.0f", avgMovesPerGame))
                aggRow("Total time", formatDuration(totalElapsed))
                if draws > 0 {
                    aggRow("Draws", "\(draws) (\(pct(draws)))")
                }
            }

            Spacer(minLength: 16)

            Divider().frame(height: 70)

            Spacer(minLength: 16)

            // Right: per-player comparison
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow {
                    Text("")
                        .gridColumnAlignment(.trailing)
                    Text(whiteName)
                        .font(.caption2.bold())
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .gridColumnAlignment(.trailing)
                    Text(blackName)
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .gridColumnAlignment(.trailing)
                }

                comparisonRow("Wins", v1: "\(winsForWhiteName) (\(pct(winsForWhiteName)))", v2: "\(winsForBlackName) (\(pct(winsForBlackName)))")
                comparisonRow("Moves", v1: "\(totalMovesFor(playerName: whiteName))", v2: "\(totalMovesFor(playerName: blackName))")
                comparisonRow("Avg/move", v1: formatDuration(avgTimePerMoveFor(playerName: whiteName)), v2: formatDuration(avgTimePerMoveFor(playerName: blackName)))
                comparisonRow("Captures", v1: "\(totalCapturesFor(playerName: whiteName))", v2: "\(totalCapturesFor(playerName: blackName))")
                comparisonRow("Checks", v1: "\(totalChecksFor(playerName: whiteName))", v2: "\(totalChecksFor(playerName: blackName))")
            }
        }
        .font(.caption2)
    }

    private func aggRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .monospacedDigit()
                .gridColumnAlignment(.leading)
        }
    }


    private func comparisonRow(_ label: String, v1: String, v2: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(v1)
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
            Text(v2)
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
        }
    }


    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return String(format: "%.0fms", seconds * 1000)
        } else if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else if seconds < 3600 {
            let mins = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return "\(mins)m \(secs)s"
        } else {
            let hrs = Int(seconds) / 3600
            let mins = (Int(seconds) % 3600) / 60
            return "\(hrs)h \(mins)m"
        }
    }
}
