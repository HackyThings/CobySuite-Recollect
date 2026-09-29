-------------------------------------------------------------------------------
-- Curator.Decode: what a finding's fact and a stamp's source say, in one
-- place (the curator dashboard, the collection history). Pure: no client
-- reads; the caller hands a namer for the names it shows.
--
-- The facts are the store's (Compare.lua, CompareItems.lua, CompareQuest.lua
-- and the Black Market, Trading Post and encounter loot recorders list them):
--   v:<npc>:i:<item>:sold   v:<npc>:i:<item>:price   m:<input>:x<n>   p:<npc>
--   c:<npc>:i:<item>   ob:<object>:i:<item>   f:<map>:i:<item>
--   x:<container>:i:<item>   de:<item>:i:<out>   pp:<npc>:i:<item>
--   R:<recipe>   R:<skillLine>:<recipe>   g:<recipe>:i:<reagent>   r:<item>
--   n:<item>:npc:<id>   n:<item>:obj:<id>   $:<item>:c:<currency>
--   q:<quest>:w:<item>   q:<quest>:k:<item>   q:<quest>:i:<item>
--   q:<quest>:o:<item>   s:<item>   G:<quest>   T:<quest>   Q:<quest>
--   bm:i:<item>   tp:i:<item>   e:<encounter>:i:<item>
--   ni:<item>   (an item with no information; its value the place it was
--               seen: bag, bank, wb, or c:<npc>, v:<npc>, q:<quest> ...)
-- The stamps' sources: v:<npc> m:<input> p:<npc> c: ob: f: x: de: pp:
-- R:<skillLine> r:<item> n:<item> $:<item> q:<quest> o:<quest> s:<item>
-- G:<quest> Q:<quest> bm tp e:<encounter>. A record's R: with two numbers is
-- a recipe a window didn't list; a stamp's R: is a profession's recipes,
-- and a stamp's o: (a quest's turn-in items) is not the loot prefix ob:.
--
-- Fact(fact) and Stamp(source): { type, group, label, subject = { kind, id },
-- source = { kind, id } or nil, other = { kind, id } or nil }, or a type
-- "unknown" one naming the raw text. Kinds of IDs: item, npc, quest, map,
-- spell (a recipe), currency, object, encounter (a dungeon encounter),
-- skill (a profession skill line).
-- Value(decoded, value, name) and Shipped(decoded, shipped, name): the
-- observed and shipped values in words; name(kind, id) returns a name or
-- nil, and Name(name, kind, id) puts "Item 1234" in place of a name the game
-- hasn't given.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator

local Decode = {}
Curator.Decode = Decode

-- The groups the filter menu offers, in its order
Decode.GROUPS = {
  { key = "vendor", label = "Vendors" },
  { key = "loot", label = "Loot and drops" },
  { key = "quest", label = "Quests" },
  { key = "crafting", label = "Crafting and combining" },
  { key = "place", label = "NPC positions" },
  { key = "use", label = "Using items" },
  { key = "market", label = "Black Market and Trading Post" },
  { key = "noinfo", label = "Items with no information" },
  { key = "other", label = "Other" },
}

-- Each type: its group and what it is, in a few words
Decode.TYPES = {
  ["vendor-sold"] = { group = "vendor", label = "Sold by a vendor" },
  ["vendor-price"] = { group = "vendor", label = "Vendor price" },
  ["drop"] = { group = "loot", label = "Drop" },
  ["object"] = { group = "loot", label = "Found in an object" },
  ["fishing"] = { group = "loot", label = "Fished up" },
  ["container"] = { group = "loot", label = "Found in a container" },
  ["disenchant"] = { group = "loot", label = "Disenchanted into" },
  ["pickpocket"] = { group = "loot", label = "Pickpocketed" },
  ["encounter"] = { group = "loot", label = "Boss loot" },
  ["quest-reward"] = { group = "quest", label = "Quest reward" },
  ["quest-choice"] = { group = "quest", label = "Quest reward choice" },
  ["quest-kind"] = { group = "quest", label = "Reward or choice" },
  ["quest-needs"] = { group = "quest", label = "Quest turn-in item" },
  ["starts"] = { group = "quest", label = "Starts a quest" },
  ["giver"] = { group = "quest", label = "Quest giver" },
  ["turnin"] = { group = "quest", label = "Quest turn-in NPC" },
  ["frequency"] = { group = "quest", label = "Daily or weekly" },
  ["recipe"] = { group = "crafting", label = "Recipe" },
  ["recipe-listed"] = { group = "crafting", label = "Recipe in a profession" },
  ["reagent"] = { group = "crafting", label = "Recipe reagent" },
  ["teaches"] = { group = "crafting", label = "Teaches a recipe" },
  ["combine"] = { group = "crafting", label = "Combine" },
  ["position"] = { group = "place", label = "NPC position" },
  ["used-on"] = { group = "use", label = "Quest item used on" },
  ["grant"] = { group = "use", label = "Using it gives" },
  ["black-market"] = { group = "market", label = "Black Market" },
  ["trading-post"] = { group = "market", label = "Trading Post" },
  ["no-info"] = { group = "noinfo", label = "Item" },   -- its Kind says No info
  ["unknown"] = { group = "other", label = "Something else" },
}

