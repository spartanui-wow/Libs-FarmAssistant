# CLAUDE.md - Lib's Farm Assistant

This file provides guidance to Claude Code when working with the Libs-FarmAssistant addon.

## Project Overview

**Lib's Farm Assistant** is a session-based farming tracker for World of Warcraft. It tracks loot, money, currency, and reputation gains with per-hour rate calculations. Session data persists through `/rl` (ReloadUI) via character-scoped SavedVariables. Registers as a LibDataBroker data source.

## Architecture

```
Libs-FarmAssistant/
├── Libs-FarmAssistant.toc       # Interface 120000, SavedVariables: LibsFarmAssistantDB
├── Libs-FarmAssistant.lua       # AceAddon main + LibAT Logger
├── Core/
│   ├── Database.lua             # AceDB with char (session data) + profile (settings)
│   ├── SessionManager.lua       # Session lifecycle: start, pause, resume, reset, duration
│   ├── LootTracker.lua          # CHAT_MSG_LOOT — item link extraction, quality filter
│   ├── MoneyTracker.lua         # PLAYER_MONEY — GetMoney() delta tracking
│   ├── CurrencyTracker.lua      # CHAT_MSG_CURRENCY — currency link extraction
│   └── ReputationTracker.lua    # CHAT_MSG_COMBAT_FACTION_CHANGE — faction/amount parsing
├── UI/
│   ├── DataBroker.lua           # LDB data source, display format
│   ├── Tooltip.lua              # Items (sorted by count), money, currency, rep — all with /hr rates
│   ├── Options.lua              # AceConfig: tracking toggles, quality filter, display format
│   └── MinimapButton.lua        # LibDBIcon registration
├── libs/
│   ├── Ace3/                    # Full Ace3 framework
│   ├── LibDataBroker-1.1/       # LDB protocol
│   └── LibDBIcon-1.0/           # Minimap button
├── Logo-Icon.tga                # Addon icon
└── .github/                     # CI workflows
```

## Key Design Decisions

### Session Persistence (char-scoped SavedVariables)
- Session data stored in `dbobj.char.session` — per-character, survives `/rl`
- Includes: `items`, `money`, `currencies`, `reputation`, `startTime`, `pausedDuration`, `active`
- Profile settings (tracking toggles, quality filter, display format) are separate

### Loot Tracking (Language-Independent)
- Extracts item links directly from CHAT_MSG_LOOT text via pattern: `|c%x+|Hitem:[%d:]+|h%[.-%]|h|r`
- Extracts quantity via `x(%d+)` pattern (defaults to 1)
- Gets item info (name, quality, icon) from `C_Item.GetItemInfo(itemLink)`
- Quality filter: configurable minimum quality (0=Poor through 4=Epic)
- Falls back gracefully if item info isn't cached yet

### Money Tracking (Delta-Based)
- Uses `GetMoney()` snapshots instead of parsing CHAT_MSG_MONEY (language-independent)
- Only tracks gains (positive deltas), ignores spending
- Snapshot updated on every PLAYER_MONEY event
- Snapshot reset on session reset and during paused state

### Session Pause/Resume
- `ToggleSession()` pauses/resumes tracking
- Paused time is tracked via `pausedDuration` accumulator
- `GetSessionDuration()` subtracts paused time from total elapsed
- All event handlers check `IsSessionActive()` before recording

### Rate Calculations
- All rates use `GetSessionHours()` (active session time in hours)
- Tooltip shows per-hour rates for every tracked item/currency/faction
- Display updates every 60 seconds via AceTimer

## Data Structures

### Session Items
```lua
session.items[itemID_string] = {
    name = 'Linen Cloth',
    link = '|cffffffff|Hitem:2589:...|h[Linen Cloth]|h|r',
    icon = texturePath,
    quality = 1,
    count = 42,
}
```

### Session Currencies
```lua
session.currencies['Dragon Isles Supplies'] = {
    name = 'Dragon Isles Supplies',
    icon = fileID,
    count = 15,
}
```

### Session Reputation
```lua
session.reputation['Valdrakken Accord'] = 250  -- total rep gained
```

## Display Formats

Configurable in options: `items` | `money` | `combined`

## Click Behaviors

| Button | Action |
|--------|--------|
| Left Click | Toggle pause/resume |
| Shift+Left | Open Options |
| Right Click | Open Options |
| Middle Click | Reset session |

## Slash Commands

- `/farmassist` or `/libsfa` — Open options
- `/farmassist reset` — Reset session
- `/farmassist pause` — Toggle pause
- `/farmassist summary` — Print session summary to chat

## Reference Addon

- `C:\Users\jerem\OneDrive\WoW\Examples\DataBar\FarmCount` — Chat-based farming tracker (inspiration for event handling)

## Testing

1. Kill mobs → verify items appear in tooltip with counts and rates
2. Loot gold → verify money tracking (compare with bags)
3. Earn currency → verify currency section appears
4. Gain reputation → verify rep section appears
5. Test quality filter: Set to Uncommon, verify gray/white items ignored
6. Test pause/resume: Pause, loot items, verify not tracked
7. Test `/rl`: Reload UI, verify session data persists
8. Test reset: Verify all data cleared, timer restarted
