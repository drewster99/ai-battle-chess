# Lichess Bot Integration — Complete Plan

## Context

The app currently supports local games (human vs human, human vs AI, AI vs AI) with LLM-based and Apple Intelligence engines. The goal is to connect to Lichess.org as a **bot player**, where the app's AI engine plays against remote Lichess opponents. Lichess games should be viewable in the existing game history alongside local games.

### Key challenges
- `GameEngine.applyMove()` is monolithic: tightly couples animation, state updates, game-end detection, and AI triggering. Lichess needs a decoupled game loop.
- The Lichess Bot API uses NDJSON streaming and UCI move format.
- The data model has no concept of game source or Lichess metadata.
- No chess clock UI exists.

### Design decisions made
- **One concurrent game**: Lichess API supports multiple, but we limit to 1 to match the existing single-game UI.
- **Explicit "Lichess mode"**: User must put the app into Lichess mode via a manual "Go Online" toggle. The app doesn't auto-connect on launch.
- **Configurable auto-accept**: When online, challenges matching user preferences (time controls, rated/casual) are auto-accepted. Others are declined. New challenges are auto-declined while a game is active (reason: "later").
- **Accept only (v1)**: Bot only responds to incoming challenges, no seeking/challenging other players.
- **AI model selection**: User picks which AI model the bot uses when entering Lichess mode, from existing SwiftLLMKit / Apple Intelligence configs.
- **Single bot identity**: One Lichess account + token. User can swap the AI model powering the bot at any time. The Lichess side doesn't know or care what model is behind the moves.

### Outstanding questions
- **Draw offers**: Should the bot auto-decline all draw offers, or should it evaluate the position? (Suggestion: auto-decline for v1, add heuristic later.)
- **Chat**: Should the bot send chat messages (e.g., "gg" on game end)? Or stay silent? (Suggestion: silent for v1.)
- **Reconnect mid-game**: If the app crashes or loses network during a game, the `gameFull` event on reconnect includes all moves so far. We can resync. But should we auto-reconnect to the event stream on app relaunch? (Suggestion: no, user must click "Go Online" again.)

---

## Lichess Account Setup (One-Time, Manual)

The user performs these steps on lichess.org before using the integration:

### Step 1: Create a Lichess account
- Go to https://lichess.org/signup
- Create a new account (e.g., "MyChessBot")
- **Critical**: The account must have **zero games played** to be eligible for bot upgrade

### Step 2: Generate a Personal Access Token
- Go to https://lichess.org/account/oauth/token/create
- Select scopes: `bot:play`, `challenge:read`, `challenge:write`
- Click "Generate"
- Copy the token (starts with `lip_`)
- Token is long-lived (~1 year), no refresh tokens

### Step 3: Upgrade to Bot (irreversible)
- The app can do this automatically via API (see below), OR
- User can do it manually via curl:
  ```
  curl -X POST https://lichess.org/api/bot/account/upgrade \
    -H "Authorization: Bearer lip_xxxxx"
  ```

### Step 4: Enter token in app
- Open Lichess Settings in the app
- Paste token
- App calls `GET /api/account` to verify it's valid and shows `title: "BOT"`
- Token stored in Keychain

---

## Lichess Bot API — Complete Reference

Base URL: `https://lichess.org`
Auth: `Authorization: Bearer <token>` on every request
Content types: JSON for single responses, `application/x-ndjson` for streams

### API 1: Get Account

Verifies the token and retrieves bot identity.

```
GET /api/account
Authorization: Bearer lip_xxxxx
```

**Response** (200 OK):
```json
{
  "id": "mychessbot",
  "username": "MyChessBot",
  "url": "https://lichess.org/@/MyChessBot",
  "title": "BOT",
  "createdAt": 1762523304481,
  "seenAt": 1769264063446,
  "perfs": {
    "bullet":  { "games": 53, "rating": 1805, "rd": 101, "prog": 14 },
    "blitz":   { "games": 222, "rating": 1622, "rd": 45, "prog": -9 },
    "rapid":   { "games": 69, "rating": 1654, "rd": 63, "prog": -15 },
    "classical": { "games": 1613, "rating": 1811, "rd": 47, "prog": 8 },
    "correspondence": { "games": 766, "rating": 1814, "rd": 54, "prog": -53 },
    "chess960": { "games": 166, "rating": 1737, "rd": 45, "prog": 20 }
  },
  "profile": {
    "flag": "US",
    "bio": "AI Battle Chess bot",
    "links": "https://github.com/..."
  },
  "playTime": { "total": 13772, "tv": 0 },
  "count": {
    "all": 5006, "rated": 4004,
    "win": 2016, "loss": 1880, "draw": 1110,
    "playing": 0
  },
  "playing": "https://lichess.org/abc123",
  "followable": true,
  "following": false,
  "blocking": false
}
```

**Fields we use**:
| Field | Purpose |
|-------|---------|
| `id`, `username` | Bot identity, display in UI |
| `title` | Must be `"BOT"` — if missing, account needs upgrade |
| `perfs.{variant}.rating` | Bot's rating per time control, display in player panel |
| `count.all/win/loss/draw` | Bot's overall stats on Lichess |
| `playing` | URL of game in progress (for reconnect scenario) |

**Fields we ignore**: `profile`, `playTime`, `flair`, `patron`, `streaming`, `streamer`, `fideId`, `verified`, `disabled`, `tosViolation`

