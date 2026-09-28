-------------------------------------------------------------------------------
-- Curator.Notes: what a curator writes or runs into, as opposed to what the
-- recorders observe (curator spec D35, Cobanyte 2026-09-27): a flag on an
-- item (a reason and, if they like, their own words), general feedback
-- (/rec feedback), and the Recollect errors the game showed on this client.
--
-- RECOLLECT_CURATOR_DB.notes (in the store's table, so Store.Swap covers it):
--   flags[itemID] = { entries }   one list per item, oldest first
--   feedback = { entries }, errors = { entries }
--   awaiting[request] = { at, keys = { [key] = true } }   notes a pull carried,
--                                  acknowledged with K, waiting for V
--   nextN                          one counter for every note of the account
-- An entry: { n, of, rev, reason, text, stack, count, data, addon, build,
-- at, state, request }; rev rises with every edit, so a K for a snapshot
-- taken before an edit leaves the edited entry pending. n is never reused, so a note's key is unique for good:
-- "f:<item>:<n>", "fb:<n>", "e:<n>". of is the n of the flag's first entry
-- (a flag's later entries are more information about it; feedback and
-- errors are their own). data and addon are the data and addon versions it
-- was written under, build the game build, at the server time.
--
-- State: "pending" (not sent yet), "sent" (in a pull the author acknowledged,
-- waiting for V), "delivered" (V said the author's copy is saved). A pending
-- entry can be edited or withdrawn; a sent or delivered one never changes,
-- and a flag saved again after that gets a new entry. A lost V, or no V for
-- AWAITING_DAYS, makes the entries pending again.
--
-- Notes are not recorder findings: they are outside the 1 MB cap and never
-- evicted (a person wrote them; a delivered flag counts toward the flagged
-- items' limit until the next database clears it), and a new database (D14) clears only what
-- the author already has: every flag whose entries are all delivered, and
-- delivered feedback and errors. Anything else stays, each entry keeping the
-- data version it was written under, so the author sees it was "flagged
-- under an older database version". The limits refuse instead of evicting.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host

local Notes = {}
Curator.Notes = Notes

local DAY = 86400

Notes.LIMITS = {
  FLAGGED_ITEMS = 300,   -- items with a flag
  FLAG_ENTRIES = 20,     -- entries on one item's flag
  FEEDBACK = 100,        -- feedback entries
  ERRORS = 50,           -- distinct errors
  FLAG_TEXT = 500,
  FEEDBACK_TEXT = 1000,
  ERROR_TEXT = 500,
  STACK_TEXT = 1500,
}

-- Why an item is flagged, in the dialog's order; "other" needs words
Notes.REASONS = {
  { key = "missing", label = "Missing info" },
  { key = "wrong", label = "Incorrect info" },
  { key = "source", label = "Wrong place or source" },
  { key = "price", label = "Wrong price or cost" },
  { key = "gone", label = "Can no longer be obtained" },
  { key = "verdict", label = "The verdict looks wrong" },
  { key = "other", label = "Something else" },
}
Notes.REASON_LABELS = {}
for _, reason in ipairs(Notes.REASONS) do Notes.REASON_LABELS[reason.key] = reason.label end

Notes.seams = {
  Now = function() return GetServerTime() end,
  Build = function() return select(2, GetBuildInfo()) end,
}

local function Now()
  local ok, now = pcall(Notes.seams.Now)
  return ok and tonumber(now) or 0
end

-- The notes table in the store in use, made valid
function Notes.DB()
  local db = Curator.Store.DB()
  local notes = type(db.notes) == "table" and db.notes or {}
  db.notes = notes
  for _, field in ipairs({ "flags", "feedback", "errors", "awaiting" }) do
    if type(notes[field]) ~= "table" then notes[field] = {} end
  end
  if type(notes.nextN) ~= "number" then notes.nextN = 1 end
  return notes
end

local function Changed()
  if Host.NotesChanged then pcall(Host.NotesChanged) end
end

local function Stamp(entry)
  entry.rev = (entry.rev or 0) + 1
  local versions = Host.Versions()
  local ok, build = pcall(Notes.seams.Build)
  entry.data, entry.addon = tostring(versions.data), tostring(versions.addon)
  entry.build, entry.at = ok and tostring(build) or "?", Now()
  return entry
end

local function NewEntry(notes, fields)
  local entry = fields
  entry.n = notes.nextN
  entry.of = entry.of or entry.n
  entry.state = "pending"
  notes.nextN = notes.nextN + 1
  return Stamp(entry)
end

-------------------------------------------------------------------------------
-- Text
-------------------------------------------------------------------------------
-- CleanText(text, limit): the player's words as they travel: color codes,
-- textures and atlases gone, a link reduced to its text, control characters
-- other than line breaks dropped, runs of blank lines folded, trimmed, then
-- cut to limit characters (never inside a character)
function Notes.CleanText(text, limit)
  if type(text) ~= "string" or Host.IsSecret(text) then return "" end
  local s = CobySuite_Recollect.Utilities.StripColors(text)
  s = s:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", "")
  s = s:gsub("||", "|"):gsub("|", "")
  s = s:gsub("\r\n?", "\n"):gsub("[%z\1-\9\11-\31\127]", "")
  s = s:gsub("[ \t]+\n", "\n"):gsub("\n\n\n+", "\n\n")
  s = s:match("^%s*(.-)%s*$") or ""
  if limit and CobySuite_Recollect.Utilities.Utf8Length(s) > limit then
    s = CobySuite_Recollect.Utilities.Truncate(s, limit, "")
  end
  return s
end

local function Copy(entry)
  local out = {}
  for k, v in pairs(entry) do out[k] = v end
  return out
end

local function Copies(entries)
  local out = {}
  for i, entry in ipairs(entries or {}) do out[i] = Copy(entry) end
  return out
end

-------------------------------------------------------------------------------
-- Flags
-------------------------------------------------------------------------------
local function FlaggedCount(notes)
  local n = 0
  for _, flag in pairs(notes.flags) do
    if #flag.entries > 0 then n = n + 1 end
  end
  return n
end

-- Flag(itemID): { entries = <copies, oldest first>, pending (the last entry
-- when it is still pending), atLimit (no new entry can be added) }
function Notes.Flag(itemID)
  local notes = Notes.DB()
  local flag = notes.flags[itemID]
  local entries = flag and flag.entries or {}
  local last = entries[#entries]
  local pending = last and last.state == "pending" and Copy(last) or nil
  local atLimit
  if pending then
    atLimit = false
  elseif #entries > 0 then
    atLimit = #entries >= Notes.LIMITS.FLAG_ENTRIES
  else
    atLimit = FlaggedCount(notes) >= Notes.LIMITS.FLAGGED_ITEMS
  end
  return { entries = Copies(entries), pending = pending, atLimit = atLimit }
end

-- Check(reason, text): the cleaned text, or nil and why the note can't be saved
function Notes.CheckFlag(reason, text)
  if not Notes.REASON_LABELS[reason] then return nil, "Choose a reason." end
  local clean = Notes.CleanText(text, Notes.LIMITS.FLAG_TEXT)
  if reason == "other" and clean == "" then return nil, "Say what's wrong: \"Something else\" needs a few words." end
  return clean
end

-- SaveFlag(itemID, reason, text): the item's pending entry is replaced (an
-- edit before any pull), else a new entry is added (the first flag, or more
-- information about one already sent). Returns the entry's copy, or nil and why.
function Notes.SaveFlag(itemID, reason, text)
  itemID = tonumber(itemID)
  if not itemID or itemID <= 0 then return nil, "No item to flag." end
  local clean, why = Notes.CheckFlag(reason, text)
  if not clean then return nil, why end
  local notes = Notes.DB()
  local flag = notes.flags[itemID]
  local entries = flag and flag.entries or {}
  local last = entries[#entries]
  if last and last.state == "pending" then
    last.reason, last.text = reason, clean
    Stamp(last)
    Changed()
    return Copy(last)
  end
  local state = Notes.Flag(itemID)
  if state.atLimit then
    return nil, #entries > 0 and "This flag has as much information as it can hold until the author collects it."
      or ("You have %d flags waiting to be collected, the most Recollect keeps."):format(Notes.LIMITS.FLAGGED_ITEMS)
  end
  notes.flags[itemID] = flag or { entries = entries }
  local first = entries[1]
  local entry = NewEntry(notes, { reason = reason, text = clean, of = first and first.n or nil })
  entries[#entries + 1] = entry
  Changed()
  return Copy(entry)
end

-- RemovePendingFlag(itemID): withdraws the item's unsent entry; true when one was
function Notes.RemovePendingFlag(itemID)
  local notes = Notes.DB()
  local flag = notes.flags[tonumber(itemID) or 0]
  local last = flag and flag.entries[#flag.entries]
  if not (last and last.state == "pending") then return false end
  flag.entries[#flag.entries] = nil
  if #flag.entries == 0 then notes.flags[tonumber(itemID)] = nil end
  Changed()
  return true
end

-------------------------------------------------------------------------------
-- Feedback
-------------------------------------------------------------------------------
-- Feedback(): { entries = <copies>, pending (the unsent entry), atLimit }
function Notes.Feedback()
  local notes = Notes.DB()
  local last = notes.feedback[#notes.feedback]
  local pending = last and last.state == "pending" and Copy(last) or nil
  return { entries = Copies(notes.feedback), pending = pending,
    atLimit = not pending and #notes.feedback >= Notes.LIMITS.FEEDBACK }
end

-- SaveFeedback(text): replaces the unsent entry, else adds one. Returns the
-- entry's copy, or nil and why
function Notes.SaveFeedback(text)
  local clean = Notes.CleanText(text, Notes.LIMITS.FEEDBACK_TEXT)
  if clean == "" then return nil, "Write something first." end
  local notes = Notes.DB()
  local last = notes.feedback[#notes.feedback]
  if last and last.state == "pending" then
    last.text = clean
    Stamp(last)
    Changed()
    return Copy(last)
  end
  if #notes.feedback >= Notes.LIMITS.FEEDBACK then
    return nil, ("You have %d pieces of feedback waiting to be collected, the most Recollect keeps."):format(Notes.LIMITS.FEEDBACK)
  end
  local entry = NewEntry(notes, { text = clean })
  notes.feedback[#notes.feedback + 1] = entry
  Changed()
  return Copy(entry)
end

function Notes.RemovePendingFeedback()
  local notes = Notes.DB()
  local last = notes.feedback[#notes.feedback]
  if not (last and last.state == "pending") then return false end
  notes.feedback[#notes.feedback] = nil
  Changed()
  return true
end

-------------------------------------------------------------------------------
-- Errors
-------------------------------------------------------------------------------
-- RecordError(message, stack): one entry per distinct error until it is
-- sent (the same message and stack again counts), then a new one. It fires
-- no change event: nothing shows errors, and a listener that errored would
-- bring its own error straight back here. At the
-- limit the oldest delivered error makes room; with none, the new error is
-- only counted (notes.errorsDropped). Returns the entry's copy or nil.
function Notes.RecordError(message, stack)
  if type(message) ~= "string" or Host.IsSecret(message) or (stack ~= nil and Host.IsSecret(stack)) then return nil end
  local text = Notes.CleanText(message, Notes.LIMITS.ERROR_TEXT)
  if text == "" then return nil end
  local trace = Notes.CleanText(type(stack) == "string" and stack or "", Notes.LIMITS.STACK_TEXT)
  local notes = Notes.DB()
  for _, entry in ipairs(notes.errors) do
    if entry.state == "pending" and entry.text == text and entry.stack == trace then
      entry.count = (entry.count or 1) + 1
      entry.at = Now()
      entry.rev = (entry.rev or 0) + 1
      return Copy(entry)
    end
  end
  if #notes.errors >= Notes.LIMITS.ERRORS then
    local room
    for i, entry in ipairs(notes.errors) do
      if entry.state == "delivered" then room = i break end
    end
    if not room then
      notes.errorsDropped = (notes.errorsDropped or 0) + 1
      return nil
    end
    table.remove(notes.errors, room)
  end
  local entry = NewEntry(notes, { text = text, stack = trace, count = 1 })
  notes.errors[#notes.errors + 1] = entry
  return Copy(entry)
end

-------------------------------------------------------------------------------
-- Delivery
-------------------------------------------------------------------------------
-- Every entry of the store with its key and wire kind: fn(key, kind, entry, itemID)
local function Each(notes, fn)
  for itemID, flag in pairs(notes.flags) do
    for _, entry in ipairs(flag.entries) do fn(("f:%d:%d"):format(itemID, entry.n), "flag", entry, itemID) end
  end
  for _, entry in ipairs(notes.feedback) do fn("fb:" .. entry.n, "feedback", entry) end
  for _, entry in ipairs(notes.errors) do fn("e:" .. entry.n, "error", entry) end
end

-- Pending(): the unsent notes as they travel ({ [key] = { kind, item, n, of,
-- reason, text, stack, count, data, addon, build, at } }) and their
-- revisions ({ [key] = rev }, for K)
function Notes.Pending()
  local notes = Notes.DB()
  local wire, keys = {}, {}
  Each(notes, function(key, kind, entry, itemID)
    if entry.state ~= "pending" then return end
    wire[key] = { kind = kind, item = itemID, n = entry.n, of = entry.of, reason = entry.reason, text = entry.text,
      stack = entry.stack, count = entry.count, data = entry.data, addon = entry.addon, build = entry.build, at = entry.at }
    keys[key] = entry.rev
  end)
  return wire, keys
end

-- keys = { [key] = rev }: only entries still at that revision change
local function SetState(notes, keys, from, to, request)
  local changed = false
  Each(notes, function(key, _, entry)
    if keys[key] == entry.rev and (from == nil or entry.state == from) then
      entry.state, entry.request = to, request
      changed = true
    end
  end)
  return changed
end

-- Acknowledged(request, keys): K arrived for a pull that carried these notes
function Notes.Acknowledged(request, keys)
  if type(keys) ~= "table" or not next(keys) then return end
  local notes = Notes.DB()
  SetState(notes, keys, "pending", "sent", request)
  notes.awaiting[request] = { at = Now(), keys = keys }
  Changed()
end

-- Saved(request) and Lost(request): V's answer for a request that carried
-- notes; true when it named one
function Notes.Saved(request)
  local notes = Notes.DB()
  local waiting = notes.awaiting[request]
  if not waiting then return false end
  notes.awaiting[request] = nil
  SetState(notes, waiting.keys, "sent", "delivered", request)
  Changed()
  return true
end

function Notes.Lost(request)
  local notes = Notes.DB()
  local waiting = notes.awaiting[request]
  if not waiting then return false end
  notes.awaiting[request] = nil
  SetState(notes, waiting.keys, "sent", "pending", nil)
  Changed()
  return true
end

-- AwaitingIDs(): the requests still waiting for V; one waiting longer than
-- AWAITING_DAYS counts as lost, so its notes go out again
function Notes.AwaitingIDs()
  local notes = Notes.DB()
  local cutoff = Now() - Curator.Const.AWAITING_DAYS * DAY
  local out = {}
  for request, waiting in pairs(notes.awaiting) do
    if (waiting.at or 0) < cutoff then Notes.Lost(request) else out[#out + 1] = request end
  end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

-------------------------------------------------------------------------------
-- A new database, and clearing
-------------------------------------------------------------------------------
-- OnDataVersionChanged(): what the author already has goes (a flag whose
-- entries are all delivered, delivered feedback and errors); the rest stays
-- with the data version it was written under
function Notes.OnDataVersionChanged()
  local notes = Notes.DB()
  local cleared = 0
  for itemID, flag in pairs(notes.flags) do
    local all = #flag.entries > 0
    for _, entry in ipairs(flag.entries) do
      if entry.state ~= "delivered" then all = false end
    end
    if all or #flag.entries == 0 then
      notes.flags[itemID] = nil
      cleared = cleared + 1
    end
  end
  for _, field in ipairs({ "feedback", "errors" }) do
    local kept = {}
    for _, entry in ipairs(notes[field]) do
      if entry.state == "delivered" then cleared = cleared + 1 else kept[#kept + 1] = entry end
    end
    notes[field] = kept
  end
  if cleared > 0 then Changed() end
  return cleared
end

-- Clear(): every note goes (opting out with "delete my findings"); the counter stays
function Notes.Clear()
  local notes = Notes.DB()
  notes.flags, notes.feedback, notes.errors, notes.awaiting = {}, {}, {}, {}
  notes.errorsDropped = nil
  Changed()
end

-- Counts(): { flags (flagged items), feedback, errors, pending (entries not sent) }
function Notes.Counts()
  local notes = Notes.DB()
  local out = { flags = 0, feedback = #notes.feedback, errors = #notes.errors, pending = 0 }
  for _, flag in pairs(notes.flags) do
    if #flag.entries > 0 then out.flags = out.flags + 1 end
  end
  Each(notes, function(_, _, entry)
    if entry.state == "pending" then out.pending = out.pending + 1 end
  end)
  return out
end
