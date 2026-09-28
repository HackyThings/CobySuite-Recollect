-------------------------------------------------------------------------------
-- Reader: one container read through C_Container, and nothing else
--
-- ReadContainer(bagID, opts) returns
--   {
--     bagID, numSlots,
--     readable = false when the slot count could not be read or was 0
--                (0 means "cannot see it", never "empty"),
--     complete = false when any occupied slot came back without its item ID
--                or link, a call failed, or a value was secret,
--     occupied, errors,
--     slots = { [slot] = { itemID, link, name, count, quality, isBound,
--                          hasLoot, hasNoValue,
--                          quest = { isQuestItem, questID, isActive } or nil,
--                          questUnread = true when the quest-info read failed
--                            (BA-02: then whether it is a quest item is
--                            unknown, which blocks Outdated and done),
--                          tooltip = Facts.Tooltip facts (opts.withTooltip) } },
--   }
--
-- An empty slot is simply absent. Only a readable, complete read may replace
-- a stored snapshot (Snapshots). Every call goes through Reader._test.seams
-- so suites can script the client.
-------------------------------------------------------------------------------
local Reader = {}
Recollect.Inventory.Reader = Reader

local Try = Recollect.Utilities.Try
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber

local function IsSecret(value) return Recollect.Utilities.IsSecret(value) end

local seams = {
  GetContainerNumSlots = function(bagID) return C_Container.GetContainerNumSlots(bagID) end,
  GetContainerItemInfo = function(bagID, slot) return C_Container.GetContainerItemInfo(bagID, slot) end,
  GetContainerItemQuestInfo = function(bagID, slot) return C_Container.GetContainerItemQuestInfo(bagID, slot) end,
}
Reader._test = { seams = seams }

local ITEM_FIELDS = { "itemID", "hyperlink", "itemName", "stackCount", "quality", "isBound", "hasLoot", "hasNoValue", "isReadable" }

-- A container-info table with any secret field is not a fact
local function AnySecret(info, fields)
  for _, key in ipairs(fields) do
    if IsSecret(info[key]) then return true end
  end
  return false
end

-- The slot's quest info, or nil and true when it couldn't be read (the call
-- answers a table for every occupied slot)
local function ReadQuest(bagID, slot)
  local ok, q = Try(seams.GetContainerItemQuestInfo, bagID, slot)
  if not ok or type(q) ~= "table" then return nil, true end
  if AnySecret(q, { "isQuestItem", "questID", "isActive" }) then return nil, true end
  return { isQuestItem = q.isQuestItem == true, questID = q.questID, isActive = q.isActive == true }, nil
end

local function ReadSlot(read, bagID, slot, opts)
  local ok, info = Try(seams.GetContainerItemInfo, bagID, slot)
  if not ok then
    read.errors = read.errors + 1
    read.complete = false
    read.failed = read.failed or {}   -- which slots, so their last-known copies can stand in (PI-10)
    read.failed[slot] = true
    return
  end
  if info == nil then return end            -- an empty slot
  if type(info) ~= "table" or AnySecret(info, ITEM_FIELDS) then
    read.errors = read.errors + 1
    read.complete = false
    read.failed = read.failed or {}
    read.failed[slot] = true
    return
  end
  local entry = {
    itemID = info.itemID,
    link = info.hyperlink,
    name = info.itemName,
    count = info.stackCount,
    quality = info.quality,
    isBound = info.isBound == true,
    hasLoot = info.hasLoot == true,
    isReadable = info.isReadable == true,
  }
  -- Non-nilable in 12.1; a read without it stays nil, so Junk goes by the
  -- item's own sell price rather than a made-up "has a value" (V-03)
  if type(info.hasNoValue) == "boolean" then entry.hasNoValue = info.hasNoValue end
  entry.quest, entry.questUnread = ReadQuest(bagID, slot)
  if not Recollect.Utilities.IsPositiveID(entry.itemID) or type(entry.link) ~= "string" then
    entry.pending = true
    read.complete = false
  end
  if opts and opts.withTooltip and Recollect.Facts.Tooltip then
    entry.tooltip = Recollect.Facts.Tooltip.FromBagSlot(bagID, slot)
  end
  read.slots[slot] = entry
  read.occupied = read.occupied + 1
end

-- ReadSlot(bagID, slot, opts): one slot's entry (nil for an empty slot), and
-- whether the read was complete
function Reader.ReadSlot(bagID, slot, opts)
  local read = { slots = {}, complete = true, occupied = 0, errors = 0 }
  ReadSlot(read, bagID, slot, opts)
  return read.slots[slot], read.complete
end

function Reader.ReadContainer(bagID, opts)
  local read = { bagID = bagID, numSlots = 0, slots = {}, readable = false, complete = false, occupied = 0, errors = 0 }
  local ok, numSlots = Try(seams.GetContainerNumSlots, bagID)
  if not ok then
    read.reason = "slot count failed: " .. tostring(numSlots)
    return read
  end
  if not IsFiniteNumber(numSlots) or numSlots <= 0 then
    read.reason = "no slots visible (" .. tostring(numSlots) .. ")"
    return read
  end
  read.numSlots = numSlots
  read.readable = true
  read.complete = true
  for slot = 1, numSlots do ReadSlot(read, bagID, slot, opts) end
  return read
end
