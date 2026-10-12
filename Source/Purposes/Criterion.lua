-------------------------------------------------------------------------------
-- Purpose: an item an achievement's criterion counts (Facts.Relations
-- "criterion": obtain, use or loot this item), read live
--
--   achievement not earned, that criterion not done   Needed, naming it
--   earned, or that criterion done                     informs only, settled,
--                                                      with its done words
--   the achievement or criterion can't be read         Unknown
--   another character's copy of an achievement not     Unknown, category
--   earned and not known to be account-wide            character: the
--                                                      criterion's progress is
--                                                      the logged-in
--                                                      character's (Task #315 ACH-01)
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict

-- The owner's words for another character's copy of an achievement not
-- earned and not known to be account-wide, or nil (Linked's words)
local function PerCharacter(ctx, a, achievementID)
  if not ctx.otherCharacter or a.earned then return nil end
  local wide = Recollect.Facts.Achievements.AccountWide(achievementID)
  if wide == true then return nil end
  return wide == false and "that progress is this character's" or "whether its progress is account-wide can't be read"
end

R.Register({
  key = "criterion",
  accountWide = true,   -- earned is the account's; a criterion's progress is guarded per character below
  label = "Achievement",
  order = 56,
  Evaluate = function(ctx)
    local criteria = Recollect.Facts.Relations.Of(ctx.stack.itemID, "criterion")
    if #criteria == 0 then return nil end
    local needed, done, unreadable, perCharacter
    for _, relation in ipairs(criteria) do
      local a = Recollect.Facts.Achievements.Get(relation.id, relation.criteria)
      local why = a and PerCharacter(ctx, a, relation.id)
      if not a or (not a.earned and a.criterionDone == nil) then
        unreadable = true
      elseif why then
        perCharacter = perCharacter or { a = a, why = why }
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
    if perCharacter then
      local headline = ("Counts toward the achievement \"%s\""):format(perCharacter.a.name)
      return R.Unknown(("%s; %s, so checked fully only on %s"):format(headline, perCharacter.why, ctx.otherCharacter),
        headline, "character")
    end
    if unreadable then return R.Unknown("Achievement; its criteria can't be read") end
    local result
    if done.earned then
      result = R.Info(("Counts toward the achievement \"%s\", which you've earned"):format(done.name))
      result.done = { "you've earned" }   -- the words that say it's done (UI.Icons.MarkDone)
    else
      result = R.Info(("Counts toward the achievement \"%s\"; you've done that part of it"):format(done.name))
      result.done = { "you've done that part of it" }
    end
    result.settled = true
    return result
  end,
})
