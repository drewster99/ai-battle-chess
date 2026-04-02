import SwiftUI

// MARK: - Content View

struct ContentView: View {
    @Bindable var engine: GameEngine
    @State private var showNewGameConfirmation = false
    @State private var showSetup = true
    @FocusState private var isGameFocused: Bool

    // Autostart
    @AppStorage("autostartNextGame") private var autostartNextGame = false
    @State private var autostartCountdown: Int = 0
    @State private var autostartTimer: Timer? = nil

    /// Background tint when viewing historical moves
    private var historyTint: Color {
        engine.isViewingHistory ? Color.orange.opacity(0.06) : Color.clear
    }

    var body: some View {
        gameView
            .frame(minWidth: 1400, minHeight: 700)
            .background(historyTint)
            .animation(.easeInOut(duration: 0.3), value: engine.isViewingHistory)
            .onChange(of: engine.gameResult, initial: false) { _, newResult in
                if newResult != nil, autostartNextGame, !engine.isViewingPastGame {
                    startAutostartCountdown()
                }
            }
            .sheet(isPresented: $showSetup) {
                GameSetupView(engine: engine)
            }
    }

    // MARK: - Game View

    private var gameView: some View {
        VStack(spacing: 0) {
            // Status bar
            statusBar

            Divider()

            // Main content: Player Panel | Board | Player Panel
            HStack(spacing: 0) {
                // White player panel (left)
                PlayerPanelView(engine: engine, color: .white)
                    .frame(width: 380)
                    .fixedSize(horizontal: true, vertical: false)

                Divider()

                // Center: Game Info + Board + Move History
                VStack(spacing: 0) {
                    // Game info bar
                    gameInfoBar
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

                    // Head-to-head stats (if prior games exist)
                    let matchupGames = engine.gameHistoryManager.gamesBetween(
                        white: engine.whitePlayer.name,
                        black: engine.blackPlayer.name
                    )
                    if !matchupGames.isEmpty {
                        Divider()
                        HeadToHeadBar(
                            whiteName: engine.whitePlayer.name,
                            blackName: engine.blackPlayer.name,
                            games: matchupGames
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }

                    Divider()

                    GeometryReader { geo in
                        let availableHeight = geo.size.height - 20
                        let availableWidth = geo.size.width - 40
                        let computedSize = min(availableWidth, availableHeight) / 8

                        VStack(spacing: 8) {
                            Spacer()

                            ChessBoardView(engine: engine, squareSize: max(computedSize, 40))

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    Divider()

                    // Move history at the bottom center
                    MoveHistoryView(engine: engine)
                        .frame(height: 170)
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(-1)

                Divider()

                // Black player panel (right)
                PlayerPanelView(engine: engine, color: .black)
                    .frame(width: 380)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .overlay(alignment: .center) {
            if autostartCountdown > 0 {
                autostartOverlay
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let error = engine.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
                    .padding(.bottom, 180)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { engine.errorMessage = nil }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: engine.errorMessage)
        .animation(.easeInOut(duration: 0.3), value: autostartCountdown > 0)
        .focusable()
        .focused($isGameFocused)
        .onAppear { isGameFocused = true }
        .onDisappear { cancelAutostart() }
        .onKeyPress(.leftArrow) { engine.navigatePrevious(); return .handled }
        .onKeyPress(.rightArrow) { engine.navigateNext(); return .handled }
        .onKeyPress(.upArrow) { engine.navigateToPreviousGame(); return .handled }
        .onKeyPress(.downArrow) { engine.navigateToNextGame(); return .handled }
        .onKeyPress(.space) { engine.navigateNextAnimated(); return .handled }
        .confirmationDialog(
            "Abandon current game?",
            isPresented: $showNewGameConfirmation,
            titleVisibility: .visible
        ) {
            Button("Abandon Game", role: .destructive) {
                engine.stopGame()
                showSetup = true
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        ZStack {
            // Left-aligned: game mode indicator
            HStack {
                Label(engine.gameMode.rawValue, systemImage: gameModeIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Center: turn indicator (always centered)
            HStack(spacing: 8) {
                if engine.isAIThinking {
                    ProgressView()
                        .controlSize(.small)
                }
                turnIndicatorText
            }

            // Right-aligned: actions
            HStack {
                Spacer()

                Toggle("Autostart", isOn: $autostartNextGame)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .instantHelp("Automatically start the next game after the current one ends")
                    .onChange(of: autostartNextGame) { _, newValue in
                        if !newValue {
                            cancelAutostart()
                        }
                    }

                Button("New Game") {
                    cancelAutostart()
                    if engine.isGameActive {
                        showNewGameConfirmation = true
                    } else {
                        showSetup = true
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Autostart Overlay

    private var autostartOverlay: some View {
        VStack(spacing: 12) {
            Text("New game in")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("\(autostartCountdown)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)

            Text("seconds")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button("Cancel") {
                autostartNextGame = false
                cancelAutostart()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThickMaterial)
                .shadow(radius: 20)
        )
    }

    // MARK: - Autostart Logic

    private func startAutostartCountdown() {
        cancelAutostart()

        let hasHuman = !engine.whitePlayer.isAI || !engine.blackPlayer.isAI
        autostartCountdown = hasHuman ? 30 : 8

        autostartTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                guard autostartCountdown > 0 else { return }
                if autostartCountdown > 1 {
                    autostartCountdown -= 1
                } else {
                    cancelAutostart()
                    engine.startNewGame()
                }
            }
        }
    }

    private func cancelAutostart() {
        autostartTimer?.invalidate()
        autostartTimer = nil
        autostartCountdown = 0
    }

    // MARK: - Game Info Bar

    private var gameInfoBar: some View {
        HStack(spacing: 16) {
            // Game ID
            let gameIDStr = String(engine.currentGameID.uuidString.prefix(8))
            Text("Game \(gameIDStr)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()

            Divider().frame(height: 28)

            // Start time + elapsed stacked
            VStack(alignment: .leading, spacing: 1) {
                if engine.isViewingPastGame || !Calendar.current.isDateInToday(engine.statistics.gameStartTime) {
                    Text("Started \(engine.statistics.gameStartTime, style: .date) \(engine.statistics.gameStartTime, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                } else {
                    Text("Started \(engine.statistics.gameStartTime, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }

                // Elapsed time — context-sensitive
                if engine.isViewingHistory, let viewIndex = engine.viewingMoveIndex {
                    let timestamps = engine.statistics.moveTimestamps
                    let moveTime = viewIndex < timestamps.count
                        ? timestamps[viewIndex]
                        : engine.statistics.gameStartTime
                    let elapsed = moveTime.timeIntervalSince(engine.statistics.gameStartTime)
                    Text("Elapsed: \(formatInfoBarDuration(elapsed))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                } else if engine.isGameActive && !engine.isViewingPastGame {
                    Text("Elapsed: \(engine.statistics.gameStartTime, style: .timer)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                } else {
                    let elapsed = (engine.statistics.moveTimestamps.last ?? engine.statistics.gameStartTime)
                        .timeIntervalSince(engine.statistics.gameStartTime)
                    Text("Duration: \(formatInfoBarDuration(elapsed))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }

            // 50-move rule counter (only show when nonzero)
            let halfMoveClock = engine.displayBoard.halfMoveClock
            if halfMoveClock > 0 {
                Divider().frame(height: 28)
                Text("50-move: \(halfMoveClock)/100")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(halfMoveClock >= 80 ? .orange : .secondary)
                    .fixedSize()
            }

            // Threefold repetition counter (only show when position repeated)
            let repCount = engine.currentPositionRepetitionCount
            if repCount > 1 {
                Divider().frame(height: 28)
                Text("Repetition: \(repCount)/3")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(repCount >= 2 ? .orange : .secondary)
                    .fixedSize()
            }

            Spacer()

            // Session stats
            let totalGames = engine.gameHistoryManager.totalGamesPlayed + (engine.isGameActive ? 1 : 0)
            Text("Session: \(totalGames) games")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
    }

    // MARK: - Helpers

    // MARK: - Turn Indicator

    @ViewBuilder
    private var turnIndicatorText: some View {
        if engine.isViewingPastGame, let index = engine.viewingGameIndex {
            let records = engine.gameHistoryManager.gameRecords
            if index < records.count {
                let gameID = String(records[index].id.uuidString.prefix(8))
                Text("Viewing game #\(gameID)")
                    .font(.title2.bold())
            }
        } else if engine.isViewingHistory {
            // Scrolling through moves in the current game — show whose turn it was
            let viewedBoard = engine.displayBoard
            let colorName = viewedBoard.activeColor.displayName
            let moveNum = (engine.viewingMoveIndex ?? 0) + 1
            HStack(spacing: 4) {
                Text(colorName)
                    .font(.title2.bold())
                Text("'s turn")
                    .font(.title2)
                Text("(move \(moveNum) of \(engine.moveHistory.count))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        } else if let result = engine.gameResult {
            Text(result.displayText)
                .font(.title2.bold())
        } else if engine.isGameActive {
            let player = engine.currentPlayer
            let colorName = engine.board.activeColor.displayName
            let config = player.aiConfigurationID.flatMap { id in
                engine.llmKit.configurations.first(where: { $0.id == id })
            }
            let provider = config.flatMap { c in
                engine.llmKit.providers.first(where: { $0.id == c.providerID })
            }

            HStack(spacing: 4) {
                Text(colorName)
                    .font(.title2.bold())
                Text("'s turn")
                    .font(.title2)

                if player.isAI {
                    Text("(")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    if let provider {
                        Text(provider.name)
                            .font(.title3.italic())
                            .foregroundStyle(.secondary)
                    }
                    if let config {
                        Text(config.modelID)
                            .font(.title3.italic())
                            .foregroundStyle(.blue)
                    } else if player.useAppleIntelligence {
                        let aiConfigName = player.appleIntelligenceConfigID
                            .flatMap { engine.appleIntelligenceConfigManager.config(byID: $0) }?.name
                            ?? "Apple Intelligence"
                        Text(aiConfigName)
                            .font(.title3.italic())
                            .foregroundStyle(.blue)
                    }
                    Text(")")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    Text("(\(player.name))")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text(engine.statusMessage)
                .font(.title2.bold())
        }
    }

    private func formatInfoBarDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        if mins > 0 {
            return String(format: "%d:%02d", mins, secs)
        }
        return "\(secs)s"
    }

    private var gameModeIcon: String {
        switch engine.gameMode {
        case .playerVsPlayer: return "person.2.fill"
        case .playerVsAI: return "person.and.background.dotted"
        case .aiVsAI: return "cpu"
        }
    }
}
