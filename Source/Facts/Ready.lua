-------------------------------------------------------------------------------
-- Facts.Ready: whether a data source can be believed yet
--
-- Several collection and quest calls answer false, not nil, before their
-- data has loaded (IsQuestFlaggedCompleted and IsRepeatableQuest return
-- non-nilable booleans; PlayerHasToy and GetNumCollectedInfo have no nil
-- convention). A false read too early would become a wrong verdict, so every
-- purpose check asks its source's gate first and says Unknown until it
-- opens:
--   Toys    the Toy Box lists at least one toy
--   Pets    the Pet Journal owns or lists at least one pet (GetNumPets'
--           second return, owned, ignores the journal's saved filters and
--           search; its first, listed, is what they leave, and covers an
--           account that owns no pets)
--   Mounts  the Mount Journal lists at least one mount
--   Heirlooms  C_Heirloom.GetNumKnownHeirlooms() above 0 (not in Blizzard's
--           generated docs; a client without it keeps the gate closed, so
--           heirlooms read as unread, never as missing; the Lab's Ready probe
--           records its answer)
--   Quests  QUEST_SETTLE seconds after the first PLAYER_ENTERING_WORLD, and
--           the completed-quest list is not empty
-- Once open, each of these gates stays open for the session: the Lab found
-- every source full at its first check and unchanged afterwards, and the
-- quest and mount gates build the whole list on each read, once per row per
-- redraw. These gates are a first guess; the Lab's Ready probe records when
-- each source really fills in, at login and after, and they are tuned from
-- that.
--
-- Events that can change a verdict without a bag change (a toy, mount or
-- pet learned, a quest turned in, a recipe learned) fire InventoryChanged.
-------------------------------------------------------------------------------
local Ready = {}
Recollect.Facts.Ready = Ready

local Try = Recollect.Utilities.Try
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber

local QUEST_SETTLE = 5

local seams = {
  NumToys = function()
    local fn = C_ToyBox.GetNumToys or C_ToyBox.GetNumTotalDisplayedToys
    return fn()
  end,
  NumPets = function() return C_PetJournal.GetNumPets() end,
  MountIDs = function() return C_MountJournal.GetMountIDs() end,
  NumHeirlooms = function() return C_Heirloom.GetNumKnownHeirlooms() end,
  CompletedQuestIDs = function() return C_QuestLog.GetAllCompletedQuestIDs() end,
  Now = function() return GetTime() end,
}

local enteredWorldAt = nil

-- Gates already open this session, by name (toys, pets, mounts, heirlooms, quests)
local latched = {}

local function ResetLatches()
  latched = {}
end

local function PositiveCount(fn)
  local ok, n = Try(fn)
  return ok and IsFiniteNumber(n) and n > 0 or false
end

local function NonEmptyList(fn)
  local ok, list = Try(fn)
  return ok and type(list) == "table" and #list > 0 or false
end

-- GetNumPets: (listed after the journal's filters and search, owned).
-- Blizzard's journal walks 1..listed with GetPetInfoByIndex and shows owned
-- as its count; filters that list nothing leave listed at 0 while loaded.
local function PetsCounted(fn)
  local ok, listed, owned = Try(fn)
  if not ok then return false end
  return (IsFiniteNumber(owned) and owned > 0) or (IsFiniteNumber(listed) and listed > 0) or false
end

-- The latch is read first, so an open gate costs no client read
local function Latched(key, check, fn)
  if latched[key] then return true end
  if check(fn) then latched[key] = true end
  return latched[key] or false
end

function Ready.Toys() return Latched("toys", PositiveCount, seams.NumToys) end
function Ready.Pets() return Latched("pets", PetsCounted, seams.NumPets) end
function Ready.Mounts() return Latched("mounts", NonEmptyList, seams.MountIDs) end
function Ready.Heirlooms() return Latched("heirlooms", PositiveCount, seams.NumHeirlooms) end

function Ready.Quests()
  if latched.quests then return true end
  if not enteredWorldAt or seams.Now() - enteredWorldAt < QUEST_SETTLE then return false end
  return Latched("quests", NonEmptyList, seams.CompletedQuestIDs)
end

-- Appearances and equipped items: read once the world has settled after
-- login (the same wait as quests; no call says when either has loaded)
function Ready.Transmog()
  return enteredWorldAt ~= nil and seams.Now() - enteredWorldAt >= QUEST_SETTLE
end

function Ready.Equipment()
  return enteredWorldAt ~= nil and seams.Now() - enteredWorldAt >= QUEST_SETTLE
end

-- Seconds since the first PLAYER_ENTERING_WORLD, or nil before it
function Ready.SinceEnteredWorld()
  return enteredWorldAt and (seams.Now() - enteredWorldAt) or nil
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local notify = CobySuite_Recollect.Utilities.Coalesce(0.5, function()
  Recollect.EventBus:Fire(Recollect.Events.InventoryChanged, "ready")
end)

local CHANGE_EVENTS = {
  "TOYS_UPDATED", "NEW_TOY_ADDED",
  "PET_JOURNAL_LIST_UPDATE", "NEW_PET_ADDED",
  "NEW_MOUNT_ADDED", "HEIRLOOMS_UPDATED",
  "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED",
  "NEW_RECIPE_LEARNED",
  "ACHIEVEMENT_EARNED", "CRITERIA_EARNED",
  "EQUIPMENT_SETS_CHANGED",
  "TRANSMOG_COLLECTION_UPDATED", "PLAYER_EQUIPMENT_CHANGED",
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
for _, event in ipairs(CHANGE_EVENTS) do
  pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_ENTERING_WORLD" then
    if not enteredWorldAt then
      enteredWorldAt = seams.Now()
      C_Timer.After(QUEST_SETTLE + 0.5, function() notify:Call() end)
    end
    return
  end
  notify:Call()
end)

Ready._test = {
  seams = seams,
  -- Also closes every latch, so a scripted seam starts from closed gates
  SetEnteredWorldAt = function(at) enteredWorldAt = at; ResetLatches() end,
  GetEnteredWorldAt = function() return enteredWorldAt end,
  ResetLatches = ResetLatches,
}
