-------------------------------------------------------------------------------
-- Curator.Sharing: the curator's side of the conversation with the author
-- (curator spec, "Message types", "Who may send what", walkthroughs 1 to 9)
--
-- Honoured only from the author: a message addressed to this account's
-- curator ID (or "*" for the presence H), whose server-stamped sender is
-- Owner or Leader in the community (Membership), and, in test mode, sent by
-- this very character (only Cobanyte's own curator side acts on test
-- traffic, D23).
--   H  presence or challenge: answered with R whether or not curator mode is
--      on (state "off" when opted out, "nodata" when the data files failed
--      their check); a challenge's checksum is Protocol.Challenge over this
--      character's own name
--   Q  a pull: refused with S (busy, off, nodata, empty, declined) or
--      started: the pending records and stamps with the contexts and quest
--      entries they name are packed, the S announces the chunk count,
--      size and checksum, and the D chunks follow at the adaptive rate. A
--      new Q replaces a transfer only waiting for its K. With "Ask me
--      before each collection" on, a prompt comes first (D4): a window when
--      resting and out of combat, else a chat line with [Review request];
--      it expires after 30 minutes.
--   N  resend the listed chunks; K  the author verified the payload: its
--      revisions count as delivered and wait for V (Store.Acknowledged);
--   V  saved or lost requests (Store.Saved / Store.Lost, and Notes.Saved /
--      Notes.Lost for the notes a pull carried), only for requests waiting
--      for it; X  cancel.
-- A pull carries the curator's notes not sent yet (flags, feedback, errors)
-- beside the findings, so a store holding only notes is not "empty".
-- The curator also sends O once a session when it is a member with curator
-- mode on, and L when it opts out. Nothing here deletes a record: only V.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Protocol = Curator.Protocol
local Transport = Curator.Transport
local Membership = Curator.Membership

local Sharing = {}
Curator.Sharing = Sharing

Sharing.PROMPT_EXPIRES = 30 * 60
Sharing.LINK = "addon:RecollectCurator:review"

local transfer = nil   -- { request, mode, sender, pending, payload, chunks, checksum, sent, waitingK }
local prompt = nil     -- { request, mode, sender, override, at }

local function CuratorID()
  return Curator.Main.CuratorID()
end

-- The last message this client left unanswered from someone who might be
-- the author, and why ({ kind, sender, why, at }), for /rec curator diag
Sharing.lastDropped = nil

local function Dropped(msg, why)
  Sharing.lastDropped = { kind = msg.kind, sender = msg.sender, why = why, at = GetServerTime() }
  Host.Log("Curator did not answer %s from %s: %s", tostring(msg.kind), tostring(msg.sender), why)
  return false
end

-- Whether a message counts as the author's, and is for this account
local function FromAuthor(msg)
  local toMe = msg.to == CuratorID() or (msg.to == Protocol.ALL and msg.kind == "H")
  if not toMe then return false end   -- another curator's: nothing to say about it
  if not Membership.MayPull(msg.sender) then
    local role = Membership.RoleOf(msg.sender)
    if role == nil then
      -- the roster may not have had their name yet: read it again for the next message
      if Membership.RefreshSoon then Membership.RefreshSoon() end
      return Dropped(msg, "the sender isn't in this character's list of community members yet (it's read again now)")
    end
    return Dropped(msg, ("the sender is a %s here, and only the Owner or a Leader can collect"):format(
      Membership.ROLE_NAMES[role] or "member"))
  end
  if msg.mode == Protocol.TEST and not msg.self then return Dropped(msg, "a test message from another character") end
  if msg.kind == "H" then Sharing.lastHello = { sender = msg.sender, at = GetServerTime() } end
  -- the author's character is known now: what goes to the author is whispered to it
  Transport.Route(Protocol.AUTHOR, msg.sender)
  return true
end
Sharing.FromAuthor = FromAuthor

