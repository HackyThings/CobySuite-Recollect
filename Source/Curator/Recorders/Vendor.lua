-------------------------------------------------------------------------------
-- Curator recorder: vendors (curator spec, "v1 recorders", D28, D29)
--
-- On MERCHANT_SHOW and MERCHANT_UPDATE (and late item data while a merchant
-- is open) it reads the open vendor a slice at a time: the NPC, the filter
-- the window opened with (never changed, D29), every entry's item, stack,
-- gold price and item and currency costs, whether every cost loaded, and
-- where the player stands. A read that finishes replaces the window's
-- staged read; nothing is written while the window is open. MERCHANT_CLOSED
-- commits the last finished read once, in later frames (one window is one
-- visit, however often it was read), then raises the merchant generation,
-- so a read still in progress is dropped. The comparison (Compare.Vendor*)
-- records additions, price conflicts, "not seen" with the filter, and one
-- confirmation stamp; the position goes to Compare.Position. Gold-only
-- trades are recorded too.
--
-- An entry whose item or info can't be read marks the read unread (no "not
-- seen", no stamp; recorder contract rule 1); a cost count, cost or gold
-- price that can't be read, or an entry with extended costs of which none
-- read and no gold price, makes that listing incomplete (no price). A secret
-- value in any return is no value.
--
-- Only while curator mode may record; events are ignored while a test run
-- scripts the client. Client reads go through Vendor.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Compare = Curator.Compare

local Vendor = {}
Curator.Recorders = Curator.Recorders or {}
Curator.Recorders.Vendor = Vendor

local SLICE = 20
local SETTLE = 0.3

