import SwiftUI

// MARK: - Content View

struct ContentView: View {
    @Bindable var engine: GameEngine
    @State private var showNewGameConfirmation = false
    @State private var showSetup = true
    @FocusState private var isGameFocused: Bool

    /// Background tint when viewing historical moves
    private var historyTint: Color {
        engine.isViewingHistory ? Color.orange.opacity(0.06) : Color.clear
    }

    var body: some View {
        gameView
            .frame(minWidth: 1400, minHeight: 700)
            .background(historyTint)
            .animation(.easeInOut(duration: 0.3), value: engine.isViewingHistory)
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
                    .frame(width: 400)
                    .fixedSize(horizontal: true, vertical: false)

                Divider()

                // Center: Game Info + Board + Move History
                VStack(spacing: 0) {
                    // Game info bar
                    gameInfoBar
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

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
                    .frame(width: 400)
                    .fixedSize(horizontal: true, vertical: false)
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
        .focusable()
        .focused($isGameFocused)
        .onAppear { isGameFocused = true }
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
                Text(engine.turnDisplayText)
                    .font(.title2.bold())
            }

            // Right-aligned: actions
            HStack {
                Spacer()

                Button("New Game") {
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

    // MARK: - Game Info Bar

    private var gameInfoBar: some View {
        HStack(spacing: 16) {
            // Game ID
            let gameIDStr = String(engine.currentGameID.uuidString.prefix(8))
            Text("Game \(gameIDStr)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            Divider().frame(height: 14)

            // Games between these players
            let history = engine.gameHistoryManager.previousResults(
                white: engine.whitePlayer.name,
                black: engine.blackPlayer.name
            )
            let totalBetween = history.whiteWins + history.blackWins + history.draws
            if totalBetween > 0 {
                Text("Prior: \(totalBetween) games (W:\(history.whiteWins) B:\(history.blackWins) D:\(history.draws))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider().frame(height: 14)
            }

            // Start time
            Text("Started \(engine.statistics.gameStartTime, style: .time)")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Elapsed time
            Text("Elapsed: \(engine.statistics.gameStartTime, style: .timer)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            // Session stats
            let totalGames = engine.gameHistoryManager.totalGamesPlayed + (engine.isGameActive ? 1 : 0)
            Text("Session: \(totalGames) games")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private var gameModeIcon: String {
        switch engine.gameMode {
        case .playerVsPlayer: return "person.2.fill"
        case .playerVsAI: return "person.and.background.dotted"
        case .aiVsAI: return "cpu"
        }
    }
}
