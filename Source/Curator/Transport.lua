-------------------------------------------------------------------------------
-- Curator.Transport: whispers, the send queue and the receiver (curator
-- spec, "Channel and addressing", "Adaptive rate")
--
-- Every message is a whisper (Cobanyte, 2026-09-28: the hidden channel went,
-- since whispers reach every realm and the channel took a chat channel slot
-- for nothing). Measured between two clients with the route test (/rec
-- curator transport): 30 of 30 arrived at 4 a second, whole, about half a
-- second each way; between realms that aren't connected (Alleria and
-- Illidan), with no Battle.net friendship and no shared guild, only the
-- community, 60 of 60 at a pull's pace and 40 of 40 in a burst each way; an
-- Alliance curator's collection reached the Horde author the same day. An
-- addon message on the community's own chat channel is never delivered to
-- another player, so the community is only the member list.
--   - A message to one addressee whose character is known goes to that
--     character (Route: the author's once a message from them passed the
--     role check, a curator's once its R came in).
--   - A message with no route is whispered to each character Recipients
--     names from the community's member list, online ones only (a whisper
--     to someone offline prints "No player named ..." in the sender's
--     chat): to everyone (Protocol.ALL, the presence check), every online
--     member; to the author with no route yet (a curator's O and L), every
--     online Owner and Leader. Its onSent runs once the last copy has left.
--   - Test-mode traffic is honoured only from this very character (D23), so
--     it is whispered to this character itself: it goes through the server's
--     send path, and the local echo delivers it.
--
-- The queue: one message at a time, WHISPER_INTERVAL seconds apart when
-- idle or resting, longer while moving (BUDGET) and in combat (a secret
-- speed counts as combat), counted from the last send even when the queue
-- had emptied since, so other addons keep room. AddonMessageThrottle (3:
-- the message was dropped) halves the rate, waits BACKOFF seconds and sends
-- it again (a receiver drops duplicate sequence numbers); a lost data part
-- is asked for again by N. A whisper the game refuses otherwise goes once
-- more after BACKOFF. AddOnMessageLockdown pauses the queue until
-- ADDON_RESTRICTION_STATE_CHANGED shows the Chat restriction gone, or, when
-- the restriction reads off (the game refused with no restriction change;
-- seen in game 2026-09-26), until BACKOFF has passed. Sends are scheduled
-- with C_Timer, never OnUpdate.
--
-- The receiver: every CHAT_MSG_ADDON argument is checked for secrets before
-- any match; a secret argument drops the message. Messages with the prefix
-- are decoded (Protocol.Decode) and handed to every handler of their type
-- (the curator side, and the author's console in development builds), with
-- the server-stamped sender in canonical "Name-Realm" form. A whisper is
-- read; so is the old hidden channel (a 0.0.1c client still sends on it) and
-- a message with no channel name (the loopback). LOCAL_ECHO hands each
-- message sent to this client's own handlers once and drops any copy the
-- server returns.
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

Transport.FULL_RATE = 1          -- the rate BUDGET's shares are of (WhisperInterval scales by them)
Transport.BUDGET = { idle = 0.5, moving = 0.35, combat = 0.2 }
Transport.BACKOFF = 5             -- seconds after a throttle before the rate recovers
Transport.WHISPER_INTERVAL = 0.25 -- seconds between whispers when idle (4 a second arrived whole, 2026-09-28)
-- The game doesn't hand a sender its own community channel message (Step 1
-- T14, in game 2026-09-26), so every message sent is also given to this
-- client's own receiver a frame later, and a copy the server does return is
-- dropped: each message is handled once either way (spec, T14's fallback)
Transport.LOCAL_ECHO = true
-- A live pull between this client's author and curator sides (the author
-- pulling their own findings) never leaves the client: SendLocal and
-- EnqueueLocal hand its messages to this client's own receiver a frame
-- later. Test-mode pulls go through the server (the channel suites
-- exercise it).
Transport.LOCAL_SELF = true

local RESULT = { SUCCESS = 0, THROTTLE = 3, LOCKDOWN = 11 }
Transport.RESULT = RESULT

Transport.seams = {
  Register = function(prefix) return C_ChatInfo.RegisterAddonMessagePrefix(prefix) end,
  Send = function(prefix, text, chatType, target) return C_ChatInfo.SendAddonMessage(prefix, text, chatType, target) end,
  Clubs = function() return C_Club.GetSubscribedClubs() end,
  Streams = function(clubId) return C_Club.GetStreams(clubId) end,
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
local lastWhisper = nil   -- the clock at the last whisper
local routes = {}         -- [addressee] = "Name-Realm", the character a message to it is whispered to
local community = nil     -- { clubId, streamId, channelName }, found once per change
local handlers = {}       -- [kind] = { fn(msg), ... }
-- What went out and came back this session, by kind (the channel suites and
-- the console say it when a message never arrives)
local tally = { sent = {}, results = {}, got = {}, own = {}, raw = {}, echo = {}, handed = {}, unreachable = 0, lockdowns = 0,
  whispered = 0, retried = 0 }

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
-- The debug log (CURATOR, /rec debug): every step of the conversation, so a
-- curator can copy it for the author (Cobanyte, 2026-09-28). Only plain
-- values are logged; a data part's payload never is, and only the first and
-- every 50th part of a transfer are.
-------------------------------------------------------------------------------
local DATA_EVERY = 50

-- A message in words: its type, mode, addressee and fields (a data part's
-- request and number only)
function Transport.Describe(msg)
  if type(msg) ~= "table" then return "?" end
  local fields = msg.fields or {}
  local shown = {}
  if msg.kind == "D" then
    shown = { tostring(fields[1]), "part " .. tostring(fields[2]) }
  else
    for i = 1, #fields do
      local text = tostring(fields[i])
      shown[i] = #text > 40 and (text:sub(1, 37) .. "...") or text
    end
  end
  -- fields joined by " / ": a "|" would read as a color code in the debug window ("|r" swallowed "on|resting")
  return ("%s (%s) to %s [%s]"):format(tostring(msg.kind), msg.mode == "t" and "test" or "live", tostring(msg.to),
    table.concat(shown, " / "))
end

-- Whether a data part is worth a line (the first, every 50th)
local function DataWorthLogging(msg)
  local seq = msg and msg.kind == "D" and tonumber((msg.fields or {})[2])
  return not seq or seq == 1 or seq % DATA_EVERY == 0
end

local lastCommunityNote

local function NoteCommunity(text)
  if text == lastCommunityNote then return end
  lastCommunityNote = text
  Host.Log("Curator community: %s", text)
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
  if not streamId then
    NoteCommunity(clubId and ("found club %s, but not its %s stream"):format(tostring(clubId), Curator.Const.STREAM_NAME)
      or ("not found among this character's communities (looking for club %s)"):format(tostring(Curator.Const.CLUB_ID)))
    return nil
  end
  community = { clubId = clubId, streamId = streamId,
    channelName = ("Community:%s:%s"):format(tostring(clubId), tostring(streamId)) }
  NoteCommunity(("found: club %s, stream %s, channel %s"):format(tostring(clubId), tostring(streamId), community.channelName))
  return community
end

-- Forget what was found (the club list, streams or channels changed)
function Transport.Forget()
  community = nil
end

function Transport.IsMember()
  return Transport.Community() ~= nil
end


-------------------------------------------------------------------------------
-- Routes: which character a message to an addressee is whispered to
-------------------------------------------------------------------------------
-- Route(to, name): whisper what goes to this addressee (Protocol.AUTHOR, a
-- curator ID) to this character from now on; set only once a message from
-- that character passed the check its side makes
function Transport.Route(to, name)
  if type(to) ~= "string" or to == "" or to == Protocol.ALL then return end
  if type(name) ~= "string" or Host.IsSecret(name) or name == "" then return end
  if name == Transport.Self() then return end   -- this client's own messages reach it by LOCAL_ECHO
  if routes[to] ~= name then Host.Log("Curator route: messages to %s are whispered to %s", to, name) end
  routes[to] = name
end

function Transport.RouteOf(to)
  return routes[to]
end

-- Whisperable(name): whether "Name-Realm" can be whispered: any realm (the
-- route test, 2026-09-28: whispers crossed realms that aren't connected)
function Transport.Whisperable(name)
  return type(name) == "string" and name ~= "" and not Host.IsSecret(name)
end

-- The character a queued message is whispered to, or nil when there is none
local function WhisperTo(item)
  if item.target and Transport.Whisperable(item.target) then return item.target end
  local to = item.text:match("^[^~]*~[^~]*~([^~]*)")
  local name = to and routes[to]
  if name and Transport.Whisperable(name) then return name end
  return nil
end

-- Recipients(mode, to): who a message with no route is whispered to, from
-- the community's member list, online members only (a whisper to someone
-- offline prints "No player named ..." in the sender's chat):
--   test mode: this character itself (D23), through the server and back
--   Protocol.ALL: every online member but this character
--   Protocol.AUTHOR: every online member who may collect (Owner, Leader)
--   anything else (a curator ID with no route yet): nobody
function Transport.Recipients(mode, to)
  local me = Transport.Self()
  if mode == Protocol.TEST then return me and { me } or {} end
  if to ~= Protocol.ALL and to ~= Protocol.AUTHOR then return {} end
  local M = Curator.Membership
  local out = {}
  for _, entry in ipairs(M and M.Roster() or {}) do
    if not entry.isSelf and entry.name ~= me and entry.presence == "online" and Transport.Whisperable(entry.name)
        and (to == Protocol.ALL or M.MayPull(entry.name)) then
      out[#out + 1] = entry.name
    end
  end
  return out
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

-- Seconds between two sends at the budget's share of FULL_RATE (the
-- whisper spacing scales by it)
function Transport.Interval()
  local activity = Transport.Activity()
  local budget = Transport.BUDGET[activity] or Transport.BUDGET.idle
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

-- Seconds between two whispers now: WHISPER_INTERVAL idle or resting,
-- longer by the budget while moving or in combat and by a throttle's cut
function Transport.WhisperInterval()
  local idle = 1 / (Transport.FULL_RATE * Transport.BUDGET.idle)
  return Transport.WHISPER_INTERVAL * Transport.Interval() / idle
end

-- Wait(): seconds until the next message may go, counted from the last
-- send, so a message queued just after a send never follows it at once
-- (two sends a frame apart drew a throttle in game, 2026-09-26)
function Transport.Wait()
  local now = Seam("Clock")
  if not now or not lastWhisper then return 0 end
  return math.max(0, lastWhisper + Transport.WhisperInterval() - now)
end

-- Sends the oldest message; returns the delay before the next one, or nil
-- to stop (empty or paused)
local function SendOne()
  local item = queue[1]
  if not item then return nil end
  local target = WhisperTo(item)
  if not target then
    -- its addressee's route is gone (never set, or a test swapped it out)
    table.remove(queue, 1)
    tally.unreachable = tally.unreachable + 1
    Host.Log("Curator send dropped: nobody to whisper %s to (%d waiting)", item.text:sub(1, 1), #queue)
    if item.onSent then pcall(item.onSent, nil) end
    return #queue > 0 and Transport.Wait() or nil
  end
  local ok, result = pcall(Transport.seams.Send, Curator.Const.PREFIX, item.text, "WHISPER", target)
  result = ok and result or nil
  local kind = item.text:sub(1, 1)
  local sentMsg = Protocol.Decode(item.text)
  if DataWorthLogging(sentMsg) then
    Host.Log("Curator sent %s by whisper to %s: %s", Transport.Describe(sentMsg), target, ok and tostring(result) or "error")
  end
  lastWhisper = Seam("Clock")
  tally.whispered = tally.whispered + 1
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
  if result == RESULT.THROTTLE then
    -- dropped by the game: sent again once the rate has come down
    scale = scale / 2
    recoverAt = (Seam("Clock") or 0) + Transport.BACKOFF
    return Transport.BACKOFF
  end
  if result ~= RESULT.SUCCESS and not item.retried then
    -- a whisper the game refused: once more after BACKOFF
    item.retried = true
    tally.retried = tally.retried + 1
    Host.Log("Curator whisper to %s refused (%s): %s goes again in %d seconds", target, tostring(result), kind, Transport.BACKOFF)
    return Transport.BACKOFF
  end
  table.remove(queue, 1)
  if result ~= RESULT.SUCCESS then
    Host.Log("Curator whisper of %s to %s refused again (%s): dropped", kind, target, tostring(result))
  end
  if item.onSent then pcall(item.onSent, result) end
  if result == RESULT.SUCCESS and Transport.LOCAL_ECHO and item.echo ~= false then
    Transport.seams.After(0, function() Transport.Echo(item.text) end)
  end
  return #queue > 0 and Transport.Wait() or nil
end

Pump = function()
  if paused then return end
  local delay = SendOne()
  if delay then Schedule(delay) end
end

-- The queue items for one message: one to its route, else one per
-- recipient (Recipients) sharing onSent, which runs once the last has left;
-- only the first is echoed to this client (LOCAL_ECHO). An empty list when
-- nobody is online to get it.
local function Items(text, tag, onSent)
  local _, mode, to = text:match("^([^~]*)~([^~]*)~([^~]*)")
  if mode ~= Protocol.TEST and to and routes[to] then return { { text = text, tag = tag, onSent = onSent } } end
  local names = Transport.Recipients(mode, to)
  local items, left = {}, #names
  local function Each(result)
    left = left - 1
    if left == 0 and onSent then onSent(result) end
  end
  for i, name in ipairs(names) do
    items[i] = { text = text, tag = tag, onSent = Each, target = name, echo = i == 1 }
  end
  return items
end

-- Enqueue(text, tag, onSent, first, target): queues one message; tag names
-- what it belongs to (a request ID) so Drop can take a cancelled transfer's
-- messages out; first puts it at the front (replies); target, when given, is
-- the character it goes to whatever the routes say by the time it is sent (a
-- collection goes to the author who asked for it, never a second author who
-- spoke since), unless it is this character. A message nobody online can be
-- whispered still reaches this client's own handlers (the author answering
-- their own presence check), and onSent(nil) runs a frame later.
function Transport.Enqueue(text, tag, onSent, first, target)
  if type(text) ~= "string" then return false end
  local kind = text:sub(1, 1)
  local items
  if target ~= nil and target ~= Transport.Self() and Transport.Whisperable(target) then
    items = { { text = text, tag = tag, onSent = onSent, target = target } }
  else
    items = Items(text, tag, onSent)
  end
  if #items == 0 then
    tally.unreachable = tally.unreachable + 1
    Host.Log("Curator %s not sent: nobody online to whisper it to", kind)
    Transport.seams.After(0, function()
      if Transport.LOCAL_ECHO then Transport.Echo(text) end
      if onSent then pcall(onSent, nil) end
    end)
    return true
  end
  for i, item in ipairs(items) do
    if first then table.insert(queue, i, item) else queue[#queue + 1] = item end
  end
  if kind ~= "D" or #queue == #items then
    Host.Log("Curator queued %s%s (%d characters) for %d %s; %d waiting, sending %s", kind, first and " first" or "", #text,
      #items, #items == 1 and "character" or "characters", #queue, paused and "paused" or tostring(Transport.Activity()))
  end
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
-- receiver a frame later, never through the server; onSent(0) first
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
  if prefix ~= Curator.Const.PREFIX then return false end
  -- a route test (/rec curator ping): counted above by chat type, handled by Ping.lua's own receivers
  if type(text) == "string" and text:sub(1, 4) == "RCT~" then return false end
  if channel == "CHANNEL" then
    -- the old hidden channel (a 0.0.1c client still sends there; TODO with
    -- LeaveOldChannel.lua: drop once no such client is left) or none (the
    -- loopback); the channel's name comes 4th after the sender
    local name = select(4, ...)
    local ours = Curator.Const.CHANNEL_NAME:lower()
    if type(name) == "string" and name ~= "" and not name:lower():find(ours, 1, true) then
      Host.Log("Curator message from %s ignored: it came on the channel %s, not %s", tostring(sender), name, Curator.Const.CHANNEL_NAME)
      return false
    end
  elseif channel ~= "WHISPER" then
    Host.Log("Curator message from %s ignored: it came by %s, not a whisper", tostring(sender), tostring(channel))
    return false
  end
  local msg = Protocol.Decode(text)
  local from = Transport.Canonical(sender)
  if not msg or not from then
    Host.Log("Curator message from %s couldn't be read (%d bytes)", tostring(sender), type(text) == "string" and #text or 0)
    return false
  end
  msg.sender = from
  msg.self = from == Transport.Self()
  local counts = msg.self and tally.own or tally.got
  counts[msg.kind] = (counts[msg.kind] or 0) + 1
  if msg.self and Transport.LOCAL_ECHO then return false end   -- Echo already handed it over
  if DataWorthLogging(msg) then Host.Log("Curator got %s from %s by %s", Transport.Describe(msg), from, channel:lower()) end
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

-- Counts(): this session's counts as plain copies: sent and got (from
-- others) by message type, raw (every message with the prefix, by chat type)
function Transport.Counts()
  local function Copy(tbl)
    local out = {}
    for k, v in pairs(tbl) do out[k] = v end
    return out
  end
  return { sent = Copy(tally.sent), got = Copy(tally.got), raw = Copy(tally.raw), results = Copy(tally.results) }
end

-- Tally(): one line on what this session sent (by kind, and by the send's
-- result code: 0 is success, 11 the addon chat lockdown; how many whispers,
-- and how many were refused once and sent again) and received (from
-- others, its own messages coming back from the server, those handed over
-- by LOCAL_ECHO, and every message with the prefix by the chat type it came
-- with, before any filter), and how many had nobody to go to
function Transport.Tally()
  return ("sent %s (results %s; %d whispers, %d sent again after a refusal); received %s; own back %s; echoed locally %s; handed over locally %s; with the prefix by chat type %s; nobody to send to %d; lockdowns %d; queued %d%s")
    :format(Counts(tally.sent), Counts(tally.results), tally.whispered or 0, tally.retried or 0, Counts(tally.got), Counts(tally.own),
      Counts(tally.echo), Counts(tally.handed), Counts(tally.raw), tally.unreachable, tally.lockdowns, #queue, paused and "; paused" or "")
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
pcall(Transport.seams.Register, Curator.Const.PREFIX)

-- A club added, removed or changed: find the community again
local function Changed()
  Transport.Forget()
end

local events = {
  CHAT_MSG_ADDON = function(...) Transport.Receive(...) end,
  ADDON_RESTRICTION_STATE_CHANGED = function() Transport.OnRestrictionChanged() end,
  CLUB_ADDED = Changed,
  CLUB_REMOVED = Changed,
  CLUB_STREAM_ADDED = Changed,
  CLUB_STREAM_REMOVED = Changed,
}

local frame = CreateFrame("Frame")
for event in pairs(events) do pcall(frame.RegisterEvent, frame, event) end
-- Not gated on a test run: the channel suites talk through the server,
-- and receiving reads nothing a test scripts
frame:SetScript("OnEvent", function(_, event, ...)
  local ok, err = pcall(events[event], ...)
  if not ok then Host.Log("Curator transport %s failed: %s", event, tostring(err)) end
end)

-------------------------------------------------------------------------------
-- Tests: _test.Swap(state) puts state in place of the queue, the rate state,
-- the routes and the tally (a fresh session's when state is nil) and
-- returns what it replaced, so the loopback sets the live ones aside for a
-- scripted run and puts them back after it. Tables are handed over, never
-- wiped. Only sync tests swap, so no real send is due while they run.
-------------------------------------------------------------------------------
Transport._test = {}
function Transport._test.Swap(state)
  local old = { queue = queue, pumping = pumping, paused = paused, scale = scale, recoverAt = recoverAt,
    lastWhisper = lastWhisper, routes = routes, community = community, tally = tally }
  state = state or { queue = {}, pumping = false, paused = false, scale = 1, recoverAt = 0, routes = {},
    tally = { sent = {}, results = {}, got = {}, own = {}, raw = {}, echo = {}, handed = {}, unreachable = 0, lockdowns = 0,
      whispered = 0, retried = 0 } }
  queue, pumping, paused, scale, recoverAt = state.queue, state.pumping, state.paused, state.scale, state.recoverAt
  lastWhisper, routes = state.lastWhisper, state.routes or {}
  community, tally = state.community, state.tally
  return old
end
