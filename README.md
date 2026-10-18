# Recollect

<p align="center">
  <img src="https://raw.githubusercontent.com/HackyThings/CobySuite-Recollect/main/.publish-meta/icon/recollect-224.jpg" width="160" alt="Recollect">
</p>

**Your bags are full of things you're afraid to throw away. Recollect tells you what each one is for, and whether you still need it.**

Hover any item in your bags, bank or warband bank and hold **Alt**. Recollect shows what the item is used for, where it comes from, and a plain answer: keep it, use it, sell it, or it's done. Every answer comes with its reason, so you never have to take its word blindly.

It's an in-game item encyclopedia too. For nearly any item in the game, Recollect can tell you what it buys, what quests and achievements need it, what it combines into, what it opens, who sells it, what drops it, and much more, without leaving the game.

## What's new in 1.0.5

- **104 secrets now, up from 22.** The Hivemind, the Mote of Nasz'uro, the S.E.L.F.I.E. Camera's hidden filters, the Secrets of Azeroth clues, 20 Midnight secrets, Zul'Gurub's relics, Legion's hidden artifact appearances and many more, each explained step by step.
- **A clearer item details window.** It opens on a Summary that says each thing once, and anything you open, such as a cache or a chest, gets its own What's inside tab showing what it can give and whether you have it.
- **Raid and dungeon loot names its difficulty,** and each boss is listed once.
- **Pause curator recording** with `/rec curator pause` for the rest of your session.
- **More items say where they come from,** including Midnight quest items the game files under an older expansion, plus many fixes from what curators found in game.

## Getting started

- Hover an item in your bags or bank and hold **Alt** to see its audit panel beside the tooltip.
- Press **Alt+D** while the panel shows to open the item's full details.
- Press **Alt+W** while the panel names a vendor, treasure or NPC to set a waypoint to it.
- Type `/rec`, or click the minimap button, to open the **Recollect Audit**: every stack you hold, with its answer.
- Type `/rec guide` for a quick tour. It also opens by itself the first time you log in.

## The answers

| Answer | What it means |
|---|---|
| **Keep it** | Something unfinished still needs it, it still has a use for you, or you can use it right now (learn it, open it, start its quest). |
| **Sell it** | A gray item the game itself marks as junk. |
| **Replaced** | Something newer does its job: older potions, food, gear from past seasons and the like. |
| **Lower level** | Gear below what you're wearing. |
| **Probably done** | Every use Recollect knows about is finished. |
| **Likely safe to delete** | Every use Recollect checked is done, with the reasons listed. Still your call. |
| **Just for fun / Your call** | An optional item, like a novelty or a pet treat. It's up to you. |
| **Can't tell yet** | Recollect can't be sure, and tells you why and what would settle it. |

Recollect never decides for you. When it thinks something is most likely safe to sell or delete, it says so with its reasons, and leaves the call to you.

## The item details window

Everything Recollect knows about one item, in one place. Open it with **Alt+D**, or click a row in the Recollect Audit.

- **What it's for:** what the item is and every use it has, each with where you stand.
- **How to get more:** every way to get it, with the full price and anything you need first.
- **Achievements** it counts toward, with progress bars.
- **What you have** on this character and your others.
- **Tabs** with sortable, searchable tables: what it buys, quests and achievements, crafting, where it comes from, what using it takes, and what's no longer available.
- **The Secret tab** for any item that's part of one of the game's secrets.

Every name is a real link: hover it, Shift-click it into chat, or Alt-click to open that item in the details window. Right-click any row to link it, preview it, set a waypoint or copy its name.

## The Recollect Audit

`/rec` lists every stack you hold with its answer and reason, counted at the top. Search it, filter it by answer, place or use, and switch between this character, all your characters, or any one alt as of their last login.

## Waypoints

Waypoints go to TomTom when it's installed, otherwise to the game's own map pin. You can always choose the game's pin in the settings.

## Settings

Open them with `/rec settings`, a right-click on the minimap button, or Options > AddOns. You can choose which key shows the audit panel (Alt, Shift, Ctrl or always), which bags and banks the audit includes, your details and waypoint keys, and whether you'd like to hear when a newer version is out.

## Curator mode (optional)

Want to help make Recollect better? Curator mode quietly notes where the game disagrees with Recollect's data while you play, and sends those notes to the author to check before anything changes. It's off by default and available in the Americas and Oceania region only.

- It records game IDs and places, and a few details about your character such as class, level and zone. It never records names, chat, gold, or how many of anything you have.
- Turn it on in `/rec settings` under **Curator**, which lists exactly what's recorded.
- Join the **Recollect Curators** community with `/rec curator join`.
- Use **Curator Flag** in the item details, or `/rec feedback`, to send your own notes.
- Turning it off stops recording and offers to delete what was saved.

## Commands

```
/rec                Open or close the Recollect Audit
/rec settings       Open the settings
/rec guide          Open the feature guide
/rec changelog      See what changed in each version
/rec addons         Every addon by Cobanyte, with CurseForge links
/rec reset windows  Put every window back in its default place
/rec curator        Open the curator dashboard
/rec feedback       Send feedback to the author
/rec debug          Open the debug log
/rec help           Show every command
```

## Found a bug?

Type `/rec debug`, press **Copy Last 250**, and send the text along with a line about what you were doing.

- **CurseForge:** comment on the project page.
- **GitHub:** [open an issue](https://github.com/HackyThings/CobySuite-Recollect/issues) for bugs you can reproduce.
- **In game:** whisper **Figment-Illidan** with BugSack errors.
- **Email:** hackythings@gmail.com

## Where the data comes from

Recollect reads your collections, quests, achievements, bags and bank live from the game. Its database of what links each item to its uses ships as IDs only, and every name is read live in your own language. That database is built from:

- the game's own answers, gathered with Recollect's development tools;
- [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings) (MIT license, Copyright (c) 2026 AllTheThings WoW Addon), from which Recollect builds its own curated list of item sources, vendor prices, places and quest items;
- what curators found in game, once the author has checked it;
- short notes written in Recollect's own words for items nothing in the game explains.

## License

Copyright (C) 2026 Cobanyte. Released under the GNU General Public License, version 2.
