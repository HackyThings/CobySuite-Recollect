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
  {
    items = { 271424 },   -- Diver's Key Fragment
    text = "Three fragments combine into a Diver's Key for the Sunken Diver's Chest, which holds a mask toy.",
    howMany = "3 per key",
    where = "The Coiled Isle: the chest at 65.4, 5.6",
    from = "Glittering Grouper Brinetail along the north shore of the Coiled Isle (61.2, 14.0; 63.6, 13.2; 65.4, 5.6; 67.2, 5.0)",
    confirmInGame = "Combine three fragments, then open the Sunken Diver's Chest with the key and check its loot.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 274481 },   -- Keepsake Corruption
    text = "Paid to the Cursed Keepsake: its quest takes it, and further copies of its decoration cost 100 each.",
    howMany = "100 for each further decoration",
    where = "The Cursed Keepsake in your housing neighborhood",
    from = "Enemies in the Cursed Keepsake scenario; those defeated over its floor pools give more",
    quest = 98204,
    confirmInGame = "In the scenario, compare what enemies give on and off a floor pool, then check the quest and the decoration's price.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 276547 },   -- Afflicted Soul
    text = "Use it before accepting a Nightmare Prey hunt for a faster hunt and an extra Preyhunter's Champion Chest at its end; in a group, each hunter uses their own.",
    from = "Heavy Trunks in Bountiful Delves of tier 6 or higher, once your Preyhunter's Journey reaches rank 4",
    confirmInGame = "With no hunt active, use one Soul, accept a Nightmare hunt, and check the hunt's progress and the extra chest.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 245929, 245931, 245933 },   -- Fleeting flasks
    text = "Taken from a Midnight flask cauldron an alchemist places; which flasks it offers follows the recipes its makers know.",
    from = "A flask cauldron (item 241318) placed by an alchemist",
    confirmInGame = "Take each flask from a placed cauldron and check its item.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 245902, 245916, 245898 },   -- Fleeting potions
    text = "Taken from a Midnight potion cauldron an alchemist places; which potions it offers follows the recipes its makers know.",
    from = "A potion cauldron (item 241284) placed by an alchemist",
    confirmInGame = "Take each potion from a placed cauldron and check its item.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 239142, 240995 },   -- Bottle of Mysterious Wisdom, Fortuitous Satchel
    text = "Rewards of the Winds of Mysterious Fortune leveling event.",
    from = "Mysterious Satchels (item 235054) during Winds of Mysterious Fortune",
    confirmInGame = "Open the event's satchels and check for these items.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 116403 },   -- Frightened Bush Chicken
    text = "Teaches a companion pet, found in Pilgrim's Bounty's seasonal reward package.",
    from = "The Pilgrim's Bounty reward container (item 116404)",
    confirmInGame = "Open the reward container during Pilgrim's Bounty and check for this pet.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 117393 },   -- Keg-Shaped Treasure Chest
    text = "Coren Direbrew's Brewfest reward chest; it can hold mounts, a toy and other Brewfest loot.",
    from = "Defeating Coren Direbrew in the queued Brewfest encounter",
    confirmInGame = "During Brewfest, finish the Coren Direbrew encounter and open the chest.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 118391 },   -- Worm Supreme
    text = "A Draenor fishing lure.",
    from = "Draenor fishing, and the Lunarfall and Frostdeep Cavedwellers at garrison fishing spots",
    confirmInGame = "Fish in Draenor or defeat a garrison cavedweller and check its loot for the lure.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 33820 },   -- Weather-Beaten Fishing Hat
    text = "A fishing hat with a reusable lure.",
    from = "Fishing daily reward bags",
    confirmInGame = "Open fishing daily reward bags and check for the hat; use its lure.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 140999, 141000 },   -- Replica Lion's Fang, Replica Lion's Heart
    text = "Alliance replica weapon appearances from the Warcraft movie promotion.",
    from = "The promotion's Alliance appearance package (item 140997)",
    confirmInGame = "Check the appearance in your collection.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 141001, 141002 },   -- Replica Blood Guard's Cleaver, Replica Staff of Gul'dan
    text = "Horde replica weapon appearances from the Warcraft movie promotion.",
    from = "The promotion's Horde appearance package (item 140998)",
    confirmInGame = "Check the appearance in your collection.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 44124 },   -- Peculiar Key
    text = "A step of the Felcycle secret: with the Torch of Pyrreth, it opens the way into the puzzle scenario at the Karazhan Catacombs.",
    where = "The Karazhan Catacombs entrance in Deadwind Pass",
    confirmInGame = "Put the key together from items 228938 and 228941, then use the torch at the entrance.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 53156 },   -- Key of Shadows
    text = "A step of the Felcycle secret: it opens the two doors beside the red-button room in the puzzle scenario.",
    from = "The Ny'alotha Obelisk above the Seat of Knowledge in the Vale of Eternal Blossoms",
    confirmInGame = "Get the key at the obelisk and try it on both doors in the scenario.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 228965 },   -- Astral Key
    text = "A step of the Felcycle secret: it opens the Astral Chest, which holds the goggles for the next stage.",
    where = "The room left of the red button, reached with the Key of Shadows",
    from = "Fishing in the bowl on that room's left bookshelf",
    confirmInGame = "Fish the key from the bowl and use it on the Astral Chest (object 466393).",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 228300 },   -- Sun-Baked Ransom Note
    text = "A clue in the anniversary detective hunt: Search the sunken gnome building off the Tanaris coast, by the bed on its upper floor.",
    where = "Tanaris: 69.2, 68.6",
    achievement = 40979,
    quest = 84426,
    confirmInGame = "Follow the clue to its spot and check that the crate or next clue is there.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 228321 },   -- Dirt-Caked Ransom Note
    text = "A clue in the anniversary detective hunt: In the Karazhan crypt, cross the pool of hanging bodies and search the back left of the next room.",
    where = "Deadwind Pass: the crypt entrance at 39.8, 73.1",
    achievement = 40979,
    quest = 84470,
    confirmInGame = "Follow the clue to its spot and check that the crate or next clue is there.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 228694 },   -- Damp Ransom Note
    text = "A clue in the anniversary detective hunt: Buy a Clam Digger from Nikto in Zuldazar and hand it to Gerald nearby.",
    where = "Zuldazar: Nikto at 54.3, 54.5, Gerald at 54.2, 54.2",
    achievement = 40979,
    quest = 83794,
    confirmInGame = "Follow the clue to its spot and check that the crate or next clue is there.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 228766 },   -- Sandy Ransom Note
    text = "A clue in the anniversary detective hunt: Search behind the pipes in the underwater tunnel of Thousand Needles for the next receipt.",
    where = "Thousand Needles: the tunnel at 66.3, 86.2",
    achievement = 40979,
    quest = 84624,
    confirmInGame = "Follow the clue to its spot and check that the crate or next clue is there.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 228769 },   -- Surprisingly Pristine Ransom Note
    text = "A clue in the anniversary detective hunt: A dog companion digs up bones behind Andrestrasz's cave; bring them to the Unmarked Grave in Stormheim.",
    where = "Stormheim: the grave at 37.3, 47.7",
    achievement = 40979,
    quest = 84625,
    confirmInGame = "Follow the clue to its spot and check that the crate or next clue is there.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 228977 },   -- Burnt Ransom Note
    text = "A clue in the anniversary detective hunt: Search the trampoline area in Mount Hyjal.",
    where = "Mount Hyjal: 13.6, 33.5",
    achievement = 40979,
    quest = 84767,
    confirmInGame = "Follow the clue to its spot and check that the crate or next clue is there.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 228985 },   -- Shiny Ransom Note
    text = "A clue in the anniversary detective hunt: Search near Oshu'gun in Outland's Nagrand.",
    where = "Nagrand (Outland): 35.3, 74.7",
    achievement = 40979,
    quest = 84773,
    confirmInGame = "Follow the clue to its spot and check that the crate or next clue is there.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 229369 },   -- Ghostly Ransom Note
    text = "A clue in the anniversary detective hunt: Search atop the Seat of the Primus, behind the portal on the right.",
    where = "Maldraxxus: 50.0, 73.8",
    achievement = 40979,
    quest = 84909,
    confirmInGame = "Follow the clue to its spot and check that the crate or next clue is there.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 178675 },   -- Dream Catcher
    text = "Lets you into Night Mare's realm, where the rare that drops the Swift Gloomhoof mount waits.",
    where = "Ardenweald: behind Hibernal Hollow, around 62.5, 51.6",
    from = "Ysera, once you bring her a Repaired Soulweb",
    confirmInGame = "Use it behind Hibernal Hollow and check that Night Mare appears.",
    confirmed = false,
    researched = "2026-10-05",
  },
  {
    items = { 265361 },   -- Pollinic Incense
    text = "Placed at marked flower spots to finish tasks of the Niffen neighborhood endeavor.",
    where = "The Common in a housing neighborhood while its Niffen endeavor runs",
    from = "The incense pot on a traveling cart, once Incense Materials are added",
    confirmInGame = "Fill the cart's incense pot, then place incense at a marked flower spot and check the endeavor's credit.",
    confirmed = false,
    researched = "2026-10-05",
  },
}
