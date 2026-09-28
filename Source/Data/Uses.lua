-------------------------------------------------------------------------------
-- Data.Uses: item uses the game cannot tell by itself, shipped with Recollect
--
-- No client call says that a Bear Tooth belongs to a Zul'Aman secret, or that
-- three particular Dragonflight rings buy a mount from the Tuskarr. Those
-- links are listed here. Whether the use is finished is still read live from
-- the game: each entry names a target whose state the client reports (a
-- mount, toy or pet collected, an achievement earned, a quest flagged).
--
--   {
--     key = "unique_key",
--     name = "What the player recognizes",   -- shown in the tooltip, after the kind's words:
--     kind = "secret",                         --   secret      "Part of the secret <name>"
--                                              --   cache       "One of the keys to <name>"
--                                              --   exchange    "One of the items that buy <name>"
--                                              --   collection  "Part of the collection <name>"
--     parts = { [itemID] = count },            -- the items it uses, and how many it needs of each
--     target = { mount = mountID }             -- or { toy = itemID }, { pet = speciesID },
--                                              -- { achievement = achievementID },
--                                              -- { quest = questID, account = true }
--     reward = "the Ancestral War Bear",       -- what finishing it gives, for the tooltip
--     rewardItem = itemID,                     -- the item that teaches the target (checked in game)
--     vendor = npcID, sold = itemID,           -- exchanges only: who sells the reward, and
--                                              -- the item they sell (checked in game)
--     mention = "text",                        -- text every part's own tooltip shows (English
--                                              -- client; read only by the in-game check)
--     confirmed = "2026-09-23, build 69933: ...",  -- the in-game check behind the entry
--   },
--
-- Every entry must be confirmed in game before it ships: the Lab's "uses"
-- probe reads the target's name and state, that the reward item teaches the
-- target, every part's name and tooltip, and for an exchange compares the
-- parts with the vendor's own cost, recorded when its window opens (the
-- player need not hold the parts). An entry without a confirmed line is
-- ignored by the checks and listed by the Lab as pending.
-- Every entry is our own wording, confirmed in game; nothing is copied from
-- another addon or a website.
-------------------------------------------------------------------------------
Recollect.Data = Recollect.Data or {}

Recollect.Data.Uses = {
  {
    key = "honored_warriors_cache",
    name = "the Honored Warrior's Cache in Zul'Aman",
    kind = "cache",
    parts = {
      [259219] = 1,   -- Bear Tooth (Nalorakk's Chosen)
      [259220] = 1,   -- Dragonhawk Feather (Jan'alai's Chosen)
      [259221] = 1,   -- Eagle Talon (Akil'zon's Chosen)
      [259223] = 1,   -- Lynx Claw (Halazzi's Chosen)
    },
    target = { mount = 2778 },
    reward = "the Ancestral War Bear",
    rewardItem = 257223,
    mention = "Honored Warrior's Cache",
    confirmed = "2026-09-23, build 69933: each part's tooltip reads Key to the Honored Warrior's Cache; "
      .. "the mount journal gives mount 2778 Ancestral War Bear the source Treasure: Honored Warrior's Cache, "
      .. "Zul'Aman; item 257223 teaches mount 2778",
  },
  {
    key = "ivory_traders_ottuk",
    name = "the Ivory Trader's Ottuk from Tattukiaka in Iskaara",
    kind = "exchange",
    parts = {
      [193633] = 1,   -- Unstable Arcane Loop (The Azure Vault)
      [193696] = 1,   -- Thunderous Downburst Ring (The Nokhud Offensive)
      [193708] = 1,   -- Platinum Star Band (Algeth'ar Academy)
    },
    target = { mount = 1658 },
    reward = "the Ivory Trader's Ottuk",
    vendor = 199448,
    sold = 198873,
    mention = "Tattukiaka",
    confirmed = "2026-09-23, build 69933: the mount journal gives mount 1658 the source Vendor: Tattukiaka, "
      .. "Cost: 1 each of items 193696, 193633 and 193708; each part's tooltip names Tattukiaka; "
      .. "item 198873 teaches mount 1658",
  },
  {
    key = "iskaara_traders_ottuk",
    name = "the Iskaara Trader's Ottuk from Tattukiaka in Iskaara",
    kind = "exchange",
    parts = {
      [195496] = 1,   -- Eye of the Vengeful Hurricane (Vault of the Incarnates)
      [195502] = 1,   -- Terros's Captive Core (Vault of the Incarnates)
    },
    target = { mount = 1546 },
    reward = "the Iskaara Trader's Ottuk",
    vendor = 199448,
    sold = 198871,
    mention = "Tattukiaka",
    confirmed = "2026-09-23, build 69933: the mount journal gives mount 1546 the source Vendor: Tattukiaka, "
      .. "Cost: 1 each of items 195502 and 195496; each part's tooltip names Tattukiaka; "
      .. "item 198871 teaches mount 1546",
  },
}
