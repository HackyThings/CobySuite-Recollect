-------------------------------------------------------------------------------
-- Curator recorders: the shared bag and cast observer
--
-- Several recorders judge what the bags did around a cast: a combine, a
-- recipe item that taught a recipe, an item used on a quest target, what an
-- item's use gave. Reading every bag once per recorder would multiply the
-- cost, so this module reads the bags' item counts once per
-- BAG_UPDATE_DELAYED (Host.BagTotals) and hands each change to its
-- subscribers as (before, after), and keeps the player's recent casts
-- (UNIT_SPELLCAST_SUCCEEDED) for all of them.
--
-- An item's Use spell (C_Item.GetItemSpell) is read once and kept for the
-- session (it never changes); ItemsForSpell finds the items in the bags whose
-- Use spell a cast was.
--
-- Bags are compared only while curator mode may record, out of combat
-- (loot and consumables move the counts), with every bag read completely,
-- and never while a test run scripts the client. Casts are kept only while
-- curator mode may record; turned off, what the bags held is forgotten.
-- Client reads go through Bags.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host

local Bags = {}
Curator.Recorders = Curator.Recorders or {}
Curator.Recorders.Bags = Bags

Bags.CAST_WINDOW = 2   -- seconds from a cast to the bag change it caused

Bags.seams = {
  Totals = function() return Host.BagTotals() end,
  Clock = function() return GetTime() end,
  InCombat = function() return InCombatLockdown() end,
  ItemSpell = function(itemID)
    local _, spellID = C_Item.GetItemSpell(itemID)
    return spellID
  end,
  ItemCached = function(itemID) return C_Item.IsItemDataCachedByID(itemID) end,
}

local last = nil          -- the bags' counts at the last read compared (none in combat)
local held = nil          -- the counts at the last good read, kept through combat
local casts = {}          -- [spellID] = when the player last cast it (seams.Clock)
local lastCast = nil      -- { spellID, at }: the most recent cast
local spellOf = {}        -- [itemID] = its Use spell, or false for none
local subscribers = {}    -- { fn(before, after) }
local castListeners = {}  -- { fn(spellID, castGUID) }

local function PositiveID(value)
  return type(value) == "number" and not Host.IsSecret(value) and value > 0
end
Bags.PositiveID = PositiveID

-- An item's Use spell ID, or nil. A spell is kept once read; "no spell" is
-- kept only when the item's data is loaded (an unloaded item answers nil
-- too) and the answer wasn't secret, so it is asked again otherwise.
function Bags.ItemSpell(itemID)
  local known = spellOf[itemID]
  if known ~= nil then return known or nil end
  local ok, spellID = pcall(Bags.seams.ItemSpell, itemID)
  if not ok or Host.IsSecret(spellID) then return nil end
  if PositiveID(spellID) then
    spellOf[itemID] = spellID
    return spellID
  end
  local okCached, cached = pcall(Bags.seams.ItemCached, itemID)
  if okCached and cached == true then spellOf[itemID] = false end
  return nil
end

-- The item's own Use spell when the player cast it within CAST_WINDOW
-- seconds, else nil
function Bags.CastJustNow(itemID)
  local spellID = Bags.ItemSpell(itemID)
  if not spellID then return nil end
  local at = casts[spellID]
  return at ~= nil and Bags.seams.Clock() - at <= Bags.CAST_WINDOW and spellID or nil
end

-- When the player last cast a spell (seams.Clock), or nil
function Bags.CastAt(spellID)
  return casts[spellID]
end

-- The most recent cast within CAST_WINDOW seconds: spellID, or nil
function Bags.RecentCast()
  if lastCast and Bags.seams.Clock() - lastCast.at <= Bags.CAST_WINDOW then return lastCast.spellID end
  return nil
end

-- The items in the bags (at the last good read, which combat keeps) whose
-- Use spell is spellID
function Bags.ItemsForSpell(spellID)
  local out = {}
  for itemID in pairs(held or {}) do
    if Bags.ItemSpell(itemID) == spellID then out[#out + 1] = itemID end
  end
  table.sort(out)
  return out
end

-- The bags' counts at the last good read, or nil
function Bags.Current()
  return held
end

-- UNIT_SPELLCAST_SUCCEEDED for the player (unit, castGUID, spellID)
function Bags.OnCast(unit, castGUID, spellID)
  if unit ~= "player" or not PositiveID(spellID) then return end
  local now = Bags.seams.Clock()
  casts[spellID] = now
  lastCast = { spellID = spellID, at = now }
  for _, fn in ipairs(castListeners) do
    local ok, err = pcall(fn, spellID, castGUID)
    if not ok then Host.Log("Cast listener failed: %s", tostring(err)) end
  end
end

-- Changes(before, after): the items gone down and gone up, each { id, n },
-- by item ID
function Bags.Changes(before, after)
  local down, up = {}, {}
  -- every ID once: those held before, then those only held after
  local function Compare(id)
    local change = (after[id] or 0) - (before[id] or 0)
    if change < 0 then down[#down + 1] = { id = id, n = -change } end
    if change > 0 then up[#up + 1] = { id = id, n = change } end
  end
  for id in pairs(before) do Compare(id) end
  for id in pairs(after) do
    if before[id] == nil then Compare(id) end
  end
  table.sort(down, function(a, b) return a.id < b.id end)
  table.sort(up, function(a, b) return a.id < b.id end)
  return down, up
end

-- Subscribe(fn): fn(before, after) on every compared bag change
function Bags.Subscribe(fn)
  subscribers[#subscribers + 1] = fn
end

-- ListenCasts(fn): fn(spellID, castGUID) on every player cast kept
function Bags.ListenCasts(fn)
  castListeners[#castListeners + 1] = fn
end

function Bags.OnBagsChanged()
  if not Curator.Main.MayRecord() or Curator.Main.IsScripted() or Bags.seams.InCombat() then
    last = nil
    return
  end
  local ok, now = pcall(Bags.seams.Totals)
  if not ok or type(now) ~= "table" then
    last = nil
    return
  end
  local before = last
  last, held = now, now
  if not before then return end
  for _, fn in ipairs(subscribers) do
    local okFn, err = pcall(fn, before, now)
    if not okFn then Host.Log("Bag change subscriber failed: %s", tostring(err)) end
  end
end

-- Forgets the last read, the casts and the kept Use spells (a test starts
-- clean)
function Bags.Reset()
  last, held, lastCast = nil, nil, nil
  wipe(casts)
  wipe(spellOf)
end

-- SetCurrent(totals): the last read, as a test scripts it
function Bags.SetCurrent(totals)
  last, held = totals, totals
end

local frame = CreateFrame("Frame")
pcall(frame.RegisterEvent, frame, "BAG_UPDATE_DELAYED")
pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SUCCEEDED", "player")
frame:SetScript("OnEvent", function(_, event, ...)
  if not Curator.Main.MayRecord() or Curator.Main.IsScripted() then
    last, held = nil, nil   -- what the bags held while off is not known
    return
  end
  local handler = event == "UNIT_SPELLCAST_SUCCEEDED" and Bags.OnCast or Bags.OnBagsChanged
  local ok, err = pcall(handler, ...)
  if not ok then Host.Log("Bag observer %s failed: %s", event, tostring(err)) end
end)
