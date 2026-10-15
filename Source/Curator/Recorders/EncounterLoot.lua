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
-- COMMIT_DELAY seconds from the first, then compared in a later frame,
-- under the context of the moment the first was seen (Task #421: a zone or
-- difficulty change in those seconds never becomes the kill's).
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
-- whose boss isn't mapped is simply no match. An item the data ships as a
-- world drop (Compare.WorldDrop, a live z0) that no code of this encounter
-- names is no addition either: a boss's copy of it says nothing about
-- where to farm it. Loot is chance: no not seen, no conflicts.
-- A Mythic+ keystone run's end-of-run loot carries the last encounter's ID
-- but comes from the whole dungeon's pool; it records like any kill, its
-- context block carrying the difficulty (8), and /recollect-data sets the
-- pool apart item by item (2026-09-28).
-- Only a route that serves the loot counts (Task #421), judged by the
-- instance difficulty alone (Task #435): the D or c code's instance
-- difficulties (M) against the difficulty it dropped on. Its faction, class
-- and race are never read, for any loot: ENCOUNTER_LOOT_RECEIVED tells every
-- group member's loot, never whose, and a raid's loot window under group loot
-- lists every player's drop, so the observer's own class says nothing about
-- a class token (Task #390: an Evoker's kill listed a four-class token, and
-- the review asked for an unrestricted D beside its shipped code;
-- /recollect-data judges a boss's loot the same way). A drop outside a
-- route's difficulties is an addition whose shipped names it ("1001|M16").
--
-- The loot recorder hands this one the loot window of a boss kill (Task #393,
-- 2026-10-13): a creature looted within LOOT_WINDOW seconds of a successful
-- ENCOUNTER_END inside an instance is this encounter's (KillOf, Note) when the
-- data maps it to the encounter's boss (Task #421: its J encounter's dungeon
-- encounter, the journal's answer, is the kill's), never on the timing alone:
-- trash killed beside a boss stays the creature's drop. A boss under a second
-- creature ID the data doesn't map (238693 at Sporefall, encounter 2711, gave
-- 11 false c findings) needs its J line.
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
EncounterLoot.LOOT_WINDOW = 5     -- seconds from a successful ENCOUNTER_END in which a loot window is that kill's

EncounterLoot.seams = {
  -- the dungeon encounter ID of an Encounter Journal encounter (7th return)
  DungeonEncounter = function(journalID) return (select(7, EJ_GetEncounterInfo(journalID))) end,
  Clock = function() return GetTime() end,
  InInstance = function() return IsInInstance() end,
  After = function(delay, fn) C_Timer.After(delay, fn) end,
}

local visits = {}     -- [encounterID] = { epoch, ctx, items = { [itemID] = true or "own" } }, gathering
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

-- The item's D codes as text ("1234,1235|x", each with its flags), then the
-- c codes a restriction left the loot outside of ("c300|f1"), or nil
local function CodesText(codes, outside)
  local parts = {}
  for _, code in ipairs(codes) do
    local flags = code.code and code.code:match("|(.*)$") or (code.gone and "x" or nil)
    parts[#parts + 1] = code.id .. (flags and flags ~= "" and "|" .. flags or "")
  end
  for _, code in ipairs(outside) do parts[#parts + 1] = code end
  return #parts > 0 and table.concat(parts, ",") or nil
end

-- Whether a shipped code's instance difficulties (its M condition) take the
-- difficulty the loot dropped on: true with none; nil when the difficulty
-- isn't known
local function DifficultyServes(code, difficulty)
  local list = (tostring(code or ""):match("|(.*)$") or ""):match("M([%d%.]+)")
  if not list then return true end
  if type(difficulty) ~= "number" then return nil end
  for id in list:gmatch("%d+") do
    if tonumber(id) == difficulty then return true end
  end
  return false
end

-- Known(itemID, encounterID, owner): true when the shipped data has the item
-- at that dungeon encounter on a route that serves the loot (owner: the
-- difficulty it dropped on, { difficulty }; nil judges no route's conditions),
-- false when it doesn't, nil when a D code can't be mapped or a route there
-- can't be told for the loot (then nothing is recorded); and the item's D
-- codes as text, with the c codes it fell outside of
function EncounterLoot.Known(itemID, encounterID, owner)
  local codes = Host.CodesOf(itemID, "D", owner)
  local unmapped, unknown, outside = false, false, {}
  local function Judge(code, text)
    local serves = true
    if owner ~= nil then serves = DifficultyServes(code.code, owner.difficulty) end
    if serves == true then return true end
    if serves == false then
      if text then outside[#outside + 1] = text end
    else
      unknown = true
    end
  end
  for _, code in ipairs(codes) do
    if not code.gone then
      local dungeon = Dungeon(code.id)
      if dungeon == encounterID then
        if Judge(code) then return true end
      elseif not dungeon then
        unmapped = true
      end
    end
  end
  for _, code in ipairs(Host.CodesOf(itemID, "c", owner)) do
    local journal = not code.gone and Host.EncounterOf(code.id)
    if journal and Dungeon(journal) == encounterID and Judge(code, code.code) then return true end
  end
  if unmapped or unknown then return nil end
  return false, CodesText(codes, outside)
end

-- The loot's owner for Known: only the difficulty it dropped on, whoever's
-- loot it is (this character's own included, Task #435: see the header)
local function LootOwner(owner)
  if owner == nil then return nil end
  return { difficulty = owner.difficulty }
end

-- Compare(encounterID, items, ctx): items = { [itemID] = true, or "own" for
-- this character's own loot, which is judged like any other since Task
-- #435 }, one kill's loot; returns how many the shipped data knows there
function EncounterLoot.Compare(encounterID, items, ctx)
  local matched = {}
  local owner = Curator.Context.OwnerOf(ctx)
  for itemID in pairs(items) do
    Curator.Compare.SawItem(itemID, "e:" .. encounterID, ctx)
    local lootOwner = LootOwner(owner)
    local known, shipped = EncounterLoot.Known(itemID, encounterID, lootOwner)
    if known then
      matched[#matched + 1] = itemID
    elseif known == false and not Curator.Compare.WorldDrop(itemID, lootOwner)
      and not Curator.Compare.SeasonDrop(itemID, lootOwner) then
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
    local matched = EncounterLoot.Compare(encounterID, visit.items, visit.ctx)
    Host.Log("Encounter %d loot: %d items the data knows there", encounterID, matched)
  end)
end

-- Note(encounterID, itemID, own): one item looted from an encounter (own:
-- this character's own loot, its loot window or a bonus roll); true when
-- kept. The visit's context is the moment its first item was seen
function EncounterLoot.Note(encounterID, itemID, own)
  if not Curator.Main.MayRecord() or not Bags.PositiveID(encounterID) or not Bags.PositiveID(itemID) then return false end
  local visit = visits[encounterID]
  if not visit then
    visit = { epoch = Curator.Main.Epoch(), items = {}, ctx = Curator.Context.Current() }
    visits[encounterID] = visit
    EncounterLoot.seams.After(EncounterLoot.COMMIT_DELAY, function() EncounterLoot.Commit(encounterID, visit) end)
  end
  if own then visit.items[itemID] = "own" else visit.items[itemID] = visit.items[itemID] or true end
  return true
end

-- ENCOUNTER_LOOT_RECEIVED: only the encounter and the item (arguments 1
-- and 2); the link, quantity, player name and class are never read
function EncounterLoot.OnLoot(encounterID, itemID)
  return EncounterLoot.Note(encounterID, itemID)
end

-- RecentKill(): the dungeon encounter that ended in success within LOOT_WINDOW
-- seconds while the player is in an instance (a world boss's end is not one),
-- or nil. A read that fails or is secret counts as none.
function EncounterLoot.RecentKill()
  if not lastEnd then return nil end
  local ok, now = pcall(EncounterLoot.seams.Clock)
  if not ok or type(now) ~= "number" or now - lastEnd.at > EncounterLoot.LOOT_WINDOW then return nil end
  local inOk, inInstance = pcall(EncounterLoot.seams.InInstance)
  if not inOk or Host.IsSecret(inInstance) or inInstance ~= true then return nil end
  return lastEnd.id
end

-- KillOf(npcID): the dungeon encounter of RecentKill when the creature is its
-- boss in the data: the J table maps it (Host.EncounterOf) to a journal
-- encounter whose dungeon encounter, the journal's own answer, is the kill's.
-- Otherwise nil, however close the timing: trash killed beside a boss, a boss
-- the data doesn't map, another encounter's boss (Task #421). The timing is
-- then only a debug log line
function EncounterLoot.KillOf(npcID)
  local encounter = EncounterLoot.RecentKill()
  if not encounter then return nil end
  local journal = Host.EncounterOf(npcID)
  if journal and Dungeon(journal) == encounter then return encounter end
  Host.Log("Creature %s looted just after encounter %d's kill isn't its boss in the data: its own drop", tostring(npcID), encounter)
  return nil
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
  return EncounterLoot.Note(lastEnd.id, CobySuite_Recollect.Utilities.IDFromLink(itemLink), true)   -- a bonus roll is this character's
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
EncounterLoot.frame = frame   -- its events, for a development timing probe (Task #294)
for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...) EncounterLoot.OnEvent(event, ...) end)
