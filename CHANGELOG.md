# Changelog

All notable changes to Recollect are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), version numbering follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-10-01

The first release of Recollect: what every item in your bags, bank and warband bank is for, and whether you still need it.

### Added

- **A verdict on every item you hold.** Needed, Use now, Useful, Can't tell, Junk, Outdated, Lower level or Purpose done, always with the reason. Recollect never decides for you: a suggestion such as "most likely safe to sell or delete, but that's your call" comes with why.

- **The audit panel.** Hover an item and hold **Alt** (or Shift, Ctrl, or always, in the settings): beside the tooltip, a short summary of the verdict, the uses that matter most and where you stand on each, where the item comes from, and a Tip when one applies. On an item you don't hold, such as a chat link, loot or a vendor's goods, it shows how many you have instead.

- **The item details window.** **Alt+D** while the panel shows, or a click on a row of the Recollect Audit, opens everything Recollect knows about one item, so you don't need a website: what it's for, the achievements it counts toward with progress bars, every way to get more with the whole price and what buying requires first, guide notes, your counts on every character, and every check Recollect ran. Tabs list its purchases, quests, crafting, sources and requirements in sortable, searchable tables; names work as they do in chat, Alt-click opens another item here, and right-click links it, previews it, sets a waypoint or copies its Wowhead link. The key can be a click instead, such as Alt+click, which works on any item, even in combat.

- **The Recollect Audit.** `/rec` or the minimap button lists every stack you hold with its verdict, counted at the top. Search it, filter it by verdict, place, use or why Recollect can't tell, and switch between this character with the warband bank, all your characters, or one of your others as of their last login.

- **Waypoints.** **Alt+W** while the panel names a vendor, treasure or NPC sets a waypoint to it: a TomTom arrow when TomTom is installed, naming the NPC and why you're going, else the game's map pin.

- **A database built for players.** Vendors and their whole prices (items, currencies and gold), drops from creatures, bosses and zones, quest rewards and quest items, recipes and their reagents, treasures and keys, combines, renown rewards, the Black Market and the Trading Post, meta achievements, and when items were added or removed from the game. Names are read live from the game in your language.

- **Curator mode (optional, Americas and Oceania region).** Off by default. Curators help keep the database right: while it's on, Recollect notes where the game disagrees with its database or shows something it lacks, such as a vendor's price, a drop or where an NPC stands, and hands only those findings to the author's own characters, in small parts. It records game IDs and positions with your character's class, race, level, faction, professions and zone, never names, chat, gold or what you carry. `/rec curator` opens the curator dashboard, and **Curator Flag** in the details window reports a problem with an item in your own words.

- **Settings, a guide and a changelog.** `/rec settings` (also a right-click on the minimap button or Options > AddOns), `/rec guide`, which opens by itself on your first login, and `/rec changelog`.

[Unreleased]: https://github.com/HackyThings/CobySuite-Recollect/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v1.0.0
