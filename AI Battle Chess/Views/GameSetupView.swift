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
    @State private var showGuestNamePrompt: Bool = false
    @State private var guestPromptWhitePickedID: UUID? = nil
    @State private var guestPromptWhiteNewName: String = ""
    @State private var guestPromptBlackPickedID: UUID? = nil
    @State private var guestPromptBlackNewName: String = ""
    @State private var addPlayerDuplicate: HumanPlayer? = nil
    @State private var guestPromptDuplicate: GuestDuplicateConflict? = nil

    private struct GuestDuplicateConflict {
        let whiteExisting: HumanPlayer?
        let blackExisting: HumanPlayer?
    }

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
        .onAppear {
            restoreLastSetup()
        }
        .sheet(isPresented: $showLoadPGN) {
            loadPGNSheet
        }
        .sheet(isPresented: $showProviderSettings) {
            ProviderSettingsView(llmKit: engine.llmKit,
                                appleIntelligenceConfigManager: engine.appleIntelligenceConfigManager)
        }
        .sheet(isPresented: $showGuestNamePrompt) {
            guestNamePromptSheet
        }
        .alert("New Player", isPresented: $showAddPlayer) {
            TextField("Name", text: $newPlayerName)
            Button("Add") {
                let trimmed = newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if let existing = engine.humanPlayerManager.player(byName: trimmed) {
                    addPlayerDuplicate = existing
                } else {
                    let newPlayer = engine.humanPlayerManager.addPlayer(name: trimmed)
                    applyAddedPlayer(newPlayer)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new player.")
        }
        .alert(
            "Player Already Exists",
            isPresented: Binding(
                get: { addPlayerDuplicate != nil },
                set: { if !$0 { addPlayerDuplicate = nil } }
            )
        ) {
            Button("Use Existing") {
                if let player = addPlayerDuplicate {
                    applyAddedPlayer(player)
                }
                addPlayerDuplicate = nil
            }
            Button("Choose Different Name", role: .cancel) {
                addPlayerDuplicate = nil
                showAddPlayer = true
            }
        } message: {
            Text("A player named \"\(addPlayerDuplicate?.name ?? "")\" already exists. Use the existing player or choose a different name.")
        }
    }

    /// Sets the side currently being added on the main screen to the given player.
    private func applyAddedPlayer(_ player: HumanPlayer) {
        if addingPlayerForColor == .white {
            whiteHumanPlayerID = player.id
            whitePlayerName = player.name
        } else {
            blackHumanPlayerID = player.id
            blackPlayerName = player.name
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
                    let aiConfigs = engine.appleIntelligenceConfigManager.configs
                    if aiConfigs.count > 1 {
                        Section("Apple Intelligence") {
                            ForEach(aiConfigs) { config in
                                Text(config.name).tag(AISelection.appleIntelligence(config.id) as AISelection?)
                            }
                        }
                    } else {
                        ForEach(aiConfigs) { config in
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
                    engine.importPGN(pgnText)
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
        let whiteIsGuestHuman = !whiteIsAI && whiteHumanPlayerID == HumanPlayer.guestID
        let blackIsGuestHuman = !blackIsAI && blackHumanPlayerID == HumanPlayer.guestID

        if whiteIsGuestHuman || blackIsGuestHuman {
            guestPromptWhitePickedID = nil
            guestPromptWhiteNewName = ""
            guestPromptBlackPickedID = nil
            guestPromptBlackNewName = ""
            showGuestNamePrompt = true
            return
        }

        commitStartGame()
    }

    private func commitStartGame() {
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

    // MARK: - Guest Name Prompt

    private var guestNamePromptSheet: some View {
        let needWhite = !whiteIsAI && whiteHumanPlayerID == HumanPlayer.guestID
        let needBlack = !blackIsAI && blackHumanPlayerID == HumanPlayer.guestID

        return VStack(spacing: 20) {
            Text("Who's playing?")
                .font(.headline)

            Text("Pick an existing player or enter a new name.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 24) {
                if needWhite {
                    guestPromptColumn(
                        title: "White",
                        color: .white,
                        pickedID: $guestPromptWhitePickedID,
                        newName: $guestPromptWhiteNewName
                    )
                }
                if needWhite && needBlack {
                    Divider().frame(height: 200)
                }
                if needBlack {
                    guestPromptColumn(
                        title: "Black",
                        color: .black,
                        pickedID: $guestPromptBlackPickedID,
                        newName: $guestPromptBlackNewName
                    )
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    showGuestNamePrompt = false
                }

                Spacer()

                Button("Start Game") {
                    applyGuestPromptThenStart(needWhite: needWhite, needBlack: needBlack)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!guestPromptIsValid(needWhite: needWhite, needBlack: needBlack))
            }
        }
        .padding(24)
        .frame(minWidth: needWhite && needBlack ? 460 : 280)
        .alert(
            "Player Already Exists",
            isPresented: Binding(
                get: { guestPromptDuplicate != nil },
                set: { if !$0 { guestPromptDuplicate = nil } }
            )
        ) {
            Button("Use Existing") {
                if let conflict = guestPromptDuplicate {
                    if let p = conflict.whiteExisting {
                        guestPromptWhitePickedID = p.id
                        guestPromptWhiteNewName = ""
                    }
                    if let p = conflict.blackExisting {
                        guestPromptBlackPickedID = p.id
                        guestPromptBlackNewName = ""
                    }
                }
                guestPromptDuplicate = nil
                performGuestPromptApply(needWhite: needWhite, needBlack: needBlack)
            }
            Button("Choose Different Name", role: .cancel) {
                guestPromptDuplicate = nil
            }
        } message: {
            Text(guestDuplicateMessage)
        }
    }

    private var guestDuplicateMessage: String {
        guard let conflict = guestPromptDuplicate else { return "" }
        var lines: [String] = []
        if let white = conflict.whiteExisting {
            lines.append("White: \"\(white.name)\" already exists.")
        }
        if let black = conflict.blackExisting {
            lines.append("Black: \"\(black.name)\" already exists.")
        }
        let prefix = lines.joined(separator: "\n")
        return prefix + "\n\nUse the existing player(s) or choose different name(s)."
    }

    private func guestPromptColumn(
        title: String,
        color: PieceColor,
        pickedID: Binding<UUID?>,
        newName: Binding<String>
    ) -> some View {
        let nonGuestPlayers = engine.humanPlayerManager.players.filter { !$0.isGuest }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color == .white ? Color.white : Color.black)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.gray, lineWidth: 1))
                Text(title).font(.headline)
            }

            if !nonGuestPlayers.isEmpty {
                Picker("Existing player", selection: pickedID) {
                    Text("—").tag(nil as UUID?)
                    ForEach(nonGuestPlayers) { player in
                        Text(player.name).tag(Optional(player.id))
                    }
                }
                .labelsHidden()
                .onChange(of: pickedID.wrappedValue) { _, newValue in
                    if newValue != nil {
                        newName.wrappedValue = ""
                    }
                }
            }

            TextField("Or enter a new name", text: newName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: newName.wrappedValue) { _, newValue in
                    if !newValue.isEmpty {
                        pickedID.wrappedValue = nil
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func guestPromptIsValid(needWhite: Bool, needBlack: Bool) -> Bool {
        func sideValid(picked: UUID?, name: String) -> Bool {
            if picked != nil { return true }
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if needWhite && !sideValid(picked: guestPromptWhitePickedID, name: guestPromptWhiteNewName) {
            return false
        }
        if needBlack && !sideValid(picked: guestPromptBlackPickedID, name: guestPromptBlackNewName) {
            return false
        }
        return true
    }

    private func applyGuestPromptThenStart(needWhite: Bool, needBlack: Bool) {
        var whiteDuplicate: HumanPlayer? = nil
        var blackDuplicate: HumanPlayer? = nil

        if needWhite, guestPromptWhitePickedID == nil {
            let trimmed = guestPromptWhiteNewName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                whiteDuplicate = engine.humanPlayerManager.player(byName: trimmed)
            }
        }
        if needBlack, guestPromptBlackPickedID == nil {
            let trimmed = guestPromptBlackNewName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blackDuplicate = engine.humanPlayerManager.player(byName: trimmed)
            }
        }

        if whiteDuplicate != nil || blackDuplicate != nil {
            guestPromptDuplicate = GuestDuplicateConflict(
                whiteExisting: whiteDuplicate,
                blackExisting: blackDuplicate
            )
            return
        }

        performGuestPromptApply(needWhite: needWhite, needBlack: needBlack)
    }

    private func performGuestPromptApply(needWhite: Bool, needBlack: Bool) {
        if needWhite {
            if let pickedID = guestPromptWhitePickedID,
               let player = engine.humanPlayerManager.player(byID: pickedID) {
                whiteHumanPlayerID = player.id
                whitePlayerName = player.name
            } else {
                let trimmed = guestPromptWhiteNewName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let newPlayer = engine.humanPlayerManager.addPlayer(name: trimmed)
                    whiteHumanPlayerID = newPlayer.id
                    whitePlayerName = newPlayer.name
                }
            }
        }
        if needBlack {
            if let pickedID = guestPromptBlackPickedID,
               let player = engine.humanPlayerManager.player(byID: pickedID) {
                blackHumanPlayerID = player.id
                blackPlayerName = player.name
            } else {
                let trimmed = guestPromptBlackNewName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let newPlayer = engine.humanPlayerManager.addPlayer(name: trimmed)
                    blackHumanPlayerID = newPlayer.id
                    blackPlayerName = newPlayer.name
                }
            }
        }

        showGuestNamePrompt = false
        commitStartGame()
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
