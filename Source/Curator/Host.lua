-------------------------------------------------------------------------------
-- Curator.Host: the curator's only doorway into Recollect (curator spec,
-- "The separation boundary", D33)
--
-- Curator mode ships inside Recollect for now (D32) but is written as a
-- guest. Every curator file other than this one reaches Recollect only
-- through Host, whose functions take and return plain Lua values (IDs,
-- numbers, strings, tables of those), never Recollect's own tables. If the
-- curator becomes its own addon later, this file becomes Recollect's public
-- CuratorAPI and nothing else in the curator changes. HOST_VERSION goes up
-- whenever a function here changes shape.
--
-- This file also creates the curator's namespace, Recollect.Curator (the one
-- place a curator file names Recollect besides that namespace).
-------------------------------------------------------------------------------
local Curator = {}
Recollect.Curator = Curator

local Host = {}
Curator.Host = Host

Host.HOST_VERSION = 7   -- 2: Versions fails closed, Hints is fact-keyed, PurchasesOf;
                        -- 3: NpcName, ZoneName, OpenSettings (the curator dashboard);
                        -- 4: Knows, StoredItems, OnSnapshotCaptured (items with no information);
                        -- 5: NpcPlaces, QuestPlace, EncounterOfObject, ObjectAlias (data format 7),
                        --    Sources' event, QuestGiver's second answer (every giver);
                        -- 6: Sources' costs and unlisted (a V code's price in currencies, data
                        --    format 8, 2026-09-29);
                        -- 7: QuestTurnIns (who takes a quest's turn-in, the Z table, data
                        --    format 10, 2026-10-05)

-------------------------------------------------------------------------------
-- Versions (D13)
-------------------------------------------------------------------------------
-- { addon, data, format, ok, why }: Recollect's version, the shipped data's
-- version and format, and whether the data files agree and are supported.
-- A version check that is missing or fails reads as not ok: the curator
-- then records nothing (Main.MayRecord).
function Host.Versions()
  local okMeta, addon = pcall(C_AddOns.GetAddOnMetadata, "Recollect", "Version")
  local out = { addon = okMeta and addon or "?", data = "unstamped", format = 1, ok = false, why = "unreadable" }
  local DataVersion = Recollect.Facts and Recollect.Facts.DataVersion
  if DataVersion and DataVersion.Get then
    local ok, info = pcall(DataVersion.Get)
    if ok and type(info) == "table" then
      out.data, out.format, out.ok, out.why = info.dataVersion, info.format, info.ok == true, info.why
    end
  end
  return out
end

-- The addon's icon (a texture path) for the curator's window titles
function Host.Icon()
  return Recollect.ICON
end

-------------------------------------------------------------------------------
-- Shipped data, as plain values
-------------------------------------------------------------------------------
-- The item IDs the shipped data says a vendor sells, in the index's order
-- (the order confirmation bitmaps count in), or an empty list
function Host.ItemsOf(npcID)
  local Vendors = Recollect.Facts and Recollect.Facts.Vendors
  if not (Vendors and Vendors.ItemsOf) then return {} end
  local ok, list = pcall(Vendors.ItemsOf, npcID)
  return ok and type(list) == "table" and list or {}
end

-- The recipe spell IDs the shipped data lists for a profession skill line
function Host.RecipesOf(skillLine)
  local Relations = Recollect.Facts and Recollect.Facts.Relations
  if not (Relations and Relations.RecipesOf) then return {} end
  local ok, list = pcall(Relations.RecipesOf, skillLine)
  return ok and type(list) == "table" and list or {}
end

-- An item's shipped relation codes as one string ("" when it has none)
function Host.Codes(itemID)
  local Relations = Recollect.Facts and Recollect.Facts.Relations
  if not (Relations and Relations.Codes) then return "" end
  local ok, codes = pcall(Relations.Codes, itemID)
  return ok and type(codes) == "string" and codes or ""
end

