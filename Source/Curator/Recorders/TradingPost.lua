-------------------------------------------------------------------------------
-- Curator recorder: the Trading Post (design Recollect-New-Sources-
-- 2026-09-27, "Curator recorders"; the shipped code U<yyyymm>, kind
-- tradingPost, "offered at the Trading Post", 0 for a month not known)
--
-- One opening is one visit: PERKS_PROGRAM_OPEN opens it, every read while it
-- is open (the opening and each PERKS_PROGRAM_DATA_REFRESH) adds the item
-- IDs of the vendor's items to the visit's set, and PERKS_PROGRAM_CLOSE
-- commits the set once, in a later frame. The month is the server's
-- calendar month (C_DateAndTime.GetCurrentCalendarTime, year * 100 + month),
-- read once per visit; a date that can't be read records nothing.
--
-- Facts (the store's fact names; values are text):
--   tp:i:<item>   offered at the Trading Post this month, value "<yyyymm>":
--                 an addition when the shipped data has no U code of that
--                 month for the item that is still available (shipped: its
--                 U codes, "202503,0|x", or nil). A U0 (month not known) or
--                 another month is no match, so the author learns the month.
-- Every offered item is also handed to the items-with-no-information
-- recorder as seen at "tp" (Compare.SawItem, the fact ni:<item>).
-- One stamp per visit, source "tp", total 0: the item IDs whose shipped U
-- code names this month. The shop is never complete for the data (ATT files
-- past months too), so no not seen and no conflicts.
--
-- The account's frozen item (one kept from an earlier month) is in the same
-- vendor item list as this month's offers, but it is offered to this
-- account alone and not this month, so it is only seen (SawItem), never a
-- tp:i fact. An item whose frozen state can't be read counts as frozen. A
-- visit that read only such items makes no stamp.
--
-- A vendor item with no item ID (itemID 0: a mount, pet or ensemble the shop
-- sells as itself) is skipped; mapping its mountID or speciesID to the item
-- behind it is left for later.
--
-- IDs only: each vendor item is read through its itemID alone, never its
-- name, price, time left or whether the player bought it. A secret or failed
-- read records nothing. Only while the Trading Post is open, curator mode may
-- record and no test run scripts the client. Client reads go through
-- TradingPost.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Store = Curator.Store

local TradingPost = {}
Curator.Recorders = Curator.Recorders or {}
Curator.Recorders.TradingPost = TradingPost

local MAX_ITEMS = 500   -- a guard; a month lists about a hundred

TradingPost.seams = {
  VendorItemIDs = function() return C_PerksProgram.GetAvailableVendorItemIDs() end,
  -- the vendor item's itemID alone: its name, price and purchased state stay here
  ItemID = function(vendorItemID)
    local info = C_PerksProgram.GetVendorItemInfo(vendorItemID)
    return info and info.itemID
  end,
  Frozen = function(vendorItemID) return C_PerksProgram.IsFrozenPerksVendorItem(vendorItemID) end,
  Date = function()
    local date = C_DateAndTime.GetCurrentCalendarTime()
    return date.year, date.month
  end,
  InCombat = function() return InCombatLockdown() end,
}

-- the open shop's { epoch, month, items = { [itemID] = true }, others = { [itemID] = true } }
-- (others: frozen items, seen only), or nil
local visit

local function Seam(name, ...)
  local ok, a, b = pcall(TradingPost.seams[name], ...)
  if not ok or Host.IsSecret(a) or Host.IsSecret(b) then return nil end
  return a, b
end

local function InCombat()
  local ok, value = pcall(TradingPost.seams.InCombat)
  return not ok or Host.IsSecret(value) or value == true
end

-- The server's month as yyyymm (202609), or nil
function TradingPost.Month()
  local year, month = Seam("Date")
  if type(year) ~= "number" or type(month) ~= "number" then return nil end
  if year < 2000 or year > 9999 or month < 1 or month > 12 or month % 1 ~= 0 or year % 1 ~= 0 then return nil end
  return year * 100 + month
end

local function ShippedText(codes)
  local parts = {}
  for _, code in ipairs(codes) do parts[#parts + 1] = code.id .. (code.gone and "|x" or "") end
  return #parts > 0 and table.concat(parts, ",") or nil
end

-- Compare(month, items, ctx, others): items = { [itemID] = true }, one
-- visit's vendor items in that month; others (optional, the same shape) the
-- items only seen there, such as the account's frozen item
function TradingPost.Compare(month, items, ctx, others)
  for itemID in pairs(others or {}) do
    if not items[itemID] then Curator.Compare.SawItem(itemID, "tp", ctx) end
  end
  if next(items) == nil then return 0 end
  local matched = {}
  for itemID in pairs(items) do
    Curator.Compare.SawItem(itemID, "tp", ctx)
    local codes, hit = Host.CodesOf(itemID, "U"), false
    for _, code in ipairs(codes) do
      if code.id == month and not code.gone then hit = true end
    end
    if hit then
      matched[#matched + 1] = itemID
    else
      Store.Record("addition", "tp:i:" .. itemID, tostring(month), ShippedText(codes), ctx)
    end
  end
  Store.Confirm("tp", matched, 0, ctx)
  return #matched
end

-- Read(): the open shop's vendor items into its visit; how many item IDs it read
function TradingPost.Read()
  if not visit or not Curator.Main.MayRecord() or InCombat() then return 0 end
  visit.month = visit.month or TradingPost.Month()
  if not visit.month then return 0 end
  local ids = Seam("VendorItemIDs")
  if type(ids) ~= "table" then return 0 end
  local found = 0
  for index = 1, math.min(#ids, MAX_ITEMS) do
    local vendorItemID = ids[index]
    local itemID = type(vendorItemID) == "number" and not Host.IsSecret(vendorItemID) and Seam("ItemID", vendorItemID)
    if type(itemID) == "number" and itemID > 0 then
      if Seam("Frozen", vendorItemID) ~= false then
        visit.others[itemID] = true
      else
        visit.items[itemID] = true
      end
      found = found + 1
    end
  end
  return found
end

-- PERKS_PROGRAM_CLOSE: commits the visit once, in a later frame
function TradingPost.OnClosed()
  local closed = visit
  visit = nil
  if not (closed and closed.month and (next(closed.items) or next(closed.others))
    and Curator.Main.StillCurrent(closed.epoch)) then return end
  Curator.Main.Defer(function()
    local matched = TradingPost.Compare(closed.month, closed.items, Curator.Context.Current(), closed.others)
    Host.Log("Trading Post %d: %d items had a shipped U code of the month", closed.month, matched)
  end)
end

-- PERKS_PROGRAM_OPEN: a new visit (one still open is committed first)
function TradingPost.OnOpen()
  if visit then TradingPost.OnClosed() end
  visit = { epoch = Curator.Main.Epoch(), items = {}, others = {} }
  TradingPost.Read()
end

function TradingPost.Reset()
  visit = nil
end

local handlers = {
  PERKS_PROGRAM_OPEN = function() TradingPost.OnOpen() end,
  PERKS_PROGRAM_DATA_REFRESH = function() TradingPost.Read() end,
  PERKS_PROGRAM_CLOSE = function() TradingPost.OnClosed() end,
}

-- The event frame's dispatch (a test run scripting the client reads nothing)
function TradingPost.OnEvent(event, ...)
  if Curator.Main.IsScripted() or not handlers[event] then return end
  local ok, err = pcall(handlers[event], ...)
  if not ok then Host.Log("Trading Post recorder %s failed: %s", event, tostring(err)) end
end

local frame = CreateFrame("Frame")
for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...) TradingPost.OnEvent(event, ...) end)
