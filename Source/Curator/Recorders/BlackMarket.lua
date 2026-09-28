-------------------------------------------------------------------------------
-- Curator recorder: the Black Market Auction House (design
-- Recollect-New-Sources-2026-09-27, "Curator recorders"; the shipped code
-- O<n>, kind blackMarket, "sometimes offered on the Black Market")
--
-- One window is one visit: the interaction's show (PLAYER_INTERACTION_
-- MANAGER_FRAME_SHOW with BlackMarketAuctioneer, 27) opens it, every read
-- while it is open (the show itself and each BLACK_MARKET_ITEM_UPDATE, which
-- follows the game's own C_BlackMarket.RequestItems) adds the item IDs it
-- found to the visit's set, and the interaction's hide commits the set once,
-- in a later frame. Reads are out of combat only.
--
-- Facts (the store's fact names; values are text):
--   bm:i:<item>   offered on the Black Market, value "1": an addition when
--                 the shipped data has no O code for the item that is still
--                 available (shipped: its codes flagged "|x", as "1|x", or
--                 nil). An O code flagged no longer available counts as none,
--                 so an item offered again reaches the author as an addition.
-- One stamp per visit, source "bm", total 0: the item IDs with a live O
-- code. A listing is never complete (the market rotates), so no not seen and
-- no conflicts.
--
-- IDs only: each listing is read through its link alone (return 15 of
-- C_BlackMarket.GetItemInfoByIndex's 17), never its seller, bids, or whether
-- the player holds the high bid. A caged pet's link is a battlepet link with
-- no item ID and records nothing. A secret or failed read records nothing.
--
-- Only while curator mode may record, and never while a test run scripts
-- the client. Client reads go through BlackMarket.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Store = Curator.Store

local BlackMarket = {}
Curator.Recorders = Curator.Recorders or {}
Curator.Recorders.BlackMarket = BlackMarket

local INTERACTION = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.BlackMarketAuctioneer or 27
local MAX_ITEMS = 200   -- a guard; the market lists a few dozen at most

BlackMarket.seams = {
  NumItems = function() return C_BlackMarket.GetNumItems() end,
  -- the listing's link alone: name, seller, bids and the high-bid flag stay here
  Link = function(index) return (select(15, C_BlackMarket.GetItemInfoByIndex(index))) end,
  InCombat = function() return InCombatLockdown() end,
}

local visit   -- the open window's { epoch, items = { [itemID] = true } }, or nil

local function Seam(name, ...)
  local ok, value = pcall(BlackMarket.seams[name], ...)
  if not ok or Host.IsSecret(value) then return nil end
  return value
end

local function InCombat()
  local ok, value = pcall(BlackMarket.seams.InCombat)
  return not ok or Host.IsSecret(value) or value == true
end

-- The shipped codes no longer available, as text ("1|x"), or nil
local function GoneText(codes)
  local parts = {}
  for _, code in ipairs(codes) do
    if code.gone then parts[#parts + 1] = code.id .. "|x" end
  end
  return #parts > 0 and table.concat(parts, ",") or nil
end

-- Compare(items, ctx): items = { [itemID] = true }, one visit's listings
function BlackMarket.Compare(items, ctx)
  local matched = {}
  for itemID in pairs(items) do
    local codes, live = Host.CodesOf(itemID, "O"), false
    for _, code in ipairs(codes) do
      if not code.gone then live = true end
    end
    if live then
      matched[#matched + 1] = itemID
    else
      Store.Record("addition", "bm:i:" .. itemID, "1", GoneText(codes), ctx)
    end
  end
  Store.Confirm("bm", matched, 0, ctx)
  return #matched
end

-- Read(): the open window's listings into its visit; how many item IDs it read
function BlackMarket.Read()
  if not visit or not Curator.Main.MayRecord() or InCombat() then return 0 end
  local count = Seam("NumItems")
  if type(count) ~= "number" then return 0 end
  local found = 0
  for index = 1, math.min(count, MAX_ITEMS) do
    local link = Seam("Link", index)
    local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    if itemID and itemID > 0 then
      visit.items[itemID] = true
      found = found + 1
    end
  end
  return found
end

-- The interaction's hide: commits the visit once, in a later frame
function BlackMarket.OnClosed()
  local closed = visit
  visit = nil
  if not (closed and next(closed.items) and Curator.Main.StillCurrent(closed.epoch)) then return end
  Curator.Main.Defer(function()
    local matched = BlackMarket.Compare(closed.items, Curator.Context.Current())
    Host.Log("Black Market: %d listings had a shipped O code", matched)
  end)
end

-- The interaction's show: a new visit (one still open is committed first)
function BlackMarket.OnShow()
  if visit then BlackMarket.OnClosed() end
  visit = { epoch = Curator.Main.Epoch(), items = {} }
  BlackMarket.Read()
end

function BlackMarket.Reset()
  visit = nil
end

local function IsMarket(kind)
  return not Host.IsSecret(kind) and kind == INTERACTION
end

local handlers = {
  PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(kind) if IsMarket(kind) then BlackMarket.OnShow() end end,
  PLAYER_INTERACTION_MANAGER_FRAME_HIDE = function(kind) if IsMarket(kind) then BlackMarket.OnClosed() end end,
  -- the market's own close event too: whether the interaction hide above fires with this type is
  -- unmeasured, and a second close commits nothing (the visit is gone)
  BLACK_MARKET_CLOSE = function() BlackMarket.OnClosed() end,
  BLACK_MARKET_ITEM_UPDATE = function() BlackMarket.Read() end,
}

-- The event frame's dispatch (a test run scripting the client reads nothing)
function BlackMarket.OnEvent(event, ...)
  if Curator.Main.IsScripted() or not handlers[event] then return end
  local ok, err = pcall(handlers[event], ...)
  if not ok then Host.Log("Black Market recorder %s failed: %s", event, tostring(err)) end
end

local frame = CreateFrame("Frame")
for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...) BlackMarket.OnEvent(event, ...) end)
