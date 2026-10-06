-------------------------------------------------------------------------------
-- Purpose: junk, by the game's own rule
--
-- Blizzard's bags mark an item as junk when its quality is Poor and it has a
-- vendor price (ContainerFrameItemButtonMixin:UpdateJunkItem: quality ==
-- Enum.ItemQuality.Poor and not noValue), and Sell All Junk takes exactly
-- those. That is the Junk verdict here, its reason saying what junk is
-- (Cobanyte, 2026-09-24: junk is not "outdated"). Any other check's Unknown
-- (a quest item, a reagent, a known use) still wins (Verdicts.Combine), and a
-- Poor item with no vendor price is not junk to the game, so this check says
-- nothing about it.
--
-- The vendor price: the slot read's hasNoValue (C_Container) when there is
-- one, else the item's sell price (a slot whose read gave no answer).
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber

R.Register({
  key = "junk",
  accountWide = true,   -- the same answer for any character's copy
  label = "Junk",
  order = 95,
  Evaluate = function(ctx)
    if ctx.facts.quality ~= R.QUALITY_POOR then return nil end
    local noValue = ctx.stack.hasNoValue
    if type(noValue) ~= "boolean" then
      local price = ctx.facts.sellPrice
      if not IsFiniteNumber(price) then return nil end
      noValue = price <= 0
    end
    if noValue then return nil end
    return R.Result(V.JUNK, "Junk: the game marks gray (Poor quality) items that have a vendor price as junk, and a merchant's Sell All Junk button takes them all at once")
  end,
})
