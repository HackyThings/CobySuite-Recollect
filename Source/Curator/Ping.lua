-------------------------------------------------------------------------------
-- Curator.Ping: which route carries curator messages between two players,
-- and how much it carries, in one run (Cobanyte, 2026-09-28: the author's
-- presence checks, sent on the community channel with result 0, never
-- reached a friend's game, and the friend's announcement never reached the
-- author's; "make this count with a TON of tests", and the author runs
-- nothing: his client answers by itself)
--
-- /rec curator ping (a curator's side) runs everything, about five minutes,
-- then prints a report; every step is in the debug log (CURATOR):
--   0. A snapshot of this client: character, realm and connected realms,
--      faction, group, instance, the addon chat restriction, the prefix,
--      the community, its channel (what GetChannelName says of it), the
--      custom test channel, the roster (who is online, with what role) and
--      Battle.net friends in it.
--   1. Pings over every route, three rounds 10 seconds apart; every client
--      that gets one answers with a pong the same way (round-trip timed).
--   2. The routes a pong came back on work. On each:
--      sizes (texts of 50 to 300 characters: which arrive, what a too-long
--      one returns), contents (plain text, every printable character, UTF-8,
--      pipes, Base64: each answered with its length and checksum), a burst
--      of 30 as fast as the game takes them and 30 at 4 a second, each
--      answered with a tally.
--   3. On the best working route: 60 data-sized messages at the real send
--      rate (a pull's pace), then a reverse burst: the other side sends 40
--      back as fast as it can.
--   4. The report.
-- The author's side answers all of it with no command: an Owner or Leader's
-- client joins the custom test channel after login (tried 20, 40 and 60
-- seconds in, as the member list may not be read yet) and on the first test
-- message it gets; any other client answers on the route a message came by
-- but never joins a channel. /rec curator pong joins it by hand.
--
-- The routes (Ping.ROUTES): the community channel by number, number as
-- text, name, and the logged send; the custom channel by number, name, and
-- the logged send; a whisper to each online member, plain and logged; the
-- party; Battle.net game data to friends in the community. Test messages
-- ride the curator prefix, always "RCT~<tag>~<route>~...", which the curator
-- protocol ignores; no data, no IDs, nothing about the player. Client calls
-- go through Ping.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host

local Ping = {}
Curator.Ping = Ping

Ping.MARK = "RCT~"
Ping.CHANNEL = "RecollectCurPing"
Ping.ROUNDS = { 6, 16, 26 }
Ping.DECIDE_AT = 40
Ping.SIZES = { 50, 150, 230, 250, 254, 255, 256, 300 }
Ping.BURST_FAST, Ping.BURST_PACED, Ping.PACED_RATE = 30, 30, 4
Ping.REAL_COUNT, Ping.REVERSE_COUNT = 60, 40
Ping.PAYLOAD = 200
Ping.QUIET = 4
Ping.LISTEN_FOR = 1800
Ping.MAX_TARGETS = 10

Ping.ROUTES = {
  { key = "comm", label = "community channel, number" },
  { key = "commText", label = "community channel, number as text" },
  { key = "commName", label = "community channel, by name" },
  { key = "commLogged", label = "community channel, logged send" },
  { key = "custom", label = "custom channel, number" },
  { key = "customName", label = "custom channel, by name" },
  { key = "customLogged", label = "custom channel, logged send" },
  { key = "whisper", label = "whisper", targeted = true },
  { key = "whisperLogged", label = "whisper, logged send", targeted = true },
  { key = "party", label = "party" },
  { key = "bnet", label = "Battle.net game data", targeted = true },
  { key = "guild", label = "guild" },
  { key = "guildLogged", label = "guild, logged send" },
}
-- The order a real transport would prefer them in
Ping.PREFERENCE = { 1, 5, 8, 11, 12, 10, 2, 3, 4, 6, 7, 9, 13 }

Ping.CONTENTS = {
  { label = "plain words", text = "Recollect curator test 12345" },
  { label = "every printable character", text = (function()
    local chars = {}
    for b = 32, 126 do chars[#chars + 1] = string.char(b) end
    return table.concat(chars)
  end)() },
  { label = "UTF-8", text = "\195\164\195\182\195\188 \195\169 \230\188\162\229\173\151 \226\128\162" },
  { label = "pipes", text = "a|b||c|cFFFF0000red|r" },
  { label = "Base64", text = "QmFzZTY0K3NhbXBsZS90ZXh0PT0=" },
}

Ping.seams = {
  Send = function(prefix, text, chatType, target) return C_ChatInfo.SendAddonMessage(prefix, text, chatType, target) end,
  SendLogged = function(prefix, text, chatType, target)
    return C_ChatInfo.SendAddonMessageLogged(prefix, text, chatType, target)
  end,
  SendBN = function(id, prefix, text) return C_BattleNet.SendGameData(id, prefix, text) end,
  Join = function(name) return JoinTemporaryChannel(name) end,
  Leave = function(name) return LeaveChannelByName(name) end,
  ChannelIndex = function(name)
    local index = GetChannelName(name)
    return index
  end,
  ChannelInfo = function(target) return GetChannelName(target) end,
  After = function(delay, fn) C_Timer.After(delay, fn) end,
  Clock = function() return GetTime() end,
  InGroup = function() return IsInGroup(LE_PARTY_CATEGORY_HOME) end,
  InGuild = function() return IsInGuild() end,
  Profile = function() return debugprofilestop() end,
  InInstance = function() return IsInInstance() end,
  Faction = function() return UnitFactionGroup("player") end,
  Realms = function() return C_AutoComplete.GetAutoCompleteRealms() end,
  PrefixRegistered = function(prefix) return C_ChatInfo.IsAddonMessagePrefixRegistered(prefix) end,
  NumBNFriends = function() return BNGetNumFriends() end,
  BNGameAccounts = function(friend) return C_BattleNet.GetFriendNumGameAccounts(friend) end,
  BNGameAccount = function(friend, account) return C_BattleNet.GetFriendGameAccountInfo(friend, account) end,
  BNAccountByID = function(id) return C_BattleNet.GetGameAccountInfoByID(id) end,
}

local state
function Ping.Reset()
  local listening = state and state.listening
  state = {
    running = false, listening = listening, finished = false,
    sent = {},       -- [route] = { [result] = n }
    heard = {},      -- [route] = { [sender] = { pings, pongs, via } }
    own = {},        -- [route] = n: own messages back
    pingAt = {},     -- [route .. "~" .. round] = clock
    rtt = {},        -- [route] = { seconds, ... }
    sizes = {},      -- [route] = { [length] = { sent, got } }
    contents = {},   -- [route] = { [n] = { sent, got, ok } }
    bursts = {},     -- [route] = { [phase] = { sent = {}, back = {} } }
    incoming = {},   -- tallies of bursts from others
    working = nil, best = nil,
    env = {},
  }
end
Ping.Reset()
function Ping.State() return state end

local function Seam(name, ...)
  local ok, a, b, c, d = pcall(Ping.seams[name], ...)
  if not ok then return nil, a end
  if Host.IsSecret(a) then return nil, "secret" end
  return a, b, c, d
end

local function Bump(tbl, key)
  key = tostring(key)
  tbl[key] = (tbl[key] or 0) + 1
end

local function Now() return Seam("Clock") or 0 end
local startedAt

-- Every test line carries the seconds since the test started (or "idle"
-- on the answering side)
local function Log(fmt, ...)
  local stamp = startedAt and ("[t+%.2f] "):format(Now() - startedAt) or "[answering] "
  Host.Log(stamp .. fmt, ...)
end

local function Checksum(text)
  local ok, sum = pcall(Curator.Protocol.Checksum, text)
  return ok and sum or "?"
end

-------------------------------------------------------------------------------
-- Routes and targets
-------------------------------------------------------------------------------
local function CustomIndex()
  local index = Seam("ChannelIndex", Ping.CHANNEL)
  return type(index) == "number" and index > 0 and index or nil
end

-- BNet friends whose character is an online community member: { [name] = gameAccountID }
function Ping.BNetMembers()
  local out = {}
  local members = {}
  for _, entry in ipairs(Curator.Membership.Roster()) do members[entry.name] = true end
  local count = Seam("NumBNFriends") or 0
  for friend = 1, math.min(tonumber(count) or 0, 200) do
    local accounts = Seam("BNGameAccounts", friend) or 0
    for account = 1, math.min(tonumber(accounts) or 0, 10) do
      local info = Seam("BNGameAccount", friend, account)
      if type(info) == "table" and info.characterName and info.gameAccountID and info.isOnline ~= false then
        local realm = info.realmName and Curator.Membership.NormalRealm(info.realmName) or nil
        local name = realm and realm ~= "" and (info.characterName .. "-" .. realm) or Curator.Transport.Canonical(info.characterName)
        if name and members[name] then out[name] = info.gameAccountID end
      end
    end
  end
  return out
end

-- Targets(route): who a targeted route goes to ({ { label, target } })
local function Targets(route)
  local key = Ping.ROUTES[route].key
  local out, me = {}, Curator.Transport.Self()
  if key == "bnet" then
    for name, id in pairs(Ping.BNetMembers()) do
      if name ~= me and #out < Ping.MAX_TARGETS then out[#out + 1] = { label = name, target = id } end
    end
  else
    for _, entry in ipairs(Curator.Membership.Roster()) do
      if entry.name ~= me and entry.presence == "online" and #out < Ping.MAX_TARGETS then
        out[#out + 1] = { label = entry.name, target = entry.name }
      end
    end
  end
  return out
end

-- SendRoute(route, text, target): one message; returns the result as text
function Ping.SendRoute(route, text, target)
  local key = Ping.ROUTES[route].key
  local prefix, T = Curator.Const.PREFIX, Curator.Transport
  -- the community's own stream channel (Transport.ChannelIndex is the hidden
  -- channel since 2026-09-28, which the custom probes cover)
  local community = T.Community()
  local index = community and community.channelName and Seam("ChannelInfo", community.channelName)
  if type(index) ~= "number" or index <= 0 then index = nil end
  local result, err
  if key:sub(1, 4) == "comm" then
    if not (community and index) then return "no community channel" end
    if key == "comm" then result, err = Seam("Send", prefix, text, "CHANNEL", index)
    elseif key == "commText" then result, err = Seam("Send", prefix, text, "CHANNEL", tostring(index))
    elseif key == "commName" then result, err = Seam("Send", prefix, text, "CHANNEL", community.channelName)
    else result, err = Seam("SendLogged", prefix, text, "CHANNEL", index) end
  elseif key:sub(1, 6) == "custom" then
    local custom = CustomIndex()
    if not custom then return "custom channel not joined" end
    if key == "custom" then result, err = Seam("Send", prefix, text, "CHANNEL", custom)
    elseif key == "customName" then result, err = Seam("Send", prefix, text, "CHANNEL", Ping.CHANNEL)
    else result, err = Seam("SendLogged", prefix, text, "CHANNEL", custom) end
  elseif key == "whisper" then
    result, err = Seam("Send", prefix, text, "WHISPER", target)
  elseif key == "whisperLogged" then
    result, err = Seam("SendLogged", prefix, text, "WHISPER", target)
  elseif key == "party" then
    if not Seam("InGroup") then return "not in a group" end
    result, err = Seam("Send", prefix, text, "PARTY")
  elseif key == "bnet" then
    if not target then return "no Battle.net friend in the community online" end
    result, err = Seam("SendBN", target, prefix, text)
  elseif key == "guild" or key == "guildLogged" then
    if not Seam("InGuild") then return "not in a guild" end
    result, err = Seam(key == "guild" and "Send" or "SendLogged", prefix, text, "GUILD")
  end
  if result == nil then return "error: " .. tostring(err) end
  return tostring(result)
end

-- Broadcast(route, text, counter): a route's message to everyone it goes to
local function Broadcast(route, text, counter)
  local tag = text:match("^RCT~(%u+)~") or "?"
  local verbose = tag ~= "BURST" or text:match("^RCT~BURST~%d+~%a+~(%d+)~") == "1"
  if Ping.ROUTES[route].targeted then
    local targets = Targets(route)
    if #targets == 0 then Bump(counter, "nobody to send to") end
    for _, t in ipairs(targets) do
      local result = Ping.SendRoute(route, text, t.target)
      Bump(counter, result)
      if verbose then Log("Curator test send %s on route %d to %s (%d characters): %s", tag, route, t.label, #text, result) end
    end
  else
    local result = Ping.SendRoute(route, text)
    Bump(counter, result)
    if verbose then Log("Curator test send %s on route %d (%d characters): %s", tag, route, #text, result) end
  end
end

local function Message(tag, route, ...)
  local parts = { "RCT", tag, tostring(route) }
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  return table.concat(parts, "~")
end

-------------------------------------------------------------------------------
-- The environment snapshot
-------------------------------------------------------------------------------
function Ping.Environment()
  local T, M = Curator.Transport, Curator.Membership
  local lines = {}
  local function Add(fmt, ...) lines[#lines + 1] = fmt:format(...) end
  local versions = Host.Versions()
  Add("Recollect %s, database %s, character %s, faction %s", tostring(versions.addon), tostring(versions.data),
    tostring(T.Self()), tostring(Seam("Faction")))
  local realms = Seam("Realms")
  Add("Connected realms: %s", type(realms) == "table" and (#realms > 0 and table.concat(realms, ", ") or "none") or "can't be read")
  local inInstance, kind = Seam("InInstance")
  Add("Group: %s; instance: %s (%s); addon chat: %s", Seam("InGroup") and "yes" or "no", tostring(inInstance), tostring(kind),
    tostring(T.Activity()))
  Add("Prefix %s registered: %s", Curator.Const.PREFIX, tostring(Seam("PrefixRegistered", Curator.Const.PREFIX)))
  local community, index = T.Community(), T.ChannelIndex()
  if community then
    local id, name, instanceID, isCommunities = Seam("ChannelInfo", index or community.channelName)
    Add("Community channel: %s at /%s; GetChannelName says id %s, name %s, instance %s, communities channel %s",
      community.channelName, tostring(index), tostring(id), tostring(name), tostring(instanceID), tostring(isCommunities))
  else
    Add("Community: not found on this character")
  end
  Add("Custom test channel %s: %s", Ping.CHANNEL, CustomIndex() and ("/" .. CustomIndex()) or "not joined")
  local roster = {}
  for _, entry in ipairs(M.Roster()) do
    roster[#roster + 1] = ("%s (%s, %s)"):format(entry.name, M.ROLE_NAMES[entry.role] or "?", entry.presence)
  end
  Add("Members (%s): %s", M.ReadAt() and "read" or "not read yet", #roster > 0 and table.concat(roster, ", ") or "none")
  local bn = {}
  for name in pairs(Ping.BNetMembers()) do bn[#bn + 1] = name end
  table.sort(bn)
  Add("Battle.net friends in the community: %s", #bn > 0 and table.concat(bn, ", ") or "none")
  local counts = T.Counts()
  local got = {}
  for kind2, n in pairs(counts.got or {}) do got[#got + 1] = kind2 .. " " .. n end
  table.sort(got)
  Add("Curator protocol messages got this session: %s", #got > 0 and table.concat(got, ", ") or "none")
  return lines
end

-------------------------------------------------------------------------------
-- Local checks: everything on this client a pull depends on, each timed
-------------------------------------------------------------------------------
local function Timed(label, fn)
  local before = Seam("Profile") or 0
  local ok, a, b = pcall(fn)
  local ms = (Seam("Profile") or 0) - before
  if ok then
    Log("Curator local check %s: %s (%.1f ms)", label, tostring(a), ms)
  else
    Log("Curator local check %s FAILED: %s (%.1f ms)", label, tostring(a), ms)
  end
  state.local_ = state.local_ or {}
  state.local_[#state.local_ + 1] = ("%s: %s"):format(label, ok and tostring(a) or ("FAILED " .. tostring(a)))
  return ok, a, b
end

function Ping.LocalTests()
  local P, T, M, S = Curator.Protocol, Curator.Transport, Curator.Membership, Curator.Sharing
  Timed("curator mode", function()
    return ("on %s, may record %s, answering as %s, curator ID %s"):format(tostring(Curator.Main.IsEnabled()),
      tostring(Curator.Main.MayRecord()), S and S.State() or "?", tostring(Curator.Main.CuratorID()))
  end)
  Timed("data files", function()
    local v = Host.Versions()
    return ("ok %s, database %s, format %s, addon %s"):format(tostring(v.ok), tostring(v.data), tostring(v.format), tostring(v.addon))
  end)
  Timed("message format", function()
    local kinds, bad = { "H", "R", "O", "Q", "S", "N", "K", "V", "X", "L" }, {}
    for _, kind in ipairs(kinds) do
      local n = P.FIELDS and P.FIELDS[kind] or 2
      local fields = {}
      for i = 1, n do fields[i] = "f" .. i end
      local text = P.Encode(kind, P.LIVE, P.AUTHOR, unpack(fields))
      local back = text and P.Decode(text)
      if not (back and back.kind == kind) then bad[#bad + 1] = kind end
    end
    return #bad == 0 and ("every message type encodes and decodes (%d)"):format(#kinds) or ("broken: " .. table.concat(bad, ", "))
  end)
  Timed("encoding library", function()
    local E = C_EncodingUtil
    return E and ("C_EncodingUtil present: CBOR %s, compress %s, Base64 %s"):format(tostring(E.SerializeCBOR ~= nil),
      tostring(E.CompressString ~= nil), tostring(E.EncodeBase64 ~= nil)) or "C_EncodingUtil missing"
  end)
  Timed("sample pack", function()
    local sample = { curator = "x", records = { r1 = { fact = "v:1:i:2:sold", value = "1", kind = "addition", rev = 1, ctx = { 2 } } },
      confirms = {}, contexts = { { class = 1 } }, quests = {} }
    local payload, why = P.Pack(sample)
    if not payload then return "pack failed: " .. tostring(why) end
    local back = P.Unpack(payload)
    return ("%d bytes packed, unpacked %s"):format(#payload, back and back.records and back.records.r1 and "intact" or "BROKEN")
  end)
  Timed("this character's collection", function()
    local snapshot = S.Snapshot()
    local count = CobySuite_Recollect.Utilities.TableCount
    local payload, why = P.Pack(snapshot)
    if not payload then return "pack failed: " .. tostring(why) end
    local chunks = P.Chunks(payload, "q0000000000")
    return ("%d findings, %d stamps, %d notes: %d bytes packed in %d parts of up to %d characters, checksum %s"):format(
      count(snapshot.records), count(snapshot.confirms), count(snapshot.notes or {}), #payload, #chunks,
      P.ChunkSize and P.ChunkSize("q0000000000") or 0, P.Checksum(payload))
  end)
  Timed("store", function()
    local c = Curator.Store.Counts()
    local n = Curator.Notes and Curator.Notes.Counts() or {}
    return ("%d findings (%d pending), %d stamps, %d bytes; notes: %s flags, %s feedback, %s errors, %s unsent"):format(c.records,
      c.pending, c.stamps, c.bytes, tostring(n.flags), tostring(n.feedback), tostring(n.errors), tostring(n.pending))
  end)
  Timed("transport", function()
    local ok, interval = pcall(T.Interval)
    return ("self %s, member %s, channel /%s, activity %s, send interval %s s, paused %s"):format(tostring(T.Self()),
      tostring(T.IsMember()), tostring(T.ChannelIndex()), tostring(T.Activity()), ok and tostring(interval) or "?",
      tostring(T.IsPaused and T.IsPaused()))
  end)
  Timed("members", function()
    local authors = {}
    for _, entry in ipairs(M.Roster()) do
      if entry.role == M.ROLE.OWNER or entry.role == M.ROLE.LEADER then
        authors[#authors + 1] = ("%s %s %s"):format(entry.name, M.ROLE_NAMES[entry.role], entry.presence)
      end
    end
    return ("%d read, may this character collect: %s; who may collect: %s"):format(#M.Roster(), tostring(M.MayPull(T.Self())),
      #authors > 0 and table.concat(authors, ", ") or "nobody")
  end)
  Timed("whisper to self", function()
    local me = T.Self()
    return ("plain %s, logged %s (own back counts on routes 8 and 9)"):format(
      Ping.SendRoute(8, Message("PING", 8, 0), me), Ping.SendRoute(9, Message("PING", 9, 0), me))
  end)
end

-------------------------------------------------------------------------------
-- The test (the curator's side)
-------------------------------------------------------------------------------
function Ping.Round(round)
  Log("Curator test round %d: community channel /%s, custom channel %s, members %d", round,
    tostring(Curator.Transport.ChannelIndex()), CustomIndex() and ("/" .. CustomIndex()) or "not joined",
    #Curator.Membership.Roster())
  for route = 1, #Ping.ROUTES do
    state.sent[route] = state.sent[route] or {}
    state.pingAt[route .. "~" .. round] = Now()
    Broadcast(route, Message("PING", route, round), state.sent[route])
  end
  local parts = {}
  for route = 1, #Ping.ROUTES do
    local r = {}
    for result, n in pairs(state.sent[route]) do r[#r + 1] = result .. " x" .. n end
    table.sort(r)
    parts[#parts + 1] = route .. ": " .. table.concat(r, ", ")
  end
  Log("Curator test round %d sent; results so far by route: %s", round, table.concat(parts, "; "))
end

local function Sequence(steps, done)
  local i = 0
  local function Next()
    i = i + 1
    local step = steps[i]
    if not step then return done() end
    local ok, err = pcall(step, Next)
    if not ok then
      Log("Curator test step failed: %s", tostring(err))
      Next()
    end
  end
  Next()
end

-- Sends count messages on a route, interval seconds apart (0: one a frame)
local function Stream(route, tag, phase, count, interval, size, counter, done)
  local pad = string.rep("x", size or Ping.PAYLOAD)
  local seq = 0
  local function Next()
    seq = seq + 1
    Broadcast(route, Message(tag, route, phase, seq, count, pad), counter)
    if seq < count then Ping.seams.After(interval, Next) else done() end
  end
  Next()
end

local function Results(tbl)
  local parts = {}
  for result, n in pairs(tbl or {}) do parts[#parts + 1] = tostring(result) .. " x" .. n end
  table.sort(parts)
  return #parts > 0 and table.concat(parts, ", ") or "nothing"
end

local function RouteSteps(route)
  local steps = {}
  steps[#steps + 1] = function(next)
    state.sizes[route] = {}
    local i = 0
    local function One()
      i = i + 1
      local length = Ping.SIZES[i]
      if not length then return Ping.seams.After(2, next) end
      local head = Message("SIZE", route, length, "")
      local text = head .. string.rep("s", math.max(0, length - #head))
      local counter = {}
      Broadcast(route, text, counter)
      state.sizes[route][length] = { sent = Results(counter), length = #text }
      Log("Curator test route %d size %d: sent %s", route, #text, Results(counter))
      Ping.seams.After(0.3, One)
    end
    One()
  end
  steps[#steps + 1] = function(next)
    state.contents[route] = {}
    for n, content in ipairs(Ping.CONTENTS) do
      local counter = {}
      Broadcast(route, Message("BYTES", route, n, content.text), counter)
      state.contents[route][n] = { sent = Results(counter), expect = #content.text .. "/" .. Checksum(content.text) }
    end
    Log("Curator test route %d contents sent (%d kinds)", route, #Ping.CONTENTS)
    Ping.seams.After(3, next)
  end
  for _, phase in ipairs({ "fast", "paced" }) do
    steps[#steps + 1] = function(next)
      state.bursts[route] = state.bursts[route] or {}
      local record = { sent = {}, back = nil }
      state.bursts[route][phase] = record
      local count = phase == "fast" and Ping.BURST_FAST or Ping.BURST_PACED
      local interval = phase == "fast" and 0 or 1 / Ping.PACED_RATE
      Stream(route, "BURST", phase, count, interval, Ping.PAYLOAD, record.sent, function()
        Log("Curator test route %d burst %s: %d sent, results %s", route, phase, count, Results(record.sent))
        Ping.seams.After(phase == "fast" and 2 or Ping.QUIET + 3, next)
      end)
    end
  end
  return steps
end

local function BestSteps(route)
  return {
    function(next)
      state.bursts[route] = state.bursts[route] or {}
      local record = { sent = {}, back = nil }
      state.bursts[route].real = record
      local ok, interval = pcall(Curator.Transport.Interval)
      interval = ok and tonumber(interval) or 0.5
      state.realInterval = interval
      Log("Curator test route %d real rate: %d messages %.2f s apart", route, Ping.REAL_COUNT, interval)
      Stream(route, "BURST", "real", Ping.REAL_COUNT, interval, Ping.PAYLOAD, record.sent, function()
        Ping.seams.After(Ping.QUIET + 3, next)
      end)
    end,
    function(next)
      state.reverse = { asked = Now(), counter = {} }
      Broadcast(route, Message("PULLTEST", route, Ping.REVERSE_COUNT), state.reverse.counter)
      Log("Curator test route %d: asked for a reverse burst of %d (%s)", route, Ping.REVERSE_COUNT, Results(state.reverse.counter))
      Ping.seams.After(15, function()
        local e = state.reverse.entry
        if e then
          Log("Curator test route %d reverse burst: got %d of %d (%d bytes) over %.1f s, first %.1f s after asking", route,
            e.got, e.total or 0, e.bytes, math.max(0, e.last - e.first), e.first - state.reverse.asked)
        else
          Log("Curator test route %d reverse burst: nothing arrived in 15 s", route)
        end
        next()
      end)
    end,
  }
end

local function Finish()
  state.running, state.finished = false, true
  for _, line in ipairs(Ping.Environment()) do Log("Curator test environment (end): %s", line) end
  local lines = Ping.Lines()
  Host.Print("Recollect curator test finished. Summary:")
  for _, line in ipairs(lines) do
    Host.Print("  " .. line)
    Log("Curator test report: %s", line)
  end
  if Host.OpenDebugLog and Host.OpenDebugLog() then
    Host.Print("The debug log is open: press Copy All and send it to the author.")
  else
    Host.Print("Now copy the whole log for the author: /rec debug, then Copy All.")
  end
  startedAt = nil
end

local function Decide()
  local working = {}
  for _, route in ipairs(Ping.PREFERENCE) do
    for from, entry in pairs(state.heard[route] or {}) do
      if (entry.pongs or 0) > 0 and (not state.target or tostring(from):lower() == state.target:lower()) then
        working[#working + 1] = route
        break
      end
    end
  end
  state.working, state.best = working, working[1]
  if #working == 0 then
    Log("Curator test: no route brought a pong back")
    return Finish()
  end
  local names = {}
  for _, route in ipairs(working) do names[#names + 1] = route .. " (" .. Ping.ROUTES[route].label .. ")" end
  Log("Curator test: working routes %s; best %d", table.concat(names, ", "), working[1])
  Host.Print("Recollect curator test: some routes work; testing how much they carry (a few minutes)...")
  local steps = {}
  for _, route in ipairs(working) do
    for _, step in ipairs(RouteSteps(route)) do steps[#steps + 1] = step end
  end
  for _, step in ipairs(BestSteps(working[1])) do steps[#steps + 1] = step end
  Sequence(steps, Finish)
end

-- Start(target): the whole test; target ("Name-Realm", optional) makes a
-- route count as working only when that player answered, since every
-- Recollect client answers test pings and another member's answer proves
-- nothing about the one being tested
function Ping.Start(target)
  if state.running then
    Host.Print("Recollect: the curator test is already running; it prints its summary when done.")
    return false
  end
  Ping.Reset()
  if type(target) == "string" and target ~= "" then
    state.target = Curator.Transport.Canonical(target) or target
    Log("Curator test target: %s (a route counts only when they answer)", state.target)
  end
  state.running = true
  startedAt = Now()
  Seam("Join", Ping.CHANNEL)
  Log("Curator test started (joined %s)", Ping.CHANNEL)
  Ping.seams.After(3, function()
    for _, line in ipairs(Ping.Environment()) do Log("Curator test environment: %s", line) end
    local ok, err = pcall(Ping.LocalTests)
    if not ok then Log("Curator test local checks failed: %s", tostring(err)) end
  end)
  for round, delay in ipairs(Ping.ROUNDS) do
    Ping.seams.After(delay, function()
      local ok, err = pcall(Ping.Round, round)
      if not ok then Log("Curator test round %d failed: %s", round, tostring(err)) end
    end)
  end
  Ping.seams.After(Ping.DECIDE_AT, function()
    local ok, err = pcall(Decide)
    if not ok then
      Log("Curator test failed while deciding: %s", tostring(err))
      Finish()
    end
  end)
  Host.Print("Recollect curator test started: it tries 13 ways to reach the author, then measures the ones that work, "
    .. "and prints a summary in about 5 minutes. Keep playing (out of instances); nothing to click.")
  return true
end

-- Listen(): join the custom test channel (automatic for the author, and on
-- the first test message any client gets)
function Ping.Listen(why)
  if CustomIndex() then return false end
  state.listening = true
  Seam("Join", Ping.CHANNEL)
  Log("Curator test: joined %s to answer tests (%s)", Ping.CHANNEL, tostring(why or "asked"))
  Ping.seams.After(Ping.LISTEN_FOR, function()
    if state.running then return end
    state.listening = false
    Seam("Leave", Ping.CHANNEL)
    Log("Curator test: left %s", Ping.CHANNEL)
  end)
  return true
end

-------------------------------------------------------------------------------
-- Answering (every client)
-------------------------------------------------------------------------------
-- The way back: the route it came by, to its sender when targeted
local function Reply(route, from, replyTarget, text)
  local result = Ping.SendRoute(route, text, Ping.ROUTES[route].targeted and replyTarget or nil)
  return result
end

local function SendBack(key)
  local entry = state.incoming[key]
  if not entry or entry.backSent then return end
  if Now() - entry.last < Ping.QUIET then
    Ping.seams.After(1, function() SendBack(key) end)
    return
  end
  entry.backSent = true
  local seconds = math.max(0, entry.last - entry.first)
  local result = Reply(entry.route, entry.from, entry.replyTarget,
    Message("BACK", entry.route, entry.phase, entry.got, entry.total, entry.bytes, ("%.1f"):format(seconds)))
  Log("Curator test route %d %s burst from %s: got %d of %d (%d bytes over %.1f s); tally sent back: %s", entry.route,
    entry.phase, entry.from, entry.got, entry.total or 0, entry.bytes, seconds, result)
end

local function Tally(route, phase, from, replyTarget, total, bytes, via)
  local key = from .. "|" .. route .. "|" .. phase
  local now = Now()
  local entry = state.incoming[key]
  if not entry or entry.backSent then
    entry = { got = 0, total = tonumber(total), bytes = 0, first = now, last = now, route = route, phase = phase,
      from = from, replyTarget = replyTarget }
    state.incoming[key] = entry
    Log("Curator test route %d %s burst from %s: first message by %s", route, phase, from, via)
    if phase ~= "reverse" then Ping.seams.After(Ping.QUIET, function() SendBack(key) end) end
  end
  entry.got, entry.bytes, entry.last = entry.got + 1, entry.bytes + bytes, now
  return entry
end

local function ReverseBurst(route, from, replyTarget, count)
  local pad = string.rep("r", Ping.PAYLOAD)
  local counter, seq = {}, 0
  local function Next()
    seq = seq + 1
    Bump(counter, Reply(route, from, replyTarget, Message("RBURST", route, "reverse", seq, count, pad)))
    if seq < count then Ping.seams.After(0, Next) else
      Log("Curator test route %d: reverse burst of %d sent to %s, results %s", route, count, from, Results(counter))
    end
  end
  Next()
end

local handlers = {}

handlers.PING = function(route, fields, from, replyTarget, via)
  state.heard[route] = state.heard[route] or {}
  local entry = state.heard[route][from] or { pings = 0, pongs = 0 }
  entry.pings, entry.via = entry.pings + 1, via
  state.heard[route][from] = entry
  local result = Reply(route, from, replyTarget, Message("PONG", route, fields[1] or "?"))
  Log("Curator test route %d (%s) ping round %s from %s by %s; pong sent: %s", route, Ping.ROUTES[route].label,
    tostring(fields[1]), from, via, result)
end

handlers.PONG = function(route, fields, from, _, via)
  state.heard[route] = state.heard[route] or {}
  local entry = state.heard[route][from] or { pings = 0, pongs = 0 }
  entry.pongs, entry.via = entry.pongs + 1, via
  state.heard[route][from] = entry
  local sentAt = state.pingAt[route .. "~" .. tostring(fields[1])]
  local rtt = sentAt and (Now() - sentAt) or nil
  if rtt then
    state.rtt[route] = state.rtt[route] or {}
    table.insert(state.rtt[route], rtt)
  end
  Log("Curator test route %d (%s): pong for round %s from %s by %s%s", route, Ping.ROUTES[route].label, tostring(fields[1]),
    from, via, rtt and (" in %.2f s"):format(rtt) or "")
end

handlers.SIZE = function(route, fields, from, replyTarget, via, text)
  local result = Reply(route, from, replyTarget, Message("SIZEACK", route, fields[1] or "?", #text))
  Log("Curator test route %d size %s from %s: arrived with %d characters by %s; answered: %s", route, tostring(fields[1]),
    from, #text, via, result)
end

handlers.SIZEACK = function(route, fields, from)
  local length = tonumber(fields[1])
  local record = length and state.sizes[route] and state.sizes[route][length]
  if record then record.got = (record.got and record.got .. ", " or "") .. from .. " got " .. tostring(fields[2]) end
  Log("Curator test route %d size %s: %s got %s characters", route, tostring(fields[1]), from, tostring(fields[2]))
end

handlers.BYTES = function(route, fields, from, replyTarget, via, text)
  local n = tonumber(fields[1])
  local body = text:match("^RCT~BYTES~%d+~%d+~(.*)$") or ""
  local result = Reply(route, from, replyTarget, Message("BYTESACK", route, n or "?", #body, Checksum(body)))
  Log("Curator test route %d content %s from %s: %d bytes, checksum %s, by %s; answered: %s", route, tostring(n), from,
    #body, Checksum(body), via, result)
end

handlers.BYTESACK = function(route, fields, from)
  local n = tonumber(fields[1])
  local record = n and state.contents[route] and state.contents[route][n]
  local got = tostring(fields[2]) .. "/" .. tostring(fields[3])
  if record then
    record.got, record.ok = got, got == record.expect
  end
  Log("Curator test route %d content %s (%s): %s got %s, expected %s", route, tostring(n),
    n and Ping.CONTENTS[n] and Ping.CONTENTS[n].label or "?", from, got, record and record.expect or "?")
end

handlers.BURST = function(route, fields, from, replyTarget, via, text)
  Tally(route, fields[1] or "?", from, replyTarget, fields[3], #text, via)
end

handlers.BACK = function(route, fields, from)
  local phase = fields[1] or "?"
  state.bursts[route] = state.bursts[route] or {}
  state.bursts[route][phase] = state.bursts[route][phase] or { sent = {} }
  state.bursts[route][phase].back = { got = tonumber(fields[2]), total = tonumber(fields[3]), bytes = tonumber(fields[4]),
    seconds = tonumber(fields[5]), from = from }
  Log("Curator test route %d %s burst: %s got %s of %s (%s bytes over %s s)", route, phase, from, tostring(fields[2]),
    tostring(fields[3]), tostring(fields[4]), tostring(fields[5]))
end

handlers.PULLTEST = function(route, fields, from, replyTarget)
  local count = math.min(tonumber(fields[1]) or 0, 100)
  Log("Curator test route %d: %s asked for a reverse burst of %d; sending", route, from, count)
  if count > 0 then ReverseBurst(route, from, replyTarget, count) end
end

handlers.RBURST = function(route, fields, from, replyTarget, via, text)
  local entry = Tally(route, "reverse", from, replyTarget, fields[3], #text, via)
  if state.reverse then state.reverse.entry = entry end
end

-- Received(text, chatType, sender, channelName, replyTarget): a test message
-- from another client (replyTarget: whom a targeted route answers)
function Ping.Received(text, chatType, sender, channelName, replyTarget)
  if type(text) ~= "string" or text:sub(1, #Ping.MARK) ~= Ping.MARK then return false end
  local fields = {}
  for field in (text:sub(#Ping.MARK + 1) .. "~"):gmatch("([^~]*)~") do fields[#fields + 1] = field end
  local tag, route = fields[1], tonumber(fields[2])
  if not (handlers[tag] and route and Ping.ROUTES[route]) then return true end
  local rest = {}
  for i = 3, #fields do rest[#rest + 1] = fields[i] end
  local from = tostring(sender)
  local via = tostring(chatType) .. (channelName and channelName ~= "" and (" on " .. tostring(channelName)) or "")
  if from == Curator.Transport.Self() then
    state.own[route] = (state.own[route] or 0) + 1
    if tag == "PING" then Log("Curator test route %d: own ping came back by %s", route, via) end
    return true
  end
  -- only a client that may collect joins the test channel by itself: another
  -- guild member with Recollect still answers, but is never joined to a channel
  if not state.running and not CustomIndex() and Curator.Membership.MayPull(Curator.Transport.Self()) then
    Ping.Listen("a test message arrived from " .. from)
  end
  local ok, err = pcall(handlers[tag], route, rest, from, replyTarget or from, via, text)
  if not ok then Log("Curator test handler %s failed: %s", tag, tostring(err)) end
  return true
end

-------------------------------------------------------------------------------
-- The report
-------------------------------------------------------------------------------
local function RttText(list)
  if not list or #list == 0 then return "" end
  local sum, low = 0, math.huge
  for _, v in ipairs(list) do sum, low = sum + v, math.min(low, v) end
  return (", round trip %.2f s best, %.2f s average"):format(low, sum / #list)
end

function Ping.Lines()
  if not next(state.sent) and not next(state.heard) and not next(state.incoming) then
    return { "Curator test: not run this session (/rec curator ping)" }
  end
  local out = {}
  if state.target then out[#out + 1] = "Target: " .. state.target .. " (routes count only when they answered)" end
  for _, line in ipairs(state.local_ or {}) do out[#out + 1] = "Local check " .. line end
  for route, def in ipairs(Ping.ROUTES) do
    local heard = {}
    for from, entry in pairs(state.heard[route] or {}) do
      heard[#heard + 1] = ("%s (%d pings, %d pongs, by %s)"):format(from, entry.pings or 0, entry.pongs or 0, tostring(entry.via))
    end
    table.sort(heard)
    out[#out + 1] = ("Route %d, %s: sent %s; heard %s; own back %d%s"):format(route, def.label, Results(state.sent[route]),
      #heard > 0 and table.concat(heard, ", ") or "nobody", state.own[route] or 0, RttText(state.rtt[route]))
    for length, record in pairs(state.sizes[route] or {}) do
      out[#out + 1] = ("  Size %d (%d characters): sent %s; %s"):format(length, record.length or 0, record.sent,
        record.got or "no answer")
    end
    for n, record in pairs(state.contents[route] or {}) do
      out[#out + 1] = ("  Content %s: sent %s; %s"):format(Ping.CONTENTS[n].label, record.sent,
        record.got and (record.ok and "arrived intact" or ("changed: got " .. record.got .. ", expected " .. record.expect))
          or "no answer")
    end
    for phase, burst in pairs(state.bursts[route] or {}) do
      local back = burst.back
      out[#out + 1] = ("  Burst %s: sent %s; %s"):format(phase, Results(burst.sent), back and back.got
        and ("%s got %d of %d (%d bytes over %.1f s)"):format(tostring(back.from), back.got, back.total or 0, back.bytes or 0,
          back.seconds or 0) or "no tally came back")
    end
  end
  for _, entry in pairs(state.incoming) do
    out[#out + 1] = ("Received route %d %s burst from %s: %d of %d (%d bytes over %.1f s)"):format(entry.route, entry.phase,
      entry.from, entry.got, entry.total or 0, entry.bytes, math.max(0, entry.last - entry.first))
  end
  if state.reverse then
    local e = state.reverse.entry
    out[#out + 1] = e and ("Reverse burst (the author's side sending): got %d of %d"):format(e.got, e.total or 0)
      or "Reverse burst (the author's side sending): nothing arrived"
  end
  if state.realInterval then out[#out + 1] = ("Real-rate run: messages %.2f s apart"):format(state.realInterval) end
  if state.working then
    local names = {}
    for _, route in ipairs(state.working) do names[#names + 1] = route .. " " .. Ping.ROUTES[route].label end
    out[#out + 1] = #names > 0 and ("Working routes, best first: %s"):format(table.concat(names, "; "))
      or "Working routes: none (no pong came back on any route)"
  end
  return out
end

-------------------------------------------------------------------------------
-- Events: the test's own receivers (the curator protocol ignores RCT~), and
-- the author's client joining the test channel after login
-------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
for _, event in ipairs({ "CHAT_MSG_ADDON", "CHAT_MSG_ADDON_LOGGED", "BN_CHAT_MSG_ADDON", "PLAYER_ENTERING_WORLD" }) do
  pcall(frame.RegisterEvent, frame, event)
end
local joinTries = { 20, 40, 60 }
local loginJoinStarted = false

local function TryLoginJoin(i)
  if CustomIndex() then return end
  local me = Curator.Transport.Self()
  if Curator.Membership.MayPull(me) then
    pcall(Ping.Listen, ("this character may collect (login try %d)"):format(i))
  elseif i < #joinTries then
    Ping.seams.After(joinTries[i + 1] - joinTries[i], function() TryLoginJoin(i + 1) end)
  else
    Host.Log("[answering] Curator test: %s may not collect, so it doesn't join the test channel", tostring(me))
  end
end

frame:SetScript("OnEvent", function(_, event, prefix, text, chatType, sender, ...)
  if event == "PLAYER_ENTERING_WORLD" then
    if loginJoinStarted then return end
    loginJoinStarted = true
    Ping.seams.After(joinTries[1], function() TryLoginJoin(1) end)
    return
  end
  for _, value in ipairs({ prefix, text, chatType, sender }) do
    if Host.IsSecret(value) then return end
  end
  if prefix ~= Curator.Const.PREFIX or type(text) ~= "string" or text:sub(1, #Ping.MARK) ~= Ping.MARK then return end
  local channelName = (select(4, ...))
  if Host.IsSecret(channelName) then channelName = nil end
  local ok, err = pcall(function()
    if event == "BN_CHAT_MSG_ADDON" then
      -- sender is the game account ID: named by the account's character
      local info = Seam("BNAccountByID", sender)
      local name = type(info) == "table" and info.characterName and (info.characterName .. "-" ..
        Curator.Membership.NormalRealm(info.realmName or "")) or ("bnet " .. tostring(sender))
      Ping.Received(text, "BNET", name, nil, sender)
    else
      local from = Curator.Transport.Canonical(sender) or tostring(sender)
      Ping.Received(text, event == "CHAT_MSG_ADDON_LOGGED" and (tostring(chatType) .. " logged") or chatType, from,
        channelName, from)
    end
  end)
  if not ok then Host.Log("Curator test receiver failed: %s", tostring(err)) end
end)
