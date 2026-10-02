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
    version = "1.0.1",
    title = "Bigger database, new settings",
    date = "2026-10-01",
    new = {
      "Just for fun: a roleplay drink such as an old ale says so instead of Can't tell yet",
    },
    changed = {
      "Database: many more items now say where they come from",
      "Settings: four pages, an example of the panel, key-clash warnings and clearer curator controls",
      "Done: an earned achievement or finished part shows green with a check mark",
      "Quest chains: item details list the quests, who starts them and what they ask for",
      "Item details: why you'd keep an item is said once, not repeated",
      "Old ales and wines are no longer Outdated on English clients",
    },
    fixed = {
      "Still needed? band: no stray semicolon, and the reason keeps the achievement's name",
      "Item details: no more \"at A vendor\", \"Buys: Buys\" or doubled parentheses",
      "Audit panel: Still needed? matches the details window, and \"Shown elsewhere\" replaces a wrong \"Not in your bags\"",
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
