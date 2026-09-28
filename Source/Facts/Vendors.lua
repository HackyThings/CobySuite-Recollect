-------------------------------------------------------------------------------
-- Facts.Vendors: where vendors stand and what they take (Data/Vendors.lua:
-- the Lab's vendor recorder, and AllTheThings' positions for the vendors
-- its facts name; IDs and positions only)
--
-- A vendor is { npcID, mapID, x, y } with x and y from 0 to 1 on that map.
-- ForCurrency(currencyID) and ForCostItem(itemID) list the vendors that take
-- them; Selling(itemID) lists the vendors that sell it for items or
-- currencies. The zone's name is read live (C_Map.GetMapInfo), and a
-- creature's name from its tooltip by a unit link (NpcName; the first ask of
-- a creature the client hasn't seen makes the server send it, so a first
-- miss is asked again after 2 seconds, any later one after 30); Describe(npc) words a vendor (or another
-- NPC) for a panel line. Object(objectID) is an object a key opens:
-- { objectID, mapID, x, y, questID, contents }, with no map when its
-- position isn't known. ItemsOf(npcID) is what a vendor sells, uncapped, in
-- the data's own order (the items table, for curator mode). Encounter(id)
-- names an Encounter Journal encounter and its dungeon or raid, and
-- Boss(npcID) a boss the data maps to one. Nothing is read
-- while Facts.DataVersion has the shipped data off.
--
-- FromSourceText(text, linkType, id) reads a vendor's name and place from a
-- collection's source text (mount and pet journals, the housing catalog), in
-- the player's language: blocks split by a blank line (|n|n), lines by |n,
-- each line a gold label and its value ("|cFFFFD200Vendor: |rFizz Alechux").
-- Only the values are kept, so no label words are read.
-------------------------------------------------------------------------------
local Vendors = {}
Recollect.Facts.Vendors = Vendors

local Try = Recollect.Utilities.Try

local seams = {
  MapInfo = function(mapID) return C_Map.GetMapInfo(mapID) end,
  -- A creature's tooltip from a unit link built from its NPC ID; its first
  -- line is the name once the client has the creature cached
  CreatureTooltip = function(npcID)
    return C_TooltipInfo.GetHyperlink(("unit:Creature-0-0-0-0-%d-0000000000"):format(npcID))
  end,
  Now = function() return GetTime() end,
  -- The Encounter Journal: the client's own data, no server ask
  EncounterInfo = function(encounterID) return EJ_GetEncounterInfo(encounterID) end,
  InstanceInfo = function(instanceID) return EJ_GetInstanceInfo(instanceID) end,
}

local names = {}   -- [npcID] = name, kept for the session once read
local misses = {}  -- [npcID] = { at, n }: when a read last found no name, and how many have
local MISS_AFTER = 30
local FIRST_MISS_AFTER = 2   -- seconds before a first miss is asked again

-- The shipped data, or an empty table while Facts.DataVersion has it off
local EMPTY = {}
local function Data()
  local version = Recollect.Facts.DataVersion
  if version and not version.Ok() then return EMPTY end
  return Recollect.Data and Recollect.Data.Vendors or EMPTY
end

-- An NPC's or object's record: the shipped data's bucketed strings (P, O),
-- else a plain table of strings (npcs, objects: what a suite scripts)
local function Placed(bucketed, plain, id)
  local data = Data()
  if not Recollect.Utilities.IsPositiveID(id) then return nil end
  return Recollect.Utilities.BucketRecord(data[bucketed], id) or (data[plain] or {})[id]
end

function Vendors.Position(npcID)
  local text = Placed("P", "npcs", npcID)
  if type(text) ~= "string" then return nil end
  local mapID, x, y = text:match("^(%d+),([%d%.]+),([%d%.]+)$")
  if not mapID then return nil end
  return { npcID = npcID, mapID = tonumber(mapID), x = tonumber(x), y = tonumber(y) }
end