**Errors**: 401 = invalid token

### API 2: Upgrade to Bot

One-time, irreversible upgrade of account to bot status.

```
POST /api/bot/account/upgrade
Authorization: Bearer lip_xxxxx
```

**Response**: 200 OK `{"ok": true}`
**Errors**: 400 = account has played games (cannot upgrade)

**App behavior**: If `GET /api/account` returns no `title: "BOT"`, show an "Upgrade to Bot" button in settings. Warn that this is irreversible.

### API 3: Stream Events (Main Event Loop)

Long-lived NDJSON stream. **Only one per token** — opening a new one closes the previous.

```
GET /api/stream/event
Authorization: Bearer lip_xxxxx
Accept: application/x-ndjson
```

**Response**: Continuous NDJSON stream. Empty lines every ~7 seconds as keep-alive.

**Event: `challenge`** — Incoming challenge from another player
```json
{
  "type": "challenge",
  "challenge": {
    "id": "VU0nyvsW",
    "url": "https://lichess.org/VU0nyvsW",
    "status": "created",
    "challenger": {
      "id": "bobby",
      "name": "Bobby",
      "title": null,
      "rating": 1635,
      "provisional": false,
      "online": true
    },
    "destUser": {
      "id": "mychessbot",
      "name": "MyChessBot",
      "title": "BOT",
      "rating": 1500
    },
    "variant": { "key": "standard", "name": "Standard", "short": "Std" },
    "rated": true,
    "speed": "blitz",
    "timeControl": {
      "type": "clock",
      "limit": 300,
      "increment": 3,
      "show": "5+3"
    },
    "color": "random",
    "perf": { "icon": ")", "name": "Blitz" }
  }
}
```

**Event: `challengeCanceled`** — Challenger withdrew
```json
{ "type": "challengeCanceled", "challenge": { "id": "VU0nyvsW", ... } }
```

**Event: `gameStart`** — A game has begun (after accepting challenge)
```json
{
  "type": "gameStart",
  "game": {
    "gameId": "rCRw1AuO",
    "fullId": "rCRw1AuOvonq",
    "color": "black",
    "fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    "hasMoved": false,
    "isMyTurn": false,
    "opponent": { "id": "bobby", "username": "Bobby", "rating": 1635 },
    "perf": "blitz",
    "rated": true,
    "speed": "blitz",
    "source": "friend",
    "variant": { "key": "standard", "name": "Standard" }
  }
}
```

**Event: `gameFinish`** — A game has ended
```json
{
  "type": "gameFinish",
  "game": { "gameId": "rCRw1AuO", ... }
}
```

### API 4: Accept Challenge

```
POST /api/challenge/{challengeId}/accept
Authorization: Bearer lip_xxxxx
```

**Response**: 200 OK `{"ok": true}`
**Errors**: 404 = challenge not found or expired

**Note**: Real-time challenges expire after ~20 seconds if not accepted.

### API 5: Decline Challenge

```
POST /api/challenge/{challengeId}/decline
Authorization: Bearer lip_xxxxx
Content-Type: application/x-www-form-urlencoded

reason=later
```

**Valid decline reasons**: `generic`, `later`, `tooFast`, `tooSlow`, `timeControl`, `rated`, `casual`, `standard`, `variant`, `noBot`, `onlyBot`

### API 6: Stream Game State

Per-game NDJSON stream. Open after receiving `gameStart` event.

```
GET /api/bot/game/stream/{gameId}
Authorization: Bearer lip_xxxxx
Accept: application/x-ndjson
```

**First event: `gameFull`** — Complete game state including all moves so far
```json
{
  "type": "gameFull",
  "id": "rCRw1AuO",
  "rated": true,
  "variant": { "key": "standard", "name": "Standard" },
  "speed": "blitz",
  "perf": { "name": "Blitz" },
  "createdAt": 1620029815106,
  "white": {
    "id": "bobby",
    "name": "Bobby",
    "title": null,
    "rating": 1635
  },
  "black": {
    "id": "mychessbot",
    "name": "MyChessBot",
    "title": "BOT",
    "rating": 1500
  },
  "initialFen": "startpos",
  "clock": {
    "initial": 300000,
    "increment": 3000
  },
  "state": {
    "type": "gameState",
    "moves": "e2e4 c7c5",
    "wtime": 298000,
    "btime": 296000,
    "winc": 3000,
    "binc": 3000,
    "status": "started"
  }
}
```

**Subsequent events: `gameState`** — After each move
```json
{
  "type": "gameState",
  "moves": "e2e4 c7c5 g1f3",
  "wtime": 295000,
  "btime": 296000,
  "winc": 3000,
  "binc": 3000,
  "status": "started"
}
```

**Game end `gameState`** — status changes from "started"
```json
{
  "type": "gameState",
  "moves": "e2e4 c7c5 g1f3 d7d6 ... ",
  "wtime": 15000,
  "btime": 0,
  "status": "mate",
  "winner": "white"
}
```

**Status values**: `created`, `started`, `aborted`, `mate`, `resign`, `stalemate`, `timeout`, `draw`, `outoftime`, `cheat`, `noStart`, `unknownFinish`, `variantEnd`

**Event: `chatLine`**
```json
{ "type": "chatLine", "room": "player", "username": "Bobby", "text": "good game!" }
```

