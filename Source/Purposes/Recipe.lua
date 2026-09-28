-------------------------------------------------------------------------------
-- Purpose: a recipe item (item class 9)
--
-- Only the tooltip says whether this character knows a recipe with the
-- profession window closed ("Already known"), so recipes are checked in the
-- bags, where the tooltip is read live. A red line means a requirement this
-- character does not meet (profession, skill, reputation): Unknown. Known is
-- done only for a copy no other character could use.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict

R.Register({
  key = "recipe",
  label = "Recipe",
  order = 70,
  Evaluate = function(ctx)
    if ctx.facts.classID ~= R.CLASS_RECIPE then return nil end
    if not ctx.live or ctx.kind ~= "bags" then return R.Unknown("Recipe; recipes are checked in your bags only") end
    local tip = ctx.Tooltip()
    if not tip then return R.Unknown("Recipe; its tooltip can't be read") end
    if tip.known then
      if R.CharacterOnlyCopy(ctx) then return R.Result(V.DONE, "Duplicate: this character already knows this recipe") end
      return R.Unknown("Recipe known here; another character may still need it")
    end
    if tip.redLines > 0 then return R.Unknown("Recipe you can't learn yet (see its tooltip)") end
    return R.Result(V.USE, "Recipe not known on this character; learn it")
  end,
})
