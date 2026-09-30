-------------------------------------------------------------------------------
-- Data.Notes: guide notes, what a guide says an item is for when no data
-- source Recollect reads explains it (Cobanyte, 2026-09-25)
--
-- Some items no client call, no dump record and no AllTheThings relation
-- explains: Latent Arcana charges the Runestones of Eversong Woods, and only
-- a guide says so. A note holds what the guide says, in Recollect's own
-- words, and how to confirm it in game. The pages it was researched on are
-- kept in the repo's research notes, never here: a shipped file names no
-- website as a source (Cobanyte, 2026-09-28).
--
--   {
--     items = { itemID, ... },          -- the items the note is about
--     text = "What it's for",           -- short; never the item's own tooltip
--                                       -- text (Use, Equip or flavor lines):
--                                       -- what the tooltip doesn't say
--     howMany = "3 per charge",         -- optional: how many a use takes
--     where = "Eversong Woods: ...",    -- optional: where it's used
--     from = "Saltheril's Soiree ...",  -- optional: where it comes from
--     achievement = achievementID,      -- optional: an achievement the note
--                                       -- names, whose progress is read live
--     quest = questID,                  -- optional: a quest the note names,
--                                       -- whose state is read live
--     confirmInGame = "...",            -- how to confirm it in game
--     confirmed = false,                -- the in-game check behind it: false
--                                       -- until then, else "2026-..., build ...: ..."
--     researched = "2026-09-25",        -- when it was researched
--   },
--
-- A note is informational only: the panel and the details window show it
-- labeled as a guide note and, until confirmed, "not confirmed in game yet".
-- It never changes a verdict, confirmed or not (Data/Uses.lua is where a
-- confirmed use that decides a verdict ships). Facts.Notes reads this table;
-- an entry without items or text is ignored.
-- Every note is our own wording, and nothing is copied from another addon
-- or a website. A note says what the item is used for, never
-- what it doesn't do, and never restates its own tooltip (Cobanyte,
-- 2026-09-25: the Key to the City's "no longer does anything", the Resilient
-- Seed's "warbound" and the Spare Toolbox's "unique" were taken out, and the
-- Shards of Domination note, whose only page was a news post rather than a
-- forum thread, was dropped).
-------------------------------------------------------------------------------
Recollect.Data = Recollect.Data or {}

