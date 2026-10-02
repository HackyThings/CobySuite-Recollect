-------------------------------------------------------------------------------
-- Purpose: an achievement criterion AllTheThings links the item to
-- (Facts.Relations "linked": ATT's item providers on a criterion, l<ach>.<crit>)
--
-- A link is never a need (SRC-06, B10): the game's own data doesn't name the
-- item for that criterion, so this check never says Needed. It reads the
-- achievement live: its name, whether it is earned (Facts.Achievements.
-- Progress, with how far along and whether it is account-wide) and whether
-- the linked criteria are done. Every link to one achievement is read
-- together, the criteria once (Facts.Achievements.Parts, with the item, so
-- a criterion whose ID reads 0 is found by the item's name, as the panel
-- reads it; review F1 and F2: Black Claw of Sethe has 72 links to one
-- achievement).
--
--   a linked part not done, achievement not earned   Useful, naming the
--                                                    achievement and its
--                                                    progress
--   every link earned or done                        informs only, naming it;
--                                                    settled, with its done
--                                                    words (result.done)
--   an achievement or a linked part that can't be    Unknown (a part not found
--   read                                             or a failed read is never
--                                                    done)
--   a link no longer in the game, or not for the     left out (rule 32)
--   copy's owner
--   another character's copy of an achievement not   Unknown: its progress,
--   known to be account-wide                         open or done, may be the
--                                                    logged-in character's
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict

local Linked = {}
Recollect.Purposes.Linked = Linked

-- The live state of every link to one achievement: { name, open (true: a
-- linked part still to do, false: earned or every linked part done),
-- progress (Progress's words), accountWide } or nil when it can't be read.
-- An earned achievement is read once (Progress keeps it for a few seconds),
-- never criterion by criterion.
function Linked.State(achievementID, criteriaIDs, itemID)
  local Achievements = Recollect.Facts.Achievements
  local progress = Achievements.Progress(achievementID)
  if not progress then return nil end
  local words = Achievements.ProgressWords(progress)
  if progress.earned then
    return { name = progress.name, open = false, earned = true, progress = words, accountWide = progress.accountWide }
  end
  local state = Achievements.PartsState(Achievements.Parts(achievementID, criteriaIDs, itemID))
  if state == nil then return nil end
  return { name = progress.name, open = state == "open", progress = words, accountWide = progress.accountWide }
end

-- The owner's words for another character's copy when the achievement is not
-- known to be account-wide, or nil
local function PerCharacter(ctx, state)
  if not ctx.otherCharacter or state.accountWide == true then return nil end
  return state.accountWide == false and "that progress is this character's"
    or "whether its progress is account-wide can't be read"
end

R.Register({
  key = "linked",
  accountWide = true,   -- the achievement's state, with a guard for per-character progress below
  label = "Linked achievement",
  order = 57,
  Evaluate = function(ctx)
    -- Only links that serve the copy's owner (rule 32: one no longer in the
    -- game, or for another faction or class, never makes it Useful)
    local Relations = Recollect.Facts.Relations
    local owner = ctx.owner or { faction = ctx.playerFaction }
    local links = {}
    for _, relation in ipairs(Relations.Of(ctx.stack.itemID, "linked")) do
      if Relations.Applies(relation, owner) == true then links[#links + 1] = relation end
    end
    if #links == 0 then return nil end
    -- Every link to one achievement together, in the data's order
    local order, byAchievement = {}, {}
    for _, relation in ipairs(links) do
      local list = byAchievement[relation.id]
      if not list then
        list = {}
        byAchievement[relation.id] = list
        order[#order + 1] = relation.id
      end
      list[#list + 1] = relation.criteria
    end
    local open, closed, unreadable, openCount = nil, nil, false, 0
    for _, achievementID in ipairs(order) do
      local state = Linked.State(achievementID, byAchievement[achievementID], ctx.stack.itemID)
      if not state then
        unreadable = true
      elseif state.open then
        openCount = openCount + 1
        open = open or state
      else
        closed = closed or state
      end
    end
    if open then
      local more = openCount > 1 and (" and %d more %s"):format(openCount - 1, openCount == 2 and "achievement" or "achievements") or ""
      local text = ("Linked to a part of the achievement \"%s\" not done yet (%s)%s"):format(
        open.name, open.progress, more)
      local why = PerCharacter(ctx, open)
      if why then
        return R.Unknown(("%s; %s, so checked fully only on %s"):format(text, why, ctx.otherCharacter),
          ("Linked to the achievement \"%s\""):format(open.name), "character")
      end
      return R.Result(V.USEFUL, text)
    end
    if unreadable then return R.Unknown("Linked to an achievement; its criteria can't be read", nil, "unreadable") end
    local headline = ("Linked to the achievement \"%s\""):format(closed.name)
    local text = ("%s (%s): the part it's linked to is done"):format(headline, closed.progress)
    -- Done on another character's copy may be the logged-in character's state (review F4)
    local why = PerCharacter(ctx, closed)
    if why then
      return R.Unknown(("%s; %s, so checked fully only on %s"):format(text, why, ctx.otherCharacter), headline, "character")
    end
    local result = R.Info(text)
    result.headline = headline
    result.settled = true
    -- the words that say it's done (UI.Icons.MarkDone): the achievement
    -- earned, else only the linked part
    result.done = { closed.earned and closed.progress or "the part it's linked to is done" }
    return result
  end,
})
