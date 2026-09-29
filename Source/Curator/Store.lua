-------------------------------------------------------------------------------
-- Curator.Store: the curator's findings in RECOLLECT_CURATOR_DB (curator
-- spec: the recorder contract rule 7, Confirmation, Saving before
-- deleting, the 1 MB cap)
--
-- A record is one fact with one observed value at one game build, under a
-- curator-local record ID made when it is created:
--   records[id] = { id, fact, kind, value, shipped, build, touched, ctx = { [ctxIndex]
--                   = count }, variants, rev, first, last, info }
--   kind: "addition", "conflict" or "notseen"; fact names the fact
--   ("v:<npc>:i:<item>:price"); value is the observed value as text (a
--   different value is a different record, and so is a later game build);
--   shipped is what the data said. info (an item with no information's
--   "ni:<item>" record only, Recorders/NoInfo.lua) is what the item is, as
--   "c<class>.<subclass>,q<quality>,b<bind>,e<expansion>,s<0|1>", a part that
--   couldn't be read left out; set when the record is made and filled in
--   by a later observation that read more parts.
--   variants = { [key] = { ctx, quests, reaction, cast, n } }: for records
--   whose observations carry more than their context (a position conflict's
--   quest state, a price conflict's reaction, a drop's cast just before),
--   how many observations had each combination; a field that couldn't be
--   read is "?", so every observation is counted in one variant.
-- A repeat observation adds to its context's count (and its variant) and
-- bumps rev. Eviction and a later sighting make a new ID.
--
-- A confirmation stamp is one source seen at one game build:
--   confirms[source .. "@" .. build] = { source, build, first, last, rev,
--     total, matched = "<numbers, comma separated>", ctx = { [ctxIndex] = count } }
--   matched lists, merged over visits, the positions in a shipped index of
--   the facts that were seen matching (vendors, a profession's recipes,
--   combines), or for sources with no index the matched IDs themselves
--   (loot, quests, what an item teaches, grants). A fact is confirmed only
--   when a stamp's matched set names it. A stamp's rev comes from one
--   counter for the whole store (nextRev), so a stamp evicted and made again
--   never repeats a revision an old acknowledgement names.
--
-- reported["ni:<item>"] = true: an item with no information whose record a
-- V deleted (the author has it), so it isn't recorded again under this data
-- version (at most NOINFO_REPORTED_CAP marks; Main.Freeze empties it).
--
-- confirmed[source] = round: this account's confirmation of a source with a
-- shipped listing (a stamp with a total) that a V saved, in that round (spec
-- D36). One confirmation per account and round: no stamp is made for the
-- source again until the data names a later round for it (Hints.lua's
-- rounds, after a difference there), and a source the data names settled
-- gets no stamp for a visit that matched in full. Differences are records
-- and always sent. Kept across data versions and layouts, outside the cap,
-- at most CONFIRMED_CAP sources; stamps with no total (loot and the like,
-- counted for drop rates) are never limited.
--
-- Delivery: delivered[id or key] = rev when that revision was acknowledged
-- (K); it goes in the next pull while its rev differs. awaiting[requestID] =
-- { at, recs = { [id] = rev }, confirms = { [key] = rev } } until a V says
-- the author's copy was saved (then the unchanged ones are deleted) or lost
-- (then they are pending again); dropped after AWAITING_DAYS.
--
-- bytes estimates every recorder field: records (with their variants),
-- stamps, delivered and reported marks, awaiting requests, context blocks and quest
-- entries (Context adds and removes its own through AddBytes). Past
-- CAP_BYTES the oldest records and stamps go first (D17), then the context
-- blocks and quest deltas nothing names any more (Context.Prune). Frozen
-- blocks (findings made under an earlier data version or layout, Main.lua's
-- header) count toward the same cap and go first, oldest block whole, before
-- any live finding. The notes (Notes.lua) and the collection history
-- (History.lua) live in the same table but outside the cap, each bounded by
-- its own limits. Store.Swap puts a scratch table in place for tests.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host

local Store = {}
Curator.Store = Store

local DAY = 86400
local MARK_BYTES = 16

Store.seams = {
  Build = function() return select(2, GetBuildInfo()) end,
}

-- The game build ("69933"), which every record and stamp carries
local function GameBuild()
  local ok, build = pcall(Store.seams.Build)
  return ok and build or "?"
