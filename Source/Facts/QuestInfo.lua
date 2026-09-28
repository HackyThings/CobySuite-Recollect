-------------------------------------------------------------------------------
-- Facts.QuestInfo: what the game says about one quest, in the log or not
--
-- Get(questID) returns the quest's facts once its data is loaded, else nil
-- and "loading" (asking for it once in RETRY_AFTER). The data is loaded
-- when HaveQuestData says so; otherwise C_QuestLog.RequestLoadQuestByID
-- asks, and QUEST_DATA_LOAD_RESULT answers. That event is synchronous: for
-- a quest cached meanwhile it fires during the request call, so the quest is
-- marked as asked before the call (the Lab's dump lost every such answer
-- the other way round, 2026-09-23). An answer fires InventoryChanged so open
-- windows and the audit panel read again.
--
-- The facts: title, completed (this character), completedOnAccount,
-- isAccount (an account quest: Done reads the account's completion), onQuest,
-- repeatable, rewards and choices ({ itemID, count }) through the quest-log
-- reward getters that take a quest ID (Blizzard's Journeys UI reads them for
-- a quest never in the log), and reward currencies. Every read goes through
-- seams and Utilities.Try; a failed read is nil, never a guess.
-------------------------------------------------------------------------------
local QuestInfo = {}
Recollect.Facts.QuestInfo = QuestInfo

local Try = Recollect.Utilities.Try
local IsPositiveID = Recollect.Utilities.IsPositiveID

local RETRY_AFTER = 30

local seams = {
  HaveData = function(questID) return HaveQuestData(questID) end,
  Request = function(questID) return C_QuestLog.RequestLoadQuestByID(questID) end,
  Title = function(questID) return C_QuestLog.GetTitleForQuestID(questID) end,
  Completed = function(questID) return C_QuestLog.IsQuestFlaggedCompleted(questID) end,
  CompletedOnAccount = function(questID) return C_QuestLog.IsQuestFlaggedCompletedOnAccount(questID) end,
  IsAccount = function(questID) return C_QuestLog.IsAccountQuest(questID) end,
  OnQuest = function(questID) return C_QuestLog.IsOnQuest(questID) end,
  Repeatable = function(questID) return C_QuestLog.IsRepeatableQuest(questID) end,
  NumRewards = function(questID) return GetNumQuestLogRewards(questID) end,
  RewardInfo = function(index, questID) return GetQuestLogRewardInfo(index, questID) end,
  NumChoices = function(questID) return GetNumQuestLogChoices(questID, true) end,
  ChoiceInfo = function(index, questID) return GetQuestLogChoiceInfo(index, questID) end,
  RewardCurrencies = function(questID) return C_QuestInfoSystem.GetQuestRewardCurrencies(questID) end,
  Now = function() return GetTime() end,
}

local asked = {}   -- [questID] = time of the last request

local notify = CobySuite_Recollect.Utilities.Coalesce(0.3, function()
  Recollect.EventBus:Fire(Recollect.Events.InventoryChanged, "quests")
end)

local function Value(fn, ...)
  local ok, value = Try(fn, ...)
  if ok then return value end
  return nil
end

-- Asks the server for a quest's data, at most once in RETRY_AFTER; true
-- when a request went out
local function Request(questID)
  local at = asked[questID]
  if at and seams.Now() - at < RETRY_AFTER then return false end
  asked[questID] = seams.Now()   -- before the call: the answer can come during it
  pcall(seams.Request, questID)
  return true
end

local function Items(questID, count, info)
  local list = {}
  for index = 1, count do
    local ok, _, _, amount, _, _, itemID = Try(info, index, questID)
    if ok and IsPositiveID(itemID) then list[#list + 1] = { itemID = itemID, count = tonumber(amount) or 1 } end
  end
  return list
end

-- Get(questID, budget): the quest's facts, or nil and why ("loading", "no
-- quest ID", "waiting"). budget (optional, BA-13/14) is { left = n }: a
-- quest not loaded yet is asked for only while left is above 0, each request
-- taking one, so one list of quest lines asks the server for a batch at a
-- time; one past the batch is "waiting" (asked for by a later build, which
-- each answer's InventoryChanged brings)
function QuestInfo.Get(questID, budget)
  if not IsPositiveID(questID) then return nil, "no quest ID" end
  if Value(seams.HaveData, questID) ~= true then
    if budget and budget.left <= 0 then return nil, "waiting" end
    if Request(questID) and budget then budget.left = budget.left - 1 end
    return nil, "loading"
  end
  local numRewards, numChoices = Value(seams.NumRewards, questID), Value(seams.NumChoices, questID)
  local currencies = {}
  local okC, list = Try(seams.RewardCurrencies, questID)
  for _, c in ipairs(okC and type(list) == "table" and list or {}) do
    if type(c) == "table" and IsPositiveID(c.currencyID) then
      currencies[#currencies + 1] = { currencyID = c.currencyID, amount = c.totalRewardAmount }
    end
  end
  local title = Value(seams.Title, questID)
  return {
    questID = questID,
    title = type(title) == "string" and title ~= "" and title or nil,
    completed = Value(seams.Completed, questID),
    completedOnAccount = Value(seams.CompletedOnAccount, questID),
    isAccount = Value(seams.IsAccount, questID),
    onQuest = Value(seams.OnQuest, questID),
    repeatable = Value(seams.Repeatable, questID),
    rewards = Items(questID, type(numRewards) == "number" and numRewards or 0, seams.RewardInfo),
    choices = Items(questID, type(numChoices) == "number" and numChoices or 0, seams.ChoiceInfo),
    currencies = currencies,
  }
end

-- Done(quest): whether the quest is done, as far as this character is
-- concerned: the account's completion for an account quest (done once for
-- the whole warband), this character's otherwise; nil when unreadable
function QuestInfo.Done(quest)
  if quest.isAccount == true then return quest.completedOnAccount end
  if quest.isAccount == false then return quest.completed end
  -- whether it is an account quest couldn't be read (PI-09): an answer only
  -- when this character's completion and the account's agree
  if type(quest.completed) == "boolean" and quest.completed == quest.completedOnAccount then return quest.completed end
  return nil
end

-- The requests one frame may send, shared by every check and panel line
-- that reads quests in that frame: { left = n }
local FRAME_REQUESTS = 24
local frameBudget = { at = nil, left = FRAME_REQUESTS }
function QuestInfo.FrameBudget()
  local now = seams.Now()
  if frameBudget.at ~= now then frameBudget.at, frameBudget.left = now, FRAME_REQUESTS end
  return frameBudget
end

-- QUEST_DATA_LOAD_RESULT: an answer to a quest asked for; a loaded one may be read now
local function OnLoaded(questID, success)
  if questID and not Recollect.Utilities.IsSecret(questID) and asked[questID] then
    if success then asked[questID] = nil end
    notify:Call()
  end
end

local frame = CreateFrame("Frame")
pcall(frame.RegisterEvent, frame, "QUEST_DATA_LOAD_RESULT")
frame:SetScript("OnEvent", function(_, _, questID, success) OnLoaded(questID, success) end)

QuestInfo._test = {
  seams = seams,
  Reset = function()
    wipe(asked)
    frameBudget.at, frameBudget.left = nil, FRAME_REQUESTS
  end,
  OnEvent = OnLoaded,
}
