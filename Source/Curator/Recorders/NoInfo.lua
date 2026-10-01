-------------------------------------------------------------------------------
-- Curator recorder: items with no information (the no-info items spec of
-- 2026-09-28; Cobanyte, 2026-09-28: every item a player can obtain should end up in the shipped
-- database, so the items it says nothing about are collected for the author)
--
-- An item has no information when the shipped data this client loaded says
-- nothing about it (Host.Knows: no relation codes, no removal patch, no
-- description, guide note, confirmed known use or leftover note, no quality
-- sibling with any). Each sighting of such an item is one ordinary
-- addition, so revisions, K and V, frozen blocks, the cap and the pipeline
-- all work unchanged:
--   ni:<item>   value where it was seen: "bag", "bank", "wb" (the warband
--               bank), or the source the loot, vendor, quest and market
--               comparisons name: c:<npc>, ob:<object>, f:<map>,
--               x:<container>, de:<item>, pp:<npc>, v:<npc>, q:<quest>,
--               e:<dungeonEncounterID>, bm, tp
--               info: what the item is (Store.lua's header), IDs only
-- A new place is a new record; an item keeps at most NOINFO_PLACES records
-- with a named source per game build, and a further place counts on its
-- newest one. Never recorded: a count, a link, a name, a tooltip line, a
-- slot, anything else held; grey (quality 0) items.
--
-- Where it looks: Compare.SawItem from the loot, vendor, quest, boss loot,
-- Black Market and Trading Post comparisons (at once, in combat too, as
-- those recorders do), and two sweeps that read what the curator holds and
-- so wait for the one-time notice (noInfoNotice, Main.lua's header): the
-- bags, through the shared bag observer (its first compared change after a
-- store or mode change sweeps every item held, later ones the items that
-- went up), and the character's stored bank tabs and the warband bank's
-- (Host.StoredItems, 2 seconds after a burst of stored bank reads and 20
-- seconds after login).
-- Sweeps run in Main.Defer jobs of NOINFO_SLICE items, out of combat.
--
-- Once per item and place per session (the epoch empties the set), and not
-- again once delivered, under this data version or a later one (the store's
-- reported set).
-- An item whose quality isn't loaded is asked for and held (at most
-- NOINFO_PENDING, for NOINFO_PENDING_SECONDS) until ITEM_DATA_LOAD_RESULT.
-- Past NOINFO_CAP live ni: records, a new item removes one first: a bag or
-- bank sighting of gear, then any bag or bank sighting, then the oldest.
--
-- Only C_Item getters and C_Item.RequestLoadItemDataByID, through
-- NoInfo.seams; no hooks, no Blizzard frames, no protected calls. Only while
-- curator mode may record, and the sweeps never while a test run scripts the
-- client.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Store = Curator.Store
local Main = Curator.Main
local Bags = Curator.Recorders.Bags

local NoInfo = {}
Curator.Recorders.NoInfo = NoInfo

NoInfo.LOGIN_NOTICE = 10   -- seconds after login: the one-time chat line
NoInfo.LOGIN_SWEEP = 20    -- seconds after login: the stored banks' sweep
NoInfo.COUNT_EVERY = 10    -- seconds between two counts of the live ni: records
NoInfo.STORED_AFTER = 2    -- seconds after the last stored bank read: the stored banks' sweep

-- The one-time line for a curator who opted in before bags and banks were included
NoInfo.NOTICE_TEXT = "Curator mode now also notes items Recollect's database knows nothing about, including ones in "
  .. "your bags and banks: only the item's ID and where you saw it, never how many you have, currencies, gold or "
  .. "anything else you carry. /rec curator shows what's recorded; turning curator mode off stops it."

-- Sightings that say where the item is, not where it came from
local HELD = { bag = true, bank = true, wb = true }
local GEAR = { [2] = true, [4] = true }   -- weapons and armor

NoInfo.seams = {
  Knows = function(itemID) return Host.Knows(itemID) end,
  Instant = function(itemID)
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    return classID, subclassID
  end,
  Quality = function(itemID) return C_Item.GetItemQualityByID(itemID) end,
  -- the bind type and expansion (the 14th and 15th returns): nothing else of GetItemInfo's
  Info = function(itemID)
    local bindType, expansionID = select(14, C_Item.GetItemInfo(itemID))
    return bindType, expansionID
  end,
  Spell = function(itemID) return Bags.ItemSpell(itemID) end,
  Cached = function(itemID) return C_Item.IsItemDataCachedByID(itemID) end,
  RequestLoad = function(itemID) C_Item.RequestLoadItemDataByID(itemID) end,
  InCombat = function() return InCombatLockdown() end,
  Clock = function() return GetTime() end,
  Now = function() return GetServerTime() end,
  Stored = function() return Host.StoredItems() end,
  NoticeAt = function() return Main.DB().noInfoNotice end,
  SetNotice = function(at) Main.DB().noInfoNotice = at end,
  Print = function(text) Host.Print(text) end,
  After = function(seconds, fn) C_Timer.After(seconds, fn) end,
}

-- A seam's first two answers, a secret one as nil
local function Seam(name, ...)
  local ok, a, b = pcall(NoInfo.seams[name], ...)
  if not ok then return nil, nil end
  if Host.IsSecret(a) then a = nil end
  if Host.IsSecret(b) then b = nil end
  return a, b
end

-- In combat, or can't be told (a secret or failed read counts as combat)
local function InCombat()
  local ok, value = pcall(NoInfo.seams.InCombat)
  return not ok or Host.IsSecret(value) or value == true
end

-------------------------------------------------------------------------------
-- The session's state, emptied when the epoch changes (curator mode turned
-- off or on, findings cleared, the store swapped)
-------------------------------------------------------------------------------
local state = {}
local waits = { notice = false, stored = false }   -- what combat held back

