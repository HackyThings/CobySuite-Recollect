-------------------------------------------------------------------------------
-- Data.Hints: curator hints, metadata only curator mode reads (IDs only;
-- /recollect-data rebuilds this file with Relations.lua and Vendors.lua, and all
-- three carry one dataVersion and format, Facts/DataVersion.lua).
--
-- unseen: facts researched and kept although no curator has seen them
-- (verified-unseen), so curators record no "not seen" for them:
--   unseen[<letter>] = { [<source ID>] = "<item IDs ascending, comma separated>" }
-- the letter a Relations code's (Facts/Relations.lua): v, vendor <source> sells
-- those items; c, creature <source> drops them. Empty until curator findings
-- are reviewed.
-------------------------------------------------------------------------------
Recollect.Data.Hints = {
  dataVersion = "2026.09.28.3",
  format = 5,
  unseen = {
  },
}