**Event: `opponentGone`**
```json
{ "type": "opponentGone", "gone": true, "claimWinInSeconds": 30 }
```

**Clock fields**: `wtime`, `btime` in **milliseconds**. `winc`, `binc` = increment in ms.

**`moves` field**: Space-separated UCI strings. E.g., `"e2e4 c7c5 g1f3 b8c6"`. This is the **authoritative** move list — always trust this over local state.

### API 7: Make a Move

```
POST /api/bot/game/{gameId}/move/{move}
Authorization: Bearer lip_xxxxx
```

**Move format**: UCI notation
- Normal: `e2e4`
- Capture: `e4d5` (same format, just happens to capture)
- Castling: `e1g1` (kingside), `e1c1` (queenside) — king's actual destination
- En passant: `e5d6` (pawn moves diagonally, captured pawn removed automatically)
- Promotion: `e7e8q` (append lowercase piece: q/r/b/n)

**Optional query param**: `?offeringDraw=true` to simultaneously offer/accept a draw

**Response**: 200 OK `{"ok": true}`
**Errors**: 400 = illegal move or not your turn

### API 8: Resign Game

```
POST /api/bot/game/{gameId}/resign
Authorization: Bearer lip_xxxxx
```

**Response**: 200 OK

### API 9: Abort Game

Only possible before move 2.

```
POST /api/bot/game/{gameId}/abort
Authorization: Bearer lip_xxxxx
```

**Response**: 200 OK

### API 10: Claim Victory (opponent gone)

After receiving `opponentGone` with `claimWinInSeconds`, wait that duration then:

```
POST /api/bot/game/{gameId}/claim-victory
Authorization: Bearer lip_xxxxx
```

### API 11: Handle Draw

```
POST /api/bot/game/{gameId}/draw/yes   — accept draw offer
POST /api/bot/game/{gameId}/draw/no    — decline draw offer
Authorization: Bearer lip_xxxxx
```

### API 12: Handle Takeback

```
POST /api/bot/game/{gameId}/takeback/no   — decline (always, for bots)
Authorization: Bearer lip_xxxxx
```

### API 13: Send Chat

```
POST /api/bot/game/{gameId}/chat
Authorization: Bearer lip_xxxxx
Content-Type: application/x-www-form-urlencoded

room=player&text=Good game!
```

`room`: `player` (only visible to players) or `spectator` (visible to all)

### Rate Limits
- **One request at a time** — do not parallelize API calls
- **HTTP 429** = rate limited. Wait at least 1 minute (check `Retry-After` header)
- **One event stream per token** — opening a new one closes the previous
- **UltraBullet (1/4+0) forbidden** for bots. 0+1 and 1/2+0 are OK.

### NDJSON Format
- Content-Type: `application/x-ndjson`
- One JSON object per line, separated by `\n`
- Empty lines are keep-alive (sent every ~7 seconds)
- In Swift: use `URLSession.bytes(for:)` → `AsyncBytes`, read line-by-line, skip empty lines, decode each non-empty line as a complete JSON object

---

## App Entitlements (Already Present)

The app already has the required entitlements in `AI_Battle_Chess.entitlements`:
- `com.apple.security.app-sandbox` = true
- `com.apple.security.network.client` = true (outbound HTTP)
- `keychain-access-groups` = `$(AppIdentifierPrefix)$(CFBundleIdentifier)` (token storage)

**No entitlement changes needed.**

---

## Phase 1: Foundation Types (No connectivity)

### 1a. UCI conversion on `ChessMove` (ChessTypes.swift)

Add computed property and static factory:

```swift
extension ChessMove {
    /// UCI string: "e2e4", "e7e8q" for promotion
    var uci: String {
        var result = "\(from)\(to)"
        if let promo = promotionType {
            switch promo {
            case .queen: result += "q"
            case .rook: result += "r"
            case .bishop: result += "b"
            case .knight: result += "n"
            default: break
            }
        }
        return result
    }

    /// Parses UCI string and finds the matching legal move on the given board.
    /// Reuses existing PGNFormatter.parseAIMoveNotation + MoveValidator.findLegalMove.
    static func fromUCI(_ uci: String, on board: ChessBoard) -> ChessMove? {
        guard let parsed = PGNFormatter.parseAIMoveNotation(uci, on: board) else { return nil }
        return MoveValidator.findLegalMove(
            from: parsed.from, to: parsed.to, promotion: parsed.promotion, on: board
        )
    }
}
```

**Why this works**: `BoardPosition.description` already outputs "e2" format. `PGNFormatter.parseAIMoveNotation` already handles "e2e4" and "e7e8q" coordinate notation. `MoveValidator.findLegalMove` auto-detects castling, en passant, and promotion from the from/to squares.

### 1b. `GameMode.lichessBot` case (ChessTypes.swift)

```swift
case lichessBot = "Lichess Bot"
```

Backward compatible: existing JSON uses string raw values; old files lacking this value decode fine.

### 1c. `GameResult` additions (ChessTypes.swift)

```swift
case timeout(winner: PieceColor)    // Lichess "outoftime" / "timeout"
case abandoned(winner: PieceColor)  // Lichess opponent left, victory claimed
```

Update `displayText`, `pgnResult`, `pgnResultComment` for both.

### 1d. Lichess API types (new `Models/LichessTypes.swift`)

All Codable structs for API responses:

