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

local window = nil   -- { itemID, epoch, net = { [itemID] = change }, ambiguous }
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

function ContainerUse.Finish(which)
  if window ~= which then return end
  window = nil
  if which.ambiguous or next(open) or InCombat() or not Curator.Main.StillCurrent(which.epoch) then return end
  local items = ContainerUse.Judge(which.itemID, which.net)
  if not items then return end
  local sources = { [which.itemID] = { kind = "container", id = which.itemID, items = items } }
  Curator.Main.Defer(function()
    if CombinesOne(which.itemID) then return end
    Curator.Compare.Loot({ sources = sources }, Curator.Context.Current())
  end)
end

-- A player cast (spellID): opens a window for the one item it uses; a cast
-- of any held item's Use spell while a window is open makes both ambiguous
function ContainerUse.OnCast(spellID)
  if not Curator.Main.MayRecord() or Curator.Main.IsScripted() then return end
  local items = Bags.ItemsForSpell(spellID)
  if #items == 0 then return end
  if window then window.ambiguous = true end
  if #items ~= 1 or InCombat() then return end
  local opened = { itemID = items[1], epoch = Curator.Main.Epoch(), net = {}, ambiguous = window ~= nil or next(open) ~= nil }
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
for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...) ContainerUse.OnEvent(event, ...) end)
