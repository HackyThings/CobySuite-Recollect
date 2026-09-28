-------------------------------------------------------------------------------
-- Curator.Membership: who is in the community, with what role (curator
-- spec, "Roles and the community")
--
-- The role map is keyed by "Name-NormalizedRealm", built from each member's
-- GUID through GetPlayerInfoByGUID (ClubMemberInfo.name may be a Kstring and
-- is never trusted). It is read only when the roster is ready
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

local roster = {}          -- [name] = { name, role, presence, zone, level, classID, isSelf, guid }
local rosterAt = nil       -- when the map was last read whole
local refreshing = false

local function Secret(value)
  return Host.IsSecret(value) or (issecrettable and type(value) == "table" and issecrettable(value))
end

-- A member's canonical name from their GUID, or nil
local function MemberName(info)
  if type(info.guid) ~= "string" or Secret(info.guid) then return nil end
  local ok, name, realm = pcall(Membership.seams.PlayerInfo, info.guid)
  if not ok or type(name) ~= "string" or Secret(name) or name == "" then return nil end
  if type(realm) ~= "string" or Secret(realm) or realm == "" then return Transport.Canonical(name) end
  return name .. "-" .. realm
end

-- Reads the whole roster now; false when it can't be read (not ready,
-- restricted, secret, not a member)
function Membership.Read()
  local found = Transport.Community()
  if not found then
    roster, rosterAt = {}, nil
    return false
  end
  local okReady, ready = pcall(Membership.seams.Ready, found.clubId)
  if not okReady or ready ~= true then return false end
  local ok, members = pcall(Membership.seams.Members, found.clubId)
  if not ok or type(members) ~= "table" or Secret(members) then return false end
  local map = {}
  for _, memberId in ipairs(members) do
    local okInfo, info = pcall(Membership.seams.MemberInfo, found.clubId, memberId)
    if not okInfo or type(info) ~= "table" or Secret(info) then return false end
    local name = MemberName(info)
    if name and not Secret(info.role) then
      map[name] = { name = name, role = info.role, presence = Membership.PRESENCE[info.presence] or "unknown",
        zone = not Secret(info.zone) and info.zone or nil, level = not Secret(info.level) and info.level or nil,
        classID = not Secret(info.classID) and info.classID or nil, isSelf = info.isSelf == true, guid = info.guid }
    end
  end
  roster, rosterAt = map, GetServerTime()
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
  if Transport.Activity() == "lockdown" then return end
  refreshing = true
  pcall(Membership.seams.Focus, found.clubId)
  local tries = 0
  local function Try()
    tries = tries + 1
    if Membership.Read() or tries >= READY_TRIES then
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
