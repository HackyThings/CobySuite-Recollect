# Recollect

<p align="center">
  <img src="https://raw.githubusercontent.com/HackyThings/CobySuite-Recollect/main/.publish-meta/icon/recollect-224.jpg" width="160" alt="Recollect">
</p>

Recollect shows what each item in your bags, bank and warband bank is for, and whether you still need it.

## How to use it

- Hover an item in your bags or bank: its tooltip gets one line, "Recollect: hold Alt for details". Hold **Alt** to see the audit panel beside it: the verdict, what the item is used for, and why.
- Press **Alt+D** while the panel shows (or click a row in the Recollect Audit) to open the item's full details.
- Press **Alt+W** while the panel names a vendor, a treasure or an NPC to set a waypoint to it.
- `/rec`, or a click on the minimap button, opens the **Recollect Audit**: every stack in your bags, bank and warband bank, with its verdict and reason. Right-click the button for settings.
- `/rec guide` opens the in-game feature guide. It opens by itself the first time you log in.

## Verdicts

- **Needed**: something unfinished still uses it.
- **Use now**: learn it, open it, or start its quest.
- **Useful**: it still has a use for you, such as something it buys that you don't have yet.
- **Can't tell**: Recollect can't confirm yet, and says why (and, where it can, what to do so it can tell).
- **Junk**: a gray item with a vendor price, the game's own junk label.
- **Outdated**: it has been replaced (older gear, an old-season reagent, and the like).
- **Lower level**: gear below what you wear, but not shown to be from an older season or expansion.
- **Purpose done**: every use Recollect checks is finished.

Recollect never decides for you. The details window's "Still needed?" answer and the Tip (shown for junk, and when every use Recollect could check is done) are suggestions with their reason, such as "most likely safe to sell or delete, but that's your call". What you keep is always up to you.

## The audit panel

Hold Alt over an item in your bags, bank or warband bank and a short summary shows beside its tooltip:

- the verdict and its reason; when Recollect can't tell, what the item is used for comes first;
- the few uses that matter most, with where you stand on each. Everything the item buys is one line, such as "Buys 4 decor and 2 pets you don't have";
- where the item comes from, and a Tip when one applies;
- the keys you can press. When there was more to show, the details key's line says "for everything".

On an item you don't hold (a chat link, a vendor's goods, loot, the auction house, gear you wear) the panel shows how many you have instead of a verdict.

## The item details window

Everything Recollect knows about one item, for a player who shouldn't need a website to find out. Open it with Alt+D while the panel shows, or click a row in the Recollect Audit. In the settings you can make the key a click instead (Alt+click, for example), which works on any item: in your bags or bank, a chat link, loot or a vendor, even in combat.

- **The header:** the item's icon in its quality's color, its name, and one quiet line saying what it is, where it's from and whether it's PvP gear.
- **Still needed?:** a band across the whole window, on every tab, with Recollect's suggestion (Keep it, Sell it, Likely safe to delete, Probably done, Replaced, Lower level or Can't tell yet) and a short reason why. Hover it for the whole reason and the Tip. For an item you aren't holding, it says how many you have and where.
- **What it's for:** what the item is, where it's from, how it's made and what it's used for, with the item's own Use line quoted so you don't have to hover it. For items whose Use line leaves you guessing, a sentence or two says what it's really for. A row of tiles counts each kind of use (Buys, Quests, Achievements, Crafting) and how many are still open. A key names the treasure it opens, where it is, what it holds and whether you've looted it.
- **Achievements:** the achievements the item counts toward, with the meta achievements they are part of, each with a progress bar.
- **How to get more:** tiles for each way to get it (Sold by, Drops from, Reward and more), what crafting it takes, and what buying it requires first: achievements with your progress, a renown level, a reputation standing or a quest to finish, dimmed until you meet them.
- **What you have:** a tile for each place (Bags, Worn, Bank, Warband bank) with its count, and one for your other characters together. Hover a tile to see exactly where: which bag, each bank or warband tab by its name, or each character with their bags and bank, as last seen.
- **Checks:** every check Recollect ran on the item and what each found.

Each section opens and closes with a click, and Recollect remembers which you keep open. Beside the Overview, tabs along the bottom list everything in sortable tables: Buys, Quests & achievements, Crafting, Comes from, What it takes and No longer available (a tab shows only when it has rows). Each has a search box and a filter for what you still need, what you have and what isn't for this character. Drag a column's divider to size it (Recollect keeps that width for every item), or double-click the divider to fit it.

