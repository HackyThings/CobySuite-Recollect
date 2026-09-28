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
