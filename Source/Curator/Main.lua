-------------------------------------------------------------------------------
-- Curator.Main: the opt-in, the curator ID and the life of the curator's
-- saved data (curator spec: D7, D14, D27, SavedVariables)
--
-- RECOLLECT_CURATOR_DB = {
--   schema, id (random, made once per account; every character shares it),
--   addonVersion, dataVersion, formatVersion (what the findings were made against),
--   records, confirms, delivered, awaiting, contexts, quests, reported, bytes
--     (the recorder fields, capped at 1 MB; Curator.Store owns their shape;
--     reported marks the items with no information already delivered, kept
--     across data versions, Recorders/NoInfo.lua),
--   noInfoNotice (the server time from which bag and bank sweeps may run:
--     set when curator mode is turned on from a build whose settings text
--     names them, or when the one-time chat line was shown; kept through a
--     layout reset and a delete),
--   notes (flags, feedback and errors the curator wrote or ran into:
--     Curator.Notes; outside the cap, never evicted),
--   history (every collection the author asked for, newest first:
--     Curator.History; outside the cap, with caps of its own),
--   windows (the curator windows' places and sizes, the dashboard's tab,
--     open sections and column widths),
--   intake, received (Cobanyte's client only, written by the dev console;
--     outside the cap and never cleared here),
--   frozen = { block, ... } (oldest first): findings made under an earlier
--     data version, format or saved-data layout (schema), each block
--     { dataVersion, formatVersion, addonVersion, schema, frozenAt, records,
--     confirms, contexts, quests, bytes, awaiting } exactly as they were,
--     never read into or changed here; a pull sends one block whole with
--     its own versions once no live finding is pending (Sharing.Snapshot),
--     and the data build reads each by the versions it carries.
-- A change of data version or format freezes the findings not handed over
-- yet into a new block at the next load (Main.Freeze: what the author
-- acknowledged stays live with its request, a revision he rejected goes),
-- and a newer schema freezes them too; findings of a schema older than
-- FIRST_KEPT_SCHEMA are dropped (Cobanyte, 2026-09-28, replacing D14's
-- clear: a curator's unsent findings survive any number of updates, and the
-- client never migrates them).
-- Notes are cleared only where the author already has them (Notes.OnDataVersionChanged).
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host

local Main = {}
Curator.Main = Main

-- 2 since protocol 2 (security design, 2026-09-30)
local SCHEMA = 2
-- Findings saved under a layout older than protocol 2's reach the author
-- only as leads no data build counts, and the author already holds them
-- from the pulls made before it, so they aren't kept: left as frozen
-- blocks they stayed pending for good, since a block goes whole and theirs
-- needed a large pull by hand (Cobanyte, 2026-09-30)
local FIRST_KEPT_SCHEMA = 2
local RECORDER_FIELDS = { "records", "confirms", "delivered", "awaiting", "contexts", "quests", "reported" }

local function NewID()
  local parts = {}
  for i = 1, 4 do parts[i] = ("%04x"):format(math.random(0, 65535)) end
  return table.concat(parts) .. ("%08x"):format(GetServerTime() % 4294967296)
end

Main.SCHEMA = SCHEMA
Main.FIRST_KEPT_SCHEMA = FIRST_KEPT_SCHEMA

-- Old(schema): findings of this layout are dropped rather than frozen
local function Old(schema)
  return type(schema) == "number" and schema < FIRST_KEPT_SCHEMA
end

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
-- field). A table of a newer schema keeps its findings as a frozen block
-- labelled with that schema; one older than FIRST_KEPT_SCHEMA (Old) drops
-- them, and one with no schema number at all is unreadable: both start
-- over, keeping only what outlives findings
function Main.DB()
  if type(RECOLLECT_CURATOR_DB) ~= "table" or RECOLLECT_CURATOR_DB.schema ~= SCHEMA then
    local keep = type(RECOLLECT_CURATOR_DB) == "table" and RECOLLECT_CURATOR_DB or {}
    local frozen = type(keep.frozen) == "table" and keep.frozen or {}
    local block = type(keep.schema) == "number" and not Old(keep.schema) and Block(keep, keep.schema) or nil
    if block then frozen[#frozen + 1] = block end
    RECOLLECT_CURATOR_DB = { schema = SCHEMA, id = type(keep.id) == "string" and keep.id or nil,
      intake = keep.intake, received = keep.received, notes = keep.notes, joinAsked = keep.joinAsked, noInfoNotice = keep.noInfoNotice, frozen = frozen,
      history = keep.history, windows = keep.windows, confirmed = keep.confirmed, generalConfirmed = keep.generalConfirmed,
      knownMembers = keep.knownMembers,
      receipts = keep.receipts, registry = keep.registry,
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
  Region = function() return GetCurrentRegionName() end,
}

-- Available(): whether curator mode can run here at all: this client's game
-- region is the author's (Const.REGION; Cobanyte, 2026-09-30: "Only ones
-- that can connect with me"). Curators and the author reach each other only
-- in game, and whispers and communities never cross regions; anywhere else
-- curator mode stays dormant, its saved findings kept as they are. A region
-- that can't be read is not available (yet)
function Main.Available()
  local ok, region = pcall(Main.seams.Region)
  return ok and type(region) == "string" and not Host.IsSecret(region) and region == Curator.Const.REGION
end

-- Opted in (the setting), where curator mode is available
function Main.IsEnabled()
  return Main.Available() and Curator.Config.Get("curator_enabled") == true
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

-- DropOldBlocks(): removes the frozen blocks saved under a layout older
-- than protocol 2's (a block awaiting V goes too: V would only have deleted
-- it); returns how many went
function Main.DropOldBlocks()
  local db = Main.DB()
  local dropped = 0
  for i = #db.frozen, 1, -1 do
    local block = db.frozen[i]
    if type(block) == "table" and Old(block.schema) then
      table.remove(db.frozen, i)
      dropped = dropped + 1
    end
  end
  return dropped
