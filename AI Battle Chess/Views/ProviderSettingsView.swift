import SwiftUI
import SwiftLLMKit

// MARK: - Provider Template

/// Known provider templates with default endpoints for common LLM services.
private struct ProviderTemplate: Identifiable {
    let id: String
    let name: String
    let apiType: ProviderType
    let defaultEndpoint: URL
    let requiresAPIKey: Bool
}

// MARK: - Provider Settings View

/// Settings sheet for managing LLM providers, API keys, and model configurations.
///
/// Displays a list of known provider types (Anthropic, OpenAI, etc.) with fields for API keys
/// and custom endpoints. Users can add/update providers, discover available models, and view
/// the resulting model configurations.
struct ProviderSettingsView: View {
    let llmKit: LLMKitManager
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeys: [String: String] = [:]
    @State private var endpoints: [String: String] = [:]
    @State private var isDiscovering = false
    @State private var discoveryError: String? = nil
    @State private var discoveryTask: Task<Void, Never>? = nil

    // Configuration editor state
    @State private var editingConfigID: UUID? = nil
    @State private var editName: String = ""
    @State private var editTemperature: Double = 0.7
    @State private var editMaxOutputTokens: Int = 4096
    @State private var editMaxContextTokens: Int = 128_000
    @State private var editThinkingBudget: Int? = nil

    // Compile-time constant URLs -- force-unwrap is acceptable here.
    // swiftlint:disable force_unwrapping
    private static let templates: [ProviderTemplate] = [
        ProviderTemplate(id: "anthropic", name: "Anthropic", apiType: .anthropic,
                        defaultEndpoint: URL(string: "https://api.anthropic.com")!,
                        requiresAPIKey: true),
        ProviderTemplate(id: "openai", name: "OpenAI", apiType: .openAICompatible,
                        defaultEndpoint: URL(string: "https://api.openai.com/v1")!,
                        requiresAPIKey: true),
        ProviderTemplate(id: "gemini", name: "Gemini", apiType: .gemini,
                        defaultEndpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
                        requiresAPIKey: true),
        ProviderTemplate(id: "mistral", name: "Mistral", apiType: .mistral,
                        defaultEndpoint: URL(string: "https://api.mistral.ai/v1")!,
                        requiresAPIKey: true),
        ProviderTemplate(id: "xai", name: "xAI", apiType: .xAI,
                        defaultEndpoint: URL(string: "https://api.x.ai/v1")!,
                        requiresAPIKey: true),
        ProviderTemplate(id: "deepseek", name: "DeepSeek", apiType: .openAICompatible,
                        defaultEndpoint: URL(string: "https://api.deepseek.com/v1")!,
                        requiresAPIKey: true),
        ProviderTemplate(id: "ollama", name: "Ollama (Local)", apiType: .ollama,
                        defaultEndpoint: URL(string: "http://localhost:11434")!,
                        requiresAPIKey: false),
        ProviderTemplate(id: "ollama-cloud", name: "Ollama Cloud", apiType: .ollama,
                        defaultEndpoint: URL(string: "https://ollama.com/api")!,
                        requiresAPIKey: true),
        ProviderTemplate(id: "huggingface", name: "Hugging Face", apiType: .huggingFace,
                        defaultEndpoint: URL(string: "https://router.huggingface.co/v1")!,
                        requiresAPIKey: true),
        ProviderTemplate(id: "lmstudio", name: "LM Studio (Local)", apiType: .lmStudio,
                        defaultEndpoint: URL(string: "http://localhost:1234/v1")!,
                        requiresAPIKey: false),
    ]
    // swiftlint:enable force_unwrapping

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AI Provider Settings")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    providersSection

                    Divider()

                    actionsSection

                    Divider()

