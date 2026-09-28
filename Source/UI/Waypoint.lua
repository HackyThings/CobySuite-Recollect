-------------------------------------------------------------------------------
-- UI.Waypoint: a key that sets a map waypoint to the vendor the audit panel
-- names (Alt+W by default; the settings window changes or turns it off)
--
-- While the panel shows an item with a known vendor (UI.UsedFor's first
-- vendor: a currency it names, or a vendor that takes or sells it), the key
-- is bound to a hidden button with SetOverrideBindingClick, and the binding
-- is cleared when the panel hides: CobySniper's pattern
-- (CobySniper/Source/Buy/Main.lua). Binding calls are blocked in combat, so
-- none is made there: a panel first shown in combat has no key (its hint
-- says "after combat") until PLAYER_REGEN_ENABLED binds it for the panel
-- still showing, and a clear that falls in combat waits for that event. A
-- key bound before combat keeps serving a panel shown in it, so its queued
-- clear is dropped. The button reads the target when clicked, so a key
-- already bound is left alone: a bag slot's tooltip, set again 5 times a
-- second, makes no binding calls. Arm says whether the key is live, and the
-- panel names it only then.
--
-- The button sets the waypoint as Blizzard's own map click and /mappin do
-- (WaypointLocationDataProvider.lua): C_Map.CanSetUserWaypointOnMap, then
-- C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(...)) and
-- C_SuperTrack.SetSuperTrackedUserWaypoint(true). A map that takes no
-- waypoint (a city's inner map) is climbed to its parent, the position moved
-- through world coordinates. It never opens the world map: that path writes
-- map state from addon code (contract rule 29).
--
-- With TomTom loaded and the waypoint_provider option on "auto" (the
-- default; Cobanyte, 2026-09-28), the waypoint goes to TomTom instead, through
-- its own TomTom:AddWaypoint(mapID, x, y, { title, from }), which takes the
-- map it is given (no climbing). A TomTom call that fails falls back to the
-- game's pin. Other navigation addons that take TomTom's calls work the same.
-------------------------------------------------------------------------------
local Waypoint = {}
Recollect.UI.Waypoint = Waypoint

local Try = Recollect.Utilities.Try
local Config = Recollect.Config

local BUTTON_NAME = "RecollectWaypointButton"
local MAX_CLIMB = 4

local seams = {
  CanSet = function(mapID) return C_Map.CanSetUserWaypointOnMap(mapID) end,
  Point = function(mapID, x, y) return UiMapPoint.CreateFromCoordinates(mapID, x, y) end,
  Set = function(point) return C_Map.SetUserWaypoint(point) end,
  SuperTrack = function() return C_SuperTrack.SetSuperTrackedUserWaypoint(true) end,
  MapInfo = function(mapID) return C_Map.GetMapInfo(mapID) end,
  WorldPos = function(mapID, x, y) return C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y)) end,
  MapPos = function(continentID, worldPos, mapID) return C_Map.GetMapPosFromWorldPos(continentID, worldPos, mapID) end,
  InCombat = function() return InCombatLockdown() end,
  -- TomTom (an optional addon): its global and its AddWaypoint, or nil
  TomTom = function()
    local tomtom = rawget(_G, "TomTom")
    return type(tomtom) == "table" and type(tomtom.AddWaypoint) == "function" and tomtom or nil
  end,
  Bind = function(owner, key) SetOverrideBindingClick(owner, true, key, BUTTON_NAME) end,
  Clear = function(owner) ClearOverrideBindings(owner) end,
}

local target = nil        -- the waypoint the key sets now
local bound = false
local boundKey = nil      -- the key bound now ("ALT-W")
local clearAfterCombat = false
local button

-- The configured key ("ALT-W"), or nil when the key is turned off
function Waypoint.Key()
  if Config.Get(Config.Options.WAYPOINT_ENABLED) == false then return nil end
  local key = Config.Get(Config.Options.WAYPOINT_KEY)
  return type(key) == "string" and key ~= "" and key or nil
end

-- "ALT-W" as "Alt+W" (CobySuite.Utilities.FormatKeyText, as the settings show keys)
function Waypoint.KeyText(key)
  return CobySuite_Recollect.Utilities.FormatKeyText(key)
end

-- The panel's line for a waypoint, or nil when the key is off; afterCombat
-- when combat keeps the key from being bound until it ends
function Waypoint.HintText(waypoint, afterCombat)
  local key = Waypoint.Key()
  if not key or type(waypoint) ~= "table" then return nil end
  local zone = waypoint.zone or ("map " .. tostring(waypoint.mapID))
  local when = afterCombat and " after combat" or ""
  return ("%s%s: waypoint to %s in %s"):format(Waypoint.KeyText(key), when, waypoint.what or "the vendor", zone)
end