```swift
// -- Account --
struct LichessAccount: Codable, Sendable {
    let id: String
    let username: String
    let title: String?               // "BOT" if upgraded
    let perfs: [String: LichessPerf]?
    let count: LichessCount?
    let playing: String?             // URL of game in progress
}

struct LichessPerf: Codable, Sendable {
    let games: Int
    let rating: Int
    let rd: Int
    let prog: Int
    let prov: Bool?
}

struct LichessCount: Codable, Sendable {
    let all: Int
    let rated: Int
    let win: Int
    let loss: Int
    let draw: Int
    let playing: Int
}

// -- Event Stream --
struct LichessEventWrapper: Codable, Sendable {
    let type: String
    // Decoded dynamically based on type
}

struct LichessChallenge: Codable, Sendable, Identifiable {
    let id: String
    let url: String
    let status: String
    let challenger: LichessPlayer
    let destUser: LichessPlayer?
    let variant: LichessVariant
    let rated: Bool
    let speed: String                // "bullet", "blitz", "rapid", "classical", "correspondence"
    let timeControl: LichessTimeControl
    let color: String                // "white", "black", "random"
}

struct LichessPlayer: Codable, Sendable {
    let id: String
    let name: String
    let title: String?
    let rating: Int?
    let provisional: Bool?
}

struct LichessVariant: Codable, Sendable {
    let key: String                  // "standard", "chess960", etc.
    let name: String
}

struct LichessTimeControl: Codable, Sendable {
    let type: String                 // "clock", "correspondence", "unlimited"
    let limit: Int?                  // seconds
    let increment: Int?              // seconds
    let show: String?                // "5+3" display format
}

struct LichessGameInfo: Codable, Sendable {
    let gameId: String
    let fullId: String?
    let color: String                // "white" or "black"
    let fen: String
    let hasMoved: Bool
    let isMyTurn: Bool
    let opponent: LichessPlayer
    let perf: String
    let rated: Bool
    let speed: String
    let variant: LichessVariant
}

// -- Game Stream --
struct LichessGameFull: Codable, Sendable {
    let id: String
    let rated: Bool
    let variant: LichessVariant
    let speed: String
    let white: LichessPlayer
    let black: LichessPlayer
    let initialFen: String           // "startpos" or FEN string
    let clock: LichessClock?
    let state: LichessGameState
}

struct LichessClock: Codable, Sendable {
    let initial: Int                 // milliseconds
    let increment: Int               // milliseconds
}

struct LichessGameState: Codable, Sendable {
    let type: String?                // "gameState"
    let moves: String                // space-separated UCI, e.g. "e2e4 c7c5 g1f3"
    let wtime: Int?                  // white time remaining (ms)
    let btime: Int?                  // black time remaining (ms)
    let winc: Int?                   // white increment (ms)
    let binc: Int?                   // black increment (ms)
    let status: String               // "started", "mate", "resign", "timeout", etc.
    let winner: String?              // "white" or "black", only if game ended with a winner
}

struct LichessChatLine: Codable, Sendable {
    let username: String
    let text: String
    let room: String                 // "player" or "spectator"
}

struct LichessOpponentGone: Codable, Sendable {
    let gone: Bool
    let claimWinInSeconds: Int?
}

// -- Parsed event enums (not Codable, used internally) --
enum LichessEvent: Sendable {
    case challenge(LichessChallenge)
    case challengeCanceled(LichessChallenge)
    case challengeDeclined(LichessChallenge)
    case gameStart(LichessGameInfo)
    case gameFinish(LichessGameInfo)
}

enum LichessGameEvent: Sendable {
    case gameFull(LichessGameFull)
    case gameState(LichessGameState)
    case chatLine(LichessChatLine)
    case opponentGone(LichessOpponentGone)
}

// -- Stored with GameRecord --
struct LichessGameMetadata: Codable, Sendable, Equatable {
    let lichessGameId: String
    let lichessGameURL: String
    let rated: Bool
    let timeControl: String?         // "5+3", "10+0"
    let variant: String              // "standard", "chess960"
    let opponentUsername: String
    let opponentRating: Int?
    let ourColor: PieceColor
    let terminationReason: String?   // "mate", "resign", "timeout"
}
```

### 1e. Extend `GameRecord` (ChessTypes.swift)

Add optional field:
```swift
let lichessMetadata: LichessGameMetadata?  // nil for local games
```

Update both `init(...)` (add parameter with default `nil`) and `init(from decoder:)` (use `decodeIfPresent`). Backward compatible — existing JSON files without this field decode with `nil`.

---

## Phase 2: GameEngine Refactoring

**RISK: HIGH** — Most critical code path. Must preserve exact behavior for local games.

### 2a. Extract `applyMoveToBoard` from `applyMove`

The current `private func applyMove(_ move: ChessMove)` at `GameEngine.swift:400` does everything in one method. Split into:

**`applyMoveToBoard(_ move:, recordTiming: Bool = true) -> ChessMove`** — Pure board state update:
1. Clear selection (`selectedSquare = nil`, `legalMovesForSelected = []`)
2. Annotate check/checkmate on the move
3. Record timing (if `recordTiming` is true — false for Lichess moves where clock comes from server)
4. Store board state snapshot in `boardStates`
5. Complete any in-flight animation
6. Set up new animation
7. Apply move to board (`board = newBoard`)
8. Append to `moveHistory`, set `lastMove`
9. Update `positionCounts`
10. Cache SAN string in `moveSANCache`
11. Update `statistics`
12. Return annotated move

