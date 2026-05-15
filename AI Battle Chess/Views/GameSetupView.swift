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
    @State private var whiteTemperatureOverride: Double? = nil
    @State private var blackTemperatureOverride: Double? = nil
    @State private var whiteMaxOutputTokensOverride: Int? = nil
    @State private var blackMaxOutputTokensOverride: Int? = nil
    @State private var whiteThinkingBudgetOverride: Int? = nil
    @State private var blackThinkingBudgetOverride: Int? = nil
    @State private var whiteSamplingModeOverride: AISamplingMode? = nil
    @State private var blackSamplingModeOverride: AISamplingMode? = nil
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

    /// A wrapping binding for the white AI selection that clears per-game parameter
    /// overrides when the user picks a different model. Restoration code writes
    /// directly to `whiteAISelection` and bypasses this clear, preserving saved overrides.
    private var whiteAISelectionBinding: Binding<AISelection?> {
        Binding(
            get: { whiteAISelection },
            set: { newValue in
                if newValue != whiteAISelection {
                    whiteTemperatureOverride = nil
                    whiteMaxOutputTokensOverride = nil
                    whiteThinkingBudgetOverride = nil
                    whiteSamplingModeOverride = nil
                }
                whiteAISelection = newValue
            }
        )
    }

    private var blackAISelectionBinding: Binding<AISelection?> {
        Binding(
            get: { blackAISelection },
            set: { newValue in
                if newValue != blackAISelection {
                    blackTemperatureOverride = nil
                    blackMaxOutputTokensOverride = nil
                    blackThinkingBudgetOverride = nil
                    blackSamplingModeOverride = nil
                }
                blackAISelection = newValue
            }
        )
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
                    aiSelection: whiteAISelectionBinding,
                    humanPlayerID: $whiteHumanPlayerID,
                    allowResign: $whiteAllowResign,
                    temperatureOverride: $whiteTemperatureOverride,
                    maxOutputTokensOverride: $whiteMaxOutputTokensOverride,
                    thinkingBudgetOverride: $whiteThinkingBudgetOverride,
                    samplingModeOverride: $whiteSamplingModeOverride
                )

                Divider()
                    .frame(height: 320)

                playerSetup(
                    title: "Black",
                    color: .black,
                    playerName: $blackPlayerName,
                    isAI: $blackIsAI,
                    aiSelection: blackAISelectionBinding,
                    humanPlayerID: $blackHumanPlayerID,
                    allowResign: $blackAllowResign,
                    temperatureOverride: $blackTemperatureOverride,
                    maxOutputTokensOverride: $blackMaxOutputTokensOverride,
                    thinkingBudgetOverride: $blackThinkingBudgetOverride,
                    samplingModeOverride: $blackSamplingModeOverride
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
        allowResign: Binding<Bool>,
        temperatureOverride: Binding<Double?>,
        maxOutputTokensOverride: Binding<Int?>,
        thinkingBudgetOverride: Binding<Int?>,
        samplingModeOverride: Binding<AISamplingMode?>
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
                modelParameterControls(
                    aiSelection: aiSelection.wrappedValue,
                    temperatureOverride: temperatureOverride,
                    maxOutputTokensOverride: maxOutputTokensOverride,
                    thinkingBudgetOverride: thinkingBudgetOverride,
                    samplingModeOverride: samplingModeOverride
                )
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

    // MARK: - Model Parameter Controls

    /// Per-game overrides for the selected AI's temperature, max output tokens,
    /// thinking budget (LLM providers), and sampling mode (Apple Intelligence).
    /// Each TextField shows the currently-selected config's default as its placeholder;
    /// a non-nil binding value is written into the resulting `PlayerConfig` as an override.
    @ViewBuilder
    private func modelParameterControls(
        aiSelection: AISelection?,
        temperatureOverride: Binding<Double?>,
        maxOutputTokensOverride: Binding<Int?>,
        thinkingBudgetOverride: Binding<Int?>,
        samplingModeOverride: Binding<AISamplingMode?>
    ) -> some View {
        switch aiSelection {
        case .llmConfig(let configID):
            let config = engine.llmKit.configurations.first(where: { $0.id == configID })
            let provider = config.flatMap { c in
                engine.llmKit.providers.first(where: { $0.id == c.providerID })
            }
            let isAnthropic = provider?.apiType == .anthropic
            VStack(alignment: .leading, spacing: 4) {
                Text("Model Parameters")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Text("Temp")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField(
                        config.map { String(format: "%.2f", $0.temperature) } ?? "—",
                        value: temperatureOverride,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                }

                HStack(spacing: 6) {
                    Text("Max Tokens")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField(
                        config.map { "\($0.maxOutputTokens)" } ?? "—",
                        value: maxOutputTokensOverride,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                }

                if isAnthropic {
                    HStack(spacing: 6) {
                        Text("Thinking")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField(
                            config.flatMap(\.thinkingBudget).map(String.init) ?? "off",
                            value: thinkingBudgetOverride,
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    }
                }
            }
        case .appleIntelligence(let configID):
            let config = engine.appleIntelligenceConfigManager.config(byID: configID)
            let effectiveSampling = samplingModeOverride.wrappedValue ?? config?.samplingMode ?? .greedy
            let samplingIsGreedy: Bool = {
                if case .greedy = effectiveSampling { return true }
                return false
            }()
            VStack(alignment: .leading, spacing: 4) {
                Text("Model Parameters")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                appleSamplingPicker(
                    configDefault: config?.samplingMode ?? .greedy,
                    samplingModeOverride: samplingModeOverride
                )

                HStack(spacing: 6) {
                    Text("Temp")
                        .font(.caption2)
                        .foregroundStyle(samplingIsGreedy ? .tertiary : .secondary)
                    TextField(
                        config?.temperature.map { String(format: "%.2f", $0) } ?? "default",
                        value: temperatureOverride,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .disabled(samplingIsGreedy)
                }
                if samplingIsGreedy {
                    Text("Greedy sampling ignores temperature.\nPick Random p or Random top-N to set it.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 6) {
                    Text("Max Tokens")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField(
                        config?.maximumResponseTokens.map(String.init) ?? "default",
                        value: maxOutputTokensOverride,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                }
            }
        case .none:
            EmptyView()
        }
    }

    /// Picks an Apple Intelligence sampling mode: greedy, random top-p (mass), or random top-k.
    /// Picking greedy writes nil (use config default) when the config's own mode is greedy —
    /// this keeps the override meaningful only when it differs from the stored config.
    private func appleSamplingPicker(
        configDefault: AISamplingMode,
        samplingModeOverride: Binding<AISamplingMode?>
    ) -> some View {
        let effective = samplingModeOverride.wrappedValue ?? configDefault

        let kindBinding = Binding<Int>(
            get: {
                switch effective {
                case .greedy: return 0
                case .randomMass: return 1
                case .randomTopN: return 2
                }
            },
            set: { newValue in
                switch newValue {
                case 1:
                    samplingModeOverride.wrappedValue = .randomMass(0.9)
                case 2:
                    samplingModeOverride.wrappedValue = .randomTopN(40)
                default:
                    samplingModeOverride.wrappedValue = .greedy
                }
            }
        )

        return VStack(alignment: .leading, spacing: 4) {
            Picker("Sampling", selection: kindBinding) {
                Text("Greedy").tag(0)
                Text("Random p").tag(1)
                Text("Random top-N").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch effective {
            case .greedy:
                EmptyView()
            case .randomMass(let mass):
                HStack(spacing: 6) {
                    Text("p")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { mass },
                            set: { samplingModeOverride.wrappedValue = .randomMass($0) }
                        ),
                        in: 0.05...1.0
                    )
                    Text(String(format: "%.2f", mass))
                        .font(.caption2.monospacedDigit())
                        .frame(width: 34, alignment: .trailing)
                }
            case .randomTopN(let n):
                HStack(spacing: 6) {
                    Text("N")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Stepper(
                        value: Binding(
                            get: { n },
                            set: { samplingModeOverride.wrappedValue = .randomTopN($0) }
                        ),
                        in: 1...200
                    ) {
                        Text("\(n)").font(.caption2.monospacedDigit())
                    }
                }
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
        // Resolve any per-game parameter tweaks into a concrete configuration ID,
        // finding or creating a configuration that matches the effective params.
        let resolvedWhiteSelection = resolveSelection(
            base: whiteAISelection,
            temperatureOverride: whiteTemperatureOverride,
            maxOutputTokensOverride: whiteMaxOutputTokensOverride,
            thinkingBudgetOverride: whiteThinkingBudgetOverride,
            samplingModeOverride: whiteSamplingModeOverride
        )
        let resolvedBlackSelection = resolveSelection(
            base: blackAISelection,
            temperatureOverride: blackTemperatureOverride,
            maxOutputTokensOverride: blackMaxOutputTokensOverride,
            thinkingBudgetOverride: blackThinkingBudgetOverride,
            samplingModeOverride: blackSamplingModeOverride
        )
        // Point the picker state at the resolved selection so it is what gets
        // saved to `SavedSideSetup` below and is what the user sees next time.
        if whiteIsAI {
            whiteAISelection = resolvedWhiteSelection
            if let selection = resolvedWhiteSelection {
                whitePlayerName = aiDisplayName(for: selection)
            }
            whiteTemperatureOverride = nil
            whiteMaxOutputTokensOverride = nil
            whiteThinkingBudgetOverride = nil
            whiteSamplingModeOverride = nil
        }
        if blackIsAI {
            blackAISelection = resolvedBlackSelection
            if let selection = resolvedBlackSelection {
                blackPlayerName = aiDisplayName(for: selection)
            }
            blackTemperatureOverride = nil
            blackMaxOutputTokensOverride = nil
            blackThinkingBudgetOverride = nil
            blackSamplingModeOverride = nil
        }

        // Build white player config
        let whiteConfig = buildPlayerConfig(
            name: whitePlayerName,
            isAI: whiteIsAI,
            aiSelection: resolvedWhiteSelection,
            color: .white,
            humanPlayerID: whiteHumanPlayerID,
            allowResign: whiteAllowResign
        )

        // Build black player config
        let blackConfig = buildPlayerConfig(
            name: blackPlayerName,
            isAI: blackIsAI,
            aiSelection: resolvedBlackSelection,
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

    // MARK: - Configuration Resolver

    /// Resolves a base AI selection plus per-game parameter tweaks into a
    /// concrete configuration. If an existing configuration matches the
    /// effective parameters, it is reused so repeated tweaks map back to the
    /// same "player" identity for history. Otherwise a new configuration is
    /// created (via `addConfiguration` / `addConfig`) with a derived name.
    private func resolveSelection(
        base: AISelection?,
        temperatureOverride: Double?,
        maxOutputTokensOverride: Int?,
        thinkingBudgetOverride: Int?,
        samplingModeOverride: AISamplingMode?
    ) -> AISelection? {
        guard let base else { return nil }
        switch base {
        case .llmConfig(let baseID):
            return resolveLLMConfig(
                baseID: baseID,
                temperatureOverride: temperatureOverride,
                maxOutputTokensOverride: maxOutputTokensOverride,
                thinkingBudgetOverride: thinkingBudgetOverride
            ).map(AISelection.llmConfig)
        case .appleIntelligence(let baseID):
            return resolveAppleIntelligenceConfig(
                baseID: baseID,
                temperatureOverride: temperatureOverride,
                maxOutputTokensOverride: maxOutputTokensOverride,
                samplingModeOverride: samplingModeOverride
            ).map(AISelection.appleIntelligence)
        }
    }

    /// Finds or creates a `ModelConfiguration` that matches the base plus the
    /// effective temperature / max output tokens / thinking budget. Returns the
    /// resolved configuration's ID, or the base ID if no tweaks applied.
    private func resolveLLMConfig(
        baseID: UUID,
        temperatureOverride: Double?,
        maxOutputTokensOverride: Int?,
        thinkingBudgetOverride: Int?
    ) -> UUID? {
        guard let base = engine.llmKit.configurations.first(where: { $0.id == baseID }) else {
            return nil
        }
        let effectiveTemperature = temperatureOverride ?? base.temperature
        let effectiveMaxOutputTokens = maxOutputTokensOverride ?? base.maxOutputTokens
        let effectiveThinkingBudget = thinkingBudgetOverride ?? base.thinkingBudget

        let noChange = effectiveTemperature == base.temperature
            && effectiveMaxOutputTokens == base.maxOutputTokens
            && effectiveThinkingBudget == base.thinkingBudget
        if noChange {
            return base.id
        }

        // Look for an existing configuration that matches the effective params.
        if let match = engine.llmKit.configurations.first(where: { candidate in
            candidate.providerID == base.providerID &&
            candidate.modelID == base.modelID &&
            candidate.maxContextTokens == base.maxContextTokens &&
            candidate.useDefaultTemperature == base.useDefaultTemperature &&
            candidate.streaming == base.streaming &&
            candidate.extendedCacheTTL == base.extendedCacheTTL &&
            candidate.temperature == effectiveTemperature &&
            candidate.maxOutputTokens == effectiveMaxOutputTokens &&
            candidate.thinkingBudget == effectiveThinkingBudget
        }) {
            return match.id
        }

        // No match — create a new derived configuration.
        let derived = ModelConfiguration(
            name: derivedLLMConfigName(
                base: base,
                temperature: effectiveTemperature,
                maxOutputTokens: effectiveMaxOutputTokens,
                thinkingBudget: effectiveThinkingBudget
            ),
            providerID: base.providerID,
            modelID: base.modelID,
            temperature: effectiveTemperature,
            maxOutputTokens: effectiveMaxOutputTokens,
            maxContextTokens: base.maxContextTokens,
            thinkingBudget: effectiveThinkingBudget,
            extendedCacheTTL: base.extendedCacheTTL,
            useDefaultTemperature: base.useDefaultTemperature,
            streaming: base.streaming
        )
        engine.llmKit.addConfiguration(derived)
        return derived.id
    }

    /// Builds a human-readable name for a derived LLM config that notes only
    /// the fields which differ from the base (e.g. "Claude Sonnet [t=0.30, think=2000]").
    private func derivedLLMConfigName(
        base: ModelConfiguration,
        temperature: Double,
        maxOutputTokens: Int,
        thinkingBudget: Int?
    ) -> String {
        var parts: [String] = []
        if temperature != base.temperature {
            parts.append(String(format: "t=%.2f", temperature))
        }
        if maxOutputTokens != base.maxOutputTokens {
            parts.append("max=\(maxOutputTokens)")
        }
        if thinkingBudget != base.thinkingBudget {
            parts.append("think=\(thinkingBudget.map(String.init) ?? "off")")
        }
        if parts.isEmpty { return base.name }
        return "\(base.name) [\(parts.joined(separator: ", "))]"
    }

    /// Finds or creates an `AppleIntelligenceConfig` that matches the effective
    /// params. If the effective sampling mode is greedy, the temperature override
    /// is discarded because Apple Intelligence ignores temperature under greedy
    /// sampling (it always picks argmax from the logits).
    private func resolveAppleIntelligenceConfig(
        baseID: UUID,
        temperatureOverride: Double?,
        maxOutputTokensOverride: Int?,
        samplingModeOverride: AISamplingMode?
    ) -> UUID? {
        guard let base = engine.appleIntelligenceConfigManager.config(byID: baseID) else {
            return nil
        }
        let effectiveSampling = samplingModeOverride ?? base.samplingMode
        let effectiveMaxTokens = maxOutputTokensOverride ?? base.maximumResponseTokens
        let effectiveTemperature: Double?
        if case .greedy = effectiveSampling {
            effectiveTemperature = nil
        } else {
            effectiveTemperature = temperatureOverride ?? base.temperature
        }

        let noChange = effectiveSampling == base.samplingMode
            && effectiveMaxTokens == base.maximumResponseTokens
            && effectiveTemperature == base.temperature
        if noChange {
            return base.id
        }

        if let match = engine.appleIntelligenceConfigManager.configs.first(where: { candidate in
            candidate.samplingMode == effectiveSampling &&
            candidate.maximumResponseTokens == effectiveMaxTokens &&
            candidate.temperature == effectiveTemperature
        }) {
            return match.id
        }

        let derived = engine.appleIntelligenceConfigManager.addConfig(
            name: derivedAppleIntelligenceName(
                base: base,
                temperature: effectiveTemperature,
                maxTokens: effectiveMaxTokens,
                sampling: effectiveSampling
            ),
            temperature: effectiveTemperature,
            maximumResponseTokens: effectiveMaxTokens,
            samplingMode: effectiveSampling
        )
        return derived.id
    }

    private func derivedAppleIntelligenceName(
        base: AppleIntelligenceConfig,
        temperature: Double?,
        maxTokens: Int?,
        sampling: AISamplingMode
    ) -> String {
        var parts: [String] = []
        if sampling != base.samplingMode {
            switch sampling {
            case .greedy:
                parts.append("greedy")
            case .randomMass(let mass):
                parts.append(String(format: "p=%.2f", mass))
            case .randomTopN(let n):
                parts.append("top-\(n)")
            }
        }
        if temperature != base.temperature {
            parts.append(String(format: "t=%.2f", temperature ?? 0))
        }
        if maxTokens != base.maximumResponseTokens {
            parts.append("max=\(maxTokens.map(String.init) ?? "default")")
        }
        if parts.isEmpty { return base.name }
        return "\(base.name) [\(parts.joined(separator: ", "))]"
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
