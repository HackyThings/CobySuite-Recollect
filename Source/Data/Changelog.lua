-------------------------------------------------------------------------------
-- Data.Changelog: the in-game changelog (UI/WhatsNew.lua, /rec changelog),
-- one entry per version, newest first. Shown after an update with every
-- version newer than the one the player last ran opened.
--
-- An entry: version (the TOC's), title (a few words), date ("2026-10-02"
-- once released; nil shows "Beta"), optional icon (a texture path or file
-- ID; default Recollect.ICON), and the lists new, changed and fixed, each a
-- line a player reads (the CHANGELOG.md style: what changed for them, no
-- internals), short enough to fit on one line: "Feature: what it does",
-- the part before the first ": " shown in blue, and {Alt+D} or {/rec} for a
-- key or command in gold (WhatsNew.Line). Keep it in step with
-- CHANGELOG.md: /release adds the entry.
-------------------------------------------------------------------------------
Recollect.Data.Changelog = {
  {
    version = "0.0.2b",
    title = "Collections that finish",
    date = "2026-09-30",
    changed = {
      "Raid loot: more Sanctum and Sepulcher boss drops, seen in game",
    },
    fixed = {
      "Windows: dragging a corner past the screen no longer fills it",
      "Curators: nothing stays waiting after the author collects",
    },
  },
  {
    version = "0.0.2a",
    title = "Safer curator mode",
    date = "2026-09-30",
    changed = {
      "Prices: name what you pay with, like 20 Apexis Crystal",
      "How to get more: says when no source is known, and what binding means",
      "Checks and crosses: show what's done or still to get at a glance",
      "Curator mode: only in the Americas and Oceania region",
      "Curators: findings go only to the author, in small parts",
      "Waypoints: a TomTom arrow names the NPC and why you're going",
    },
    fixed = {
      "Guide: names your own keys when you've changed them",
      "Curators: History says when the author turned a collection down",
      "Earned meta achievements now show green",
      "Plain words and plurals throughout",
    },
  },
  {
    version = "0.0.2",
    title = "Currency prices",
    date = "2026-09-29",
    new = {
      "Currency prices: Sold by X for 350 Honor, on thousands of items",
    },
    changed = {
      "Weapon oils and stones: an older expansion's now read Outdated",
      "Curator mode: sends less, and skips what the author ruled out",
    },
    fixed = {
      "Curators: far fewer false reports (discounts, places, loot)",
      "Curator collections and the connection test: steadier",
    },
  },
  {
    version = "0.0.1d",
    title = "Curator dashboard",
    date = "2026-09-28",
    new = {
      "Curator dashboard: {/rec curator} shows what you recorded and sent",
      "Items with no information: curators note them for the author",
      "Want to be a curator?: a button in the item details window",
      "Achievement button: opens the game's achievement window at it",
    },
    changed = {
      "Windows: click any window to bring it to the front",
      "Curator mode: whispers only, no hidden chat channel",
      "What it's for tiles: plain words and a tooltip on each",
    },
    fixed = {
      "Blocked-action errors after Open Settings in Options > AddOns",
      "Right-click menus on names in the item details Overview",
    },
  },
  {
    version = "0.0.1c",
    title = "Curators on any realm",
    date = "2026-09-28",
    new = {
      "Curator test: {/rec curator transport} checks the link to one player",
    },
    fixed = {
      "Curator mode: reaches curators on realms not connected to yours",
    },
  },
  {
    version = "0.0.1b",
    title = "Clearer answers",
    date = "2026-09-28",
    new = {
      "Still needed?: an answer band atop the item details, with why",
      "Recollect Audit: tabs for My Items, All Characters and each character",
      "Requirements: what a vendor item needs you to complete first",
      "NPCs and treasures: hover for what they are, right-click for more",
      "TomTom: waypoints go to TomTom's arrow when it's installed",
      "Copy Wowhead link: from any right-click menu in the item details",
      "Curators on an alt: asked once whether to join the community",
      "Shift-click: link items, quests, achievements and NPCs in chat",
    },
    changed = {
      "Audit panel: a short summary; {Alt+D} shows everything",
      "What it's for: opens by explaining what the item is",
      "Achievements: a section of their own, with their meta achievements",
      "Treasures: keys say what the treasure holds",
      "Right-click menus: the game's own menu, at the mouse",
      "Recollect Audit: grouped filters, counts by verdict, clearer columns",
      "Settings: resizable, tidier groups, a Guide button",
      "What crafting takes: now under How to get more",
    },
    fixed = {
      "Tables: dragging a divider on a full table widens the column",
      "What it takes: the Others and Status columns show their values",
      "Windows no longer jump when resized by the corner",
      "Every quality of a crafted item shows the recipe that makes it",
      "Items that milling and prospecting take show those recipes",
      "Minimap button: sits outside the minimap again",
      "Curators: unsent findings are kept through updates",
    },
  },
  {
    version = "0.0.1a",
    title = "Curators and glyphs",
    date = "2026-09-28",
    new = {
      "Curator check: {/rec curator diag} shows what curator mode sees",
    },
    changed = {
      "Database: 17 missing Inscription glyph recipes added",
      "Database: Fused Vitality shown as a Tailoring weekly reward",
    },
    fixed = {
      "Curator mode: collections now reach the author from other players",
      "Curator mode: works when your game doesn't know the author yet",
      "Curator mode: salvage recipes are no longer reported as missing",
    },
  },
  {
    version = "0.0.1",
    title = "First beta",
    date = "2026-09-27",
    new = {
      "Verdicts: a colored answer for every item you hold, with the reason",
      "Audit panel: hold {Alt} over any item to see what it's for",
      "Item details: press {Alt+D} for everything about one item",
      "Recollect Audit: every item you hold in one list, with {/rec}",
      "Minimap button: opens the Recollect Audit",
      "Waypoints: press {Alt+W} to go where the panel points",
      "Guide: opens on your first login, or with {/rec guide}",
      "Changelog: opens after each update, or with {/rec changelog}",
      "Curator mode: optional, help improve Recollect's database",
      "Curator Flag: tell the author an item's details are missing or wrong",
      "Feedback: {/rec feedback} sends the author your thoughts",
    },
  },
}