**`applyMoveLocal(_ move: ChessMove)`** — Full local pipeline:
```swift
private func applyMoveLocal(_ move: ChessMove) {
    let annotated = applyMoveToBoard(move)
    let duration = animationDuration(for: annotated)
    startMoveAnimation(moveID: annotated.id, duration: duration)

    if let result = MoveValidator.detectGameResult(on: board, positionCounts: positionCounts) {
        endGame(result: result)
        return
    }
    statusMessage = "\(board.activeColor.displayName)'s turn"
    triggerAIMoveIfNeeded()
}
```

**`applyLichessMove(_ move: ChessMove)`** — Lichess move (from opponent or confirmed ours):
```swift
func applyLichessMove(_ move: ChessMove) {
    let annotated = applyMoveToBoard(move, recordTiming: false)
    let duration = animationDuration(for: annotated)
    startMoveAnimation(moveID: annotated.id, duration: duration)

    statusMessage = "\(board.activeColor.displayName)'s turn"
    // Game end is determined by Lichess stream, not local detection
    // AI trigger is handled by LichessGameController
}
```

Then update all existing callers of `applyMove` to call `applyMoveLocal` instead.

### 2b. Extract `endGame(result:)` helper

Consolidate game-ending logic currently duplicated in `applyMove` and elsewhere:
```swift
func endGame(result: GameResult) {
    gameResult = result
    isGameActive = false
    statusMessage = result.displayText
    finalizeCurrentGame()
}
```

Needs to be non-private so `LichessGameController` can call it.

### 2c. Add `startLichessGame(ourColor:aiConfig:opponentName:)`

```swift
func startLichessGame(ourColor: PieceColor, aiConfig: PlayerConfig, opponentName: String, opponentRating: Int?) {
    // Reset all state (similar to startNewGame)
    board = ChessBoard()
    moveHistory = []
    boardStates = []
    gameResult = nil
    positionCounts = [:]
    moveSANCache = []
    statistics = GameStatistics()
    currentGameID = UUID()
    gameFinalized = false

    gameMode = .lichessBot
    isGameActive = true

    let botPlayer = aiConfig
    var remotePlayer = PlayerConfig(name: opponentName, isAI: false, color: ourColor.opposite)
    remotePlayer.humanPlayerID = nil  // remote player has no local profile

    if ourColor == .white {
        whitePlayer = botPlayer
        blackPlayer = remotePlayer
    } else {
        whitePlayer = remotePlayer
        blackPlayer = botPlayer
    }

    statistics.gameStartTime = Date()
    statistics.turnStartTime = Date()
    positionCounts[board.positionKey, default: 0] += 1
}
```

### 2d. Add `triggerLichessAIMoveIfNeeded()`

Called by `LichessGameController` when it's our bot's turn:

```swift
func triggerLichessAIMoveIfNeeded() {
    guard isGameActive, gameResult == nil else { return }
    guard gameMode == .lichessBot else { return }
    guard let controller = lichessController, controller.isPlayingOnLichess else { return }
    guard board.activeColor == controller.ourColor else { return }

    let player = board.activeColor == .white ? whitePlayer : blackPlayer
    guard player.isAI else { return }

    isAIThinking = true
    currentAIColor = board.activeColor

    // Uses same AI service call as triggerAIMoveIfNeeded, but on success:
    // 1. Call controller.submitMove(move) which sends to Lichess API
    // 2. On HTTP 200: call applyLichessMove(move) to update local state
    // 3. On failure: log error, wait for stream resync
}
```

### 2e. Guard `selectSquare` for Lichess mode

Add at the top of `selectSquare(_ position:)`:
```swift
guard gameMode != .lichessBot else { return }
```

### 2f. Add `lichessController` property

```swift
var lichessController: LichessGameController?
```

Set during app initialization.

### 2g. Update `finalizeCurrentGame`

Add `lichessMetadata` parameter to `GameRecord` construction:
```swift
let record = GameRecord(
    // ... existing params ...
    lichessMetadata: lichessController?.currentGameMetadata  // NEW
)
```

### Verification after Phase 2
Run PvP, PvAI, and AIvAI local games. PGN output and animation behavior must be identical to pre-refactor. This is the highest-risk phase.

---

## Phase 3: Lichess API Client

### 3a. `LichessTokenManager` (new `Services/LichessTokenManager.swift`)

Keychain wrapper. Service name: `"com.drew.ai-battle-chess.lichess"`.

```swift
final class LichessTokenManager: Sendable {
    static let shared = LichessTokenManager()
    private let service = "com.drew.ai-battle-chess.lichess"
    private let account = "lichess-bot-token"

    func store(token: String) throws      // SecItemAdd / SecItemUpdate
    func retrieve() -> String?            // SecItemCopyMatching
    func delete() throws                  // SecItemDelete
}
```

Uses the existing `keychain-access-groups` entitlement.

### 3b. `LichessAPI` (new `Services/LichessAPI.swift`)

Stateless HTTP client. All methods require token.

