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
    @State private var whiteAllowResign: Bool = true
    @State private var blackAllowResign: Bool = true

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
                    humanPlayerID: $whiteHumanPlayerID,
                    allowResign: $whiteAllowResign
                )

                Divider()
                    .frame(height: 250)

                playerSetup(
                    title: "Black",
                    color: .black,
                    playerName: $blackPlayerName,
                    isAI: $blackIsAI,
                    aiSelection: $blackAISelection,
                    humanPlayerID: $blackHumanPlayerID,
                    allowResign: $blackAllowResign
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
        .onAppear {
            restoreLastSetup()
        }
    }

    // MARK: - Player Setup

    private func playerSetup(
        title: String,
        color: PieceColor,
        playerName: Binding<String>,
        isAI: Binding<Bool>,
        aiSelection: Binding<AISelection?>,
        humanPlayerID: Binding<UUID>,
        allowResign: Binding<Bool>
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
                Toggle("Allow resignation", isOn: allowResign)
                    .font(.caption)
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
        case .appleIntelligence(let configID):
            if let config = engine.appleIntelligenceConfigManager.config(byID: configID) {
                return config.name
            }
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
                        ForEach(engine.appleIntelligenceConfigManager.configs) { config in
                            Text(config.name).tag(AISelection.appleIntelligence(config.id) as AISelection?)
                        }
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

            // Inline Apple Intelligence config controls
            if let selectedAIConfig = selectedAppleIntelligenceConfig(for: selection.wrappedValue) {
                appleIntelligenceConfigControls(configID: selectedAIConfig.id)
            }

            if appleIntelligenceAvailable {
                HStack(spacing: 8) {
                    Button {
                        let newConfig = engine.appleIntelligenceConfigManager.addConfig(
                            name: "Apple Intelligence (\(engine.appleIntelligenceConfigManager.configs.count + 1))"
                        )
                        selection.wrappedValue = .appleIntelligence(newConfig.id)
                    } label: {
                        Label("New Config", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let selected = selectedAppleIntelligenceConfig(for: selection.wrappedValue),
                       engine.appleIntelligenceConfigManager.configs.count > 1 {
                        Button(role: .destructive) {
                            engine.appleIntelligenceConfigManager.deleteConfig(id: selected.id)
                            // Select the first remaining config
                            if let first = engine.appleIntelligenceConfigManager.configs.first {
                                selection.wrappedValue = .appleIntelligence(first.id)
                            } else {
                                selection.wrappedValue = nil
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            if configurations.isEmpty && !appleIntelligenceAvailable {
                Text("No AI configurations available.\nClick 'Configure AI Providers' to add providers.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Returns the Apple Intelligence config if the current selection is an Apple Intelligence config.
    private func selectedAppleIntelligenceConfig(for selection: AISelection?) -> AppleIntelligenceConfig? {
        guard case .appleIntelligence(let configID) = selection else { return nil }
        return engine.appleIntelligenceConfigManager.config(byID: configID)
    }

    /// Inline controls for editing an Apple Intelligence configuration.
    private func appleIntelligenceConfigControls(configID: UUID) -> some View {
        let manager = engine.appleIntelligenceConfigManager

        // Bind directly to the manager's config
        let nameBinding = Binding<String>(
            get: { manager.config(byID: configID)?.name ?? "" },
            set: { newValue in
                guard var config = manager.config(byID: configID) else { return }
                config.name = newValue
                manager.updateConfig(config)
            }
        )

        let samplingModeTag = Binding<Int>(
            get: {
                guard let config = manager.config(byID: configID) else { return 0 }
                switch config.samplingMode {
                case .greedy: return 0
                case .randomMass: return 1
                case .randomTopN: return 2
                }
            },
            set: { newTag in
                guard var config = manager.config(byID: configID) else { return }
                switch newTag {
                case 0: config.samplingMode = .greedy
                case 1: config.samplingMode = .randomMass(0.9)
                case 2: config.samplingMode = .randomTopN(40)
                default: break
                }
                manager.updateConfig(config)
            }
        )

        let temperatureEnabled = Binding<Bool>(
            get: { manager.config(byID: configID)?.temperature != nil },
            set: { enabled in
                guard var config = manager.config(byID: configID) else { return }
                config.temperature = enabled ? 1.0 : nil
                manager.updateConfig(config)
            }
        )

        let temperature = Binding<Double>(
            get: { manager.config(byID: configID)?.temperature ?? 1.0 },
            set: { newValue in
                guard var config = manager.config(byID: configID) else { return }
                config.temperature = newValue
                manager.updateConfig(config)
            }
        )

        let maxTokensEnabled = Binding<Bool>(
            get: { manager.config(byID: configID)?.maximumResponseTokens != nil },
            set: { enabled in
                guard var config = manager.config(byID: configID) else { return }
                config.maximumResponseTokens = enabled ? 4096 : nil
                manager.updateConfig(config)
            }
        )

        let maxTokens = Binding<Double>(
            get: { Double(manager.config(byID: configID)?.maximumResponseTokens ?? 4096) },
            set: { newValue in
                guard var config = manager.config(byID: configID) else { return }
                config.maximumResponseTokens = Int(newValue)
                manager.updateConfig(config)
            }
        )

        let probabilityMass = Binding<Double>(
            get: {
                guard let config = manager.config(byID: configID),
                      case .randomMass(let mass) = config.samplingMode else { return 0.9 }
                return mass
            },
            set: { newValue in
                guard var config = manager.config(byID: configID) else { return }
                config.samplingMode = .randomMass(newValue)
                manager.updateConfig(config)
            }
        )

        let topN = Binding<Double>(
            get: {
                guard let config = manager.config(byID: configID),
                      case .randomTopN(let n) = config.samplingMode else { return 40 }
                return Double(n)
            },
            set: { newValue in
                guard var config = manager.config(byID: configID) else { return }
                config.samplingMode = .randomTopN(Int(newValue))
                manager.updateConfig(config)
            }
        )

        return VStack(alignment: .leading, spacing: 6) {
            Divider()

            // Config name
            HStack {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                TextField("Config Name", text: nameBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            // Sampling mode
            HStack {
                Text("Sampling")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                Picker("Sampling", selection: samplingModeTag) {
                    Text("Greedy").tag(0)
                    Text("Random (probability)").tag(1)
                    Text("Random (top-N)").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Probability mass slider (only for randomMass mode)
            if case .randomMass = manager.config(byID: configID)?.samplingMode ?? .greedy {
                HStack {
                    Text("Mass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    Slider(value: probabilityMass, in: 0.01...1.0, step: 0.01)
                    Text(String(format: "%.2f", probabilityMass.wrappedValue))
                        .font(.caption.monospacedDigit())
                        .frame(width: 35, alignment: .trailing)
                }
            }

            // Top-N stepper (only for randomTopN mode)
            if case .randomTopN = manager.config(byID: configID)?.samplingMode ?? .greedy {
                HStack {
                    Text("Top-N")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    Slider(value: topN, in: 1...200, step: 1)
                    Text("\(Int(topN.wrappedValue))")
                        .font(.caption.monospacedDigit())
                        .frame(width: 35, alignment: .trailing)
                }
            }

            // Temperature
            HStack {
                Text("Temp")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                Toggle("", isOn: temperatureEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                if temperatureEnabled.wrappedValue {
                    Slider(value: temperature, in: 0.0...2.0, step: 0.05)
                    Text(String(format: "%.2f", temperature.wrappedValue))
                        .font(.caption.monospacedDigit())
                        .frame(width: 35, alignment: .trailing)
                } else {
                    Text("System default")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Max response tokens
            HStack {
                Text("Tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
                Toggle("", isOn: maxTokensEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                if maxTokensEnabled.wrappedValue {
                    Slider(value: maxTokens, in: 256...16384, step: 256)
                    Text("\(Int(maxTokens.wrappedValue))")
                        .font(.caption.monospacedDigit())
                        .frame(width: 50, alignment: .trailing)
                } else {
                    Text("System default")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
        }
        .padding(.top, 4)
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
            humanPlayerID: whiteHumanPlayerID,
            allowResign: whiteAllowResign
        )

        // Build black player config
        let blackConfig = buildPlayerConfig(
            name: blackPlayerName,
            isAI: blackIsAI,
            aiSelection: blackAISelection,
            color: .black,
            humanPlayerID: blackHumanPlayerID,
            allowResign: blackAllowResign
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

        saveLastSetup()
        engine.startNewGame()
        dismiss()
    }

    private func buildPlayerConfig(name: String, isAI: Bool, aiSelection: AISelection?, color: PieceColor, humanPlayerID: UUID?, allowResign: Bool = true) -> PlayerConfig {
        var config = PlayerConfig(name: name, isAI: isAI, color: color, humanPlayerID: isAI ? nil : humanPlayerID, allowResign: allowResign)
        if isAI, let selection = aiSelection {
            switch selection {
            case .appleIntelligence(let configID):
                config.useAppleIntelligence = true
                config.appleIntelligenceConfigID = configID
            case .llmConfig(let configID):
                config.aiConfigurationID = configID
            }
        }
        return config
    }

    // MARK: - Last Player Setup Persistence

    /// Saved state for one side of the board.
    private struct SavedSideSetup: Codable {
        let isAI: Bool
        let playerName: String
        let humanPlayerID: String
        let isAppleIntelligence: Bool
        let aiConfigID: String?
        let appleIntelligenceConfigID: String?
        var allowResign: Bool?  // Optional for backward compatibility with saved data

        init(isAI: Bool, playerName: String, humanPlayerID: String,
             isAppleIntelligence: Bool, aiConfigID: String?,
             appleIntelligenceConfigID: String? = nil, allowResign: Bool? = nil) {
            self.isAI = isAI
            self.playerName = playerName
            self.humanPlayerID = humanPlayerID
            self.isAppleIntelligence = isAppleIntelligence
            self.aiConfigID = aiConfigID
            self.appleIntelligenceConfigID = appleIntelligenceConfigID
            self.allowResign = allowResign
        }
    }

    private static let lastWhiteKey = "lastSetup.white"
    private static let lastBlackKey = "lastSetup.black"

    private func saveLastSetup() {
        let whiteSide = SavedSideSetup(
            isAI: whiteIsAI,
            playerName: whitePlayerName,
            humanPlayerID: whiteHumanPlayerID.uuidString,
            isAppleIntelligence: whiteAISelection.isAppleIntelligence,
            aiConfigID: whiteAISelection.llmConfigID?.uuidString,
            appleIntelligenceConfigID: whiteAISelection.appleIntelligenceConfigID?.uuidString,
            allowResign: whiteAllowResign
        )
        let blackSide = SavedSideSetup(
            isAI: blackIsAI,
            playerName: blackPlayerName,
            humanPlayerID: blackHumanPlayerID.uuidString,
            isAppleIntelligence: blackAISelection.isAppleIntelligence,
            aiConfigID: blackAISelection.llmConfigID?.uuidString,
            appleIntelligenceConfigID: blackAISelection.appleIntelligenceConfigID?.uuidString,
            allowResign: blackAllowResign
        )

        do {
            let encoder = JSONEncoder()
            let whiteData = try encoder.encode(whiteSide)
            let blackData = try encoder.encode(blackSide)
            UserDefaults.standard.set(whiteData, forKey: Self.lastWhiteKey)
            UserDefaults.standard.set(blackData, forKey: Self.lastBlackKey)
        } catch {
            print("[GameSetupView] Failed to save last setup: \(error)")
        }
    }

    private func restoreLastSetup() {
        let decoder = JSONDecoder()

        if let whiteData = UserDefaults.standard.data(forKey: Self.lastWhiteKey) {
            do {
                let saved = try decoder.decode(SavedSideSetup.self, from: whiteData)
                applySavedSetup(saved, isAI: &whiteIsAI, playerName: &whitePlayerName,
                                humanPlayerID: &whiteHumanPlayerID, aiSelection: &whiteAISelection,
                                allowResign: &whiteAllowResign)
            } catch {
                print("[GameSetupView] Failed to decode white setup: \(error)")
            }
        }

        if let blackData = UserDefaults.standard.data(forKey: Self.lastBlackKey) {
            do {
                let saved = try decoder.decode(SavedSideSetup.self, from: blackData)
                applySavedSetup(saved, isAI: &blackIsAI, playerName: &blackPlayerName,
                                humanPlayerID: &blackHumanPlayerID, aiSelection: &blackAISelection,
                                allowResign: &blackAllowResign)
            } catch {
                print("[GameSetupView] Failed to decode black setup: \(error)")
            }
        }
    }

    private func applySavedSetup(
        _ saved: SavedSideSetup,
        isAI: inout Bool,
        playerName: inout String,
        humanPlayerID: inout UUID,
        aiSelection: inout AISelection?,
        allowResign: inout Bool
    ) {
        allowResign = saved.allowResign ?? true
        isAI = saved.isAI

        if saved.isAI {
            // Restore AI selection, validating that the config still exists
            if saved.isAppleIntelligence && appleIntelligenceAvailable {
                // Restore the specific Apple Intelligence config, or fall back to first available
                if let idStr = saved.appleIntelligenceConfigID,
                   let configID = UUID(uuidString: idStr),
                   let config = engine.appleIntelligenceConfigManager.config(byID: configID) {
                    aiSelection = .appleIntelligence(configID)
                    playerName = config.name
                } else if let first = engine.appleIntelligenceConfigManager.configs.first {
                    aiSelection = .appleIntelligence(first.id)
                    playerName = first.name
                } else {
                    aiSelection = nil
                    playerName = "Apple Intelligence"
                }
            } else if let idStr = saved.aiConfigID,
                      let configID = UUID(uuidString: idStr),
                      configurations.contains(where: { $0.id == configID }) {
                aiSelection = .llmConfig(configID)
                playerName = aiDisplayName(for: .llmConfig(configID))
            } else {
                // Saved config no longer exists — clear selection
                aiSelection = nil
                playerName = saved.playerName
            }
        } else {
            // Restore human player, validating they still exist
            if let id = UUID(uuidString: saved.humanPlayerID),
               let player = engine.humanPlayerManager.player(byID: id) {
                humanPlayerID = id
                playerName = player.name
            } else {
                humanPlayerID = HumanPlayer.guestID
                playerName = engine.humanPlayerManager.player(byID: HumanPlayer.guestID)?.name ?? "Guest"
            }
        }
    }
}