-- "on", "ask", "off" or "nodata"
function Sharing.State()
  if not Curator.Main.IsEnabled() then return "off" end
  if Host.Versions().ok ~= true then return "nodata" end
  if Curator.Config.Get("curator_ask") == true then return "ask" end
  return "on"
end

local function Send(kind, mode, ...)
  return Transport.Send(kind, mode, Protocol.AUTHOR, ...)
end

-- A message of a pull: handed over locally when the author is this very
-- character (Transport.IsLocalPull), else sent on the channel
local function SendFor(localOnly, kind, mode, ...)
  if localOnly then return Transport.SendLocal(kind, mode, Protocol.AUTHOR, ...) end
  return Send(kind, mode, ...)
end

-------------------------------------------------------------------------------
-- H and R
-------------------------------------------------------------------------------
function Sharing.OnHello(msg)
  if not FromAuthor(msg) then return end
  local f = msg.fields
  local state = Sharing.State()
  local checksum = ""
  if f[3] ~= "" and state ~= "nodata" then
    checksum = Protocol.Challenge(f[3], f[4], f[5], f[6], Transport.Self()) or ""
  end
  local versions = Host.Versions()
  local counts = Curator.Store.Counts()
  Host.Log("Curator answering the presence check from %s: state %s, %d findings and %d notes pending, %s", msg.sender,
    state, counts.pending, Curator.Notes.Counts().pending, f[3] ~= "" and "with the installation check" or "presence only")
  Send("R", msg.mode, f[1], CuratorID(), versions.addon, versions.data, versions.format, Protocol.VERSION,
    checksum, state, Transport.Activity(), counts.pending + Curator.Notes.Counts().pending, counts.pendingBytes,
    Protocol.List(Sharing.AwaitingIDs()))
end

