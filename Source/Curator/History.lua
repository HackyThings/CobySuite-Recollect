-------------------------------------------------------------------------------
-- Curator.History: the curator's own record of every collection the author
-- asked for (the curator dashboard's History tab, Cobanyte 2026-09-28)
--
-- Written only from Sharing's existing steps (a request, the start, a
-- refusal, K, V, a cancel, a request that replaced one waiting for K), never
-- from the wire: nothing here is sent, and no message changes.
--
-- RECOLLECT_CURATOR_DB.history (in the store's table, so Store.Swap and the
-- loopback cover it as they cover notes):
--   since    the server time the history began (entries exist only from the
--            version that added it on)
--   entries  newest first: { request, mode ("L" live, "T" test; "l" and "t"
--            in entries from before protocol 2), by (the
--            author's character that asked), localOnly, prompt (asked you
--            first), state, why, asked, started, ack, saved, ended (server
--            times), contents }
--   contents { findings, kinds = { [addition|conflict|notseen] = n },
--              types = { [Decode type] = n }, stamps, notes,
--              noteKinds = { [flag|feedback|error] = n }, frozen, data,
--              format, bytes (packed, as sent), parts }
--   delivered { collections, findings, stamps, notes }: what the author
--            saved since the history began, added up at each save, so it
--            outlasts the entries the caps drop (the dashboard's Saved by
--            the author tile; a history from before the counter starts it
--            from its saved entries)
-- States: asked (starting, or waiting for your answer when prompt),
-- sending, acknowledged (the author has it, waiting for V), saved (V: the
-- author's copy is on disk, so the findings were deleted here), kept (V's
-- quarantined list: the author kept it only for a closer look, so it was
-- deleted here with no marker; never counted as delivered), rejected (V's
-- rejected list or an X "rejected:": the author turned it down, and its
-- findings aren't sent again unless they change), lost (V: the
-- author's copy was lost; its findings went back to pending and travel with
-- a later collection), cancelled (why: "you" or "author"), refused (why: the
-- reason S carried: busy, nodata, empty, declined, pack, large), replaced (a new
-- request came while this one waited for K; its findings stay pending),
-- interrupted (the game closed or reloaded mid-way, or it never started:
-- curator mode toggled between the request and its start), expired (a
-- prompt not answered in time, or no V within AWAITING_DAYS).
-- A refusal because curator mode is off is not kept: an opted-out player's
-- client keeps nothing.
--
-- Outside the 1 MB findings cap, with caps of its own (MAX_ENTRIES and
-- MAX_BYTES, oldest finished entries first): these are the curator's
-- receipts, small and bounded, and counting them in the cap would evict
-- findings to keep a record of sending them. Kept through a new database
-- (Main.Freeze); cleared with the findings when a curator opts out and
-- deletes them (OptOutDialog).
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host

local History = {}
Curator.History = History

History.MAX_ENTRIES = 100
History.MAX_BYTES = 32 * 1024
local DAY = 86400

History.seams = {
  Now = function() return GetServerTime() end,
}

local function Now()
  local ok, now = pcall(History.seams.Now)
  return ok and tonumber(now) or 0
end

-- The history table in the store in use, made valid
function History.DB()
  local db = Curator.Store.DB()
  local history = type(db.history) == "table" and db.history or {}
  db.history = history
  if type(history.entries) ~= "table" then history.entries = {} end
  if type(history.since) ~= "number" then history.since = Now() end
  if type(history.delivered) ~= "table" then
    local d = { collections = 0, findings = 0, stamps = 0, notes = 0 }
    for _, entry in ipairs(history.entries) do
      if entry.state == "saved" then
        local c = type(entry.contents) == "table" and entry.contents or {}
        d.collections = d.collections + 1
        d.findings = d.findings + (tonumber(c.findings) or 0)
        d.stamps = d.stamps + (tonumber(c.stamps) or 0)
        d.notes = d.notes + (tonumber(c.notes) or 0)
      end
    end
    history.delivered = d
  end
  return history
end

-- Delivered(): { collections, findings, stamps, notes } the author saved
-- since the history began
function History.Delivered()
  return History.DB().delivered
end