-- The position on mapID, or on the nearest parent map that takes a waypoint:
-- mapID, x, y or nil
function Waypoint.Placeable(mapID, x, y)
  for _ = 1, MAX_CLIMB do
    local okCan, can = Try(seams.CanSet, mapID)
    if okCan and can == true then return mapID, x, y end
    local okInfo, info = Try(seams.MapInfo, mapID)
    local parent = okInfo and type(info) == "table" and info.parentMapID
    if not parent or parent == 0 then return nil end
    local okWorld, continentID, worldPos = Try(seams.WorldPos, mapID, x, y)
    if not okWorld or not continentID or not worldPos then return nil end
    local okMap, _, mapPos = Try(seams.MapPos, continentID, worldPos, parent)
    if not okMap or type(mapPos) ~= "table" then return nil end
    mapID, x, y = parent, mapPos.x, mapPos.y
  end
  return nil
end

-- Whether TomTom is loaded (it has AddWaypoint)
function Waypoint.TomTomLoaded()
  local ok, tomtom = pcall(seams.TomTom)
  return ok and tomtom ~= nil
end

-- Whether a waypoint goes to TomTom now: the option and TomTom loaded
function Waypoint.UsesTomTom()
  if Config.Get(Config.Options.WAYPOINT_PROVIDER) == "game" then return false end
  return Waypoint.TomTomLoaded()
end

-- Set(waypoint, provider): TomTom's or the game's map pin, as the option
-- says (Waypoint.UsesTomTom), or as provider picks ("tomtom", "game": the
-- item details menu's choice). Returns true and "TomTom" or "map" on
-- success, else false and why
function Waypoint.Set(waypoint, provider)
  if type(waypoint) ~= "table" then return false, "no vendor known" end
  local tomtom
  if provider == "tomtom" then tomtom = Waypoint.TomTomLoaded()
  elseif provider == "game" then tomtom = false
  else tomtom = Waypoint.UsesTomTom() end
  if tomtom and tonumber(waypoint.mapID) and tonumber(waypoint.x) and tonumber(waypoint.y) then
    local tomtom = seams.TomTom()
    local ok = pcall(tomtom.AddWaypoint, tomtom, waypoint.mapID, waypoint.x, waypoint.y,
      { title = waypoint.what or "Recollect", from = "Recollect", persistent = false })
    if ok then return true, "TomTom" end
  end
  local mapID, x, y = Waypoint.Placeable(waypoint.mapID, waypoint.x, waypoint.y)
  if not mapID then return false, "that map takes no waypoint" end
  local okPoint, point = Try(seams.Point, mapID, x, y)
  if not okPoint or not point then return false, "the waypoint could not be made" end
  local okSet, wasSet = Try(seams.Set, point)
  if not okSet or wasSet == false then return false, "the game did not set the waypoint" end
  pcall(seams.SuperTrack)
  return true, "map"
end

local function Unbind()
  if not bound then return end
  if seams.InCombat() then
    clearAfterCombat = true
    return
  end
  pcall(seams.Clear, button)
  bound, boundKey, clearAfterCombat = false, nil, false
end

-- The panel shows a waypoint (or nil): bind the key out of combat, or unbind.
-- Returns live (the key sets this waypoint now) and afterCombat (a key is
-- set but combat keeps it unbound until it ends)
function Waypoint.Arm(waypoint)
  target = waypoint
  local key = waypoint and Waypoint.Key()
  if not key then
    Unbind()
    return false, false
  end
  if bound and boundKey == key then
    clearAfterCombat = false   -- it serves this panel: a clear queued in combat by an earlier one is dropped
    return true, false
  end
  if seams.InCombat() then return false, true end
  if bound then pcall(seams.Clear, button) end
  local ok = pcall(seams.Bind, button, key)
  bound, boundKey, clearAfterCombat = ok, ok and key or nil, false
  return bound, false
end

function Waypoint.Disarm()
  target = nil
  Unbind()
end

-- Combat is over: bind the key for the panel still showing a vendor, else
-- run the clear that waited for this
local function OnCombatEnded()
  if target then
    Waypoint.Arm(target)
  elseif clearAfterCombat then
    Unbind()
  end
end

local function OnClick()
  if not target then return end
  local ok, why = Waypoint.Set(target)
  if ok then
    Recollect.Utilities.Message(("Waypoint set to %s in %s."):format(target.what or "the vendor", target.zone or "that zone"))
  else
    Recollect.Utilities.Message.Warn("No waypoint: " .. tostring(why) .. ".")
  end
end

button = CreateFrame("Button", BUTTON_NAME, UIParent)
button:Hide()
button:SetScript("OnClick", OnClick)
button:RegisterEvent("PLAYER_REGEN_ENABLED")
button:SetScript("OnEvent", OnCombatEnded)

Waypoint._test = {
  seams = seams,
  Click = OnClick,
  CombatEnded = OnCombatEnded,
  -- The live state, to save before a suite scripts it and restore after
  State = function()
    return { target = target, bound = bound, boundKey = boundKey, clearAfterCombat = clearAfterCombat }
  end,
  SetState = function(saved)
    saved = type(saved) == "table" and saved or {}
    target, bound, boundKey = saved.target, saved.bound == true, saved.boundKey
    clearAfterCombat = saved.clearAfterCombat == true
  end,
  Reset = function() target, bound, boundKey, clearAfterCombat = nil, false, nil, false end,
}
