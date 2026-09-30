-------------------------------------------------------------------------------
-- Curator.Membership: who is in the community, with what role (curator
-- spec, "Roles and the community")
--
-- The role map is keyed by "Name-NormalizedRealm", the form chat gives a
-- sender. Each member's name comes from their GUID through
-- GetPlayerInfoByGUID, which answers nothing for a player this client has
-- never cached (its docs: MayReturnNothing); then from the roster's own
-- ClubMemberInfo.name when that is a plain string (it may be a Kstring,
-- which is never used). Either way the realm is normalized as chat
-- normalizes it (no spaces or hyphens). Seen in game 2026-09-28: a friend's
-- client had no name for the author, so every presence check went
-- unanswered. A message from a sender the map doesn't know asks for a fresh
-- read (RefreshSoon), since the GUID may be cached by then. It is read only when the roster is ready
-- (C_Club.FocusMembers, then C_Club.AreMembersReady) and outside the Chat
-- restriction (the roster reads go secret then); the last good map stays in
-- use meanwhile, and a refresh is redone when the restriction lifts. It is
-- refreshed on the club events of this community only (joins, leaves and
-- roles at once; presence and member details within a few seconds). Each
-- entry keeps its GUID, every member is also kept by GUID named or not
-- (Members), and Watch lets the author's side hear every whole read (the
-- dev console's live roster and member watch). Roles: 1 Owner, 2 Leader, 3 Moderator,
-- 4 Member (Enum.ClubRoleIdentifier); only Owner and Leader may pull, and
-- only their messages are honoured as the author's.
--
-- Client calls go through Membership.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Transport = Curator.Transport

local Membership = {}
Curator.Membership = Membership

Membership.ROLE = { OWNER = 1, LEADER = 2, MODERATOR = 3, MEMBER = 4 }
Membership.ROLE_NAMES = { [1] = "Owner", [2] = "Leader", [3] = "Moderator", [4] = "Member" }
-- Presence: Away and Busy count as online; OnlineMobile can't answer addon messages
Membership.PRESENCE = { [1] = "online", [2] = "mobile", [3] = "offline", [4] = "online", [5] = "online" }

local READY_TRIES = 10

Membership.seams = {
  Members = function(clubId) return C_Club.GetClubMembers(clubId) end,
  MemberInfo = function(clubId, memberId) return C_Club.GetMemberInfo(clubId, memberId) end,
  Focus = function(clubId) return C_Club.FocusMembers(clubId) end,
  Ready = function(clubId) return C_Club.AreMembersReady(clubId) end,
  PlayerInfo = function(guid)
    local _, _, _, _, _, name, realm = GetPlayerInfoByGUID(guid)
    return name, realm
  end,
  After = function(delay, fn) C_Timer.After(delay, fn) end,
}

local roster = {}          -- [name] = { name, role, presence, nameFrom, isSelf, guid }
local byGuid = {}          -- [guid] = { guid, name (nil while unreadable), role, presence }: every member, named or not
local rosterAt = nil       -- when the map was last read whole
local refreshing = false
local lastSummary = nil    -- the last "members read" log line, so an unchanged read logs nothing
local watchers = {}        -- Watch(fn): called with Members() after every whole read

local function Secret(value)
  return Host.IsSecret(value) or (issecrettable and type(value) == "table" and issecrettable(value))
end

-- A realm as chat carries it in a sender's name: no spaces or hyphens
-- ("Area 52" is "Area52", "Azjol-Nerub" is "AzjolNerub")
function Membership.NormalRealm(realm)
  return (tostring(realm):gsub("[%s%-]", ""))
end

-- "Name" or "Name-Realm" (a realm as any source writes it) in the map's form
local function Normalized(name, realm)
  if realm == nil or realm == "" then return Transport.Canonical(name) end
  return name .. "-" .. Membership.NormalRealm(realm)
end

-- The roster's own name for a member when it is a plain string: never a
-- Kstring or anything with an escape in it, never secret
local function RosterName(info)
  local name = info.name
  if type(name) ~= "string" or Secret(name) or name == "" or name:find("|", 1, true) then return nil end
  local base, realm = name:match("^([^%-]+)%-(.+)$")
  if base then return Normalized(base, realm) end
  return Transport.Canonical(name)
end