-- The stamps' types: what a confirmation vouches for
local STAMP_TYPES = {
  ["vendor"] = { group = "vendor", label = "Vendor's goods" },
  ["combine"] = { group = "crafting", label = "Combines" },
  ["position"] = { group = "place", label = "NPC position" },
  ["drop"] = { group = "loot", label = "Creature's loot" },
  ["object"] = { group = "loot", label = "Object's loot" },
  ["fishing"] = { group = "loot", label = "Fishing catch" },
  ["container"] = { group = "loot", label = "Container's contents" },
  ["disenchant"] = { group = "loot", label = "Disenchanting" },
  ["pickpocket"] = { group = "loot", label = "Pickpocketing" },
  ["encounter"] = { group = "loot", label = "Boss loot" },
  ["recipes"] = { group = "crafting", label = "Recipes" },
  ["teaches"] = { group = "crafting", label = "Recipe it teaches" },
  ["used-on"] = { group = "use", label = "Quest item used on" },
  ["grant"] = { group = "use", label = "Using it gives" },
  ["quest-reward"] = { group = "quest", label = "Quest rewards" },
  ["quest-needs"] = { group = "quest", label = "Quest turn-in items" },
  ["starts"] = { group = "quest", label = "Starts a quest" },
  ["giver"] = { group = "quest", label = "Quest giver" },
  ["frequency"] = { group = "quest", label = "Daily or weekly" },
  ["black-market"] = { group = "market", label = "Black Market" },
  ["trading-post"] = { group = "market", label = "Trading Post" },
  ["unknown"] = { group = "other", label = "Something else" },
}
Decode.STAMP_TYPES = STAMP_TYPES

local function Id(kind, text)
  local id = tonumber(text)
  if not id then return nil end
  return { kind = kind, id = id }
end

local function Made(typeKey, subject, source, other, types)
  local def = (types or Decode.TYPES)[typeKey]
  return { type = typeKey, group = def.group, label = def.label, subject = subject, source = source, other = other }
end

local function Unknown(text, types)
  local out = Made("unknown", nil, nil, nil, types)
  out.raw = tostring(text)
  return out
end

-- Loot-like facts "<prefix>:<source>:i:<item>": the type and the source's kind
local LOOT = {
  c = { "drop", "npc" }, ob = { "object", "object" }, f = { "fishing", "map" }, x = { "container", "item" },
  de = { "disenchant", "item" }, pp = { "pickpocket", "npc" }, e = { "encounter", "encounter" },
}

