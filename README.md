# Recollect

<p align="center">
  <img src="https://raw.githubusercontent.com/HackyThings/CobySuite-Recollect/main/.publish-meta/icon/recollect-224.jpg" width="160" alt="Recollect">
</p>

Recollect shows what each item in your bags, bank and warband bank is for, and whether you still need it.

## How to use it

- Hold **Alt** over any item to see its audit panel: the verdict, what the item is used for, and why.
- Press **Alt+D** while the panel shows (or click a row in the Recollect Audit) to open the item's full details.
- Press **Alt+W** while the panel names a vendor, a treasure or an NPC to set a waypoint to it.
- `/rec`, or a click on the minimap button, opens the **Recollect Audit**: every stack in your bags, bank and warband bank, with its verdict and reason. Right-click the button for settings.
- `/rec settings` lets you change the panel, waypoint and pin keys, or turn Recollect off on tooltips.
- `/rec guide` opens the in-game feature guide.

## Verdicts

- **Needed**: something unfinished still uses it.
- **Use now**: learn it, open it, or start its quest.
- **Useful**: it still has a use for you, such as something it buys that you don't have yet.
- **Can't tell**: Recollect can't confirm yet, and says why.
- **Junk**: a gray item with a vendor price, the game's own junk label.
- **Outdated**: it has been replaced (older gear, an old-season reagent, and the like).
- **Lower level**: gear below what you wear, but not shown to be from an older season or expansion.
- **Purpose done**: every use Recollect checks is finished.

Recollect never tells you to delete or sell anything. When every use it could check is done, a Tip may say the item is most likely safe to sell or delete, but that's your call.

## Curator mode

Curator mode is optional and off by default: turn it on under `/rec settings`, Curator. While it's on, Recollect notes where the game shows you something its database gets wrong or doesn't have (a vendor's prices, a drop, a quest reward, where an NPC stands), as game IDs and map positions, with your character's class, race, level, faction, professions and, where it matters, quest progress. It never records names, chat, gold or your inventory.

With curator mode on you can also flag an item from its details window (Curator Flag: pick what's wrong and, if you like, add your own words) or send feedback with `/rec feedback`. Recollect errors your game shows are sent along too, so they can be fixed. Only the author reads flags, feedback and errors.

The author collects these findings through the "Recollect Curators" community (`/rec curator join` prints the invite link) to improve the database that ships with Recollect. Members of the community can see each other's character names and zones. Turning curator mode off offers to delete your findings.

## Commands

- `/rec` or `/recollect`: open or close the Recollect Audit
- `/rec settings`: open the settings window
- `/rec guide`: open or close the feature guide (it opens by itself the first time you log in)
- `/rec changelog` (or `/rec change`): what changed in each version (it opens by itself after an update)
- `/rec debug`: open or close the debug log
- `/rec curator`: curator mode's status; `join` prints the community's invite link, `cancel` stops a collection
- `/rec feedback` (or `/rec bug`): write feedback for the author; it's sent with your next curator collection
- `/rec version`: print the addon version
- `/rec help`: list the commands

The Addon Compartment (the minimap's addon list) also opens the Recollect Audit; right-click it for the settings. The settings are also under Options > AddOns.

## License

Copyright (C) 2026 Cobanyte. Released under the GNU General Public License, version 2 (see LICENSE).

## Where the data comes from

Recollect reads your collections, quests, achievements and bags live from the game. What links an item to its uses comes from these places, shipped as IDs only (every name is read live in your language):

- the game's own answers, gathered in game by Recollect's development tools;
- [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings) (MIT license, Copyright (c) 2026 AllTheThings WoW Addon), from which Recollect builds its own curated list of vendor costs, positions, quest items and item sources. Its license notice is in `Source/Data/Relations.lua`;
- for a few items nothing in the game explains, a guide note written from a guide website, shown with that site's name and "not confirmed in game yet". A guide note never changes a verdict.
