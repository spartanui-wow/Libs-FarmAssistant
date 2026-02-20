# CLAUDE.md - Lib's Farm Assistant

This file provides guidance to Claude Code when working with the Libs-FarmAssistant addon.

## Project Overview

**Lib's Farm Assistant** is a session-based farming assistant for World of Warcraft. It provides **active auto-looting** with a priority-based filter system (quality, price, whitelist/blacklist, quest items, fishing, BoP, alerts) plus **comprehensive tracking** of loot, money, currency, reputation, and honor gains with per-hour rate calculations, session history with personal bests, trend comparison arrows, goal/target tracking with progress bars, vendor value estimation, and session time notifications. Session data persists through `/rl` (ReloadUI) via character-scoped SavedVariables. Registers as a LibDataBroker data source.

## Architecture

```
Libs-FarmAssistant/
├── Libs-FarmAssistant.toc       # Interface 120000, SavedVariables: LibsFarmAssistantDB
├── Libs-FarmAssistant.lua       # AceAddon main + LibAT Logger
├── Core/
│   ├── Database.lua             # AceDB with char (session+history) + profile (settings+goals+autoLoot)
│   ├── SessionManager.lua       # Session lifecycle, FormatNumber/Money/Duration, GetTotalVendorValue
│   ├── LootTracker.lua          # CHAT_MSG_LOOT — passive item tracking with dedup for auto-looted items
│   ├── MoneyTracker.lua         # PLAYER_MONEY — GetMoney() delta tracking
│   ├── CurrencyTracker.lua      # CHAT_MSG_CURRENCY — currency link extraction
│   ├── ReputationTracker.lua    # CHAT_MSG_COMBAT_FACTION_CHANGE — faction/amount parsing
│   ├── HonorTracker.lua         # CHAT_MSG_COMBAT_HONOR_GAIN — PvP honor tracking
│   ├── SessionHistory.lua       # Save sessions to history, personal bests, averages
│   ├── Notifications.lua        # Periodic session reminder chat messages
│   ├── GoalTracker.lua          # Goal progress, completion, ETA, progress bars
│   └── Looting/                 # Active auto-looting system
│       ├── LootingModule.lua    # Base module prototype, registration, sorted cache
│       ├── LootingCore.lua      # LOOT_READY/LOOT_OPENED handler, module iteration, LootSlot()
│       └── Modules/             # 14 priority-based filter modules
│           ├── AlertList.lua    # Priority 1    — Sound + raid warning for special items
│           ├── Locked.lua       # Priority 100  — Skip locked items
│           ├── WatchedItems.lua # Priority 150  — Priority-loot watched items
│           ├── Money.lua        # Priority 200  — Auto-loot gold/silver/copper
│           ├── Currency.lua     # Priority 300  — Auto-loot currencies
│           ├── WhiteList.lua    # Priority 400  — Always loot whitelisted items
│           ├── BlackList.lua    # Priority 500  — Never loot blacklisted items
│           ├── IgnoreBOP.lua    # Priority 600  — Skip Bind on Pickup items
│           ├── Rarity.lua       # Priority 700  — Quality-based filtering (per-tier)
│           ├── Quest.lua        # Priority 800  — Auto-loot quest items
│           ├── Token.lua        # Priority 900  — Loot items with no vendor price
│           ├── Price.lua        # Priority 1000 — Minimum vendor price threshold
│           ├── Fishing.lua      # Priority 1200 — Loot everything while fishing
│           └── All.lua          # Priority 99999 — Fallback: loot everything
├── UI/
│   ├── DataBroker.lua           # LDB data source, display format, notification/goal checks
│   ├── Tooltip.lua              # Full tooltip: items, money, currency, rep, honor, goals, trends
│   ├── Options.lua              # AceConfig: tracking, auto-looting, notifications, display, goals
│   ├── MinimapButton.lua        # LibDBIcon registration
│   ├── ItemDragDrop.lua         # Drag items to minimap: default=watch, Shift=whitelist, Ctrl=blacklist, Alt=alert
│   └── PopupWindow.lua          # Standalone dashboard window
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
- Includes: `items`, `money`, `currencies`, `reputation`, `honor`, `startTime`, `pausedDuration`, `active`
- Session history stored in `dbobj.char.history` — array of up to 20 snapshots
- Personal best rates stored in `dbobj.char.bestRates`
- Profile settings (tracking toggles, quality filter, display format, goals, notifications) are separate

### Auto-Looting System (Active Looting)
- Priority-based module system: 14 modules checked in priority order (lowest number first)
- Hooks `LOOT_READY` (fast) or `LOOT_OPENED` (configurable) to call `LootSlot()` automatically
- Each module's `CanLoot(slotData)` returns `{ loot, reason, forceBreak }` or nil
- First module returning `loot=true` wins → item is looted and recorded
- First module returning `forceBreak=true` stops processing (blacklist, locked)
- AlertList fires alerts but doesn't affect loot decision (no loot/forceBreak)
- Auto-looted items are dedup'd against passive CHAT_MSG_LOOT tracker (2-second window)
- Settings stored in `profile.autoLoot` (general) and `profile.lootModules` (per-module)
- Three separate item lists: Watched (char-scoped), Whitelist/Blacklist/AlertList (profile-scoped)
- Drag-and-drop to minimap: default=watched, Shift=whitelist, Ctrl=blacklist, Alt=alert

### Loot Tracking (Language-Independent, Passive Fallback)
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
    sellPrice = 25,  -- per-unit vendor sell price in copper
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

### Session Honor
```lua
session.honor = 1500  -- total honor gained
```

### Session History Snapshot
```lua
char.history[1] = {
    timestamp = 1700000000,  -- time() epoch
    duration = 3600,         -- seconds of active farming
    totalItems = 234,
    items = { ['2589'] = { name='Linen Cloth', count=100, quality=1, sellPrice=25 } },
    money = 50000,           -- copper
    currencies = { ['Dragon Isles Supplies'] = 15 },
    reputation = { ['Valdrakken Accord'] = 250 },
    honor = 500,
    totalVendorValue = 2500, -- copper
    itemsPerHour = 234,      -- pre-computed rates
    goldPerHour = 50000,
    honorPerHour = 500,
}
```

### Goals
```lua
profile.goals[1] = {
    type = 'item',       -- 'item', 'money', 'honor', 'currency', 'reputation'
    targetValue = 1000,  -- target count (copper for money goals)
    targetItemID = 2589, -- for item goals
    targetName = 'Linen Cloth',
    active = true,
}
```

## Display Formats

Configurable in options: `items` | `money` | `combined`

## Click Behaviors

| Button | Action |
|--------|--------|
| Left Click | Open Dashboard |
| Right Click | Pause/Resume session |
| Shift+Click (either) | Reset session (with confirmation) |
| Scroll Wheel | Cycle display format (items/money/combined) |

## Slash Commands

- `/farmassist` or `/libsfa` — Open options
- `/farmassist reset` — Reset session
- `/farmassist pause` — Toggle pause
- `/farmassist summary` — Print session summary to chat

## Reference Addons

- `C:\Users\jerem\OneDrive\WoW\Examples\DataBar\FarmCount` — Chat-based farming tracker (inspiration for event handling)
- `C:\Users\jerem\OneDrive\WoW\Examples\AutoLooter` — Selective auto-looting addon (inspiration for priority-based module system)

## Testing

### Core Tracking
1. Kill mobs → verify items appear in tooltip with counts and rates
2. Loot gold → verify money tracking (compare with bags)
3. Earn currency → verify currency section appears
4. Gain reputation → verify rep section appears
5. Enter BG, earn honor → verify honor section appears with /hr rate
6. Test quality filter: Set to Uncommon, verify gray/white items ignored
7. Test pause/resume: Pause, loot items, verify not tracked
8. Test `/rl`: Reload UI, verify session data persists
9. Test reset: Verify all data cleared, timer restarted

### Number Formatting
10. Loot 1000+ items → verify tooltip shows "1,234" not "1234"
11. Earn 10000+ gold → verify gold shows "1,234g" not "1234g"

### Vendor Value
12. Loot items → verify "Est. Vendor Value" line under items list
13. Test /rl → verify sellPrice backfill works (ITEM_DATA_LOAD_RESULT)

### Session History
14. Farm >1 min, reset → verify "Session saved" log message
15. Farm again → check tooltip for "Personal Best" green indicator
16. Reset 3+ times → verify trend arrows (▲/▼) appear next to rates

### Notifications
17. Enable at 5-min frequency → verify chat reminder appears

### Goals
18. Add item goal (e.g., Item 2589, target 50) → farm, verify progress bar
19. Verify ETA updates as you loot
20. Verify sound + chat on completion
21. Test money/honor goals
22. Verify goals persist after /rl
23. Verify completed goals show checkmark, don't re-notify after /rl

### Auto-Looting
24. Enable auto-looting, kill mob → items looted automatically
25. Disable auto-looting → falls back to manual loot + passive tracking
26. Toggle fast loot → verify LOOT_READY vs LOOT_OPENED behavior
27. Enable close loot → verify window closes after looting
28. Enable only Uncommon+ quality → kill mob, verify grey/white items left on corpse
29. Add item to whitelist → verify always looted regardless of quality
30. Add item to blacklist → verify never looted
31. Accept quest, kill mob → verify quest items auto-looted
32. Enable Ignore BoP → verify BoP items left on corpse
33. Go fishing with fishing mode ON → verify all catches looted
34. Set minimum price to 1g → verify cheap items ignored
35. Add item to alert list → when it drops, verify sound + raid warning
36. Shift+drag item to minimap → verify added to whitelist
37. Ctrl+drag item to minimap → verify added to blacklist
38. Alt+drag item to minimap → verify added to alert list
39. Auto-loot + goal tracking → verify goal progress updates
40. Manual loot while auto-loot enabled → verify no double-counting
