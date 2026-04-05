import SwiftUI
import SwiftLLMKit

@main
struct AIBattleChessApp: App {
    @State private var llmKit = LLMKitManager(
        appIdentifier: Bundle.main.bundleIdentifier ?? "com.drew.ai-battle-chess",
        keychainServicePrefix: "com.drew.ai-battle-chess"
    )
    @State private var gameHistoryManager = GameHistoryManager()
    @State private var humanPlayerManager = HumanPlayerManager()
    @State private var appleIntelligenceConfigManager = AppleIntelligenceConfigManager()
    @State private var engine: GameEngine?

    var body: some Scene {
        WindowGroup {
            Group {
                if let engine {
                    ContentView(engine: engine)
                } else {
                    ProgressView("Loading...")
                        .frame(width: 300, height: 200)
                }
            }
            .onAppear {
                llmKit.load()
                gameHistoryManager.loadAll()
                gameHistoryManager.migrateIsAIFlagsIfNeeded()
                humanPlayerManager.loadAll()
                appleIntelligenceConfigManager.loadAll()
                let gameEngine = GameEngine(llmKit: llmKit, gameHistoryManager: gameHistoryManager, humanPlayerManager: humanPlayerManager, appleIntelligenceConfigManager: appleIntelligenceConfigManager)
                engine = gameEngine

                // Refresh model catalog and auto-create configurations
                Task {
                    await llmKit.refreshIfNeeded()
                    llmKit.autoCreateConfigurations()
                }
            }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1600, height: 900)

        WindowGroup("AI Move Detail", for: AIActivityDetail.self) { $detail in
            if let detail {
                AIActivityDetailView(detail: detail)
            }
        }
        .defaultSize(width: 650, height: 600)
    }
}

// MARK: - Auto-Create Configurations

extension LLMKitManager {
    /// Creates a ModelConfiguration for each discovered model that doesn't already have one.
    func autoCreateConfigurations() {
        let existingConfigs = configurations
        let allModels = providers.flatMap { provider in
            models(for: provider.id).map { (provider, $0) }
        }

        for (provider, model) in allModels {
            let alreadyExists = existingConfigs.contains { config in
                config.providerID == provider.id && config.modelID == model.modelID
            }
            guard !alreadyExists else { continue }

            let config = ModelConfiguration(
                name: "\(provider.name) \(model.displayName)",
                providerID: provider.id,
                modelID: model.modelID,
                temperature: 0.7,
                maxOutputTokens: model.maxOutputTokens ?? 4096,
                maxContextTokens: model.maxInputTokens ?? 128_000,
                streaming: false
            )
            addConfiguration(config)
        }
    }
}
