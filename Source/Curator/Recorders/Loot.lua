-------------------------------------------------------------------------------
-- Curator recorder: loot (curator spec, "v1 recorders": loot, containers,
-- pickpocket, salvage; research note I sections 2 and 14)
--
-- Read once per loot window at LOOT_READY (it can fire twice for one window,
-- U18: a second one before LOOT_CLOSED is ignored; slot data is gone once a
-- slot is looted, so nothing waits for LOOT_OPENED). Each item slot (greys,
-- quality 0, skipped; money and currencies not recorded yet) is filed under
-- the sources GetLootSourceInfo gives for it, in pairs of GUID and count:
--   Creature or Vehicle   a drop; a pickpocket when it is the living target
--                         and the player can attack it (the Pick Pocket
--                         spell ID is unconfirmed, U13); a living target the
--                         player can't attack (a boss that surrendered, a
--                         friendly NPC) is no guess and records nothing; a
--                         cast just before is kept beside the record, so the
--                         pipeline can set skinning apart
--   GameObject            a chest, node or other object
--   Item                  a container, resolved with C_Item.GetItemIDByGUID
--                         (U11; unresolved records nothing), or a disenchant
--                         when Disenchant (13262) was cast just before and
--                         the item is a weapon, armor or profession gear (a
--                         container opened right after a disenchant is still
--                         a container; a class that can't be read, or a
--                         gem, which may be a relic, then records nothing)
--   fishing               IsFishingLoot(): the player's map
-- A secret or unreadable source records nothing for its slot (U1: sources
-- may be secret in instances; no "not seen" comes from loot anyway).
-- Every window keeps the player's map and the zone it lies in (ZoneMaps),
-- so a creature's copy of that zone's drop is no finding. A Mythic+
-- keystone run's Challenger's Cache records like any object: its context
-- block carries the difficulty (8), and /recollect-data decides item by
-- item, keeping what only the cache holds (2026-09-28).
-- Salvage recipes (milling, prospecting) are not loot windows; they wait on
-- U5. Compare.Loot records each source.
--
-- Only while curator mode may record, and never while a test run scripts
-- the client. Client reads go through Loot.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Bags = Curator.Recorders.Bags

local Loot = {}
Curator.Recorders.Loot = Loot

