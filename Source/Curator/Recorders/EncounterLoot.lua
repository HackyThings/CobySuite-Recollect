-------------------------------------------------------------------------------
-- Curator recorder: boss loot by encounter (design
-- Recollect-New-Sources-2026-09-27; the shipped code D<encounter>, kind
-- journalDrop, and a boss's c<npc> code, which the build keeps in its place)
--
-- ENCOUNTER_LOOT_RECEIVED names the dungeon encounter (the ID ENCOUNTER_END
-- and BOSS_KILL give, not the Encounter Journal's) and the item looted,
-- for every group member (the boss banner shows others' loot from it).
-- Only arguments 1 and 2 are read: the item link, quantity, player name and
-- class are never touched. A bonus roll (BONUS_ROLL_RESULT with type
-- "item", the item ID from its link) counts for the last encounter that
-- ended in success (ENCOUNTER_END, success 1) within BONUS_WINDOW seconds.
--
-- One kill is one visit: the items of an encounter are gathered for
-- COMMIT_DELAY seconds from the first, then compared in a later frame.
-- Facts (the store's fact names; values are text):
--   e:<encounter>:i:<item>   looted from that dungeon encounter, value "1":
--                            an addition when the shipped data has no live
--                            D code whose journal encounter is that dungeon
--                            encounter (EJ_GetEncounterInfo's 7th return),
--                            and no live c code naming a boss the data maps
--                            (table J) to such a journal encounter. shipped:
--                            the item's D codes as "<journal>[|x]", or nil.
-- Every item is also handed to the items-with-no-information recorder as
-- seen at "e:<encounter>" (Compare.SawItem, the fact ni:<item>).
-- One stamp per visit, source "e:<encounter>", total 0: the item IDs the
-- shipped data knows there. A D code the journal can't map (no answer, or
-- a secret one) leaves the item unjudged: no addition, no stamp. A c code
-- whose boss isn't mapped is simply no match. Loot is chance: no not seen,
-- no conflicts.
--
-- Recorded in combat too (read in the event, compared later). Only while
-- curator mode may record, and never while a test run scripts the client.
-- Client reads go through EncounterLoot.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Store = Curator.Store
local Bags = Curator.Recorders.Bags

local EncounterLoot = {}
Curator.Recorders.EncounterLoot = EncounterLoot

EncounterLoot.BONUS_WINDOW = 90   -- seconds from a successful ENCOUNTER_END to a bonus roll
EncounterLoot.COMMIT_DELAY = 5    -- seconds a kill's loot is gathered before it is compared

EncounterLoot.seams = {
  -- the dungeon encounter ID of an Encounter Journal encounter (7th return)
  DungeonEncounter = function(journalID) return (select(7, EJ_GetEncounterInfo(journalID))) end,
  Clock = function() return GetTime() end,
  After = function(delay, fn) C_Timer.After(delay, fn) end,
}

local visits = {}     -- [encounterID] = { epoch, items = { [itemID] = true } }, gathering
local lastEnd = nil   -- { id, at }: the last encounter ended in success

-- The dungeon encounter a journal encounter is, or nil (kept once read: the
-- journal is client data and doesn't change within a session)
local dungeonOf = {}
local function Dungeon(journalID)
  if dungeonOf[journalID] then return dungeonOf[journalID] end
  local ok, id = pcall(EncounterLoot.seams.DungeonEncounter, journalID)
  if not ok or not Bags.PositiveID(id) then return nil end
  dungeonOf[journalID] = id
  return id
end

-- The item's D codes as text ("1234,1235|x"), or nil
local function CodesText(codes)
  local parts = {}
  for _, code in ipairs(codes) do parts[#parts + 1] = code.id .. (code.gone and "|x" or "") end
  return #parts > 0 and table.concat(parts, ",") or nil
end

-- Known(itemID, encounterID): true when the shipped data has the item at
-- that dungeon encounter, false when it doesn't, nil when a D code can't be
-- mapped (then nothing is recorded); and the item's D codes as text
function EncounterLoot.Known(itemID, encounterID)
  local codes = Host.CodesOf(itemID, "D")
  local unmapped = false
  for _, code in ipairs(codes) do
    if not code.gone then
      local dungeon = Dungeon(code.id)
      if dungeon == encounterID then return true end
      if not dungeon then unmapped = true end
    end
  end
  for _, code in ipairs(Host.CodesOf(itemID, "c")) do
    local journal = not code.gone and Host.EncounterOf(code.id)
    if journal and Dungeon(journal) == encounterID then return true end
  end
  if unmapped then return nil end
  return false, CodesText(codes)
end

-- Compare(encounterID, items, ctx): items = { [itemID] = true }, one kill's
-- loot; returns how many the shipped data knows there
function EncounterLoot.Compare(encounterID, items, ctx)
  local matched = {}
  for itemID in pairs(items) do
    Curator.Compare.SawItem(itemID, "e:" .. encounterID, ctx)
    local known, shipped = EncounterLoot.Known(itemID, encounterID)
    if known then
      matched[#matched + 1] = itemID
    elseif known == false then
      Store.Record("addition", ("e:%d:i:%d"):format(encounterID, itemID), "1", shipped, ctx)
    end
  end
  Store.Confirm("e:" .. encounterID, matched, 0, ctx)
  return #matched
end

-- The visit's commit: compared in a later frame, once
function EncounterLoot.Commit(encounterID, visit)
  if visits[encounterID] ~= visit then return end
  visits[encounterID] = nil
  if not Curator.Main.StillCurrent(visit.epoch) then return end
  Curator.Main.Defer(function()
    local matched = EncounterLoot.Compare(encounterID, visit.items, Curator.Context.Current())
    Host.Log("Encounter %d loot: %d items the data knows there", encounterID, matched)
  end)
end

-- Note(encounterID, itemID): one item looted from an encounter; true when kept
function EncounterLoot.Note(encounterID, itemID)
  if not Curator.Main.MayRecord() or not Bags.PositiveID(encounterID) or not Bags.PositiveID(itemID) then return false end
  local visit = visits[encounterID]
  if not visit then
    visit = { epoch = Curator.Main.Epoch(), items = {} }
    visits[encounterID] = visit
    EncounterLoot.seams.After(EncounterLoot.COMMIT_DELAY, function() EncounterLoot.Commit(encounterID, visit) end)
  end
  visit.items[itemID] = true
  return true
end

-- ENCOUNTER_LOOT_RECEIVED: only the encounter and the item (arguments 1
-- and 2); the link, quantity, player name and class are never read
function EncounterLoot.OnLoot(encounterID, itemID)
  return EncounterLoot.Note(encounterID, itemID)
end

-- ENCOUNTER_END (encounterID, encounterName, difficultyID, groupSize, success)
function EncounterLoot.OnEnd(encounterID, _, _, _, success)
  if Host.IsSecret(success) or success ~= 1 or not Bags.PositiveID(encounterID) then return end
  local ok, now = pcall(EncounterLoot.seams.Clock)
  if ok and type(now) == "number" then lastEnd = { id = encounterID, at = now } end
end

-- BONUS_ROLL_RESULT (typeIdentifier, itemLink, ...): an item counts for the
-- encounter that just ended; true when kept
function EncounterLoot.OnBonusRoll(typeIdentifier, itemLink)
  if not lastEnd or Host.IsSecret(typeIdentifier) or typeIdentifier ~= "item" then return false end
  if Host.IsSecret(itemLink) or type(itemLink) ~= "string" then return false end
  local ok, now = pcall(EncounterLoot.seams.Clock)
  if not ok or type(now) ~= "number" or now - lastEnd.at > EncounterLoot.BONUS_WINDOW then return false end
  return EncounterLoot.Note(lastEnd.id, tonumber(itemLink:match("item:(%d+)")))
end

function EncounterLoot.Reset()
  wipe(visits)
  wipe(dungeonOf)
  lastEnd = nil
end

local handlers = {
  ENCOUNTER_LOOT_RECEIVED = function(encounterID, itemID) EncounterLoot.OnLoot(encounterID, itemID) end,
  ENCOUNTER_END = EncounterLoot.OnEnd,
  BONUS_ROLL_RESULT = function(typeIdentifier, itemLink) EncounterLoot.OnBonusRoll(typeIdentifier, itemLink) end,
}

-- The event frame's dispatch (a test run scripting the client reads nothing)
function EncounterLoot.OnEvent(event, ...)
  if Curator.Main.IsScripted() or not handlers[event] then return end
  local ok, err = pcall(handlers[event], ...)
  if not ok then Host.Log("Encounter loot recorder %s failed: %s", event, tostring(err)) end
end

local frame = CreateFrame("Frame")
for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...) EncounterLoot.OnEvent(event, ...) end)
