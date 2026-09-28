-------------------------------------------------------------------------------
-- Curator.Main: the opt-in, the curator ID and the life of the curator's
-- saved data (curator spec: D7, D14, D27, SavedVariables)
--
-- RECOLLECT_CURATOR_DB = {
--   schema, id (random, made once per account; every character shares it),
--   addonVersion, dataVersion, formatVersion (what the findings were made against),
--   records, confirms, delivered, awaiting, contexts, quests, bytes
--     (the recorder fields, capped at 1 MB; Curator.Store owns their shape),
--   notes (flags, feedback and errors the curator wrote or ran into:
--     Curator.Notes; outside the cap, never evicted),
--   intake, received (Cobanyte's client only, written by the dev console;
--     outside the cap and never cleared here),
--   frozen = { block, ... } (oldest first): findings made under an earlier
--     data version, format or saved-data layout (schema), each block
--     { dataVersion, formatVersion, addonVersion, schema, frozenAt, records,
--     confirms, contexts, quests, bytes, awaiting } exactly as they were,
--     never read into or changed here; a pull sends one block whole with
--     its own versions once no live finding is pending (Sharing.Snapshot),
--     and the data build reads each by the versions it carries.
-- A change of data version, format or schema freezes the live recorder
-- fields into a new block at the next load and recording starts empty
-- (Cobanyte, 2026-09-28, replacing D14's clear: a curator's unsent findings
-- survive any number of updates, and the client never migrates them).
-- Notes are cleared only where the author already has them (Notes.OnDataVersionChanged).
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host

local Main = {}
Curator.Main = Main

local SCHEMA = 1
local RECORDER_FIELDS = { "records", "confirms", "delivered", "awaiting", "contexts", "quests" }

local function NewID()
  local parts = {}
  for i = 1, 4 do parts[i] = ("%04x"):format(math.random(0, 65535)) end
  return table.concat(parts) .. ("%08x"):format(GetServerTime() % 4294967296)
end

Main.SCHEMA = SCHEMA

-- A block of findings as they are, labelled with what they were made under
-- (nil when there is nothing to keep)
local function Block(db, schema)
  local any = false
  for _, field in ipairs({ "records", "confirms" }) do
    if type(db[field]) == "table" and next(db[field]) ~= nil then any = true end
  end
  if not any then return nil end
  return { dataVersion = db.dataVersion, formatVersion = db.formatVersion, addonVersion = db.addonVersion,
    schema = schema, frozenAt = GetServerTime(), records = db.records, confirms = db.confirms,
    contexts = type(db.contexts) == "table" and db.contexts or {}, quests = type(db.quests) == "table" and db.quests or {},
    bytes = tonumber(db.bytes) or 0 }
end

-- The saved table, made valid (a table, the schema, an ID, every recorder
-- field). A table of another schema, older or newer, keeps its findings as
-- a frozen block labelled with that schema; one with no schema number at
-- all is unreadable and starts over, keeping only what outlives findings
function Main.DB()
  if type(RECOLLECT_CURATOR_DB) ~= "table" or RECOLLECT_CURATOR_DB.schema ~= SCHEMA then
    local keep = type(RECOLLECT_CURATOR_DB) == "table" and RECOLLECT_CURATOR_DB or {}
    local frozen = type(keep.frozen) == "table" and keep.frozen or {}
    local block = type(keep.schema) == "number" and Block(keep, keep.schema) or nil
    if block then frozen[#frozen + 1] = block end
    RECOLLECT_CURATOR_DB = { schema = SCHEMA, id = type(keep.id) == "string" and keep.id or nil,
      intake = keep.intake, received = keep.received, notes = keep.notes, joinAsked = keep.joinAsked, frozen = frozen,
      dataVersion = keep.dataVersion, formatVersion = keep.formatVersion, addonVersion = keep.addonVersion }
    if block then
      Host.Log("Curator saved data of layout %s kept as a frozen block (%s), made under data %s", tostring(keep.schema),
        tostring(#frozen), tostring(keep.dataVersion))
    end
  end
  local db = RECOLLECT_CURATOR_DB
  if type(db.id) ~= "string" or db.id == "" then db.id = NewID() end
  for _, field in ipairs(RECORDER_FIELDS) do
    if type(db[field]) ~= "table" then db[field] = {} end
  end
  if type(db.bytes) ~= "number" then db.bytes = 0 end
  if type(db.frozen) ~= "table" then db.frozen = {} end
  return db
end

-------------------------------------------------------------------------------
-- Recording gates and the deferred queue (curator spec: the recorder
-- contract rule 1, Footprint). An event handler keeps only what the event
-- shows; comparing and writing happen in a deferred job, about BUDGET_MS a
-- frame. A job runs only while recording is allowed and nothing it was made
-- for has changed since (the epoch: curator mode turned off or on, findings
-- cleared, the store swapped).
-------------------------------------------------------------------------------
local BUDGET_MS = 1
local epoch = 0
local queue = {}   -- { { fn, epoch } }, oldest first

Main.seams = {
  Clock = function() return debugprofilestop() end,
}

-- Opted in (the setting)
function Main.IsEnabled()
  return Curator.Config.Get("curator_enabled") == true
end

-- Opted in and able to compare: the shipped data's files agree and are a
-- format this build reads. While they don't, the shipped data reads empty,
-- so every observation would look new: nothing is recorded then.
function Main.MayRecord()
  return Main.IsEnabled() and Host.Versions().ok == true
end

function Main.Epoch()
  return epoch
end

function Main.BumpEpoch()
  epoch = epoch + 1
end

-- A job or a read made at epoch `noted` may still write
function Main.StillCurrent(noted)
  return noted == epoch and Main.MayRecord()
end

local runner
local function Run()
  local started = Main.seams.Clock()
  while #queue > 0 do
    local job = table.remove(queue, 1)
    if Main.StillCurrent(job.epoch) then
      local ok, err = pcall(job.fn)
      if not ok then Host.Log("Curator job failed: %s", tostring(err)) end
    end
    if #queue > 0 and Main.seams.Clock() - started >= BUDGET_MS then
      runner:Call()
      return
    end
  end
end
runner = CobySuite_Recollect.Utilities.Coalesce(0, Run)

-- Defer(fn): runs fn in a later frame, if the epoch is unchanged then
function Main.Defer(fn)
  queue[#queue + 1] = { fn = fn, epoch = epoch }
  runner:Call()
end

-- Runs every queued job now (tests; the jobs' own gates still apply)
function Main.RunDeferred()
  runner:Cancel()
  while #queue > 0 do Run() end
  runner:Cancel()
end

-- Empties the recorder fields; the ID, intake and received stay
-- ClearFindings(): every finding goes, the frozen blocks too (opting out
-- with delete, a test)
function Main.ClearFindings()
  local db = Main.DB()
  for _, field in ipairs(RECORDER_FIELDS) do db[field] = {} end
  db.bytes = 0
  db.frozen = {}
  Main.BumpEpoch()
  if Curator.OnFindingsCleared then Curator.OnFindingsCleared() end
end

function Main.CuratorID()
  return Main.DB().id
end

-- Whether a test run is scripting the client right now, so a recorder's
-- event reads would see scripted answers, not the game's. Always false in a
-- release; the development hooks (Tests/Curator/Hooks.lua) point it at the
-- test runner.
function Main.IsScripted()
  return false
end

-- Freeze(): the live findings into a frozen block, labelled with the
-- versions they were made under, and recording starts empty; false when
-- there was nothing to keep
function Main.Freeze()
  local db = Main.DB()
  local block = Block(db, SCHEMA)
  if not block then return false end
  db.frozen[#db.frozen + 1] = block
  for _, field in ipairs(RECORDER_FIELDS) do db[field] = {} end
  db.bytes = 0
  Main.BumpEpoch()
  if Curator.OnFindingsCleared then Curator.OnFindingsCleared() end
  return true
end

-- Findings belong to one data version and format: a new one freezes them
-- (replacing D14's clear, 2026-09-28)
function Main.CheckDataVersion()
  local db = Main.DB()
  local versions = Host.Versions()
  if db.dataVersion == versions.data and db.formatVersion == versions.format then return false end
  local had = db.dataVersion
  if had ~= nil then
    local frozen = Main.Freeze()
    if Curator.Notes then Curator.Notes.OnDataVersionChanged() end
    Host.Log("Data version %s (format %s) replaced %s (format %s): %s", tostring(versions.data), tostring(versions.format),
      tostring(had), tostring(db.formatVersion), frozen and "the findings made under it are kept as a frozen block" or "no findings to keep")
  end
  db.dataVersion, db.formatVersion, db.addonVersion = versions.data, versions.format, versions.addon
  return had ~= nil
end

Host.OnLoaded(function()
  Curator.Config.InitializeData()
  Main.DB()
  Main.CheckDataVersion()
  Host.Log("Curator mode %s; curator ID %s", Main.IsEnabled() and "on" or "off", Main.CuratorID())
end)
