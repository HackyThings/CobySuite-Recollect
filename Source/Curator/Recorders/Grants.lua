-------------------------------------------------------------------------------
-- Curator recorder: what using an item gives (curator spec, "v1 recorders";
-- research note I section 7)
--
-- A player cast out of combat whose spell is the Use spell of exactly one
-- item in the bags opens a window of the bag observer's CAST_WINDOW
-- seconds. Every CURRENCY_DISPLAY_UPDATE with a positive quantityChange in
-- it is summed by currency. When the window closes with exactly one currency gained, and no
-- loot window or quest turn-in fell inside it (another gain could have
-- landed), and combat didn't start in it, Compare.Grant records it in a
-- later frame: a random amount is never a conflict. A second item cast
-- while a window is open makes both ambiguous.
-- Reputation gains have no amount event (they need a before and after read
-- of candidate factions, U7), so they are not recorded yet.
--
-- Only while curator mode may record, and never while a test run scripts
-- the client. Client reads go through Grants.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Bags = Curator.Recorders.Bags

local Grants = {}
Curator.Recorders.Grants = Grants

Grants.seams = {
  After = function(delay, fn) C_Timer.After(delay, fn) end,
  InCombat = function() return InCombatLockdown() end,
}

local window = nil   -- { itemID, epoch, gains = { [currencyID] = amount }, ambiguous }

local function InCombat()
  local ok, value = pcall(Grants.seams.InCombat)
  return not ok or Host.IsSecret(value) or value == true
end

function Grants.Finish(which)
  if window ~= which then return end
  window = nil
  if which.ambiguous or InCombat() or not Curator.Main.StillCurrent(which.epoch) then return end
  local currency, amount = next(which.gains)
  if currency and next(which.gains, currency) == nil then
    Curator.Main.Defer(function() Curator.Compare.Grant(which.itemID, currency, amount, Curator.Context.Current()) end)
  end
end

-- A player cast (spellID): opens a window for the one item it uses. In
-- combat nothing is opened (a kill's currency would land in it), and a
-- cast while a window is open makes both windows ambiguous (a delayed gain
-- could belong to either).
function Grants.OnCast(spellID)
  if not Curator.Main.MayRecord() then return end
  if InCombat() then
    if window then window.ambiguous = true end
    return
  end
  local items = Bags.ItemsForSpell(spellID)
  if #items ~= 1 then return end
  local opened = { itemID = items[1], epoch = Curator.Main.Epoch(), gains = {} }
  if window then
    window.ambiguous = true
    opened.ambiguous = true
  end
  window = opened
  Grants.seams.After(Bags.CAST_WINDOW, function() Grants.Finish(opened) end)
end

-- CURRENCY_DISPLAY_UPDATE (currencyType, quantity, quantityChange,
-- quantityGainSource, destroyReason)
function Grants.OnCurrency(currencyID, _, change)
  if not window then return end
  if Host.IsSecret(currencyID) or Host.IsSecret(change) then
    window.ambiguous = true
    return
  end
  if Bags.PositiveID(currencyID) and type(change) == "number" and change > 0 then
    window.gains[currencyID] = (window.gains[currencyID] or 0) + change
  end
end

-- A loot window, a quest turn-in or combat inside the window: another gain
-- may land in it
function Grants.OnOtherGain()
  if window then window.ambiguous = true end
end

function Grants.Reset()
  window = nil
end

Bags.ListenCasts(function(spellID) Grants.OnCast(spellID) end)

local handlers = {
  CURRENCY_DISPLAY_UPDATE = Grants.OnCurrency,
  LOOT_READY = Grants.OnOtherGain,
  QUEST_TURNED_IN = Grants.OnOtherGain,
  PLAYER_REGEN_DISABLED = Grants.OnOtherGain,
}

local frame = CreateFrame("Frame")
for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...)
  if Curator.Main.IsScripted() or not Curator.Main.MayRecord() then return end
  local ok, err = pcall(handlers[event], ...)
  if not ok then Host.Log("Grants recorder %s failed: %s", event, tostring(err)) end
end)
