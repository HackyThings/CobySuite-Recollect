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
-- refreshed on the club events. Roles: 1 Owner, 2 Leader, 3 Moderator,
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

local roster = {}          -- [name] = { name, role, presence, nameFrom, isSelf }
local rosterAt = nil       -- when the map was last read whole
local refreshing = false

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
    roster, rosterAt = {}, nil
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
  local map, unnamed = {}, 0
  for _, memberId in ipairs(members) do
    local okInfo, info = pcall(Membership.seams.MemberInfo, found.clubId, memberId)
    if not okInfo or type(info) ~= "table" or Secret(info) then
      Host.Log("Curator members: a member's info can't be read now (%s)", okInfo and "secret or missing" or "error")
      return false
    end
    local name, from = MemberName(info)
    if not name then unnamed = unnamed + 1 end
    if name and not Secret(info.role) then
      map[name] = { name = name, role = info.role, presence = Membership.PRESENCE[info.presence] or "unknown", nameFrom = from,
        isSelf = info.isSelf == true }
    end
  end
  roster, rosterAt, Membership.unnamed = map, GetServerTime(), unnamed
  local authors, count = {}, 0
  for _, entry in pairs(map) do
    count = count + 1
    if entry.role == Membership.ROLE.OWNER or entry.role == Membership.ROLE.LEADER then
      authors[#authors + 1] = ("%s (%s, name from %s, %s)"):format(entry.name, Membership.ROLE_NAMES[entry.role],
        tostring(entry.nameFrom), entry.presence)
    end
  end
  table.sort(authors)
  Host.Log("Curator members read: %d named, %d with no readable name; who may collect: %s", count, unnamed,
    #authors > 0 and table.concat(authors, "; ") or "nobody")
  return true
end

-- Refresh(): asks for the roster and reads it when it is ready (tried a few
-- times a second apart); nothing while the Chat restriction is on
function Membership.Refresh()
  if refreshing then return end
  local found = Transport.Community()
  if not found then
    roster, rosterAt = {}, nil
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

-- SetRoster(map): the role map, as a test scripts it
function Membership.SetRoster(map)
  roster, rosterAt, refreshing = map or {}, GetServerTime(), false
end

-- Swap(map, at): puts a role map in place and returns the one it replaced
-- with when it was read (a test puts the real one back with it)
function Membership.Swap(map, at)
  local previous, previousAt = roster, rosterAt
  roster, rosterAt = map or {}, at
  return previous, previousAt
end

local refresh = CobySuite_Recollect.Utilities.Coalesce(0.5, function() Membership.Refresh() end)

-- RefreshSoon(): a fresh read in a moment (a message from a sender the map
-- doesn't know: their name may be readable now)
function Membership.RefreshSoon()
  refresh:Call()
end

local events = {
  PLAYER_ENTERING_WORLD = true, CLUB_ADDED = true, CLUB_REMOVED = true, CLUB_MEMBER_ADDED = true,
  CLUB_MEMBER_REMOVED = true, CLUB_MEMBER_ROLE_UPDATED = true, CLUB_MEMBERS_UPDATED = true,
  ADDON_RESTRICTION_STATE_CHANGED = true,
}

local frame = CreateFrame("Frame")
for event in pairs(events) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function()
  refresh:Call()
end)