end

local function DeepCopy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = DeepCopy(v) end
  return out
end

-- Split(db, field): a field's entries sorted three ways: handed over (K
-- arrived for this very revision, V not yet: the author has it), dropped (a
-- revision the author rejected, never sent again) and the rest, to freeze
local function Split(db, field, sent, delivered)
  local rest = {}
  for key, entry in pairs(db[field]) do
    local rev = type(entry) == "table" and entry.rev or nil
    if rev ~= nil and db.delivered[key] == rev then
      sent[key], delivered[key] = entry, rev
    elseif rev == nil or entry.rejected ~= rev then
      rest[key] = entry
    end
  end
  return rest
end

-- Freeze(): the findings not handed over yet into a frozen block, labelled
-- with the versions they were made under, and recording starts over; false
-- when there was nothing to freeze. What the author already has stays live
-- with its request, so V still deletes it and none of it counts as waiting
-- again after a database update (Cobanyte, 2026-09-30: both sides at 0
-- right after a collection); a revision the author rejected goes
function Main.Freeze()
  local db = Main.DB()
  local sentRecords, sentConfirms, delivered = {}, {}, {}
  local records = Split(db, "records", sentRecords, delivered)
  local confirms = Split(db, "confirms", sentConfirms, delivered)
  local kept = next(sentRecords) ~= nil or next(sentConfirms) ~= nil
  local oldBytes = tonumber(db.bytes) or 0
  -- the kept findings still use the context blocks and quest entries: the
  -- block gets its own copy of them then
  local block = Block({ dataVersion = db.dataVersion, formatVersion = db.formatVersion, addonVersion = db.addonVersion,
    records = records, confirms = confirms, contexts = kept and DeepCopy(db.contexts) or db.contexts,
    quests = kept and DeepCopy(db.quests) or db.quests, bytes = oldBytes }, SCHEMA)
  if not block and not kept then return false end
  if block then db.frozen[#db.frozen + 1] = block end
  -- the reported marks stay: an item the author already has isn't sent
  -- again after a database update (Cobanyte, 2026-09-30: only what changed
  -- since the last send); one the new data knows isn't recorded anyway
  if kept then
    -- held from the older data version: never merged with what is recorded
    -- under the new one, and dropped rather than sent again under its label
    -- when its V is lost (Store.Record, Confirm, Lost; review CUR-01)
    for _, entry in pairs(sentRecords) do entry.held = true end
    for _, stamp in pairs(sentConfirms) do stamp.held = true end
    db.records, db.confirms, db.delivered = sentRecords, sentConfirms, delivered
    if Curator.Context and Curator.Context.Prune then pcall(Curator.Context.Prune) end
  else
    for _, field in ipairs(RECORDER_FIELDS) do
      if field ~= "reported" then db[field] = {} end
    end
  end
  if Curator.Store and Curator.Store.Recount then pcall(Curator.Store.Recount) end
  if block and kept then block.bytes = math.max(0, oldBytes - (tonumber(db.bytes) or 0)) end
  Main.BumpEpoch()
  return block ~= nil
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
    if not frozen then
      -- nothing to freeze, but work begun under the old data version is
      -- dropped (the epoch); the reported marks stay, as in Freeze
      Main.BumpEpoch()
    end
    if Curator.Notes then Curator.Notes.OnDataVersionChanged() end
    Host.Log("Data version %s (format %s) replaced %s (format %s): %s", tostring(versions.data), tostring(versions.format),
      tostring(had), tostring(db.formatVersion), frozen and "the findings made under it are kept as a frozen block" or "no findings to keep")
  end
  db.dataVersion, db.formatVersion, db.addonVersion = versions.data, versions.format, versions.addon
  return had ~= nil
end

Host.OnLoaded(function()
  Curator.Config.InitializeData()
  if not Main.Available() then
    -- dormant: no curator ID made, no findings frozen or migrated, nothing sent
    Host.Log("Curator mode is not available in this game region: dormant")
    return
  end
  Main.DB()
  local dropped = Main.DropOldBlocks()
  if dropped > 0 then
    Host.Log("Curator dropped %d frozen block(s) saved before protocol 2 (leads only, which the author already holds)", dropped)
  end
  Main.CheckDataVersion()
  Host.Log("Curator mode %s; curator ID %s", Main.IsEnabled() and "on" or "off", Main.CuratorID())
end)
