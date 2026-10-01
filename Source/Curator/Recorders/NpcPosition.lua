-------------------------------------------------------------------------------
-- Curator recorder: NPC positions (curator spec, "v1 recorders", NPC position)
--
-- On every interaction with an NPC (gossip, a quest window, a trainer) it
-- notes where the player stands and hands it to Compare.Position: near any
-- shipped place (within Compare.POSITION_TOLERANCE on the same map, or
-- Compare.WORLD_TOLERANCE yards in world coordinates on another map) is a
-- confirmation; far from every place on the sighting's map, a conflict
-- carrying the character's quest state (phased NPCs); with no place on that
-- map, an addition. When nothing matched and a place can't be translated,
-- nothing is recorded.
-- An NPC the data has no position for is added only by the recorders that
-- know the NPC matters (Vendor, and Quest for givers and turn-ins): nothing
-- ships an index of every NPC the data mentions yet, and recording every
-- innkeeper would fill the store with facts nobody reads. Vendors are read by the Vendor
-- recorder, which uses the helpers here.
--
-- Only while curator mode may record and out of combat; the position is
-- read in the event, compared in a later frame. A secret GUID or
-- position records nothing, and neither does an NPC that travels with a
-- player (Traveling: a listed ID, a vendor mount ridden, or an NPC the
-- game says a player controls or owns). Client reads go through
-- NpcPosition.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host

local NpcPosition = {}
Curator.Recorders = Curator.Recorders or {}
Curator.Recorders.NpcPosition = NpcPosition

NpcPosition.seams = {
  UnitGUID = function(unit) return UnitGUID(unit) end,
  Map = function() return C_Map.GetBestMapForUnit("player") end,
  Position = function(mapID)
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if position then return position:GetXY() end
  end,
  InCombat = function() return InCombatLockdown() end,
  -- whether the player wears the aura of a mount spell (out of combat a
  -- mount's aura is not secret; Traveling counts a secret answer as riding
  -- and a failed call as not)
  HasAura = function(spellID) return C_UnitAuras.GetPlayerAuraBySpellID(spellID) ~= nil end,
  -- whether the NPC in a unit belongs to a player (a summoned vendor, a pet
  -- with a vendor window, another player's mount passenger): three answers,
  -- returned apart so a secret one is never tested as a boolean. How each
  -- answers for a guardian, a companion or a passenger is the Lab's U23
  Controlled = function(unit)
    return UnitPlayerControlled(unit), UnitIsOtherPlayersPet(unit), UnitIsBattlePetCompanion(unit)
  end,
}

local function Read(name, ...)
  local ok, a, b = pcall(NpcPosition.seams[name], ...)
  if not ok or Host.IsSecret(a) or Host.IsSecret(b) then return nil end
  return a, b
end

-- The NPC ID from a creature GUID ("Creature-0-<server>-<instance>-<zone>-
-- <npcID>-<spawn>"), or nil for a player, an object or anything unreadable
function NpcPosition.NpcID(guid)
  if type(guid) ~= "string" or Host.IsSecret(guid) then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  return tonumber(id)
end

-- The NPC in a unit ("npc" for gossip and trainers, "questnpc" for quest
-- windows), or with no unit named, "npc" then "questnpc"; and the unit it
-- was read from
function NpcPosition.CurrentNpc(unit)
  if unit then
    local npc = NpcPosition.NpcID(Read("UnitGUID", unit))
    return npc, npc and unit or nil
  end
  local npc = NpcPosition.NpcID(Read("UnitGUID", "npc"))
  if npc then return npc, "npc" end
  npc = NpcPosition.NpcID(Read("UnitGUID", "questnpc"))
  return npc, npc and "questnpc" or nil
end

-- Whether a seam's answer says yes: true, or a secret the addon can't test
local function Yes(answer)
  return Host.IsSecret(answer) or answer == true
end

-- Traveling(npc, unit): whether an NPC travels with a player, so its goods
-- and place mean nothing: it is in Const.TRAVELING_VENDORS, the player
-- rides a mount that carries vendors (Const.VENDOR_MOUNT_SPELLS), whose
-- passengers can't all be told by ID, or, with the unit it was read from
-- given, the game says a player controls it or owns it as a pet (the
-- Controlled seam). A secret answer counts as traveling: skipping a visit
-- loses little, recording a passenger misleads (2026-09-27: 34 findings of
-- the Grand Expedition Yak's vendor). A call that fails (no such API)
-- answers nothing, so a broken read never silences every recorder.
function NpcPosition.Traveling(npc, unit)
  local const = Curator.Const
  if npc and const.TRAVELING_VENDORS[npc] then return true end
  for _, spellID in ipairs(const.VENDOR_MOUNT_SPELLS) do
    local ok, riding = pcall(NpcPosition.seams.HasAura, spellID)
    if ok and Yes(riding) then return true end
  end
  if unit then
    local ok, controlled, pet, companion = pcall(NpcPosition.seams.Controlled, unit)
    if ok and (Yes(controlled) or Yes(pet) or Yes(companion)) then return true end
  end
  return false
end

-- Where the player stands: mapID, x, y (0 to 1), or nil
function NpcPosition.Here()
  local mapID = Read("Map")
  if type(mapID) ~= "number" then return nil end
  local x, y = Read("Position", mapID)
  if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
  return mapID, x, y
end

-- Capture(unit): the NPC and where the player stands, read now (they end
-- with the interaction), as { npc, mapID, x, y }, or nil
function NpcPosition.Capture(unit)
  if not Curator.Main.MayRecord() or Read("InCombat") then return nil end
  local npc, from = NpcPosition.CurrentNpc(unit)
  if not npc or NpcPosition.Traveling(npc, from) then return nil end
  local mapID, x, y = NpcPosition.Here()
  if not mapID then return nil end
  return { npc = npc, mapID = mapID, x = x, y = y }
end

-- Commit(capture, addWhenUnshipped, fallback): the comparison, in a later
-- frame; fallback (optional, Host.QuestPlace) is where the quest being
-- handled starts, for a giver the data has no place for
function NpcPosition.Commit(capture, addWhenUnshipped, fallback)
  if not capture then return end
  Curator.Main.Defer(function()
    Curator.Compare.Position(capture.npc, capture.mapID, capture.x, capture.y, Curator.Context.Current(), nil,
      addWhenUnshipped, fallback)
  end)
end

-- Record(addWhenUnshipped, unit): captures the NPC's position now and
-- compares it with the shipped one later; true when something was captured
function NpcPosition.Record(addWhenUnshipped, unit)
  local capture = NpcPosition.Capture(unit)
  NpcPosition.Commit(capture, addWhenUnshipped)
  return capture ~= nil
end

-- QUEST_DETAIL and QUEST_COMPLETE are the Quest recorder's, which adds the
-- giver and turn-in NPC when the data has no place for them
local EVENTS = { "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_PROGRESS", "TRAINER_SHOW" }

local frame = CreateFrame("Frame")
for _, event in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event)
  if Curator.Main.IsScripted() then return end
  local ok, err = pcall(NpcPosition.Record, false)
  if not ok then Host.Log("NPC position recorder %s failed: %s", event, tostring(err)) end
end)
