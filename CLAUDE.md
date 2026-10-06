# CLAUDE.md - Lib's Farm Assistant

Guidance for working on Libs-FarmAssistant. Root rules in `C:\code\CLAUDE.md` and `.context/` apply.
Product truth (who it is for, principles) lives in `PRODUCT.md`.

## What it is

Tracks everything a player farms and ties it to where it came from: loot and its value, gold by
source, kills, drops per mob/node/fishing spot, rare drop hunts (attempts, luck), reputation,
currency, experience and honor. Every gain is kept for the session, today, the week (since the
weekly reset), the month and all time. It also has a priority-based auto-looter.

Runs on every client: Retail 12.x, WoW Forever, Mists, Titan, TBC Anniversary, Classic Era.
The window, tracker and tooltips need no other addon (Libs-DataBar and Libs-AddonTools are optional).

## Architecture

```
Libs-FarmAssistant.lua        AceAddon, slash /farm, throttled UpdateDisplay -> LIBSFA_UPDATE message
Core/
  Compat.lua                  Every client-specific API + secret-value guards (CanAccess, Readable),
                              FactionProgress (standard/friendship/renown/paragon in one shape),
                              Collectible (mount/pet/toy), FormatToPattern (GlobalStrings -> patterns),
                              RegisterEvent (skips events the client does not know)
  Format.lua                  Number, money, duration, clock, odds ("1 in 14"), percent, dates
  Ledger.lua                  The data model. Buckets, writes, window sums, rates, item sources, archive
  Database.lua                AceDB defaults and migration from the v1 layout (DATA_VERSION)
  Pricing.lua                 Item meta cache (name/quality/sell price/bind) + vendor/auction value
  SessionManager.lua          Session clock (active seconds, never timestamps), pause, new session,
                              start mode at login (login / first kill / manual), pause while away
                              or resting. session.pausedFor = 'away'|'resting'|'kill' marks a pause
                              that ends by itself; nil is the player's own pause and never resumes alone
  Sources.lua                 GUID -> source key, names, kill counting once per GUID
  LootTracker.lua             Loot window snapshot + LOOT_SLOT_CLEARED + CHAT_MSG_LOOT dedupe
  MoneyTracker.lua            GetMoney() deltas, categorized by which window is open
  CurrencyTracker.lua         CURRENCY_DISPLAY_UPDATE; honor (currency on Mists+, chat on older)
  ReputationTracker.lua       Monotonic faction totals diffed; chat as a hint; Gains(bucket) for UI
  ExperienceTracker.lua       UnitXP deltas across level-ups; time to level; experience per kill
                              for the current level only (char.levelXP, reset on level-up) and
                              kills to level with the rested pool spent first
  Lockouts.lua                Raid, dungeon and world boss saves per character (account-wide),
                              boss matching by name, per-character hunt counts, weekly summaries
  Hunts.lua                   Attempt counting, drop history, sources, bosses, luck math, shared hunts
  GoalTracker.lua             Session goals with ETA
  Notifications.lua, SmartSession.lua
  Looting/                    Auto-loot: priority modules; only decides what to take
UI/
  Theme.lua                   Tokens (colors, sizes, fonts) and primitives (Fill, Border, Rule, Text, Icon)
  Widgets.lua                 Button, IconButton (bar glyphs), Segmented, Chip, EditBox, Heading, Bar,
                              List (virtual rows), Table (columns, sort, select), tooltip helpers
  Components.lua              RepCard, HuntCard, StandingColor, RepPace, ItemRows
  Window.lua                  Main window shell: header clock + time range switch, nav, footer, pages
  QuickSettings.lua           Header panel: start tracking, pause while resting/away (same as General)
  Pages/                      Overview, Loot, Hunts, Sources, Progress, History (FarmPage interface)
  Tracker.lua                 Compact always-on panel
  DataBroker.lua, Tooltip.lua LDB object and its tooltip
  GameTooltips.lua            Optional lines on item and creature tooltips
  Options.lua                 AceConfig tabs: General, Tracking, Hunts and Goals, Display, Auto-Loot, Watched
Tests/                        Headless harness (not packaged)
```

## Data model

Every bucket (session, `char.days[YYYY-MM-DD]`, `char.months[YYYY-MM]`, `char.lifetime`) has:

```lua
{ time, kills, loots, xp, honor, spent,
  money = { loot, vendor, quest, mail, other },   -- copper by where it came from
  items = { [itemID] = quantity },
  currencies = { [currencyID] = amount },
  rep = { [factionID] = amount },
  sources = { [sourceKey] = { kills, loots, money, items = { [itemID] = qty }, drops = { [itemID] = loots containing it } } } }
```

- Source keys: `c:<npcID>` creature, `o:<objectID>` node/chest, `f:<zone>` fishing, `i` containers,
  `e:<encounterID>` boss encounter, `q` rewards and other.
- "1 in N" uses `drops` (loot events), never quantity. Tries = kills for creatures, opens otherwise.
- Weeks are summed from days (`Ledger:Window('week')`, cached by `Ledger.version`). Days older than
  62 days are pruned; months and lifetime keep totals.
