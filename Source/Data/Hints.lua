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
--
-- settled: sources the author settled after a trusted curator confirmed them, so a visit that
-- matches in full sends nothing; rounds: sources where a difference started
-- another round of confirmations, so every curator may confirm once more:
--   settled["<stamp source>"] = round; rounds["<stamp source>"] = round
-- quiet: findings the author checked and turned down, or the review drops by
-- rule (spec D38), which curators record no more:
--   quiet["<fact>"] = true for every value, or = { ["<value>"] = true }
-------------------------------------------------------------------------------
Recollect.Data.Hints = {
  dataVersion = "2026.09.30.1",
  format = 8,
  unseen = {
  },
  settled = {
  },
  rounds = {
  },
  quiet = {
    ["R:171:471003"] = true,
    ["R:182:471009"] = true,
    ["R:186:471013"] = true,
    ["R:197:471015"] = true,
    ["R:382994"] = true,
    ["ob:369898:i:186201"] = true,
    ["ob:375886:i:188263"] = true,
    ["ob:375886:i:189544"] = true,
    ["ob:375886:i:189806"] = true,
    ["ob:375886:i:189832"] = true,
    ["ob:375886:i:191019"] = true,
    ["ob:375886:i:191020"] = true,
    ["ob:375901:i:189544"] = true,
    ["ob:375901:i:189838"] = true,
    ["ob:375901:i:189839"] = true,
    ["ob:375901:i:189840"] = true,
    ["ob:375901:i:190959"] = true,
    ["ob:375901:i:191004"] = true,
    ["ob:375901:i:191005"] = true,
    ["ob:642087:i:251285"] = true,
    ["p:227774"] = true,
    ["p:62822"] = true,
  },
}