Vendor.seams = {
  NpcGUID = function() return UnitGUID("npc") end,
  NumItems = function() return GetMerchantNumItems() end,
  Info = function(index) return C_MerchantFrame.GetItemInfo(index) end,
  ItemID = function(index) return GetMerchantItemID(index) end,
  CostCount = function(index) return GetMerchantItemCostInfo(index) end,
  CostItem = function(index, slot) return GetMerchantItemCostItem(index, slot) end,
  ItemFromLink = function(link) return C_Item.GetItemInfoInstant(link) end,
  Filter = function() return GetMerchantFilter() end,
  Map = function() return C_Map.GetBestMapForUnit("player") end,
  Position = function(mapID)
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if position then return position:GetXY() end
  end,
  InCombat = function() return InCombatLockdown() end,
  -- how the vendor regards the player, for reputation discounts (no API
  -- names an NPC's faction); which side's reaction this argument order
  -- gives is Lab check U9, so the pipeline treats it as a hint
  Reaction = function() return UnitReaction("npc", "player") end,
  -- the next slice of a long window, a frame later (scripted by the suites)
  After = function(delay, fn) C_Timer.After(delay, fn) end,
}

local pending   -- the read in progress, or nil
local staged    -- the window's last finished read, or nil

-- A seam's returns, or nil when the call fails or any return is secret
local function Seam(name, ...)
  local ok, a, b, c, d = pcall(Vendor.seams[name], ...)
  if not ok or Host.IsSecret(a) or Host.IsSecret(b) or Host.IsSecret(c) or Host.IsSecret(d) then return nil end
  return a, b, c, d
end

-- The NPC ID from a creature GUID (NpcPosition's helper)
function Vendor.NpcID(guid)
  return Curator.Recorders.NpcPosition.NpcID(guid)
end

-- One entry's costs: { { kind, id, count } }, and whether every cost read
local function Costs(index)
  local count = Seam("CostCount", index)
  if type(count) ~= "number" then return {}, false end
  local list, complete = {}, true
  for slot = 1, count do
    local _, value, link = Seam("CostItem", index, slot)
    local currency = type(link) == "string" and tonumber(link:match("currency:(%d+)"))
    local itemID = type(link) == "string" and not currency and Seam("ItemFromLink", link)
    if type(value) ~= "number" then
      complete = false
    elseif currency then
      list[#list + 1] = { kind = "currency", id = currency, count = value }
    elseif itemID then
      list[#list + 1] = { kind = "item", id = itemID, count = value }
    else
      complete = false
    end
  end
  return list, complete
end

local function ReadEntry(index, visit)
  local itemID = Seam("ItemID", index)
  local info = Seam("Info", index)
  if type(itemID) ~= "number" or type(info) ~= "table" then
    visit.unread = true
    return
  end
  local costs, complete = Costs(index)
  -- the gold price and the stack are fields of the returned table, which
  -- Seam can't check; a secret one is no value (2026-09-29: the stack is
  -- written into a price in a currency's text since data format 8)
  local price = info.price
  if type(price) ~= "number" or Host.IsSecret(price) then price, complete = nil, false end
  local stack = info.stackCount
  if type(stack) ~= "number" or Host.IsSecret(stack) then stack = nil end
  -- an entry the game says has item or currency costs, with none read and
  -- no gold price, has costs not loaded yet: it is not free. Only at no gold
  -- price: whether an extended cost with no cost items (a requirement only)
  -- stays that way beside a gold price is unmeasured, and marking that
  -- incomplete would drop its gold price from every comparison
  local free = price == nil or price <= 0
  if info.hasExtendedCost == true and #costs == 0 and free then complete = false end
  if not complete then visit.costsLoaded = false end
  visit.trades[itemID] = visit.trades[itemID] or {}
  table.insert(visit.trades[itemID], { stack = stack, price = price or 0, costs = costs, complete = complete })
end

local function StillReading(visit)
  return pending == visit and Compare.StillValid("merchant", visit.generation) and Curator.Main.StillCurrent(visit.epoch)
end

-- A finished read: where the player stands, then it becomes the staged read
local function Finish(visit)
  local mapID = Seam("Map")
  if type(mapID) == "number" then
    visit.mapID = mapID
    visit.x, visit.y = Seam("Position", mapID)
  end
  pending, staged = nil, visit
end

local function Step(visit, from)
  if not StillReading(visit) then
    if pending == visit then pending = nil end
    return
  end
  local last = math.min(visit.count, from + SLICE - 1)
  for index = from, last do ReadEntry(index, visit) end
  if last < visit.count then
    Vendor.seams.After(0, function() Step(visit, last + 1) end)
    return
  end
  Finish(visit)
end

-- Starts a read of the open vendor (one at a time; a newer one replaces it)
function Vendor.Read()
  if not Curator.Main.MayRecord() or Seam("InCombat") then return end
  local npc = Vendor.NpcID(Seam("NpcGUID"))
  local count = Seam("NumItems")
  if not npc or type(count) ~= "number" or Curator.Recorders.NpcPosition.Traveling(npc, "npc") then return end
  local visit = { npc = npc, filter = Seam("Filter"), costsLoaded = true, trades = {}, count = count,
    generation = Compare.Generation("merchant"), epoch = Curator.Main.Epoch(),
    context = Curator.Context.Owner(), reaction = Seam("Reaction") }
  pending = visit
  Step(visit, 1)
end

-- The staged read's comparison, a slice of items per deferred job; the
-- context block is read in each job right before it writes
local function Commit(visit)
  local state
  local function Slice(from)
    local ctx = Curator.Context.Current()
    if from == 1 then state = Compare.VendorStart(visit) end
    Compare.VendorItems(state, visit, ctx, from, from + SLICE - 1)
    if from + SLICE <= #state.items then
      Curator.Main.Defer(function() Slice(from + SLICE) end)
      return
    end
    local matched, shipped = Compare.VendorEnd(state, visit, ctx)
    Compare.Position(visit.npc, visit.mapID, visit.x, visit.y, ctx, nil, true)
    Host.Log("Vendor %d: %d of %d shipped trades matched%s", visit.npc, matched, shipped, visit.unread and " (an entry unread)" or "")
  end
  Curator.Main.Defer(function() Slice(1) end)
end

-- MERCHANT_CLOSED: commits the window's last finished read, once
function Vendor.OnClosed()
  local visit = staged
  staged, pending = nil, nil
  if visit and Compare.StillValid("merchant", visit.generation) and Curator.Main.StillCurrent(visit.epoch) then
    Commit(visit)
  end
  Compare.Invalidate("merchant")
end

local timer = CobySuite_Recollect.Utilities.Debounce(SETTLE, function() Vendor.Read() end)
local open = false

local handlers = {
  MERCHANT_SHOW = function()
    open, staged = true, nil
    timer:Call()
  end,
  MERCHANT_UPDATE = function() if open then timer:Call() end end,
  GET_ITEM_INFO_RECEIVED = function() if open then timer:Call() end end,
  MERCHANT_CLOSED = function()
    open = false
    timer:Cancel()
    Vendor.OnClosed()
  end,
}

local frame = CreateFrame("Frame")
for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event)
  if Curator.Main.IsScripted() then return end
  local ok, err = pcall(handlers[event])
  if not ok then Host.Log("Vendor recorder %s failed: %s", event, tostring(err)) end
end)
