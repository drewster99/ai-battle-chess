import SwiftUI
import SwiftLLMKit

@main
struct AIBattleChessApp: App {
    @State private var llmKit = LLMKitManager(
        appIdentifier: Bundle.main.bundleIdentifier ?? "com.drew.ai-battle-chess",
        keychainServicePrefix: "com.drew.ai-battle-chess"
    )
    @State private var gameHistoryManager = GameHistoryManager()
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
                let gameEngine = GameEngine(llmKit: llmKit, gameHistoryManager: gameHistoryManager)
                engine = gameEngine

                // Refresh model catalog and auto-create configurations
                Task {
                    await llmKit.refreshIfNeeded()
                    autoCreateConfigurations()
                }
            }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1600, height: 900)
    }

    /// Automatically creates a ModelConfiguration for each discovered model with reasonable defaults.
    private func autoCreateConfigurations() {
        let existingConfigs = llmKit.configurations
        let allModels = llmKit.providers.flatMap { provider in
            llmKit.models(for: provider.id).map { (provider, $0) }
        }

        for (provider, model) in allModels {
            // Check if a configuration already exists for this provider+model combo
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
            llmKit.addConfiguration(config)
        }
    }
}
