-------------------------------------------------------------------------------
-- Curator.Transport: the community channel, the send queue and the
-- receiver (curator spec, "Channel and addressing", "Adaptive rate")
--
-- The channel: the community named Const.CLUB_NAME (or Const.CLUB_ID once
-- known), its stream named Const.STREAM_NAME (General: people chat there
-- and the curator traffic, addon messages, never shows), and that stream's
-- chat channel, "Community:<clubId>:<streamId>", looked up by name before
-- each send (its index moves). Blizzard adds General to chat only for a
-- join with the Communities window open (CommunitiesFrame.lua), so the
-- addon adds it once when this character joins the community (CLUB_ADDED);
-- otherwise a missing channel means the player left it, and the addon never
-- adds it back by itself. The channel watch (CheckChannel, on login and on channel and club
-- changes) tells OnChannelChanged when a member's channel goes missing
-- (after a second look CONFIRM seconds later) or comes back;
-- AddChannel(), for /rec curator channel, puts it back
-- (C_Club.AddClubStreamChatChannel is not restricted).
--
-- The queue: one message at a time, spaced by the adaptive rate (counted
-- from the last send, even when the queue had emptied since): about 1
-- message a second at full rate, of which curator traffic uses 50% idle or
-- resting, 35% moving and 20% in combat (a secret speed counts as combat),
-- so other addons keep room. AddonMessageThrottle or ChannelThrottle halves
-- the rate and waits 5 seconds before recovering (the message is sent
-- again; a receiver drops duplicate sequence numbers). AddOnMessageLockdown
-- pauses the queue until ADDON_RESTRICTION_STATE_CHANGED shows the Chat
-- restriction gone, or, when the restriction reads off (the game refused
-- with no restriction change; seen in game 2026-09-26), until BACKOFF has
-- passed. Sends are scheduled with C_Timer, never OnUpdate.
--
-- The receiver: every CHAT_MSG_ADDON argument is checked for secrets before
-- any match; a secret argument drops the message. Messages with the prefix
-- are decoded (Protocol.Decode) and handed to every handler of their type
-- (the curator side, and the author's console in development builds), with
-- the server-stamped sender in canonical "Name-Realm" form. The game never
-- returns a sender's own channel message (Step 1 T14), so LOCAL_ECHO hands
-- each message sent to this client's own handlers and drops a server copy.
-- Tally() says what went out and came back; OnSent(text, result, locally),
-- when set (the console's activity log in development builds), hears every
-- send with its result code.
--
-- Client calls go through Transport.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Protocol = Curator.Protocol

local Transport = {}
Curator.Transport = Transport

Transport.FULL_RATE = 1          -- messages a second the channel allows (Step 1 T4 measures it)
Transport.BUDGET = { idle = 0.5, moving = 0.35, combat = 0.2 }
Transport.BACKOFF = 5             -- seconds after a throttle before the rate recovers
-- The game doesn't hand a sender its own community channel message (Step 1
-- T14, in game 2026-09-26), so every message sent is also given to this
-- client's own receiver a frame later, and a copy the server does return is
-- dropped: each message is handled once either way (spec, T14's fallback)
Transport.LOCAL_ECHO = true
-- A live pull between this client's author and curator sides (the author
-- pulling their own findings) never needs the channel: SendLocal and
-- EnqueueLocal hand its messages to this client's own receiver a frame
-- later, so it takes a moment instead of minutes at the channel's rate.
-- Test-mode pulls keep the channel (the channel suites exercise it).
Transport.LOCAL_SELF = true

local RESULT = { SUCCESS = 0, THROTTLE = 3, CHANNEL_THROTTLE = 8, LOCKDOWN = 11 }
Transport.RESULT = RESULT

Transport.seams = {
  Register = function(prefix) return C_ChatInfo.RegisterAddonMessagePrefix(prefix) end,
  Send = function(prefix, text, chatType, target) return C_ChatInfo.SendAddonMessage(prefix, text, chatType, target) end,
  Clubs = function() return C_Club.GetSubscribedClubs() end,
  Streams = function(clubId) return C_Club.GetStreams(clubId) end,
  ChannelIndex = function(name) return GetChannelName(name) end,
  AddChannel = function(clubId, streamId) return C_Club.AddClubStreamChatChannel(clubId, streamId) end,
  CanAddChannel = function() return ChatFrameUtil.CanAddChannel() end,
  ChatRestricted = function()
    local state = C_RestrictedActions.GetAddOnRestrictionState(Enum.AddOnRestrictionType.Chat)
    return state ~= nil and state ~= 0
  end,
  InCombat = function() return InCombatLockdown() end,
  Resting = function() return IsResting() end,
  Speed = function() return GetUnitSpeed("player") end,
  Self = function() return UnitFullName("player") end,
  Realm = function() return GetNormalizedRealmName() end,
  After = function(delay, fn) C_Timer.After(delay, fn) end,
  Clock = function() return GetTime() end,
}

local queue = {}          -- { { text, tag } }, oldest first
local pumping = false     -- a send is scheduled
local paused = false      -- the Chat restriction is on
local scale = 1           -- the throttle's cut, back to 1 after BACKOFF
local recoverAt = 0
local lastSent = nil      -- the clock at the last send attempt
local community = nil     -- { clubId, streamId, channelName }, found once per change
local channelState = nil  -- "ok", "missing" or "none" (not a member), as last told
local handlers = {}       -- [kind] = { fn(msg), ... }
-- What went out and came back this session, by kind (the channel suites and
-- the console say it when a message never arrives)
local tally = { sent = {}, results = {}, got = {}, own = {}, raw = {}, echo = {}, handed = {}, noChannel = 0, lockdowns = 0 }

local function Seam(name, ...)
  local ok, a, b = pcall(Transport.seams[name], ...)
  if not ok or Host.IsSecret(a) or Host.IsSecret(b) then return nil end
  return a, b
end

-------------------------------------------------------------------------------
-- Names
-------------------------------------------------------------------------------
-- "Name-NormalizedRealm", the form every sender comparison uses
function Transport.Canonical(name)
  if type(name) ~= "string" or Host.IsSecret(name) or name == "" then return nil end
  if name:find("-", 1, true) then return name end
  local realm = Seam("Realm")
  if type(realm) == "string" and realm ~= "" then return name .. "-" .. realm end
  return name
end

function Transport.Self()
  local name, realm = Seam("Self")
  if type(name) ~= "string" then return nil end
  if type(realm) ~= "string" or realm == "" then return Transport.Canonical(name) end
  return name .. "-" .. realm
end

-------------------------------------------------------------------------------
-- The community and its channel
-------------------------------------------------------------------------------
local function FindClub()
  local clubs = Seam("Clubs")
  if type(clubs) ~= "table" or (issecrettable and issecrettable(clubs)) then return nil end
  for _, club in ipairs(clubs) do
    if Curator.Const.CLUB_ID and tostring(club.clubId) == tostring(Curator.Const.CLUB_ID) then return club.clubId end
    if not Curator.Const.CLUB_ID and not Host.IsSecret(club.name) and club.name == Curator.Const.CLUB_NAME then
      return club.clubId
    end
  end
  return nil
end

local function FindStream(clubId)
  local streams = Seam("Streams", clubId)
  if type(streams) ~= "table" or (issecrettable and issecrettable(streams)) then return nil end
  for _, stream in ipairs(streams) do
    if not Host.IsSecret(stream.name) and stream.name == Curator.Const.STREAM_NAME then return stream.streamId end
  end
  return nil
end

-- Community(): { clubId, streamId, channelName }, or nil while this
-- character isn't in the community (or its stream can't be seen)
function Transport.Community()
  if community then return community end
  local clubId = FindClub()
  local streamId = clubId and FindStream(clubId)
  if not streamId then return nil end
  community = { clubId = clubId, streamId = streamId,
    channelName = ("Community:%s:%s"):format(tostring(clubId), tostring(streamId)) }
  return community
