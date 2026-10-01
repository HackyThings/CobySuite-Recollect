-------------------------------------------------------------------------------
-- Facts.DataVersion: whether the shipped data files belong together
--
-- /recollect-data stamps Data/Relations.lua, Data/Vendors.lua and Data/Hints.lua
-- with one data version ("2026.09.26.1": the build's date and a counter that
-- rises within a day) and one data format (a small integer, raised whenever
-- the files' layout changes). A file with no stamp is format 1, version
-- "unstamped" (data built before the stamps). The three must carry the same
-- version and format, and the format must be one this Recollect reads
-- (SUPPORTED_FORMATS). Otherwise (a database built for a newer Recollect, or
-- files copied in part) the shipped data is off: Facts.Relations and
-- Facts.Vendors read empty tables, and one chat line says why, once per
-- session.
--
-- Check() compares the files as they are now. Get() is the answer taken when
-- this file loaded (the data files load before it): { dataVersion, format,
-- ok, why }, why "missing" (a file absent), "mismatch" (versions or formats
-- differ), "format" (a format this Recollect doesn't read), nil when ok; the
-- table is shared, read-only. Ok() says whether the shipped data may be
-- read, telling the player the first time it may not. Refresh() takes the
-- answer again (the data build loads this file after the files it wrote).
-- Hints() is the curator hints (Data/Hints.lua: unseen, the verified-unseen
-- facts; settled, rounds and quiet), { unseen = {} } while the data is off.
-------------------------------------------------------------------------------
local DataVersion = {}
Recollect.Facts.DataVersion = DataVersion

-- The data formats (1: the files before the stamps, no longer read; 2:
-- the stamps and the curator indexes; 3: the gold-only trade code V and the
-- display-only route conditions P, E and Q; 4: the sources D (Encounter
-- Journal loot), N (a renown reward), O (the Black Market) and U (the
-- Trading Post; 5: the meta achievement tables H and I, Relations.MetasOf and
-- ChildrenOf, and the display-only route conditions N (a renown level) and A
-- (an achievement earned), with E and Q, on purchases from AllTheThings; 6:
-- Hints.lua's settled sources and confirmation rounds, which only curator
-- mode reads; 7: every place of an NPC in Vendors.lua's P, every giver of a
-- quest in Relations' G, the boss loot chests (Relations' L) and a
-- treasure's spawn objects (Vendors.lua's S), 2026-09-28; 8: a V code's
-- price in currencies, with the stack "?" when it isn't known, 2026-09-29).
-- Each adds codes or tables the one before lacks, so an older file still
-- reads, a missing table as none (a format 6 record of one place or one
-- giver reads as a list of one; a format 7 file has no currency V)
DataVersion.SUPPORTED_FORMATS = { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true }

local UNSTAMPED = "unstamped"
local FILES = { "Relations", "Vendors", "Hints" }
local NO_HINTS = { unseen = {} }

local seams = {
  Message = function(text) Recollect.Utilities.Message(text) end,
}

-- result: Get()'s answer; told: whether the player was told this session
local state = { result = nil, told = false }

-- A data file's stamp: its version and format, "unstamped" and 1 for a file
-- with neither, nil for a file that isn't there
local function Stamp(data)
  if type(data) ~= "table" then return nil end
  if data.dataVersion == nil and data.format == nil then return UNSTAMPED, 1 end
  return data.dataVersion, data.format
end

-- The highest format this Recollect reads
local function Newest()
  local newest = 0
  for format in pairs(DataVersion.SUPPORTED_FORMATS) do
    if format > newest then newest = format end
  end
  return newest
end

function DataVersion.Check()
  local data = Recollect.Data or {}
  local version, format
  for i, name in ipairs(FILES) do
    local v, f = Stamp(data[name])
    if v == nil then return { ok = false, why = "missing", file = name } end
    if i == 1 then
      version, format = v, f
    elseif v ~= version or f ~= format then
      return { dataVersion = version, format = format, ok = false, why = "mismatch", file = name }
    end
  end
  if not DataVersion.SUPPORTED_FORMATS[format] then
    return { dataVersion = version, format = format, ok = false, why = "format" }
  end
  return { dataVersion = version, format = format, ok = true }
end

function DataVersion.Refresh()
  state.result = DataVersion.Check()
  return state.result
end

function DataVersion.Get()
  return state.result or DataVersion.Refresh()
end

-- The chat line for an answer that turns the data off
function DataVersion.Words(result)
  if result.why == "format" and type(result.format) == "number" and result.format > Newest() then
    return ("Recollect's database needs a newer Recollect (data format %d); what items are used for is off until then.")
      :format(result.format)
  end
  if result.why == "format" then
    return ("Recollect's database is older than this Recollect reads (data format %s); reinstall Recollect.")
      :format(tostring(result.format))
  end
  return "Recollect's data files don't match; reinstall Recollect. What items are used for is off until then."
end

function DataVersion.Ok()
  local result = DataVersion.Get()
  if result.ok then return true end
  if not state.told then
    state.told = true
    seams.Message(DataVersion.Words(result))
  end
  return false
end

function DataVersion.Hints()
  if not DataVersion.Ok() then return NO_HINTS end
  local hints = Recollect.Data and Recollect.Data.Hints
  return type(hints) == "table" and type(hints.unseen) == "table" and hints or NO_HINTS
end

DataVersion.Refresh()

-- Say it at login, not first when something is looked up
if EventUtil and EventUtil.RegisterOnceFrameEventAndCallback then
  EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_LOGIN", function() DataVersion.Ok() end)
end

DataVersion._test = { seams = seams, state = state }
