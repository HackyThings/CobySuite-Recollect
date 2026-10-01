-------------------------------------------------------------------------------
-- Curator recorder: what using an item gives (curator spec, "v1 recorders";
-- research note I section 7)
--
-- A player cast out of combat whose spell is the Use spell of exactly one
-- item in the bags opens a window of the bag observer's CAST_WINDOW
-- seconds. Every CURRENCY_DISPLAY_UPDATE with a positive quantityChange in
-- it is summed by currency. When the window closes with exactly one currency gained, and no
-- loot window, quest turn-in or craft fell inside it (another gain could
-- have landed: a first craft gives profession knowledge, the same currency
-- as a notebook), and combat didn't start in it, Compare.Grant records it in a
-- later frame: a random amount is never a conflict. A cast of any held
-- item's Use spell while a window is open (one shared by several items
-- included) makes both ambiguous.
-- A currency at its total, seasonal or weekly cap when the window closes
-- records nothing: the gain may have been cut short by the cap, so the
-- amount seen may be less than the item gives. A cap that can't be read
-- records nothing either.
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
  CurrencyInfo = function(currencyID) return C_CurrencyInfo.GetCurrencyInfo(currencyID) end,
}

local window = nil   -- { itemID, epoch, gains = { [currencyID] = amount }, ambiguous }

local function InCombat()
  local ok, value = pcall(Grants.seams.InCombat)
  return not ok or Host.IsSecret(value) or value == true
end

-- A number field of a currency's info, or nil when missing or secret
local function Field(info, key)
  local value = info[key]
  if Host.IsSecret(value) or type(value) ~= "number" then return nil end
  return value
end

-- Whether a currency may have been held back by a cap: true when its total
-- (or, for a seasonal cap, its total earned) or its week's earnings are at
-- the most it allows, or when its info can't be read
function Grants.AtCap(currencyID)
  local ok, info = pcall(Grants.seams.CurrencyInfo, currencyID)
  if not ok or type(info) ~= "table" or (issecrettable and issecrettable(info)) then return true end
  local max, weeklyMax = Field(info, "maxQuantity"), Field(info, "maxWeeklyQuantity")
  if not max or not weeklyMax then return true end
  if max > 0 then
    local seasonal = info.useTotalEarnedForMaxQty
    if Host.IsSecret(seasonal) then return true end
    local held = Field(info, seasonal == true and "totalEarned" or "quantity")
    if not held or held >= max then return true end
  end
  if weeklyMax > 0 then
    local week = Field(info, "quantityEarnedThisWeek")
    if not week or week >= weeklyMax then return true end
  end
  return false
end

function Grants.Finish(which)
  if window ~= which then return end
  window = nil
  if which.ambiguous or InCombat() or not Curator.Main.StillCurrent(which.epoch) then return end
  local currency, amount = next(which.gains)
  if currency and next(which.gains, currency) == nil and not Grants.AtCap(currency) then
    Curator.Main.Defer(function() Curator.Compare.Grant(which.itemID, currency, amount, Curator.Context.Current()) end)
  end
end

-- A player cast (spellID): opens a window for the one item it uses. In
-- combat nothing is opened (a kill's currency would land in it), and a
-- cast of any held item's Use spell while a window is open, one several
-- items share included, makes both windows ambiguous (a delayed gain could
-- belong to either; as ContainerUse.OnCast)
function Grants.OnCast(spellID)
  if not Curator.Main.MayRecord() then return end
  if InCombat() then
    if window then window.ambiguous = true end
    return
  end
  local items = Bags.ItemsForSpell(spellID)
  if #items == 0 then return end
  if window then window.ambiguous = true end
  if #items ~= 1 then return end
  local opened = { itemID = items[1], epoch = Curator.Main.Epoch(), gains = {} }
  if window then opened.ambiguous = true end
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

-- A loot window, a quest turn-in, a craft or combat inside the window:
-- another gain may land in it. A craft's recipe spell is no bag item's Use
-- spell, so OnCast never sees it; its trade skill events mark the window
-- instead, whichever comes first of them and the currency update.
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
  TRADE_SKILL_CRAFT_BEGIN = Grants.OnOtherGain,
  TRADE_SKILL_ITEM_CRAFTED_RESULT = Grants.OnOtherGain,
  TRADE_SKILL_CURRENCY_REWARD_RESULT = Grants.OnOtherGain,
}

-- The event frame's dispatch (a test run scripting the client, or curator
-- mode unable to record, reads nothing)
function Grants.OnEvent(event, ...)
  if Curator.Main.IsScripted() or not Curator.Main.MayRecord() or not handlers[event] then return end
  local ok, err = pcall(handlers[event], ...)
  if not ok then Host.Log("Grants recorder %s failed: %s", event, tostring(err)) end
end

local frame = CreateFrame("Frame")
for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...) Grants.OnEvent(event, ...) end)