end
-- Build(): the game build records are made under now
function Store.Build()
  return GameBuild()
end

local sandbox
local lookup, lookupFor   -- [fact] = { [value .. "@" .. build] = id }, built per records
                          -- table in memory (a clear puts a new one in place)

-------------------------------------------------------------------------------
-- The table
-------------------------------------------------------------------------------
local FIELDS = { "records", "confirms", "delivered", "awaiting", "contexts", "quests", "reported" }

local function Normalize(db)
  for _, field in ipairs(FIELDS) do
    if type(db[field]) ~= "table" then db[field] = {} end
  end
  if type(db.bytes) ~= "number" then db.bytes = 0 end
  if type(db.nextID) ~= "number" then db.nextID = 1 end
  if type(db.nextRev) ~= "number" then db.nextRev = 1 end
  if type(db.frozen) ~= "table" then db.frozen = {} end
  if type(db.confirmed) ~= "table" then db.confirmed = {} end
  return db
end

function Store.DB()
  if sandbox then return Normalize(sandbox) end
  return Normalize(Curator.Main.DB())
end

-- Swap(tbl): uses tbl instead of the saved table until Swap(nil); returns
-- the table that was in use (tests put a scratch table in place this way).
-- Work scheduled against the other table is dropped (the epoch).
function Store.Swap(tbl)
  local previous = sandbox
  sandbox = tbl
  lookup, lookupFor = nil, nil
  Curator.Main.BumpEpoch()
  return previous
end

-- Tests: whether the in-memory lookup is built for the table in use, and its
-- bucket for one fact (read only; the suites check a deletion leaves none)
Store._test = {
  Bucket = function(fact)
    local db = Store.DB()
    if lookupFor ~= db.records or not lookup then return false, nil end
    return true, lookup[fact]
  end,
}

local function LookupKey(value, build)
  return value .. "@" .. tostring(build)
end

local function Lookup(db)
  if lookupFor == db.records and lookup then return lookup end
  lookup, lookupFor = {}, db.records
  for id, record in pairs(db.records) do
    lookup[record.fact] = lookup[record.fact] or {}
    lookup[record.fact][LookupKey(record.value, record.build)] = id
  end
  return lookup
end

-------------------------------------------------------------------------------
-- Size
-------------------------------------------------------------------------------
local function Count(tbl)
  return CobySuite_Recollect.Utilities.TableCount(tbl or {})
end

local function RecordBytes(record)
  return 48 + #record.fact + #record.value + #(record.shipped or "") + #(record.info or "") + Count(record.ctx) * 8
    + Count(record.variants) * 40
end

local function StampBytes(stamp)
  return 48 + #stamp.source + #(stamp.matched or "") + Count(stamp.ctx) * 8
end

local function AwaitingBytes(entry)
  return 32 + (Count(entry.recs) + Count(entry.confirms)) * MARK_BYTES
end

function Store.ContextBytes(block)
  return 64 + #tostring(block.profs or "")
end

function Store.QuestBytes(entry)
  return 32 + #tostring(entry.data or "")
end

-- AddBytes(n): Context's blocks and quest entries, as they come and go
function Store.AddBytes(n)
  local db = Store.DB()
  db.bytes = db.bytes + n
end

function Store.Recount()
  local db = Store.DB()
  local bytes = 0
  for _, record in pairs(db.records) do bytes = bytes + RecordBytes(record) end
  for _, stamp in pairs(db.confirms) do bytes = bytes + StampBytes(stamp) end
  bytes = bytes + Count(db.delivered) * MARK_BYTES
  bytes = bytes + Count(db.reported) * MARK_BYTES
  for _, entry in pairs(db.awaiting) do bytes = bytes + AwaitingBytes(entry) end
  for _, block in pairs(db.contexts) do bytes = bytes + Store.ContextBytes(block) end
  for _, entry in pairs(db.quests) do bytes = bytes + Store.QuestBytes(entry) end
  db.bytes = bytes
  return bytes
end

local function Unmark(db, key)
  if db.delivered[key] ~= nil then
    db.delivered[key] = nil
    db.bytes = db.bytes - MARK_BYTES
  end
end

