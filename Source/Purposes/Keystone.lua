-------------------------------------------------------------------------------
-- Purpose: the Mythic+ keystone (item class 5, Reagent; subclass 1,
-- Keystone). One per character, bound, and the only way into that week's
-- Mythic+ dungeon: Useful.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict

R.Register({
  key = "keystone",
  label = "Keystone",
  order = 66,
  Evaluate = function(ctx)
    if ctx.facts.classID ~= R.CLASS_REAGENT or ctx.facts.subclassID ~= R.REAGENT_KEYSTONE then return nil end
    return R.Result(V.USEFUL, "Your Mythic+ keystone")
  end,
})
