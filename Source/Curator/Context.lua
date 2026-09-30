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

-- Ranges (protocol 2, security design C, reviews PAY-01 and PAY-02): a
-- set of quest IDs as the runs a collection carries. Runs of consecutive
-- IDs, ascending, comma separated, each "g" or "g.l" in base 36: g the gap
-- from the end of the run before (from 0 for the first), l how many IDs the
-- run has after its first. 7,077 completed quests were 2,858 runs (probe
-- P7). ParseRanges bounds a text before a single ID is made: how many runs
-- (RANGE_RUNS), how many IDs they add up to (RANGE_IDS), every ID within
-- 1..RANGE_MAX, each number at most RANGE_DIGITS long; a tiny text can't
-- stand for millions of IDs.
Context.RANGE_RUNS = 20000
Context.RANGE_IDS = 100000
Context.RANGE_MAX = 2147483648
Context.RANGE_DIGITS = 7

local DIGITS36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function Base36(n)
  if n == 0 then return "0" end
  local out = {}
  while n > 0 do
    local d = n % 36
    table.insert(out, 1, DIGITS36:sub(d + 1, d + 1))
    n = (n - d) / 36
  end
  return table.concat(out)
end

-- RangesText(list): ascending IDs (repeats dropped) as runs
function Context.RangesText(list)
  local out, last, start, prev = {}, 0, nil, nil
  local function Close()
    if not start then return end
    local gap, extra = start - last, prev - start
    out[#out + 1] = extra > 0 and (Base36(gap) .. "." .. Base36(extra)) or Base36(gap)
    last = prev
  end
  for _, id in ipairs(list) do
    if prev == nil or id > prev then
      if start and id == prev + 1 then
        prev = id
      else
        Close()
        start, prev = id, id
      end
    end
  end
  Close()
  return table.concat(out, ",")
end

-- ParseRanges(text): the runs as { { first, count }, ... } and how many IDs
-- they hold, or nil and why; nothing is expanded
function Context.ParseRanges(text)
  if type(text) ~= "string" then return nil, "not text" end
  if text == "" then return {}, 0 end
  if #text > Context.RANGE_RUNS * (2 * Context.RANGE_DIGITS + 2) then return nil, "too long" end
  local runs, total, last = {}, 0, 0
  for token in (text .. ","):gmatch("([^,]*),") do
    if #runs >= Context.RANGE_RUNS then return nil, "too many runs" end
    local gapText, extraText = token:match("^(%w+)%.(%w+)$")
    if not gapText then gapText = token:match("^(%w+)$") end
    if not gapText or #gapText > Context.RANGE_DIGITS or (extraText and #extraText > Context.RANGE_DIGITS) then
      return nil, "a malformed run"
    end
    local gap, extra = tonumber(gapText:lower(), 36), extraText and tonumber(extraText:lower(), 36) or 0
    if not gap or not extra or (gap < 1) then return nil, "a malformed run" end
    local first = last + gap
    local count = extra + 1
    total = total + count
    if total > Context.RANGE_IDS then return nil, "too many IDs" end
    if first < 1 or first + count - 1 > Context.RANGE_MAX then return nil, "an ID out of range" end
    runs[#runs + 1] = { first, count }
    last = first + count - 1
  end
  return runs, total
end

-- A base's quest IDs as a collection carries them (RangesText)
function Context.BaseText(entry)
  local list = {}
  for questID in pairs(Context.BaseSet(entry)) do list[#list + 1] = questID end
  table.sort(list)
  return Context.RangesText(list)
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
