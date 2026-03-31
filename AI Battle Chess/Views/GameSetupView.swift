import SwiftUI
import SwiftLLMKit

// MARK: - Game Setup View

struct GameSetupView: View {
    @Bindable var engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    @State private var whitePlayerName: String = "Guest"
    @State private var blackPlayerName: String = "AI Opponent"
    @State private var whiteIsAI: Bool = false
    @State private var blackIsAI: Bool = true
    @State private var whiteAISelection: AISelection? = nil
    @State private var blackAISelection: AISelection? = nil
    @State private var whiteHumanPlayerID: UUID = HumanPlayer.guestID
    @State private var blackHumanPlayerID: UUID = HumanPlayer.guestID
    @State private var showLoadPGN: Bool = false
    @State private var showProviderSettings: Bool = false
    @State private var showAddPlayer: Bool = false
    @State private var newPlayerName: String = ""
    @State private var addingPlayerForColor: PieceColor? = nil
    @State private var pgnText: String = ""

    private var configurations: [ModelConfiguration] {
        engine.llmKit.configurations.filter(\.isValid)
    }

    private var appleIntelligenceAvailable: Bool {
        if #available(macOS 26.0, *) {
            return AppleIntelligenceService.isAvailable
        }
        return false
    }

    /// Configurations grouped by provider, then by model.
    private var groupedConfigurations: [(providerName: String, configs: [ModelConfiguration])] {
        let grouped = Dictionary(grouping: configurations, by: { $0.providerID })
        return grouped.map { providerID, configs in
            let providerName = engine.llmKit.providers.first(where: { $0.id == providerID })?.name ?? providerID
            return (providerName, configs.sorted(by: { $0.name < $1.name }))
        }
        .sorted(by: { $0.providerName < $1.providerName })
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("AI Battle Chess")
                .font(.largeTitle.bold())

            Text("Configure your game")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Player setup
            HStack(alignment: .top, spacing: 24) {
                playerSetup(
                    title: "White",
                    color: .white,
                    playerName: $whitePlayerName,
                    isAI: $whiteIsAI,
                    aiSelection: $whiteAISelection,
                    humanPlayerID: $whiteHumanPlayerID
                )

                Divider()
                    .frame(height: 250)

                playerSetup(
                    title: "Black",
                    color: .black,
                    playerName: $blackPlayerName,
                    isAI: $blackIsAI,
                    aiSelection: $blackAISelection,
                    humanPlayerID: $blackHumanPlayerID
                )
            }

            Divider()

            HStack(spacing: 16) {
                Button("Load PGN") {
                    showLoadPGN = true
                }
                .buttonStyle(.bordered)

                Button {
                    showProviderSettings = true
                } label: {
                    Label("Configure AI Providers", systemImage: "gear")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Start Game") {
                    startGame()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canStart)
            }
        }
        .padding(32)
        .frame(maxWidth: 800)
        .sheet(isPresented: $showLoadPGN) {
            loadPGNSheet
        }
        .sheet(isPresented: $showProviderSettings) {
            ProviderSettingsView(llmKit: engine.llmKit)
        }
        .alert("New Player", isPresented: $showAddPlayer) {
            TextField("Name", text: $newPlayerName)
            Button("Add") {
                let trimmed = newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let newPlayer = engine.humanPlayerManager.addPlayer(name: trimmed)
                if addingPlayerForColor == .white {
                    whiteHumanPlayerID = newPlayer.id
                    whitePlayerName = newPlayer.name
                } else {
                    blackHumanPlayerID = newPlayer.id
                    blackPlayerName = newPlayer.name
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new player.")
        }
    }

    // MARK: - Player Setup

    private func playerSetup(
        title: String,
        color: PieceColor,
        playerName: Binding<String>,
        isAI: Binding<Bool>,
        aiSelection: Binding<AISelection?>,
        humanPlayerID: Binding<UUID>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color == .white ? Color.white : Color.black)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Color.gray, lineWidth: 1))
                Text(title)
                    .font(.headline)
            }

            // Human / AI picker
            Picker("Player Type", selection: isAI) {
                Text("Human Player").tag(false)
                Text("AI Opponent").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if isAI.wrappedValue {
                TextField("Player Name", text: playerName)
                    .textFieldStyle(.roundedBorder)
                aiModelPicker(selection: aiSelection)
            } else {
                humanPlayerPicker(
                    selectedPlayerID: humanPlayerID,
                    playerName: playerName,
                    color: color
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: aiSelection.wrappedValue) { _, newSelection in
            if let selection = newSelection {
                playerName.wrappedValue = aiDisplayName(for: selection)
            }
        }
        .onChange(of: isAI.wrappedValue) { _, nowAI in
            if !nowAI {
                // Switching to human — set name from selected human player
                let selectedID = humanPlayerID.wrappedValue
                if let player = engine.humanPlayerManager.player(byID: selectedID) {
                    playerName.wrappedValue = player.name
                } else {
                    playerName.wrappedValue = "Guest"
                }
            } else if let selection = aiSelection.wrappedValue {
                playerName.wrappedValue = aiDisplayName(for: selection)
            } else {
                playerName.wrappedValue = "AI Opponent"
            }
        }
    }

    // MARK: - Human Player Picker

    private func humanPlayerPicker(
        selectedPlayerID: Binding<UUID>,
        playerName: Binding<String>,
        color: PieceColor
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Player")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Picker("Player", selection: selectedPlayerID) {
                    ForEach(engine.humanPlayerManager.players) { player in
                        Text(player.name).tag(player.id)
                    }
                }
                .labelsHidden()
                .onChange(of: selectedPlayerID.wrappedValue) { _, newID in
                    if let player = engine.humanPlayerManager.player(byID: newID) {
                        playerName.wrappedValue = player.name
                    }
                }

                Button {
                    addingPlayerForColor = color
                    newPlayerName = ""
                    showAddPlayer = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func aiDisplayName(for selection: AISelection) -> String {
        switch selection {
        case .appleIntelligence:
            return "Apple Intelligence"
        case .llmConfig(let configID):
            if let config = engine.llmKit.configurations.first(where: { $0.id == configID }) {
                return config.name
            }
            return "AI Opponent"
        }
    }

    // MARK: - Hierarchical AI Model Picker

    private func aiModelPicker(selection: Binding<AISelection?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI Model")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("AI Model", selection: selection) {
                Text("Select...").tag(nil as AISelection?)

                if appleIntelligenceAvailable {
                    Section("Apple Intelligence") {
                        Text("Apple Intelligence").tag(AISelection.appleIntelligence as AISelection?)
                    }
                }

                ForEach(groupedConfigurations, id: \.providerName) { group in
                    Section(group.providerName) {
                        ForEach(group.configs) { config in
                            Text(config.name).tag(AISelection.llmConfig(config.id) as AISelection?)
                        }
                    }
                }
            }
            .labelsHidden()

            if configurations.isEmpty && !appleIntelligenceAvailable {
                Text("No AI configurations available.\nClick 'Configure AI Providers' to add providers.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Load PGN

    private var loadPGNSheet: some View {
        VStack(spacing: 16) {
            Text("Load Game from PGN")
                .font(.headline)

            TextEditor(text: $pgnText)
                .font(.body.monospaced())
                .frame(minHeight: 200)
                .border(Color.secondary.opacity(0.3))

            HStack {
                Button("Cancel") {
                    showLoadPGN = false
                }

                Spacer()

                Button("Load") {
                    engine.loadGame(pgn: pgnText)
                    if engine.errorMessage != nil {
                        // Leave the PGN sheet open so the user sees the error
                    } else {
                        showLoadPGN = false
                        dismiss() // Also dismiss the setup sheet
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(pgnText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let error = engine.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(24)
        .frame(width: 500, height: 350)
    }

    // MARK: - Validation

    private var canStart: Bool {
        if whiteIsAI && whiteAISelection == nil { return false }
        if blackIsAI && blackAISelection == nil { return false }
        return true
    }

    // MARK: - Actions

    private func startGame() {
        // Build white player config
        let whiteConfig = buildPlayerConfig(
            name: whitePlayerName,
            isAI: whiteIsAI,
            aiSelection: whiteAISelection,
            color: .white,
            humanPlayerID: whiteHumanPlayerID
        )

        // Build black player config
        let blackConfig = buildPlayerConfig(
            name: blackPlayerName,
            isAI: blackIsAI,
            aiSelection: blackAISelection,
            color: .black,
            humanPlayerID: blackHumanPlayerID
        )

        engine.whitePlayer = whiteConfig
        engine.blackPlayer = blackConfig

        // Infer game mode
        if whiteIsAI && blackIsAI {
            engine.gameMode = .aiVsAI
        } else if whiteIsAI || blackIsAI {
            engine.gameMode = .playerVsAI
        } else {
            engine.gameMode = .playerVsPlayer
        }

        engine.startNewGame()
        dismiss()
    }

    private func buildPlayerConfig(name: String, isAI: Bool, aiSelection: AISelection?, color: PieceColor, humanPlayerID: UUID?) -> PlayerConfig {
        var config = PlayerConfig(name: name, isAI: isAI, color: color, humanPlayerID: isAI ? nil : humanPlayerID)
        if isAI, let selection = aiSelection {
            switch selection {
            case .appleIntelligence:
                config.useAppleIntelligence = true
            case .llmConfig(let configID):
                config.aiConfigurationID = configID
            }
        }
        return config
    }
}