-- A member's canonical name, and where it came from ("guid" or "roster"), or nil
local function MemberName(info)
  if type(info.guid) == "string" and not Secret(info.guid) then
    local ok, name, realm = pcall(Membership.seams.PlayerInfo, info.guid)
    if ok and type(name) == "string" and not Secret(name) and name ~= "" and not Secret(realm) then
      return Normalized(name, type(realm) == "string" and realm or ""), "guid"
    end
  end
  local name = RosterName(info)
  if name then return name, "roster" end
  return nil
end

-- Reads the whole roster now; false when it can't be read (not ready,
-- restricted, secret, not a member)
function Membership.Read()
  local found = Transport.Community()
  if not found then
    roster, byGuid, rosterAt = {}, {}, nil
    Host.Log("Curator members: not read, this character isn't in the community")
    return false
  end
  local okReady, ready = pcall(Membership.seams.Ready, found.clubId)
  if not okReady or ready ~= true then return false end
  local ok, members = pcall(Membership.seams.Members, found.clubId)
  if not ok or type(members) ~= "table" or Secret(members) then
    Host.Log("Curator members: the member list can't be read now (%s)", ok and "secret or empty" or "error")
    return false
  end
  local map, guids, unnamed = {}, {}, 0
  for _, memberId in ipairs(members) do
    local okInfo, info = pcall(Membership.seams.MemberInfo, found.clubId, memberId)
    if not okInfo or type(info) ~= "table" or Secret(info) then
      Host.Log("Curator members: a member's info can't be read now (%s)", okInfo and "secret or missing" or "error")
      return false
    end
    local name, from = MemberName(info)
    if not name then unnamed = unnamed + 1 end
    local guid = type(info.guid) == "string" and not Secret(info.guid) and info.guid ~= "" and info.guid or nil
    local role = not Secret(info.role) and info.role or nil
    local presence = Membership.PRESENCE[info.presence] or "unknown"
    if name and role then
      map[name] = { name = name, role = role, presence = presence, nameFrom = from, isSelf = info.isSelf == true, guid = guid }
    end
    if guid then guids[guid] = { guid = guid, name = name, role = role, presence = presence } end
  end
  roster, byGuid, rosterAt, Membership.unnamed = map, guids, GetServerTime(), unnamed
  local authors, count = {}, 0
  for _, entry in pairs(map) do
    count = count + 1
    if entry.role == Membership.ROLE.OWNER or entry.role == Membership.ROLE.LEADER then
      authors[#authors + 1] = ("%s (%s, name from %s, %s)"):format(entry.name, Membership.ROLE_NAMES[entry.role],
        tostring(entry.nameFrom), entry.presence)
    end
  end
  table.sort(authors)
  local summary = ("%d named, %d with no readable name; who may collect: %s"):format(count, unnamed,
    #authors > 0 and table.concat(authors, "; ") or "nobody")
  if summary ~= lastSummary then Host.Log("Curator members read: %s", summary) end
  lastSummary = summary
  for _, fn in ipairs(watchers) do pcall(fn, Membership.Members()) end
  return true
end

-- Refresh(): asks for the roster and reads it when it is ready (tried a few
-- times a second apart); nothing while the Chat restriction is on
function Membership.Refresh()
  if refreshing or not Curator.Main.Available() then return end
  local found = Transport.Community()
  if not found then
    roster, byGuid, rosterAt = {}, {}, nil
    return
  end
  if Transport.Activity() == "lockdown" then
    Host.Log("Curator members: not read during the addon chat restriction; read again when it lifts")
    return
  end
  refreshing = true
  pcall(Membership.seams.Focus, found.clubId)
  local tries = 0
  local function Try()
    tries = tries + 1
    local read = Membership.Read()
    if read or tries >= READY_TRIES then
      if not read then Host.Log("Curator members: the list wasn't ready after %d tries; the last good one stays", tries) end
      refreshing = false
      if Membership.OnChanged then pcall(Membership.OnChanged) end
      return
    end
    Membership.seams.After(1, Try)
  end
  Try()
end

-- The role of a sender ("Name-Realm"), or nil when not in the map
function Membership.RoleOf(name)
  local entry = name and roster[name]
  return entry and entry.role or nil
end

-- Whether a sender's messages count as the author's (Owner or Leader)
function Membership.MayPull(name)
  local role = Membership.RoleOf(name)
  return role == Membership.ROLE.OWNER or role == Membership.ROLE.LEADER
end

function Membership.Entry(name)
  return name and roster[name] or nil
end

-- GuidOf(name): a member's roster GUID as the last read gave it, or nil
function Membership.GuidOf(name)
  local entry = name and roster[name]
  return entry and entry.guid or nil
end

-- IsCollector(name): whether a sender is one of the author's collector
-- characters (Const.COLLECTORS, by roster GUID) holding Owner or Leader now
function Membership.IsCollector(name)
  local guid = Membership.GuidOf(name)
  return guid ~= nil and Curator.Const.COLLECTORS[guid] == true and Membership.MayPull(name)
end

-- Roster(): a list of entries, sorted by name
function Membership.Roster()
  local out = {}
  for _, entry in pairs(roster) do out[#out + 1] = entry end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function Membership.ReadAt()
  return rosterAt
end

-- Members(): every member of the last whole read by GUID, named or not
-- ({ [guid] = { guid, name, role, presence } }, a copy)
function Membership.Members()
  local out = {}
  for guid, entry in pairs(byGuid) do out[guid] = { guid = guid, name = entry.name, role = entry.role, presence = entry.presence } end
  return out
end

-- Watch(fn): fn(Members()) after every whole read of the roster (never after
-- a failed one, so a read that couldn't finish never looks like members
-- leaving); returns a function that stops it
function Membership.Watch(fn)
  watchers[#watchers + 1] = fn
  return function()
    for i = #watchers, 1, -1 do
      if watchers[i] == fn then table.remove(watchers, i) end
    end
  end
end

-- The by-GUID view of a role map a test puts in place: its entries that name a GUID
local function GuidsOf(map)
  local out = {}
  for name, entry in pairs(map or {}) do
    if type(entry) == "table" and entry.guid then
      out[entry.guid] = { guid = entry.guid, name = entry.name or name, role = entry.role, presence = entry.presence }
    end
  end
  return out
end

-- SetRoster(map): the role map, as a test scripts it
function Membership.SetRoster(map)
  roster, rosterAt, refreshing = map or {}, GetServerTime(), false
  byGuid = GuidsOf(roster)
end

-- Swap(map, at, unnamed): puts a role map in place (with how many members
-- had no readable name, 0 by default) and returns the one it replaced, when
-- it was read and its unnamed count (a test puts the real one back with them)
function Membership.Swap(map, at, unnamed)
  local previous, previousAt, previousUnnamed = roster, rosterAt, Membership.unnamed
  roster, rosterAt, Membership.unnamed = map or {}, at, unnamed or 0
  byGuid = GuidsOf(roster)
  return previous, previousAt, previousUnnamed
end

local refresh = CobySuite_Recollect.Utilities.Coalesce(0.5, function() Membership.Refresh() end)

-- RefreshSoon(): a fresh read in a moment (a message from a sender the map
-- doesn't know: their name may be readable now)
function Membership.RefreshSoon()
  refresh:Call()
end

-- A member's presence or details changing: read again, less eagerly (a busy
-- community sends many)
local refreshLater = CobySuite_Recollect.Utilities.Coalesce(5, function() Membership.Refresh() end)

-- The events that change the roster: true reads again soon, "later" within
-- a few seconds. A club event about another club (the guild is one) is
-- ignored once the community is known
local events = {
  PLAYER_ENTERING_WORLD = true, CLUB_ADDED = true, CLUB_REMOVED = true, CLUB_MEMBER_ADDED = true,
  CLUB_MEMBER_REMOVED = true, CLUB_MEMBER_ROLE_UPDATED = true, CLUB_MEMBERS_UPDATED = true,
  ADDON_RESTRICTION_STATE_CHANGED = true, CLUB_MEMBER_UPDATED = "later", CLUB_MEMBER_PRESENCE_UPDATED = "later",
}

-- Whether a club event concerns the community (or can't tell)
local function Ours(event, clubId)
  if event:sub(1, 5) ~= "CLUB_" or event == "CLUB_ADDED" or event == "CLUB_REMOVED" then return true end
  local found = Transport.Community()
  return not found or clubId == nil or Secret(clubId) or clubId == found.clubId
end

local frame = CreateFrame("Frame")
for event in pairs(events) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, clubId)
  if not Ours(event, clubId) then return end
  if events[event] == "later" then refreshLater:Call() else refresh:Call() end
end)