end

-- Forget what was found (the club list, streams or channels changed)
function Transport.Forget()
  community = nil
end

function Transport.IsMember()
  return Transport.Community() ~= nil
end

-- The channel's current index, or nil when it isn't in the channel list
function Transport.ChannelIndex()
  local found = Transport.Community()
  if not found then return nil end
  local index = Seam("ChannelIndex", found.channelName)
  if type(index) == "number" and index > 0 then return index end
  return nil
end

-- AddChannel(): puts the community's channel back in the channel list;
-- returns the index, or nil and why ("member", "slot", "failed")
function Transport.AddChannel()
  Transport.Forget()
  local found = Transport.Community()
  if not found then return nil, "member" end
  local index = Transport.ChannelIndex()
  if index then return index end
  if Seam("CanAddChannel") == false then return nil, "slot" end
  pcall(Transport.seams.AddChannel, found.clubId, found.streamId)
  index = Transport.ChannelIndex()
  if not index then return nil, "failed" end
  Transport.CheckChannel()
  Transport.Resume()
  return index
end

-------------------------------------------------------------------------------
-- The channel watch
-------------------------------------------------------------------------------
Transport.CONFIRM = 3   -- seconds between the two looks that call a channel missing

local function ChannelNow()
  if not Transport.IsMember() then return "none" end
  return Transport.ChannelIndex() and "ok" or "missing"
