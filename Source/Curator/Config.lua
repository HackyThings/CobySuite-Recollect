-------------------------------------------------------------------------------
-- Curator.Config: the curator's own settings (RECOLLECT_CURATOR_CONFIG) and
-- constants. Its settings show as the "Curator" category of Recollect's
-- settings window, which binds them to this config, not Recollect's
-- (curator spec, "The separation boundary").
--
--   curator_enabled  the opt-in: recording on, for every character on the
--                    account (D27); off by default
--   curator_ask      "Ask me before each collection" (D4); off by default
-------------------------------------------------------------------------------
local Curator = Recollect.Curator

Curator.Config = CobySuite_Recollect.Config.New({
  savedVariable = "RECOLLECT_CURATOR_CONFIG",
  options = {
    ENABLED = "curator_enabled",
    ASK = "curator_ask",
  },
  defaults = {
    curator_enabled = false,
    curator_ask = false,
  },
  validate = {
    curator_enabled = { type = "boolean" },
    curator_ask = { type = "boolean" },
  },
  onSet = function(name, old, new)
    if Curator.OnConfigChanged then Curator.OnConfigChanged(name, old, new) end
  end,
})

Curator.OnConfigChanged = function(name, old, new)
  -- work scheduled before curator mode was turned off (or on) is dropped
  if name == "curator_enabled" and Curator.Main then Curator.Main.BumpEpoch() end
  -- turned off: the opt-out dialog (delete findings, how to leave), after
  -- the settings window has finished applying
  if name == "curator_enabled" and old == true and new == false and Curator.OptOutDialog then
    C_Timer.After(0, Curator.OptOutDialog.Show)
  end
  Curator.Host.NotifyConfigChanged(name)
end

-- Constants (curator spec: Roles and the community, Protocol, Footprint)
Curator.Const = {
  CLUB_NAME = "Recollect Curators",
  STREAM_NAME = "General",  -- the community's stream: chat, and the hidden curator traffic (Cobanyte, 2026-09-26)
  CLUB_ID = 503127671,     -- the "Recollect Curators" community (a number in game; compared as text); nil: found by name
  TICKET_ID = "jKPlgr0hzZD", -- the public invite ticket: never expires, unlimited uses (made 2026-09-26)
  PREFIX = "RecollectCur",  -- at most 16 bytes
  CAP_BYTES = 1024 * 1024, -- the recorder fields of RECOLLECT_CURATOR_DB (D17)
  AWAITING_DAYS = 30,      -- acknowledged collections not confirmed saved are dropped after this
  RECEIVED_DAYS = 30,      -- the author's received list is pruned after this
  -- Vendors that travel with a player, riding on a mount (the Grand Expedition
  -- Yak's reagent vendor, 62822, seen in Silvermoon at two places, 2026-09-27):
  -- their goods and positions are nobody's place to shop, so the vendor and
  -- NPC position recorders skip them. /recollect-data drops archived findings
  -- of the same IDs (curator_intake.TRAVELING_VENDORS); keep the two alike.
  TRAVELING_VENDORS = { [62822] = true },
  -- The mounts that carry vendors (spell IDs from AllTheThings' MountDB):
  -- while the player rides one, the vendor and NPC position recorders skip
  -- the visit, whichever vendor it is, since its passengers' IDs are not all
  -- known. Traveler's Tundra Mammoth (61425, 61447), Grand Expedition Yak
  -- (122708), Mighty Caravan Brutosaur (264058), Trader's Gilded Brutosaur
  -- (465235)
  VENDOR_MOUNT_SPELLS = { 61425, 61447, 122708, 264058, 465235 },
}