                    configurationsSection
                }
                .padding()
            }
        }
        .frame(width: 700, height: 600)
        .onAppear {
            loadExistingKeys()
        }
        .onDisappear {
            discoveryTask?.cancel()
        }
    }

    // MARK: - Providers Section

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Providers")
                .font(.headline)

            ForEach(Self.templates) { template in
                providerRow(template)
            }
        }
    }

    private func providerRow(_ template: ProviderTemplate) -> some View {
        let isConfigured = llmKit.providers.contains(where: { $0.id == template.id })

        return HStack(spacing: 12) {
            Circle()
                .fill(isConfigured ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)

            Text(template.name)
                .font(.body)
                .frame(width: 120, alignment: .leading)

            if template.requiresAPIKey {
                SecureField("API Key", text: Binding(
                    get: { apiKeys[template.id] ?? "" },
                    set: { apiKeys[template.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 250)
            } else {
                TextField("Endpoint", text: Binding(
                    get: { endpoints[template.id] ?? template.defaultEndpoint.absoluteString },
                    set: { endpoints[template.id] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 250)
            }

            Button(isConfigured ? "Update" : "Add") {
                saveProvider(template)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(template.requiresAPIKey && (apiKeys[template.id] ?? "").isEmpty)
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        HStack {
            Button {
                discoverModels()
            } label: {
                HStack(spacing: 4) {
                    if isDiscovering {
                        ProgressView().controlSize(.small)
                    }
                    Text("Discover Models")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isDiscovering || llmKit.providers.isEmpty)

            if let error = discoveryError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Spacer()

            Text("\(llmKit.configurations.filter(\.isValid).count) configurations available")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Configurations Section

    private var configurationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model Configurations")
                .font(.headline)

            let validConfigs = llmKit.configurations.filter(\.isValid)

            if validConfigs.isEmpty {
                Text("No configurations yet. Add a provider and click 'Discover Models'.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let grouped = Dictionary(grouping: validConfigs, by: { $0.providerID })

                ForEach(Array(grouped.keys.sorted()), id: \.self) { providerID in
                    let providerName = llmKit.providers.first(where: { $0.id == providerID })?.name ?? providerID

                    DisclosureGroup(providerName) {
                        if let configs = grouped[providerID] {
                            ForEach(configs) { config in
                                if editingConfigID == config.id {
                                    configEditor(for: config)
                                } else {
                                    configRow(for: config)
                                }
                            }
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Configuration Row

    private func configRow(for config: ModelConfiguration) -> some View {
        HStack {
            Text(config.name)
                .font(.caption)
            Spacer()
            Text("temp: \(config.temperature, specifier: "%.1f")")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("max: \(config.maxOutputTokens)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("ctx: \(config.maxContextTokens)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let budget = config.thinkingBudget {
                Text("think: \(budget)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Edit") {
                startEditing(config)
            }
            Button("Duplicate & Edit") {
                if let duplicate = llmKit.duplicateConfiguration(id: config.id) {
                    startEditing(duplicate)
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                llmKit.deleteConfiguration(id: config.id)
            }
        }
    }

    // MARK: - Configuration Editor

    private func startEditing(_ config: ModelConfiguration) {
        editingConfigID = config.id
        editName = config.name
        editTemperature = config.temperature
        editMaxOutputTokens = config.maxOutputTokens
        editMaxContextTokens = config.maxContextTokens
        editThinkingBudget = config.thinkingBudget
    }

    private func configEditor(for config: ModelConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $editName)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Temperature")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Slider(value: $editTemperature, in: 0...2, step: 0.1)
                            .frame(width: 100)
                        Text("\(editTemperature, specifier: "%.1f")")
                            .font(.caption.monospacedDigit())
                            .frame(width: 28)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Max Output Tokens")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("", value: $editMaxOutputTokens, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .font(.caption)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Context Size")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("", value: $editMaxContextTokens, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .font(.caption)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Thinking Budget")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("None", value: $editThinkingBudget, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .font(.caption)
                }
            }

            HStack {
                Button("Save") {
                    var updated = config
                    updated.name = editName
                    updated.temperature = editTemperature
                    updated.maxOutputTokens = editMaxOutputTokens
                    updated.maxContextTokens = editMaxContextTokens
                    updated.thinkingBudget = editThinkingBudget
                    llmKit.updateConfiguration(updated)
                    editingConfigID = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Cancel") {
                    editingConfigID = nil
                }
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.05))
        )
    }

    // MARK: - Actions

    /// Loads existing API keys and endpoints from configured providers into the local state.
    private func loadExistingKeys() {
        for template in Self.templates {
            if let provider = llmKit.providers.first(where: { $0.id == template.id }) {
                if let key = llmKit.apiKey(for: provider.id), !key.isEmpty {
                    apiKeys[template.id] = key
                }
                endpoints[template.id] = provider.endpoint.absoluteString
            }
        }
    }

    /// Saves or updates a provider from a template, storing the API key in Keychain.
    private func saveProvider(_ template: ProviderTemplate) {
        let endpointStr = endpoints[template.id] ?? template.defaultEndpoint.absoluteString
        guard let endpoint = URL(string: endpointStr) else {
            discoveryError = "Invalid endpoint URL"
            return
        }
        let apiKey = apiKeys[template.id] ?? ""

        let provider = ModelProvider(
            id: template.id,
            name: template.name,
            apiType: template.apiType,
            endpoint: endpoint
        )

        do {
            if llmKit.providers.contains(where: { $0.id == template.id }) {
                try llmKit.updateProvider(provider, apiKey: apiKey.isEmpty ? nil : apiKey)
                print("[ProviderSettings] Updated provider '\(template.name)' (key length: \(apiKey.count))")
            } else {
                try llmKit.addProvider(provider, apiKey: apiKey)
                print("[ProviderSettings] Added provider '\(template.name)' (key length: \(apiKey.count))")
            }

            // Verify the key was saved by reading it back
            if let savedKey = llmKit.apiKey(for: template.id) {
                print("[ProviderSettings] Keychain verify: key retrieved OK (length: \(savedKey.count))")
            } else {
                print("[ProviderSettings] WARNING: Keychain verify FAILED — apiKey(for: \(template.id)) returned nil")
            }

            discoveryError = nil

            // Fetch models immediately after saving/updating a key
            print("[ProviderSettings] Triggering model refresh after key update for '\(template.name)'")
            discoveryTask?.cancel()
            isDiscovering = true
            discoveryTask = Task {
                await llmKit.forceRefresh()
                guard !Task.isCancelled else { return }
                llmKit.autoCreateConfigurations()
                isDiscovering = false

                let errors = llmKit.refreshErrors
                if !errors.isEmpty {
                    discoveryError = errors.values.joined(separator: "; ")
                }
            }
        } catch {
            print("[ProviderSettings] ERROR saving provider '\(template.name)': \(error)")
            discoveryError = "Failed to save provider: \(error.localizedDescription)"
        }
    }

    /// Triggers a model discovery refresh across all configured providers.
    private func discoverModels() {
        isDiscovering = true
        discoveryError = nil

        discoveryTask?.cancel()
        discoveryTask = Task {
            await llmKit.forceRefresh()
            guard !Task.isCancelled else { return }
            llmKit.autoCreateConfigurations()
            isDiscovering = false

            let errors = llmKit.refreshErrors
            if !errors.isEmpty {
                discoveryError = errors.values.joined(separator: "; ")
            }
        }
    }

}
