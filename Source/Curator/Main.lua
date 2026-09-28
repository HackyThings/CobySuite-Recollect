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
-- }
-- A change of data version or format clears the recorder fields at the next
-- load (D14): findings are only meaningful against the data they compared.
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

-- The saved table, made valid (a table, the schema, an ID, every recorder field)
function Main.DB()
  if type(RECOLLECT_CURATOR_DB) ~= "table" or RECOLLECT_CURATOR_DB.schema ~= SCHEMA then
    local keep = type(RECOLLECT_CURATOR_DB) == "table" and RECOLLECT_CURATOR_DB or {}
    RECOLLECT_CURATOR_DB = { schema = SCHEMA, id = type(keep.id) == "string" and keep.id or nil,
      intake = keep.intake, received = keep.received, notes = keep.notes }
  end
  local db = RECOLLECT_CURATOR_DB
  if type(db.id) ~= "string" or db.id == "" then db.id = NewID() end
  for _, field in ipairs(RECORDER_FIELDS) do
    if type(db[field]) ~= "table" then db[field] = {} end
  end
  if type(db.bytes) ~= "number" then db.bytes = 0 end
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
function Main.ClearFindings()
  local db = Main.DB()
  for _, field in ipairs(RECORDER_FIELDS) do db[field] = {} end
  db.bytes = 0
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

-- D14: findings belong to one data version and format
function Main.CheckDataVersion()
  local db = Main.DB()
  local versions = Host.Versions()
  if db.dataVersion == versions.data and db.formatVersion == versions.format then return false end
  local had = db.dataVersion
  if had ~= nil then
    Main.ClearFindings()
    if Curator.Notes then Curator.Notes.OnDataVersionChanged() end
    Host.Log("Data version %s (format %s) replaced %s (format %s): curator findings cleared",
      tostring(versions.data), tostring(versions.format), tostring(had), tostring(db.formatVersion))
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
