import Foundation
import Observation

// MARK: - Game History Manager

/// Manages per-game disk persistence with merge-friendly UUID-based storage.
///
/// Each completed game is stored as its own JSON file at:
/// `~/Library/Application Support/AI Battle Chess/games/<game_uuid>/game.json`
///
/// This structure avoids merge conflicts when syncing via iCloud Drive or version control,
/// since each game writes to a unique path and never modifies another game's file.
@Observable
@MainActor
final class GameHistoryManager {

    // MARK: - Properties

    /// All loaded game records, sorted by start time descending (most recent first).
    var gameRecords: [GameRecord] = []

    // MARK: - Computed Queries

    /// The total number of games played.
    var totalGamesPlayed: Int {
        gameRecords.count
    }

    /// The cumulative time spent by human players across all recorded games.
    var totalHumanTime: TimeInterval {
        gameRecords.reduce(0) { $0 + $1.humanTime }
    }

    /// The cumulative time spent by AI players across all recorded games.
    var totalAITime: TimeInterval {
        gameRecords.reduce(0) { $0 + $1.aiTime }
    }

    // MARK: - Storage

    private static let gamesDirectoryName = "games"
    private static let gameFileName = "game.json"
    private static let appSupportDirectoryName = "AI Battle Chess"

    private var gamesRootURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent(Self.appSupportDirectoryName)
            .appendingPathComponent(Self.gamesDirectoryName)
    }

    // MARK: - Encoder / Decoder

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

    // MARK: - Persistence

    /// Saves a game record to disk at `games/<id>/game.json` and inserts it into `gameRecords`.
    ///
    /// Creates the game's directory if it does not already exist. The record is inserted
    /// into `gameRecords` at the correct position to maintain descending start-time order.
    func save(_ record: GameRecord) {
        let directory = gameDirectory(for: record.id)
        let fileURL = directory.appendingPathComponent(Self.gameFileName)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(record)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[GameHistoryManager] Failed to save game \(record.id): \(error)")
            return
        }

        // Insert while maintaining descending startTime order
        if let insertionIndex = gameRecords.firstIndex(where: { $0.startTime < record.startTime }) {
            gameRecords.insert(record, at: insertionIndex)
        } else {
            gameRecords.append(record)
        }
    }

    /// Scans all UUID subdirectories under the games root and loads each `game.json`.
    ///
    /// Records that fail to decode are logged and skipped. The resulting array is sorted
    /// by start time descending.
    func loadAll() {
        let fileManager = FileManager.default

        // If the games directory doesn't exist yet, there's nothing to load.
        guard fileManager.fileExists(atPath: gamesRootURL.path) else {
            gameRecords = []
            return
        }

        var loadedRecords: [GameRecord] = []

        do {
            let subdirectories = try fileManager.contentsOfDirectory(
                at: gamesRootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            )

            for subdirectory in subdirectories {
                let gameFile = subdirectory.appendingPathComponent(Self.gameFileName)
                guard fileManager.fileExists(atPath: gameFile.path) else {
                    continue
                }

                do {
                    let data = try Data(contentsOf: gameFile)
                    let record = try decoder.decode(GameRecord.self, from: data)
                    loadedRecords.append(record)
                } catch {
                    print("[GameHistoryManager] Failed to load game at \(gameFile.path): \(error)")
                }
            }
        } catch {
            print("[GameHistoryManager] Failed to enumerate games directory: \(error)")
        }

        gameRecords = loadedRecords.sorted { $0.startTime > $1.startTime }
    }

    /// Returns the directory URL for a given game's storage.
    ///
    /// - Parameter gameID: The unique identifier of the game.
    /// - Returns: A URL of the form `games/<gameID>/`.
    func gameDirectory(for gameID: UUID) -> URL {
        gamesRootURL.appendingPathComponent(gameID.uuidString)
    }

    // MARK: - Query Methods

    /// Returns all games where the specified players occupied the white and black seats.
    ///
    /// - Parameters:
    ///   - white: The white player's name.
    ///   - black: The black player's name.
    /// - Returns: Matching records, sorted by start time descending.
    func gamesBetween(white: String, black: String) -> [GameRecord] {
        gameRecords.filter { $0.whitePlayerName == white && $0.blackPlayerName == black }
    }

    /// Returns win/draw tallies for the given matchup.
    ///
    /// - Parameters:
    ///   - white: The white player's name.
    ///   - black: The black player's name.
    /// - Returns: A tuple of white wins, black wins, and draws.
    func previousResults(white: String, black: String) -> (whiteWins: Int, blackWins: Int, draws: Int) {
        let matchups = gamesBetween(white: white, black: black)

        var whiteWins = 0
        var blackWins = 0
        var draws = 0

        for record in matchups {
            switch record.result {
            case .checkmate(let winner), .resignation(let winner):
                if winner == .white {
                    whiteWins += 1
                } else {
                    blackWins += 1
                }
            case .stalemate, .insufficientMaterial, .fiftyMoveRule, .drawByAgreement:
                draws += 1
            }
        }

        return (whiteWins: whiteWins, blackWins: blackWins, draws: draws)
    }

    /// Returns the total number of games a player has participated in (as white or black).
    ///
    /// - Parameter name: The player name to search for.
    /// - Returns: The count of games where the player appeared as either white or black.
    func totalGamesForPlayer(name: String) -> Int {
        gameRecords.count(where: { $0.whitePlayerName == name || $0.blackPlayerName == name })
    }
}
