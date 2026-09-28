-------------------------------------------------------------------------------
-- Purpose: an item a task of the neighborhood endeavor running now names
-- (Facts.Endeavors: Home-Grown Wax in "Candle Culture"), read live;
-- contract rule 40
--
--   a task that names it is open           Useful, naming the endeavor, the
--                                          task, its progress and the
--                                          endeavor's
--   only tasks whose state can't be read   Unknown (unreadable)
--   every task that names it is done       Unknown: the endeavor's use is
--                                          known and finished for now, and
--                                          whether it counts again (another
--                                          endeavor, a repeat) can't be read,
--                                          so no other check may call the
--                                          item Outdated or done (rule 3)
--   no endeavor, not loaded, not named     nothing: outside an active
--                                          endeavor nothing says the item
--                                          belongs to one
-- The endeavor is the logged-in character's neighborhood's, so another
-- character's copy is not judged here.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict

local function Quote(text) return "\"" .. tostring(text) .. "\"" end

-- "; the endeavor is at 340 of 1000", or ""
local function EndeavorProgress()
  local Endeavors = Recollect.Facts.Endeavors
  local words = Endeavors.ProgressWords((Endeavors.Get()))
  return words and ("; the endeavor is at " .. words) or ""
end

-- " and 2 more open tasks", or ""
local function More(n, what)
  if n <= 0 then return "" end
  return (" and %d more %s %s"):format(n, what, n == 1 and "task" or "tasks")
end

R.Register({
  key = "endeavor",
  label = "Endeavor",
  order = 11,
  Evaluate = function(ctx)
    local uses = Recollect.Facts.Endeavors.UsesOf(ctx.stack.itemID)
    if not uses then return nil end
    local open, done, unread = {}, {}, {}
    for _, use in ipairs(uses) do
      if use.done == false then open[#open + 1] = use
      elseif use.done == true then done[#done + 1] = use
      else unread[#unread + 1] = use end
    end
    local title = uses[1].title
    local headline = "Used in the endeavor " .. Quote(title)
    if #open > 0 then
      local first = open[1]
      return R.Result(V.USEFUL, ("The neighborhood endeavor %s has an open task that names it: %s (%s)%s%s"):format(
        Quote(title), Quote(first.taskName), first.progressText, More(#open - 1, "open"), EndeavorProgress()))
    end
    if #unread > 0 then
      return R.Unknown(("The neighborhood endeavor %s has a task that names it, %s, whose state can't be read"):format(
        Quote(title), Quote(unread[1].taskName)), headline, "unreadable")
    end
    return R.Unknown(("The neighborhood endeavor %s names it in %s, which you've done%s"):format(
      Quote(title), Quote(done[1].taskName), More(#done - 1, "done")), headline)
  end,
})
