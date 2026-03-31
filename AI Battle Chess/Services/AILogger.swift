import Foundation

/// Logs full LLM API requests and responses to disk for debugging and analysis.
///
/// Files are organized in a hierarchical directory structure under
/// `~/Library/Application Support/AI Battle Chess/games/`:
/// ```
/// games/<game_uuid>/
///   <color>/                    # "white" or "black"
///     turn_000/                 # game turn index (zero-padded 3 digits)
///       <provider_model>/       # e.g. "anthropic_claude-opus-4" (sanitized)
///         attempt_0_request.json
///         attempt_0_response.json
///         attempt_1_request.json   # retry
///         attempt_1_response.json
/// ```
struct AILogger {

    // MARK: - Base Directory

    /// Base directory for all game log data.
    ///
    /// Resolves to `~/Library/Application Support/AI Battle Chess/games/`.
    static var baseDirectory: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // Fallback to temp directory if Application Support is unavailable
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("AI Battle Chess", isDirectory: true)
                .appendingPathComponent("games", isDirectory: true)
        }
        return appSupport
            .appendingPathComponent("AI Battle Chess", isDirectory: true)
            .appendingPathComponent("games", isDirectory: true)
    }

    // MARK: - Public API

    /// Logs a full API request body to disk.
    ///
    /// - Parameters:
    ///   - gameID: The unique identifier for the current game.
    ///   - color: The color of the player making the request (`.white` or `.black`).
    ///   - gameTurnIndex: This player's Nth turn (0-based).
    ///   - providerModel: The provider/model identifier, e.g. `"anthropic/claude-opus-4"`.
    ///   - attemptIndex: The retry attempt index (0-based).
    ///   - requestBody: The raw JSON request body as `Data`.
    static func logRequest(
        gameID: UUID,
        color: PieceColor,
        gameTurnIndex: Int,
        providerModel: String,
        attemptIndex: Int,
        requestBody: Data
    ) {
        let filename = "attempt_\(attemptIndex)_request.json"
        writeLog(
            gameID: gameID,
            color: color,
            gameTurnIndex: gameTurnIndex,
            providerModel: providerModel,
            filename: filename,
            data: requestBody
        )
    }

    /// Logs a full API response body to disk.
    ///
    /// - Parameters:
    ///   - gameID: The unique identifier for the current game.
    ///   - color: The color of the player that received the response (`.white` or `.black`).
    ///   - gameTurnIndex: This player's Nth turn (0-based).
    ///   - providerModel: The provider/model identifier, e.g. `"anthropic/claude-opus-4"`.
    ///   - attemptIndex: The retry attempt index (0-based).
    ///   - responseBody: The raw JSON response body as `Data`.
    static func logResponse(
        gameID: UUID,
        color: PieceColor,
        gameTurnIndex: Int,
        providerModel: String,
        attemptIndex: Int,
        responseBody: Data
    ) {
        let filename = "attempt_\(attemptIndex)_response.json"
        writeLog(
            gameID: gameID,
            color: color,
            gameTurnIndex: gameTurnIndex,
            providerModel: providerModel,
            filename: filename,
            data: responseBody
        )
    }

    // MARK: - Private Helpers

    /// Sanitizes a string for use as a filesystem directory name.
    ///
    /// Replaces `/`, `:`, and spaces with `_`, then lowercases the result.
    /// - Parameter input: The raw string to sanitize.
    /// - Returns: A filesystem-safe lowercased string.
    private static func sanitizeForFilesystem(_ input: String) -> String {
        let disallowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.")).inverted
        return input
            .unicodeScalars
            .map { disallowed.contains($0) ? "_" : String($0) }
            .joined()
            .lowercased()
    }

    /// Builds the directory URL for a specific turn and provider, then writes data to a file.
    ///
    /// - Parameters:
    ///   - gameID: The unique identifier for the current game.
    ///   - color: The piece color (`.white` or `.black`).
    ///   - gameTurnIndex: The turn index (0-based).
    ///   - providerModel: The raw provider/model string to be sanitized.
    ///   - filename: The file to write (e.g. `"attempt_0_request.json"`).
    ///   - data: The raw data to write.
    private static func writeLog(
        gameID: UUID,
        color: PieceColor,
        gameTurnIndex: Int,
        providerModel: String,
        filename: String,
        data: Data
    ) {
        let turnFolder = String(format: "turn_%03d", gameTurnIndex)
        let sanitizedModel = sanitizeForFilesystem(providerModel)

        let directory = baseDirectory
            .appendingPathComponent(gameID.uuidString, isDirectory: true)
            .appendingPathComponent(color.rawValue, isDirectory: true)
            .appendingPathComponent(turnFolder, isDirectory: true)
            .appendingPathComponent(sanitizedModel, isDirectory: true)

        let fileURL = directory.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            print("[AILogger] Failed to create directory \(directory.path): \(error)")
            return
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[AILogger] Failed to write \(fileURL.path): \(error)")
        }
    }
}
