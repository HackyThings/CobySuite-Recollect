-------------------------------------------------------------------------------
-- Curator.Transport: the hidden channel, whispers, the send queue and the
-- receiver (curator spec, "Channel and addressing", "Adaptive rate")
--
-- The routes (the route test, /rec curator ping, 2026-09-28): an addon
-- message on the community's chat channel is never delivered to another
-- player (nor echoed back), so the traffic goes two other ways, both
-- measured between two clients:
--   - whispers, for a message to one addressee whose character is known
--     (Route: the author's character once a message from them passed the
--     role check, a curator's once its R came in). 30 of 30 arrived at 4 a
--     second, whole, about half a second each way. Only to a character of
--     this realm or a connected one (GetAutoCompleteRealms);
--   - the hidden channel, Const.CHANNEL_NAME, a custom channel joined with
--     JoinTemporaryChannel and in no chat window (so no join notice shows),
--     for messages to everyone (the presence check) and for any addressee
--     with no route. 60 of 60 arrived at one message every 2 seconds; faster
--     draws the channel throttle.
-- A member of the community joins the hidden channel by itself (the channel
-- watch, CheckChannel: 15 seconds after login and on channel and club
-- changes); it is told once, after a second look CONFIRM seconds later,
-- only when the join failed (every channel slot in use), and once when it
-- is back. AddChannel(), for /rec curator channel, joins it again.
--
-- The queue: one message at a time, spaced by the adaptive rate (counted
-- from the last send on its route, even when the queue had emptied since):
-- on the channel about 1 message a second at full rate, of which curator
-- traffic uses 50% idle or resting, 35% moving and 20% in combat (a secret
-- speed counts as combat), so other addons keep room; a whisper
-- WHISPER_INTERVAL seconds apart when idle, scaled the same way.
-- AddonMessageThrottle (3: the message was dropped) halves the rate, waits
-- BACKOFF seconds and sends it again (a receiver drops duplicate sequence
-- numbers). ChannelThrottle (8: the message may still arrive) halves the
-- rate and moves on; a lost data part is asked for again by N. A whisper
-- the game refuses goes once more over the channel. AddOnMessageLockdown
-- pauses the queue until ADDON_RESTRICTION_STATE_CHANGED shows the Chat
-- restriction gone, or, when the restriction reads off (the game refused
-- with no restriction change; seen in game 2026-09-26), until BACKOFF has
-- passed. Sends are scheduled with C_Timer, never OnUpdate.
--
-- The receiver: every CHAT_MSG_ADDON argument is checked for secrets before
-- any match; a secret argument drops the message. Messages with the prefix
-- are decoded (Protocol.Decode) and handed to every handler of their type
-- (the curator side, and the author's console in development builds), with
-- the server-stamped sender in canonical "Name-Realm" form. Only a whisper
-- or the hidden channel is read (a message with no channel name, from the
-- loopback, counts as the channel). LOCAL_ECHO hands each message sent to
-- this client's own handlers and drops a server copy (the community channel
-- never returned one, Step 1 T14; the hidden channel does).
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
Transport.WHISPER_INTERVAL = 0.25 -- seconds between whispers when idle (4 a second arrived whole, 2026-09-28)
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
  AddChannel = function(name) return JoinTemporaryChannel(name) end,
  Realms = function() return GetAutoCompleteRealms() end,
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
local lastSent = nil      -- the clock at the last send attempt on the channel
local lastWhisper = nil   -- the clock at the last whisper
local routes = {}         -- [addressee] = "Name-Realm", the character a message to it is whispered to
local joinTried = nil     -- the clock at the last join of the hidden channel
local community = nil     -- { clubId, streamId, channelName }, found once per change
local channelState = nil  -- "ok", "missing" or "none" (not a member), as last told
local handlers = {}       -- [kind] = { fn(msg), ... }
-- What went out and came back this session, by kind (the channel suites and
-- the console say it when a message never arrives)
local tally = { sent = {}, results = {}, got = {}, own = {}, raw = {}, echo = {}, handed = {}, noChannel = 0, lockdowns = 0,
  whispered = 0, fallback = 0 }

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
-- values are logged; a data part's payload never is, and only the first,
-- every 50th and last part of a transfer are.
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

-- The hidden channel's current index, or nil when this character isn't a
-- member of the community or isn't in the channel
function Transport.ChannelIndex()
  if not Transport.Community() then return nil end
  local index = Seam("ChannelIndex", Curator.Const.CHANNEL_NAME)
  if type(index) == "number" and index > 0 then return index end
  return nil
end

-- AddChannel(): joins the hidden channel; returns the index, or nil and why
-- ("member", "slot", "joining": the join answers a moment later, and the
-- watch tells if it failed)
function Transport.AddChannel()
  Transport.Forget()
  if not Transport.Community() then return nil, "member" end
  local index = Transport.ChannelIndex()
  if index then return index end
  if Seam("CanAddChannel") == false then
    Host.Log("Curator channel: can't join %s, every chat channel slot is in use", Curator.Const.CHANNEL_NAME)
    return nil, "slot"
  end
  joinTried = Seam("Clock") or 0
  local ok, err = pcall(Transport.seams.AddChannel, Curator.Const.CHANNEL_NAME)
  index = Transport.ChannelIndex()
  Host.Log("Curator channel: joined %s: %s", Curator.Const.CHANNEL_NAME,
    not ok and ("error " .. tostring(err)) or index and ("/" .. index) or "waiting for the game")
  if not index then return nil, "joining" end
  Transport.CheckChannel()
  Transport.Resume()
  return index
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

local function NormalRealm(realm)
  if type(realm) ~= "string" or Host.IsSecret(realm) then return nil end
  return (realm:gsub("[%s%-]", "")):lower()
end

-- Whisperable(name): whether a whisper can reach "Name-Realm": this realm or
-- one connected to it
function Transport.Whisperable(name)
  if type(name) ~= "string" then return false end
  local realm = NormalRealm(name:match("^[^%-]+%-(.+)$"))
  if not realm then return true end
  local mine = NormalRealm(Seam("Realm"))
  if mine and realm == mine then return true end
  local ok, realms = pcall(Transport.seams.Realms)
  if not ok or type(realms) ~= "table" or (issecrettable and issecrettable(realms)) then return false end
  for _, other in ipairs(realms) do
    if NormalRealm(other) == realm then return true end
  end
  return false
end

-- The character a queued message is whispered to, or nil for the channel
local function WhisperTo(item)
  if item.channel then return nil end
  local to = item.text:match("^[^~]*~[^~]*~([^~]*)")
  local name = to and routes[to]
  if name and Transport.Whisperable(name) then return name end
  return nil
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
  Host.Log("Curator channel: %s (was %s; index %s)", state, tostring(channelState), tostring(Transport.ChannelIndex()))
  channelState = state
  if Transport.OnChannelChanged then pcall(Transport.OnChannelChanged, state) end
end

Transport.JOIN_AGAIN = 30   -- seconds before a join that didn't take is tried again

-- CheckChannel(): looks at the channel now; a member not in it joins it (at
-- most every JOIN_AGAIN seconds), and "missing" is told only when a second
-- look CONFIRM seconds later still finds no channel; "ok" and "none" at once
function Transport.CheckChannel()
  local state = ChannelNow()
  if state ~= "missing" then
    Tell(state)
    return state
  end
  local now = Seam("Clock") or 0
  if not joinTried or now - joinTried >= Transport.JOIN_AGAIN then
    if Transport.AddChannel() then return "ok" end
  end
  if channelState == "missing" then return state end
  Transport.seams.After(Transport.CONFIRM, function()
    local later = ChannelNow()
    if later ~= "none" then Tell(later) end
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

-- Seconds between two whispers now: WHISPER_INTERVAL idle, longer by the
-- same budget and throttle cut as the channel
function Transport.WhisperInterval()
  local idle = 1 / (Transport.FULL_RATE * Transport.BUDGET.idle)
  return Transport.WHISPER_INTERVAL * Transport.Interval() / idle
end

-- Wait(): seconds until the next message may go, counted from the last
-- send on its route, so a message queued just after a send never follows
-- it at once (two sends a frame apart drew ChannelThrottle in game,
-- 2026-09-26)
function Transport.Wait()
  local now = Seam("Clock")
  if not now then return 0 end
  local item = queue[1]
  if item and WhisperTo(item) then
    return lastWhisper and math.max(0, lastWhisper + Transport.WhisperInterval() - now) or 0
  end
  if not lastSent then return 0 end
  return math.max(0, lastSent + Transport.Interval() - now)
end

-- Sends the oldest message; returns the delay before the next one, or nil
-- to stop (empty, paused, or no route and no channel)
local function SendOne()
  local item = queue[1]
  if not item then return nil end
  local target = WhisperTo(item)
  local index = not target and Transport.ChannelIndex()
  if not target and not index then
    tally.noChannel = tally.noChannel + 1
    Host.Log("Curator send held: no whisper route and not in the %s channel (%d waiting)", Curator.Const.CHANNEL_NAME, #queue)
    return nil
  end
  local ok, result
  if target then
    ok, result = pcall(Transport.seams.Send, Curator.Const.PREFIX, item.text, "WHISPER", target)
  else
    ok, result = pcall(Transport.seams.Send, Curator.Const.PREFIX, item.text, "CHANNEL", index)
  end
  result = ok and result or nil
  local kind = item.text:sub(1, 1)
  local sentMsg = Protocol.Decode(item.text)
  if DataWorthLogging(sentMsg) then
    Host.Log("Curator sent %s %s: %s", Transport.Describe(sentMsg), target and ("by whisper to " .. target) or ("on /" .. index),
      ok and tostring(result) or "error")
  end
  if target then
    lastWhisper = Seam("Clock")
    tally.whispered = tally.whispered + 1
  else
    lastSent = Seam("Clock")
  end
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
  if result == RESULT.CHANNEL_THROTTLE then
    -- the game may still deliver it: slow down, never send it twice
    scale = scale / 2
    recoverAt = (Seam("Clock") or 0) + Transport.BACKOFF
    Host.Log("Curator send throttled by the channel (8): %s may still arrive; the rate is halved", kind)
  elseif result ~= RESULT.SUCCESS and target then
    -- a whisper the game refused: once more over the channel
    item.channel = true
    tally.fallback = tally.fallback + 1
    Host.Log("Curator whisper to %s refused (%s): %s goes over the channel instead", target, tostring(result), kind)
    return Transport.Wait()
  end
  table.remove(queue, 1)
  if result ~= RESULT.SUCCESS and result ~= RESULT.CHANNEL_THROTTLE then
    Host.Log("Curator send refused (%s): %s", tostring(result), kind)
  end
  if item.onSent then pcall(item.onSent, result) end
  if (result == RESULT.SUCCESS or result == RESULT.CHANNEL_THROTTLE) and Transport.LOCAL_ECHO then
    Transport.seams.After(0, function() Transport.Echo(item.text) end)
  end
  return #queue > 0 and Transport.Wait() or nil
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
  local kind = text:sub(1, 1)
  if kind ~= "D" or #queue == 1 then
    Host.Log("Curator queued %s%s (%d characters); %d waiting, sending %s", kind, first and " first" or "", #text, #queue,
      paused and "paused" or tostring(Transport.Activity()))
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
  if prefix ~= Curator.Const.PREFIX then return false end
  -- a route test (/rec curator ping): counted above by chat type, handled by Ping.lua's own receivers
  if type(text) == "string" and text:sub(1, 4) == "RCT~" then return false end
  if channel == "CHANNEL" then
    -- the channel's name comes 4th after the sender; none from the loopback
    local name = select(4, ...)
    local ours = Curator.Const.CHANNEL_NAME:lower()
    if type(name) == "string" and name ~= "" and not name:lower():find(ours, 1, true) then
      Host.Log("Curator message from %s ignored: it came on the channel %s, not %s", tostring(sender), name, Curator.Const.CHANNEL_NAME)
      return false
    end
  elseif channel ~= "WHISPER" then
    Host.Log("Curator message from %s ignored: it came by %s, not a whisper or the %s channel", tostring(sender), tostring(channel),
      Curator.Const.CHANNEL_NAME)
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
-- result code: 0 is success, 11 the addon chat lockdown; how many went by
-- whisper, and how many whispers went again on the channel) and received (from
-- others, its own messages coming back from the server, those handed over
-- by LOCAL_ECHO, and every message with the prefix by the chat type it came
-- with, before any filter), and how often no channel was found
function Transport.Tally()
  return ("sent %s (results %s; %d by whisper, %d whispers sent again on the channel); received %s; own back %s; echoed locally %s; handed over without the channel %s; with the prefix by chat type %s; no channel %d; lockdowns %d; queued %d%s")
    :format(Counts(tally.sent), Counts(tally.results), tally.whispered or 0, tally.fallback or 0, Counts(tally.got), Counts(tally.own),
      Counts(tally.echo), Counts(tally.handed), Counts(tally.raw), tally.noChannel, tally.lockdowns, #queue, paused and "; paused" or "")
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

-- A character that just joined the curator community joins the hidden
-- channel a moment later
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
-- the routes, the channel state and the tally (a fresh session's when state is nil) and
-- returns what it replaced, so the loopback sets the live ones aside for a
-- scripted run and puts them back after it. Tables are handed over, never
-- wiped. Only sync tests swap, so no real send is due while they run.
-------------------------------------------------------------------------------
Transport._test = {}
function Transport._test.Swap(state)
  local old = { queue = queue, pumping = pumping, paused = paused, scale = scale, recoverAt = recoverAt, lastSent = lastSent,
    lastWhisper = lastWhisper, routes = routes, joinTried = joinTried, community = community, channelState = channelState, tally = tally }
  state = state or { queue = {}, pumping = false, paused = false, scale = 1, recoverAt = 0, routes = {},
    tally = { sent = {}, results = {}, got = {}, own = {}, raw = {}, echo = {}, handed = {}, noChannel = 0, lockdowns = 0,
      whispered = 0, fallback = 0 } }
  queue, pumping, paused, scale, recoverAt, lastSent = state.queue, state.pumping, state.paused, state.scale, state.recoverAt, state.lastSent
  lastWhisper, routes, joinTried = state.lastWhisper, state.routes or {}, state.joinTried
  community, channelState, tally = state.community, state.channelState, state.tally
  return old
end