-- Each pattern and how it reads, tried in order (the longer forms first)
local FACTS = {
  { "^v:(%d+):i:(%d+):sold$", function(npc, item) return Made("vendor-sold", Id("item", item), Id("npc", npc)) end },
  { "^v:(%d+):i:(%d+):price$", function(npc, item) return Made("vendor-price", Id("item", item), Id("npc", npc)) end },
  { "^m:(%d+):x(%d+)$", function(item, n)
    local out = Made("combine", Id("item", item))
    out.count = tonumber(n)
    return out
  end },
  { "^p:(%d+)$", function(npc) return Made("position", Id("npc", npc)) end },
  { "^n:(%d+):npc:(%d+)$", function(item, npc) return Made("used-on", Id("item", item), nil, Id("npc", npc)) end },
  { "^n:(%d+):obj:(%d+)$", function(item, obj) return Made("used-on", Id("item", item), nil, Id("object", obj)) end },
  { "^%$:(%d+):c:(%d+)$", function(item, currency) return Made("grant", Id("item", item), nil, Id("currency", currency)) end },
  { "^R:(%d+):(%d+)$", function(skill, recipe) return Made("recipe-listed", Id("spell", recipe), Id("skill", skill)) end },
  { "^R:(%d+)$", function(recipe) return Made("recipe", Id("spell", recipe)) end },
  { "^g:(%d+):i:(%d+)$", function(recipe, item) return Made("reagent", Id("item", item), Id("spell", recipe)) end },
  { "^r:(%d+)$", function(item) return Made("teaches", Id("item", item)) end },
  { "^q:(%d+):w:(%d+)$", function(quest, item) return Made("quest-reward", Id("item", item), Id("quest", quest)) end },
  { "^q:(%d+):k:(%d+)$", function(quest, item) return Made("quest-choice", Id("item", item), Id("quest", quest)) end },
  { "^q:(%d+):i:(%d+)$", function(quest, item) return Made("quest-kind", Id("item", item), Id("quest", quest)) end },
  { "^q:(%d+):o:(%d+)$", function(quest, item) return Made("quest-needs", Id("item", item), Id("quest", quest)) end },
  { "^s:(%d+)$", function(item) return Made("starts", Id("item", item)) end },
  { "^G:(%d+)$", function(quest) return Made("giver", Id("quest", quest)) end },
  { "^T:(%d+)$", function(quest) return Made("turnin", Id("quest", quest)) end },
  { "^Q:(%d+)$", function(quest) return Made("frequency", Id("quest", quest)) end },
  { "^bm:i:(%d+)$", function(item) return Made("black-market", Id("item", item)) end },
  { "^tp:i:(%d+)$", function(item) return Made("trading-post", Id("item", item)) end },
  { "^ni:(%d+)$", function(item) return Made("no-info", Id("item", item)) end },
  { "^(%a+):(%d+):i:(%d+)$", function(prefix, source, item)
    local def = LOOT[prefix]
    if not def then return nil end
    return Made(def[1], Id("item", item), Id(def[2], source))
  end },
}

-- Fact(fact): what a finding is about (see the header)
function Decode.Fact(fact)
  if type(fact) ~= "string" then return Unknown(fact) end
  for _, entry in ipairs(FACTS) do
    local a, b, c = fact:match(entry[1])
    if a then
      local out = entry[2](a, b, c)
      if out then return out end
    end
  end
  return Unknown(fact)
end

local STAMP_PREFIX = {
  v = { "vendor", "npc" }, m = { "combine", "item" }, p = { "position", "npc" }, c = { "drop", "npc" },
  ob = { "object", "object" }, f = { "fishing", "map" }, x = { "container", "item" }, de = { "disenchant", "item" },
  pp = { "pickpocket", "npc" }, e = { "encounter", "encounter" }, R = { "recipes", "skill" }, r = { "teaches", "item" },
  n = { "used-on", "item" }, ["$"] = { "grant", "item" }, q = { "quest-reward", "quest" }, o = { "quest-needs", "quest" },
  s = { "starts", "item" }, G = { "giver", "quest" }, Q = { "frequency", "quest" },
}

-- Stamp(source): what a confirmation stamp vouches for (its source, without
-- the "@<build>" of its key)
function Decode.Stamp(source)
  if type(source) ~= "string" then return Unknown(source, STAMP_TYPES) end
  source = source:match("^([^@]*)") or source
  if source == "bm" then return Made("black-market", nil, nil, nil, STAMP_TYPES) end
  if source == "tp" then return Made("trading-post", nil, nil, nil, STAMP_TYPES) end
  local prefix, id = source:match("^([%a%$]+):(%d+)$")
  local def = prefix and STAMP_PREFIX[prefix]
  if not def then return Unknown(source, STAMP_TYPES) end
  return Made(def[1], Id(def[2], id), nil, nil, STAMP_TYPES)
end

-------------------------------------------------------------------------------
-- Words
-------------------------------------------------------------------------------
local NOUNS = { item = "Item", npc = "NPC", quest = "Quest", map = "Zone", spell = "Recipe", currency = "Currency",
  object = "Object", encounter = "Boss encounter", skill = "Profession" }

