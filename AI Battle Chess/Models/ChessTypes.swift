import Foundation

// MARK: - Piece Color

enum PieceColor: String, Codable, Sendable, Equatable, CaseIterable {
    case white
    case black

    var opposite: PieceColor {
        self == .white ? .black : .white
    }

    var displayName: String {
        rawValue.capitalized
    }

    var symbol: String {
        self == .white ? "♔" : "♚"
    }
}

// MARK: - Piece Type

enum PieceType: String, Codable, Sendable, Equatable, CaseIterable {
    case pawn
    case knight
    case bishop
    case rook
    case queen
    case king

    var notation: String {
        switch self {
        case .pawn: return ""
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }

    var value: Int {
        switch self {
        case .pawn: return 1
        case .knight: return 3
        case .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 0
        }
    }

    var assetPrefix: String {
        switch self {
        case .pawn: return "P"
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }
}

// MARK: - Chess Piece

struct ChessPiece: Equatable, Sendable, Codable, Identifiable {
    let id: UUID
    let color: PieceColor
    let type: PieceType

    init(color: PieceColor, type: PieceType, id: UUID = UUID()) {
        self.id = id
        self.color = color
        self.type = type
    }

    var assetName: String {
        let colorPrefix = color == .white ? "w" : "b"
        return "\(colorPrefix)\(type.assetPrefix)"
    }

    var notation: String {
        type.notation
    }
}

// MARK: - Board Position

struct BoardPosition: Hashable, Equatable, Sendable, Codable, CustomStringConvertible {
    let file: Int // 0-7 (a-h)
    let rank: Int // 0-7 (1-8)

    var description: String {
        guard let scalar = UnicodeScalar(97 + file) else { return "?\(rank + 1)" }
        let fileChar = Character(scalar)
        return "\(fileChar)\(rank + 1)"
    }

    var isValid: Bool {
        file >= 0 && file < 8 && rank >= 0 && rank < 8
    }

    init(file: Int, rank: Int) {
        self.file = file
        self.rank = rank
    }

    init?(algebraic: String) {
        guard algebraic.count == 2,
              let fileChar = algebraic.first,
              let rankChar = algebraic.last,
              let asciiVal = fileChar.asciiValue,
              let rankVal = rankChar.wholeNumberValue else {
            return nil
        }
        let f = Int(asciiVal) - 97
        let r = rankVal - 1
        guard f >= 0, f < 8, r >= 0, r < 8 else { return nil }
        self.file = f
        self.rank = r
    }
}

// MARK: - Chess Move

struct ChessMove: Equatable, Sendable, Codable, Identifiable {
    let id: UUID
    let piece: ChessPiece
    let from: BoardPosition
    let to: BoardPosition
    let capturedPiece: ChessPiece?
    let isEnPassant: Bool
    let isCastleKingside: Bool
    let isCastleQueenside: Bool
    let promotionType: PieceType?
    let isCheck: Bool
    let isCheckmate: Bool
    let comment: String?
    let thinking: String?

    init(
        piece: ChessPiece,
        from: BoardPosition,
        to: BoardPosition,
        capturedPiece: ChessPiece? = nil,
        isEnPassant: Bool = false,
        isCastleKingside: Bool = false,
        isCastleQueenside: Bool = false,
        promotionType: PieceType? = nil,
        isCheck: Bool = false,
        isCheckmate: Bool = false,
        comment: String? = nil,
        thinking: String? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.piece = piece
        self.from = from
        self.to = to
        self.capturedPiece = capturedPiece
        self.isEnPassant = isEnPassant
        self.isCastleKingside = isCastleKingside
        self.isCastleQueenside = isCastleQueenside
        self.promotionType = promotionType
        self.isCheck = isCheck
        self.isCheckmate = isCheckmate
        self.comment = comment
        self.thinking = thinking
    }

    /// Returns a copy with check/checkmate flags and optional comment/thinking updated.
    func withCheckStatus(isCheck: Bool, isCheckmate: Bool, comment: String? = nil, thinking: String? = nil) -> ChessMove {
        ChessMove(
            piece: piece,
            from: from,
            to: to,
            capturedPiece: capturedPiece,
            isEnPassant: isEnPassant,
            isCastleKingside: isCastleKingside,
            isCastleQueenside: isCastleQueenside,
            promotionType: promotionType,
            isCheck: isCheck,
            isCheckmate: isCheckmate,
            comment: comment ?? self.comment,
            thinking: thinking ?? self.thinking,
            id: id
        )
    }
}

// MARK: - Game Result

enum GameResult: Equatable, Sendable, Codable {
    case checkmate(winner: PieceColor)
    case stalemate
    case insufficientMaterial
    case fiftyMoveRule
    case threefoldRepetition
    case resignation(winner: PieceColor)
    case drawByAgreement

    var displayText: String {
        switch self {
        case .checkmate(let winner):
            return "Checkmate! \(winner.displayName) wins!"
        case .stalemate:
            return "Stalemate - Draw!"
        case .insufficientMaterial:
            return "Insufficient Material - Draw!"
        case .fiftyMoveRule:
            return "50-Move Rule - Draw!"
        case .threefoldRepetition:
            return "Threefold Repetition - Draw!"
        case .resignation(let winner):
            return "\(winner.opposite.displayName) resigned. \(winner.displayName) wins!"
        case .drawByAgreement:
            return "Draw by Agreement"
        }
    }

    var pgnResult: String {
        switch self {
        case .checkmate(let winner), .resignation(let winner):
            return winner == .white ? "1-0" : "0-1"
        case .stalemate, .insufficientMaterial, .fiftyMoveRule, .threefoldRepetition, .drawByAgreement:
            return "1/2-1/2"
        }
    }

    var pgnResultComment: String? {
        switch self {
        case .threefoldRepetition: return "threefold repetition"
        case .fiftyMoveRule: return "50 move rule"
        case .insufficientMaterial: return "insufficient material"
        case .stalemate: return "stalemate"
        default: return nil
        }
    }
}

// MARK: - Game Mode

enum GameMode: String, Codable, Sendable, CaseIterable {
    case playerVsPlayer = "Player vs Player"
    case playerVsAI = "Player vs AI"
    case aiVsAI = "AI vs AI"
}

// MARK: - Human Player

/// A persistent human player profile.
struct HumanPlayer: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    let isGuest: Bool

    // Well-known ID for the built-in Guest player
    // swiftlint:disable:next force_unwrapping
    static let guestID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    static var guest: HumanPlayer {
        HumanPlayer(id: guestID, name: "Guest", createdAt: .distantPast, isGuest: true)
    }
}

// MARK: - Apple Intelligence Configuration

/// Sampling strategy for Apple Intelligence on-device generation.
enum AISamplingMode: Sendable, Equatable, Hashable {
    case greedy
    case randomMass(Double)   // probabilityThreshold (0.0–1.0)
    case randomTopN(Int)      // top-k token count
}

extension AISamplingMode: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, value
    }

    private enum Kind: String, Codable {
        case greedy, randomMass, randomTopN
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .greedy:
            try container.encode(Kind.greedy, forKey: .kind)
        case .randomMass(let mass):
            try container.encode(Kind.randomMass, forKey: .kind)
            try container.encode(mass, forKey: .value)
        case .randomTopN(let n):
            try container.encode(Kind.randomTopN, forKey: .kind)
            try container.encode(n, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .greedy:
            self = .greedy
        case .randomMass:
            let mass = try container.decode(Double.self, forKey: .value)
            self = .randomMass(mass)
        case .randomTopN:
            let n = try container.decode(Int.self, forKey: .value)
            self = .randomTopN(n)
        }
    }
}