```swift
@MainActor
final class LichessAPI {
    private let baseURL = "https://lichess.org"
    private let session: URLSession
    private var token: String

    init(token: String) {
        self.token = token
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60  // for streams, keep alive
        self.session = URLSession(configuration: config)
    }

    // -- Account --
    func getAccount() async throws -> LichessAccount
    func upgradeToBot() async throws

    // -- Streams --
    func streamEvents() -> AsyncThrowingStream<LichessEvent, Error>
    func streamGame(gameId: String) -> AsyncThrowingStream<LichessGameEvent, Error>

    // -- Challenges --
    func acceptChallenge(id: String) async throws
    func declineChallenge(id: String, reason: String?) async throws

    // -- Game Actions --
    func makeMove(gameId: String, uciMove: String) async throws
    func resignGame(gameId: String) async throws
    func abortGame(gameId: String) async throws
    func claimVictory(gameId: String) async throws
    func handleDraw(gameId: String, accept: Bool) async throws
    func handleTakeback(gameId: String, accept: Bool) async throws
    func sendChat(gameId: String, room: String, text: String) async throws
}
```

**NDJSON streaming implementation**:
```swift
func streamEvents() -> AsyncThrowingStream<LichessEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            var request = URLRequest(url: URL(string: "\(baseURL)/api/stream/event")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")

            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw LichessError.httpError(/* status code */)
            }

            for try await line in bytes.lines {
                guard !line.isEmpty else { continue }  // skip keep-alive
                let data = Data(line.utf8)
                let event = try LichessStreamParser.parseEvent(data)
                continuation.yield(event)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
```

### 3c. `LichessStreamParser` (new `Services/LichessStreamParser.swift`)

Decodes a single NDJSON line into typed events:

```swift
enum LichessStreamParser {
    static func parseEvent(_ data: Data) throws -> LichessEvent {
        let wrapper = try JSONDecoder().decode(LichessEventWrapper.self, from: data)
        switch wrapper.type {
        case "challenge":
            let obj = try JSONDecoder().decode(ChallengeWrapper.self, from: data)
            return .challenge(obj.challenge)
        case "challengeCanceled":
            let obj = try JSONDecoder().decode(ChallengeWrapper.self, from: data)
            return .challengeCanceled(obj.challenge)
        case "gameStart":
            let obj = try JSONDecoder().decode(GameStartWrapper.self, from: data)
            return .gameStart(obj.game)
        case "gameFinish":
            let obj = try JSONDecoder().decode(GameFinishWrapper.self, from: data)
            return .gameFinish(obj.game)
        default:
            throw LichessError.unknownEventType(wrapper.type)
        }
    }

    static func parseGameEvent(_ data: Data) throws -> LichessGameEvent {
        // Similar dispatch on "type" field for gameFull, gameState, chatLine, opponentGone
    }
}
```

---

## Phase 4: Lichess Game Controller

### `LichessGameController` (new `ViewModels/LichessGameController.swift`)

`@Observable @MainActor` — The orchestrator bridging Lichess streams and GameEngine.

```swift
@Observable
@MainActor
final class LichessGameController {
    // -- Connection State --
    enum ConnectionState: Sendable, Equatable {
        case disconnected
        case connecting
        case connected(username: String)
        case error(String)
    }
    var connectionState: ConnectionState = .disconnected
    var botUsername: String?
    var botRatings: [String: Int] = [:]  // variant -> rating

    // -- Active Game --
    var activeGameId: String?
    var isPlayingOnLichess: Bool { activeGameId != nil }
    var ourColor: PieceColor?

    // -- Clock --
    var whiteTimeRemaining: TimeInterval?
    var blackTimeRemaining: TimeInterval?
    var whiteIncrement: TimeInterval?
    var blackIncrement: TimeInterval?
    var clockLastUpdated: Date?
    var activeClockColor: PieceColor?

    // -- Game Metadata (for saving to GameRecord) --
    var currentGameMetadata: LichessGameMetadata?

    // -- Challenge Preferences --
    var acceptBullet: Bool = false
    var acceptBlitz: Bool = true
    var acceptRapid: Bool = true
    var acceptClassical: Bool = true
    var acceptRated: Bool = true
    var acceptCasual: Bool = true

    // -- Dependencies --
    private var api: LichessAPI?
    private weak var engine: GameEngine?

    // -- Tasks --
    private var eventStreamTask: Task<Void, Never>?
    private var gameStreamTask: Task<Void, Never>?
    private var clockTimer: Timer?
    private var opponentGoneTimer: Task<Void, Never>?
}
```

### Key flows

**Flow 1: Go Online**
```
User taps "Go Online"
  → LichessTokenManager.retrieve() → get token
  → LichessAPI(token:) → store api
  → api.getAccount() → verify title == "BOT", store username + ratings
  → connectionState = .connected(username)
  → Start event stream loop (eventStreamTask)
```

**Flow 2: Event Stream Loop**
```
for event in api.streamEvents():
  case .challenge(let c):
    if activeGameId != nil → api.declineChallenge(id: c.id, reason: "later")
    else if matchesPreferences(c) → api.acceptChallenge(id: c.id)
    else → api.declineChallenge(id: c.id, reason: appropriateReason(c))

  case .gameStart(let g):
    activeGameId = g.gameId
    ourColor = PieceColor from g.color
    Start game stream loop (gameStreamTask)

  case .gameFinish(let g):
    Clean up game state
    activeGameId = nil

  case .challengeCanceled: no-op (already handled)
```

