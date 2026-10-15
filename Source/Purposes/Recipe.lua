-------------------------------------------------------------------------------
-- Purpose: a recipe item (item class 9)
--
-- This check reads whether this character knows a recipe from its tooltip
-- ("Already known"), which only a read made now keeps current: a copy in the
-- bags reads its slot, and a copy in the bank or the warband bank, kept from
-- a snapshot, reads its item link's tooltip now (Task #339). A red line means a requirement this
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
    -- what it teaches is gone from the game (every p and r code flagged x):
    -- no "learn it"; the removed check says what it was (Task #446). With
    -- an X record too (every way to get it gone: the recipes AllTheThings
    -- files only under Never Implemented, all 376 the sweep moved), its Use
    -- effect is that teaching, so it is accounted for and the removed
    -- check's Outdated stands (Cobanyte's decision, rule 42); without one it
    -- stays silent and the Use effect keeps it Can't tell
    if R.AllGone(ctx.stack.itemID, { "recipeFor", "teaches" }) then
      if Recollect.Facts.Relations.Removed(ctx.stack.itemID) == nil then return nil end
      local result = R.Info("Recipe; what it teaches is no longer in the game")
      result.useAccounted = true
      return result
    end
    local tip
    if ctx.live then
      tip = ctx.Tooltip()
    elseif ctx.otherCharacter then
      return R.Unknown("Recipe; whether it's known is checked only on the character logged in", nil, "character")
    else
      -- a link tooltip read before the recipe's spell loads has no Use line,
      -- and may lack "Already known" too (contract rule 14)
      if ctx.facts.spellLoading then return R.Unknown("Recipe; its tooltip is still loading", nil, "loading") end
      if ctx.facts.spellFailed then return R.Unknown("Recipe; its tooltip can't be loaded", nil, "unreadable") end
      tip = Recollect.Facts.Tooltip.FromLink(ctx.stack.link)
      if tip and ctx.facts.hasSpell ~= false and type(tip.useText) ~= "string" then
        return R.Unknown("Recipe; its tooltip read shows no Use line yet", nil, "loading")
      end
    end
    if not tip then return R.Unknown("Recipe; its tooltip can't be read") end
    if tip.known then
      if R.CharacterOnlyCopy(ctx) then return R.Result(V.DONE, "Duplicate: this character already knows this recipe") end
      return R.Unknown("Recipe known here; another character may still need it")
    end
    if tip.redLines > 0 then return R.Unknown("Recipe you can't learn yet (see its tooltip)") end
    return R.Result(V.USE, "Recipe not known on this character; learn it")
  end,
})