end

local function Tell(state)
  if channelState == state then return end
  channelState = state
  if Transport.OnChannelChanged then pcall(Transport.OnChannelChanged, state) end
end

-- CheckChannel(): looks at the channel now; "missing" is told only when a
-- second look CONFIRM seconds later agrees (channels rejoin a moment after
-- a loading screen), "ok" and "none" at once
function Transport.CheckChannel()
  local state = ChannelNow()
  if state ~= "missing" then
    Tell(state)
    return state
  end
  if channelState == "missing" then return state end
  Transport.seams.After(Transport.CONFIRM, function()
    if ChannelNow() == "missing" then Tell("missing") end
  end)
  return state
end

-------------------------------------------------------------------------------
-- The send queue
-------------------------------------------------------------------------------
-- "idle", "resting", "moving", "combat" or "lockdown"
function Transport.Activity()
  if paused or Seam("ChatRestricted") then return "lockdown" end
  if Seam("InCombat") ~= false then return "combat" end
  local ok, speed = pcall(Transport.seams.Speed)
  if not ok or Host.IsSecret(speed) then return "combat" end
  if type(speed) == "number" and speed > 0 then return "moving" end
  if Seam("Resting") then return "resting" end
  return "idle"
end

-- Seconds between two sends now
function Transport.Interval()
  local activity = Transport.Activity()
  local budget = Transport.BUDGET[activity] or Transport.BUDGET.idle
  if activity == "resting" then budget = Transport.BUDGET.idle end
  if Seam("Clock") and Seam("Clock") >= recoverAt then scale = 1 end
  return 1 / (Transport.FULL_RATE * budget * scale)
end

local Pump

local function Schedule(delay)
  if pumping then return end
  pumping = true
  Transport.seams.After(delay, function()
    pumping = false
    Pump()
  end)
end

-- Wait(): seconds until the next send may go, counted from the last one,
-- so a message queued just after a send never follows it at once (two
-- sends a frame apart drew ChannelThrottle in game, 2026-09-26)
function Transport.Wait()
  local now = Seam("Clock")
  if not lastSent or not now then return 0 end
  return math.max(0, lastSent + Transport.Interval() - now)
end

-- Sends the oldest message; returns the delay before the next one, or nil
-- to stop (empty, paused or no channel)
local function SendOne()
  local item = queue[1]
  if not item then return nil end
  local index = Transport.ChannelIndex()
  if not index then
    tally.noChannel = tally.noChannel + 1
    return nil
  end
  local ok, result = pcall(Transport.seams.Send, Curator.Const.PREFIX, item.text, "CHANNEL", index)
  result = ok and result or nil
  lastSent = Seam("Clock")
  local kind = item.text:sub(1, 1)
  tally.sent[kind] = (tally.sent[kind] or 0) + 1
  local code = ok and tostring(result) or "error"
  tally.results[code] = (tally.results[code] or 0) + 1
  if Transport.OnSent then pcall(Transport.OnSent, item.text, ok and result or "error") end
  if result == RESULT.LOCKDOWN then
    -- Paused until ADDON_RESTRICTION_STATE_CHANGED; that event fires only
    -- when a restriction changes, so a refusal while the Chat restriction
    -- reads off is looked at again after BACKOFF
    paused = true
    tally.lockdowns = tally.lockdowns + 1
    Transport.seams.After(Transport.BACKOFF, function() Transport.OnRestrictionChanged() end)
    return nil
  end
  if result == RESULT.THROTTLE or result == RESULT.CHANNEL_THROTTLE then
    scale = scale / 2
    recoverAt = (Seam("Clock") or 0) + Transport.BACKOFF
    return Transport.BACKOFF
  end
  table.remove(queue, 1)
  if result ~= RESULT.SUCCESS then
    Host.Log("Curator send refused (%s): %s", tostring(result), item.text:sub(1, 1))
  end
  if item.onSent then pcall(item.onSent, result) end
  if result == RESULT.SUCCESS and Transport.LOCAL_ECHO then
    Transport.seams.After(0, function() Transport.Echo(item.text) end)
  end
  return #queue > 0 and Transport.Interval() or nil
end

Pump = function()
  if paused then return end
  local delay = SendOne()
  if delay then Schedule(delay) end
end

