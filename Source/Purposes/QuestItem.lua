-------------------------------------------------------------------------------
-- Purpose: a quest item that does not start a quest
--
-- Linked to the quests in the player's quest log (Facts.QuestLog):
--   * named exactly by a quest you are on (its special item, or an item
--     objective whose name is the item's): Needed, naming the quest and the
--     objective's progress
--   * its name only appears inside an objective's text: Unknown, "possibly
--     for" that quest
--   * named by no quest in the log: Unknown, saying exactly that. A quest not
--     yet taken, a later step of a chain, or a quest already turned in are
--     out of the client's reach, so this is never "not needed". Items of the
--     quest item class that the bag does not mark as quest items (tokens,
--     keys) say so too, since they often have other uses.
--   * a quest-class item the bag doesn't flag that Legacy.System names (a
--     Runecarving memory): only informs; the legacy check answers for it
-- An unreadable quest log is Unknown.
-- The "no quest names it" Unknown also says which quests the data says
-- reward the item and where each stands ('a reward of "The Old Guard"
-- (done)': Titan Emitter, Lady Darkglen's Device), read with the frame's
-- quest budget, and for an unflagged quest-type item with a Use effect what
-- using it gives and where it works (Purposes.UseEffect.Describe: Thunderlord
-- Grapple works only in Frostfire Ridge). Neither changes the verdict: a
-- quest not taken yet or a later step may still name it (rule 10).
-- When the data names the item for quests (an objective or a quest's item)
-- and every one is done, with none coming back, that Unknown is settled: a
-- quest may still return for the item, but nothing here is left to check
-- (Probably done, Task #384: Aelyse's Gleaming Falchion).
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local IsPositiveID = Recollect.Utilities.IsPositiveID

local MAX_GIVERS = 2   -- rewarding quests named in the reason

local function QuestText(match)
  local text = ("\"%s\""):format(match.title or ("quest " .. tostring(match.questID)))
  if match.progress then text = text .. " (" .. match.progress .. ")" end
  return text
end

local function Titles(list)
  local names = {}
  for _, match in ipairs(list) do names[#names + 1] = QuestText(match) end
  return table.concat(names, ", ")
end

-- '; a reward of "The Old Guard" (done) and 1 more quest', from the data's
-- reward and choice codes, each quest once, or "" when it names none
local function RewardWords(itemID, owner)
  local Relations, QuestInfo = Recollect.Facts.Relations, Recollect.Facts.QuestInfo
  local budget = QuestInfo.FrameBudget()
  local seen, names, total = {}, {}, 0
  for _, relation in ipairs(Relations.For(itemID)) do
    if (relation.kind == "reward" or relation.kind == "choice") and IsPositiveID(relation.id) and not seen[relation.id] then
      seen[relation.id] = true
      total = total + 1
      if #names < MAX_GIVERS then
        local applies = Relations.Applies(relation, owner)
        local quest = applies == true and QuestInfo.Get(relation.id, budget) or nil
        local title = quest and quest.title or Recollect.Facts.QuestLog.Title(relation.id)
        local state
        if applies == "unavailable" then
          state = "no longer in the game"
        elseif applies == "other" then
          state = "for another " .. R.KindWords((R.Restrictions({ relation }, owner)))
        elseif applies ~= true then
          state = "whether it's for this character isn't recorded yet"
        elseif not quest then
          state = "still being checked"
        elseif quest.onQuest == true then
          state = "you're on it"
        else
          local done = QuestInfo.Done(quest)
          state = done == true and "done" or done == false and "not done" or "can't be read"
        end
        names[#names + 1] = ("\"%s\" (%s)"):format(title or ("quest " .. relation.id), state)
      end
    end
  end
  if total == 0 then return "" end
  local more = total - #names
  return "; a reward of " .. table.concat(names, " and ")
    .. (more > 0 and (" and %d more %s"):format(more, more == 1 and "quest" or "quests") or "")
end

-- Whether every quest the data names the item for (objective or questItem
-- codes serving this character) is done, none repeatable or recurring, none
-- still loading or in the log; false when it names none
local function EveryQuestDone(itemID, owner)
  local Relations, QuestInfo = Recollect.Facts.Relations, Recollect.Facts.QuestInfo
  local serves, budget, seen, found = Relations.QuestApplies(itemID, owner), QuestInfo.FrameBudget(), {}, false
  for _, kind in ipairs({ "objective", "questItem" }) do
    for _, relation in ipairs(Relations.Of(itemID, kind)) do
      if not seen[relation.id] and serves[relation.id] == true then
        seen[relation.id] = true
        local quest = QuestInfo.Get(relation.id, budget)
        if not quest or quest.onQuest == true or quest.repeatable == true or QuestInfo.Done(quest) ~= true then return false end
        local Recurs = Recollect.Purposes.QuestRecurs
        if Recurs and Recurs(relation.id) then return false end
        found = true
      end
    end
  end
  return found
end

R.Register({
  key = "questItem",
  label = "Quest item",
  order = 60,
  Evaluate = function(ctx)
    local quest = ctx.stack.quest
    if quest and IsPositiveID(quest.questID) then return nil end
    local flagged = quest and quest.isQuestItem
    if not flagged and ctx.facts.classID ~= R.CLASS_QUEST then return nil end
    -- A quest-class item of an older system the bag doesn't flag (a
    -- Runecarving memory): the legacy check says what it is for; this only
    -- informs, so Verdicts.OtherUses doesn't count it as an unchecked quest item
    if not flagged and ctx.facts.hasSpell ~= false then
      local Legacy = Recollect.Purposes.Legacy
      local okSystem, system = pcall(Legacy and Legacy.System or function() return nil end, ctx.stack.itemID, ctx.facts, ctx.Tooltip())
      if okSystem and system then
        return R.Info(("Quest-type item; it's %s %s, not a quest's"):format(R.Article(system.name):lower(), system.name))
      end
    end

    local QuestLog = Recollect.Facts.QuestLog
    local ok, exact, possible, complete = pcall(QuestLog.Matches, ctx.stack.itemID, ctx.facts.name)
    if not ok then return R.Unknown("Quest item; your quest log couldn't be read") end
    if #exact > 0 then
      return R.Result(V.NEEDED, "Needed for " .. Titles(exact) .. ", in your quest log")
    end
    if #possible > 0 then
      return R.Unknown("Quest item; possibly for " .. Titles(possible) .. " (its name appears in an objective)")
    end
    if not complete then return R.Unknown("Quest item; your quest log couldn't be fully read") end
    local owner = ctx.owner or { faction = ctx.playerFaction }
    local rewards = RewardWords(ctx.stack.itemID, owner)
    local result
    if flagged then
      result = R.Unknown("Quest item" .. rewards .. "; no quest in your quest log names it")
    else
      -- what using it gives and where it works, as the game's own words say
      local UseEffect = Recollect.Purposes.UseEffect
      local okD, described = false, nil
      if UseEffect and ctx.facts.hasSpell == true then okD, described = pcall(UseEffect.Describe, ctx) end
      described = okD and described or nil
      result = R.Unknown("Quest-type item" .. (described and described.text or "") .. rewards
        .. "; no quest in your quest log names it (it may be a token or a key)")
      if described and described.headline then result.headline = described.headline end
    end
    if EveryQuestDone(ctx.stack.itemID, owner) then result.settled = true end
    return result
  end,
})