Loot.DISENCHANT = 13262
local ITEM_SLOT = 1   -- Enum.LootSlotType.Item
-- What Disenchant takes: weapons, armor and profession gear (Enum.ItemClass)
local DISENCHANTABLE = { [2] = true, [4] = true, [19] = true }
-- A Gem may be an artifact relic, which disenchants too (subclass 11), and
-- no container is a gem: after a disenchant it is neither answer
local EITHER = { [3] = true }
-- Enum.UIMapType: the zone a sub-area's map lies in is found by walking up
-- from a Micro map; a Dungeon map (an instance's floor) or an Orphan map is
-- never walked up from, since its parent is not a zone its creatures belong to
local MAP_ZONE, MAP_MICRO = 3, 5
local MAP_DEPTH = 6   -- parents walked at most

Loot.seams = {
  NumItems = function() return GetNumLootItems() end,
  SlotType = function(slot) return GetLootSlotType(slot) end,
  Quality = function(slot) return select(5, GetLootSlotInfo(slot)) end,
  Link = function(slot) return GetLootSlotLink(slot) end,
  Sources = function(slot) return { GetLootSourceInfo(slot) } end,
  IsFishing = function() return IsFishingLoot() end,
  ItemIDByGUID = function(guid) return C_Item.GetItemIDByGUID(guid) end,
  ItemClass = function(itemID) return (select(6, C_Item.GetItemInfoInstant(itemID))) end,
  TargetGUID = function() return UnitGUID("target") end,
  TargetDead = function() return UnitIsDead("target") end,
  CanAttack = function() return UnitCanAttack("player", "target") end,
  Map = function() return C_Map.GetBestMapForUnit("player") end,
  MapInfo = function(mapID) return C_Map.GetMapInfo(mapID) end,
}

local read = false   -- this window was read

local function Seam(name, ...)
  local ok, value = pcall(Loot.seams[name], ...)
  if not ok or Host.IsSecret(value) then return nil end
  return value
end

local function ItemFromLink(link)
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- A GUID's kind and ID ("Creature-0-1-2-3-<id>-<spawn>"), or nil
local function GuidParts(guid)
  if type(guid) ~= "string" or Host.IsSecret(guid) then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  return kind, tonumber(id)
end

-- One source GUID as { key, kind, id, extra }, or nil
local function Classify(guid)
  local kind, id = GuidParts(guid)
  if not kind then return nil end
  if kind == "Creature" or kind == "Vehicle" then
    if not id then return nil end
    if guid == Seam("TargetGUID") and Seam("TargetDead") == false then
      -- a living target the player can't attack is looted some other way
      -- (a boss that surrendered): neither a pickpocket nor a drop is sure
      if Seam("CanAttack") ~= true then return nil end
      return { key = guid, kind = "pickpocket", id = id }
    end
    -- the spell cast just before, or false for none, kept per observation
    -- (a skinning or gathering loot is set apart by the pipeline, never here)
    return { key = guid, kind = "drop", id = id, extra = { cast = Bags.RecentCast() or false } }
  end
  if kind == "GameObject" then
    return id and { key = guid, kind = "object", id = id } or nil
  end
  if kind == "Item" then
    local container = Seam("ItemIDByGUID", guid)
    if not Bags.PositiveID(container) then return nil end
    local at = Bags.CastAt(Loot.DISENCHANT)
    local disenchant = at ~= nil and Bags.seams.Clock() - at <= Bags.CAST_WINDOW
    if disenchant then
      -- the cast alone can't tell: a container opened right after a
      -- disenchant has an Item source too, so the item's class decides
      local class = Seam("ItemClass", container)
      if type(class) ~= "number" or EITHER[class] then return nil end
      disenchant = DISENCHANTABLE[class] == true
    end
    return { key = guid, kind = disenchant and "disenchant" or "container", id = container }
  end
  return nil
end

local function Add(window, source, itemID)
  local entry = window.sources[source.key]
  if not entry then
    entry = { kind = source.kind, id = source.id, items = {}, extra = source.extra }
    window.sources[source.key] = entry
  end
  entry.items[itemID] = true
end

-- The slot's sources, or nil when any can't be read (then the slot records
-- nothing)
local function SlotSources(slot)
  local ok, list = pcall(Loot.seams.Sources, slot)
  if not ok or type(list) ~= "table" or #list == 0 then return nil end
  local out = {}
  for i = 1, #list, 2 do
    local source = Classify(list[i])
    if not source then return nil end
    out[#out + 1] = source
  end
  return out
end

local function ReadSlot(window, slot, fishingMap)
  if Seam("SlotType", slot) ~= ITEM_SLOT then return end
  local quality = Seam("Quality", slot)
  if type(quality) ~= "number" or quality == 0 then return end
  local itemID = ItemFromLink(Seam("Link", slot))
  if not itemID then return end
  if fishingMap then
    Add(window, { key = "fishing", kind = "fishing", id = fishingMap }, itemID)
    return
  end
  for _, source in ipairs(SlotSources(slot) or {}) do Add(window, source, itemID) end
end

-- A map's type and parent, or nil when either can't be read
local function MapTypeOf(mapID)
  local info = Seam("MapInfo", mapID)
  if type(info) ~= "table" then return nil end
  local mapType, parent = info.mapType, info.parentMapID
  if type(mapType) ~= "number" or Host.IsSecret(mapType) then return nil end
  return mapType, parent
end

-- ZoneMaps(mapID): { [mapID] = true } for the loot's map and, from a Micro
-- map (a cave or building inside a zone), each parent up to and including
-- the Zone it lies in. Never a Continent or anything above, and nothing
-- above a Dungeon or Orphan map; a map that can't be read ends the walk.
function Loot.ZoneMaps(mapID)
  local maps = {}
  if not Bags.PositiveID(mapID) then return maps end
  maps[mapID] = true
  local mapType, parent = MapTypeOf(mapID)
  for _ = 1, MAP_DEPTH do
    if mapType ~= MAP_MICRO or not Bags.PositiveID(parent) or maps[parent] then break end
    local parentType, grandparent = MapTypeOf(parent)
    if parentType ~= MAP_MICRO and parentType ~= MAP_ZONE then break end
    maps[parent] = true
    mapType, parent = parentType, grandparent
  end
  return maps
end

-- Read(): the open loot window, once, captured now (slots are gone once
-- looted) and compared in a later frame; true when it was read
function Loot.Read()
  if read or not Curator.Main.MayRecord() then return false end
  read = true
  local map = Seam("Map")
  local window = { sources = {}, map = map }
  local fishingMap = Seam("IsFishing") == true and map or nil
  for slot = 1, Seam("NumItems") or 0 do ReadSlot(window, slot, fishingMap) end
  if next(window.sources) then
    Curator.Main.Defer(function()
      window.zones = Loot.ZoneMaps(window.map)
      Curator.Compare.Loot(window, Curator.Context.Current())
    end)
  end
  return true
end

function Loot.OnClosed()
  read = false
end

local handlers = { LOOT_READY = Loot.Read, LOOT_CLOSED = Loot.OnClosed }

local frame = CreateFrame("Frame")
for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event)
  if Curator.Main.IsScripted() then return end
  local ok, err = pcall(handlers[event])
  if not ok then Host.Log("Loot recorder %s failed: %s", event, tostring(err)) end
end)
