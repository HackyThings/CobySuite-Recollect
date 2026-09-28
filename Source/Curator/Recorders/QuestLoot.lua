-------------------------------------------------------------------------------
-- Curator recorder: quest rewards that arrive with no quest window
-- (QUEST_LOOT_RECEIVED: world quests, bonus objectives and invasions, which
-- the game's own toasts show from this event)
--
-- QUEST_LOOT_RECEIVED (questID, itemLink, quantity) gives the quest and one
-- reward item; only the quest ID, the item ID parsed from the link and the
-- count are kept. A quest's items are gathered for COMMIT_DELAY seconds
-- from the first, so one turn-in is one visit, then compared in a later
-- frame through the quest window's own comparison (Compare.QuestRewards),
-- so the facts are the quest recorder's:
--   q:<quest>:w:<item>   a reward not shipped (value: how many)
-- and the stamp "q:<quest>" (the matched item IDs, total 0). An item the
-- data ships as one of the quest's choices counts as that choice (the one
-- picked arrives as loot): it goes in the stamp, never a "w versus k"
-- conflict (q:<quest>:i:<item>). Rewards are class-filtered and can be
-- random, so no not seen.
--
-- A quest whose reward window (QUEST_COMPLETE) was read in the last
-- WINDOW_SECONDS is left to the quest recorder, which already compared its
-- rewards: whether QUEST_LOOT_RECEIVED also fires for such a turn-in is
-- unmeasured. Recorded in combat too (world quests end in combat; read in
-- the event). Only while curator mode may record, and never while a test
-- run scripts the client. Client reads go through QuestLoot.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Bags = Curator.Recorders.Bags

local QuestLoot = {}
Curator.Recorders.QuestLoot = QuestLoot

QuestLoot.COMMIT_DELAY = 2      -- seconds a turn-in's items are gathered
QuestLoot.WINDOW_SECONDS = 60   -- a quest window's turn-in this recent is the quest recorder's

QuestLoot.seams = {
  QuestID = function() return GetQuestID() end,
  Clock = function() return GetTime() end,
  After = function(delay, fn) C_Timer.After(delay, fn) end,
}

local visits = {}     -- [questID] = { epoch, rewards = { [itemID] = n } }, gathering
local windowed = {}   -- [questID] = when its reward window was read

local function Now()
  local ok, now = pcall(QuestLoot.seams.Clock)
  return ok and type(now) == "number" and now or nil
end

-- Compare(questID, rewards, ctx): the items as the quest window's
-- comparison takes them, each under the kind the data ships it as for this
-- quest (a choice, else a plain reward); returns how many matched
function QuestLoot.Compare(questID, rewards, ctx)
  local visit = { questID = questID, rewards = {}, choices = {} }
  for itemID, count in pairs(rewards) do
    if Curator.Compare.Shipped(itemID, "choice")[questID] then
      visit.choices[itemID] = count
    else
      visit.rewards[itemID] = count
    end
  end
  return Curator.Compare.QuestRewards(visit, ctx)
end

function QuestLoot.Commit(questID, visit)
  if visits[questID] ~= visit then return end
  visits[questID] = nil
  if not Curator.Main.StillCurrent(visit.epoch) then return end
  Curator.Main.Defer(function() QuestLoot.Compare(questID, visit.rewards, Curator.Context.Current()) end)
end

-- QUEST_LOOT_RECEIVED (questID, itemLink, quantity): true when kept
function QuestLoot.OnLoot(questID, itemLink, quantity)
  if not Curator.Main.MayRecord() or not Bags.PositiveID(questID) then return false end
  if Host.IsSecret(itemLink) or type(itemLink) ~= "string" or Host.IsSecret(quantity) then return false end
  local itemID = tonumber(itemLink:match("item:(%d+)"))
  if not Bags.PositiveID(itemID) then return false end
  local now, at = Now(), windowed[questID]
  if at and (not now or now - at <= QuestLoot.WINDOW_SECONDS) then return false end
  local visit = visits[questID]
  if not visit then
    visit = { epoch = Curator.Main.Epoch(), rewards = {} }
    visits[questID] = visit
    QuestLoot.seams.After(QuestLoot.COMMIT_DELAY, function() QuestLoot.Commit(questID, visit) end)
  end
  visit.rewards[itemID] = type(quantity) == "number" and quantity > 0 and quantity or 1
  return true
end

-- QUEST_COMPLETE: the quest recorder reads this turn-in's rewards
function QuestLoot.OnWindow()
  local ok, questID = pcall(QuestLoot.seams.QuestID)
  local now = Now()
  if ok and Bags.PositiveID(questID) and now then windowed[questID] = now end
end

function QuestLoot.Reset()
  wipe(visits)
  wipe(windowed)
end

local handlers = { QUEST_LOOT_RECEIVED = QuestLoot.OnLoot, QUEST_COMPLETE = QuestLoot.OnWindow }

-- The event frame's dispatch (a test run scripting the client reads nothing)
function QuestLoot.OnEvent(event, ...)
  if Curator.Main.IsScripted() or not handlers[event] then return end
  local ok, err = pcall(handlers[event], ...)
  if not ok then Host.Log("Quest loot recorder %s failed: %s", event, tostring(err)) end
end

local frame = CreateFrame("Frame")
for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...) QuestLoot.OnEvent(event, ...) end)
