import Foundation
import Observation

// MARK: - Apple Intelligence Config Manager

/// Manages persistent Apple Intelligence configuration profiles with file-based JSON storage.
///
/// Profiles are stored at:
/// `~/Library/Application Support/AI Battle Chess/apple-intelligence-configs.json`
///
/// A default configuration is auto-created on first launch.
@Observable
@MainActor
final class AppleIntelligenceConfigManager {

    // MARK: - Properties

    /// All Apple Intelligence configurations, sorted alphabetically by name.
    private(set) var configs: [AppleIntelligenceConfig] = [] {
        didSet { rebuildIndex() }
    }

    /// O(1) lookup index keyed by config ID. Derived from `configs`; excluded from observation.
    @ObservationIgnored
    private var configsByID: [UUID: AppleIntelligenceConfig] = [:]

    private func rebuildIndex() {
        configsByID = Dictionary(uniqueKeysWithValues: configs.map { ($0.id, $0) })
    }

    // MARK: - Storage

    private static let fileName = "apple-intelligence-configs.json"
    private static let appSupportDirectoryName = "AI Battle Chess"

    private var fileURL: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            assertionFailure("Application Support directory not found — falling back to temporary directory")
            return FileManager.default.temporaryDirectory
                .appendingPathComponent(Self.appSupportDirectoryName)
                .appendingPathComponent(Self.fileName)
        }
        return appSupport
            .appendingPathComponent(Self.appSupportDirectoryName)
            .appendingPathComponent(Self.fileName)
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }()

    private let decoder = JSONDecoder()

    // MARK: - Loading

    /// Loads configurations from disk, creating a default if none exist.
    func loadAll() {
        let url = fileURL
        let decoder = self.decoder

        let loaded: [AppleIntelligenceConfig]? = {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            do {
                let data = try Data(contentsOf: url)
                let decoded = try decoder.decode([AppleIntelligenceConfig].self, from: data)
                return decoded.isEmpty ? nil : decoded
            } catch {
                print("[AIConfigManager] Failed to load configs: \(error)")
                return nil
            }
        }()

        if let loaded {
            configs = loaded.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        } else {
            configs = [Self.makeDefault()]
            persistToDisk()
        }
    }

    // MARK: - Persistence

    /// Schedules a background write of the current config list to disk.
    private func persistToDisk() {
        let url = fileURL
        let encoder = self.encoder
        let snapshot = configs

        Task.detached(priority: .utility) {
            let directory = url.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                print("[AIConfigManager] Failed to save configs: \(error)")
            }
        }
    }

    // MARK: - CRUD

    /// Creates a new configuration, persists it, and returns the created config.
    @discardableResult
    func addConfig(
        name: String,
        temperature: Double? = nil,
        maximumResponseTokens: Int? = nil,
        samplingMode: AISamplingMode = .greedy
    ) -> AppleIntelligenceConfig {
        let config = AppleIntelligenceConfig(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            temperature: temperature,
            maximumResponseTokens: maximumResponseTokens,
            samplingMode: samplingMode
        )
        configs.append(config)
        configs.sort(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        persistToDisk()
        return config
    }

    /// Duplicates an existing configuration with a new name.
    @discardableResult
    func duplicateConfig(id: UUID) -> AppleIntelligenceConfig? {
        guard let source = config(byID: id) else { return nil }
        let copy = AppleIntelligenceConfig(
            name: "\(source.name) (Copy)",
            temperature: source.temperature,
            maximumResponseTokens: source.maximumResponseTokens,
            samplingMode: source.samplingMode
        )
        configs.append(copy)
        configs.sort(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        persistToDisk()
        return copy
    }

    /// Updates a configuration in place. The config's `id` must match an existing entry.
    func updateConfig(_ updated: AppleIntelligenceConfig) {
        guard let index = configs.firstIndex(where: { $0.id == updated.id }) else { return }
        configs[index] = updated
        configs.sort(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        persistToDisk()
    }

    /// Deletes a configuration. Refuses to delete the last remaining config.
    func deleteConfig(id: UUID) {
        guard configs.count > 1 else { return }
        configs.removeAll(where: { $0.id == id })
        persistToDisk()
    }

    /// Returns the config with the given ID, or nil if not found. O(1) via dictionary index.
    func config(byID id: UUID) -> AppleIntelligenceConfig? {
        configsByID[id]
    }

    // MARK: - Defaults

    /// Creates the default Apple Intelligence configuration.
    private static func makeDefault() -> AppleIntelligenceConfig {
        AppleIntelligenceConfig(
            name: "Apple Intelligence",
            temperature: nil,
            maximumResponseTokens: nil,
            samplingMode: .greedy
        )
    }
}
