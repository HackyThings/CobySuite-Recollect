-------------------------------------------------------------------------------
-- Curator.Context: the state of the character that saw something (curator
-- spec, "Context block", D12). Every record points at a context block by
-- index; blocks are stored once and shared, so a session's records share a
-- few blocks.
--
--   contexts[n] = { char, class, race, level, faction, profs, chromie,
--                   warmode, map, build, difficulty }
--     char: an index into the account's characters (no GUID or name
--     travels); faction: 0 Horde, 1 Alliance, 2 neither (as the shipped
--     f0/f1); profs: the character's profession skill lines, "171.333";
--     difficulty: the instance difficulty (0 outside an instance, 8 a
--     Mythic+ keystone run), so the pipeline can tell a keystone run's
--     end-of-run loot apart and decide it item by item (blocks made before
--     it lack the field)
--   quests[n] = { char, at, kind = "base" or "delta", base, data }
--     the completed-quest state for records that need it (positions and
--     availability): one base per character per data version, then deltas
--     relative to that base, each immutable and shared only until the
--     completed-quest set changes (a turn-in, a daily or weekly reset)
--
-- Reads go through Context.seams (scripted by tests); a read that fails or
-- is secret leaves its field nil.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host

local Context = {}
Curator.Context = Context

local FACTIONS = { Horde = 0, Alliance = 1 }

Context.seams = {
  PlayerGUID = function() return UnitGUID("player") end,
  Class = function() return select(3, UnitClass("player")) end,
  Race = function() return select(3, UnitRace("player")) end,
  Level = function() return UnitLevel("player") end,
  Faction = function() return UnitFactionGroup("player") end,
  Professions = function() return GetProfessions() end,
  SkillLine = function(index) return select(7, GetProfessionInfo(index)) end,
  Chromie = function() return UnitChromieTimeID and UnitChromieTimeID("player") or 0 end,
  WarMode = function() return C_PvP.IsWarModeActive() end,
  Map = function() return C_Map.GetBestMapForUnit("player") end,
  Build = function() return select(2, GetBuildInfo()) end,
  Difficulty = function() return (select(3, GetInstanceInfo())) end,
  CompletedQuests = function() return C_QuestLog.GetAllCompletedQuestIDs() end,
  Compress = function(text) return C_EncodingUtil.CompressString(text) end,
  Decompress = function(data) return C_EncodingUtil.DecompressString(data) end,
  SecondsToReset = function() return C_DateAndTime.GetSecondsUntilDailyReset() end,
}

local keyToIndex, keyFor        -- context key -> index, per contexts table, in memory
                                -- (a clear puts a new one in place)
-- The quest-state memory belongs to one quests table: a clear or a swapped
-- store starts it again (QuestMemory)
local questsFor                 -- the quests table the three below describe
local questsDirty = true        -- the completed-quest set may have changed
local currentDelta = {}         -- [charIndex] = quest entry index shared until dirty
local resetAt                   -- server time of the next daily reset seen

local function QuestMemory(db)
  if questsFor ~= db.quests then
    questsFor, questsDirty, currentDelta, resetAt = db.quests, true, {}, nil
  end
end

-- The next free index of a table that pruning leaves holes in
local function NextIndex(db, counter, tbl)
  local n = db[counter]
  if type(n) ~= "number" then
    n = 0
    for index in pairs(tbl) do if index > n then n = index end end
  end
  n = n + 1
  db[counter] = n
  return n
end

local function Read(name, ...)
  local ok, value = pcall(Context.seams[name], ...)
  if not ok or Host.IsSecret(value) then return nil end
  return value
end

-- The account's index for this character (made on first sight)
function Context.CharIndex(db)
  local guid = Read("PlayerGUID")
  if not guid then return 0 end
  db.characters = type(db.characters) == "table" and db.characters or {}
  local entry = db.characters[guid]
  if not entry then
    entry = { index = CobySuite_Recollect.Utilities.TableCount(db.characters) + 1 }
    db.characters[guid] = entry
  end
  return entry.index
end

