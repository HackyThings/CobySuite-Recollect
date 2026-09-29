-------------------------------------------------------------------------------
-- Facts.Endeavors: the neighborhood endeavor running now and the items its
-- tasks name, read live from C_NeighborhoodInitiative
--
-- Get() returns nil and why ("no active endeavor", "not loaded", "can't be
-- read"), or { ready = true, id, title, description, progress, required,
-- contribution, cycle, unreadTasks, tasks = { { id, name, description, done,
-- completed, inProgress, amount, timesCompleted, taskType, repeatable,
-- rewardQuestID, supersedes, requirements = { { text, done } }, criteria =
-- { { id, required } }, items = { [itemID] = true } or nil } } } (plus
-- lower-case copies of the texts, read once for matching: plainName,
-- plainDescription, and each requirement's plain and bare, its count taken off).
--
-- Read as Blizzard's Endeavors tab reads it (Blizzard_HousingDashboard
-- Initiatives.lua): GetNeighborhoodInitiativeInfo() answers nil or
-- isLoaded false until RequestNeighborhoodInitiativeInfo() has brought it
-- (Blizzard asks on the tab's OnShow, and after login only when a task is
-- tracked), so this module asks at the first PLAYER_ENTERING_WORLD and again
-- at most every REQUEST_SECONDS while it still isn't loaded. initiativeID 0
-- is "no endeavor set"; the tab shows tasks only while
-- IsViewingActiveNeighborhood() is true (a neighborhood being browsed is not
-- the one a player contributes to), so any other answer is "not loaded". The
-- tab is disabled when IsInitiativeEnabled, PlayerMeetsRequiredLevel or
-- PlayerHasInitiativeAccess is false: "no active endeavor" for this
-- character. A task is done when completed and not RepeatableInfinite (the
-- tab's own checkmark rule: an endlessly repeatable task stays open); done
-- is nil when its state can't be read. A task whose ID, name or requirements
-- can't be read is left out and counted in unreadTasks.
--
-- Which items a task names. Neither of the task's lists carries an item ID:
-- requirementsList is { completed, requirementText } and criteriaList is
-- { criteriaID, requiredValue } (PerksVendorConstantsDocumentation.lua), and
-- no public call resolves a criteria ID to its item. So:
--   1. an item link inside the task's texts (|Hitem:ID) names the item on any
--      client language (task.items);
--   2. on English clients only (Registry.EnglishClient), the item's name
--      (Facts.Item.Name, loaded on demand): a requirement text equal to the
--      name once its count is stripped ("0/10 Home-Grown Wax", "Home-Grown
--      Wax: 0 / 10"), or, for a name of two words or more, the name as a
--      whole phrase in the task's name, description or a requirement ("Donate
--      Home-Grown Wax to the Community Chest"). A one-word name is matched
--      only by a whole requirement: "Wax" must not be read out of
--      "Home-Grown Wax".
-- UsesOf(itemID) returns { { title, taskName, done, progressText, taskID,
-- how } } or nil and why: "no active endeavor", "not loaded" (unloaded, or
-- an answer that can't be read: the third return then says "can't be
-- read"), or "not named" (the third return says "name loading" while the
-- item's name is still coming, "not English" when only a link could have
-- named it, "tasks unread" when some task could not be read). done is true,
-- false, or nil when that task's state can't be read. progressText is the
-- game's own requirement line when a requirement named the item ("3/10
-- Home-Grown Wax"), else the task's state.
--
-- Kept for MEMO_SECONDS or until an endeavor event or InventoryChanged, the
-- Achievements pattern (a panel redraws five times a second). A secret value
-- or table anywhere makes that part "can't be read", never a guess.
-------------------------------------------------------------------------------
local Endeavors = {}
Recollect.Facts.Endeavors = Endeavors

local Try = Recollect.Utilities.Try
local IsPositiveID = Recollect.Utilities.IsPositiveID
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber
local EscapePattern = CobySuite_Recollect.Utilities.EscapePattern

local MEMO_SECONDS = 5
local REQUEST_SECONDS = 30
-- Enum.NeighborhoodInitiativeTaskType.RepeatableInfinite (2 in 12.1)
local REPEATABLE_INFINITE = Enum and Enum.NeighborhoodInitiativeTaskType
  and Enum.NeighborhoodInitiativeTaskType.RepeatableInfinite or 2
local REPEATABLE_FINITE = Enum and Enum.NeighborhoodInitiativeTaskType
  and Enum.NeighborhoodInitiativeTaskType.RepeatableFinite or 1

local seams = {
  Enabled = function() return C_NeighborhoodInitiative.IsInitiativeEnabled() end,
  MeetsLevel = function() return C_NeighborhoodInitiative.PlayerMeetsRequiredLevel() end,
  Access = function() return C_NeighborhoodInitiative.PlayerHasInitiativeAccess() end,
  ViewingActive = function() return C_NeighborhoodInitiative.IsViewingActiveNeighborhood() end,
  Info = function() return C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo() end,
  Request = function() C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo() end,
  IsSecretTable = function(t) return issecrettable ~= nil and issecrettable(t) and true or false end,
  InCombat = function() return InCombatLockdown() end,
  Now = function() return GetTime() end,
}

-------------------------------------------------------------------------------
-- Reading one answer
-------------------------------------------------------------------------------
-- A field of a table the client gave, or nil and false when it can't be read
-- (a secret table, a secret value, or an error reading it)
local function Field(t, key)
  if type(t) ~= "table" then return nil, false end
  local okSecret, secret = pcall(seams.IsSecretTable, t)
  if not okSecret or secret then return nil, false end
  local ok, value = pcall(function() return t[key] end)
  -- looked up per call, as Utilities.Try does, so suites can script secret values
  if not ok or Recollect.Utilities.IsSecret(value) then return nil, false end
  return value, true
end

local function Text(t, key)
  local value, ok = Field(t, key)
  if not ok then return nil, false end
  if value == nil then return "", true end
  if type(value) ~= "string" then return nil, false end
  return value, true
end

local function Number(t, key)
  local value, ok = Field(t, key)
  if not ok or not IsFiniteNumber(value) then return nil, false end
  return value, true
end

-- A text as shown, with its color codes, textures and link wrappers removed
-- and " / " closed up as Blizzard's tracker shows it ("3/10 Home-Grown Wax")
local function Display(text)
  text = CobySuite_Recollect.Utilities.StripColors(text)
  text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
  text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("%[(.-)%]", "%1"):gsub(" / ", "/")
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The same, lower case, for matching
local function Plain(text)
  return Display(text):lower()
end

-- A requirement's text with its count taken off: "0/10 x", "0 / 10 x",
-- "x: 0/10", "x (0/10)", "x 0/10", "10 x", "x x10"
local function WithoutCount(text)
  text = text:gsub("^%d+%s*/%s*%d+%s*", "")
  text = text:gsub("%s*:?%s*%(?%d+%s*/%s*%d+%)?$", "")
  text = text:gsub("^%d+%s*x?%s+", "")
  text = text:gsub("%s+x%s*%d+$", "")
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Item IDs named by links in a text (|Hitem:ID:...), into set
local function LinkedItems(text, set)
  for id in text:gmatch("|Hitem:(%d+)") do
    local itemID = tonumber(id)
    if IsPositiveID(itemID) then
      set = set or {}
      set[itemID] = true
    end
  end
  return set
end

-- A list the client gave (requirementsList, criteriaList, tasks), {} when it
-- is absent, or nil when it can't be read
local function Entries(t, key)
  local list, ok = Field(t, key)
  if not ok or (list ~= nil and type(list) ~= "table") then return nil end
  local okSecret, secret = pcall(seams.IsSecretTable, list or {})
  if not okSecret or secret then return nil end
  return list or {}
end

-- A task read into plain values, or nil when what names its items (its ID,
-- name and requirements) can't be read. A state that can't be read (completed
-- or its type) leaves done nil: the task still names its items, and a check
-- then says its state can't be read.
local function ReadTask(raw)
  local id = Number(raw, "ID")
  local name = Text(raw, "taskName")
  if not IsPositiveID(id) or not name then return nil end
  local completed = Field(raw, "completed")
  local taskType = Number(raw, "taskType")
  if type(completed) ~= "boolean" then completed = nil end
  local done = nil
  if completed ~= nil and taskType then done = completed and taskType ~= REPEATABLE_INFINITE end
  local description = Text(raw, "description") or ""
  local inProgress = Field(raw, "inProgress")
  local task = {
    id = id, name = name, description = description, completed = completed, taskType = taskType, done = done,
    repeatable = taskType == REPEATABLE_INFINITE or taskType == REPEATABLE_FINITE,
    inProgress = inProgress == true,
    amount = Number(raw, "progressContributionAmount"),
    timesCompleted = Number(raw, "timesCompleted"),
    rewardQuestID = Number(raw, "rewardQuestID"),
    supersedes = Number(raw, "supersedes"),
    requirements = {}, criteria = {},
  }
  local requirements = Entries(raw, "requirementsList")
  if not requirements then return nil end
  for _, entry in ipairs(requirements) do
    local text = Text(entry, "requirementText")
    if not text then return nil end
    local done = Field(entry, "completed")
    local plain = Plain(text)
    -- plain and bare are for matching, read once here rather than per item
    task.requirements[#task.requirements + 1] = { text = text, done = done == true, plain = plain, bare = WithoutCount(plain) }
  end
  local criteria = Entries(raw, "criteriaList") or {}
  for _, entry in ipairs(criteria) do
    local criteriaID = Number(entry, "criteriaID")
    if criteriaID then task.criteria[#task.criteria + 1] = { id = criteriaID, required = Number(entry, "requiredValue") } end
  end
  local items = LinkedItems(name, nil)
  items = LinkedItems(description, items)
  for _, requirement in ipairs(task.requirements) do items = LinkedItems(requirement.text, items) end
  task.items = items
  task.plainName, task.plainDescription = Plain(name), Plain(description)
  return task
end

-- A gate read: true, false, or nil when it can't be read
local function Flag(fn)
  local ok, value = Try(fn)
  if not ok or type(value) ~= "boolean" then return nil end
  return value
end

local function Read()
  local enabled, meets, access = Flag(seams.Enabled), Flag(seams.MeetsLevel), Flag(seams.Access)
  if enabled == false or meets == false or access == false then return nil, "no active endeavor" end
  if enabled == nil then return nil, "can't be read" end
  local ok, info = Try(seams.Info)
  if not ok then return nil, "can't be read" end
  if info == nil then return nil, "not loaded" end
  local loaded, okLoaded = Field(info, "isLoaded")
  if not okLoaded then return nil, "can't be read" end
  if loaded ~= true then return nil, "not loaded" end
  local id = Number(info, "initiativeID")
  if not id then return nil, "can't be read" end
  if id == 0 then return nil, "no active endeavor" end
  local viewing = Flag(seams.ViewingActive)
  if viewing == nil then return nil, "can't be read" end
  if not viewing then return nil, "not loaded" end
  local title = Text(info, "title")
  local progress, required = Number(info, "currentProgress"), Number(info, "progressRequired")
  local tasks = Entries(info, "tasks")
  if not title or not tasks then return nil, "can't be read" end
  local result = { ready = true, id = id, title = title, description = Text(info, "description") or "",
    progress = progress, required = required, contribution = Number(info, "playerTotalContribution"),
    cycle = Number(info, "currentCycleID"), tasks = {}, unreadTasks = 0 }
  for _, raw in ipairs(tasks) do
    local task = ReadTask(raw)
    if task then result.tasks[#result.tasks + 1] = task else result.unreadTasks = result.unreadTasks + 1 end
  end
  return result
end

-------------------------------------------------------------------------------
-- Asking the server, and keeping answers until data changes
-------------------------------------------------------------------------------
local requestedAt = nil

local function Request()
  local now = seams.Now()
  if requestedAt and now >= requestedAt and now - requestedAt < REQUEST_SECONDS then return false end
  local okCombat, combat = Try(seams.InCombat)
  if okCombat and combat then return false end
  requestedAt = now
  Try(seams.Request)
  return true
end

local generation = 0
local memo = nil        -- { at, generation, value, reason }
local usesMemo = {}     -- [itemID] = { list or false, reason, detail }

function Endeavors.Get()
  local now = seams.Now()
  if memo and memo.generation == generation and now >= memo.at and now - memo.at < MEMO_SECONDS then
    return memo.value or nil, memo.reason
  end
  local value, reason = Read()
  if not value and reason == "not loaded" then Request() end
  memo = { at = now, generation = generation, value = value or false, reason = reason }
  usesMemo = {}
  return value, reason
end

-------------------------------------------------------------------------------
-- Which tasks name an item
-------------------------------------------------------------------------------
-- A lower-case name as a pattern for a whole phrase: not inside a longer word
local function PhrasePattern(name)
  return "%f[%w]" .. EscapePattern(name) .. "%f[%W]"
end

-- Whether a lower-case text holds that phrase, and not as the tail of a
-- hyphenated or possessive word ("grown wax" in "home-grown wax")
local function HasPhrase(text, pattern)
  local init = 1
  while true do
    local start, stop = text:find(pattern, init)
    if not start then return false end
    local before = start > 1 and text:sub(start - 1, start - 1) or ""
    if before ~= "-" and before ~= "'" then return true end
    init = stop + 1
  end
end

-- How a task names the item: "link", "requirement" (with that requirement),
-- "text", or nil. name is the item's name, lower case; phrase its
-- PhrasePattern, or nil for a one-word name
local function Names(task, itemID, name, phrase)
  if task.items and task.items[itemID] then
    for _, requirement in ipairs(task.requirements) do
      if requirement.text:find("|Hitem:" .. itemID .. "[:|]") then return "link", requirement end
    end
    return "link", nil
  end
  if not name then return nil end
  for _, requirement in ipairs(task.requirements) do
    if requirement.bare == name then return "requirement", requirement end
  end
  if not phrase then return nil end
  for _, requirement in ipairs(task.requirements) do
    if HasPhrase(requirement.plain, phrase) then return "requirement", requirement end
  end
  if HasPhrase(task.plainName, phrase) or HasPhrase(task.plainDescription, phrase) then return "text", nil end
  return nil
end

local function TaskState(task)
  if task.done == nil then return "state can't be read" end
  if task.done then return "done" end
  if task.taskType == REPEATABLE_INFINITE and task.timesCompleted and task.timesCompleted > 0 then
    return ("done %d %s, repeatable"):format(task.timesCompleted, task.timesCompleted == 1 and "time" or "times")
  end
  if task.inProgress then return "in progress" end
  return "not started"
end

local function Uses(itemID)
  local endeavor, reason = Endeavors.Get()
  if not endeavor then
    if reason == "no active endeavor" then return nil, "no active endeavor" end
    return nil, "not loaded", reason
  end
  local english = Recollect.Purposes.Registry.EnglishClient()
  local name
  if english then
    local itemName = Recollect.Facts.Item.Name(itemID)
    if type(itemName) == "string" and itemName ~= "" then name = Plain(itemName) end
  end
  -- A one-word name is matched only as a whole requirement ("Wax" is not read out of "Home-Grown Wax")
  local phrase = name and name:find("[%s%-]") and PhrasePattern(name) or nil
  local list = {}
  for _, task in ipairs(endeavor.tasks) do
    local how, requirement = Names(task, itemID, name, phrase)
    if how then
      local progressText = requirement and Display(requirement.text) or ""
      if progressText == "" then progressText = TaskState(task) end
      list[#list + 1] = { title = endeavor.title, taskName = task.name, done = task.done, progressText = progressText,
        taskID = task.id, how = how }
    end
  end
  if #list > 0 then return list end
  if endeavor.unreadTasks > 0 then return nil, "not named", "tasks unread" end
  if not english then return nil, "not named", "not English" end
  if not name then return nil, "not named", "name loading" end
  return nil, "not named"
end

function Endeavors.UsesOf(itemID)
  if not IsPositiveID(itemID) then return nil, "not named" end
  Endeavors.Get()   -- a new answer clears the kept uses
  local kept = usesMemo[itemID]
  if kept then return kept[1] or nil, kept[2], kept[3] end
  local list, reason, detail = Uses(itemID)
  -- An item whose name is still loading is asked again next time
  if detail ~= "name loading" then usesMemo[itemID] = { list or false, reason, detail } end
  return list, reason, detail
end

-- "340 of 1000" for an endeavor's progress, or nil when it can't be read
function Endeavors.ProgressWords(endeavor)
  if not endeavor or not endeavor.progress or not endeavor.required or endeavor.required <= 0 then return nil end
  return ("%d of %d"):format(endeavor.progress, endeavor.required)
end

-------------------------------------------------------------------------------
-- Events: an endeavor that loads or changes redraws the verdicts, only when
-- what Get reads changed (a request brings an update event even when nothing
-- did, and InventoryChanged redraws every row)
-------------------------------------------------------------------------------
local function Signature()
  local endeavor, reason = Endeavors.Get()
  if not endeavor then return tostring(reason) end
  local parts = { endeavor.id, endeavor.progress or "?", endeavor.unreadTasks, #endeavor.tasks }
  for _, task in ipairs(endeavor.tasks) do
    parts[#parts + 1] = ("%d:%s:%s:%s"):format(task.id, tostring(task.completed), tostring(task.inProgress), tostring(task.timesCompleted))
    for _, requirement in ipairs(task.requirements) do parts[#parts + 1] = requirement.text end
  end
  return table.concat(parts, "|")
end

local lastSignature = nil

local notify = CobySuite_Recollect.Utilities.Coalesce(0.5, function()
  Recollect.EventBus:Fire(Recollect.Events.InventoryChanged, "endeavor")
end)
seams.Notify = function() notify:Call() end

local function OnEndeavorEvent()
  generation = generation + 1
  local signature = Signature()
  if signature ~= lastSignature then
    lastSignature = signature
    seams.Notify()
  end
end

local listener = {}
function listener:ReceiveEvent() generation = generation + 1 end
Recollect.EventBus:Register(listener, { Recollect.Events.InventoryChanged })

local ENDEAVOR_EVENTS = { "NEIGHBORHOOD_INITIATIVE_UPDATED", "INITIATIVE_TASK_COMPLETED", "INITIATIVE_COMPLETED" }
local frame = CreateFrame("Frame")
local enteredOnce = false
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
for _, event in ipairs(ENDEAVOR_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_ENTERING_WORLD" then
    if enteredOnce then return end
    enteredOnce = true
    if Flag(seams.Enabled) and Flag(seams.MeetsLevel) and Flag(seams.Access) then Request() end
    return
  end
  OnEndeavorEvent()
end)

Endeavors._test = {
  seams = seams,
  REQUEST_SECONDS = REQUEST_SECONDS,
  -- Forgets every kept answer and the last request, so a scripted seam is read at once
  Reset = function() memo, usesMemo, requestedAt, lastSignature = nil, {}, nil, nil end,
  -- Drops the kept answers only (the Lab's probe reads the game afresh)
  Forget = function() memo, usesMemo = nil, {} end,
  DataChanged = function() listener:ReceiveEvent() end,
  OnEndeavorEvent = OnEndeavorEvent,
  Display = Display, Plain = Plain, WithoutCount = WithoutCount,
}