local function Find(request)
  if request == nil or request == "" then return nil end
  for _, entry in ipairs(History.DB().entries) do
    if entry.request == request then return entry end
  end
  return nil
end
History.Find = Find

-- An entry's size, estimated as the store estimates its fields
local function Bytes(entry)
  local n = 160 + #tostring(entry.request or "") + #tostring(entry.by or "") + #tostring(entry.why or "")
  local contents = entry.contents
  if type(contents) == "table" then
    for key in pairs(contents.types or {}) do n = n + 16 + #tostring(key) end
    n = n + #tostring(contents.data or "")
  end
  return n
end
History.Bytes = Bytes

local FINISHED = { saved = true, kept = true, rejected = true, lost = true, cancelled = true, refused = true, replaced = true,
  interrupted = true, expired = true }

-- Keeps the caps: the oldest finished entries go first, then the oldest
function History.Trim()
  local entries = History.DB().entries
  local total = 0
  for _, entry in ipairs(entries) do total = total + Bytes(entry) end
  local function Over() return #entries > History.MAX_ENTRIES or total > History.MAX_BYTES end
  for i = #entries, 1, -1 do
    if not Over() then break end
    if FINISHED[entries[i].state] then
      total = total - Bytes(entries[i])
      table.remove(entries, i)
    end
  end
  while Over() and #entries > 1 do
    total = total - Bytes(entries[#entries])
    table.remove(entries)
  end
end

-- The entry for a request, made (newest first) when there is none
local function Entry(request, sender, mode)
  local entry = Find(request)
  if not entry then
    entry = { request = request, mode = mode, by = sender, state = "asked", asked = Now() }
    table.insert(History.DB().entries, 1, entry)
    History.Trim()
  end
  if sender and not entry.by then entry.by = sender end
  if mode and not entry.mode then entry.mode = mode end
  return entry
end

-------------------------------------------------------------------------------
-- What a collection held
-------------------------------------------------------------------------------
local function Bump(tbl, key)
  tbl[key] = (tbl[key] or 0) + 1
end

-- Contents(snapshot, bytes, parts): a pull's payload table summed up
function History.Contents(snapshot, bytes, parts)
  local out = { findings = 0, kinds = {}, types = {}, stamps = 0, notes = 0, noteKinds = {}, bytes = bytes, parts = parts }
  snapshot = type(snapshot) == "table" and snapshot or {}
  for _, record in pairs(snapshot.records or {}) do
    out.findings = out.findings + 1
    if type(record) == "table" then
      Bump(out.kinds, tostring(record.kind))
      Bump(out.types, Curator.Decode.Fact(record.fact).type)
    end
  end
  for _ in pairs(snapshot.confirms or {}) do out.stamps = out.stamps + 1 end
  for _, note in pairs(snapshot.notes or {}) do
    out.notes = out.notes + 1
    if type(note) == "table" then Bump(out.noteKinds, tostring(note.kind)) end
  end
  local versions = type(snapshot.versions) == "table" and snapshot.versions or {}
  out.frozen = snapshot.frozen == true
  out.data, out.format = versions.data, versions.format
  return out
end

-------------------------------------------------------------------------------
-- Sharing's steps
-------------------------------------------------------------------------------
-- Asked(request, sender, mode, info): a request arrived and will start, or
-- waits for the curator's answer (info.prompt), info.localOnly for a pull
-- that stays on this client
function History.Asked(request, sender, mode, info)
  local entry = Entry(request, sender, mode)
  info = info or {}
  entry.state, entry.why = "asked", nil
  entry.prompt = info.prompt == true or nil
  entry.localOnly = info.localOnly == true or nil
  entry.asked = entry.asked or Now()
  return entry
end

-- Started(request, sender, mode, snapshot, bytes, parts, localOnly): the S went out
function History.Started(request, sender, mode, snapshot, bytes, parts, localOnly)
  local entry = Entry(request, sender, mode)
  entry.state, entry.why, entry.started = "sending", nil, Now()
  entry.localOnly = localOnly == true or entry.localOnly
  entry.contents = History.Contents(snapshot, bytes, parts)
  History.Trim()
  return entry
end

-- Refused(request, reason, sender, mode): the S refused it (not kept for "off")
function History.Refused(request, reason, sender, mode)
  if reason == "off" then return nil end
  local entry = Entry(request, sender, mode)
  entry.state, entry.why, entry.ended = "refused", tostring(reason), Now()
  return entry
end

-- A step on an entry that exists: its new state, when, and why
local function Step(request, state, field, why)
  local entry = Find(request)
  if not entry then return nil end
  entry.state, entry.why = state, why
  entry[field] = Now()
  return entry
end

function History.Acknowledged(request) return Step(request, "acknowledged", "ack") end
function History.Saved(request)
  local entry = Find(request)
  if not entry or entry.state == "saved" then return nil end
  local d, c = History.DB().delivered, type(entry.contents) == "table" and entry.contents or {}
  d.collections = d.collections + 1
  d.findings = d.findings + (tonumber(c.findings) or 0)
  d.stamps = d.stamps + (tonumber(c.stamps) or 0)
  d.notes = d.notes + (tonumber(c.notes) or 0)
  return Step(request, "saved", "saved")
end
-- Kept(request): the author kept it only as a lead (never delivered counts)
function History.Kept(request)
  local entry = Find(request)
  if not entry or entry.state == "saved" then return nil end
  return Step(request, "kept", "saved")
end
-- Rejected(request): the author turned it down for good
function History.Rejected(request)
  local entry = Find(request)
  if not entry or entry.state == "saved" then return nil end
  return Step(request, "rejected", "ended")
end
function History.Lost(request)
  local entry = Find(request)
  if not entry or entry.state == "saved" then return nil end
  return Step(request, "lost", "ended")
end
-- by: "you" or "author"
function History.Cancelled(request, by) return Step(request, "cancelled", "ended", by) end
function History.Replaced(request) return Step(request, "replaced", "ended") end

-- Interrupt(running): an entry still asked or sending that isn't the running
-- request stopped with the session (a /reload, the game closed); login calls
-- it with nothing running
function History.Interrupt(running)
  local changed = 0
  for _, entry in ipairs(History.DB().entries) do
    if (entry.state == "sending" or (entry.state == "asked" and not entry.prompt)) and entry.request ~= running then
      entry.state, entry.ended = "interrupted", entry.ended or Now()
      changed = changed + 1
    end
  end
  return changed
end

-- Expire(): a prompt not answered in time, a request that never started
-- (its start is a frame later, and dropped when curator mode was toggled in
-- between), and an acknowledged collection with no V within AWAITING_DAYS
-- (its findings were sent again)
History.START_WITHIN = 60   -- seconds a request may wait for its start
function History.Expire()
  local now = Now()
  local promptFor = Curator.Sharing and Curator.Sharing.PROMPT_EXPIRES or 1800
  local awaitFor = Curator.Const.AWAITING_DAYS * DAY
  for _, entry in ipairs(History.DB().entries) do
    if entry.state == "asked" and entry.prompt and now - (entry.asked or now) > promptFor then
      entry.state, entry.why, entry.ended = "expired", "prompt", now
    elseif entry.state == "asked" and not entry.prompt and now - (entry.asked or now) > History.START_WITHIN then
      entry.state, entry.ended = "interrupted", now
    elseif entry.state == "acknowledged" and now - (entry.ack or now) > awaitFor then
      entry.state, entry.why, entry.ended = "expired", "noanswer", now
    end
  end
end

-- Entries(): the entries, newest first, with expiries applied
function History.Entries()
  History.Expire()
  return History.DB().entries
end

-- Since(): when the history began
function History.Since()
  return History.DB().since
end

-- Clear(): every entry goes (opting out with "delete my findings"); the
-- history begins again from now
function History.Clear()
  local db = Curator.Store.DB()
  db.history = { entries = {}, since = Now() }
end

Host.OnLoaded(function()
  if not Curator.Main.Available() then return end   -- dormant outside the author's region
  -- nothing runs across a reload: what was mid-way stopped with the session
  local ok, err = pcall(History.Interrupt, nil)
  if not ok then Host.Log("Curator history check failed: %s", tostring(err)) end
end)
