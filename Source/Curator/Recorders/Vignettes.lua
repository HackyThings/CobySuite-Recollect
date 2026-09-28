-------------------------------------------------------------------------------
-- Curator recorder: rare NPC positions from the map's vignettes
--
-- A vignette is the game's own marker for a rare, a treasure or an event.
-- VIGNETTE_MINIMAP_UPDATED (vignetteGUID, onMinimap) with onMinimap true
-- reads one; entering the world or a new zone sweeps every vignette the map
-- has (C_VignetteInfo.GetVignettes), at most once per SWEEP_GAP seconds.
-- A vignette is read only when its object is a creature (its objectGUID, a
-- "Creature-" GUID: never a treasure's object) that isn't dead, at most once
-- per READ_GAP seconds per vignette; its position is read on the player's
-- current map (C_Map.GetBestMapForUnit, C_VignetteInfo.GetVignettePosition).
-- Only the NPC ID, the map and x, y are kept: never the vignette's name,
-- its type or anything else of GetVignetteInfo's.
--
-- The position goes to the NPC position comparison (NpcPosition.Commit,
-- Compare.Position): near the shipped position confirms ("p:<npc>" stamp),
-- far on the same map is a conflict with the quest state, on another map
-- compared in world coordinates. An NPC with no shipped position is never
-- added: the shipped data has no index of the creatures it names as drop
-- sources (the c codes hang off each item, and nothing maps an NPC to them
-- short of scanning every bucket), so a rare with no shipped place gives
-- nothing yet.
--
-- Out of combat only. Only while curator mode may record, and never while a
-- test run scripts the client. Client reads go through Vignettes.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local NpcPosition = Curator.Recorders.NpcPosition

local Vignettes = {}
Curator.Recorders.Vignettes = Vignettes

Vignettes.READ_GAP = 60    -- seconds between two reads of one vignette
Vignettes.SWEEP_GAP = 10   -- seconds between two sweeps

Vignettes.seams = {
  List = function() return C_VignetteInfo.GetVignettes() end,
  -- the vignette's object and whether it is dead: nothing else of its info
  -- (its name stays here)
  Object = function(vignetteGUID)
    local info = C_VignetteInfo.GetVignetteInfo(vignetteGUID)
    if info then return info.objectGUID, info.isDead end
  end,
  Position = function(vignetteGUID, mapID)
    local position = C_VignetteInfo.GetVignettePosition(vignetteGUID, mapID)
    if position then return position:GetXY() end
  end,
  Map = function() return C_Map.GetBestMapForUnit("player") end,
  InCombat = function() return InCombatLockdown() end,
  Clock = function() return GetTime() end,
}

local readAt = {}     -- [vignetteGUID] = when it was last read
local sweptAt = nil   -- when the last sweep ran

local function Seam(name, ...)
  local ok, a, b = pcall(Vignettes.seams[name], ...)
  if not ok or Host.IsSecret(a) or Host.IsSecret(b) then return nil end
  return a, b
end

local function InCombat()
  local ok, value = pcall(Vignettes.seams.InCombat)
  return not ok or Host.IsSecret(value) or value == true
end

local function Now()
  local now = Seam("Clock")
  return type(now) == "number" and now or nil
end

-- Capture(vignetteGUID): the rare's NPC and position, read now, as
-- { npc, mapID, x, y }, or nil
function Vignettes.Capture(vignetteGUID)
  local objectGUID, isDead = Seam("Object", vignetteGUID)
  if isDead ~= false then return nil end
  local npc = NpcPosition.NpcID(objectGUID)
  if not npc or not tostring(objectGUID):find("^Creature%-") then return nil end
  local mapID = Seam("Map")
  if type(mapID) ~= "number" or mapID <= 0 then return nil end
  local x, y = Seam("Position", vignetteGUID, mapID)
  if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
  if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return { npc = npc, mapID = mapID, x = x, y = y }
end

-- Read(vignetteGUID): one vignette, at most once per READ_GAP seconds;
-- true when a position was captured (compared in a later frame)
function Vignettes.Read(vignetteGUID)
  if not Curator.Main.MayRecord() or InCombat() then return false end
  if type(vignetteGUID) ~= "string" or Host.IsSecret(vignetteGUID) then return false end
  local now = Now()
  if not now then return false end
  local at = readAt[vignetteGUID]
  if at and now - at < Vignettes.READ_GAP then return false end
  readAt[vignetteGUID] = now
  local capture = Vignettes.Capture(vignetteGUID)
  NpcPosition.Commit(capture, false)
  return capture ~= nil
end

-- Sweep(): every vignette on the map, at most once per SWEEP_GAP seconds;
-- how many positions were captured
function Vignettes.Sweep()
  if not Curator.Main.MayRecord() or InCombat() then return 0 end
  local now = Now()
  if not now or (sweptAt and now - sweptAt < Vignettes.SWEEP_GAP) then return 0 end
  sweptAt = now
  for guid, at in pairs(readAt) do
    if now - at >= Vignettes.READ_GAP then readAt[guid] = nil end
  end
  local ok, list = pcall(Vignettes.seams.List)
  if not ok or type(list) ~= "table" or Host.IsSecret(list) then return 0 end
  local captured = 0
  for _, guid in ipairs(list) do
    if Vignettes.Read(guid) then captured = captured + 1 end
  end
  return captured
end

-- VIGNETTE_MINIMAP_UPDATED (vignetteGUID, onMinimap)
function Vignettes.OnMinimap(vignetteGUID, onMinimap)
  if Host.IsSecret(onMinimap) or onMinimap ~= true then return false end
  return Vignettes.Read(vignetteGUID)
end

function Vignettes.Reset()
  wipe(readAt)
  sweptAt = nil
end

local handlers = {
  VIGNETTE_MINIMAP_UPDATED = function(vignetteGUID, onMinimap) Vignettes.OnMinimap(vignetteGUID, onMinimap) end,
  ZONE_CHANGED_NEW_AREA = function() Vignettes.Sweep() end,
  PLAYER_ENTERING_WORLD = function() Vignettes.Sweep() end,
}

-- The event frame's dispatch (a test run scripting the client reads nothing)
function Vignettes.OnEvent(event, ...)
  if Curator.Main.IsScripted() or not handlers[event] then return end
  local ok, err = pcall(handlers[event], ...)
  if not ok then Host.Log("Vignette recorder %s failed: %s", event, tostring(err)) end
end

local frame = CreateFrame("Frame")
for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...) Vignettes.OnEvent(event, ...) end)