local function RemoveRecord(db, id)
  local record = db.records[id]
  if not record then return end
  db.records[id] = nil
  Unmark(db, id)
  local bucket = lookupFor == db.records and lookup and lookup[record.fact]
  if bucket then
    bucket[LookupKey(record.value, record.build)] = nil
    if next(bucket) == nil then lookup[record.fact] = nil end
  end
  db.bytes = db.bytes - RecordBytes(record)
end

-- Remove(id): one record goes, with its delivered mark and its lookup entry
-- (an item with no information making room under its own cap, NoInfo)
function Store.Remove(id)
  local db = Store.DB()
  local had = db.records[id] ~= nil
  RemoveRecord(db, id)
  return had
end

-- Find(fact, value): the record of that fact and value at this game build,
-- or nil (whether Record would repeat it or make a new one)
function Store.Find(fact, value)
  local db = Store.DB()
  local byValue = Lookup(db)[fact]
  local id = byValue and byValue[LookupKey(tostring(value or ""), GameBuild())]
  return id and db.records[id] or nil
end

local function RemoveStamp(db, key)
  local stamp = db.confirms[key]
  if not stamp then return end
  db.confirms[key] = nil
  Unmark(db, key)
  db.bytes = db.bytes - StampBytes(stamp)
end

-- Oldest first: by the server time of the last write, then by the write
-- order (touched, from the store's counter) for writes in the same second
local function Oldest(db)
  local list = {}
  for id, record in pairs(db.records) do
    list[#list + 1] = { kind = "record", key = id, last = record.last or 0, touched = record.touched or 0 }
  end
  for key, stamp in pairs(db.confirms) do
    list[#list + 1] = { kind = "stamp", key = key, last = stamp.last or 0, touched = stamp.rev or 0 }
  end
  table.sort(list, function(a, b)
    if a.last ~= b.last then return a.last < b.last end
    return a.touched < b.touched
  end)
  return list
end

-- FrozenBytes(): the frozen blocks' size together.
-- Trim(), below, keeps the recorder fields and the frozen blocks under the
-- cap: the oldest frozen block goes whole first, then the oldest records
-- and stamps (whatever their kind, D17) with their delivered marks, then
-- what only they named (Context.Prune). A write calls it after inserting,
-- so the context and quest entry it names are already referenced.
function Store.FrozenBytes()
  local total = 0
  for _, block in ipairs(Store.DB().frozen) do total = total + (tonumber(block.bytes) or 0) end
  return total
end

function Store.Trim()
  local db = Store.DB()
  local cap = Curator.Const.CAP_BYTES
  if db.bytes + Store.FrozenBytes() <= cap then return 0 end
  local target, dropped = math.floor(cap * 0.9), 0
  -- the oldest frozen block goes whole first, before any live finding
  while #db.frozen > 0 and db.bytes + Store.FrozenBytes() > target do
    local block = table.remove(db.frozen, 1)
    Host.Log("Curator store over the cap: a frozen block made under data %s dropped", tostring(block.dataVersion))
  end
  target = math.max(0, target - Store.FrozenBytes())
  for _, entry in ipairs(Oldest(db)) do
    if db.bytes <= target then break end
    if entry.kind == "record" then RemoveRecord(db, entry.key) else RemoveStamp(db, entry.key) end
    dropped = dropped + 1
  end
  if dropped > 0 then
    if Curator.Context and Curator.Context.Prune then Curator.Context.Prune() end
    Host.Log("Curator store over the cap: %d oldest findings dropped", dropped)
  end
  return dropped
end

-------------------------------------------------------------------------------
-- Recording
-------------------------------------------------------------------------------
local function NextRev(db)
  local rev = db.nextRev
  db.nextRev = rev + 1
  return rev
end

local function Field(value)
  if value == nil then return "?" end
  return value
end

-- One observation's variant (extra = { quests, reaction, cast }), or nil
local function AddVariant(record, ctxIndex, extra)
  if type(extra) ~= "table" then return end
  local quests, reaction, cast = Field(extra.quests), Field(extra.reaction), Field(extra.cast)
  local key = table.concat({ tostring(ctxIndex), tostring(quests), tostring(reaction), tostring(cast) }, "|")
  record.variants = record.variants or {}
  local variant = record.variants[key]
  if not variant then
    variant = { ctx = ctxIndex, quests = quests, reaction = reaction, cast = cast, n = 0 }
    record.variants[key] = variant
  end
  variant.n = variant.n + 1
end

-- The parts of an info text ("c15.4,q3"), counted
local function InfoParts(info)
  local n = 0
  for _ in tostring(info or ""):gmatch("[^,]+") do n = n + 1 end
  return n
end

-- Quiet(fact, value): whether the author turned this finding down (Hints.lua's
-- quiet, spec D38: a walking NPC, a salvage recipe's placeholder), so it is
-- recorded no more
function Store.Quiet(fact, value)
  local quiet = (Host.Hints() or {}).quiet
  local entry = type(quiet) == "table" and quiet[fact]
  if entry == true then return true end
  return type(entry) == "table" and entry[tostring(value or "")] == true
end

-- Record(kind, fact, value, shipped, ctxIndex, extra, info): adds one
-- observation and returns its record, or nil when the finding is quiet
-- (Quiet). value and shipped are text; extra, when given, the observation's
-- { quests, reaction, cast } (see variants above); info, when given, what
-- the item is (see info above): kept on a new record, and on a repeat when
-- it has more parts than the record's.
function Store.Record(kind, fact, value, shipped, ctxIndex, extra, info)
  if Store.Quiet(fact, value) then return nil end
  local db = Store.DB()
  value = tostring(value or "")
  local build = GameBuild()
  local key = LookupKey(value, build)
  local byValue = Lookup(db)[fact]
  local id = byValue and byValue[key]
  local record = id and db.records[id]
  local now = GetServerTime()
  if record then
    db.bytes = db.bytes - RecordBytes(record)
    record.ctx[ctxIndex] = (record.ctx[ctxIndex] or 0) + 1
    record.rev = record.rev + 1
    record.last = now
  else
    id = "r" .. db.nextID
    db.nextID = db.nextID + 1
    record = { id = id, fact = fact, kind = kind, value = value, shipped = shipped and tostring(shipped) or nil,
      ctx = { [ctxIndex] = 1 }, rev = 1, first = now, last = now, build = build }
    db.records[id] = record
    byValue = Lookup(db)[fact] or {}
    Lookup(db)[fact] = byValue
    byValue[key] = id
  end
  AddVariant(record, ctxIndex, extra)
  if type(info) == "string" and info ~= "" and InfoParts(info) > InfoParts(record.info) then record.info = info end
  record.touched = NextRev(db)
  db.bytes = db.bytes + RecordBytes(record)
  Store.Trim()
  return record
end

local function MergePositions(current, positions)
  local set, list = {}, {}
  for number in (current or ""):gmatch("%d+") do set[tonumber(number)] = true end
  for _, position in ipairs(positions) do set[position] = true end
  for position in pairs(set) do list[#list + 1] = position end
  table.sort(list)
  return table.concat(list, ",")
end

-- Round(source): the confirmation round the data names for a source (1
-- unless a difference there started another) and whether it is settled
function Store.Round(source)
  local hints = Host.Hints() or {}
  local settled = type(hints.settled) == "table" and tonumber(hints.settled[source]) or nil
  local round = settled or (type(hints.rounds) == "table" and tonumber(hints.rounds[source])) or 1
  return round, settled ~= nil
end

-- Wanted(source, positions, total): whether a visit's stamp is still wanted
-- (spec D36): always for a source with no total; otherwise not once this
-- account's confirmation of this round was saved, nor for a settled source
-- that matched in full
function Store.Wanted(source, positions, total)
  if (tonumber(total) or 0) <= 0 then return true end
  local round, settled = Store.Round(source)
  if (Store.DB().confirmed[source] or 0) >= round then return false end
  return not (settled and #positions >= total)
end

-- Confirm(source, positions, total, ctxIndex): a visit to a source where the
-- facts at those positions (of total) were seen matching; nil when no stamp
-- is wanted (Wanted)
function Store.Confirm(source, positions, total, ctxIndex)
  if not Store.Wanted(source, positions, total) then return nil end
  local db = Store.DB()
  local build = GameBuild()
  local key = source .. "@" .. tostring(build)
  local stamp = db.confirms[key]
  local now = GetServerTime()
  if stamp then
    db.bytes = db.bytes - StampBytes(stamp)
  else
    stamp = { source = source, build = build, first = now, ctx = {} }
    db.confirms[key] = stamp
  end
  stamp.matched = MergePositions(stamp.matched, positions)
  stamp.total = total
  -- the round it confirms, so a stamp saved after a database update named a
  -- later round marks its own (MarkConfirmed)
  stamp.round = (tonumber(total) or 0) > 0 and (Store.Round(source)) or nil
  stamp.ctx[ctxIndex] = (stamp.ctx[ctxIndex] or 0) + 1
  stamp.rev = NextRev(db)
  stamp.last = now
  db.bytes = db.bytes + StampBytes(stamp)
  Store.Trim()
  return stamp
end

-------------------------------------------------------------------------------
-- Delivery
-------------------------------------------------------------------------------
-- Pending(): the records and stamps whose current revision was not
-- acknowledged yet, as { recs = { [id] = rev }, confirms = { [key] = rev } }
function Store.Pending()
  local db = Store.DB()
  local out = { recs = {}, confirms = {} }
  for id, record in pairs(db.records) do
    if db.delivered[id] ~= record.rev then out.recs[id] = record.rev end
  end
  for key, stamp in pairs(db.confirms) do
    if db.delivered[key] ~= stamp.rev then out.confirms[key] = stamp.rev end
  end
  return out
end

local function Mark(db, key, rev)
  if db.delivered[key] == nil then db.bytes = db.bytes + MARK_BYTES end
  db.delivered[key] = rev
end

-- Acknowledged(requestID, snapshot): K arrived for a snapshot (Pending's
-- shape); those revisions count as delivered and wait for V
function Store.Acknowledged(requestID, snapshot)
  local db = Store.DB()
  for id, rev in pairs(snapshot.recs or {}) do Mark(db, id, rev) end
  for key, rev in pairs(snapshot.confirms or {}) do Mark(db, key, rev) end
  if db.awaiting[requestID] then db.bytes = db.bytes - AwaitingBytes(db.awaiting[requestID]) end
  local entry = { at = GetServerTime(), recs = snapshot.recs or {}, confirms = snapshot.confirms or {} }
  db.awaiting[requestID] = entry
  db.bytes = db.bytes + AwaitingBytes(entry)
end

local function DropAwaiting(db, requestID)
  local entry = db.awaiting[requestID]
  if not entry then return nil end
  db.awaiting[requestID] = nil
  db.bytes = db.bytes - AwaitingBytes(entry)
  return entry
end

-- Saved(requestID): V says the author's copy is saved; unchanged records and
-- stamps of that request are deleted, changed ones stay pending
function Store.Saved(requestID)
  local db = Store.DB()
  local entry = DropAwaiting(db, requestID)
  if not entry then return false end
  local marks = Count(db.reported)
  for id, rev in pairs(entry.recs) do
    local record = db.records[id]
    if record and record.rev == rev then
      -- an item with no information the author now has: not recorded again
      -- under this data version (NoInfo), within the marks' cap
      local fact = record.fact
      if type(fact) == "string" and fact:find("^ni:") and not db.reported[fact] and marks < Curator.Const.NOINFO_REPORTED_CAP then
        db.reported[fact] = true
        db.bytes = db.bytes + MARK_BYTES
        marks = marks + 1
      end
      RemoveRecord(db, id)
    end
  end
  for key, rev in pairs(entry.confirms) do
    local stamp = db.confirms[key]
    if stamp and stamp.rev == rev then
      Store.MarkConfirmed(stamp)
      RemoveStamp(db, key)
    end
  end
  if Curator.Context and Curator.Context.Prune then Curator.Context.Prune() end
  return true
end

-- MarkConfirmed(stamp, frozen): the author saved this account's
-- confirmation of a source with a shipped listing, in the round the stamp was
-- made in (spec D36). A live stamp with no round is from this data version,
-- whose round the data names now; a frozen one with none (made before stamps
-- kept their round) marks nothing, since the data it was made under may have
-- named an earlier round
function Store.MarkConfirmed(stamp, frozen)
  if type(stamp) ~= "table" or type(stamp.source) ~= "string" or (tonumber(stamp.total) or 0) <= 0 then return end
  local db = Store.DB()
  local round = tonumber(stamp.round)
  if not round then
    if frozen then return end
    round = Store.Round(stamp.source)
  end
  if db.confirmed[stamp.source] == nil and Count(db.confirmed) >= Curator.Const.CONFIRMED_CAP then return end
  if (db.confirmed[stamp.source] or 0) < round then db.confirmed[stamp.source] = round end
end

-- Lost(requestID): V says the author's copy was lost; its records are sent again
function Store.Lost(requestID)
  local db = Store.DB()
  local entry = DropAwaiting(db, requestID)
  if not entry then return false end
  for id in pairs(entry.recs) do Unmark(db, id) end
  for key in pairs(entry.confirms) do Unmark(db, key) end
  return true
end

-- A frozen block's delivery: K marks it awaiting its request, V deletes it
-- whole, a lost V (or none within AWAITING_DAYS) makes it pending again
function Store.FrozenAcknowledged(block, requestID)
  block.awaiting, block.awaitingAt = requestID, GetServerTime()
end

-- FrozenSaved(requestID) / FrozenLost(requestID): true when a block had it
function Store.FrozenSaved(requestID)
  local db = Store.DB()
  for i, block in ipairs(db.frozen) do
    if block.awaiting == requestID then
      for _, stamp in pairs(type(block.confirms) == "table" and block.confirms or {}) do Store.MarkConfirmed(stamp, true) end
      table.remove(db.frozen, i)
      return true
    end
  end
  return false
end

function Store.FrozenLost(requestID)
  for _, block in ipairs(Store.DB().frozen) do
    if block.awaiting == requestID then
      block.awaiting, block.awaitingAt = nil, nil
      return true
    end
  end
  return false
end

-- NextFrozen(): the oldest block not waiting for V, or nil
function Store.NextFrozen()
  for _, block in ipairs(Store.DB().frozen) do
    if not block.awaiting then return block end
  end
  return nil
end

-- AwaitingIDs(): the request IDs still waiting for V (they go in R); ones
-- older than AWAITING_DAYS are dropped first
function Store.AwaitingIDs()
  local db = Store.DB()
  local cutoff = GetServerTime() - Curator.Const.AWAITING_DAYS * DAY
  local out = {}
  local expired = {}
  for requestID, entry in pairs(db.awaiting) do
    if (entry.at or 0) < cutoff then expired[#expired + 1] = requestID else out[#out + 1] = requestID end
  end
  -- expired as a lost request is: its findings are sent again (dropping it
  -- alone left them marked sent for good)
  for _, requestID in ipairs(expired) do Store.Lost(requestID) end
  for _, block in ipairs(db.frozen) do
    if block.awaiting and (block.awaitingAt or 0) < cutoff then block.awaiting, block.awaitingAt = nil, nil end
    if block.awaiting then out[#out + 1] = block.awaiting end
  end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

-- Counts(): records, stamps, pending (records and stamps not yet
-- delivered), bytes (the whole store, against the cap), pendingBytes (the
-- pending ones as the store counts them, before packing and compression:
-- what a pull would send, less the contexts it carries along), byKind
-- ({ [kind] = n }), noInfo (the live "ni:" records, also counted in
-- byKind.addition), frozen and frozenPending
function Store.Counts()
  local db = Store.DB()
  local out = { records = 0, pending = 0, pendingBytes = 0, stamps = 0, bytes = db.bytes, byKind = {}, noInfo = 0 }
  local pending = Store.Pending()
  for _, record in pairs(db.records) do
    out.records = out.records + 1
    out.byKind[record.kind] = (out.byKind[record.kind] or 0) + 1
    if type(record.fact) == "string" and record.fact:find("^ni:") then out.noInfo = out.noInfo + 1 end
  end
  for _ in pairs(db.confirms) do out.stamps = out.stamps + 1 end
  for id in pairs(pending.recs) do
    out.pending = out.pending + 1
    out.pendingBytes = out.pendingBytes + RecordBytes(db.records[id])
  end
  for key in pairs(pending.confirms) do
    out.pending = out.pending + 1
    out.pendingBytes = out.pendingBytes + StampBytes(db.confirms[key])
  end
  -- frozen blocks not yet acknowledged count as pending, whole
  out.frozen, out.frozenPending = #db.frozen, 0
  for _, block in ipairs(db.frozen) do
    if not block.awaiting then
      local n = Count(block.records or {}) + Count(block.confirms or {})
      out.frozenPending = out.frozenPending + n
      out.pending = out.pending + n
      out.pendingBytes = out.pendingBytes + (tonumber(block.bytes) or 0)
    end
  end
  return out
end
