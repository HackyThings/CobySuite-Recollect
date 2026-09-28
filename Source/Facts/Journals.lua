-------------------------------------------------------------------------------
-- Facts.Journals: which items buy which mounts and pets, from the game's own
-- collection journals
--
-- A vendor collectible's journal source text lists its cost as item links
-- with counts ("Cost: 1|Hitem:193696|h...|h 1|Hitem:193633|h...|h"). Item
-- links and counts read the same in every locale. After login, once the
-- mount and pet journals are ready, every mount (C_MountJournal.GetMountIDs,
-- GetMountInfoExtraByID's 3rd return) and pet species (GetPetInfoBySpeciesID
-- for 1 to MAX_SPECIES, 5th return) is read a chunk per frame, so there is
-- no hitch, and the index is kept for the session:
--   index[costItemID] = { { kind = "mount" | "pet", id, count }, ... }
-- Only the links are stored; whether each target is collected is read live
-- when an item is checked. Get() returns nil until the index is built.
--
-- A source text whose read fails is read once more RETRY_DELAY seconds after
-- the pass (at most MAX_RETRIES targets); what still fails leaves the index
-- incomplete (Incomplete() counts them, BA-02): an item missing from an
-- incomplete index may buy one of them, so Currency can't call it free of
-- journal uses.
-------------------------------------------------------------------------------
local Journals = {}
Recollect.Facts.Journals = Journals

local Try = Recollect.Utilities.Try
local Ready = Recollect.Facts.Ready

local MAX_SPECIES = 8000
local MOUNTS_PER_STEP = 150
local SPECIES_PER_STEP = 400
local RETRY_DELAY = 2
local MAX_RETRIES = 500

local seams = {
  MountIDs = function() return C_MountJournal.GetMountIDs() end,
  MountSource = function(mountID)
    local _, _, source = C_MountJournal.GetMountInfoExtraByID(mountID)
    return source
  end,
  PetSource = function(speciesID)
    local name, _, _, _, source = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
    return name and source or nil
  end,
  After = function(delay, fn) C_Timer.After(delay, fn) end,
}

local index = nil
local building = false
local incomplete = 0   -- targets whose source text could not be read, after the retry

-- The item costs a source text lists, added to into. One entry per item
-- and collectible: a text that names two vendors (one per faction) repeats
-- the cost, and the first mention is kept (ATT cross-check 2026-09-23: Love
-- Token and the Halaa tokens read double when repeats were added up).
function Journals.AddCosts(into, kind, id, source)
  if type(source) ~= "string" then return end
  for count, itemID in source:gmatch("(%d+)%s*|Hitem:(%d+)") do
    local key = tonumber(itemID)
    local list = into[key]
    if not list then
      list = {}
      into[key] = list
    end
    local seen = false
    for _, entry in ipairs(list) do
      if entry.kind == kind and entry.id == id then seen = true end
    end
    if not seen then list[#list + 1] = { kind = kind, id = id, count = tonumber(count) } end
  end
end

local function Finish(built, unread)
  index = built
  building = false
  incomplete = unread
  Recollect.Debug.Log("INVENTORY", "Journal index built: %d cost items, %d sources unreadable",
    CobySuite_Recollect.Utilities.TableCount(built), unread)
  Recollect.EventBus:Fire(Recollect.Events.InventoryChanged, "journals")
end

-- One target's source text into built; false when the read failed
local function ReadTarget(built, kind, id)
  local ok, source = Try(kind == "mount" and seams.MountSource or seams.PetSource, id)
  if ok then Journals.AddCosts(built, kind, id, source) end
  return ok
end

-- The failed targets read once more; what still fails is counted
local function Retry(built, failed)
  local unread = math.max(0, #failed - MAX_RETRIES)
  for i = 1, math.min(#failed, MAX_RETRIES) do
    if not ReadTarget(built, failed[i][1], failed[i][2]) then unread = unread + 1 end
  end
  Finish(built, unread)
end

local function StepPets(built, from, failed)
  for speciesID = from, math.min(from + SPECIES_PER_STEP - 1, MAX_SPECIES) do
    if not ReadTarget(built, "pet", speciesID) then failed[#failed + 1] = { "pet", speciesID } end
  end
  if from + SPECIES_PER_STEP > MAX_SPECIES then
    if #failed > 0 then
      seams.After(RETRY_DELAY, function() Retry(built, failed) end)
    else
      Finish(built, 0)
    end
  else
    seams.After(0, function() StepPets(built, from + SPECIES_PER_STEP, failed) end)
  end
end

local function StepMounts(built, ids, from, failed)
  for i = from, math.min(from + MOUNTS_PER_STEP - 1, #ids) do
    if not ReadTarget(built, "mount", ids[i]) then failed[#failed + 1] = { "mount", ids[i] } end
  end
  if from + MOUNTS_PER_STEP > #ids then
    seams.After(0, function() StepPets(built, 1, failed) end)
  else
    seams.After(0, function() StepMounts(built, ids, from + MOUNTS_PER_STEP, failed) end)
  end
end

local function Start()
  local ok, ids = Try(seams.MountIDs)
  if not ok or type(ids) ~= "table" then return end
  building = true
  StepMounts({}, ids, 1, {})
end

-- Get(): the index, or nil while it is not built yet (starts the build when
-- the journals are ready)
function Journals.Get()
  if index then return index end
  if not building and Ready.Mounts() and Ready.Pets() then Start() end
  return nil
end

-- How many journal entries could not be read into the index (0 when it is
-- complete, or not built yet)
function Journals.Incomplete()
  return index and incomplete or 0
end

-- A mount's or pet's journal source text, read live, or nil
function Journals.SourceText(kind, id)
  local ok, text = Try(kind == "mount" and seams.MountSource or seams.PetSource, id)
  return ok and type(text) == "string" and text or nil
end

-- Start reading soon after login, so the index is there before anything asks
local START_AFTER = 3
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_ENTERING_WORLD")
  seams.After(START_AFTER, function() Journals.Get() end)
end)

Journals._test = {
  seams = seams,
  Reset = function() index, building, incomplete = nil, false, 0 end,
  Set = function(built, unread) index, building, incomplete = built, false, unread or 0 end,
  -- Isolate(): the session's index, build state and unread count set aside
  -- for a test (reset to not built); returns the function that puts them back
  Isolate = function()
    local savedIndex, savedBuilding, savedIncomplete = index, building, incomplete
    index, building, incomplete = nil, false, 0
    return function() index, building, incomplete = savedIndex, savedBuilding, savedIncomplete end
  end,
  Start = Start,
}
