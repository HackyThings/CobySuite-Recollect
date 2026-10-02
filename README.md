# Recollect

<p align="center">
  <img src="https://raw.githubusercontent.com/HackyThings/CobySuite-Recollect/main/.publish-meta/icon/recollect-224.jpg" width="160" alt="Recollect">
</p>

Recollect shows what each item in your bags, bank and warband bank is for, and whether you still need it.

## How to use it

- Hover an item in your bags or bank and hold **Alt**: the audit panel beside the tooltip shows the verdict, what the item is used for, and why.
- **Alt+D** while the panel shows opens the item's full details.
- **Alt+W** while the panel names a vendor, treasure or NPC sets a waypoint to it.
- `/rec` or the minimap button opens the **Recollect Audit**, every stack you hold with its verdict. Right-click the button for settings.
- `/rec guide` opens the feature guide (it opens by itself on your first login).

## Verdicts

- **Needed**: something unfinished still uses it.
- **Use now**: learn it, open it, or start its quest.
- **Useful**: it still has a use for you, such as something it buys that you don't have.
- **Can't tell**: Recollect can't confirm yet, and says why (and what to do, where it can).
- **Junk**: a gray item with a vendor price, the game's own junk label.
- **Outdated**: it has been replaced (older gear, an older expansion's potions, flasks, food, weapon oils and sharpening stones, an old-season reagent and the like).
- **Lower level**: gear below what you wear, not shown to be from an older season.
- **Purpose done**: every use Recollect checks is finished.

Recollect never decides for you. Its suggestions, such as "most likely safe to sell or delete, but that's your call", always come with their reason.

## The audit panel

A short summary beside the tooltip: the verdict and why, the uses that matter most, where the item comes from, and a Tip when one applies. For an item you don't hold (a chat link, loot, a vendor's goods), it shows how many you have instead.

## The item details window

Everything Recollect knows about one item, so you don't need a website. Open it with Alt+D, or click a row in the Recollect Audit. A setting can make the key a click instead (Alt+click, for example), which works on any item, even in combat.

- **Still needed?** Recollect's suggestion (Keep it, Sell it, Likely safe to delete, Probably done, Replaced, Lower level or Can't tell yet) with a short reason; hover for the rest.
- **What it's for:** what the item is, its Use line, and a tile for each kind of use with how many there are and how many are still open.
- **Achievements:** what it counts toward, with progress bars.
- **How to get more:** each way to get it (sold by, drops from, rewards) with the whole price and what buying requires first. With no source recorded yet, it says so, and whether another player could trade you one.
- **Guide notes:** short notes in Recollect's own words for items nothing in the game explains. They never change the suggestion.
- **What you have:** your counts by place and on your other characters; hover a tile for exactly where.
- **Checks:** every check Recollect ran and what it found.

A green check marks what's done, earned, collected or known, a red cross what's still to get or do, and a gray cross what this character can't use.

Tabs along the bottom list everything in sortable, searchable tables. Names work as they do in chat (hover, Shift-click, Ctrl-click), Alt-click opens that item here, and right-click gives a menu: link it, preview it, set a waypoint, or copy its Wowhead link. An achievement row's icon opens the game's achievement window at it.

## The Recollect Audit

`/rec` lists every stack you hold with its verdict and reason, counted by verdict at the top. Search it, or filter by verdict, place, use or why Recollect can't tell. Tabs choose whose items you see: My Items (this character and the warband bank), All Characters, or one of your others as they were at their last login. Click a row for its details.

## Waypoints

Waypoints go to TomTom when it's installed, else to the game's map pin; a setting can always use the game's pin. A TomTom arrow names the NPC and why you're going, such as "sells ..." or "drops ...". The waypoint key isn't bound in combat.

## Settings

`/rec settings`, a right-click on the minimap button, or Options > AddOns.

- **Audit panel:** whether Recollect shows on item tooltips, and when the audit panel shows (Alt, Shift, Ctrl or always), with an example.
- **Recollect Audit:** whether the list includes your bank, warband bank and other characters, and the minimap button.
- **Keys and waypoints:** the item details key, the waypoint key, and where waypoints go (TomTom first, or the game's map pin).
- **Curator:** curator mode (below).

## Curator mode

Optional and off by default, and available only in the Americas and Oceania region. It helps the author find missing or wrong item data while you play.

- Turn it on under `/rec settings` > **Curator**, which lists exactly what is recorded. It records game IDs and positions, never names, chat, gold, currencies or how many of anything you have.
- Join **Recollect Curators** with `/rec curator join`; the author collects findings through that community.
- **Curator Flag** (or **Request info**) in item details and `/rec feedback` send your own notes.
- `/rec curator` shows what waits to be sent and the collection history. Turn on **Ask me before each collection** to approve each one.
- Turning curator mode off stops recording and offers to delete saved findings.

## Commands

```
/rec              Open or close the Recollect Audit (also /recollect, /rec show)
/rec settings     Open or close the settings window (also /rec config, /rec options)
/rec guide        Open or close the feature guide (also /rec tutorial)
/rec changelog    Open or close the changelog: what changed in each version (also /rec whatsnew, /rec news, /rec change)
/rec debug        Open or close the debug log window
/rec curator      Open the curator dashboard (also status, join, cancel, diag, ping)
/rec feedback     Write feedback for Recollect's author, sent with your next curator collection (also /rec bug)
/rec version      Print the addon version
/rec help         Show this help
```

The Addon Compartment also opens the Recollect Audit; right-click it for settings.

## Issues / Feedback

Found a bug? Run `/rec debug`, press **Copy Last 250** and send the text with a line about what you were doing. The log holds the addon version, your WoW build and your settings.

- **Email:** hackythings@gmail.com
- **BugSack errors:** whisper them to **Figment-Illidan** in game.
- **CurseForge:** comment on the [project page](https://www.curseforge.com/projects/1714804) for questions and feedback.
- **GitHub:** [open an issue](https://github.com/HackyThings/CobySuite-Recollect/issues) for bugs you can reproduce.

## License

Copyright (C) 2026 Cobanyte. Released under the GNU General Public License, version 2 (see LICENSE).

## Where the data comes from

Recollect reads your collections, quests, achievements, bags and bank live from the game. What links an item to its uses ships as IDs only (names are read live in your language), from:

- the game's own answers, gathered with Recollect's development tools;
- [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings) (MIT license, Copyright (c) 2026 AllTheThings WoW Addon), from which Recollect builds its own curated list of vendor costs, positions, quest items and item sources; its license notice is in `Source/Data/Relations.lua` and `Source/Data/Vendors.lua`;
- what curators found in game, once the author has checked it;
- short notes the author wrote in Recollect's own words for items nothing in the game explains. None of them changes a verdict.
