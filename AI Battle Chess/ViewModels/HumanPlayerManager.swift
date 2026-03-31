import Foundation
import Observation

// MARK: - Human Player Manager

/// Manages persistent human player profiles with file-based JSON storage.
///
/// Profiles are stored at:
/// `~/Library/Application Support/AI Battle Chess/players.json`
///
/// A built-in "Guest" player is auto-created on first launch and cannot be deleted.
@Observable
@MainActor
final class HumanPlayerManager {

    // MARK: - Properties

    /// All human player profiles, sorted with Guest first then alphabetical.
    private(set) var players: [HumanPlayer] = []

    // MARK: - Storage

    private static let fileName = "players.json"
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
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Loading

    /// Loads player profiles from disk, ensuring Guest always exists.
    func loadAll() {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                var loaded = try decoder.decode([HumanPlayer].self, from: data)

                // Ensure Guest exists
                if !loaded.contains(where: { $0.id == HumanPlayer.guestID }) {
                    loaded.append(.guest)
                }

                players = sortPlayers(loaded)
            } catch {
                print("[HumanPlayerManager] Failed to load players: \(error)")
                players = [.guest]
                save()
            }
        } else {
            // First launch — create Guest
            players = [.guest]
            save()
        }
    }

    // MARK: - Persistence

    /// Writes the current player list to disk.
    private func save() {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(players)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[HumanPlayerManager] Failed to save players: \(error)")
        }
    }

    // MARK: - CRUD

    /// Creates a new player profile, persists it, and returns the created player.
    @discardableResult
    func addPlayer(name: String) -> HumanPlayer {
        let player = HumanPlayer(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date(),
            isGuest: false
        )
        players.append(player)
        players = sortPlayers(players)
        save()
        return player
    }

    /// Renames an existing player. Guest's name can be changed.
    func renamePlayer(id: UUID, newName: String) {
        guard let index = players.firstIndex(where: { $0.id == id }) else { return }
        players[index].name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        players = sortPlayers(players)
        save()
    }

    /// Deletes a player profile. The built-in Guest player cannot be deleted.
    func deletePlayer(id: UUID) {
        guard id != HumanPlayer.guestID else { return }
        players.removeAll(where: { $0.id == id })
        save()
    }

    /// Returns the player with the given ID, or nil if not found.
    func player(byID id: UUID) -> HumanPlayer? {
        players.first(where: { $0.id == id })
    }

    // MARK: - Sorting

    /// Guest first, then alphabetical by name.
    private func sortPlayers(_ list: [HumanPlayer]) -> [HumanPlayer] {
        list.sorted { a, b in
            if a.isGuest { return true }
            if b.isGuest { return false }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