-- The requests waiting for V: the store's and the notes' (which keep their
-- own, since a new database empties the store's), each once
function Sharing.AwaitingIDs()
  local seen, out = {}, {}
  for _, list in ipairs({ Curator.Store.AwaitingIDs(), Curator.Notes.AwaitingIDs() }) do
    for _, request in ipairs(list) do
      if not seen[request] then
        seen[request] = true
        out[#out + 1] = request
      end
    end
  end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

-------------------------------------------------------------------------------
-- The snapshot
-------------------------------------------------------------------------------
local function Copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = Copy(v) end
  return out
end

local function AddQuest(db, out, index)
  local entry = db.quests[index]
  if not entry or out.quests[index] then return end
  local copy = { char = entry.char, at = entry.at, kind = entry.kind, base = entry.base, data = entry.data }
  if entry.kind == "base" then copy.data = Curator.Context.BaseText(entry) end
  out.quests[index] = copy
  if entry.kind == "delta" and entry.base then AddQuest(db, out, entry.base) end
end

-- Snapshot(): the payload table (the intake shape's fields) and the
-- revisions it holds (Store.Pending's shape, for K)
function Sharing.Snapshot()
  local db = Curator.Store.DB()
  local pending = Curator.Store.Pending()
  local versions = Host.Versions()
  local out = { protocol = Protocol.VERSION, curator = CuratorID(), records = {}, confirms = {}, contexts = {}, quests = {},
    versions = { addon = versions.addon, data = versions.data, format = versions.format, protocol = Protocol.VERSION } }
  local used = {}
  for id in pairs(pending.recs) do
    local record = db.records[id]
    out.records[id] = Copy(record)
    for index in pairs(record.ctx or {}) do used[index] = true end
    for _, variant in pairs(record.variants or {}) do
      if type(variant.quests) == "number" then AddQuest(db, out, variant.quests) end
    end
  end
  for key in pairs(pending.confirms) do
    out.confirms[key] = Copy(db.confirms[key])
    for index in pairs(db.confirms[key].ctx or {}) do used[index] = true end
  end
  for index in pairs(used) do out.contexts[index] = Copy(db.contexts[index]) end
  -- the notes not sent yet (flags, feedback, errors: Curator.Notes)
  out.notes, pending.notes = Curator.Notes.Pending()
  return out, pending
end

local Count = CobySuite_Recollect.Utilities.TableCount

-------------------------------------------------------------------------------
-- A pull
-------------------------------------------------------------------------------
local function Refuse(request, mode, reason, localOnly)
  Host.Log("Curator collection %s refused: %s", tostring(request), tostring(reason))
  SendFor(localOnly, "S", mode, request, 0, 0, "", "refused:" .. reason)
end

local function SendChunk(seq)
  if not transfer or not transfer.chunks[seq] then return end
  local current = transfer
  local text = Protocol.Encode("D", current.mode, Protocol.AUTHOR, current.request, seq, current.chunks[seq])
  local function OnSent()
    if transfer ~= current then return end
    current.sent = current.sent + 1
    if current.sent >= #current.chunks then current.waitingK = true end
    if Sharing.OnChanged then pcall(Sharing.OnChanged) end
  end
  if current.localOnly then
    Transport.EnqueueLocal(text, OnSent)
  else
    Transport.Enqueue(text, current.request, OnSent)
  end
end

-- Starts sending a pull's collection (in a later frame: packing a big
-- store is the costliest step); localOnly: the author is this very
-- character, so nothing goes over the channel
function Sharing.Start(request, mode, sender, localOnly)
  local snapshot, pending = Sharing.Snapshot()
  if not next(snapshot.records) and not next(snapshot.confirms) and not next(snapshot.notes) then
    Refuse(request, mode, "empty", localOnly)
    return false
  end
  local payload, why = Protocol.Pack(snapshot)
  if not payload then
    Refuse(request, mode, why or "pack", localOnly)
    return false
  end
  transfer = { request = request, mode = mode, sender = sender, pending = pending, payload = payload,
    chunks = Protocol.Chunks(payload, request), checksum = Protocol.Checksum(payload), sent = 0, localOnly = localOnly }
  Host.Log("Curator collection %s for %s: %d findings, %d stamps, %d notes, %d bytes in %d parts%s", tostring(request),
    tostring(sender), Count(snapshot.records), Count(snapshot.confirms), Count(snapshot.notes), #payload, #transfer.chunks,
    localOnly and " (on this client)" or "")
  SendFor(localOnly, "S", mode, request, #transfer.chunks, #payload, transfer.checksum,
    ("records:%d,confirms:%d,notes:%d"):format(Count(snapshot.records), Count(snapshot.confirms), Count(snapshot.notes)))
  for seq = 1, #transfer.chunks do SendChunk(seq) end
  if mode == Protocol.LIVE and not localOnly then
    Host.Print(("Recollect: sending curator findings (%d KB). /rec curator to watch or cancel."):format(
      math.max(1, math.ceil(#payload / 1024))))
  end
  if Sharing.OnChanged then pcall(Sharing.OnChanged) end
  return true
end

function Sharing.OnRequest(msg)
  if not FromAuthor(msg) or msg.to == Protocol.ALL then return end
  local request, override = msg.fields[1], msg.fields[2]
  if request == "" then return end
  local localOnly = Transport.IsLocalPull(msg.mode, msg.sender)
  if transfer and not transfer.waitingK then
    Refuse(request, msg.mode, "busy", localOnly)
    return
  end
  if transfer then
    Transport.Drop(transfer.request)
    transfer = nil
  end
  local state = Sharing.State()
  if state == "off" or state == "nodata" then
    Refuse(request, msg.mode, state, localOnly)
    return
  end
  Host.Log("Curator collection %s requested by %s (%s)", tostring(request), tostring(msg.sender), state)
  if state == "ask" then
    prompt = { request = request, mode = msg.mode, sender = msg.sender, override = override, at = GetServerTime(),
      localOnly = localOnly }
    if Sharing.OnPrompt then pcall(Sharing.OnPrompt, prompt) end
    return
  end
  Curator.Main.Defer(function() Sharing.Start(request, msg.mode, msg.sender, localOnly) end)
end

-- The prompt's answer (D4); an expired prompt does nothing
function Sharing.AnswerPrompt(allow)
  local asked = prompt
  prompt = nil
  if not asked or GetServerTime() - asked.at > Sharing.PROMPT_EXPIRES then return false end
  if allow then
    Curator.Main.Defer(function() Sharing.Start(asked.request, asked.mode, asked.sender, asked.localOnly) end)
  else
    Refuse(asked.request, asked.mode, "declined", asked.localOnly)
  end
  if Sharing.OnChanged then pcall(Sharing.OnChanged) end
  return true
end

function Sharing.Prompt()
  if prompt and GetServerTime() - prompt.at > Sharing.PROMPT_EXPIRES then prompt = nil end
  return prompt
end

function Sharing.OnResend(msg)
  if not FromAuthor(msg) or not transfer or msg.fields[1] ~= transfer.request then return end
  for _, seq in ipairs(Protocol.ParseList(msg.fields[2])) do SendChunk(tonumber(seq)) end
end

function Sharing.OnAcknowledge(msg)
  if not FromAuthor(msg) or not transfer or msg.fields[1] ~= transfer.request then return end
  if msg.fields[2] ~= transfer.checksum then
    Host.Log("Curator acknowledgement for %s ignored: its checksum doesn't match", tostring(transfer.request))
    return
  end
  Host.Log("Curator collection %s acknowledged: the author has it", tostring(transfer.request))
  Curator.Store.Acknowledged(transfer.request, transfer.pending)
  Curator.Notes.Acknowledged(transfer.request, transfer.pending.notes)
  local mode = transfer.mode
  transfer = nil
  if mode == Protocol.LIVE then Host.Print("Recollect: curator findings delivered. Thank you.") end
  if Sharing.OnChanged then pcall(Sharing.OnChanged) end
end

-- V: the requests the author's copy holds, and the ones it lost; any other
-- request ID is ignored
function Sharing.OnSaved(msg)
  if not FromAuthor(msg) or msg.to == Protocol.ALL then return end
  local db = Curator.Store.DB()
  Host.Log("Curator saved report from %s: saved %s; lost %s", tostring(msg.sender), tostring(msg.fields[1]), tostring(msg.fields[2]))
  for _, request in ipairs(Protocol.ParseList(msg.fields[1])) do
    if db.awaiting[request] then Curator.Store.Saved(request) end
    Curator.Notes.Saved(request)
  end
  for _, request in ipairs(Protocol.ParseList(msg.fields[2])) do
    if db.awaiting[request] then Curator.Store.Lost(request) end
    Curator.Notes.Lost(request)
  end
end

local function Stop(printed)
  if not transfer then return end
  Transport.Drop(transfer.request)
  local mode = transfer.mode
  transfer = nil
  if printed and mode == Protocol.LIVE then Host.Print("Recollect: curator collection cancelled. Nothing was deleted.") end
  if Sharing.OnChanged then pcall(Sharing.OnChanged) end
end

function Sharing.OnCancel(msg)
  if not FromAuthor(msg) or not transfer or msg.fields[1] ~= transfer.request then return end
  Stop(true)
end

-- Cancel(): the curator stops the transfer (the transfer window, /rec curator cancel)
function Sharing.Cancel()
  if not transfer then return false end
  SendFor(transfer.localOnly, "X", transfer.mode, transfer.request, "cancelled")
  Stop(true)
  return true
end

-- Status(): { request, sent, total, bytes, waitingK, paused } or nil
function Sharing.Status()
  if not transfer then return nil end
  return { request = transfer.request, sent = transfer.sent, total = #transfer.chunks, bytes = #transfer.payload,
    waitingK = transfer.waitingK == true, paused = Transport.IsPaused() }
end

-------------------------------------------------------------------------------
-- O, L and the login line
-------------------------------------------------------------------------------
function Sharing.Announce()
  if not Curator.Main.IsEnabled() or not Transport.IsMember() then return false end
  local versions = Host.Versions()
  return Send("O", Protocol.LIVE, CuratorID(), versions.addon, versions.data, versions.format, Protocol.VERSION)
end

function Sharing.SendLeaving()
  if not Transport.IsMember() then return false end
  return Send("L", Protocol.LIVE, CuratorID())
end

-- D27: once per character with curator mode on, a line saying findings go
-- out from characters in the community
function Sharing.LoginNotice(guid)
  if not Curator.Main.IsEnabled() or type(guid) ~= "string" then return false end
  local db = Curator.Main.DB()
  db.told = type(db.told) == "table" and db.told or {}
  if db.told[guid] then return false end
  db.told[guid] = true
  if Transport.IsMember() then return false end
  Host.Print("Recollect is recording curator findings on this character. They're sent from characters that have "
    .. "joined the Recollect Curators community: type /rec curator join to join on this one.")
  return true
end

-------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------
-- A stale K arriving after a new transfer began carries another request ID,
-- and each handler checks it
Transport.On("H", Sharing.OnHello)
Transport.On("Q", Sharing.OnRequest)
Transport.On("N", Sharing.OnResend)
Transport.On("K", Sharing.OnAcknowledge)
Transport.On("V", Sharing.OnSaved)
Transport.On("X", Sharing.OnCancel)

-- [Review request] in chat opens the prompt
if EventRegistry and EventRegistry.RegisterCallback then
  EventRegistry:RegisterCallback("SetItemRef", function(_, link)
    if link == Sharing.LINK and Sharing.OnPromptLink then pcall(Sharing.OnPromptLink) end
  end, Sharing)
end

-- The channel watch (Transport.CheckChannel): a curator, or the author,
-- whose character is in the community but couldn't join the hidden channel
-- hears it once, and once when it is back
Sharing.CHANNEL_MISSING = "Recollect curator mode couldn't join its hidden channel on this character, so the author "
  .. "can't reach it. Every chat channel slot may be in use: leave one, then type /rec curator channel."
Sharing.CHANNEL_BACK = "Recollect: the hidden curator channel is joined; curator mode can send and receive again."

local wasMissing = false
function Sharing.OnChannelChanged(state)
  local concerned = Curator.Main.IsEnabled() or Membership.MayPull(Transport.Self())
  if state == "missing" then
    wasMissing = true
    if concerned then Host.Print(Sharing.CHANNEL_MISSING) end
  elseif state == "ok" and wasMissing then
    wasMissing = false
    if concerned then Host.Print(Sharing.CHANNEL_BACK) end
  end
end
Transport.OnChannelChanged = function(state) Sharing.OnChannelChanged(state) end

local announced = false
local frame = CreateFrame("Frame")
pcall(frame.RegisterEvent, frame, "PLAYER_ENTERING_WORLD")
pcall(frame.RegisterEvent, frame, "CLUB_ADDED")
frame:SetScript("OnEvent", function(_, event)
  if event == "CLUB_ADDED" then announced = false end
  if announced then return end
  C_Timer.After(10, function()
    if announced then return end
    local ok = pcall(function()
      announced = Sharing.Announce() == true
      Sharing.LoginNotice(UnitGUID("player"))
    end)
    if not ok then Host.Log("Curator login notice failed") end
  end)
end)

-------------------------------------------------------------------------------
-- Tests: _test.Swap(state) puts state in place of the transfer, the prompt
-- and the channel-missing note (none when state is nil) and returns what it
-- replaced (the loopback's set-aside, as Transport._test.Swap)
-------------------------------------------------------------------------------
Sharing._test = {}
function Sharing._test.Swap(state)
  local old = { transfer = transfer, prompt = prompt, wasMissing = wasMissing }
  state = state or { wasMissing = false }
  transfer, prompt, wasMissing = state.transfer, state.prompt, state.wasMissing
  return old
end
