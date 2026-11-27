# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-11-26

### Added
- `/ib inspect [name]` asks one player for their talents right away.
- `/ib debug` prints talent requests and replies to chat.
- `/ib specs` now also shows who hasn't answered and when they'll be asked again.

### Fixed
- Talent replies were never recognised if the server put whitespace (a tab) in front of them, which also stopped the lock-up fix below from working. Leading whitespace is now stripped.
- A reply could be read from the middle when another addon (such as ChronicleCompanion) asked the same player just before, giving a wrong point split. Only replies read complete and in order, from the first tree's header to the end, are used now; anything else is thrown away and the player is asked again later.
- Game could lock up when changing target (e.g. targeting an NPC) after a background talent scan. Turtle's own Inspect code also processed the scan replies and stored them against your current target, sometimes opening its talent frame for it. Replies to InnervateBuddy's requests are now kept away from Turtle's Inspect code, unless you're inspecting that player yourself.
- Talent detection never got any answers on Turtle WoW ("Specs inspected: 0/4 (waiting)"). Turtle doesn't send talents through the standard inspect; it uses a hidden `INSTalentShow` addon message that the other player's client answers. InnervateBuddy now uses that, the same way Turtle's own Inspect → Talents tab does. Requests go out every 3 s and wait up to 10 s for a reply.
- Options window: "Manual list" label overlapped the name box, the remove "x" sat off its row, and the inspect status floated. The Healers section now lines up on a two-column grid.

## [1.1.0] - 2026-11-26

### Added
- Healer detection by inspecting group members' talents (Turtle WoW / 1.18 allows inspecting at any range). Throttled to one request every 2 seconds, paused in combat and while the Inspect window is open.
- Inspected specs are saved per player, refreshed every 30 minutes and expire after 14 days.
- `/ib talents`, `/ib combatlog`, `/ib specs` and `/ib rescan` commands.
- Options: "Inspect talents" and "Use combat log" toggles, and an inspected-specs counter.
- The "Healers in group now" list shows each player's talent point split.

### Changed
- Combat log healer detection is now optional and **off by default**.
- Talent trees are matched by name instead of tab position.
- "Reset detected" also clears saved talent specs.

## 1.0.0 - 2026-11-26 (unreleased)

### Added
- Frame listing mana users sorted by lowest mana %, class-coloured bars.
- Healers only by default, optional DPS mana classes; shows the 5 lowest by default.
- Out-of-range (Innervate, 30 yd) fading, using UnitXP_SP3 when available.
- Click to cast Innervate (SuperWoW-aware), right-click to target, Shift+Right-click to toggle manual healer.
- Innervate cooldown in the header.
- Manual healer list and combat log based healer detection.
- Slash commands and an options window.
- Test mode with fake data.

[1.2.0]: https://github.com/medarrow/InnervateBuddy/releases/tag/v1.2.0
[1.1.0]: https://github.com/medarrow/InnervateBuddy/releases/tag/v1.1.0