/// Configuration for an Apple Intelligence on-device model instance.
struct AppleIntelligenceConfig: Equatable, Sendable, Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var temperature: Double?           // nil = system default
    var maximumResponseTokens: Int?    // nil = system default
    var samplingMode: AISamplingMode

    init(
        id: UUID = UUID(),
        name: String = "Apple Intelligence",
        temperature: Double? = nil,
        maximumResponseTokens: Int? = nil,
        samplingMode: AISamplingMode = .greedy
    ) {
        self.id = id
        self.name = name
        self.temperature = temperature
        self.maximumResponseTokens = maximumResponseTokens
        self.samplingMode = samplingMode
    }

    /// Human-readable summary of the sampling configuration.
    var samplingDescription: String {
        switch samplingMode {
        case .greedy:
            return "Greedy"
        case .randomMass(let mass):
            return "Random (p=\(String(format: "%.2f", mass)))"
        case .randomTopN(let n):
            return "Random (top-\(n))"
        }
    }
}

// MARK: - Player Configuration

struct PlayerConfig: Equatable, Sendable, Codable, Identifiable {
    let id: UUID
    var name: String
    var isAI: Bool
    var aiConfigurationID: UUID?  // References ModelConfiguration.id from SwiftLLMKit
    var useAppleIntelligence: Bool
    var appleIntelligenceConfigID: UUID?  // References AppleIntelligenceConfig.id
    var color: PieceColor
    var humanPlayerID: UUID?  // References HumanPlayer.id for human players
    var allowResign: Bool

    init(
        name: String = "Player",
        isAI: Bool = false,
        aiConfigurationID: UUID? = nil,
        useAppleIntelligence: Bool = false,
        appleIntelligenceConfigID: UUID? = nil,
        color: PieceColor = .white,
        humanPlayerID: UUID? = nil,
        allowResign: Bool = true,
        id: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.isAI = isAI
        self.aiConfigurationID = aiConfigurationID
        self.useAppleIntelligence = useAppleIntelligence
        self.appleIntelligenceConfigID = appleIntelligenceConfigID
        self.color = color
        self.humanPlayerID = humanPlayerID
        self.allowResign = allowResign
    }
}