local function SkillLines()
  local slots = { pcall(Context.seams.Professions) }
  if not slots[1] then return nil end
  local lines = {}
  -- GetProfessions answers five slots, any of them nil (no second primary,
  -- no archaeology): every slot is read, never stopping at a gap
  for slot = 2, 6 do
    local index = slots[slot]
    local skillLine = index and Read("SkillLine", index)
    if skillLine then lines[#lines + 1] = skillLine end
  end
  table.sort(lines)
  return table.concat(lines, ".")
end

local function Block(db)
  local faction = Read("Faction")
  return {
    char = Context.CharIndex(db), class = Read("Class"), race = Read("Race"), level = Read("Level"),
    faction = faction and (FACTIONS[faction] or 2) or nil, profs = SkillLines(), chromie = Read("Chromie"),
    warmode = Read("WarMode"), map = Read("Map"), build = Read("Build"), difficulty = Read("Difficulty"),
  }
end

-- Owner(): the character as route conditions read it: { faction (0 Horde,
-- 1 Alliance, nil otherwise), classID, raceID }
function Context.Owner()
  local faction = Read("Faction")
  return { faction = faction and FACTIONS[faction] or nil, classID = Read("Class"), raceID = Read("Race") }
end

local function Key(block)
  return table.concat({ tostring(block.char), tostring(block.class), tostring(block.race), tostring(block.level),
    tostring(block.faction), tostring(block.profs), tostring(block.chromie), tostring(block.warmode),
    tostring(block.map), tostring(block.build), tostring(block.difficulty) }, "|")
end

-- Current(): the index of the context block for this moment, made once
function Context.Current()
  local db = Curator.Store.DB()
  if keyFor ~= db.contexts then
    keyToIndex, keyFor = {}, db.contexts
    for index, block in pairs(db.contexts) do keyToIndex[Key(block)] = index end
  end
  local block = Block(db)
  local key = Key(block)
  local index = keyToIndex[key]
  if index then return index end
  index = NextIndex(db, "nextContext", db.contexts)
  db.contexts[index] = block
  keyToIndex[key] = index
  Curator.Store.AddBytes(Curator.Store.ContextBytes(block))
  return index
end

-------------------------------------------------------------------------------
-- Quest state
-------------------------------------------------------------------------------
local function QuestSet()
  local ok, list = pcall(Context.seams.CompletedQuests)
  if not ok or type(list) ~= "table" then return nil end
  local set = {}
  for _, questID in ipairs(list) do set[questID] = true end
  return set, list
end

local function Pack(list)
  table.sort(list)
  local text = table.concat(list, ",")
  local ok, packed = pcall(Context.seams.Compress, text)
  if ok and type(packed) == "string" then return packed, true end
  return text, false
end

local function BaseFor(db, char)
  for index, entry in pairs(db.quests) do
    if entry.char == char and entry.kind == "base" then return index, entry end
  end
end

-- QuestRef(): the index of the quest-state entry for this moment (the
-- character's base, or the current delta against it); nil when the
-- completed quests can't be read
function Context.QuestRef()
  local db = Curator.Store.DB()
  QuestMemory(db)
  local char = Context.CharIndex(db)
  local set, list = QuestSet()
  if not set then return nil end
  local now = GetServerTime()
  if resetAt and now >= resetAt then questsDirty = true end
  local okReset, seconds = pcall(Context.seams.SecondsToReset)
  resetAt = now + (okReset and type(seconds) == "number" and seconds or 86400)
  local baseIndex = BaseFor(db, char)
  if not baseIndex then
    local data, packed = Pack(list)
    baseIndex = NextIndex(db, "nextQuest", db.quests)
    db.quests[baseIndex] = { char = char, at = now, kind = "base", data = data, packed = packed }
    Curator.Store.AddBytes(Curator.Store.QuestBytes(db.quests[baseIndex]))
    currentDelta[char], questsDirty = nil, false
    return baseIndex
  end
  if currentDelta[char] and not questsDirty then return currentDelta[char] end
  local base = Context.BaseSet(db.quests[baseIndex])
  local added, removed = {}, {}
  for questID in pairs(set) do if not base[questID] then added[#added + 1] = questID end end
  for questID in pairs(base) do if not set[questID] then removed[#removed + 1] = questID end end
  table.sort(added)
  table.sort(removed)
  local index = NextIndex(db, "nextQuest", db.quests)
  db.quests[index] = { char = char, at = GetServerTime(), kind = "delta", base = baseIndex,
    data = "+" .. table.concat(added, ",") .. ";-" .. table.concat(removed, ",") }
  Curator.Store.AddBytes(Curator.Store.QuestBytes(db.quests[index]))
  currentDelta[char], questsDirty = index, false
  return index
end

-- The base's quest IDs as a set (unpacked once per session)
local baseCache = setmetatable({}, { __mode = "k" })
function Context.BaseSet(entry)
  if baseCache[entry] then return baseCache[entry] end
  local text = entry.data
  if entry.packed then
    local ok, raw = pcall(Context.seams.Decompress, entry.data)
    text = ok and raw or ""
  end
  local set = {}
  for questID in (text or ""):gmatch("%d+") do set[tonumber(questID)] = true end
  baseCache[entry] = set
  return set
end

-- A base's quest IDs as the plain text a collection carries: ascending,
-- comma separated
function Context.BaseText(entry)
  local list = {}
  for questID in pairs(Context.BaseSet(entry)) do list[#list + 1] = questID end
  table.sort(list)
  return table.concat(list, ",")
end

-- A turn-in or a reset changes the set: the next QuestRef makes a new delta
function Context.MarkQuestsChanged()
  questsDirty = true
end

-- Drops contexts and quest entries no record or stamp names any more
-- (bases stay: later deltas are relative to them), with their bytes. The
-- store calls it after dropping findings; a write inserts its record
-- before the store trims, so what it names is never dropped under it.
function Context.Prune()
  local db = Curator.Store.DB()
  QuestMemory(db)
  local used, usedQuests = {}, {}
  for _, record in pairs(db.records) do
    for index in pairs(record.ctx or {}) do used[index] = true end
    for _, variant in pairs(record.variants or {}) do
      if type(variant.quests) == "number" then usedQuests[variant.quests] = true end
    end
  end
  for _, stamp in pairs(db.confirms) do
    for index in pairs(stamp.ctx or {}) do used[index] = true end
  end
  for index, block in pairs(db.contexts) do
    if not used[index] then
      db.contexts[index] = nil
      Curator.Store.AddBytes(-Curator.Store.ContextBytes(block))
    end
  end
  for index, entry in pairs(db.quests) do
    if entry.kind == "delta" and not usedQuests[index] and index ~= currentDelta[entry.char] then
      db.quests[index] = nil
      Curator.Store.AddBytes(-Curator.Store.QuestBytes(entry))
    end
  end
  keyFor = nil
end

local frame = CreateFrame("Frame")
pcall(frame.RegisterEvent, frame, "QUEST_TURNED_IN")
frame:SetScript("OnEvent", Context.MarkQuestsChanged)
