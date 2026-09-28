-------------------------------------------------------------------------------
-- Purpose: an item that starts a quest (the slot's quest info names it)
--
--   * Unknown while quest data is settling, while the quest is in the log,
--     and for repeatable quests: a daily or weekly reads as completed for
--     the day or week, which says nothing about the next one.
--   * Completed is Unknown too, never done. A yearly holiday quest looks
--     exactly like a one-time quest from outside the quest log (the Lab,
--     2026-09-23: Brewfest's Direbrew's Dire Brew, quest 12492, reads
--     classification Normal and not repeatable), and its starter works again
--     next year. Until the quest's frequency is known, a completed quest
--     proves nothing about the item. Where the shipped data gives it
--     (Facts.Relations.Frequency: yearly, weekly, daily, monthly, a world
--     quest, repeatable), a completed quest comes back: Useful.
--   * Use now when the quest is not done, the client says the item is
--     usable, and its tooltip shows no unmet requirement; otherwise Unknown.
--   * A quest the shipped data marks as no longer in the game on any code
--     naming it (Relations.QuestApplies, rule 32) only informs: the
--     "removed" check says what is gone. One for another faction, class or
--     race is Unknown, never Use now; one whose condition this character's
--     record can't answer is Unknown too. Being on the quest outranks the
--     data: the quest log is read first. Every completed answer with no
--     frequency in the data carries settled (Verdicts.Combine).
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try
local IsPositiveID = Recollect.Utilities.IsPositiveID

local function ReadBoolean(fn, questID)
  local ok, value = Try(fn, questID)
  if not ok or type(value) ~= "boolean" then return nil end
  return value
end

local function Completed(client, questID, isAccount)
  if isAccount then return ReadBoolean(client.IsQuestFlaggedCompletedOnAccount, questID) end
  return ReadBoolean(client.IsQuestFlaggedCompleted, questID)
end

-- The codes that name a quest (Relations.QuestApplies reads the same kinds)
local QUEST_KINDS = { starts = true, objective = true, questItem = true, reward = true, choice = true }

-- "\"Title\"" or "a quest" while the title is loading
local function QuestName(questID)
  local title = Recollect.Facts.QuestLog.Title(questID)
  return title and ("\"" .. title .. "\"") or "a quest"
end

R.Register({
  key = "questStarter",
  label = "Starts a quest",
  order = 50,
  Evaluate = function(ctx)
    local client = Recollect.Purposes.client
    local quest = ctx.stack.quest
    local questID = quest and quest.questID
    if not IsPositiveID(questID) then return nil end
    if not Recollect.Facts.Ready.Quests() then return R.Unknown("Starts a quest; quest data is still loading", nil, "loading") end
    local name = QuestName(questID)

    local onQuest = ReadBoolean(client.IsOnQuest, questID)
    if onQuest == nil then return R.Unknown("Starts a quest; couldn't read your quest log") end
    if onQuest then return R.Unknown("Starts " .. name .. ", which is in your quest log") end

    -- The data's conditions on this quest (rule 32): gone, or not this
    -- character's, never decides here
    local owner = ctx.owner or { faction = ctx.playerFaction }
    local okApplies, applies = pcall(function()
      return Recollect.Facts.Relations.QuestApplies(ctx.stack.itemID, owner)[questID]
    end)
    if okApplies and applies == "unavailable" then
      return R.Info("Starts " .. name .. ", which is no longer in the game")
    end
    if okApplies and applies == "other" then
      local named = {}
      for _, relation in ipairs(Recollect.Facts.Relations.For(ctx.stack.itemID)) do
        if QUEST_KINDS[relation.kind] and relation.id == questID then named[#named + 1] = relation end
      end
      local mismatch = R.Restrictions(named, owner)
      return R.Unknown(("Starts %s, a quest for another %s"):format(name, R.KindWords(mismatch)))
    end
    if okApplies and applies == "unknown" then
      return R.Unknown("Starts " .. name .. "; whether it's for this character isn't recorded yet", nil, "character")
    end

    local repeatable = ReadBoolean(client.IsRepeatableQuest, questID)
    local okClass, classification = Try(client.GetQuestClassification, questID)
    if repeatable == nil or not okClass then return R.Unknown("Starts a quest; couldn't read the quest") end
    if repeatable or classification == R.QUEST_RECURRING then return R.Unknown("Starts " .. name .. ", a repeatable quest") end

    local isAccount = ReadBoolean(client.IsAccountQuest, questID)
    if isAccount == nil then return R.Unknown("Starts a quest; couldn't read the quest") end
    local done = Completed(client, questID, isAccount)
    if done == nil then return R.Unknown("Starts a quest; couldn't read whether it is done") end
    if done then
      -- The data's frequency (AllTheThings, G-03) says whether it comes back;
      -- with none, a yearly quest reads like a one-time one (rule 7)
      local recurs = Recollect.Purposes.QuestRecurs and Recollect.Purposes.QuestRecurs(questID)
      if recurs then
        return R.Result(V.USEFUL, "Starts " .. name .. ", " .. recurs .. " that comes back; you've done it this time")
      end
      local result = R.Unknown("Starts " .. name .. (isAccount and ", completed on your account" or ", already completed")
        .. "; a holiday or yearly quest looks the same, so it may be needed again")
      result.settled = true
      return result
    end

    local okUse, usable = Try(client.CanUseItem, ctx.stack.itemID)
    if not okUse or usable ~= true then return R.Unknown("Starts " .. name .. ", which you can't take yet") end
    local tip = ctx.Tooltip()
    if not tip then return R.Unknown("Starts " .. name .. "; its tooltip can't be read") end
    if tip.redLines > 0 then return R.Unknown("Starts " .. name .. ", which you can't take yet (see its tooltip)") end
    return R.Result(V.USE, "Starts " .. name .. "; you haven't done it")
  end,
})
