-------------------------------------------------------------------------------
-- Curator recorder: NPC positions (curator spec, "v1 recorders", NPC position)
--
-- On every interaction with an NPC (gossip, a quest window, a trainer) it
-- notes where the player stands and hands it to Compare.Position: near the
-- shipped position (within Compare.POSITION_TOLERANCE) is a confirmation,
-- far from it a conflict carrying the character's quest state (phased NPCs).
-- An NPC the data has no position for is added only by the recorders that
-- know the NPC matters (Vendor, and Quest for givers and turn-ins): nothing
-- ships an index of every NPC the data mentions yet, and recording every
-- innkeeper would fill the store with facts nobody reads. Vendors are read by the Vendor
-- recorder, which uses the helpers here.
--
-- Only while curator mode may record and out of combat; the position is
-- read in the event, compared in a later frame. A secret GUID or
-- position records nothing. Client reads go through NpcPosition.seams.
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
  -- mount's aura is not secret; a secret or failed read counts as riding)
  HasAura = function(spellID) return C_UnitAuras.GetPlayerAuraBySpellID(spellID) ~= nil end,
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
-- windows), or with no unit named, "npc" then "questnpc"
function NpcPosition.CurrentNpc(unit)
  if unit then return NpcPosition.NpcID(Read("UnitGUID", unit)) end
  return NpcPosition.NpcID(Read("UnitGUID", "npc")) or NpcPosition.NpcID(Read("UnitGUID", "questnpc"))
end

-- Whether an NPC travels with a player, so its goods and place mean nothing
-- (Const.TRAVELING_VENDORS), or the player rides a mount that carries
-- vendors (Const.VENDOR_MOUNT_SPELLS), whose passengers can't all be told by
-- ID. A secret answer counts as riding: skipping a visit loses little,
-- recording a passenger misleads (2026-09-27: 34 findings of the Grand
-- Expedition Yak's vendor). A call that fails (no such API) answers nothing.
function NpcPosition.Traveling(npc)
  local const = Curator.Const
  if npc and const.TRAVELING_VENDORS[npc] then return true end
  for _, spellID in ipairs(const.VENDOR_MOUNT_SPELLS) do
    local ok, riding = pcall(NpcPosition.seams.HasAura, spellID)
    if ok and (Host.IsSecret(riding) or riding == true) then return true end
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
  local npc = NpcPosition.CurrentNpc(unit)
  if not npc or NpcPosition.Traveling(npc) then return nil end
  local mapID, x, y = NpcPosition.Here()
  if not mapID then return nil end
  return { npc = npc, mapID = mapID, x = x, y = y }
end

-- Commit(capture, addWhenUnshipped): the comparison, in a later frame
function NpcPosition.Commit(capture, addWhenUnshipped)
  if not capture then return end
  Curator.Main.Defer(function()
    Curator.Compare.Position(capture.npc, capture.mapID, capture.x, capture.y, Curator.Context.Current(), nil,
      addWhenUnshipped)
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
