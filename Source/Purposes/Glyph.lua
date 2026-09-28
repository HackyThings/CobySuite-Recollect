-------------------------------------------------------------------------------
-- Purpose: a glyph or grimoire (item class 16)
--
-- The only thing the client says about a glyph item is its tooltip: "Already
-- known" once this character has it, red lines for a class or reputation
-- this character doesn't meet. No call says whether a glyph is on its spell
-- right now (HasAttachedGlyph needs the spell, which no call links to the
-- item), so a glyph that isn't known stays Unknown, with what could be read
-- as the reason. Known is done only for a copy no other character could use.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict

R.Register({
  key = "glyph",
  label = "Glyph",
  order = 72,
  Evaluate = function(ctx)
    if ctx.facts.classID ~= R.CLASS_GLYPH then return nil end
    local tip = ctx.Tooltip()
    if not tip then return R.Unknown("Glyph; its tooltip can't be read") end
    if tip.known then
      if R.CharacterOnlyCopy(ctx) then return R.Result(V.DONE, "Duplicate: this character already knows it") end
      return R.Unknown("Glyph known here; another character may still need it")
    end
    if tip.redLines > 0 then return R.Unknown("Glyph this character can't use (see its tooltip)") end
    return R.Unknown("Glyph this character can use; whether it's already on its spell can't be read")
  end,
})
