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

-- One frame's step of the index build (the mount steps run first, then the
-- pet steps); each step and the
-- next are called through the module, so a development timing probe reaches
-- them (Task #294)
function Journals.StepPets(built, from, failed)
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
    seams.After(0, function() Journals.StepPets(built, from + SPECIES_PER_STEP, failed) end)
  end
end

function Journals.StepMounts(built, ids, from, failed)
  for i = from, math.min(from + MOUNTS_PER_STEP - 1, #ids) do
    if not ReadTarget(built, "mount", ids[i]) then failed[#failed + 1] = { "mount", ids[i] } end
  end
  if from + MOUNTS_PER_STEP > #ids then
    seams.After(0, function() Journals.StepPets(built, 1, failed) end)
  else
    seams.After(0, function() Journals.StepMounts(built, ids, from + MOUNTS_PER_STEP, failed) end)
  end
end

local function Start()
  local ok, ids = Try(seams.MountIDs)
  if not ok or type(ids) ~= "table" then return end
  building = true
  Journals.StepMounts({}, ids, 1, {})
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

-------------------------------------------------------------------------------
-- Facts.LiveSources: where the game itself says an item comes from, read
-- live (Task #394; Cobanyte, 2026-10-13: new 12.1.5 items with no
-- information yet). Information only, like the journals' source text
-- (contract rule 25, "Not shipped data"): nothing under Purposes/ or
-- Verdicts/ reads this module, so it never moves a verdict, the band or the
-- Tip.
--
--   Decor(itemID)       the housing catalog's source text for a decor item
--                       (C_HousingCatalog.GetCatalogEntryInfoByItem's
--                       HousingCatalogEntryInfo.sourceText: "Describes
--                       specific sources this entry may be gained from"),
--                       cleaned by Clean; nil when it has none or can't be read
--   Appearance(itemID)  the appearance's source type for gear
--                       (C_TransmogCollection.GetItemInfo gives the item's
--                       source, GetSourceInfo its AppearanceSourceInfo, whose
--                       sourceType is the index of the wardrobe's
--                       TRANSMOG_SOURCE_<n> label; for a boss drop
--                       GetAppearanceSourceDrops names the encounters):
--                       { sourceType, words, drops } or nil. Only the seven
--                       indexes below are worded; any other says nothing.
--                       Read only once Ready.Transmog() opens.
--   For(itemID)         both, as { { kind = "catalog" | "appearance", label,
--                       text, sourceType } } (catalog first; an empty list
--                       when the game says nothing)
--   Covered(entry, relations)  whether a shipped source of the same kind
--                       already names it (a live route of a kind in COVERS),
--                       so an appearance's vaguer words aren't said twice
--   Clean(text)         colors, links and textures out, its lines joined "; "
--                       (shared with the journals' text, TooltipUI.JournalText)
--
-- The source type is NOT Enum.TransmogSource (Task #408, 2026-10-14: 115 new
-- 12.1.5 items with type 7 read "An achievement reward" while the game says
-- Trading Post). AppearanceSourceInfo.sourceType is typed luaIndex in the
-- generated docs, and the wardrobe words it with its own global string,
-- _G["TRANSMOG_SOURCE_" .. sourceType] (Blizzard_FrameXMLUtil/
-- CollectionsUtil.lua, GetAppearanceSourceTextAndColor; the Source filter
-- menu builds the same labels, Blizzard_Wardrobe.lua; the Enum has other
-- numbers: 7 is Achievement there). The labels, from the game's own
-- GlobalStrings for the live branch: 1 Boss Drop, 2 Quest, 3 Vendor, 4 World
-- Drop, 5 Achievement, 6 Profession, 7 Trading Post; 1, 3, 4 and 7 were also
-- read in game by Verify q394-01 (rec.dev.live-sources). No other index has a
-- label, so any other says nothing rather than a guess.
-- Answers are kept per item until data changes or 5 seconds pass (rule 9),
-- through Facts.Buys.Stamp. Every read goes through Utilities.Try, and a
-- field that is a secret value is no answer.
-------------------------------------------------------------------------------
-- (kept in this file beside the journals' source text, its closest
-- relative, in a block of its own)
-------------------------------------------------------------------------------
do
  local LiveSources = {}
  Recollect.Facts.LiveSources = LiveSources

  local Try = Recollect.Utilities.Try
  local IsPositiveID = Recollect.Utilities.IsPositiveID
  local function IsSecret(value) return Recollect.Utilities.IsSecret(value) end   -- read at call time: suites script it

  local seams = {
    DecorInfo = function(itemID) return C_HousingCatalog.GetCatalogEntryInfoByItem(itemID) end,
    TransmogItem = function(itemID) return C_TransmogCollection.GetItemInfo(itemID) end,
    SourceInfo = function(sourceID) return C_TransmogCollection.GetSourceInfo(sourceID) end,
    SourceDrops = function(sourceID) return C_TransmogCollection.GetAppearanceSourceDrops(sourceID) end,
    Ready = function() return Recollect.Facts.Ready.Transmog() end,
    Stamp = function() return Recollect.Facts.Buys.Stamp() end,
  }

  -- The wardrobe's TRANSMOG_SOURCE_<n> indexes (see above), not Enum.TransmogSource
  local SOURCE = { BossDrop = 1, Quest = 2, Vendor = 3, WorldDrop = 4, Achievement = 5, Profession = 6, TradingPost = 7 }
  LiveSources.SOURCE = SOURCE

  -- Our own words for each source type worth saying; a boss drop is worded
  -- from its encounters (Words)
  local WORDS = {
    [SOURCE.Quest] = "A quest reward", [SOURCE.Vendor] = "Sold by a vendor", [SOURCE.WorldDrop] = "A world drop",
    [SOURCE.Achievement] = "An achievement reward", [SOURCE.Profession] = "Crafted by a profession",
    [SOURCE.TradingPost] = "Offered at the Trading Post",
  }

  -- The shipped source kinds (Facts.Relations) that already say the same as a
  -- source type, with more (a named boss, vendor, quest, achievement or recipe)
  local COVERS = {
    [SOURCE.BossDrop] = { journalDrop = true, dropsFrom = true, seasonDrop = true },
    [SOURCE.Quest] = { reward = true, choice = true },
    [SOURCE.Vendor] = { soldBy = true },
    [SOURCE.WorldDrop] = { zoneDrop = true },
    [SOURCE.Achievement] = { achievementReward = true },
    [SOURCE.Profession] = { craftedBy = true },
    [SOURCE.TradingPost] = { tradingPost = true },
  }
  LiveSources.COVERS = COVERS

  LiveSources.LABELS = { catalog = "Housing Catalog", appearance = "Appearances" }

  local function PlainString(value)
    return type(value) == "string" and not IsSecret(value) and value ~= "" and value or nil
  end

  function LiveSources.Clean(text)
    if not PlainString(text) then return nil end
    local parts = {}
    for line in (text:gsub("\r?\n", "|n") .. "|n"):gmatch("(.-)|n") do
      local plain = CobySuite_Recollect.Utilities.StripColors(line):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
      plain = plain:match("^%s*(.-)%s*$")
      if plain ~= "" then parts[#parts + 1] = plain end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "; ")
  end

  -- "Drops from Rasha'nan in the Dawnbreaker (Normal, Heroic)", "and from 2
  -- other bosses" when there are more; nil for an entry with no names
  local function DropWords(drops)
    local first = type(drops) == "table" and drops[1]
    if type(first) ~= "table" then return nil end
    local encounter, instance = PlainString(first.encounter), PlainString(first.instance)
    if not (encounter and instance) then return nil end
    local words = ("Drops from %s in %s"):format(encounter, instance)
    local difficulties = {}
    for _, name in ipairs(type(first.difficulties) == "table" and first.difficulties or {}) do
      if PlainString(name) then difficulties[#difficulties + 1] = name end
    end
    if #difficulties > 0 then words = ("%s (%s)"):format(words, table.concat(difficulties, ", ")) end
    local others = #drops - 1
    if others > 0 then words = ("%s, and from %d other %s"):format(words, others, others == 1 and "boss" or "bosses") end
    return words
  end

  local memo, memoStamp = {}, nil

  local function Kept(itemID, key, read)
    local stamp = seams.Stamp()
    if stamp ~= memoStamp then memo, memoStamp = {}, stamp end
    local kept = memo[itemID]
    if not kept then
      kept = {}
      memo[itemID] = kept
    end
    if kept[key] == nil then kept[key] = read(itemID) or false end
    return kept[key] or nil
  end

  local function ReadDecor(itemID)
    local ok, info = Try(seams.DecorInfo, itemID)
    if not ok or type(info) ~= "table" then return nil end
    local okText, text = pcall(function() return info.sourceText end)
    return okText and LiveSources.Clean(text) or nil
  end

  local function ReadAppearance(itemID)
    local okReady, ready = pcall(seams.Ready)
    if not (okReady and ready == true) then return nil end
    local ok, _, sourceID = Try(seams.TransmogItem, itemID)
    if not (ok and IsPositiveID(sourceID)) then return nil end
    local okInfo, info = Try(seams.SourceInfo, sourceID)
    if not okInfo or type(info) ~= "table" then return nil end
    local okType, sourceType = pcall(function() return info.sourceType end)
    if not (okType and not IsSecret(sourceType) and IsPositiveID(sourceType)) then return nil end
    if sourceType == SOURCE.BossDrop then
      local okDrops, drops = Try(seams.SourceDrops, sourceID)
      local count = okDrops and type(drops) == "table" and #drops or 0
      local words = count > 0 and DropWords(drops) or nil
      return { sourceType = sourceType, drops = count, words = words or "A boss drop in a dungeon or raid" }
    end
    local words = WORDS[sourceType]
    if not words then return nil end
    return { sourceType = sourceType, drops = 0, words = words }
  end

  function LiveSources.Decor(itemID)
    if not IsPositiveID(itemID) then return nil end
    return Kept(itemID, "decor", ReadDecor)
  end

  function LiveSources.Appearance(itemID)
    if not IsPositiveID(itemID) then return nil end
    return Kept(itemID, "appearance", ReadAppearance)
  end

  function LiveSources.For(itemID)
    local out = {}
    local decor = LiveSources.Decor(itemID)
    if decor then out[#out + 1] = { kind = "catalog", label = LiveSources.LABELS.catalog, text = decor } end
    local look = LiveSources.Appearance(itemID)
    if look then
      out[#out + 1] = { kind = "appearance", label = LiveSources.LABELS.appearance, text = look.words, sourceType = look.sourceType }
    end
    return out
  end

  -- Whether relations (Facts.Relations.For's list) hold a route still in the
  -- game of a kind that already says what entry says; a catalog entry, the
  -- game's whole text, is never covered
  function LiveSources.Covered(entry, relations)
    local kinds = entry and entry.sourceType and COVERS[entry.sourceType]
    if not kinds then return false end
    for _, relation in ipairs(type(relations) == "table" and relations or {}) do
      if kinds[relation.kind] and not (relation.flags and relation.flags.unavailable) then return true end
    end
    return false
  end

  LiveSources._test = {
    seams = seams,
    Reset = function() memo, memoStamp = {}, nil end,
  }
end