-- An item's shipped codes of one letter whose body is a number, as
-- { { id, gone } }: CodesOf(item, "O") for the Black Market ({ { id = 1 } }),
-- CodesOf(item, "U") for the Trading Post's months ({ { id = 202503 } }, 0
-- for a month not known). gone is true when the code's route flags say it
-- is no longer available ("|x"). Reads Host.Codes, so what it parses is
-- the same string the rest of the curator sees.
function Host.CodesOf(itemID, letter)
  local out = {}
  for code in Host.Codes(itemID):gmatch("[^;]+") do
    local body, flags = code:match("^([^|]*)|?(.*)$")
    local id = body and body:sub(1, #letter) == letter and tonumber(body:sub(#letter + 1):match("^%d+$") or "")
    if id then out[#out + 1] = { id = id, gone = flags:find("x", 1, true) ~= nil } end
  end
  return out
end

-- The fact a shipped hint names: the shipped form is unseen[<letter>] =
-- { [<source ID>] = "<item IDs, comma separated>" } (Data/Hints.lua); a
-- vendor's is the Compare fact "v:<npc>:i:<item>:sold"
local function HintFact(letter, source, item)
  if letter == "v" then return ("v:%d:i:%d:sold"):format(source, item) end
  return ("%s:%d:i:%d"):format(letter, source, item)
end

local hintsFor, hintsSet
-- The curator hints shipped with the data (D30), as a fresh set of the
-- facts they name, and the settled sources and confirmation rounds (D36) as
-- shipped: { unseen = { [fact] = true }, settled = { [source] = round },
-- rounds = { [source] = round }, quiet = { [fact] = true or { [value] = true } } }
function Host.Hints()
  local DataVersion = Recollect.Facts and Recollect.Facts.DataVersion
  local ok, hints = false, nil
  if DataVersion and DataVersion.Hints then ok, hints = pcall(DataVersion.Hints) end
  local unseen = ok and type(hints) == "table" and type(hints.unseen) == "table" and hints.unseen or nil
  local settled = ok and type(hints) == "table" and type(hints.settled) == "table" and hints.settled or {}
  local rounds = ok and type(hints) == "table" and type(hints.rounds) == "table" and hints.rounds or {}
  local quiet = ok and type(hints) == "table" and type(hints.quiet) == "table" and hints.quiet or {}
  if hintsFor == unseen and hintsSet then return { unseen = hintsSet, settled = settled, rounds = rounds, quiet = quiet } end
  local set = {}
  for letter, sources in pairs(unseen or {}) do
    if type(letter) == "string" and type(sources) == "table" then
      for source, items in pairs(sources) do
        if type(source) == "number" and type(items) == "string" then
          for item in items:gmatch("%d+") do set[HintFact(letter, source, tonumber(item))] = true end
        end
      end
    end
  end
  hintsFor, hintsSet = unseen, set
  return { unseen = set, settled = settled, rounds = rounds, quiet = quiet }
end

-- The shipped relations bucket strings the handshake challenge reads
-- (the item buckets, keyed by item ID // 1024): the list of bucket indexes,
-- and one bucket's string
function Host.BucketIndexes()
  local data = Recollect.Data and Recollect.Data.Relations
  local out = {}
  for index, bucket in pairs(data and data.B or {}) do
    if type(bucket) == "string" then out[#out + 1] = index end
  end
  table.sort(out)
  return out
end

function Host.Bucket(index)
  local data = Recollect.Data and Recollect.Data.Relations
  local bucket = data and data.B and data.B[index]
  return type(bucket) == "string" and bucket or nil
end

local function Owner(context)
  if type(context) ~= "table" then return nil end
  return { faction = context.faction, classID = context.classID, raceID = context.raceID }
end

-- true, false or nil: whether a parsed route serves the context
local function Serves(relation, context)
  local Relations = Recollect.Facts.Relations
  local ok, applies = pcall(Relations.Applies, relation, Owner(context))
  if not ok then return nil end
  if applies == true then return true end
  if applies == "unavailable" or applies == "other" then return false end
  return nil
end

local function CopyCosts(costs)
  local out = {}
  for i, cost in ipairs(costs or {}) do out[i] = { kind = cost.kind, id = cost.id, count = cost.count } end
  return out
end

-- The item a purchase hands over: its own ID for a plain item, toy,
-- heirloom or decor; the item that teaches a mount; the item behind a pet,
-- ensemble, recipe or illusion (the data's T table, one representative
-- item); nil for an achievement or anything that can't be resolved (never
-- the raw thing ID, which is another kind of ID)
local ITEM_LETTERS = { [""] = true, t = true, h = true, d = true }
local function SoldItem(Relations, relation)
  local thing = relation.thing or ""
  if ITEM_LETTERS[thing] then return relation.id end
  if thing == "m" then
    local ok, item = pcall(Relations.MountItem, relation.id)
    return ok and item or nil
  end
  if thing == "a" then return nil end
  local ok, item = pcall(Relations.ThingItem, thing, relation.id)
  return ok and item or nil
end

-- [costItemID] = { [soldItemID] = { relation, ... } }, the last few cost
-- items looked up (one Mark of Honor holds about 8,700 purchases)
local purchaseIndex, indexOrder, INDEX_KEPT = {}, {}, 4

local function PurchaseIndex(Relations, costItemID)
  local index = purchaseIndex[costItemID]
  if index then return index end
  index = {}
  local ok, list = pcall(Relations.Of, costItemID, "buys")
  for _, relation in ipairs(ok and list or {}) do
    local item = SoldItem(Relations, relation)
    if item then
      index[item] = index[item] or {}
      table.insert(index[item], relation)
    end
  end
  purchaseIndex[costItemID] = index
  indexOrder[#indexOrder + 1] = costItemID
  if #indexOrder > INDEX_KEPT then purchaseIndex[table.remove(indexOrder, 1)] = nil end
  return index
end

-- What an item buys when it is soldItemID, as plain entries: { item, thing,
-- id, count, costs = { { kind, id, count } } (this item's own first),
-- unlisted, vendors = { npcID }, mapID, serves (for context: true, false, nil) }
function Host.PurchasesOf(costItemID, soldItemID, context)
  local Relations = Recollect.Facts and Recollect.Facts.Relations
  local out = {}
  if not (Relations and Relations.Of) then return out end
  for _, relation in ipairs(PurchaseIndex(Relations, costItemID)[soldItemID] or {}) do
    local vendors = {}
    for i, npc in ipairs(relation.vendors or {}) do vendors[i] = npc end
    out[#out + 1] = { item = soldItemID, thing = relation.thing, id = relation.id, count = relation.count,
      costs = CopyCosts(Relations.Costs(relation, costItemID)), unlisted = relation.unlisted,
      vendors = vendors, mapID = relation.mapID, serves = Serves(relation, context) }
  end
  return out
end

-- The shipped relations of one kind for an item, sources or uses
-- ("soldBy", "dropsFrom", "foundIn", "zoneDrop", "reward", "choice",
-- "objective", "questItem", "starts", "usedAt", "teaches", "reagentOf",
-- "currency" ...): { id, count, price, costs, unlisted, serves, event }
-- (price: a gold-only seller's shipped price in copper, count its stack, nil
-- when the data gives it as "?"; costs: a priced seller's (V) every cost as
-- copied { kind, id, count } entries, gold included, nil for any other
-- relation; unlisted: "costs" or "gold" when part of that price isn't known;
-- event: true for a route only during a holiday or event, the "h" flag)
function Host.Sources(itemID, kind, context)
  local Relations = Recollect.Facts and Recollect.Facts.Relations
  local out = {}
  if not (Relations and Relations.Of) then return out end
  local ok, list = pcall(Relations.Of, itemID, kind)
  if not ok then return out end
  for _, relation in ipairs(list) do
    local costs = type(relation.costs) == "table" and relation.kind == "soldBy" and relation.costs or nil
    out[#out + 1] = { id = relation.id, count = relation.count, price = relation.price, serves = Serves(relation, context),
      event = relation.flags and relation.flags.event and true or nil,
      costs = costs and CopyCosts(costs) or nil, unlisted = costs and costs.unlisted or nil }
  end
  return out
end

-- An NPC's shipped position (its first place): { mapID, x, y } or nil
function Host.NpcPosition(npcID)
  local Vendors = Recollect.Facts and Recollect.Facts.Vendors
  if not (Vendors and Vendors.Position) then return nil end
  local ok, position = pcall(Vendors.Position, npcID)
  if not ok or type(position) ~= "table" then return nil end
  return { mapID = position.mapID, x = position.x, y = position.y }
end

-- Every place the shipped data gives an NPC, the first place first, as
-- { { mapID, x, y } }: an NPC walking a path, with several spawns or in
-- several cities has more than one (data format 7). Empty when none
function Host.NpcPlaces(npcID)
  local Vendors = Recollect.Facts and Recollect.Facts.Vendors
  local out = {}
  if not (Vendors and Vendors.Places) then return out end
  local ok, list = pcall(Vendors.Places, npcID)
  for _, place in ipairs(ok and type(list) == "table" and list or {}) do
    if type(place) == "table" and type(place.mapID) == "number" and place.mapID > 0 and type(place.x) == "number"
      and type(place.y) == "number" then
      out[#out + 1] = { mapID = place.mapID, x = place.x, y = place.y }
    end
  end
  return out
end

-- The Encounter Journal encounter the shipped data maps a boss NPC to (the
-- data's J table: AllTheThings' Encounter nodes), or nil
function Host.EncounterOf(npcID)
  local Relations = Recollect.Facts and Recollect.Facts.Relations
  if not (Relations and Relations.EncounterOf) then return nil end
  local ok, encounterID = pcall(Relations.EncounterOf, npcID)
  return ok and type(encounterID) == "number" and encounterID or nil
end

-- The numbers of a Facts reader's list answer, as a new list (empty when
-- the reader is missing, throws or answers anything else)
local function Numbers(reader, id)
  local out = {}
  if type(reader) ~= "function" then return out end
  local ok, list = pcall(reader, id)
  for _, value in ipairs(ok and type(list) == "table" and list or {}) do
    if type(value) == "number" then out[#out + 1] = value end
  end
  return out
end

-- The Encounter Journal encounters whose loot comes out of a boss loot chest
-- (the data's L table, data format 7: AllTheThings' encounter providers), as
-- a list, empty when the object is none
function Host.EncounterOfObject(objectID)
  local Relations = Recollect.Facts and Recollect.Facts.Relations
  return Numbers(Relations and Relations.EncountersOfObject, objectID)
end

-- The container objects a treasure's spawn object is filed under (the data's
-- S table, data format 7: the loot of any spawn is the container's), as a
-- list, empty when none
function Host.ObjectAlias(objectID)
  local Vendors = Recollect.Facts and Recollect.Facts.Vendors
  return Numbers(Vendors and Vendors.ObjectAliases, objectID)
end

-- What the shipped data says combining an item makes: { count (how many of
-- it one combine takes), product (item ID, or nil while unconfirmed), parts
-- (true for a combine of several different parts) }, from its makes ("m",
-- "mx") and part-of ("e") codes
function Host.Combines(itemID)
  local Relations = Recollect.Facts and Recollect.Facts.Relations
  local out = {}
  if not (Relations and Relations.Of) then return out end
  local okMakes, makes = pcall(Relations.Of, itemID, "makes")
  for _, relation in ipairs(okMakes and makes or {}) do
    if relation.count then out[#out + 1] = { count = relation.count, product = relation.id } end
  end
  local okParts, parts = pcall(Relations.Of, itemID, "partOf")
  for _, relation in ipairs(okParts and parts or {}) do
    for _, part in ipairs(relation.parts or {}) do
      if part.itemID == itemID then out[#out + 1] = { count = part.count, product = relation.id, parts = true } end
    end
  end
  return out
end

-- An NPC's name in the player's language, or nil until the client has it
-- (a boss by its journal entry, else its creature tooltip, read again later
-- after a miss)
function Host.NpcName(npcID)
  local Vendors = Recollect.Facts and Recollect.Facts.Vendors
  if not (Vendors and Vendors.NpcName) then return nil end
  local ok, name = pcall(Vendors.NpcName, npcID)
  return ok and type(name) == "string" and name ~= "" and name or nil
end

-- A map's name in the player's language, or nil
function Host.ZoneName(mapID)
  local Vendors = Recollect.Facts and Recollect.Facts.Vendors
  if not (Vendors and Vendors.ZoneName) then return nil end
  local ok, name = pcall(Vendors.ZoneName, mapID)
  return ok and type(name) == "string" and name ~= "" and name or nil
end

-- A quest's G record as plain values, or nil
local function QuestRecord(questID)
  local Relations = Recollect.Facts and Recollect.Facts.Relations
  if not (Relations and Relations.QuestGiver) then return nil end
  local ok, giver = pcall(Relations.QuestGiver, questID)
  if not ok or type(giver) ~= "table" then return nil end
  local givers = {}
  for _, npc in ipairs(type(giver.npcIDs) == "table" and giver.npcIDs or {}) do
    if type(npc) == "number" then givers[#givers + 1] = npc end
  end
  local first = type(giver.npcID) == "number" and giver.npcID or givers[1]
  if first and givers[1] == nil then givers[1] = first end
  return { npcID = first, npcIDs = givers, mapID = giver.mapID, x = giver.x, y = giver.y }
end

-- The NPC the shipped data says gives a quest, or nil; and, second, every
-- giver it lists (the first first; a quest with a giver in each faction's
-- camp lists both since data format 7), a new list, empty with no giver
function Host.QuestGiver(questID)
  local record = QuestRecord(questID)
  if not record then return nil, {} end
  return record.npcID, record.npcIDs
end

-- Where the shipped data says a quest starts: { npcID, npcIDs, mapID, x, y }
-- (x and y from 0 to 1; npcIDs every giver, npcID the one the place was
-- taken with, or the first listed), or nil. The place is the quest's, not
-- one giver's: with several givers it may be another giver's spot
function Host.QuestPlace(questID)
  local record = QuestRecord(questID)
  if not (record and type(record.mapID) == "number" and type(record.x) == "number" and type(record.y) == "number") then
    return nil
  end
  return record
end

-- The NPCs the shipped data says take a quest's turn-in (the Z table, data
-- format 10), a new list of IDs, ascending; empty when it names none
function Host.QuestTurnIns(questID)
  local Relations = Recollect.Facts and Recollect.Facts.Relations
  local out = {}
  if not (Relations and Relations.QuestTurnIns) then return out end
  local ok, list = pcall(Relations.QuestTurnIns, questID)
  if not ok or type(list) ~= "table" then return out end
  for _, npc in ipairs(list) do
    if type(npc) == "number" then out[#out + 1] = npc end
  end
  return out
end

-- A quest's shipped frequency letters ("d" daily, "w" weekly, "y" yearly,
-- "m" monthly, "q" world quest ...), or nil
function Host.QuestFrequency(questID)
  local Relations = Recollect.Facts and Recollect.Facts.Relations
  if not (Relations and Relations.Frequency) then return nil end
  local ok, flags = pcall(Relations.Frequency, questID)
  return ok and type(flags) == "string" and flags or nil
end

-- A recipe's shipped schematic summary: { skillLine, product, quantity }, or nil
function Host.Recipe(spellID)
  local Relations = Recollect.Facts and Recollect.Facts.Relations
  if not (Relations and Relations.Recipe) then return nil end
  local ok, recipe = pcall(Relations.Recipe, spellID)
  if not ok or type(recipe) ~= "table" then return nil end
  return { skillLine = recipe.skillLine, product = recipe.product, quantity = recipe.quantity }
end

-------------------------------------------------------------------------------
-- Items with no information (Recorders/NoInfo.lua)
-------------------------------------------------------------------------------
-- The items a confirmed known use names (its parts, the reward item, the
-- item a vendor sells for it), built once per Data.Uses table. An entry
-- with no confirmed line is ignored by the checks, so it is no information.
local usesFor, usesSet
local function ConfirmedUses()
  local uses = Recollect.Data and Recollect.Data.Uses
  if usesSet and usesFor == uses then return usesSet end
  local set = {}
  for _, entry in ipairs(type(uses) == "table" and uses or {}) do
    if type(entry) == "table" and type(entry.confirmed) == "string" and entry.confirmed ~= "" then
      for itemID in pairs(type(entry.parts) == "table" and entry.parts or {}) do
        if type(itemID) == "number" then set[itemID] = true end
      end
      if type(entry.rewardItem) == "number" then set[entry.rewardItem] = true end
      if type(entry.sold) == "number" then set[entry.sold] = true end
    end
  end
  usesFor, usesSet = uses, set
  return set
end

-- What the shipped data says of one item, without its quality siblings:
-- the reason it counts as known, or nil when it says nothing. A read that
-- fails counts as known ("unreadable"): nothing is recorded on a guess.
local function OwnInformation(itemID)
  local Facts = Recollect.Facts or {}
  local Data = Recollect.Data or {}
  local Relations = Facts.Relations
  local ok, codes = pcall(Relations and Relations.Codes or function() return nil end, itemID)
  if not ok then return "unreadable" end
  if type(codes) == "string" and codes ~= "" then return "codes" end
  local okRemoved, removed = pcall(Relations and Relations.RemovedIn or function() return nil end, itemID)
  if not okRemoved then return "unreadable" end
  if removed then return "removed" end
  if type(Data.Descriptions) == "table" and Data.Descriptions[itemID] then return "description" end
  local okNotes, notes = pcall(Facts.Notes and Facts.Notes.For or function() return nil end, itemID)
  if not okNotes then return "unreadable" end
  if type(notes) == "table" and #notes > 0 then return "note" end
  local okUses, uses = pcall(ConfirmedUses)
  if not okUses then return "unreadable" end
  if uses[itemID] then return "use" end
  if type(Data.Residual) == "table" and Data.Residual[itemID] then return "leftover" end
  return nil
end

-- Knows(itemID): whether the shipped data this client loaded says anything
-- at all about an item, as { known, why }. Known: relation codes of any
-- letter (routes no longer available included), a removal patch, a
-- description, a guide note, a confirmed known use naming it, a leftover
-- note, or a quality sibling that has one of those (Relations.Family, once
-- the data ships a family table). An added patch alone is not information.
-- The data off counts as known ("data off"), and so does anything that
-- can't be read: nothing is recorded then.
function Host.Knows(itemID)
  if type(itemID) ~= "number" or Host.IsSecret(itemID) or itemID <= 0 then return { known = true, why = "not an item" } end
  if Host.Versions().ok ~= true then return { known = true, why = "data off" } end
  local why = OwnInformation(itemID)
  if why then return { known = true, why = why } end
  local Relations = Recollect.Facts and Recollect.Facts.Relations
  if Relations and type(Relations.Family) == "function" then
    local ok, family = pcall(Relations.Family, itemID)
    for _, sibling in ipairs(ok and type(family) == "table" and family or {}) do
      if type(sibling) == "number" and sibling ~= itemID and OwnInformation(sibling) then
        return { known = true, why = "sibling" }
      end
    end
  end
  return { known = false, why = "nothing" }
end

-- StoredItems(): the items in the logged-in character's stored bank tabs
-- and in the warband bank's, as { { id, where = "bank" or "wb", quality } },
-- one per item and place, from Recollect's stored reads (never a bank frame,
-- never another character's bank, no counts). quality is nil when the
-- stored read has none.
function Host.StoredItems()
  local Inventory = Recollect.Inventory
  local Snapshots, Locations = Inventory.Snapshots, Inventory.Locations
  local out, seen = {}, {}
  local function Add(entry, where)
    local slots = type(entry) == "table" and type(entry.read) == "table" and entry.read.slots
    for _, stack in pairs(type(slots) == "table" and slots or {}) do
      local id = type(stack) == "table" and stack.itemID
      local key = type(id) == "number" and id > 0 and (id .. "@" .. where)
      if key and not seen[key] then
        seen[key] = true
        out[#out + 1] = { id = id, where = where, quality = type(stack.quality) == "number" and stack.quality or nil }
      end
    end
  end
  local okChar, char = pcall(Snapshots.CurrentCharacter, false)
  for bagID, entry in pairs(okChar and type(char) == "table" and type(char.locations) == "table" and char.locations or {}) do
    if Locations.KindOf(bagID) == Locations.KIND_BANK then Add(entry, "bank") end
  end
  local okWarband, warband = pcall(Snapshots.Warband)
  for bagID, entry in pairs(okWarband and type(warband) == "table" and warband or {}) do
    if Locations.KindOf(bagID) == Locations.KIND_WARBAND then Add(entry, "wb") end
  end
  table.sort(out, function(a, b)
    if a.where ~= b.where then return a.where < b.where end
    return a.id < b.id
  end)
  return out
end

-- OnSnapshotCaptured(fn): fn() whenever Recollect stores a bank tab it read;
-- returns a function that stops it
function Host.OnSnapshotCaptured(fn)
  local listener = {}
  function listener:ReceiveEvent() fn() end
  local events = { Recollect.Events.SnapshotCaptured }
  Recollect.EventBus:Register(listener, events)
  return function() Recollect.EventBus:Unregister(listener, events) end
end

-- The bags' item counts ({ [itemID] = count }, bags 0 to 5), or nil when a
-- bag can't be read completely
function Host.BagTotals()
  local Inventory = Recollect.Inventory
  local reads = {}
  for _, bagID in ipairs(Inventory.Locations.Bags()) do
    local read = Inventory.Reader.ReadContainer(bagID)
    if read.readable then
      if not read.complete then return nil end
      reads[#reads + 1] = read
    end
  end
  return Recollect.Verdicts.Rows.Totals(reads)
end

-------------------------------------------------------------------------------
-- Checks
-------------------------------------------------------------------------------
-- Whether a shipped code's route conditions (the flags after "|", such as
-- "|f1" or "|c2.8") include a character context { faction (0 Horde,
-- 1 Alliance, as Enum.PvPFaction and the shipped f0/f1), classID, raceID }:
-- true, false, or nil when it can't be told. A route no longer in the game
-- ("x") is false. Holiday routes ("h") are true: the flag is display only
-- (D34) and Applies ignores it; an event route is kept from any not seen by
-- Sources' event field (Compare.lua's MayBeMissing).
function Host.ConditionsInclude(code, itemID, context)
  local Relations = Recollect.Facts and Recollect.Facts.Relations
  if not (Relations and Relations.Applies and Relations.Parse) or type(context) ~= "table" then return nil end
  local okParse, relation = pcall(Relations.Parse, code, itemID)
  if not okParse or type(relation) ~= "table" then return nil end
  local owner = { faction = context.faction, classID = context.classID, raceID = context.raceID }
  local ok, applies = pcall(Relations.Applies, relation, owner)
  if not ok then return nil end
  if applies == true then return true end
  if applies == "unavailable" or applies == "other" then return false end
  return nil
end

-------------------------------------------------------------------------------
-- Services
-------------------------------------------------------------------------------
function Host.Log(format, ...)
  Recollect.Debug.Log("CURATOR", format, ...)
end

function Host.Print(text)
  Recollect.Utilities.Message(text)
end

-- Is a value secret (12.x)? The curator records nothing it can't read.
function Host.IsSecret(value)
  return Recollect.Utilities.IsSecret(value) and true or false
end

-- Registers the curator's provider for Recollect's hooks (the settings
-- category, the guide section, /rec curator and /rec feedback, the details
-- window's Curator Flag button)
function Host.RegisterProvider(provider)
  if Recollect.RegisterCuratorProvider then Recollect.RegisterCuratorProvider(provider) end
end

-- Opens Recollect's settings window at a category ("curator"); false when
-- it can't open (not built yet, or in combat before it was)
function Host.OpenSettings(category)
  local Config = Recollect.Config
  local open = Config and (Config.OpenSettingsAt or Config.OpenSettings)
  if not open then return false end
  local ok = pcall(open, category)
  return ok
end

-- Tells Recollect a curator setting changed, so its settings window repaints
-- that row (the window watches Recollect's ConfigChanged event)
function Host.NotifyConfigChanged(key)
  Recollect.EventBus:Fire(Recollect.Events.ConfigChanged, key)
end

-- Tells Recollect the curator's notes changed (a flag saved, sent or
-- delivered), so the details window repaints its Curator Flag button
function Host.NotesChanged()
  Recollect.EventBus:Fire(Recollect.Events.CuratorNotesChanged)
end

-- Opens Recollect's debug log window (the curator test, when it finishes,
-- so its report is one Copy All away); nothing in combat
function Host.OpenDebugLog()
  local window = Recollect.DebugWindow
  if not window or InCombatLockdown() then return false end
  local ok = pcall(function() if not window:IsShown() then window:Show() end end)
  return ok
end

-- Runs fn once Recollect's SavedVariables and config are loaded
function Host.OnLoaded(fn)
  EventUtil.ContinueOnAddOnLoaded("Recollect", fn)
end