Recollect.Data.Notes = {
  {
    items = { 242241 },   -- Latent Arcana
    text = "Charges the five Runestones of Eversong Woods (the Saltheril's Soiree event): a full Runestone starts a defense "
      .. "against a strong boss, and defending all five earns the achievement Runestone Rush.",
    howMany = "3 per charge; each charge fills a Runestone's bar by 3%",
    where = "Eversong Woods: Elrendar River (47.4, 58.6), Ath'ran (38.4, 55.5), Dawnstar Spire (61.8, 61.8), "
      .. "Sanctum of the Moon (41.1, 73.8), Sunstrider Isle (40.5, 13.6)",
    from = "Saltheril's Soiree dailies and small treasures in Eversong Woods, once the Soiree is unlocked",
    achievement = 61961,
    confirmInGame = "Open the achievement Runestone Rush (61961): 5 Runestone criteria. At a Runestone, one charge takes 3 "
      .. "Latent Arcana.",
    confirmed = false,
    researched = "2026-09-25",
  },
  {
    items = { 270274 },   -- Home-Grown Wax
    text = "A resource of the neighborhood endeavor Candle Culture while it runs: contributed to its projects, donated to "
      .. "the community chest, and poured into the candle cauldron before Scally's candle workshops. The endeavor's tasks "
      .. "earn Community Coupons, which buy decor from Timicky.",
    where = "Your housing neighborhood (Founder's Point or Razorwind Shores), when its endeavor is Candle Culture",
    from = "Wax deposits in the neighborhood",
    confirmInGame = "In the neighborhood, open the Endeavors tab while Candle Culture runs: its wax tasks name Home-Grown Wax "
      .. "with how many each takes.",
    confirmed = false,
    researched = "2026-09-25",
  },
  {
    items = { 226120 },   -- Deployable Battle Supplies
    text = "Players drop it at world bosses, outdoor events and outside Delves so everyone nearby gets the buff. It shares "
      .. "its 1-hour cooldown with the other deployables (the Recovery Keg and the Wind-Wrangling Spire).",
    from = "The War Within Delves",
    confirmInGame = "Use one outdoors: nearby players get the stat buff, and a Deployable Recovery Keg shows the shared cooldown.",
    confirmed = false,
    researched = "2026-09-25",
  },
  {
    items = { 226132 },   -- Deployable Recovery Keg
    text = "Players drop it at world bosses and outdoor events to heal everyone nearby. It shares its 1-hour cooldown with "
      .. "the other deployables (Battle Supplies and the Wind-Wrangling Spire).",
    from = "The War Within Delves",
    confirmInGame = "Use one outdoors: nearby players are healed to full, and Deployable Battle Supplies shows the shared "
      .. "cooldown.",
    confirmed = false,
    researched = "2026-09-25",
  },
  {
    items = { 34076 },   -- Fish Bladder
    text = "Given for the Howling Fjord quest \"Forgotten Treasure\", where you dive to Black Conrad's sunken fleet.",
    where = "Howling Fjord: Handsome Terry gives the quest at Scalawag Point (35, 81)",
    confirmInGame = "Use it: 3 minutes of water breathing, and its charges drop from 3 to 2.",
    confirmed = false,
    researched = "2026-09-25",
  },
  {
    items = { 246771 },   -- Radiant Echo
    text = "Starts a Worldsoul Memory in Khaz Algar in Radiant Echo mode, a solo 5-minute fight whose rewards are The War "
      .. "Within Season 3 Valorstones and Coffer Keys; 5 saved open a mode that spends them together.",
    howMany = "1 per run; 5 for the Many Radiant Echoes mode",
    where = "A Worldsoul Memory in Khaz Algar",
    confirmInGame = "At a Worldsoul Memory in Khaz Algar, talk to the event: a Radiant Echo option shows, or doesn't once "
      .. "Season 3's mode is gone.",
    confirmed = false,
    researched = "2026-09-25",
  },
  {
    items = { 269586 },   -- Emergency Soul Link
    text = "Anyone can use it, not only engineers, so raid and Mythic+ groups want it for a battle resurrection.",
    howMany = "1 per resurrection",
    from = "Crafted by Midnight Engineering; also sold on the Auction House",
    confirmInGame = "Hover it: its Use line describes bringing a dead party member back in combat.",
    confirmed = false,
    researched = "2026-09-25",
  },
  {
    items = { 267051 },   -- Dark Particle
    text = "Traded at Maren Silverwing in Silvermoon City: 100 buy a Field Accolade Pouch, and Field Accolades buy Champion "
      .. "and Hero catch-up gear. The vendor beside her takes 150 for a Bulging Field Pouch of appearances.",
    howMany = "100 per Field Accolade Pouch; 150 per Bulging Field Pouch",
    where = "Silvermoon City, the Ritual Site hub (48.2, 49.6)",
    from = "Void Assault events and Ritual Sites",
    confirmInGame = "Visit Maren Silverwing in Silvermoon City: the Field Accolade Pouch costs 100 Dark Particle.",
    confirmed = false,
    researched = "2026-09-25",
  },
  {
    items = { 273000 },   -- Corrosive Soul
    text = "Given to Er'inye for Corrosive Coins, which buy appearance ensembles and decor from the vendor beside her and "
      .. "pay for Altar of Corrosion upgrades (Corrode Spirit).",
    howMany = "1 per Satchel of Corrosive Coins",
    where = "Er'inye, in front of the Altar of Corrosion, Vaults of Atal'Utek (51.1, 62.7)",
    confirmInGame = "Talk to Er'inye at the Altar of Corrosion: the Satchel of Corrosive Coins costs 1 Corrosive Soul.",
    confirmed = false,
    researched = "2026-09-25",
  },
  {
    items = { 280005 },   -- Dispelling Charm
    text = "Opens Jin'tal's Reliquary in the Profaned Mausoleum, which holds the Lost Med'jai Amulet. The amulet starts "
      .. "\"The Protection of the Med'jai\", which unlocks a hidden Altar of Corrosion choice (Surge Seniority or Spiritual "
      .. "Succession).",
    where = "Profaned Mausoleum, Vaults of Atal'Utek (36.6, 25.3)",
    from = "High Priest Jin'tal, in the Vault of Restless Brothers",
    quest = 97661,
    confirmInGame = "/dump C_QuestLog.IsQuestFlaggedCompleted(97661): false means the charm is still needed; the note's "
      .. "quest state should match.",
    confirmed = false,
    researched = "2026-09-25",
  },
  {
    items = { 12382 },   -- Key to the City
    text = "In Classic it opened Stratholme's inner gates: the Eastwall Gate and the gate between Festival Lane and King's "
      .. "Square.",
    where = "Stratholme, Eastern Plaguelands",
    confirmInGame = "In Stratholme, walk to the Eastwall Gate with the key in your bags and see whether the gate asks for it.",
    confirmed = false,
    researched = "2026-09-25",
  },
  {
    items = { 192466 },   -- Puzzling Cartel Dinar
    text = "A token of Shadowlands Season 4, the Fated raid season: each one bought one Fated raid item (a trinket, a weapon "
      .. "or another special item) from the brokers near the Great Vault in Oribos, three per season.",
    howMany = "1 per item",
    where = "Oribos, near the Great Vault",
    from = "A 3-part questline you got by entering a Fated raid",
    confirmInGame = "In Oribos, look near the Great Vault: no Dinar broker should be there.",
    confirmed = false,
    researched = "2026-09-25",
  },
  {
    items = { 198400 },   -- Lucky Horseshoe
    text = "One of the lucky items of the Ratts' Revenge secret (the Incognitro felcycle): its \"Feeling Lucky?\" slot "
      .. "machines pay out only when you have five different lucky items or buffs, out of 13.",
    howMany = "1; it counts as one of the five",
    from = "Farrier Roscha in the Ohn'ahran Plains",
    confirmInGame = "Open the Mount Journal: whether Incognitro, the Indecipherable Felcycle is collected says whether you "
      .. "still need luck for it.",
    confirmed = false,
    researched = "2026-09-25",
  },
  {
    items = { 269010 },   -- Essence of Lumber
    text = "Traded for housing lumber: one Essence buys a stack of 20 lumber of any of the 12 expansions' kinds from the "
      .. "neighborhood lumber vendors.",
    howMany = "1 per stack of 20 lumber",
    where = "Lestia Goldenstrike in Founder's Point and Xiz'ro in Razorwind Shores, near the town-center contractors "
      .. "(as of early 2026)",
    from = "Rarely from harvesting lumber, and one from each housing weekly quest",
    confirmInGame = "Open Lestia Goldenstrike's or Xiz'ro's vendor window: a stack of lumber costs 1 Essence of Lumber.",
    confirmed = false,
    researched = "2026-09-25",
  },
  {
    items = { 271094 },   -- Lady Darkglen's Device
    text = "The quest item of \"Raising Magical Alarms\": you use it at spots inside a Ritual Site to monitor its magical "
      .. "energies, and finishing the quest unlocks a Ritual Site challenge.",
    where = "Inside a Ritual Site; it works only close to the quest's spots",
    from = "Lady Darkglen, top level of the Bazaar in Silvermoon City (47.7, 49.7), after a Tier 4 Ritual Site",
    quest = 95549,
    confirmInGame = "/dump C_QuestLog.IsQuestFlaggedCompleted(95549): true means the quest is done; the note's quest state "
      .. "should match.",
    confirmed = false,
    researched = "2026-09-25",
  },
  {
    items = { 166971 },   -- Empty Energy Cell
    text = "Filled at Mechagon's Charging Station: contributing an Energy Cell to the station fills your empty cells. The "
      .. "station is one of Mechagon's rotating projects and isn't up every day; access is said to cost 250 Spare Parts "
      .. "and one charged Energy Cell for two hours.",
    where = "The Charging Station in Mechagon, when it is the day's project",
    confirmInGame = "On a day the Charging Station is up in Mechagon, talk to it with Empty Energy Cells in your bags: they "
      .. "become Energy Cells.",
    confirmed = false,
    researched = "2026-09-25",
  },
}