-- Enqueue(text, tag, onSent, first): queues one message; tag names what it
-- belongs to (a request ID) so Drop can take a cancelled transfer's messages
-- out; first puts it at the front (replies)
function Transport.Enqueue(text, tag, onSent, first)
  if type(text) ~= "string" then return false end
  local item = { text = text, tag = tag, onSent = onSent }
  if first then table.insert(queue, 1, item) else queue[#queue + 1] = item end
  if not pumping and not paused then Schedule(Transport.Wait()) end
  return true
end

-- Send(kind, mode, to, ...): encodes and queues a message; false when it
-- can't be encoded
function Transport.Send(kind, mode, to, ...)
  local text = Protocol.Encode(kind, mode, to, ...)
  return Transport.Enqueue(text, nil, nil, kind ~= "D")
end

-- EnqueueLocal(text, onSent): hands a message to this client's own
-- receiver a frame later, never over the channel; onSent(0) first
function Transport.EnqueueLocal(text, onSent)
  if type(text) ~= "string" then return false end
  local kind = text:sub(1, 1)
  tally.handed[kind] = (tally.handed[kind] or 0) + 1
  if Transport.OnSent then pcall(Transport.OnSent, text, RESULT.SUCCESS, true) end
  Transport.seams.After(0, function()
    if onSent then pcall(onSent, RESULT.SUCCESS) end
    Transport.Echo(text)
  end)
  return true
end

-- SendLocal(kind, mode, to, ...): Send, handed over locally (EnqueueLocal)
function Transport.SendLocal(kind, mode, to, ...)
  return Transport.EnqueueLocal(Protocol.Encode(kind, mode, to, ...))
end

-- IsLocalPull(mode, name): whether a pull with this character stays on
-- this client (LOCAL_SELF, live mode, this very character)
function Transport.IsLocalPull(mode, name)
  return Transport.LOCAL_SELF == true and mode == Protocol.LIVE and name ~= nil and name == Transport.Self()
end

-- SendThen(onSent, kind, mode, to, ...): Send, calling onSent(result) once
-- the message has left the queue (a deadline starts then, not when queued)
function Transport.SendThen(onSent, kind, mode, to, ...)
  local text = Protocol.Encode(kind, mode, to, ...)
  return Transport.Enqueue(text, nil, onSent, kind ~= "D")
end

function Transport.Drop(tag)
  for i = #queue, 1, -1 do
    if queue[i].tag == tag then table.remove(queue, i) end
  end
end

function Transport.Queued(tag)
  local n = 0
  for _, item in ipairs(queue) do
    if tag == nil or item.tag == tag then n = n + 1 end
  end
  return n
end

-- Resume(): starts the queue again when messages wait (the channel is back)
function Transport.Resume()
  if #queue > 0 and not pumping and not paused then Schedule(Transport.Wait()) end
end

function Transport.IsPaused()
  return paused
end

-- The Chat restriction lifted (ADDON_RESTRICTION_STATE_CHANGED)
function Transport.OnRestrictionChanged()
  if paused and not Seam("ChatRestricted") then
    paused = false
    Schedule(Transport.Wait())
  end
end

-------------------------------------------------------------------------------
-- Receiving
-------------------------------------------------------------------------------
-- On(kind, fn): fn(msg) for every message of that type; msg = { kind, mode,
-- to, fields, sender ("Name-Realm"), self (sent by this character) }
function Transport.On(kind, fn)
  handlers[kind] = handlers[kind] or {}
  table.insert(handlers[kind], fn)
end

local function Dispatch(msg)
  for _, fn in ipairs(handlers[msg.kind] or {}) do
    local ok, err = pcall(fn, msg)
    if not ok then Host.Log("Curator handler %s failed: %s", msg.kind, tostring(err)) end
  end
end

-- Receive(prefix, text, channel, sender, ...): one CHAT_MSG_ADDON
function Transport.Receive(prefix, text, channel, sender, ...)
  for i = 1, select("#", ...) do
    if Host.IsSecret((select(i, ...))) then return false end
  end
  if Host.IsSecret(prefix) or Host.IsSecret(text) or Host.IsSecret(channel) or Host.IsSecret(sender) then return false end
  if prefix == Curator.Const.PREFIX then
    local key = tostring(channel)
    tally.raw[key] = (tally.raw[key] or 0) + 1
  end
  if prefix ~= Curator.Const.PREFIX or channel ~= "CHANNEL" then return false end
  local msg = Protocol.Decode(text)
  local from = Transport.Canonical(sender)
  if not msg or not from then return false end
  msg.sender = from
  msg.self = from == Transport.Self()
  local counts = msg.self and tally.own or tally.got
  counts[msg.kind] = (counts[msg.kind] or 0) + 1
  if msg.self and Transport.LOCAL_ECHO then return false end   -- Echo already handed it over
  Dispatch(msg)
  return true
end

-- Echo(text): a message this client just sent, handed to its own receiver
-- as sent by this character (LOCAL_ECHO)
function Transport.Echo(text)
  local msg = Protocol.Decode(text)
  local me = Transport.Self()
  if not msg or not me then return false end
  msg.sender, msg.self = me, true
  tally.echo[msg.kind] = (tally.echo[msg.kind] or 0) + 1
  Dispatch(msg)
  return true
end

local function Counts(tbl)
  local keys, out = {}, {}
  for k in pairs(tbl) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do out[#out + 1] = k .. " " .. tbl[k] end
  return #out > 0 and table.concat(out, ", ") or "none"
end

-- Tally(): one line on what this session sent (by kind, and by the send's
-- result code: 0 is success, 11 the addon chat lockdown) and received (from
-- others, its own messages coming back from the server, those handed over
-- by LOCAL_ECHO, and every message with the prefix by the chat type it came
-- with, before any filter), and how often no channel was found
function Transport.Tally()
  return ("sent %s (results %s); received %s; own back %s; echoed locally %s; handed over without the channel %s; with the prefix by chat type %s; no channel %d; lockdowns %d; queued %d%s")
    :format(Counts(tally.sent), Counts(tally.results), Counts(tally.got), Counts(tally.own), Counts(tally.echo), Counts(tally.handed),
      Counts(tally.raw), tally.noChannel, tally.lockdowns, #queue, paused and "; paused" or "")
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
pcall(Transport.seams.Register, Curator.Const.PREFIX)

-- The watch starts WATCH_AFTER seconds after entering the world (the
-- community channels join a moment after login), then follows changes
Transport.WATCH_AFTER = 15
local watching = false
local check = CobySuite_Recollect.Utilities.Coalesce(1, function() if watching then Transport.CheckChannel() end end)

local function Changed()
  Transport.Forget()
  check:Call()
end

-- A character that just joined the curator community gets its channel
-- once (a join by the invite link may not add it)
local function Joined(clubId)
  Changed()
  if Host.IsSecret(clubId) then return end
  Transport.seams.After(Transport.CONFIRM, function()
    local found = Transport.Community()
    if found and tostring(found.clubId) == tostring(clubId) and not Transport.ChannelIndex() then Transport.AddChannel() end
  end)
end
Transport.Joined = Joined

local events = {
  CHAT_MSG_ADDON = function(...) Transport.Receive(...) end,
  ADDON_RESTRICTION_STATE_CHANGED = function() Transport.OnRestrictionChanged() end,
  CLUB_ADDED = Joined,
  CLUB_REMOVED = Changed,
  CLUB_STREAM_ADDED = Changed,
  CLUB_STREAM_REMOVED = Changed,
  CHANNEL_UI_UPDATE = function()
    if #queue > 0 and not pumping then Schedule(Transport.Wait()) end
    check:Call()
  end,
  PLAYER_ENTERING_WORLD = function()
    if watching then return end
    Transport.seams.After(Transport.WATCH_AFTER, function()
      watching = true
      Transport.CheckChannel()
    end)
  end,
}

local frame = CreateFrame("Frame")
for event in pairs(events) do pcall(frame.RegisterEvent, frame, event) end
-- Not gated on a test run: the channel suites talk over the real channel,
-- and receiving reads nothing a test scripts
frame:SetScript("OnEvent", function(_, event, ...)
  local ok, err = pcall(events[event], ...)
  if not ok then Host.Log("Curator transport %s failed: %s", event, tostring(err)) end
end)

-------------------------------------------------------------------------------
-- Tests: _test.Swap(state) puts state in place of the queue, the rate state,
-- the channel state and the tally (a fresh session's when state is nil) and
-- returns what it replaced, so the loopback sets the live ones aside for a
-- scripted run and puts them back after it. Tables are handed over, never
-- wiped. Only sync tests swap, so no real send is due while they run.
-------------------------------------------------------------------------------
Transport._test = {}
function Transport._test.Swap(state)
  local old = { queue = queue, pumping = pumping, paused = paused, scale = scale, recoverAt = recoverAt, lastSent = lastSent,
    community = community, channelState = channelState, tally = tally }
  state = state or { queue = {}, pumping = false, paused = false, scale = 1, recoverAt = 0,
    tally = { sent = {}, results = {}, got = {}, own = {}, raw = {}, echo = {}, handed = {}, noChannel = 0, lockdowns = 0 } }
  queue, pumping, paused, scale, recoverAt, lastSent = state.queue, state.pumping, state.paused, state.scale, state.recoverAt, state.lastSent
  community, channelState, tally = state.community, state.channelState, state.tally
  return old
end
