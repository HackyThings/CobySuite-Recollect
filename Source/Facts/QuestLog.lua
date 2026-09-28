-------------------------------------------------------------------------------
-- Facts.QuestLog: which quests in the player's quest log name an item
--
-- No client call links a quest item to its quest, so the link is read off
-- the quests the player is on:
--   * a quest's special item (the usable item on its tracker line), by item
--     ID: exact
--   * a quest's item objectives, by the item's name: the objective text with
--     its count stripped ("Pressed Sanguithorn: 0/5" or "0/5 Pressed
--     Sanguithorn") equal to the item's name is exact; the name merely
--     appearing somewhere in the text is only "possibly"
-- Anything else (a quest not yet taken, one already turned in, one
-- abandoned) is out of reach: the checks built on this say what they
-- checked ("no quest in your log names it"), never that nothing needs it.
--
-- The index is rebuilt on the next read after the log changes. Title(questID)
-- names any quest, asking the server for it once when the client has not
-- loaded it; the answer fires InventoryChanged.
-------------------------------------------------------------------------------
local QuestLog = {}
Recollect.Facts.QuestLog = QuestLog

local Try = Recollect.Utilities.Try
local IsPositiveID = Recollect.Utilities.IsPositiveID
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber

local seams = {
  NumEntries = function() return C_QuestLog.GetNumQuestLogEntries() end,
  GetInfo = function(index) return C_QuestLog.GetInfo(index) end,
  GetObjectives = function(questID) return C_QuestLog.GetQuestObjectives(questID) end,
  GetSpecialItem = function(index) return GetQuestLogSpecialItemInfo(index) end,
  GetTitle = function(questID) return C_QuestLog.GetTitleForQuestID(questID) end,
  RequestLoad = function(questID) return C_QuestLog.RequestLoadQuestByID(questID) end,
}

local index = nil          -- the built index, nil when the log changed
local requested = {}       -- [questID] = true once a title load was asked for

function QuestLog.Invalidate()
  index = nil
end

-- The item name an objective text names, with the count stripped
function QuestLog.ObjectiveItemName(text)
  if type(text) ~= "string" then return nil end
  local name = text:match("^%d+/%d+%s+(.+)$") or text:match("^(.-):%s*%d+/%d+$") or text
  name = name:match("^%s*(.-)%s*$")
  return name ~= "" and name or nil
end

local function ItemIDFromLink(link)
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function AddSpecialItem(built, quest, logIndex)
  local ok, link = Try(seams.GetSpecialItem, logIndex)
  if not ok then
    built.complete = false
    return
  end
  local itemID = ItemIDFromLink(link)
  if itemID then
    built.byItem[itemID] = built.byItem[itemID] or {}
    table.insert(built.byItem[itemID], { questID = quest.questID, title = quest.title, how = "special" })
  end
end

local function AddObjectives(built, quest)
  local ok, objectives = Try(seams.GetObjectives, quest.questID)
  if not ok or type(objectives) ~= "table" then
    built.complete = false
    return
  end
  for _, objective in ipairs(objectives) do
    if type(objective) == "table" and objective.type == "item" and type(objective.text) == "string" then
      built.itemObjectives[#built.itemObjectives + 1] = {
        questID = quest.questID, title = quest.title, text = objective.text,
        name = QuestLog.ObjectiveItemName(objective.text),
        fulfilled = objective.numFulfilled, required = objective.numRequired, finished = objective.finished,
      }
    end
  end
end

-- Build(): { quests = { { questID, title } }, byItem = { [itemID] = { ... } },
-- itemObjectives = { ... }, complete }. complete is false when any read
-- failed, so a check never says "no quest names it" from half a log.
function QuestLog.Build()
  local built = { quests = {}, byItem = {}, itemObjectives = {}, complete = true }
  local ok, count = Try(seams.NumEntries)
  if not ok or not IsFiniteNumber(count) then
    built.complete = false
    return built
  end
  for logIndex = 1, count do
    local okInfo, info = Try(seams.GetInfo, logIndex)
    if not okInfo then
      built.complete = false
    elseif type(info) == "table" and not info.isHeader and IsPositiveID(info.questID) then
      local quest = { questID = info.questID, title = info.title or ("quest " .. info.questID) }
      built.quests[#built.quests + 1] = quest
      AddSpecialItem(built, quest, logIndex)
      AddObjectives(built, quest)
    end
  end
  return built
end

function QuestLog.Get()
  if not index then index = QuestLog.Build() end
  return index
end

local function Progress(objective)
  if IsFiniteNumber(objective.fulfilled) and IsFiniteNumber(objective.required) then
    return ("%d/%d"):format(objective.fulfilled, objective.required)
  end
  return nil
end

-- Matches(itemID, itemName): exact = { { questID, title, how, progress } },
-- possible = { ... } (the name only appears inside an objective's text),
-- and whether the whole log was read
function QuestLog.Matches(itemID, itemName)
  local built = QuestLog.Get()
  local exact, possible = {}, {}
  for _, match in ipairs(built.byItem[itemID] or {}) do exact[#exact + 1] = match end
  local lower = type(itemName) == "string" and itemName:lower() or nil
  if lower and lower ~= "" then
    for _, objective in ipairs(built.itemObjectives) do
      local match = { questID = objective.questID, title = objective.title, how = "objective", progress = Progress(objective) }
      if objective.name and objective.name:lower() == lower then
        exact[#exact + 1] = match
      elseif objective.text:lower():find(lower, 1, true) then
        possible[#possible + 1] = match
      end
    end
  end
  return exact, possible, built.complete
end

-- Title(questID): the quest's name, or nil while it is being loaded
function QuestLog.Title(questID)
  if not IsPositiveID(questID) then return nil end
  local ok, title = Try(seams.GetTitle, questID)
  if ok and type(title) == "string" and title ~= "" then return title end
  if not requested[questID] then
    requested[questID] = true
    Try(seams.RequestLoad, questID)
  end
  return nil
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local notify = CobySuite_Recollect.Utilities.Coalesce(0.5, function()
  Recollect.EventBus:Fire(Recollect.Events.InventoryChanged, "quests")
end)

local frame = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_DATA_LOAD_RESULT" }) do
  pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event)
  if event ~= "QUEST_DATA_LOAD_RESULT" then QuestLog.Invalidate() end
  notify:Call()
end)

QuestLog._test = {
  seams = seams,
  Reset = function()
    index = nil
    wipe(requested)
  end,
}
