-------------------------------------------------------------------------------
-- Facts.Achievements: one achievement and one of its criteria, read on demand
--
-- Get(achievementID, criteriaID, itemID) returns { name, earned,
-- criterionDone, quantity, required } or nil when the achievement can't be
-- read (itemID: see criterion ID 0 below).
-- GetAchievementInfo(id) gives the name and whether it is earned (4th
-- return); the criterion is found by its ID (GetAchievementCriteriaInfo's
-- 10th return) among the achievement's own criteria, the order Blizzard's
-- objective tracker reads (Blizzard_AchievementObjectiveTracker.lua:130).
-- Nothing is indexed at login: Blizzard never walks every achievement, and
-- an item names its achievement through Facts.Relations.
-- The game answers criterion ID 0 for some achievements' criteria (the big
-- dump of 2026-09-24: 952 criteria of 378 achievements, among them every
-- part of "Traversing the Spheres", whose AllTheThings link names criterion
-- 52616): with itemID given, a criterion whose ID reads 0 and whose text is
-- that item's name (read live, so on any language) stands for it. Only when
-- no criterion matched by ID; a name not loaded yet matches nothing.
--
-- Parts(achievementID, criteriaIDs, itemID) reads the criteria once for many
-- IDs of one achievement (Black Claw of Sethe links to 72 parts of Advanced
-- Husbandry): { found, done, unreadable, wanted } where found counts the IDs
-- found (the text match standing in as above), done those found done,
-- unreadable is true when a criterion could not be read, and wanted is how
-- many distinct IDs were asked for; nil when the achievement can't be read.
-- PartsState(parts) says what they add up to: "open" when a part found is
-- not done (a fact, whatever else failed to read), "done" only when every
-- wanted part was found done and nothing failed to read, else nil (can't be
-- read: a failed read or a part not found is never done; review F14).
--
-- Progress(achievementID) says how far along an achievement is, for an
-- item it rewards: { name, earned, byMe, earnedBy, accountWide, done,
-- total, quantity, required }, or nil when it can't be read. As Blizzard's
-- achievement frame reads it (Blizzard_AchievementUI.lua:1233):
-- GetAchievementInfo's 4th return (completed: earned on this account), 9th
-- (flags: ACHIEVEMENT_FLAGS_ACCOUNT marks an account-wide one), 13th
-- (wasEarnedByMe) and 14th (earnedBy, a name); done and total count its
-- criteria (GetAchievementCriteriaInfo's 3rd return), and an achievement of
-- one counted criterion gives its quantity and required amount instead.
-- Kept for MEMO_SECONDS or until data changes (a meta achievement has 30
-- criteria, and a panel redraws often).
-------------------------------------------------------------------------------
local Achievements = {}
Recollect.Facts.Achievements = Achievements

local Try = Recollect.Utilities.Try
local IsPositiveID = Recollect.Utilities.IsPositiveID

local seams = {
  Info = function(achievementID) return GetAchievementInfo(achievementID) end,
  NumCriteria = function(achievementID) return GetAchievementNumCriteria(achievementID) end,
  Criteria = function(achievementID, index) return GetAchievementCriteriaInfo(achievementID, index) end,
  -- ACHIEVEMENT_FLAGS_ACCOUNT, a constant the client defines (0x20000)
  AccountFlag = function() return ACHIEVEMENT_FLAGS_ACCOUNT or 0x20000 end,
  Now = function() return GetTime() end,
}

-- The item's name for a criterion whose ID reads 0, or nil
local function ItemName(itemID)
  if not IsPositiveID(itemID) then return nil end
  local ok, name = pcall(Recollect.Facts.Item.Name, itemID)
  return ok and type(name) == "string" and name ~= "" and name or nil
end

-- Whether a criterion read (its ID and text) stands for the item named name
local function ByText(thisID, text, name)
  return name ~= nil and (thisID == 0 or thisID == nil) and text == name
end

function Achievements.Get(achievementID, criteriaID, itemID)
  if not IsPositiveID(achievementID) then return nil end
  local ok, id, name, _, completed = Try(seams.Info, achievementID)
  if not ok or id == nil or type(name) ~= "string" then return nil end
  local result = { achievementID = achievementID, name = name, earned = completed == true }
  if IsPositiveID(criteriaID) then
    local okN, count = Try(seams.NumCriteria, achievementID)
    local itemName = ItemName(itemID)
    local byText = nil
    for index = 1, okN and type(count) == "number" and count or 0 do
      local okC, text, _, done, quantity, required, _, _, _, _, thisID = Try(seams.Criteria, achievementID, index)
      if okC and thisID == criteriaID then
        result.criterionDone = done == true
        result.quantity, result.required = quantity, required
        byText = nil
        break
      end
      if okC and not byText and ByText(thisID, text, itemName) then byText = { done = done, quantity = quantity, required = required } end
    end
    if byText then
      result.criterionDone = byText.done == true
      result.quantity, result.required = byText.quantity, byText.required
      result.byText = true
    end
  end
  return result
end

-- Parts(achievementID, criteriaIDs, itemID): see the header
function Achievements.Parts(achievementID, criteriaIDs, itemID)
  if not IsPositiveID(achievementID) or type(criteriaIDs) ~= "table" then return nil end
  local ok, id = Try(seams.Info, achievementID)
  if not ok or id == nil then return nil end
  local wanted, wantedCount = {}, 0
  for _, criteriaID in ipairs(criteriaIDs) do
    if IsPositiveID(criteriaID) and not wanted[criteriaID] then
      wanted[criteriaID] = true
      wantedCount = wantedCount + 1
    end
  end
  local okN, count = Try(seams.NumCriteria, achievementID)
  if not okN or type(count) ~= "number" then return { found = 0, done = 0, unreadable = true, wanted = wantedCount } end
  local itemName = ItemName(itemID)
  local found, done, unreadable, textDone = 0, 0, false, nil
  for index = 1, count do
    local okC, text, _, criterionDone, _, _, _, _, _, _, thisID = Try(seams.Criteria, achievementID, index)
    if not okC or type(criterionDone) ~= "boolean" then
      unreadable = true
    elseif thisID ~= nil and wanted[thisID] then
      found = found + 1
      if criterionDone then done = done + 1 end
    elseif textDone == nil and ByText(thisID, text, itemName) then
      textDone = criterionDone
    end
  end
  -- The text match stands in only when no ID matched
  if found == 0 and textDone ~= nil then
    found = 1
    if textDone then done = 1 end
  end
  return { found = found, done = done, unreadable = unreadable, wanted = wantedCount }
end

-- PartsState(parts): "open", "done" or nil, see the header
function Achievements.PartsState(parts)
  if type(parts) ~= "table" or type(parts.found) ~= "number" or type(parts.done) ~= "number" then return nil end
  if parts.found > parts.done then return "open" end
  if parts.unreadable or parts.found == 0 or parts.found < (parts.wanted or 1) then return nil end
  return "done"
end

-- Whether a flags value has a bit set (no bit library needed)
local function HasFlag(flags, flag)
  if type(flags) ~= "number" or type(flag) ~= "number" or flag <= 0 then return false end
  return math.floor(flags / flag) % 2 == 1
end

local MEMO_SECONDS = 5
local memo, memoAt, generation, memoGeneration = {}, nil, 0, nil

local function Read(achievementID)
  local ok, id, name, _, completed, _, _, _, _, flags, _, _, _, wasEarnedByMe, earnedBy = Try(seams.Info, achievementID)
  if not ok or id == nil or type(name) ~= "string" then return nil end
  local okFlag, accountFlag = Try(seams.AccountFlag)
  local result = { achievementID = achievementID, name = name, earned = completed == true,
    byMe = wasEarnedByMe == true, earnedBy = type(earnedBy) == "string" and earnedBy ~= "" and earnedBy or nil }
  -- true, false, or nil when the flags or the constant can't be read
  if okFlag and type(flags) == "number" and type(accountFlag) == "number" then result.accountWide = HasFlag(flags, accountFlag) end
  if result.earned then return result end
  local okN, count = Try(seams.NumCriteria, achievementID)
  if not okN or type(count) ~= "number" then return result end
  local done, total = 0, 0
  for index = 1, count do
    local okC, _, _, criterionDone, quantity, required = Try(seams.Criteria, achievementID, index)
    -- a criterion that can't be read leaves the count unknown, never lower
    if not okC or type(criterionDone) ~= "boolean" then return result end
    total = total + 1
    if criterionDone then done = done + 1 end
    if count == 1 and type(quantity) == "number" and type(required) == "number" and required > 1 then
      result.quantity, result.required = quantity, required
    end
  end
  result.done, result.total = done, total
  return result
end

-- Progress(achievementID): how far along it is (see the header), or nil
function Achievements.Progress(achievementID)
  if not IsPositiveID(achievementID) then return nil end
  local now = seams.Now()
  if memoGeneration ~= generation or memoAt == nil or now < memoAt or now - memoAt >= MEMO_SECONDS then
    memo, memoAt, memoGeneration = {}, now, generation
  end
  local kept = memo[achievementID]
  if kept == nil then
    kept = Read(achievementID) or false
    memo[achievementID] = kept
  end
  return kept or nil
end

-- "3 of 5 done", "120 of 250", "not earned", "earned by Tanklite": a
-- progress's words, and whether it is still to do (true), done (false) or
-- unknown (nil)
function Achievements.ProgressWords(progress)
  if not progress then return "can't be read", nil end
  if progress.earned then
    local by
    if progress.byMe then
      by = "earned"
    else
      by = progress.earnedBy and ("earned by " .. progress.earnedBy) or "earned on another character"
    end
    if progress.accountWide == true then return by .. ", account-wide", false end
    if progress.accountWide == false then return by .. (progress.byMe and " by this character" or ""), false end
    return by, false
  end
  if progress.required then return ("%d of %d"):format(progress.quantity, progress.required), true end
  if progress.total and progress.total > 1 then return ("%d of %d done"):format(progress.done, progress.total), true end
  return "not earned", true
end

-- Data changed: every progress is read again
local listener = {}
function listener:ReceiveEvent() generation = generation + 1 end
Recollect.EventBus:Register(listener, { Recollect.Events.InventoryChanged })

Achievements._test = { seams = seams, Reset = function() memo, memoAt = {}, nil end,
  DataChanged = function() listener:ReceiveEvent() end }
