-------------------------------------------------------------------------------
-- Purpose: a gem (item class 3)
--
-- Gems are made anew for each expansion, like potions: one from an older
-- expansion is Outdated, one from the current expansion is Useful. Older
-- means both the game's expansionID and AllTheThings' added patch are below
-- GetServerExpansionLevel (Facts.Item.Age, as Consumable); when the game says
-- older and the added patch current, it is Unknown naming both.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict

local CLASS_GEM = (Enum and Enum.ItemClass and Enum.ItemClass.Gem) or 3

R.Register({
  key = "gem",
  label = "Gem",
  order = 67,
  Evaluate = function(ctx)
    if ctx.facts.classID ~= CLASS_GEM then return nil end
    local age, expansion, source, patch = R.Age(ctx)
    if not age then return R.Unknown("Gem; its expansion can't be read") end
    if age == "current" then return R.Result(V.USEFUL, "A current-expansion gem") end
    local UseEffect = Recollect.Purposes.UseEffect
    if age == "disagree" then
      return R.Unknown(("A gem; %s, so whether a newer one replaces it can't be told"):format(
        UseEffect.Disagree(ctx.facts, expansion, patch)))
    end
    return R.Result(V.OUTDATED, ("A gem %s, an older expansion"):format(UseEffect.From(expansion, source, patch)))
  end,
})