-- Name(name, kind, id): the name the game gives, else "<Noun> <id>"
function Decode.Name(name, kind, id)
  local ok, text = false, nil
  if type(name) == "function" then ok, text = pcall(name, kind, id) end
  if ok and type(text) == "string" and text ~= "" then return text end
  return ("%s %s"):format(NOUNS[kind] or "ID", tostring(id))
end

local function Named(name, ref)
  if not ref then return "?" end
  return Decode.Name(name, ref.kind, ref.id)
end

-- "i32572x4+c1813x25+g250000" or "g<copper>x<stack>" in words
function Decode.Cost(text, name)
  text = tostring(text or "")
  local copper, stack = text:match("^g(%d+)x(%d+)$")
  if copper then
    local money = CobySuite_Recollect.Utilities.FormatMoneyText(tonumber(copper))
    return tonumber(stack) and tonumber(stack) > 1 and ("%s for %s"):format(money, stack) or money
  end
  local parts = {}
  for part in text:gmatch("[^+]+") do
    local letter, id, count = part:match("^([ic])(%d+)x(%d+)$")
    if letter then
      parts[#parts + 1] = ("%s %s"):format(count, Decode.Name(name, letter == "i" and "item" or "currency", tonumber(id)))
    else
      local gold = part:match("^g(%d+)$")
      parts[#parts + 1] = gold and CobySuite_Recollect.Utilities.FormatMoneyText(tonumber(gold)) or part
    end
  end
  return #parts > 0 and table.concat(parts, " + ") or "?"
end

-- "<map>:<x>,<y>" in words: "Zone (50.0, 42.1)"
function Decode.Position(text, name)
  local map, x, y = tostring(text or ""):match("^(%d+):([%d%.]+),([%d%.]+)$")
  if not map then return tostring(text or "?") end
  return ("%s (%.1f, %.1f)"):format(Decode.Name(name, "map", tonumber(map)), tonumber(x) * 100, tonumber(y) * 100)
end

-- "<item>x<n>" in words: "Makes 5 Name"
local function Makes(text, name)
  local item, n = tostring(text or ""):match("^(%d+)x(%d+)")
  if not item then return tostring(text or "?") end
  -- a schematic whose product the game gives as item 0 (a placeholder)
  if item == "0" then return "Makes no named item" end
  return ("Makes %s %s"):format(n, Decode.Name(name, "item", tonumber(item)))
end

local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
  "November", "December" }

local FREQUENCY = { d = "Daily", w = "Weekly", y = "Yearly", m = "Monthly", q = "World quest", r = "Repeatable" }

-- How each type's observed value reads
local VALUES = {
  ["vendor-sold"] = function(value)
    if tostring(value):find("^filter") then
      return tostring(value):find("costs loading", 1, true) and "Not listed (prices still loading)" or "Not listed"
    end
    return "Listed"
  end,
  ["vendor-price"] = function(value, _, name) return Decode.Cost(value, name) end,
  ["combine"] = function(value, _, name) return Makes(value, name) end,
  ["position"] = function(value, _, name) return Decode.Position(value, name) end,
  ["recipe"] = function(value, _, name) return Makes(value, name) end,
  ["recipe-listed"] = function() return "Not in the profession window" end,
  ["reagent"] = function(value) return ("Takes %s"):format(tostring(value)) end,
  ["teaches"] = function(value, _, name) return "Teaches " .. Decode.Name(name, "spell", tonumber(value)) end,
  ["used-on"] = function(_, decoded, name) return "Used on " .. Named(name, decoded.other) end,
  ["grant"] = function(value, decoded, name) return ("Gave %s %s"):format(tostring(value), Named(name, decoded.other)) end,
  ["quest-reward"] = function(value) return ("Rewards %s"):format(tostring(value)) end,
  ["quest-choice"] = function(value) return ("A choice of %s"):format(tostring(value)) end,
  ["quest-kind"] = function(value) return value == "k" and "A reward you choose" or "A reward" end,
  ["quest-needs"] = function(value) return ("Asks for %s"):format(tostring(value)) end,
  ["starts"] = function(value, _, name) return "Starts " .. Decode.Name(name, "quest", tonumber(value)) end,
  ["giver"] = function(value, _, name) return "Given by " .. Decode.Name(name, "npc", tonumber(value)) end,
  ["turnin"] = function(value, _, name) return "Turned in to " .. Decode.Name(name, "npc", tonumber(value)) end,
  ["frequency"] = function(value) return FREQUENCY[value] or tostring(value) end,
  ["black-market"] = function() return "Offered" end,
  ["trading-post"] = function(value)
    local year, month = tostring(value):match("^(%d%d%d%d)(%d%d)$")
    local m = MONTHS[tonumber(month or 0)]
    return m and ("Offered, %s %s"):format(m, year) or "Offered"
  end,
}
-- Where an item with no information was seen, in words: its value is a
-- place ("bag", "bank", "wb") or a source ("c:<npc>", "v:<npc>" ...)
local HELD_WORDS = { bag = "In your bags", bank = "In your bank", wb = "In your warband bank", bm = "On the Black Market",
  tp = "At the Trading Post" }
local PLACE_WORDS = {
  c = { "Dropped by %s", "npc" }, ob = { "Found in %s", "object" }, f = { "Fished in %s", "map" },
  x = { "Inside %s", "item" }, de = { "Disenchanted from %s", "item" }, pp = { "Pickpocketed from %s", "npc" },
  v = { "Sold by %s", "npc" }, q = { "From the quest %s", "quest" },
}

function Decode.Place(value, name)
  value = tostring(value or "")
  if HELD_WORDS[value] then return HELD_WORDS[value] end
  local prefix, id = value:match("^(%a+):(%d+)$")
  if prefix == "e" then return ("From a boss (encounter %s)"):format(id) end
  local words = prefix and PLACE_WORDS[prefix]
  if not words then return value end
  return words[1]:format(Decode.Name(name, words[2], tonumber(id)))
end
VALUES["no-info"] = function(value, _, name) return Decode.Place(value, name) end

local LOOT_WORDS = { drop = "Dropped", object = "Found", fishing = "Fished up", container = "Found inside",
  disenchant = "Disenchanted into", pickpocket = "Pickpocketed", encounter = "Dropped" }

-- Value(decoded, value, name): what the curator saw, in words
function Decode.Value(decoded, value, name)
  local fn = VALUES[decoded.type]
  if fn then
    local ok, text = pcall(fn, value, decoded, name)
    if ok and type(text) == "string" then return text end
  end
  if LOOT_WORDS[decoded.type] then return LOOT_WORDS[decoded.type] end
  return tostring(value or "")
end

-- How each type's shipped value reads, where it differs from Value's
local SHIPPED = {
  ["vendor-price"] = function(shipped, _, name)
    local out = {}
    for one in tostring(shipped):gmatch("[^|]+") do out[#out + 1] = Decode.Cost(one, name) end
    return table.concat(out, " or ")
  end,
  ["combine"] = function(shipped, _, name) return "Makes " .. Decode.Name(name, "item", tonumber(shipped)) end,
  ["teaches"] = function(shipped, _, name) return "Teaches " .. Decode.Name(name, "spell", tonumber(shipped)) end,
  ["quest-kind"] = function(shipped) return shipped == "k" and "A reward you choose" or "A reward" end,
  ["frequency"] = function(shipped)
    local out = {}
    for letter in tostring(shipped):gmatch("%a") do out[#out + 1] = FREQUENCY[letter] or letter end
    return #out > 0 and table.concat(out, ", ") or tostring(shipped)
  end,
  ["black-market"] = function() return "Listed as no longer offered" end,
  ["trading-post"] = function(shipped) return "Listed for another month (" .. tostring(shipped) .. ")" end,
  ["encounter"] = function() return "Another boss" end,
}

-- Shipped(decoded, shipped, name): what the shipped data says, or "" when it
-- says nothing (an item with no information: that it has nothing)
function Decode.Shipped(decoded, shipped, name)
  if decoded.type == "no-info" then return "Nothing" end
  if shipped == nil or shipped == "" then return "" end
  local fn = SHIPPED[decoded.type]
  if fn then
    local ok, text = pcall(fn, shipped, decoded, name)
    if ok and type(text) == "string" then return text end
  end
  return Decode.Value(decoded, shipped, name)
end
