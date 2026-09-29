# Product
<!-- impeccable:product-schema 1 -->

> Written from the owner's brief on 2026-09-28 without an interview round (the session ran
> unattended). Facts marked *(inferred)* were not confirmed by the owner.

## Platform
World of Warcraft addon UI (Lua 5.1 frames, not web). Ships to every live client: Retail 12.x,
WoW Forever, Mists Classic, Titan, TBC Anniversary and Classic Era.

## Users
Players who repeat the same activity to get something out of it: grinding mobs for a rare drop
or a mount, gathering herbs, ore and cloth for gold, fishing, grinding reputation, leveling alts,
earning currency and honor. They play with the addon open beside the game, glance at it between
pulls, and come back to it later to compare days and characters. *(inferred: most sessions last
30 minutes to several hours.)*

## Product Purpose
Lib's Farm Assistant answers "was this worth my time, and how close am I?" for anything a player
farms. It records what came in (items, gold, currency, reputation, experience, honor, kills),
where it came from (which mob, node, chest or fishing spot), and how fast, then keeps it by
session, day, week, month and all time.

Success: a player hunting a rare drop knows how many kills they are in, how lucky that is, and
which mob gives it more often; a gold farmer knows their real gold per hour; a rep grinder knows
how long until the next standing.

## Positioning
One addon that measures every kind of farm with the same vocabulary (per hour, per kill, per
source, per time window), and ties drops to the exact mob or node that produced them, so luck can
be compared across sources.

## Operating Context
- Used mid-gameplay: the data broker text, a compact tracker and item/mob tooltips must be
  readable at a glance; the full window is for between pulls and after the session.
- Often paired with an auto-loot setup (the addon has its own priority auto-looter).
- Players switch characters; history is per character.
- Retail 12.x hides some combat values from addons (secret values); tracking must degrade
  quietly rather than error.

## Capabilities and Constraints
- Tracking modes: everything (filtered by item quality tiers) or only chosen items.
- Hunts: pick items (including mounts, pets, toys) and count attempts until they drop, with
  optional known drop chance to show luck.
- Optional lines on item and unit tooltips.
- No emoji or arbitrary Unicode in game text; icons come from game atlases or textures.
- Must not require another addon to show its window. Libs-DataBar and Libs-AddonTools are optional.
- Auction values come only from an installed pricing addon; never named in user-facing text.
- Undecided: account-wide (all characters) views; sharing results with a group.

## Brand Commitments
- Name: "Lib's Farm Assistant", part of the "Lib's" addon family by Wutname1.
- Family look already exists in code (Libs-Totembar `UI/Theme.lua`): flat near-black translucent
  panes, 1px hairlines, saturated color only where it carries game meaning.
- The owner likes the reputation displays in W2UI and Plumber (standing colors, clear progress,
  "until next level" wording).

## Evidence on Hand
No real player data, screenshots or testimonials exist yet. Demonstration data in mockups is
synthetic and must be labeled as such.

## Product Principles
1. Every number answers a question a farmer actually asks: how much, how fast, from where, how long until.
2. Glanceable first, detailed on demand: the tracker and tooltips carry the headline, the window carries the proof.
3. Honest counts: say "looted" when we only know loot, never invent kills or drop chances.
4. Quiet by default: no chat spam, no popups; the player opts in to alerts.
5. Works the same on every game version; missing game features hide, never break.

## Accessibility & Inclusion
Text sits on dark panes at readable contrast; quality and standing colors are always paired with
a word or number, never color alone. *(inferred)*
