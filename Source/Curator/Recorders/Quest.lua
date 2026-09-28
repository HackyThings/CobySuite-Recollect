-------------------------------------------------------------------------------
-- Curator recorder: quests (curator spec, "v1 recorders": quest; research
-- note I section 3)
--
-- Every read happens inside the event that shows it (an offer from an item
-- or an area trigger closes itself during QUEST_DETAIL), and needs only IDs,
-- which the game gives before an item is cached; the comparison runs in a
-- later frame (recorder contract rule 1):
--   QUEST_DETAIL    the offer: rewards and choices, the item that started it
--                   (the event's questStartItemID), who gives it, and daily
--                   or weekly (QuestIsDaily / QuestIsWeekly, U20)
--   QUEST_PROGRESS  the turn-in's required items (hidden ones skipped)
--   QUEST_COMPLETE  the rewards again, and who takes the turn-in
-- The giver and the turn-in NPC are only ever the quest frame's own NPC
-- (the "questnpc" unit), never a nearby gossip NPC, and an offer an item
-- started names no giver at all; their positions are recorded too (with
-- unshipped NPCs added). Rewards are filtered by class (U14), so a quest is
-- never complete: CompareQuest records additions, conflicts and stamps,
-- never "not seen".
--
-- Only while curator mode may record, and never while a test run scripts
-- the client. Client reads go through Quest.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Bags = Curator.Recorders.Bags
local NpcPosition = Curator.Recorders.NpcPosition

local Quest = {}
Curator.Recorders.Quest = Quest

Quest.seams = {
  QuestID = function() return GetQuestID() end,
  NumRewards = function() return GetNumQuestRewards() end,
  NumChoices = function() return GetNumQuestChoices() end,
  NumRequired = function() return GetNumQuestItems() end,
  -- how many, and the item ID (GetQuestItemInfo's 3rd and 6th returns)
  ItemInfo = function(kind, index)
    local _, _, count, _, _, itemID = GetQuestItemInfo(kind, index)
    return count, itemID
  end,
  ChoiceType = function(index) return GetQuestItemInfoLootType("choice", index) end,
  RequiredHidden = function() return C_QuestOffer.GetHideRequiredItems() end,
  ItemHidden = function(index) return IsQuestItemHidden(index) end,
  IsDaily = function() return QuestIsDaily() end,
  IsWeekly = function() return QuestIsWeekly() end,
}

local QUEST_UNIT = "questnpc"

local function Seam(name, ...)
  local ok, a, b = pcall(Quest.seams[name], ...)
  if not ok or Host.IsSecret(a) or Host.IsSecret(b) then return nil end
  return a, b
end

local function Wanted(kind, index)
  if kind == "choice" then return (Seam("ChoiceType", index) or 0) == 0 end   -- items only, not currencies
  if kind == "required" then return (Seam("ItemHidden", index) or 0) == 0 end
  return true
end

-- The items of one list: { [itemID] = how many }
local function Items(kind, count)
  local out = {}
  for index = 1, count or 0 do
    if Wanted(kind, index) then
      local n, itemID = Seam("ItemInfo", kind, index)
      if Bags.PositiveID(itemID) then out[itemID] = type(n) == "number" and n or 1 end
    end
  end
  return out
end

local function QuestID()
  local questID = Seam("QuestID")
  return Bags.PositiveID(questID) and questID or nil
end

local function Rewards(questID)
  return { questID = questID, rewards = Items("reward", Seam("NumRewards")), choices = Items("choice", Seam("NumChoices")) }
end

-- QUEST_DETAIL (questStartItemID): true when the offer was captured
function Quest.OnDetail(startItemID)
  local questID = Curator.Main.MayRecord() and QuestID()
  if not questID then return false end
  local fromItem = Bags.PositiveID(startItemID)
  local visit = Rewards(questID)
  local giver = not fromItem and NpcPosition.CurrentNpc(QUEST_UNIT) or nil
  local place = not fromItem and NpcPosition.Capture(QUEST_UNIT) or nil
  local daily, weekly = Seam("IsDaily"), Seam("IsWeekly")
  Curator.Main.Defer(function()
    local ctx = Curator.Context.Current()
    Curator.Compare.QuestRewards(visit, ctx)
    if fromItem then Curator.Compare.QuestStarter(startItemID, questID, ctx) end
    if giver then Curator.Compare.QuestGiver(questID, giver, ctx) end
    if daily then Curator.Compare.QuestFrequency(questID, "d", ctx) end
    if weekly then Curator.Compare.QuestFrequency(questID, "w", ctx) end
  end)
  NpcPosition.Commit(place, true)
  return true
end

-- QUEST_PROGRESS
function Quest.OnProgress()
  local questID = Curator.Main.MayRecord() and QuestID()
  if not questID or Seam("RequiredHidden") then return false end
  local required = Items("required", Seam("NumRequired"))
  Curator.Main.Defer(function() Curator.Compare.QuestRequired(questID, required, Curator.Context.Current()) end)
  return true
end

-- QUEST_COMPLETE
function Quest.OnComplete()
  local questID = Curator.Main.MayRecord() and QuestID()
  if not questID then return false end
  local visit = Rewards(questID)
  local taker = NpcPosition.CurrentNpc(QUEST_UNIT)
  local place = NpcPosition.Capture(QUEST_UNIT)
  Curator.Main.Defer(function()
    local ctx = Curator.Context.Current()
    Curator.Compare.QuestRewards(visit, ctx)
    if taker then Curator.Compare.QuestTurnIn(questID, taker, ctx) end
  end)
  NpcPosition.Commit(place, true)
  return true
end

local handlers = { QUEST_DETAIL = Quest.OnDetail, QUEST_PROGRESS = Quest.OnProgress, QUEST_COMPLETE = Quest.OnComplete }

local frame = CreateFrame("Frame")
for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...)
  if Curator.Main.IsScripted() then return end
  local ok, err = pcall(handlers[event], ...)
  if not ok then Host.Log("Quest recorder %s failed: %s", event, tostring(err)) end
end)
