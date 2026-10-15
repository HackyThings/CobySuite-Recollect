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
    version = "1.0.4",
    title = "Secrets, and where things come from",
    date = "2026-10-15",
    new = {
      "Secrets: 22 of the game's secrets explained step by step",
      "Secret tab: steps, what you need, waypoints and your own checkmarks",
      "New items: where they come from, even before the database knows them",
      "More ways to get things: trades, missions, events and pickpocketing",
      "More uses: customizations, reputation items, tokens, combines",
      "No longer obtainable: said even when the removal patch isn't known",
    },
    changed = {
      "Patch 12.1.5 in the database: renown vendors, decor, quests, Delves",
      "How to get more walks a chain back to what you need",
      "A bigger, more complete database from curators' findings",
      "Curator mode: records more, more precisely, in fewer messages",
      "Performance improvements",
      "Many smaller look and wording improvements",
    },
    fixed = {
      "Wrong facts removed: later items no longer read 'from Classic'",
      "Older items: gone recipes and parts no longer say Keep it",
      "Another character's copy describes that character",
      "Several smaller bug fixes",
    },
  },
  {
    version = "1.0.3",
    title = "Where mounts, pets and toys come from",
    date = "2026-10-11",
    new = {
      "Mounts, pets and toys: where far more come from, shop and promos too",
      "Comes from: disenchanting, skinning, gathering, Delves and more",
      "{/rec} addons: every addon by Cobanyte, with CurseForge links",
      "{/rec} reset windows: every window back to its default place and size",
      "Newer version notice: when your guild or group has a newer one",
    },
    changed = {
      "Still needed?: Just for fun, Your call or Replaced for far more items",
      "A bigger database and about 400 more item descriptions",
      "Curator mode: online checks also say your zone and instance",
    },
    fixed = {
      "Done quests show the green check, dailies and weeklies included",
      "Alts' achievement items: checked fully only on that character",
      "Item details: looks, filters and late-loading links read right",
      "Several smaller fixes",
    },
  },
  {
    version = "1.0.2",
    title = "A bigger database and a clearer answer",
    date = "2026-10-06",
    changed = {
      "Database: fishing zones, containers, turn-ins and 50 more notes",
      "Still needed?: a short answer; What it's for has the full story",
      "No longer available: a For column",
      "Guide: names the keys you actually set",
      "Settings: Cancel is now Undo edits",
      "Performance improvements",
      "Many smaller look and wording improvements",
    },
    fixed = {
      "Item details: hovering a cut-off cell shows its whole text",
      "Several smaller bug fixes",
    },
  },
  {
    version = "1.0.1",
    title = "Bigger database, new settings",
    date = "2026-10-01",
    new = {
      "Just for fun: roleplay drinks such as old ale, not Can't tell yet",
    },
    changed = {
      "Database: many more items now say where they come from",
      "Settings: four pages, a preview, key-clash warnings, curator controls",
      "Done: earned achievements and finished parts show a green check mark",
      "Quest chains: item details list the quests, their starters and needs",
      "Item details: why you'd keep an item is said once, not repeated",
      "Old ales and wines are no longer Outdated on English clients",
    },
    fixed = {
      "Still needed? band: no stray semicolon; keeps the achievement name",
      "Item details: no more \"at A vendor\", \"Buys: Buys\", doubled parentheses",
      "Audit panel: Still needed? matches details; fixed \"Not in your bags\"",
      "Quests whose details hadn't loaded yet now show them once they arrive",
    },
  },
  {
    version = "1.0.0",
    title = "The first release",
    date = "2026-10-01",
    new = {
      "Verdicts: what every item you hold is for, and if you still need it",
      "Audit panel: hold {Alt} on an item for its verdict and uses",
      "Item details: {Alt+D} for everything about one item, no website",
      "Recollect Audit: {/rec} lists every stack you hold with its verdict",
      "Waypoints: {Alt+W} to the vendor, treasure or NPC the panel names",
      "Database: vendors, prices, drops, quests, recipes and more",
      "Curator mode: optional, help keep the database right",
    },
  },
}
