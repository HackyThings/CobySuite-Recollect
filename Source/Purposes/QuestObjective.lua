-------------------------------------------------------------------------------
-- Purpose: an item a quest's objective names (Facts.Relations "objective",
-- from the game's own quest data) or a quest uses (Facts.Relations
-- "questItem", from AllTheThings), with the quest's state read live
--
--   you are on one of those quests            Needed, naming it
--   one you haven't done (or a repeatable)    Useful, naming it
--   one done whose frequency the data gives   Useful: a yearly, weekly,
--   (daily, weekly, yearly, monthly, a world  daily or world quest comes
--   quest, repeatable)                        back (G-03)
--   a quest's data still loading              Unknown
--   every one completed                       Unknown, naming it: from outside
--                                             the log a yearly quest reads like
--                                             a one-time one (contract rule 7),
--                                             so a completed quest with no
--                                             frequency in the data never makes
--                                             the item leftover
--
-- Every quest the data names is read (BA-13), those in the quest log first;
-- a quest not loaded yet is asked of the server a batch at a time
-- (QuestInfo.FrameBudget, shared by everything that reads quests in a
-- frame), and each answer brings a new evaluation that asks for the next
-- batch. A quest that any of the item's codes names as no longer in the game,
-- or for another faction, class or race (Relations.QuestApplies), never
-- counts. An account quest counts as done when the account has done it.
--
-- When no quest serves this character but some are for another faction,
-- class or race (the Shadowmourne quest's Acidic Bloods on an Evoker), the
-- check is Unknown naming them, never Useful (rule 32); one whose condition
-- the owner's record can't answer is Unknown, category character. Every
-- quest completed carries settled (Verdicts.Combine).
--
-- Quests of one title (one per faction) are one quest, as in the panel's
-- USED FOR lines: the other faction's copy never reads completed here, so a
-- title completed on any of its quests counts as completed, unless the
-- quest is repeatable.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try

local LEAD = { objective = "Objective of", questItem = "Used in" }
local RECURS = { { "y", "a yearly quest" }, { "m", "a monthly quest" }, { "w", "a weekly quest" }, { "d", "a daily quest" },
  { "q", "a world quest" }, { "r", "a repeatable quest" } }

-- The item's quests that serve this character: objectives first, then the
-- quests that use it, each once; those in the quest log ahead of the rest
-- Also the quests left out for another faction, class or race ("other",
-- with their relations) and those whose condition the owner's record can't
-- answer ("unknown"), each once: { other = { relation }, unknown = { relation } }
local function QuestRelations(itemID, owner)
  local Relations = Recollect.Facts.Relations
  local inLog, rest, seen = {}, {}, {}
  local restricted = { other = {}, unknown = {} }
  local client = Recollect.Purposes.client
  -- A quest counts only when every code naming it serves this character
  local serves = Relations.QuestApplies(itemID, owner)
  for _, kind in ipairs({ "objective", "questItem" }) do
    for _, relation in ipairs(Relations.Of(itemID, kind)) do
      if not seen[relation.id] and serves[relation.id] == true then
        seen[relation.id] = true
        local ok, on = Try(client.IsOnQuest, relation.id)
        local into = ok and on == true and inLog or rest
        into[#into + 1] = relation
      elseif not seen[relation.id] and restricted[serves[relation.id]] then
        seen[relation.id] = true
        local list = restricted[serves[relation.id]]
        list[#list + 1] = relation
      end
    end
  end
  for _, relation in ipairs(rest) do inLog[#inLog + 1] = relation end
  return inLog, restricted
end

-- "\"Title\"", "\"Title\" and 1 more quest": the first quest named, by its
-- title once loaded
local function Named(list)
  local title = Recollect.Facts.QuestLog.Title(list[1].id)
  local text = title and ("\"" .. title .. "\"") or "a quest"
  if #list > 1 then text = ("%s and %d more %s"):format(text, #list - 1, #list == 2 and "quest" or "quests") end
  return text
end

-- The answer when no quest serves this character: nil when none is
-- restricted either (every one gone, which the "removed" check says)
local function Restricted(restricted, owner, itemID)
  local Relations = Recollect.Facts.Relations
  if #restricted.other > 0 then
    -- the conditions of every code naming those quests (QuestApplies' view)
    local ids, named = {}, {}
    for _, relation in ipairs(restricted.other) do ids[relation.id] = true end
    for _, relation in ipairs(Relations.For(itemID)) do
      if ids[relation.id] and relation.flags and not Relations.SOURCE[relation.kind] then named[#named + 1] = relation end
    end
    local words = R.KindWords((R.Restrictions(named, owner)))
    local headline = ("Used in %s for another %s"):format(Named(restricted.other), words)
    return R.Unknown(headline, headline)
  end
  if #restricted.unknown > 0 then
    return R.Unknown(("Used in %s; whether it's for this character isn't recorded yet"):format(Named(restricted.unknown)),
      nil, "character")
  end
  return nil
end

-- How a quest the data gives a frequency for recurs ("a yearly quest"), or nil
local function Recurs(questID)
  local flags = Recollect.Facts.Relations.Frequency(questID)
  if not flags then return nil end
  for _, entry in ipairs(RECURS) do
    if flags:find(entry[1], 1, true) then return entry[2] end
  end
  return nil
end
Recollect.Purposes.QuestRecurs = Recurs

local function Title(quest)
  return quest.title and ("\"" .. quest.title .. "\"") or ("quest " .. quest.questID)
end

R.Register({
  key = "questObjective",
  label = "Quest objective",
  order = 55,
  Evaluate = function(ctx)
    local owner = ctx.owner or { faction = ctx.playerFaction }
    local objectives, restricted = QuestRelations(ctx.stack.itemID, owner)
    if #objectives == 0 then return Restricted(restricted, owner, ctx.stack.itemID) end
    if not Recollect.Facts.Ready.Quests() then return R.Unknown("Quest objective; your quest history hasn't loaded yet", nil, "loading") end
    local QuestInfo = Recollect.Facts.QuestInfo
    local quests, doneTitles, budget = {}, {}, QuestInfo.FrameBudget()
    for i, relation in ipairs(objectives) do
      local quest = QuestInfo.Get(relation.id, budget)
      quests[i] = quest or false
      if quest and QuestInfo.Done(quest) == true and quest.title then doneTitles[quest.title] = true end
    end
    local on, open, done, loading = nil, nil, nil, 0
    for i, relation in ipairs(objectives) do
      local quest = quests[i]
      -- Done for this character, or for the account when it is an account quest
      local completed = quest and QuestInfo.Done(quest)
      if not quest then
        loading = loading + 1
      elseif quest.onQuest == true then
        on = on or { quest, relation }
      elseif quest.repeatable == true then
        open = open or { quest, relation, "a repeatable quest" }
      elseif completed == true and Recurs(relation.id) then
        open = open or { quest, relation, Recurs(relation.id) .. " that comes back" }
      elseif completed == false and quest.title and doneTitles[quest.title] then
        -- the other copy of a title you've completed: that one decides
      elseif completed == false then
        open = open or { quest, relation, "a quest you haven't done" }
      elseif completed == true then
        done = done or { quest, relation }
      else
        loading = loading + 1   -- a state that could not be read
      end
    end
    if on then
      local count = on[2].count or 1
      return R.Result(V.NEEDED, ("%s %s, which you're on%s"):format(LEAD[on[2].kind] or LEAD.objective, Title(on[1]),
        count > 1 and (" (it needs %d)"):format(count) or ""))
    end
    if open then return R.Result(V.USEFUL, ("Used by %s, %s"):format(Title(open[1]), open[3])) end
    if loading > 0 then
      return R.Unknown(("Quest objective; %d %s still being checked"):format(loading, loading == 1 and "quest is" or "quests are"),
        nil, "loading")
    end
    local result = R.Unknown(("%s %s, which you've completed; a yearly quest would need it again"):format(
      LEAD[done[2].kind] or LEAD.objective, Title(done[1])))
    result.settled = true
    return result
  end,
})
