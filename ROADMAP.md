# AI Battle Chess — Roadmap

## Planned

### Load Game from FEN
Allow pasting a FEN string to create a new game starting from that board state. Similar to the existing "Load PGN" flow but for arbitrary positions. Requires a FEN parser on `ChessBoard` (inverse of the existing `fen` computed property) and UI in `GameSetupView` or the existing Load PGN sheet.

### Fix Move Animation Interruption
When the next move arrives before the current piece animation finishes, the animated piece snaps back to its source square before jumping to the final position. The animation cancellation logic (`animationTask?.cancel()` with `disablesAnimations` transaction) should instantly commit the in-flight piece to its destination before starting the new animation.

### Resume Game on Relaunch
If the app crashes, is closed, or is otherwise terminated during an active game, there is currently no way to resume that game on next launch. Since we already save move-by-move board state, this should be straightforward — persist the active game's state (player configs, move history, board states) and offer to resume on next launch.

### Persist AI Activity Logs in Game History
When viewing historical games, the AI Activity section shows "No moves yet" because the full prompt/response/token data is only held in memory during the live game. Make `AIActivityLog` and its nested types (`AITurnAttempt`, `TokenUsage`, `AIGuidedGenerationResult`) `Codable`, add an `aiActivityHistory` field to `GameRecord`, save it in `finalizeCurrentGame()`, and restore it in `loadGameRecord()`. The `AIConfigSnapshot` pattern is a good reference for the approach.

### Copy PGN/FEN Should Match Displayed State
Copy FEN already respects the currently displayed position (via `displayBoard`). However, Copy PGN always exports the live game's full move history — it does not reflect mid-game navigation (`viewingMoveIndex`) or past game viewing (`viewingGameIndex`). PGN export should truncate moves to the viewed position when navigating history, and export the past game's data when viewing a past game.

## Completed

### FEN Export (2026-04-02)
Added `ChessBoard.fen` computed property and "Copy FEN" button in the move history panel. FEN respects the currently viewed board position when navigating history.

### AI Model Details in PGN Headers (2026-04-02)
PGN export now includes `[WhiteModel]` and `[BlackModel]` headers with provider, model ID, temperature, max tokens, and thinking budget. App version includes build number.

### Apple Intelligence as First-Class Provider (2026-03-31)
Moved Apple Intelligence configuration from inline game setup controls to the Provider Settings screen, treating it like any other provider. Configs support sampling mode, temperature, and max token settings.

### Safety Guardrail Handling (2026-04-01)
Apple Intelligence guardrail violations now fail fast (3 retries) and fall back to a random legal move instead of retrying 100 times. Sessions use permissive guardrails for chess content.

### AI Error Surfacing (2026-04-01)
AI errors during retries are now shown in the UI immediately via a red capsule overlay, rather than being silently logged until all retries are exhausted.

### Game Abandon Fix (2026-04-01)
"Abandon Game" now properly cancels in-flight AI tasks before showing the setup sheet.