local function List(field, id)
  local out = {}
  local text = (Data()[field] or {})[id]
  for npc in (type(text) == "string" and text or ""):gmatch("%d+") do
    local vendor = Vendors.Position(tonumber(npc))
    if vendor then out[#out + 1] = vendor end
  end
  return out
end

function Vendors.ForCurrency(currencyID) return List("currency", currencyID) end
function Vendors.ForCostItem(itemID) return List("costItem", itemID) end
function Vendors.Selling(itemID) return List("sold", itemID) end

-- What a vendor sells as the data's index lists it (the items table), in
-- that order, never sorted again: a curator's confirmation counts over
-- these positions. An empty list when the data names none
function Vendors.ItemsOf(npcID)
  local list = {}
  if not Recollect.Utilities.IsPositiveID(npcID) then return list end
  local text = (Data().items or EMPTY)[npcID]
  if type(text) ~= "string" then return list end
  for item in text:gmatch("%d+") do list[#list + 1] = tonumber(item) end
  return list
end

local MAX_SELLERS = 2

-- The value of one source-text line: the text after its label's color ends,
-- else the line without color codes
local function LineValue(line)
  local value = line:match("|[rR](.-)$")
  if not value or value == "" then value = line end
  value = CobySuite_Recollect.Utilities.StripColors(value)
  return value:match("^%s*(.-)%s*$")
end

-- The vendors a source text names beside a cost that links linkType:id
-- ("item", 37829): { "Fizz Alechux (Razorwind Shores)", ... }, at most
-- MAX_SELLERS, one per block that lists that cost
function Vendors.FromSourceText(text, linkType, id)
  local out = {}
  if type(text) ~= "string" or text == "" then return out end
  text = text:gsub("\r?\n", "|n")
  local link = "|H" .. linkType .. ":" .. id
  for block in (text .. "|n|n"):gmatch("(.-)|n|n") do
    local at = block:find(link, 1, true)
    local nextChar = at and block:sub(at + #link, at + #link)
    if at and (nextChar == "|" or nextChar == ":") and #out < MAX_SELLERS then
      local values = {}
      for line in (block .. "|n"):gmatch("(.-)|n") do
        if not line:find("|H", 1, true) then
          local value = LineValue(line)
          if value ~= "" then values[#values + 1] = value end
        end
      end
      if #values > 0 then
        local first = table.remove(values, 1)
        out[#out + 1] = #values > 0 and ("%s (%s)"):format(first, table.concat(values, ", ")) or first
      end
    end
  end
  return out
end

-- "Silvermoon City", or nil
function Vendors.ZoneName(mapID)
  local ok, info = Try(seams.MapInfo, mapID)
  return ok and type(info) == "table" and type(info.name) == "string" and info.name or nil
end

-- NpcName(npcID): a creature's name in the player's language, or nil until
-- the client has it, and whether a read went out just now. The first read
-- of a creature the client hasn't seen makes the server send it, so a first
-- miss is read again after FIRST_MISS_AFTER seconds, any later one after
-- MISS_AFTER (BA-11: a list naming many vendors builds no tooltip for each
-- one again)
-- Encounter(encounterID): an Encounter Journal encounter, read from the
-- client's own journal data (no server ask): { name, instance (its dungeon
-- or raid), link (opens the journal at it) }, or nil when the journal can't
-- name it. The instance is asked for only by its ID: EJ_GetInstanceInfo with
-- none answers for the journal's selected instance instead
-- Boss(npcID): the same for a boss the data maps to its encounter
-- (Relations.EncounterOf), or nil
-- JOURNAL_COLOR: the game's color for a journal link (66bbff, as
-- ItemRef.lua colors one)
Vendors.JOURNAL_COLOR = { 0.4, 0.733, 1 }

function Vendors.Encounter(encounterID)
  if not Recollect.Utilities.IsPositiveID(encounterID) then return nil end
  local ok, name, _, _, _, link, instanceID = Try(seams.EncounterInfo, encounterID)
  if not ok or type(name) ~= "string" or name == "" then return nil end
  local instance
  if Recollect.Utilities.IsPositiveID(instanceID) then
    local okI, text = Try(seams.InstanceInfo, instanceID)
    instance = okI and type(text) == "string" and text ~= "" and text or nil
  end
  return { name = name, instance = instance, link = type(link) == "string" and link ~= "" and link or nil }
end

function Vendors.Boss(npcID)
  local encounterID = Recollect.Facts.Relations.EncounterOf(npcID)
  return encounterID and Vendors.Encounter(encounterID) or nil
end

function Vendors.NpcName(npcID)
  if not Recollect.Utilities.IsPositiveID(npcID) then return nil end
  if names[npcID] then return names[npcID] end
  -- a boss: the journal names it at once (a raid boss's tooltip may never come)
  local boss = Vendors.Boss(npcID)
  if boss then
    names[npcID] = boss.name
    return boss.name
  end
  local now = seams.Now()
  local miss = misses[npcID]
  if miss and now - miss.at < (miss.n == 1 and FIRST_MISS_AFTER or MISS_AFTER) then return nil, false end
  local ok, data = Try(seams.CreatureTooltip, npcID)
  local line = ok and type(data) == "table" and type(data.lines) == "table" and data.lines[1]
  local text = type(line) == "table" and line.leftText
  if type(text) ~= "string" or Recollect.Utilities.IsSecret(text) or text == "" then
    misses[npcID] = { at = now, n = (miss and miss.n or 0) + 1 }
    return nil, true
  end
  misses[npcID] = nil
  names[npcID] = text
  return text
end

-- A creature's name read before this session asked, or nil; never builds a
-- tooltip (the pinned view rations new reads itself)
function Vendors.KnownName(npcID)
  return names[npcID]
end

-- A vendor for a panel line: "Name (Zone)", "a vendor in Zone (x, y)", or
-- nil when neither its name nor its place is known; and its position.
-- noun words an NPC that isn't a vendor ("an NPC").
function Vendors.Describe(npcID, noun)
  local name = Vendors.NpcName(npcID)
  local vendor = Vendors.Position(npcID)
  local zone = vendor and Vendors.ZoneName(vendor.mapID)
  if vendor then vendor.zone = zone end
  -- a boss with no place in the data: its dungeon or raid
  if name and not zone then
    local boss = Vendors.Boss(npcID)
    if boss and boss.instance then return ("%s (%s)"):format(name, boss.instance), vendor end
  end
  if name then return zone and ("%s (%s)"):format(name, zone) or name, vendor end
  if zone then return ("%s in %s (%.1f, %.1f)"):format(noun or "a vendor", zone, vendor.x * 100, vendor.y * 100), vendor end
  return nil, vendor
end

-- An object a key opens (Data/Vendors.lua objects, from AllTheThings):
-- { objectID, mapID, x, y, questID (nil when none), contents = { itemID } };
-- mapID, x and y are nil for an object with no known position (map 0 in the
-- data: its use still counts, with no waypoint)
function Vendors.Object(objectID)
  local text = Placed("O", "objects", objectID)
  if type(text) ~= "string" then return nil end
  local mapID, x, y, quest, held = text:match("^(%d+),([%d%.]+),([%d%.]+),(%d+),([%d%.]*)$")
  if not mapID then return nil end
  local contents = {}
  for item in held:gmatch("%d+") do contents[#contents + 1] = tonumber(item) end
  quest, mapID = tonumber(quest), tonumber(mapID)
  local placed = mapID > 0
  return { objectID = objectID, mapID = placed and mapID or nil, x = placed and tonumber(x) or nil,
    y = placed and tonumber(y) or nil, questID = quest > 0 and quest or nil, contents = contents }
end

-- Every NPC with a position, in ID order (the Lab's name sample)
function Vendors.PlacedNpcIDs()
  local data, out = Data(), {}
  for _, bucket in pairs(data.P or {}) do
    for id in tostring(bucket):gmatch("\30(%d+)\31") do out[#out + 1] = tonumber(id) end
  end
  for id in pairs(data.npcs or {}) do out[#out + 1] = id end
  table.sort(out)
  return out
end

Vendors._test = { seams = seams, Reset = function() wipe(names) wipe(misses) end }