// MARK: - AI Penalty

struct AIPenalty: Codable, Sendable, Equatable {
    let reason: String
    let severity: PenaltySeverity
    let timestamp: Date

    enum PenaltySeverity: String, Codable, Sendable, Equatable {
        case warning    // Syntax issue, move clarified
        case minor      // Invalid move attempted
        case major      // Repeated invalid moves
        case critical   // Too many failures, forfeit
    }
}

// MARK: - Game Statistics

struct GameStatistics: Codable, Sendable, Equatable {
    var totalMoves: Int = 0
    var captureCount: [PieceColor: Int] = [.white: 0, .black: 0]
    var checkCount: [PieceColor: Int] = [.white: 0, .black: 0]
    var castled: [PieceColor: Bool] = [.white: false, .black: false]
    var promotions: [PieceColor: Int] = [.white: 0, .black: 0]
    var aiPenalties: [PieceColor: [AIPenalty]] = [.white: [], .black: []]
    var aiRetryCount: [PieceColor: Int] = [.white: 0, .black: 0]
    var materialValue: [PieceColor: Int] = [.white: 39, .black: 39]

    // Timing
    var gameStartTime: Date = Date()
    var moveTimestamps: [Date] = []
    var perMoveDuration: [PieceColor: [TimeInterval]] = [.white: [], .black: []]
    var turnStartTime: Date = Date()
}

// MARK: - Game Record

/// A completed game record, stored as one JSON file per game for merge-friendly storage.
struct GameRecord: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let whitePlayerName: String
    let blackPlayerName: String
    let whitePlayerID: UUID?  // HumanPlayer.id for human players, nil for AI or legacy records
    let blackPlayerID: UUID?  // HumanPlayer.id for human players, nil for AI or legacy records
    let gameMode: GameMode
    let result: GameResult
    let moveCount: Int
    let pgnText: String
    let statistics: GameStatistics
    let humanTime: TimeInterval
    let aiTime: TimeInterval
}

// MARK: - AI Activity Log

/// A single attempt by the AI to produce a move.
struct AITurnAttempt: Sendable, Identifiable {
    let id = UUID()
    let thinking: String?
    let moveText: String
    let comment: String?
    let isValid: Bool
    let errorMessage: String?

    static func == (lhs: AITurnAttempt, rhs: AITurnAttempt) -> Bool {
        lhs.thinking == rhs.thinking &&
        lhs.moveText == rhs.moveText &&
        lhs.comment == rhs.comment &&
        lhs.isValid == rhs.isValid &&
        lhs.errorMessage == rhs.errorMessage
    }
}

extension AITurnAttempt: Equatable {}

/// Captures the details of a single AI interaction for display and debugging.
struct AIActivityLog: Sendable, Equatable {
    let systemPrompt: String
    let userPrompt: String
    let responseText: String
    let temperature: Double?
    let thinkingBudget: Int?
    let maxOutputTokens: Int?
    let modelName: String
    let providerName: String
    let tokenUsage: TokenUsage?
    let guidedGenerationResult: AIGuidedGenerationResult?
    var attempts: [AITurnAttempt]
    let requestTimestamp: Date?
    let responseTimestamp: Date?
}

// MARK: - Token Usage

/// Token counts from an LLM API response.
struct TokenUsage: Codable, Sendable, Equatable, Hashable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let cacheReadTokens: Int?
    let cacheCreationTokens: Int?
    let thinkingTokens: Int?
}

// MARK: - AI Guided Generation Result

/// Structured output from Apple Intelligence guided generation.
struct AIGuidedGenerationResult: Sendable, Equatable {
    let thinkingLogic: String
    let move: String
}

// MARK: - AI Selection

/// Represents the user's choice of AI for a player slot.
enum AISelection: Hashable, Sendable {
    case appleIntelligence(UUID)  // Carries an AppleIntelligenceConfig.id
    case llmConfig(UUID)

    var isAppleIntelligence: Bool {
        if case .appleIntelligence = self { return true }
        return false
    }

    var appleIntelligenceConfigID: UUID? {
        if case .appleIntelligence(let id) = self { return id }
        return nil
    }

    var llmConfigID: UUID? {
        if case .llmConfig(let id) = self { return id }
        return nil
    }
}

extension Optional where Wrapped == AISelection {
    var isAppleIntelligence: Bool {
        self?.isAppleIntelligence ?? false
    }

    var appleIntelligenceConfigID: UUID? {
        self?.appleIntelligenceConfigID
    }

    var llmConfigID: UUID? {
        self?.llmConfigID
    }
}