- `global.itemMeta` / `global.sourceMeta` are account-wide name caches.
- `char.sessions` holds short summaries (last 100). `char.hunts[itemID string]` holds hunts.
- `global.characters[AceDB char key]` = { name, realm, class, level, scanned, lockouts, hunts }:
  each character's saves (`GetSavedInstanceInfo` / `GetSavedInstanceEncounterInfo` /
  `GetSavedWorldBossInfo`, rescanned on `UPDATE_INSTANCE_INFO`, asked for with `RequestRaidInfo`
  at login and a few seconds after each boss kill) and a snapshot of its hunt counts.
- `global.sharedHunts[itemID string]` = { sources, bosses, chance, mode }: hunts every character
  picks up at login (`Hunts:SyncShared`). Mounts, pets and toys are shared by default.

## Rules that keep counts honest

- A creature counts once per GUID, whichever signal arrives first: `PARTY_KILL` (exists on every
  client, payload can be secret on Retail), `PLAYER_TARGET_DIED` (Retail fallback), or looting the corpse.
  Skinning or re-opening a corpse never adds a kill or a loot.
- Items count only when the slot leaves the loot window (`LOOT_SLOT_CLEARED`). The same items then
  arriving in chat are consumed from an expectation table. Chat-only loot (personal loot, bonus
  rolls) is credited to the last kill within 20 seconds.
- Group-loot items at or above the roll threshold are left to the chat path (only the winner gets them).
- The auto-looter calls `LootTracker:Snapshot()` before `LootSlot()`; it never records items itself.
- Money: an open loot/merchant/mail/quest window outranks one that closed a moment ago.
- Everything checks `IsSessionActive()`; pausing stops the clock and the counting.
- Start mode applies on the first `PLAYER_ENTERING_WORLD` with `isReloadingUi` false; a reload keeps
  the state. Away/resting act only when the reason changes, so resuming by hand in town sticks.
  "First kill" resumes in `Sources:CountKill` before the kill is counted, so that kill is in the session.
- Experience per kill: kills (`LIBSFA_ATTEMPT` with a `c:` key), bar gains and `QUEST_TURNED_IN`
  rewards are gathered into a burst that closes after 1s of quiet (6s at most). The burst's
  experience minus quest rewards is split over max(kills, bar gains - quests); the rested bonus is
  the drop in `GetXPExhaustion()` across the burst. A burst that spans a level-up is not recorded.

## Lockouts

Bosses are matched by name, the only thing lockout lists and kill events share. A hunt's boss
names are: bosses linked by hand (`hunt.bosses`), its encounter sources (`e:`), and creature
sources whose name appears in some lockout or encounter (so ordinary mobs never count). A
character is "done" when a lockout that has not reset lists one of those bosses as killed. Each
hunt also keeps `weekKey`/`weekAttempts` (week = since the weekly reset).

## Messages

`LIBSFA_UPDATE` (throttled redraw), `LIBSFA_SESSION_STARTED`, `LIBSFA_SESSION_STATE`,
`LIBSFA_TIME_ADDED(seconds)`, `LIBSFA_ATTEMPT(sourceKey)`, `LIBSFA_ITEM_GAINED(itemID, qty, sourceKey, link)`,
`LIBSFA_REP_GAINED`, `LIBSFA_CURRENCY_GAINED`, `LIBSFA_HUNTS_CHANGED`, `LIBSFA_HUNTS_UPDATED`,
`LIBSFA_ITEM_LOADED`, `LIBSFA_SETTINGS_CHANGED`, `LIBSFA_LOCKOUTS_UPDATED`.

## UI rules

- Visual world: the Lib's family (see `UI/Theme.lua`): flat near-black panes, 1px lines, color only
  for game meaning (item quality, standing, gold, good/bad). Friz for words, Arial Narrow for figures.
- No Unicode glyphs: icons are textures; header glyphs are drawn from bars (`W.IconButton`).
- Pages implement `Create(parent, window)`, `Refresh(bucket, range)`, optional `Count(bucket)`.
- Design direction and the layout mock live in `.impeccable/` (git-ignored, local only).

## Testing

Headless (no game needed):

```
"C:/Users/jerem/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" Tests/run.lua
```

`Tests/run.lua core` skips the UI. The harness loads real Ace3 + LibDataBroker + AceConfigRegistry
(which validates the options table) against a mocked client. Scenarios cover kills, skinning,
group kills, area loot splits, chat dedupe, filters, money categories, hunts, reputation, XP
level-ups, currency/honor, fishing, pause/AFK, goals, sessions, weeks, and a UI smoke pass.

In game, check:
1. Kill and loot mobs: Overview income/kills/top loot, Sources shows the mob with drops and rates.
2. Skin a looted corpse: kills do not go up.
3. Group loot on an epic: counted only for the winner.
4. Sell to a vendor: "Sold to vendors" rises, looted gold does not.
5. Gain rep (normal, renown, paragon, friendship): Progress bars, pace, and no double counts.
6. Level up mid-session: XP keeps counting across the level. Kill a few mobs: Progress shows
   experience per kill and kills to level; after the level-up both start over.
7. Add a hunt (Shift-click into the Hunts box), kill mobs, set a drop chance: luck bar and text.
8. Log out for over 30 minutes: a new session starts, the old one is in History.
9. /reload: everything persists; the window reopens on the same page and range.
10. Item and creature tooltips show farming lines only when there is data.
11. Classic Era and Mists: no errors, rep and honor still counted.
12. Add a mount hunt, open Characters, Add a boss (from a saved raid): kill it and the row turns
    "Done, resets in ...". Log in on an alt: the hunt appears there, and the first character's row
    shows its lockout and counts.
