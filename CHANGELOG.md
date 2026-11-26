# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/).

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

## [1.0.0] - 2026-11-26

### Added
- Frame listing mana users sorted by lowest mana %, class-coloured bars.
- Healers only by default, optional DPS mana classes; shows the 5 lowest by default.
- Out-of-range (Innervate, 30 yd) fading, using UnitXP_SP3 when available.
- Click to cast Innervate (SuperWoW-aware), right-click to target, Shift+Right-click to toggle manual healer.
- Innervate cooldown in the header.
- Manual healer list and combat log based healer detection.
- Slash commands and an options window.
- Test mode with fake data.

[1.1.0]: https://github.com/medarrow/InnervateBuddy/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/medarrow/InnervateBuddy/releases/tag/v1.0.0