Names of items, quests, achievements and the like work as they do in chat: hover for the game's tooltip, Shift-click to link, Ctrl-click to preview, and Alt-click to open that item in this window, with Back and Forward buttons. NPCs and treasure spots are links too: hover one to see what Recollect knows of it (a boss and its dungeon, how many items a vendor sells, what a treasure holds), and Shift-click it to put its name, place and a map pin in chat. Right-click any of them, or any table row, for a menu: open it here, link it in chat, preview it, set a waypoint, or copy its Wowhead link or its name. A map button beside a place sets a waypoint to it.

## The Recollect Audit

`/rec` opens a list of every stack you hold, one row each, with its verdict and reason. The top says what the list is for and counts your stacks by verdict, each in its color. Search by name, or open the filter menu, grouped under Verdict, Where it is, Uses, and Why Recollect can't tell. Hover a column title to see what it holds. An empty list says why: nothing read yet, nothing on that character, or nothing matching your search and filters.

Tabs along the bottom choose whose items you see: My Items (this character and the warband bank), All Characters, and one tab for each of your other characters Recollect has seen. Your other characters' items are as they were when each last logged in, and only checks that hold for your whole account run on them. Click a row to open that item's details, and hold Alt over it for its panel.

## Waypoints

Waypoints go to TomTom's arrow when TomTom is installed, else to the game's own map pin; a setting can always use the game's pin. In the item details window's right-click menu you can pick either each time. The waypoint key isn't bound during combat.

## Settings

`/rec settings`, a right-click on the minimap button, or Options > AddOns opens the settings window. Drag its bottom-right corner to make it bigger; it keeps that size.

- **Tooltips:** whether Recollect shows on item tooltips, when the audit panel shows (hold Alt, Shift or Ctrl, or always), the waypoint key and the details key (called the pin key there), and where waypoints go.
- **Recollect Audit:** whether the list includes your bank, the warband bank and your other characters, and whether the minimap button shows.
- **Curator:** curator mode (below).

A Guide button opens the feature guide.

## Curator mode

Curator mode is optional and off by default: turn it on under `/rec settings`, Curator. While it's on, Recollect notes where the game shows you something its database gets wrong or doesn't have (a vendor's prices, a drop, a quest reward, where an NPC stands), as game IDs and map positions, with your character's class, race, level, faction, professions, zone, whether War Mode or Chromie Time is on and, where it matters, quest progress. It never records names, chat, gold or your inventory.

With curator mode on you can also flag an item from its details window (Curator Flag: pick what's wrong and, if you like, add your own words) or send feedback with `/rec feedback`. Recollect's own errors are sent along too, so they can be fixed. Only the author reads flags, feedback and errors.

The author collects these findings through the "Recollect Curators" community (`/rec curator join` prints the invite link) to improve the database that ships with Recollect. Members of the community can see each other's character names and zones. The first time you log in on a character that isn't in the community, a small window asks whether to add it; if you'd rather not, that character isn't asked again. Collections travel as hidden whispers between you and the author, on any realm. Characters in the community also join a hidden chat channel used to find online curators: it never shows in your chat windows, but it takes one of your chat channel slots. Findings not collected yet are kept when Recollect or its database updates, labelled with the version they were recorded under. Turning curator mode off offers to delete your findings.

## Commands

- `/rec` or `/recollect`: open or close the Recollect Audit
- `/rec settings`: open the settings window
- `/rec guide`: open or close the feature guide (it opens by itself the first time you log in)
- `/rec changelog` (or `/rec change`): what changed in each version (it opens by itself after an update)
- `/rec debug`: open or close the debug log
- `/rec curator`: curator mode's status; `join` prints the community's invite link, `cancel` stops a collection, `channel` joins the hidden curator channel again, `diag` prints what your game sees, for a bug report, and `transport Name-Realm` (or `ping`) runs a five-minute connection test with that player's game and prints a report
- `/rec feedback` (or `/rec bug`): write feedback for the author; it's sent with your next curator collection
- `/rec version`: print the addon version
- `/rec help`: list the commands

The Addon Compartment (the minimap's addon list) also opens the Recollect Audit; right-click it for the settings.

## License

Copyright (C) 2026 Cobanyte. Released under the GNU General Public License, version 2 (see LICENSE).

## Where the data comes from

Recollect reads your collections, quests, achievements, bags and bank live from the game. What links an item to its uses comes from these places, shipped as IDs only (every name is read live in your language):

- the game's own answers, gathered in game by Recollect's development tools;
- [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings) (MIT license, Copyright (c) 2026 AllTheThings WoW Addon), from which Recollect builds its own curated list of vendor costs, positions, quest items and item sources. Its license notice is in `Source/Data/Relations.lua`;
- what curators found in game, once the author has checked it;
- a few short texts the author wrote in Recollect's own words: guide notes for items nothing in the game explains (labeled "Guide note", and "not confirmed in game yet" until checked in game), a sentence or two for items whose Use line leaves you guessing, and the items known to stay in your bags once their use is done. None of them ever changes a verdict.