**Flow 3: Game Stream Loop**
```
for event in api.streamGame(gameId:):
  case .gameFull(let full):
    Determine our color from full.white/black matching botUsername
    engine.startLichessGame(ourColor:aiConfig:opponentName:opponentRating:)
    Build currentGameMetadata from full
    syncBoardFromMoves(full.state.moves)
    Update clock from full.state
    If it's our turn → engine.triggerLichessAIMoveIfNeeded()

  case .gameState(let state):
    Update clock from state.wtime/btime/winc/binc
    If state.status != "started" → handleGameEnd(state)
    Else → syncNewMoves(state.moves)
    If it's now our turn → engine.triggerLichessAIMoveIfNeeded()

  case .opponentGone(let og):
    If og.gone && og.claimWinInSeconds != nil → start timer, then api.claimVictory()

  case .chatLine: ignore for v1
```

**Flow 4: Move Submission (our bot's move)**
```
engine.triggerLichessAIMoveIfNeeded()
  → AI service computes move (same as local AI)
  → On success: controller.submitMove(move)
    → api.makeMove(gameId: activeGameId, uciMove: move.uci)
    → On HTTP 200: engine.applyLichessMove(move)
    → On HTTP 400: log error, wait for stream to resync
```

**Flow 5: Sync Moves from Stream**
```
func syncNewMoves(_ movesString: String) {
    let uciMoves = movesString.isEmpty ? [] : movesString.split(separator: " ").map(String.init)
    let localCount = engine.moveHistory.count

    // Only apply moves we haven't seen yet
    guard uciMoves.count > localCount else { return }

    for i in localCount..<uciMoves.count {
        guard let move = ChessMove.fromUCI(uciMoves[i], on: engine.board) else {
            // Desync — should not happen. Log error.
            continue
        }
        engine.applyLichessMove(move)
    }
}
```

**Flow 6: Clock Management**
```
func updateClock(from state: LichessGameState) {
    whiteTimeRemaining = state.wtime.map { TimeInterval($0) / 1000.0 }
    blackTimeRemaining = state.btime.map { TimeInterval($0) / 1000.0 }
    whiteIncrement = state.winc.map { TimeInterval($0) / 1000.0 }
    blackIncrement = state.binc.map { TimeInterval($0) / 1000.0 }
    clockLastUpdated = Date()
    activeClockColor = engine.board.activeColor
    startClockCountdown()
}

func startClockCountdown() {
    clockTimer?.invalidate()
    clockTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
        // Decrement active player's time by elapsed since last tick
        // Purely cosmetic — server values are authoritative
    }
}
```

**Flow 7: Game End**
```
func handleGameEnd(_ state: LichessGameState) {
    clockTimer?.invalidate()
    gameStreamTask?.cancel()

    let result: GameResult = switch state.status {
    case "mate":      .checkmate(winner: colorFromString(state.winner))
    case "resign":    .resignation(winner: colorFromString(state.winner))
    case "timeout", "outoftime": .timeout(winner: colorFromString(state.winner))
    case "stalemate": .stalemate
    case "draw":      .drawByAgreement
    case "aborted":   nil  // don't save aborted games
    default:          nil
    }

    // Update metadata termination reason
    currentGameMetadata?.terminationReason = state.status

    if let result {
        engine.endGame(result: result)
    }

    activeGameId = nil
}
```

**Flow 8: Go Offline**
```
User taps "Go Offline"
  → If activeGameId != nil: api.resignGame() (or warn user)
  → eventStreamTask?.cancel()
  → gameStreamTask?.cancel()
  ��� clockTimer?.invalidate()
  → connectionState = .disconnected
```

---

## Phase 5: UI

### 5a. `LichessSettingsView` (new `Views/LichessSettingsView.swift`)

Sheet presented from GameSetupView:
- Token entry (`SecureField`) with show/hide toggle
- "Test Connection" button → calls `api.getAccount()`, shows username + "BOT" title
- If account exists but `title != "BOT"`: show "Upgrade to Bot" button with irreversibility warning
- "Clear Token" button → `LichessTokenManager.delete()`
- Challenge preferences section:
  - Time controls: checkboxes for Bullet / Blitz / Rapid / Classical
  - Rated/Casual toggles
- Connection status indicator

### 5b. `ChessClockView` (new `Views/ChessClockView.swift`)

Compact countdown display embedded in `PlayerPanelView`:
- Format: `mm:ss` (or `h:mm:ss` for classical)
- Shows tenths of seconds when under 10 seconds
- Red text when under 30 seconds
- Bold when it's this player's turn (clock is ticking)
- Shows increment badge (e.g., "+3") if increment > 0

### 5c. Lichess mode in `GameSetupView` (modify `Views/GameSetupView.swift`)

Add a mode selector at the top of the setup sheet: **Local Game** | **Lichess Bot**

When "Lichess Bot" is selected:
- AI model picker (same as existing, for the bot's brain)
- "Configure Lichess" button → presents `LichessSettingsView`
- If token is configured:
  - "Go Online" / "Go Offline" button
  - When online: green dot + bot username, "Waiting for challenges..."
  - Challenge preferences summary
- When a game starts from Lichess:
  - Setup sheet dismisses automatically
  - Game appears on the board
- When game ends:
  - Return to setup sheet in "waiting" state (if auto-start is off)
  - Or auto-wait for next challenge

### 5d. `PlayerPanelView` updates (modify `Views/PlayerPanelView.swift`)

When `engine.gameMode == .lichessBot`:
- Show `ChessClockView` below player header
- For remote player: show "[Lichess]" badge, opponent rating, username
- For our bot: show "[Bot]" badge, bot rating for this time control
- Hide AI activity section for the remote player (they have none)

### 5e. `ContentView` status bar (modify `Views/ContentView.swift`)

- New icon for `.lichessBot` mode: `Image(systemName: "globe")`
- When Lichess is connected: small green/yellow/red dot + "Lichess" label
- Turn indicator shows opponent username when it's their turn

### 5f. History view enhancements (modify `Views/MoveHistoryView.swift`, history browsing)

- Lichess games show a globe icon or "[Lichess]" badge in the game list
- Show time control (e.g., "5+3") and rated/casual badge
- Show opponent rating
- "Open on Lichess" button → opens `lichessMetadata.lichessGameURL` in browser
- PGN headers for Lichess games include `[Site "https://lichess.org/{gameId}"]`

---

## Phase 6: Polish & Edge Cases

- **Takebacks**: Auto-decline all takeback requests (`api.handleTakeback(accept: false)`)
- **Draw offers**: Auto-decline for v1 (`api.handleDraw(accept: false)`)
- **`opponentGone`**: Start countdown timer, then `api.claimVictory()` after `claimWinInSeconds`
- **Reconnection**: If event stream drops (network error), reconnect with exponential backoff (1s → 2s → 4s → ... → 30s cap). Do NOT auto-reconnect on app relaunch — user must click "Go Online" again.
- **Mid-game reconnect**: If we reconnect and there's a game in progress, the `gameFull` event includes all moves so far. Replay them to rebuild local state.
- **One event stream per token**: Disconnect old stream before starting a new one (handled by Lichess server automatically, but clean up locally too).
- **PGN headers for Lichess games**: Set `[Site "https://lichess.org/{gameId}"]`, `[Event "Lichess Rated Blitz"]` etc.
- **Games already in progress on connect**: The `playing` field in `GET /api/account` gives the URL of a game in progress. Use this to detect and reconnect.
- **Rate limit handling**: On HTTP 429, read `Retry-After` header and wait. Surface error in UI.

---

## Files Modified

| File | Changes |
|------|---------|
| `Models/ChessTypes.swift` | `GameMode.lichessBot`, `GameResult.timeout/abandoned`, `ChessMove.uci`/`fromUCI`, `GameRecord.lichessMetadata` |
| `ViewModels/GameEngine.swift` | Extract `applyMoveToBoard`, add `applyLichessMove`, `startLichessGame`, `triggerLichessAIMoveIfNeeded`, `endGame` (non-private), guard `selectSquare`, add `lichessController` property, update `finalizeCurrentGame` |
| `Views/GameSetupView.swift` | Add Local/Lichess mode selector, Lichess connection section, challenge preferences |
| `Views/PlayerPanelView.swift` | Chess clock display, Lichess badges, hide AI activity for remote player |
| `Views/ContentView.swift` | Status bar Lichess indicator, `.lichessBot` mode icon |
| `Views/MoveHistoryView.swift` | Lichess game badges, "Open on Lichess" link |
| `AI_Battle_Chess.entitlements` | No changes needed (already has network.client + keychain) |

## New Files

| File | Purpose |
|------|---------|
| `Models/LichessTypes.swift` | All Codable API types + `LichessGameMetadata` |
| `Services/LichessAPI.swift` | HTTP client, NDJSON streaming, all API methods |
| `Services/LichessStreamParser.swift` | NDJSON line → typed event decoder |
| `Services/LichessTokenManager.swift` | Keychain CRUD for API token |
| `ViewModels/LichessGameController.swift` | Bot lifecycle, event/game stream orchestration, clock |
| `Views/LichessSettingsView.swift` | Token config, connection test, challenge preferences |
| `Views/ChessClockView.swift` | Countdown timer display |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| GameEngine refactoring breaks local games | Critical | Structural-only changes. Verify PvP/PvAI/AIvAI produce identical PGN + animation before proceeding. |
| NDJSON streaming reliability | High | Skip empty keep-alive lines. Reconnect with exponential backoff. 15s no-data timeout triggers reconnect. |
| Move sync race conditions | High | Always trust Lichess `moves` string as authoritative. Diff against local count. Never assume in-sync. |
| Token security | Medium | Keychain only, never UserDefaults or files. Entitlements already configured. |
| Clock drift | Low | Server clock is authoritative. Local timer is cosmetic only. Snap to server values on every `gameState`. |
| Rate limits | Medium | Respect HTTP 429 + `Retry-After`. Sequential requests only. Surface errors in UI. |

## Verification

1. **After Phase 2**: Run PvP, PvAI, AIvAI local games. PGN output and animation must be identical to pre-refactor.
2. **After Phase 3**: Manual test with real Lichess bot token — event stream connects, NDJSON parses, account info displays.
3. **After Phase 4**: Play a full game against the bot on Lichess. Moves sync, clock updates, game ends correctly, record saved with metadata.
4. **After Phase 5**: Clock display, badges, history view for Lichess games. Local games unaffected.
5. **End-to-end**: Multiple Lichess games with different time controls. Test promotions, castling, en passant over Lichess. Verify all games appear in history alongside local games with correct metadata.
