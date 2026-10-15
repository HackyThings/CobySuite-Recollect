-------------------------------------------------------------------------------
-- Curator recorder: containers that put their contents straight into the
-- bags, with no loot window (curator spec, "v1 recorders", Containers: "the
-- item's use spell plus a bag diff")
--
-- On the shared bag and cast observer (Recorders/Bags.lua), as Grants and
-- Combine are. A player cast out of combat whose spell is the Use spell of
-- exactly one item in the bags opens a window of the observer's CAST_WINDOW
-- seconds; every bag change compared in it is added up by item. When the
-- window closes, the use is a container's only when, across the window:
--   - the used item went down by exactly one, no other item went down, and
--     one or more other items went up;
--   - no loot window opened (LOOT_READY), no quest was turned in or paid
--     out (QUEST_TURNED_IN, QUEST_LOOT_RECEIVED), no boss loot or bonus roll
--     arrived, no interaction window opened (PLAYER_INTERACTION_MANAGER_
--     FRAME_SHOW of any type) and none of those that move items into the
--     bags (merchant, mail, banks, guild bank, auction house, void storage)
--     or a trade window was open;
--   - no second item's Use spell was cast (a cast of no held item's Use
--     spell doesn't count: many containers fire a spell of their own);
--   - combat didn't start, and the item doesn't combine one at a time (a
--     count-1 combine is the Combine recorder's).
-- Each new item is then recorded as the container's contents through the
-- loot recorder's comparison (Compare.Loot, kind "container"), so the facts
-- are the same as a container's loot window gives:
--   x:<container>:i:<item>   found in a container item, value "1"
-- and the stamp "x:<container>" (total 0). When in doubt, nothing.
--
-- Transformations (Task #423): the same window, with the same rules (a craft
-- begun or finished in it, TRADE_SKILL_CRAFT_BEGIN or
-- TRADE_SKILL_ITEM_CRAFTED_RESULT, and gear changed, PLAYER_EQUIPMENT_CHANGED,
-- now count as another gain too), may show
-- a use the container and combine recorders don't take: some other item went
-- down beside the used one (parts consumed together), or the used item went
-- down by a count no shipped combine has. With the used item down and
-- something up, it is recorded whole (Compare.Transform):
--   tf:<used item>   "<consumed>|<gained>", each "<item>x<n>" comma
--                    separated by item ID, the used item among the consumed,
--                    with the Use spell kept as the observation's cast
-- A use the Combine recorder takes (only the used item down, by a count the
-- data combines, and one item up) and a plain container use stay theirs.
-- The client never judges a transformation: the pipeline sorts each into a
-- simple combine, a combine of several parts or one for review.
--
-- Only while curator mode may record, and never while a test run scripts
-- the client. Client reads go through ContainerUse.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Bags = Curator.Recorders.Bags

local ContainerUse = {}
Curator.Recorders.ContainerUse = ContainerUse

ContainerUse.seams = {
  After = function(delay, fn) C_Timer.After(delay, fn) end,
  InCombat = function() return InCombatLockdown() end,
}

local window = nil   -- { itemID, spell, epoch, net = { [itemID] = change }, ambiguous }
local open = {}      -- [interaction type, or "trade"] = true while that window is open

-- The interaction windows that move items into the bags and close with a
-- hide of their own type: tracked while open. Any other type's show only
-- makes an open window ambiguous, so a hide that never comes can't leave
-- the recorder stuck.
local TRACKED = { [5] = true, [8] = true, [10] = true, [17] = true, [21] = true, [26] = true, [67] = true, [68] = true,
  trade = true }   -- Merchant, Banker, GuildBanker, MailInfo, Auctioneer, VoidStorageBanker, CharacterBanker, AccountBanker

local function InCombat()
  local ok, value = pcall(ContainerUse.seams.InCombat)
  return not ok or Host.IsSecret(value) or value == true
end

-- Whether combining the item one at a time makes something (the Combine
-- recorder's case)
local function CombinesOne(itemID)
  for _, combine in ipairs(Host.Combines(itemID)) do
    if combine.count == 1 then return true end
  end
  return false
end

-- Judge(itemID, net): the items the container gave ({ itemID = true }), or nil
function ContainerUse.Judge(itemID, net)
  if net[itemID] ~= -1 then return nil end
  local items = nil
  for id, change in pairs(net) do
    if id ~= itemID then
      if change < 0 then return nil end
      if change > 0 then
        items = items or {}
        items[id] = true
      end
    end
  end
  return items
end

-- Whether the Combine recorder takes this use: only the used item went down,
-- by a count the data combines it in, and one item went up
local function CombineRecorders(itemID, net)
  local ups = 0
  for id, change in pairs(net) do
    if id ~= itemID and change < 0 then return false end
    if change > 0 then ups = ups + 1 end
  end
  if ups ~= 1 then return false end
  for _, combine in ipairs(Host.Combines(itemID)) do
    if combine.count == -(net[itemID] or 0) then return true end
  end
  return false
end

-- Transformation(itemID, net): what the use consumed and gave, as two lists
-- of { id, n } by item ID, when the used item went down and something went
-- up and neither the container rule (Judge, not a count-1 combine) nor the
-- Combine recorder takes it; else nil
function ContainerUse.Transformation(itemID, net)
  if (net[itemID] or 0) >= 0 then return nil end
  if ContainerUse.Judge(itemID, net) and not CombinesOne(itemID) then return nil end
  if CombineRecorders(itemID, net) then return nil end
  local consumed, gained = {}, {}
  for id, change in pairs(net) do
    if change < 0 then consumed[#consumed + 1] = { id = id, n = -change } end
    if change > 0 then gained[#gained + 1] = { id = id, n = change } end
  end
  if #gained == 0 then return nil end
  local byID = function(a, b) return a.id < b.id end
  table.sort(consumed, byID)
  table.sort(gained, byID)
  return consumed, gained
end

function ContainerUse.Finish(which)
  if window ~= which then return end
  window = nil
  if which.ambiguous or next(open) or InCombat() or not Curator.Main.StillCurrent(which.epoch) then return end
  local ctx = which.ctx
  local items = ContainerUse.Judge(which.itemID, which.net)
  if items and not CombinesOne(which.itemID) then
    local sources = { [which.itemID] = { kind = "container", id = which.itemID, items = items } }
    Curator.Main.Defer(function() Curator.Compare.Loot({ sources = sources }, ctx) end)
    return
  end
  local consumed, gained = ContainerUse.Transformation(which.itemID, which.net)
  if not consumed then return end
  Curator.Main.Defer(function() Curator.Compare.Transform(which.itemID, consumed, gained, which.spell, ctx) end)
end

-- A player cast (spellID): opens a window for the one item it uses; a cast
-- of any held item's Use spell while a window is open makes both ambiguous
function ContainerUse.OnCast(spellID)
  if not Curator.Main.MayRecord() or Curator.Main.IsScripted() then return end
  local items = Bags.ItemsForSpell(spellID)
  if #items == 0 then return end
  if window then window.ambiguous = true end
  if #items ~= 1 or InCombat() then return end
  -- the context of the moment of the use, read in the cast's event (Task #421)
  local opened = { itemID = items[1], spell = spellID, epoch = Curator.Main.Epoch(), net = {},
    ambiguous = window ~= nil or next(open) ~= nil, ctx = Curator.Context.Current() }
  window = opened
  ContainerUse.seams.After(Bags.CAST_WINDOW, function() ContainerUse.Finish(opened) end)
end

-- A compared bag change (the observer's, out of combat): added to the
-- open window's net change
function ContainerUse.OnBagsChanged(before, after)
  if not window then return end
  local down, up = Bags.Changes(before, after)
  for _, d in ipairs(down) do window.net[d.id] = (window.net[d.id] or 0) - d.n end
  for _, u in ipairs(up) do window.net[u.id] = (window.net[u.id] or 0) + u.n end
end

-- Loot, a quest's reward, boss loot or combat inside the window: another
-- gain may land in it
function ContainerUse.OnOtherGain()
  if window then window.ambiguous = true end
end

-- An interaction or trade window shown: ambiguous now, and while it stays
-- open when it is one that moves items into the bags
function ContainerUse.OnOpen(kind)
  ContainerUse.OnOtherGain()
  if not Host.IsSecret(kind) and TRACKED[kind] then open[kind] = true end
end

function ContainerUse.OnClose(kind)
  if not Host.IsSecret(kind) and TRACKED[kind] then open[kind] = nil end
end

function ContainerUse.Reset()
  window = nil
  wipe(open)
end

Bags.ListenCasts(function(spellID) ContainerUse.OnCast(spellID) end)
Bags.Subscribe(function(before, after) ContainerUse.OnBagsChanged(before, after) end)

local handlers = {
  LOOT_READY = ContainerUse.OnOtherGain,
  QUEST_TURNED_IN = function() ContainerUse.OnOtherGain() end,   -- its money is never read
  QUEST_LOOT_RECEIVED = function() ContainerUse.OnOtherGain() end,
  ENCOUNTER_LOOT_RECEIVED = function() ContainerUse.OnOtherGain() end,
  BONUS_ROLL_RESULT = function() ContainerUse.OnOtherGain() end,
  PLAYER_REGEN_DISABLED = ContainerUse.OnOtherGain,
  -- a craft's products land in the bags too, and gear put on or taken off
  -- moves items in and out of them (Task #423)
  PLAYER_EQUIPMENT_CHANGED = function() ContainerUse.OnOtherGain() end,
  TRADE_SKILL_CRAFT_BEGIN = function() ContainerUse.OnOtherGain() end,
  TRADE_SKILL_ITEM_CRAFTED_RESULT = function() ContainerUse.OnOtherGain() end,
  PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(kind) ContainerUse.OnOpen(kind) end,
  PLAYER_INTERACTION_MANAGER_FRAME_HIDE = function(kind) ContainerUse.OnClose(kind) end,
  TRADE_SHOW = function() ContainerUse.OnOpen("trade") end,
  TRADE_CLOSED = function() ContainerUse.OnClose("trade") end,
}

-- The event frame's dispatch (a test run scripting the client reads nothing)
function ContainerUse.OnEvent(event, ...)
  if Curator.Main.IsScripted() or not handlers[event] then return end
  local ok, err = pcall(handlers[event], ...)
  if not ok then Host.Log("Container use recorder %s failed: %s", event, tostring(err)) end
end

local frame = CreateFrame("Frame")
ContainerUse.frame = frame   -- its events, for a development timing probe (Task #294)
for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...) ContainerUse.OnEvent(event, ...) end)
