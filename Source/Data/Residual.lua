-------------------------------------------------------------------------------
-- Data.Residual: items that stay in the bags after their purpose is done and
-- serve no further use (Cobanyte, 2026-09-28). Research per item, recorded in
-- the repo's research notes; each note is in our own words. Read only by
-- the item details window's "Still needed?" box (UI.DetailWindow Detail.Keep),
-- and only once every use Recollect knows for the item is done; never by a
-- check, a verdict or the Tip. Only entries our own data or an in-game check backs ship
-- (2026-09-28: five candidates wait for a check; see the research notes).
--   [itemID] = { note = "why it lingers, our words", checked = "2026-09-28" }
-------------------------------------------------------------------------------
Recollect.Data = Recollect.Data or {}
Recollect.Data.Residual = {
  -- The Honored Warrior's Cache, Zul'Aman (the Ancestral War Bear)
  [259219] = { note = "Opening the Honored Warrior's Cache doesn't take this part, so it stays behind; with the Ancestral War Bear learned, nothing else needs it.", checked = "2026-09-28" },   -- Bear Tooth
  [259220] = { note = "Opening the Honored Warrior's Cache doesn't take this part, so it stays behind; with the Ancestral War Bear learned, nothing else needs it.", checked = "2026-09-28" },   -- Dragonhawk Feather
  [259221] = { note = "Opening the Honored Warrior's Cache doesn't take this part, so it stays behind; with the Ancestral War Bear learned, nothing else needs it.", checked = "2026-09-28" },   -- Eagle Talon
  [259223] = { note = "Opening the Honored Warrior's Cache doesn't take this part, so it stays behind; with the Ancestral War Bear learned, nothing else needs it.", checked = "2026-09-28" },   -- Lynx Claw

  -- Quest leftovers
  [238500] = { note = "Left over from the quest Post-Mortem; once that quest is turned in, the report serves no purpose.", checked = "2026-09-28" },   -- Maella's Report
}
