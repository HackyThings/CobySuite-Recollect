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
  -- turned on: the settings text the curator just read says bags and banks
  -- are included, so their sweeps need no chat line (Recorders/NoInfo.lua)
  local NoInfo = Curator.Recorders and Curator.Recorders.NoInfo
  if name == "curator_enabled" and new == true and NoInfo then NoInfo.OptedIn() end
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
  STREAM_NAME = "General",  -- the community's stream: curators' chat (Cobanyte, 2026-09-26); the traffic goes by whisper
  CLUB_ID = 503127671,     -- the "Recollect Curators" community (a number in game; compared as text); nil: found by name
  TICKET_ID = "jKPlgr0hzZD", -- the public invite ticket: never expires, unlimited uses (made 2026-09-26)
  PREFIX = "RecollectCur",  -- at most 16 bytes
  -- The old hidden channel (0.0.1c) the curator traffic went on until it
  -- moved to whispers (2026-09-28): the receiver still reads it from 0.0.1c
  -- clients, and UI/LeaveOldChannel.lua asks a character still in it to
  -- leave.
  CHANNEL_NAME = "RecollectCurators",
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
  -- Items with no information (Recorders/NoInfo.lua, spec
  -- Recollect-No-Info-Items-Spec-2026-09-28): at most NOINFO_CAP live ni:
  -- records (about 135 KB of the 1 MB); NOINFO_REPORTED_CAP delivered marks
  -- kept per data version; NOINFO_PLACES named places per item (a fourth
  -- counts on the newest); NOINFO_SLICE items a sweep job compares;
  -- NOINFO_PENDING items waiting for their data at once, each for at most
  -- NOINFO_PENDING_SECONDS
  NOINFO_CAP = 1500,
  NOINFO_REPORTED_CAP = 4000,
  NOINFO_PLACES = 3,
  NOINFO_SLICE = 40,
  NOINFO_PENDING = 60,
  NOINFO_PENDING_SECONDS = 30,
}
