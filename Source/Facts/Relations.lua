-------------------------------------------------------------------------------
-- Facts.Relations: what the game's data says an item is for
--
-- Reads Data/Relations.lua (built by /recollect-data from the Lab's big dump
-- and AllTheThings' database; IDs only). Each bucket (item ID // BUCKET) is one string of records:
-- byte 30, the item ID, byte 31, its codes joined by ";". A code is a letter
-- and numbers:
--   o<quest>x<n>       an objective of <quest> names this item (n needed)
--   w<quest>           <quest> rewards this item
--   k<quest>           <quest> offers this item as a choice
--   a<ach>.<crit>x<n>  criterion <crit> of achievement <ach> counts it
--   m<item>x<n>        its Use text combines <n> of it into <item>
--   mx<n>              it combines <n> of it, and what that makes is
--                      unconfirmed (the sources disagree; unresolved = true)
--   f<item>x<n>        it is made from <n> of <item>
--   e<item>@<part>x<n>,...  it is one of the different parts whose Use text
--                      combines them into <item> (parts = { { itemID,
--                      count } }, this item among them)
--   p<item>            this recipe teaches how to make <item>
--   t<item>            it is made with the recipe <item>
--   $<currency>[x<n>]  its Use text names <currency>, or a phrase for it
--                      (n of it: an anima vessel's "Infuse 35 stored Anima")
--   d<decor>x<n>       <n> of it buy the housing decor <decor> (the decor's
--                      catalog source text lists the cost)
--   g<spell>x<n>       <n> of it are a reagent of recipe <spell> (the Lab read
--                      its schematic; Recipe(spell) says what it makes)
-- From AllTheThings and the Lab's vendor recorder:
--   b<t><id>x<n>[+<cost>...][@<npcs>|#<map>]  <n> of it buy a thing at those
--                      vendors ("," between them; "@..." left out when none is
--                      named; "#<map>" when no vendor is named but the trade's
--                      place is, mapID). Each other cost of the trade follows a
--                      "+": i<item>x<n>, c<currency>x<n>, g<copper>; "?" when
--                      the whole price is not known, "g?" when a recorded
--                      trade's gold price was not recorded (unlisted = "costs"
--                      or "gold"); a bare "+" is other costs not listed. plus
--                      is true when the trade has other costs; costs (For, or
--                      Costs(relation, itemID)) lists every cost, this item's
--                      own first: { kind = "item" | "currency" | "gold", id
--                      (nil for gold), count (copper for gold) }.
--                      <t> says what the thing's state is read from (thing):
--                      "" a plain item, t a toy item, m a mount spell, p a pet
--                      species, d a decor item, e an ensemble set, h an
--                      heirloom item, r a recipe spell, l a weapon illusion,
--                      a an achievement
--   u<quest>[x<n>]     <quest> uses it (a quest item), or takes n of it
--   s<quest>           it starts <quest> (ATT's qss and quest providers)
--   j<object>[x<n>]    it opens <object> (a key to a treasure; the object's
--                      place, loot quest and contents in Data/Vendors.lua),
--                      taking n of it
--   n<npc>[x<n>]       it is used at <npc>, n of it (to summon it, handed
--                      over, or to play a game there)
--   l<ach>.<crit>      AllTheThings links it to criterion <crit> of <ach>
--   r<spell>           this recipe item teaches recipe <spell>
--   v<npc>             vendor <npc> sells it
--   V<npc>x<n>+<cost>[+<cost>...]  vendor <npc> sells n of it at a price
--                      with no item cost, each cost as a b code's ("+c1792x350",
--                      "+g2500", "+?", "+g?"): a seller like v (kind soldBy),
--                      with count (the stack; "x?" when it isn't known, count
--                      nil) and costs (every cost, shared and read-only, with
--                      costs.unlisted as a b code's); a gold-only one also has
--                      price (copper), as before data format 8. The data ships it
--                      in place of v for that vendor and conditions: gold-only
--                      trades from curator findings (format 3), currency prices
--                      from AllTheThings, the Lab's vendor recorder and curator
--                      findings (format 8, 2026-09-29)
--   c<npc>             creature <npc> drops it
--   i<object>          it is found in <object> (a treasure; its place in
--                      Data/Vendors.lua objects)
--   z<map>             enemies in zone <map> drop it (ATT's Zone Drop)
--   y<spell>           recipe <spell> crafts it (the Lab read its schematic;
--                      Recipe(spell) says which profession)
--   A<ach>             achievement <ach> rewards it (the game's reward text for
--                      the achievement names it; AllTheThings gives the ID)
-- Sources since data format 4 (the Lab's big dump and AllTheThings):
--   D<encounter>       it is in the Encounter Journal's loot of <encounter>
--                      (a journal encounter ID, as EJ_GetEncounterInfo takes;
--                      left out where a c code's boss is the same encounter)
--   N<faction>.<level> a renown reward of major faction <faction> at renown
--                      <level> (id = faction, level)
--   O<n>               sometimes offered on the Black Market Auction House
--                      (n is always 1, reserved)
--   U<yyyymm>          offered at the Trading Post, in the month AllTheThings
--                      files it under (202503), 0 when not known (id = yyyymm)
-- Any code may end in "|" and flags, the route's conditions (flags):
--   x unavailable (no longer available), f0 / f1 faction (Horde / Alliance
--   only, as PvPFaction), c<id.id> classes (class IDs), h event (only
--   during a holiday or seasonal event), R<id.id> races (race IDs)
-- and conditions a character can still meet, shown and never deciding
-- anything (curator spec D34; relation.shows, never in flags): P<skillLine>
-- a profession (professions = { skillLine }), E<faction>.<standing> a
-- reputation standing (standing = { factionID, standing }, 1 Hated to 8
-- Exalted), N<faction>.<level> a renown level with a major faction (renown
-- = { factionID, level }), Q<quest> after a completed quest (quests = {
-- questID }, one Q per quest), A<ach> an achievement earned (achievements =
-- { achievementID }, one A per achievement: "v255503|A62562A62563", what
-- buying the Unbound Manawyrm requires). AllTheThings gives E, N, Q and A
-- for purchases (b, v), accepted curator findings any of them. A route
-- whose only conditions are these has no flags, so it serves every character
-- exactly as one with none.
-- For(itemID) returns { { kind, id, criteria, count, level, thing, vendors, plus,
-- costs, costText, unlisted, mapID, seller, unresolved, parts, price, flags, shows } }, uses first (objective, questItem, starts, opens,
-- usedAt, criterion, linked, buysDecor, buys, partOf, makes, reagentOf, currency,
-- recipeFor, teaches), then where it comes from (Relations.SOURCE: madeFrom,
-- craftedBy, taughtBy, reward, choice, achievementReward, soldBy,
-- renownReward, blackMarket, tradingPost, dropsFrom, journalDrop, foundIn,
-- zoneDrop; ORDER lists every kind, since the sort compares by it), parsed once per item and
-- kept for the session. Names, titles and states are read live by the
-- modules that use a relation; Applies(relation, owner) says whether a route
-- serves a character (SRC-01), and Conditions(relation, owner) which of its
-- conditions the character misses, as tags for display only (D34: an event
-- route is tagged but served as any other). QuestGiver(questID) says where a quest
-- starts (the data's G table: its givers and place, from AllTheThings; every
-- giver since data format 7, the one standing at that place first).
-- EncountersOfObject(objectID) lists the Encounter Journal encounters whose
-- loot comes out of a boss loot chest (the L table, format 7), and
-- EncounterOfObject the first.
-- QuestRewards(questID) says what a quest a use code names rewards (the W
-- table: each thing typed as a purchase's is), and ItemThing(itemID) what a
-- combine's product is when it is a collectible (the K table). RemovedIn(itemID)
-- gives the patch in which every route to the item was removed from the game
-- (the X table, from AllTheThings: 120100 is 12.1.0), and AddedIn(itemID) the
-- patch it was added: for those items when known, and for an item still in
-- the game when that patch's expansion is later than the one the game files it
-- under (the A table: the Seal Breaker Key, a Maw key the game calls Battle
-- for Azeroth's, 90100). RecipesOf(skillLine) lists the recipe spells the
-- data knows for a profession (the S table), for curator mode.
-- MetasOf(achievementID) lists the meta achievements an achievement counts
-- toward, and ChildrenOf(metaID) the achievements a meta achievement asks
-- for (data format 5's H and I tables, from the big dump's achievement
-- criteria of type 8, CRITERIA_TYPE_ACHIEVEMENT: the criterion's asset is
-- the achievement to earn), each ascending; an empty list when the data
-- names none, or has no such table (a file of an older format). Nothing is
-- read while Facts.DataVersion has the shipped data off (its files of
-- different versions, or of a format this Recollect doesn't read).
-------------------------------------------------------------------------------
local Relations = {}
Recollect.Facts.Relations = Relations

local BUCKET = 1024
local KIND = {
  o = "objective", w = "reward", k = "choice", a = "criterion", m = "makes", f = "madeFrom",
  p = "recipeFor", t = "taughtBy", ["$"] = "currency", d = "buysDecor", g = "reagentOf",
  b = "buys", u = "questItem", s = "starts", v = "soldBy", c = "dropsFrom", j = "opens", n = "usedAt",
  l = "linked", r = "teaches", i = "foundIn", z = "zoneDrop", y = "craftedBy", e = "partOf",
  A = "achievementReward", V = "soldBy", D = "journalDrop", N = "renownReward", O = "blackMarket", U = "tradingPost",
}
-- Every kind must be here: Less compares ORDER[kind], and a kind missing
-- from it would throw in the sort (build_data.py's KIND_RANK ships the codes
-- in this order, so the sort is skipped)
local ORDER = { objective = 1, questItem = 2, starts = 3, opens = 4, usedAt = 5, criterion = 6, linked = 7,
  buysDecor = 8, buys = 9, partOf = 10, makes = 11, reagentOf = 12, currency = 13, recipeFor = 14, teaches = 15,
  madeFrom = 16, craftedBy = 17, taughtBy = 18, reward = 19, choice = 20, achievementReward = 21, soldBy = 22,
  renownReward = 23, blackMarket = 24, tradingPost = 25, dropsFrom = 26, journalDrop = 27, foundIn = 28, zoneDrop = 29 }

-- Kinds that say where an item comes from, not what it is for
Relations.SOURCE = { madeFrom = true, taughtBy = true, reward = true, choice = true, soldBy = true, dropsFrom = true,
  foundIn = true, zoneDrop = true, craftedBy = true, achievementReward = true, journalDrop = true, renownReward = true,
  blackMarket = true, tradingPost = true }

-- Kinds whose body is a number alone (no "x<n>")
local NUMBER_ONLY = { journalDrop = true, blackMarket = true, tradingPost = true }

-- "xf0c8.13h": the route's conditions, or nil for none. One table per
-- distinct text, shared by every relation that carries it (read-only):
-- thousands of routes carry the same few flags
local flagsOf = {}
local function Flags(text)
  if not text or text == "" then return nil end
  local shared = flagsOf[text]
  if shared then return shared end
  local flags = {}
  if text:find("x", 1, true) then flags.unavailable = true end
  local faction = text:match("f(%d)")
  if faction then flags.faction = tonumber(faction) end
  local classes = text:match("c([%d%.]+)")
  if classes then
    flags.classes = {}
    for id in classes:gmatch("%d+") do flags.classes[tonumber(id)] = true end
  end
  if text:find("h", 1, true) then flags.event = true end
  local races = text:match("R([%d%.]+)")
  if races then
    flags.races = {}
    for id in races:gmatch("%d+") do flags.races[tonumber(id)] = true end
  end
  flagsOf[text] = flags
  return flags
end

-- The display-only conditions (P, E, N, Q, A) of a flags text, one shared table
-- per distinct text (read-only), or nil for none; and the text without them,
-- for Flags (a text with nothing else then gives nil flags)
local showsOf, plainOf = {}, {}
local function Shows(text)
  local cached = showsOf[text]
  if cached ~= nil then return cached or nil, plainOf[text] end
  local shows = {}
  for id in text:gmatch("P(%d+)") do
    shows.professions = shows.professions or {}
    shows.professions[#shows.professions + 1] = tonumber(id)
  end
  local faction, standing = text:match("E(%d+)%.(%d+)")
  if faction then shows.standing = { factionID = tonumber(faction), standing = tonumber(standing) } end
  local renownFaction, level = text:match("N(%d+)%.(%d+)")
  if renownFaction then shows.renown = { factionID = tonumber(renownFaction), level = tonumber(level) } end
  for id in text:gmatch("Q(%d+)") do
    shows.quests = shows.quests or {}
    shows.quests[#shows.quests + 1] = tonumber(id)
  end
  for id in text:gmatch("A(%d+)") do
    shows.achievements = shows.achievements or {}
    shows.achievements[#shows.achievements + 1] = tonumber(id)
  end
  local plain = text:gsub("P%d+", ""):gsub("E%d+%.%d+", ""):gsub("N%d+%.%d+", ""):gsub("Q%d+", ""):gsub("A%d+", "")
  if not next(shows) then shows = nil end
  showsOf[text], plainOf[text] = shows or false, plain
  return shows, plain
end

-- "@212419,212420": the vendor list, one shared table per distinct list
-- (read-only; Mark of Honor's purchases, about 8,700, name a handful of vendors)
local vendorsOf = {}
local function VendorList(at)
  local list = vendorsOf[at]
  if list then return list end
  list = {}
  for npc in at:sub(2):gmatch("%d+") do list[#list + 1] = tonumber(npc) end
  vendorsOf[at] = list
  return list
end
local NO_VENDORS = {}

-- "+i32572x4+c1813x25+g250000": a trade's other costs, one shared list per
-- distinct text (read-only), with unlisted "costs" ("?" or a bare "+": more
-- costs the data doesn't list) or "gold" ("g?": a recorded trade whose gold
-- price was not recorded); nil for a text that doesn't parse
local othersOf = {}
local COST_KIND = { i = "item", c = "currency" }
local function OtherCosts(text)
  local list = othersOf[text]
  if list then return list end
  if text:sub(1, 1) ~= "+" then return nil end
  list = {}
  for part in text:gmatch("%+([^+]*)") do
    local letter, id, n = part:match("^([ic])(%d+)x(%d+)$")
    local copper = part:match("^g(%d+)$")
    if letter then
      list[#list + 1] = { kind = COST_KIND[letter], id = tonumber(id), count = tonumber(n) }
    elseif copper then
      list[#list + 1] = { kind = "gold", count = tonumber(copper) }
    elseif part == "g?" then
      if list.unlisted ~= "costs" then list.unlisted = "gold" end
    elseif part == "?" or part == "" then
      list.unlisted = "costs"
    else
      return nil
    end
  end
  othersOf[text] = list
  return list
end
local NO_COSTS = {}

-- Every cost of a trade, this item's own first, then the others as the code
-- lists them; one shared list per item, count and other costs (read-only),
-- dropped with the parses' older generation
local costsOf = {}
local function CostList(itemID, count, text)
  local key = itemID .. "x" .. count .. text
  local list = costsOf[key]
  if list then return list end
  local others = text ~= "" and OtherCosts(text) or NO_COSTS
  list = { { kind = "item", id = itemID, count = count } }
  for i = 1, #others do list[i + 1] = others[i] end
  costsOf[key] = list
  return list
end

-- A purchase's costs are read through a metatable shared by every purchase
-- of the same item, count and price (relation.costs), so the relation's own
-- table keeps the size it had before costs were shipped: Mark of Honor's
-- purchases (about 8,700) parse into 3.9 MB that way, 6.1 MB with the list stored on
-- each. Its __index is a table, not a function, so reading a field a
-- relation lacks (flags, mapID) costs no call. Dropped with the parses'
-- older generation
local metaOf = {}
local function CostsMeta(itemID, count, text)
  local key = itemID .. "x" .. count .. text
  local meta = metaOf[key]
  if meta then return meta end
  meta = { __index = { costs = CostList(itemID, count, text) } }
  metaOf[key] = meta
  return meta
end

-- "b<t><id>x<n>[+<cost>...]@<npc>,<npc>" or "...#<map>": what a cost buys,
-- for how many, at what whole price, and where; costs only when the owner
-- item is given
local function ParseBuys(body, itemID)
  local thing, id, n, rest = body:match("^(%a?)(%d+)x(%d+)(.*)$")
  if not id then return nil end
  local text, where = rest:match("^([^@#]*)(.*)$")
  local others = NO_COSTS
  if text ~= "" then
    others = OtherCosts(text)
    if not others then return nil end
  end
  local vendors, mapID = NO_VENDORS, nil
  local mark = where:sub(1, 1)
  if mark == "@" then
    if not where:match("^@[%d,]+$") then return nil end
    vendors = VendorList(where)
  elseif mark == "#" then
    mapID = tonumber(where:match("^#(%d+)$"))
    if not mapID then return nil end
  end
  local count = tonumber(n)
  local relation = { kind = "buys", thing = thing, id = tonumber(id), count = count, vendors = vendors,
    plus = #others > 0 or others.unlisted == "costs" }
  -- Fields most purchases don't have are set only when present, so the
  -- relation's table stays small (Mark of Honor alone is about 8,700 of them)
  if text ~= "" then relation.costText = text end
  relation.unlisted = others.unlisted
  relation.mapID = mapID
  -- seller: the vendor list as written ("@212419,212420"), which names the
  -- panel's seller group without building a key for each of thousands
  if mark == "@" then relation.seller = where end
  if Recollect.Utilities.IsPositiveID(itemID) then setmetatable(relation, CostsMeta(itemID, count, text)) end
  return relation
end

-- Every cost of a buys relation, this item's own first ({ kind, id, count };
-- see the b code above), for a relation parsed without its item; nil for
-- any other kind
function Relations.Costs(relation, itemID)
  if type(relation) ~= "table" or relation.kind ~= "buys" then return nil end
  local costs = relation.costs
  if costs then return costs end
  if not Recollect.Utilities.IsPositiveID(itemID) then return nil end
  return CostList(itemID, relation.count, relation.costText or "")
end

-- The session's parses, in two generations so memory stays bounded however
-- many items are looked at: a hit in the older one moves the list to the
-- newer, and once the newer holds CACHE_RELATIONS relations it becomes the
-- older (the oldest is dropped). Mark of Honor alone is about 8,700.
local CACHE_RELATIONS = 12000
local newer, older, newerSize = {}, {}, 0

-- A list costs its relations, and an empty one 1, so items with no relations
-- rotate out too
local function Keep(itemID, list)
  local cost = math.max(1, #list)
  if newerSize > 0 and newerSize + cost > CACHE_RELATIONS then
    older, newer, newerSize = newer, {}, 0
    costsOf, metaOf = {}, {}
  end
  newer[itemID] = list
  newerSize = newerSize + cost
end

local function Cached(itemID)
  local list = newer[itemID]
  if list then return list end
  list = older[itemID]
  if list then Keep(itemID, list) end
  return list
end

-- The shipped data, or an empty table while Facts.DataVersion has it off
-- (files of another version or an unsupported format)
local EMPTY = {}
local function Data()
  local version = Recollect.Facts.DataVersion
  if version and not version.Ok() then return EMPTY end
  return Recollect.Data and Recollect.Data.Relations
end

-- The record for key in a bucketed table (B by item, Q by quest), or nil
local function Record(tbl, key)
  local bucket = tbl and tbl[math.floor(key / BUCKET)]
  if type(bucket) ~= "string" then return nil end
  local _, stop = bucket:find("\30" .. key .. "\31", 1, true)
  if not stop then return nil end
  local finish = bucket:find("\30", stop + 1, true)
  return bucket:sub(stop + 1, (finish or 0) - 1)
end

-- The codes string for an item, or nil
function Relations.Codes(itemID)
  local data = Data()
  return Record(data and data.B, itemID)
end

-- "e<product>@<part>x<n>,<part>x<n>": the product and every part, with how many
local function ParseParts(body)
  local id, list = body:match("^(%d+)@(.+)$")
  if not id then return nil end
  local parts = {}
  for part in list:gmatch("[^,]+") do
    local item, n = part:match("^(%d+)x(%d+)$")
    if not item then return nil end
    parts[#parts + 1] = { itemID = tonumber(item), count = tonumber(n) }
  end
  if #parts < 2 then return nil end
  return { kind = "partOf", id = tonumber(id), parts = parts }
end

-- "V<npc>x<n>+<cost>[+<cost>...]": a priced trade with no item cost, read as
-- a seller with its stack and costs (OtherCosts' list, shared, read-only);
-- "x?" when the stack isn't known (count nil). A gold-only one also gives
-- price, in copper, exactly as before data format 8 (2026-09-29), so every
-- reader of price reads only gold-only trades. A tail with no stated cost
-- ("+?" alone) says no more than a plain v, and doesn't parse
local function ParsePriced(body)
  local npc, n, text = body:match("^(%d+)x([%d%?]+)(%+.*)$")
  if not npc or (n ~= "?" and not n:match("^%d+$")) then return nil end
  local costs = OtherCosts(text)
  if not costs or #costs == 0 then return nil end
  local relation = { kind = "soldBy", id = tonumber(npc), count = tonumber(n), costs = costs }
  if #costs == 1 and costs[1].kind == "gold" and not costs.unlisted then relation.price = costs[1].count end
  return relation
end

local function ParseBody(kind, body, itemID)
  if kind == "buys" then return ParseBuys(body, itemID) end
  if kind == "partOf" then return ParseParts(body) end
  if kind == "criterion" then
    local ach, crit, n = body:match("^(%d+)%.(%d+)x(%d+)$")
    if not ach then return nil end
    return { kind = kind, id = tonumber(ach), criteria = tonumber(crit), count = tonumber(n) }
  end
  if kind == "linked" then
    local ach, crit = body:match("^(%d+)%.(%d+)$")
    if not ach then return nil end
    return { kind = kind, id = tonumber(ach), criteria = tonumber(crit) }
  end
  if kind == "makes" then
    local n = body:match("^x(%d+)$")
    if n then return { kind = kind, count = tonumber(n), unresolved = true } end
  end
  if kind == "renownReward" then
    local faction, level = body:match("^(%d+)%.(%d+)$")
    if not faction then return nil end
    return { kind = kind, id = tonumber(faction), level = tonumber(level) }
  end
  if NUMBER_ONLY[kind] then
    local only = body:match("^(%d+)$")
    return only and { kind = kind, id = tonumber(only) } or nil
  end
  local id, n = body:match("^(%d+)x(%d+)$")
  if id then return { kind = kind, id = tonumber(id), count = tonumber(n) } end
  id = body:match("^(%d+)$")
  if not id then return nil end
  return { kind = kind, id = tonumber(id) }
end

-- One code as a relation, or nil for a code this build does not know;
-- itemID, the item whose code it is, gives a purchase its costs
function Relations.Parse(code, itemID)
  local letter = code:sub(1, 1)
  local kind = KIND[letter]
  if not kind then return nil end
  local body, flags = code:sub(2), nil
  local bar = body:find("|", 1, true)
  if bar then body, flags = body:sub(1, bar - 1), body:sub(bar + 1) end
  local relation
  if letter == "V" then relation = ParsePriced(body) else relation = ParseBody(kind, body, itemID) end
  if relation and flags and flags ~= "" then
    local shows, plain = Shows(flags)
    relation.flags, relation.shows = Flags(plain), shows
  end
  return relation
end

local function Less(a, b)
  if a.kind ~= b.kind then return ORDER[a.kind] < ORDER[b.kind] end
  if (a.id or 0) ~= (b.id or 0) then return (a.id or 0) < (b.id or 0) end
  return (a.count or 0) < (b.count or 0)
end

-- Whether a list is in order already (the data ships every item's codes in
-- this order, so the sort is skipped)
local function InOrder(list)
  for i = 2, #list do
    if Less(list[i], list[i - 1]) then return false end
  end
  return true
end

-- Where each kind sits in a long parsed list ({ [kind] = { first, last } }),
-- keyed weakly by the list, so Of copies one range instead of scanning the
-- whole list for every kind asked (Mark of Honor has about 8,700 relations,
-- and a verdict asks for 8 kinds). Only lists For itself sorted have one;
-- any other list (a substituted For in the suites) is scanned.
local kindRanges = setmetatable({}, { __mode = "k" })
local RANGE_MIN = 16   -- shorter lists are scanned: an index would cost more than it saves

local function IndexKinds(list)
  if #list < RANGE_MIN then return end
  local ranges, last = {}, nil
  for i, relation in ipairs(list) do
    local kind = relation.kind
    local range = ranges[kind]
    if not range then
      ranges[kind] = { i, i }
    elseif kind ~= last then
      return   -- not grouped by kind: leave it to the scan
    else
      range[2] = i
    end
    last = kind
  end
  kindRanges[list] = ranges
end

-- Every relation of an item, in a stable order (objectives first); an empty
-- list when there is none
function Relations.For(itemID)
  if not Recollect.Utilities.IsPositiveID(itemID) then return {} end
  local list = Cached(itemID)
  if list then return list end
  list = {}
  local codes = Relations.Codes(itemID)
  for code in (codes or ""):gmatch("[^;]+") do
    local relation = Relations.Parse(code, itemID)
    if relation then list[#list + 1] = relation end
  end
  if not InOrder(list) then table.sort(list, Less) end
  IndexKinds(list)
  Keep(itemID, list)
  return list
end

-- The relations For(itemID) has parsed this session, or nil (UI.DetailData
-- parses the rest a slice at a time)
function Relations.Parsed(itemID)
  return Cached(itemID)
end

-- The relations of one kind
function Relations.Of(itemID, kind)
  local list, out = Relations.For(itemID), {}
  local ranges = kindRanges[list]
  if ranges then
    local range = ranges[kind]
    if range then
      for i = range[1], range[2] do out[#out + 1] = list[i] end
    end
    return out
  end
  for _, relation in ipairs(list) do
    if relation.kind == kind then out[#out + 1] = relation end
  end
  return out
end

-- Whether a route serves a character (SRC-01): owner = { faction (0 Horde,
-- 1 Alliance, nil unknown), classID, raceID }. Returns true; "unavailable" for a
-- route no longer in the game; "other" for another faction's or class's
-- route; nil when a condition names what the owner's record can't say.
function Relations.Applies(relation, owner)
  local flags = relation.flags
  if not flags then return true end
  if flags.unavailable then return "unavailable" end
  if flags.faction ~= nil then
    local faction = owner and owner.faction
    if faction == nil then return nil end
    if faction ~= flags.faction then return "other" end
  end
  if flags.classes then
    local classID = owner and owner.classID
    if classID == nil then return nil end
    if not flags.classes[classID] then return "other" end
  end
  if flags.races then
    local raceID = owner and owner.raceID
    if raceID == nil then return nil end
    if not flags.races[raceID] then return "other" end
  end
  return true
end

-- Conditions(relation, owner): display only (D19, D34). The route's
-- conditions the owner does not meet, as tags for a dimmed row or line; never
-- read by a check, so no verdict moves (Applies decides those). A list of
-- { kind, words, after, ids }, in this order:
--   unavailable  "No longer obtainable" (x)
--   unknown      a condition the owner's record can't answer (a stored alt
--                with no race recorded): words as the checks say it (PI-14)
--   faction      "Horde only" / "Alliance only"
--   class, race  ids, the sorted class or race IDs the route is for (the
--                caller names them: UI.UsedFor reads the names)
--   profession   ids = { skillLine } (P), standing ids = { factionID,
--                standing } (E), renown ids = { factionID, level } (N),
--                quest ids = { questID } (Q, one tag per quest), achievement
--                ids = { achievementID, ... } (every A of the route in one
--                tag): conditions a character can still meet (D34), listed
--                for every character, since only a live read tells whether
--                the viewer meets them (the caller reads and words them:
--                UI.UsedFor)
--   event        "During a holiday or event" (h), for every character: the
--                data carries no holiday ID yet
-- words is how the tag reads first in a parenthetical, after how it reads
-- after another tag ("Horde only, during a holiday or event"). Empty when
-- the route has no condition the owner misses.
local CONDITION_WORDS = {
  unavailable = { "No longer obtainable", "no longer obtainable" },
  unknown = { "whether it's for this character isn't recorded yet", "whether it's for this character isn't recorded yet" },
  event = { "During a holiday or event", "during a holiday or event" },
  [0] = { "Horde only", "Horde only" },
  [1] = { "Alliance only", "Alliance only" },
}
local function SortedIDs(set)
  local ids = {}
  for id in pairs(set) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end
local function Tag(kind, words, ids)
  return { kind = kind, words = words and words[1], after = words and words[2], ids = ids }
end
-- The display-only conditions' tags (profession, standing, renown, quest,
-- achievement), added to tags
local function ShownTags(relation, tags)
  local shows = relation and relation.shows
  if not shows then return tags end
  for _, skillLine in ipairs(shows.professions or {}) do tags[#tags + 1] = Tag("profession", nil, { skillLine }) end
  if shows.standing then
    tags[#tags + 1] = Tag("standing", nil, { shows.standing.factionID, shows.standing.standing })
  end
  if shows.renown then tags[#tags + 1] = Tag("renown", nil, { shows.renown.factionID, shows.renown.level }) end
  for _, questID in ipairs(shows.quests or {}) do tags[#tags + 1] = Tag("quest", nil, { questID }) end
  if shows.achievements then
    local ids = {}
    for i, achievementID in ipairs(shows.achievements) do ids[i] = achievementID end
    tags[#tags + 1] = Tag("achievement", nil, ids)
  end
  return tags
end

function Relations.Conditions(relation, owner)
  local flags = relation and relation.flags
  local tags = {}
  if not flags then return ShownTags(relation, tags) end
  owner = owner or {}
  if flags.unavailable then tags[#tags + 1] = Tag("unavailable", CONDITION_WORDS.unavailable) end
  local unknown = (flags.faction ~= nil and owner.faction == nil) or (flags.classes and owner.classID == nil)
    or (flags.races and owner.raceID == nil)
  if unknown then tags[#tags + 1] = Tag("unknown", CONDITION_WORDS.unknown) end
  if flags.faction ~= nil and owner.faction ~= nil and owner.faction ~= flags.faction then
    tags[#tags + 1] = Tag("faction", CONDITION_WORDS[flags.faction] or { "not for this character", "not for this character" })
  end
  if flags.classes and owner.classID ~= nil and not flags.classes[owner.classID] then
    tags[#tags + 1] = Tag("class", nil, SortedIDs(flags.classes))
  end
  if flags.races and owner.raceID ~= nil and not flags.races[owner.raceID] then
    tags[#tags + 1] = Tag("race", nil, SortedIDs(flags.races))
  end
  ShownTags(relation, tags)
  if flags.event then tags[#tags + 1] = Tag("event", CONDITION_WORDS.event) end
  return tags
end

-- ConditionTag(kind): a new tag of kind "unavailable", "unknown" or "event",
-- for a route another code of the same quest decided (QuestAppliesOf)
function Relations.ConditionTag(kind)
  return Tag(kind, CONDITION_WORDS[kind])
end

-- How far each quest an item names serves a character, over every code of
-- the item that names it: a quest removed from the game, or for another
-- faction, class or race, on any of its codes is that for all of them (the
-- dump's own objective and reward codes can lack conditions ATT gives the
-- same quest). { [questID] = true | "unknown" | "other" | "unavailable" }
-- A reward code's "x" can also mean only that reward is no longer given by
-- a quest still in the game (the Dilated Time Pod, w77236|x); no item in the
-- 2026-09-25 data has such a code beside a live use code of the same quest.
local QUEST_KINDS = { objective = true, questItem = true, starts = true, reward = true, choice = true }
local APPLIES_RANK = { [true] = 1, unknown = 2, other = 3, unavailable = 4 }
-- QuestAppliesOf(relations, owner): the same, over a list already parsed
function Relations.QuestAppliesOf(relations, owner)
  local out = {}
  for _, relation in ipairs(relations) do
    if QUEST_KINDS[relation.kind] and relation.id then
      local applies = Relations.Applies(relation, owner)
      if applies == nil then applies = "unknown" end
      local kept = out[relation.id]
      if kept == nil or APPLIES_RANK[applies] > APPLIES_RANK[kept] then out[relation.id] = applies end
    end
  end
  return out
end

function Relations.QuestApplies(itemID, owner)
  return Relations.QuestAppliesOf(Relations.For(itemID), owner)
end

-- A quest's frequency from the data: letters d daily, w weekly, y yearly,
-- r repeatable, q world quest, m monthly; nil when the data names none
-- (unknown, never "one-time")
function Relations.Frequency(questID)
  if not Recollect.Utilities.IsPositiveID(questID) then return nil end
  local data = Data()
  local flags = Record(data and data.Q, questID)
  return flags ~= "" and flags or nil
end

-- A recipe whose schematic the Lab read: { skillLine, product, quantity }, or nil
-- (the shipped data's bucketed C, else a plain R table of strings)
function Relations.Recipe(spellID)
  local data = Data()
  if not data or not Recollect.Utilities.IsPositiveID(spellID) then return nil end
  local text = Record(data.C, spellID) or (data.R and data.R[spellID])
  if type(text) ~= "string" then return nil end
  local skill, product, quantity = text:match("^(%d+),(%d+),(%d+)$")
  if not skill then return nil end
  return { skillLine = tonumber(skill), product = tonumber(product), quantity = tonumber(quantity) }
end

-- Where a quest starts: { npcID, npcIDs, mapID, x, y } with x and y from 0
-- to 1, or nil when the data has no place for it. npcID is the giver the
-- place was taken with (nil when none is known), npcIDs every giver the data
-- knows, npcID first (empty when none): a record lists them "npc/npc" since
-- data format 7 (2026-09-28: a quest with a giver in each faction's camp, or
-- one per capital), "0/npc" when only other givers are known, and a format 6
-- record one alone
function Relations.QuestGiver(questID)
  if not Recollect.Utilities.IsPositiveID(questID) then return nil end
  local data = Data()
  local text = Record(data and data.G, questID)
  if not text then return nil end
  local npcs, map, x, y = text:match("^([%d/]+),(%d+),(%d+),(%d+)$")
  if not npcs or tonumber(map) == 0 then return nil end
  local ids, first = {}, nil
  for npc in npcs:gmatch("%d+") do
    npc = tonumber(npc)
    first = first or npc
    if npc > 0 then ids[#ids + 1] = npc end
  end
  return { npcID = first and first > 0 and first or nil, npcIDs = ids, mapID = tonumber(map), x = tonumber(x) / 1000,
    y = tonumber(y) / 1000 }
end

-- The item behind a thing a purchase names, by its letter ("e" an ensemble
-- set, "l" a weapon illusion, "p" a pet species, "r" a recipe spell) and ID
-- (the data's T table, from AllTheThings), or nil
function Relations.ThingItem(letter, id)
  local data = Data()
  local byLetter = data and data.T and data.T[letter]
  local item = byLetter and byLetter[id]
  return Recollect.Utilities.IsPositiveID(item) and item or nil
end

-- The Encounter Journal encounter a boss is (the data's J table, from
-- AllTheThings), or nil
function Relations.EncounterOf(npcID)
  if not Recollect.Utilities.IsPositiveID(npcID) then return nil end
  local data = Data()
  local text = Record(data and data.J, npcID)
  local encounterID = text and tonumber(text)
  return Recollect.Utilities.IsPositiveID(encounterID) and encounterID or nil
end

-- The Encounter Journal encounters whose loot comes out of a boss loot chest
-- (the L table, data format 7, from AllTheThings' encounter providers:
-- Ula'tek's Ruin, 673428, holds encounter 2895's loot), ascending as
-- shipped, a new list each call; empty when the data names none
function Relations.EncountersOfObject(objectID)
  local list = {}
  if not Recollect.Utilities.IsPositiveID(objectID) then return list end
  local data = Data()
  local text = Record(data and data.L, objectID)
  for id in (text or ""):gmatch("%d+") do list[#list + 1] = tonumber(id) end
  return list
end

-- The first encounter a boss loot chest holds the loot of, or nil
function Relations.EncounterOfObject(objectID)
  return Relations.EncountersOfObject(objectID)[1]
end

-- "p3389" or "193373": a typed thing, as a purchase's (thing letter, ID)
local function Thing(text)
  local letter, id = text:match("^(%a?)(%d+)$")
  if not id then return nil end
  return letter, tonumber(id)
end

-- What a quest rewards (the data's W table, for quests a use code names):
-- a list of { thing, id, choice }, thing the letter a purchase's thing has
-- ("" a plain item, "p" a pet species, ...), so Facts.Buys reads its state;
-- nil when the data names none
function Relations.QuestRewards(questID)
  if not Recollect.Utilities.IsPositiveID(questID) then return nil end
  local data = Data()
  local text = Record(data and data.W, questID)
  if not text or text == "" then return nil end
  local list = {}
  for entry in text:gmatch("[^,]+") do
    local choice = entry:sub(1, 1) == "k"
    local letter, id = Thing(choice and entry:sub(2) or entry)
    if id then list[#list + 1] = { thing = letter, id = id, choice = choice } end
  end
  return #list > 0 and list or nil
end

-- What an item is when a combine makes it and it is a collectible (the
-- data's K table): the letter and ID a purchase's thing would have, or nil
function Relations.ItemThing(itemID)
  local data = Data()
  local text = data and data.K and data.K[itemID]
  if type(text) ~= "string" then return nil end
  return Thing(text)
end

-- The X record of an item: "120100", or "120100,120001" with the patch added
local function Removal(itemID)
  if not Recollect.Utilities.IsPositiveID(itemID) then return nil end
  local data = Data()
  local text = Record(data and data.X, itemID)
  if not text then return nil end
  local removed, added = text:match("^(%d+),?(%d*)$")
  if not removed then return nil end
  return tonumber(removed), tonumber(added)
end

-- The patch in which every route to an item was removed from the game, as
-- AllTheThings numbers patches (120100 is 12.1.0), or nil: nil also for an
-- item removed with no patch known, or with a source the data still has live
function Relations.RemovedIn(itemID)
  local removed = Removal(itemID)
  return Recollect.Utilities.IsPositiveID(removed) and removed or nil
end

-- The patch an item was added in (the same numbers), or nil: known for an
-- item RemovedIn answers for (when AllTheThings gives it), and for an item
-- still in the game that was added in a later expansion than the game files
-- it under (the A table); nil means the game's own expansion stands
function Relations.AddedIn(itemID)
  local removed, added = Removal(itemID)
  if Recollect.Utilities.IsPositiveID(removed) then
    return Recollect.Utilities.IsPositiveID(added) and added or nil
  end
  if not Recollect.Utilities.IsPositiveID(itemID) then return nil end
  local data = Data()
  local text = Record(data and data.A, itemID)
  local patch = text and tonumber(text:match("^(%d+)$"))
  return Recollect.Utilities.IsPositiveID(patch) and patch or nil
end

-- The item that teaches a mount, by the mount's spell (AllTheThings), or nil
function Relations.MountItem(spellID)
  local data = Data()
  local item = data and data.M and data.M[spellID]
  return Recollect.Utilities.IsPositiveID(item) and item or nil
end

-- The recipe spells the data knows for a profession, by its skill line (the
-- S table: the recipes the Lab read and AllTheThings' list), ascending as
-- shipped; an empty list when it names none
function Relations.RecipesOf(skillLine)
  local list = {}
  if not Recollect.Utilities.IsPositiveID(skillLine) then return list end
  local data = Data()
  local text = data and data.S and data.S[skillLine]
  if type(text) ~= "string" then return list end
  for spell in text:gmatch("%d+") do list[#list + 1] = tonumber(spell) end
  return list
end

-- The IDs of one achievement's record in the H or I table ("41,45"), a new
-- list each call, ascending as shipped; empty when there is none
local function AchievementList(tableKey, achievementID)
  local list = {}
  if not Recollect.Utilities.IsPositiveID(achievementID) then return list end
  local data = Data()
  local text = Record(data and data[tableKey], achievementID)
  for id in (text or ""):gmatch("%d+") do list[#list + 1] = tonumber(id) end
  return list
end

-- The meta achievements an achievement counts toward (the H table: each
-- meta whose criteria of type 8 name it), ascending; empty when none
function Relations.MetasOf(achievementID)
  return AchievementList("H", achievementID)
end

-- The achievements a meta achievement asks for (the I table, the reverse of
-- H), ascending; empty when the data names none
function Relations.ChildrenOf(metaID)
  return AchievementList("I", metaID)
end

-- The client build the data came from ("69933"), or nil
function Relations.Build()
  local data = Data()
  return data and data.build
end

Relations._test = {
  Reset = function() newer, older, newerSize, costsOf, metaOf = {}, {}, 0, {}, {} end,
  InOrder = InOrder,
  CacheSize = function() return newerSize end,
  SetCacheLimit = function(n) CACHE_RELATIONS = n end,
  CacheLimit = function() return CACHE_RELATIONS end,
  -- The kind ranges Of reads for a list For sorted, or nil when it scans
  Ranges = function(list) return kindRanges[list] end,
  IndexKinds = IndexKinds,
  ORDER = ORDER,   -- read only
}
