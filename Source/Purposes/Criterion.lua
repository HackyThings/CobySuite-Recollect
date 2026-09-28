-------------------------------------------------------------------------------
-- Purpose: an item an achievement's criterion counts (Facts.Relations
-- "criterion": obtain, use or loot this item), read live
--
--   achievement not earned, that criterion not done   Needed, naming it
--   earned, or that criterion done                     informs only, settled
--   the achievement or criterion can't be read         Unknown
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict

R.Register({
  key = "criterion",
  accountWide = true,   -- the same answer for any character's copy
  label = "Achievement",
  order = 56,
  Evaluate = function(ctx)
    local criteria = Recollect.Facts.Relations.Of(ctx.stack.itemID, "criterion")
    if #criteria == 0 then return nil end
    local needed, done, unreadable
    for _, relation in ipairs(criteria) do
      local a = Recollect.Facts.Achievements.Get(relation.id, relation.criteria)
      if not a or (not a.earned and a.criterionDone == nil) then
        unreadable = true
      elseif not a.earned and a.criterionDone == false then
        needed = needed or a
      else
        done = done or a
      end
    end
    if needed then
      local progress = ""
      if type(needed.required) == "number" and needed.required > 1 and type(needed.quantity) == "number" then
        progress = (" (%d of %d)"):format(needed.quantity, needed.required)
      end
      return R.Result(V.NEEDED, ("Counts toward the achievement \"%s\"%s"):format(needed.name, progress))
    end
    if unreadable then return R.Unknown("Achievement; its criteria can't be read") end
    local result
    if done.earned then
      result = R.Info(("Counts toward the achievement \"%s\", which you've earned"):format(done.name))
    else
      result = R.Info(("Counts toward the achievement \"%s\"; you've done that part of it"):format(done.name))
    end
    result.settled = true
    return result
  end,
})