local function Current()
  local epoch = Main.Epoch()
  if state.epoch ~= epoch then
    -- seen [item@place] = true; pending [item] = { wheres, at }; places
    -- [item] = { record IDs of its named sightings }; held: sweep jobs combat stopped
    state = { epoch = epoch, seen = {}, pending = {}, places = nil, count = nil, countAt = nil, bagSwept = false, held = {} }
  end
  return state
end

-- Reset(): forgets the session (a test starts clean)
function NoInfo.Reset()
  state = {}
  waits.notice, waits.stored = false, false
end

NoInfo._test = {
  Pending = function(itemID) return Current().pending[itemID] end,
}

-------------------------------------------------------------------------------
-- What the item is: "c<class>.<subclass>,q<quality>,b<bind>,e<expansion>,s<0|1>"
-------------------------------------------------------------------------------
local function Whole(value)
  return type(value) == "number" and value == math.floor(value) and value >= 0 and value < 2 ^ 31
end

function NoInfo.InfoText(itemID, quality)
  local parts = {}
  local classID, subclassID = Seam("Instant", itemID)
  if Whole(classID) then
    parts[#parts + 1] = Whole(subclassID) and ("c%d.%d"):format(classID, subclassID) or ("c%d"):format(classID)
  end
  if Whole(quality) then parts[#parts + 1] = ("q%d"):format(quality) end
  local bind, expansion = Seam("Info", itemID)
  if Whole(bind) then parts[#parts + 1] = ("b%d"):format(bind) end
  if Whole(expansion) then parts[#parts + 1] = ("e%d"):format(expansion) end
  if Whole(Seam("Spell", itemID)) then
    parts[#parts + 1] = "s1"
  elseif Seam("Cached", itemID) == true then
    parts[#parts + 1] = "s0"
  end
  return table.concat(parts, ",")
end

-- The item class an info text names, or nil
local function InfoClass(info)
  return tonumber(("," .. tostring(info or "")):match(",c(%d+)"))
end

-------------------------------------------------------------------------------
-- Where a sighting goes: its own place, or past NOINFO_PLACES named places
-- the item's newest named record
-------------------------------------------------------------------------------
local function IsNoInfo(record)
  return type(record) == "table" and type(record.fact) == "string" and record.fact:find("^ni:") ~= nil
end

-- places[item]: the record IDs of the item's named sightings, read from the
-- store once per session and kept up by each write
local function Places()
  local s = Current()
  if s.places then return s.places end
  local places = {}
  for id, record in pairs(Store.DB().records) do
    local item = IsNoInfo(record) and tonumber(record.fact:match("^ni:(%d+)$"))
    if item and not HELD[record.value] then
      places[item] = places[item] or {}
      table.insert(places[item], id)
    end
  end
  s.places = places
  return places
end

-- The item's named records at this game build still in the store, newest first
local function NamedRecords(itemID)
  local db, build, fact = Store.DB(), Store.Build(), "ni:" .. itemID
  local list = {}
  for _, id in ipairs(Places()[itemID] or {}) do
    local record = db.records[id]
    if record and record.fact == fact and record.build == build then list[#list + 1] = record end
  end
  table.sort(list, function(a, b)
    if (a.last or 0) ~= (b.last or 0) then return (a.last or 0) > (b.last or 0) end
    return (a.touched or 0) > (b.touched or 0)
  end)
  return list
end

local function PlaceValue(itemID, where)
  if HELD[where] then return where end
  local named = NamedRecords(itemID)
  for _, record in ipairs(named) do
    if record.value == where then return where end
  end
  if #named >= Curator.Const.NOINFO_PLACES then return named[1].value end
  return where
end

-------------------------------------------------------------------------------
-- The sub-cap
-------------------------------------------------------------------------------
local function LiveCount()
  local s = Current()
  local now = Seam("Clock") or 0
  if s.count and s.countAt and now - s.countAt < NoInfo.COUNT_EVERY then return s.count end
  local n = 0
  for _, record in pairs(Store.DB().records) do
    if IsNoInfo(record) then n = n + 1 end
  end
  s.count, s.countAt = n, now
  return n
end

-- The ni: record that makes room: rank 1 a bag or bank sighting of gear, 2
-- any bag or bank sighting, 3 any other; the oldest last seen within a rank
local function Rank(record)
  if not HELD[record.value] then return 3 end
  return GEAR[InfoClass(record.info)] and 1 or 2
end

local function Victim()
  -- the best key as three scalars, never a table per candidate (a full list
  -- is scanned for every new item)
  local best, bestRank, bestLast, bestTouched
  for id, record in pairs(Store.DB().records) do
    if IsNoInfo(record) then
      local rank, last, touched = Rank(record), record.last or 0, record.touched or 0
      if not best or rank < bestRank or (rank == bestRank and (last < bestLast or (last == bestLast and touched < bestTouched))) then
        best, bestRank, bestLast, bestTouched = id, rank, last, touched
      end
    end
  end
  return best
end

local function MakeRoom()
  if LiveCount() < Curator.Const.NOINFO_CAP then return end
  local id = Victim()
  if id and Store.Remove(id) then
    local s = Current()
    s.count = math.max(0, (s.count or 1) - 1)
  end
end

-------------------------------------------------------------------------------
-- A sighting
-------------------------------------------------------------------------------
local function Write(itemID, where, ctx, quality)
  local fact = "ni:" .. itemID
  local value = PlaceValue(itemID, where)
  local isNew = Store.Find(fact, value) == nil
  if isNew then MakeRoom() end
  local record = Store.Record("addition", fact, value, nil, ctx, nil, NoInfo.InfoText(itemID, quality))
  if not (isNew and record) then return end
  local s = Current()
  if s.count then s.count = s.count + 1 end
  if not HELD[value] then
    local places = Places()
    places[itemID] = places[itemID] or {}
    table.insert(places[itemID], record.id)
  end
end

-- The quality: a number, "load" when the item isn't loaded yet, or nil
-- when the read failed or was secret
local function ReadQuality(itemID)
  local ok, quality = pcall(NoInfo.seams.Quality, itemID)
  if not ok or Host.IsSecret(quality) then return nil end
  if quality == nil then return "load" end
  return type(quality) == "number" and quality or nil
end

-- An item whose data isn't loaded: asked for and held until it is
local function Hold(itemID, where)
  local s = Current()
  local now = Seam("Clock") or 0
  local n = 0
  for id, entry in pairs(s.pending) do
    if now - entry.at > Curator.Const.NOINFO_PENDING_SECONDS then s.pending[id] = nil else n = n + 1 end
  end
  local entry = s.pending[itemID]
  if entry then
    entry.wheres[where] = true
    return "pending"
  end
  if n >= Curator.Const.NOINFO_PENDING then return "full" end
  s.pending[itemID] = { wheres = { [where] = true }, at = now }
  pcall(NoInfo.seams.RequestLoad, itemID)
  return "pending"
end

-- Saw(itemID, where, ctx, quality, loaded): one sighting of an item at a
-- place (see the header); ctx the context index; quality when the caller
-- read it (a stored bank read), else read here; loaded when the item's data
-- just loaded (a quality still missing then records nothing). Returns
-- "recorded", "known", "seen", "reported", "grey", "pending", "full",
-- "unreadable" or "off".
function NoInfo.Saw(itemID, where, ctx, quality, loaded)
  if type(itemID) ~= "number" or Host.IsSecret(itemID) or itemID <= 0 or type(where) ~= "string" then return "unreadable" end
  local s = Current()
  local key = itemID .. "@" .. where
  if s.seen[key] then return "seen" end   -- a repeat costs one lookup
  if not Main.MayRecord() then return "off" end
  if Store.DB().reported["ni:" .. itemID] then
    s.seen[key] = true
    return "reported"
  end
  local knows = Seam("Knows", itemID)
  if type(knows) ~= "table" or knows.known ~= false then
    s.seen[key] = true
    return "known"
  end
  if type(quality) ~= "number" then quality = ReadQuality(itemID) end
  if quality == "load" then
    if loaded then return "unreadable" end
    return Hold(itemID, where)
  end
  if quality == nil then return "unreadable" end
  s.seen[key] = true
  if quality == 0 then return "grey" end
  Write(itemID, where, ctx, quality)
  return "recorded"
end

-- IsEmpty(itemID): whether the shipped data says nothing about the item
-- (the details window's Request info, through the provider)
function NoInfo.IsEmpty(itemID)
  local knows = Seam("Knows", tonumber(itemID))
  return type(knows) == "table" and knows.known == false
end

-- OnLoadResult(itemID, success): ITEM_DATA_LOAD_RESULT, which fires for
-- every item the client loads; one lookup unless NoInfo waits for this one
function NoInfo.OnLoadResult(itemID, success)
  local s = Current()
  local entry = s.pending[itemID]
  if not entry then return end
  s.pending[itemID] = nil
  if success ~= true then return end
  if (Seam("Clock") or 0) - entry.at > Curator.Const.NOINFO_PENDING_SECONDS then return end
  Main.Defer(function()
    local ctx = Curator.Context.Current()
    for where in pairs(entry.wheres) do NoInfo.Saw(itemID, where, ctx, nil, true) end
  end)
end

-------------------------------------------------------------------------------
-- The sweeps: what the curator holds, only once the notice was shown
-------------------------------------------------------------------------------
-- Whether bag and bank sweeps may run: the notice mark set
function NoInfo.NoticeShown()
  local at = Seam("NoticeAt")
  return type(at) == "number" and at > 0
end

local function MaySweep()
  return Main.MayRecord() and not Main.IsScripted() and NoInfo.NoticeShown()
end

-- SweepItems(list): { { id, where, quality } }, compared NOINFO_SLICE a job;
-- combat holds the rest until it ends
function NoInfo.SweepItems(list)
  if #list == 0 then return end
  local s = Current()
  local function Slice(from)
    if InCombat() then
      s.held[#s.held + 1] = function() Slice(from) end
      return
    end
    local ctx = Curator.Context.Current()
    local last = math.min(#list, from + Curator.Const.NOINFO_SLICE - 1)
    for i = from, last do NoInfo.Saw(list[i].id, list[i].where, ctx, list[i].quality) end
    if last < #list then Main.Defer(function() Slice(last + 1) end) end
  end
  Main.Defer(function() Slice(1) end)
end

-- OnBags(before, after): a compared bag change (the bag observer's
-- subscriber, out of combat): the first after an epoch change sweeps every
-- item held, later ones the items that went up
function NoInfo.OnBags(before, after)
  if not MaySweep() or type(after) ~= "table" then return end
  local s = Current()
  local list = {}
  if not s.bagSwept then
    s.bagSwept = true
    for id in pairs(after) do list[#list + 1] = { id = id, where = "bag" } end
  else
    local _, up = Bags.Changes(before or {}, after)
    for _, change in ipairs(up) do list[#list + 1] = { id = change.id, where = "bag" } end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  NoInfo.SweepItems(list)
end

-- SweepStored(): the character's stored bank tabs and the warband bank's;
-- false when it can't run now (combat holds it until it ends)
function NoInfo.SweepStored()
  if not MaySweep() then return false end
  if InCombat() then
    waits.stored = true
    return false
  end
  local ok, stored = pcall(NoInfo.seams.Stored)
  local list = {}
  for _, entry in ipairs(ok and type(stored) == "table" and stored or {}) do
    if type(entry) == "table" and (entry.where == "bank" or entry.where == "wb") then
      list[#list + 1] = { id = entry.id, where = entry.where, quality = entry.quality }
    end
  end
  NoInfo.SweepItems(list)
  return true
end

-------------------------------------------------------------------------------
-- The notice (consent for the sweeps)
-------------------------------------------------------------------------------
-- OptedIn(): curator mode turned on from this build, whose settings text
-- names bags and banks: the sweeps may run, no chat line needed
function NoInfo.OptedIn()
  if NoInfo.NoticeShown() then return end
  pcall(NoInfo.seams.SetNotice, Seam("Now") or 1)
end

-- Notice(): the one-time chat line for a curator who opted in before, then
-- the mark; true when shown
function NoInfo.Notice()
  if not Main.IsEnabled() or NoInfo.NoticeShown() then return false end
  if InCombat() then
    waits.notice = true
    return false
  end
  pcall(NoInfo.seams.Print, NoInfo.NOTICE_TEXT)
  pcall(NoInfo.seams.SetNotice, Seam("Now") or 1)
  Host.Log("Curator: the items-with-no-information notice was shown; bag and bank sweeps may run")
  return true
end

-- OnCombatEnded(): what combat held back runs now
function NoInfo.OnCombatEnded()
  local s = Current()
  local held = s.held
  s.held = {}
  for _, fn in ipairs(held) do Main.Defer(fn) end
  if waits.notice then
    waits.notice = false
    NoInfo.Notice()
  end
  if waits.stored then
    waits.stored = false
    NoInfo.SweepStored()
  end
end

-- OnEnteringWorld(isInitialLogin, isReloadingUi): the notice and the stored
-- banks' sweep, once per login or reload (never on a loading screen)
function NoInfo.OnEnteringWorld(isInitialLogin, isReloadingUi)
  if not (isInitialLogin or isReloadingUi) then return end
  pcall(NoInfo.seams.After, NoInfo.LOGIN_NOTICE, function() NoInfo.Notice() end)
  pcall(NoInfo.seams.After, NoInfo.LOGIN_SWEEP, function() NoInfo.SweepStored() end)
end

-- A bank open stores every tab, and each later bag update of a tab stores it
-- again: one sweep for a burst
local storedSoon = CobySuite_Recollect.Utilities.Coalesce(NoInfo.STORED_AFTER, function() NoInfo.SweepStored() end)

Bags.Subscribe(function(before, after) NoInfo.OnBags(before, after) end)
Host.OnSnapshotCaptured(function() storedSoon:Call() end)

local frame = CreateFrame("Frame")
for _, event in ipairs({ "ITEM_DATA_LOAD_RESULT", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
  pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, a, b)
  if event == "ITEM_DATA_LOAD_RESULT" then
    -- every item load in the client: nothing to do unless an item waits
    if next(state.pending or {}) == nil or Host.IsSecret(a) then return end
    local ok, err = pcall(NoInfo.OnLoadResult, a, b)
    if not ok then Host.Log("No-info recorder %s failed: %s", event, tostring(err)) end
    return
  end
  if Main.IsScripted() then return end
  local handler = event == "PLAYER_ENTERING_WORLD" and NoInfo.OnEnteringWorld or NoInfo.OnCombatEnded
  local ok, err = pcall(handler, a, b)
  if not ok then Host.Log("No-info recorder %s failed: %s", event, tostring(err)) end
end)
