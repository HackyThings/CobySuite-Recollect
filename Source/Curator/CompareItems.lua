-------------------------------------------------------------------------------
-- Curator.Compare, continued: loot, recipes, what an item teaches, what a
-- quest item is used on, and what an item's use gives (curator plan, phase
-- 4c), against the shipped data through Host only
--
-- Facts (the store's fact names; values are text):
--   c:<npc>:i:<item>          dropped by a creature (shipped: dropsFrom, or
--                             the loot of the encounter its boss is; an
--                             item shipped as a world drop, or as a drop of
--                             the zone it was looted in, is no finding)
--   ob:<object>:i:<item>      found in an object or node (shipped: foundIn,
--                             also under the container a spawn is filed
--                             under, or the loot of the encounter whose
--                             loot chest it is)
--   f:<map>:i:<item>          fished in a zone (shipped: fishedIn, the F code
--                             of data format 10; a z code no longer counts)
--   x:<container>:i:<item>    found in a container item (shipped: openedFrom,
--                             the Y code of data format 10)
--   de:<item>:i:<out>         disenchanting the item gave out (shipped: a
--                             live G code of a disenchant spell on out, data
--                             format 11)
-- A creature looted right after a Skinning cast is a skinning:
--   sk:<npc>:i:<item>         skinned from a creature (shipped as skinnedFrom,
--                             the S code, or a live G code of a skinning
--                             spell; never a confirmation of a drop code, and
--                             no stamp). Before Task #423 it was filed as
--                             c:<npc>:i:<item> with the cast kept beside it.
--   pp:<npc>:i:<item>         pickpocketed from a creature (stated by a G921 code since data format 22)
-- An item the data ships as a seasonal drop (a live P code) is no finding from
-- any source: the season's activities give it, not one creature or chest.
--   R:<recipe>                a recipe's product and count, "<item>x<n>"
--                             (plus "|<reagents>" when the recipe isn't
--                             shipped at all; shipped: the C table)
--   R:<skillLine>:<recipe>    a shipped recipe of a profession its window
--                             didn't list (not seen)
--   g:<recipe>:i:<reagent>    how many of a reagent a recipe takes (each item a
--                             required slot accepts, a recipe not shipped too;
--                             not seen, "schematic", for a shipped reagent no
--                             required slot lists)
--   sv:<skillLine>:<recipe>:i:<item>   a salvage recipe's input and the quantity
--                             it takes (shipped: a g code; not seen "window")
--   qy:<recipe>:i:<item>      one quality's item of what a recipe crafts, its
--                             tier (shipped: a y code)
--   r:<item>                  the recipe an item taught (shipped: teaches)
--   n:<item>:npc:<id> / :obj:<id>   what a quest item was used on (usedAt)
--   $:<item>:c:<currency>     how much of a currency using the item gave
--   tf:<item>                 one use of the item that consumed and gave items:
--                             "<consumed>|<gained>", each "<item>x<n>" comma
--                             separated (never judged here; no stamp)
-- Every looted item is also handed to the items-with-no-information recorder
-- as seen at its source ("c:<npc>", "ob:<object>" ...: Compare.SawItem, the
-- fact ni:<item>).
-- Loot is never complete (chance), so it has no "not seen"; each loot
-- window stamps a confirmation per source (the matched item IDs as the
-- positions, total 0), which also counts how often a source was looted.
-- A random amount is never a conflict: grants are additions or confirmed.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Compare = Curator.Compare

-- Shipped(itemID, kind, ctx, letter): the shipped relations of a kind for an
-- item as the observation's character sees them (ctx: the context index it
-- was seen under, Context.OwnerOf): { [id] = count or true } for the routes
-- that serve it, the only ones a sighting confirms; and, second, { [id] =
-- code } for those that don't, a route no longer available ("|x") or for
-- another faction, class or race: a sighting of one is an addition naming it
-- ("w900|x"; letter is the code's letter), never a confirmation (Task #421).
-- An ID with a route that serves is only in the first; a route whose
-- conditions can't be told for the character is in neither.
local function Shipped(itemID, kind, ctx, letter)
  local serving, other = {}, {}
  for _, relation in ipairs(Host.Sources(itemID, kind, Curator.Context.OwnerOf(ctx))) do
    if relation.id then
      if relation.serves == true then
        serving[relation.id] = relation.count or true
      elseif relation.serves == false then
        other[relation.id] = (letter or "") .. relation.id .. (relation.flags and "|" .. relation.flags or "")
      end
    end
  end
  for id in pairs(serving) do other[id] = nil end
  return serving, other
end
Compare.Shipped = Shipped

local function Record(kind, fact, value, shipped, ctx, extra)
  return Curator.Store.Record(kind, fact, value, shipped, ctx, extra)
end

-------------------------------------------------------------------------------
-- Loot
-------------------------------------------------------------------------------
-- letter: the code that ships the source (c<npc>, i<object>, F<map>,
-- Y<container>, S<npc>), read through Host.CodesOf
local LOOT = {
  drop = { prefix = "c", letter = "c" },
  object = { prefix = "ob", letter = "i" },
  fishing = { prefix = "f", letter = "F" },
  container = { prefix = "x", letter = "Y" },
  disenchant = { prefix = "de", gathered = "DISENCHANT_SPELLS" },
  -- a live Pick Pocket G (data format 22) on this creature, on a zone the
  -- window lies in or with neither (anywhere) states it (Task #449)
  pickpocket = { prefix = "pp", pickpocket = true },
  -- a creature's corpse looted right after a Skinning cast (Compare.Skinned):
  -- its own fact since Task #423 (sk:), where older clients filed it under c:
  -- with the cast kept beside it; its items are seen at the creature (place c:)
  skinning = { prefix = "sk", letter = "S", gathered = "SKINNING_SPELLS", place = "c" },
}

-- The gathering spells whose G codes (data format 11) state a loot: Disenchant
-- (13262, and 1280952, under which the data files Midnight's enchanting
-- materials) and Skinning (8613, the cast a skinned corpse follows, and
-- Midnight Skinning's 471014); keep them alike with the data build's
-- DISENCHANT_SPELLS and SKINNING_SPELLS
Compare.DISENCHANT_SPELLS = { [13262] = true, [1280952] = true }
Compare.SKINNING_SPELLS = { [8613] = true, [471014] = true }

-- Whether a loot source is a skinned corpse: a creature looted right after a
-- Skinning cast (the loot recorder keeps the cast, extra.cast)
function Compare.Skinned(source)
  local cast = source.kind == "drop" and type(source.extra) == "table" and source.extra.cast
  return cast and Compare.SKINNING_SPELLS[cast] == true or false
end

-- Pick Pocket, the spell a pickpocket's G code names (Loot.PICK_POCKET, the
-- pipeline's PICK_POCKET)
Compare.PICK_POCKET = 921

-- Whether the data ships an item as coming from one of the spells given
-- ({ [spellID] = true }) on a route still in the game (a live plain G code:
-- never one on a creature or a zone, or one made by the spell, data format 22)
function Compare.Gathered(itemID, spells)
  for _, code in ipairs(Host.CodesOf(itemID, "G")) do
    if not code.gone and not (code.npc or code.mapID or code.made) and spells[code.id] then return true end
  end
  return false
end

-- The three checks below count only a route that may serve the looting
-- character (owner, Context.OwnerOf; Task #423): a world, zone or seasonal
-- drop for another faction, class or race, or another difficulty, is no
-- reason to stay silent, so its copy is a finding; a route whose conditions
-- can't be told still keeps quiet. With no owner every live code counts.
local function MayServe(code, owner)
  return owner == nil or code.serves ~= false
end

-- Whether the data ships an item as a seasonal drop still in the game (a live
-- P, data format 11): many of the season's activities give it, so one
-- creature's, chest's or boss's copy says nothing new (Spark of Tides)
function Compare.SeasonDrop(itemID, owner)
  for _, code in ipairs(Host.CodesOf(itemID, "P", owner)) do
    if not code.gone and MayServe(code, owner) then return true end
  end
  return false
end

-- Whether the data ships an item as a world drop still in the game (a live
-- z0: any enemy anywhere can drop it). One creature's copy of a world drop
-- says nothing about where to farm it, so it is no finding (2026-09-27: a
-- world-drop ore recorded from two creatures)
function Compare.WorldDrop(itemID, owner)
  for _, code in ipairs(Host.CodesOf(itemID, "z", owner)) do
    if code.id == 0 and not code.gone and MayServe(code, owner) then return true end
  end
  return false
end

-- Whether the data ships an item as a drop of any enemy in one of the zones
-- given (a live z<map>: zones = { [mapID] = true }, the loot window's map
-- and the zone it lies in). One creature's copy of a zone drop, looted in
-- that zone, says no more than the zone code does; in another zone it is a
-- real difference, so only these maps count
function Compare.ZoneDrop(itemID, zones, owner)
  if not zones then return false end
  for _, code in ipairs(Host.CodesOf(itemID, "z", owner)) do
    if code.id ~= 0 and not code.gone and zones[code.id] and MayServe(code, owner) then return true end
  end
  return false
end

-- The live codes that name a sighting's source, tallied by whether their
-- route serves the observation's character (owner: Context.OwnerOf; with
-- none, every live code counts as serving, as before Task #421): served, a
-- code that can't be told (unknown), and the codes a restriction leaves the
-- character out of (outside, as shipped: "c300|f1")
local function Tally()
  return { served = false, unknown = false, outside = {} }
end

local function Count(tally, code, owner)
  local serves = true
  if owner ~= nil then serves = code.serves end
  if serves == true then
    tally.served = true
  elseif serves == false then
    tally.outside[#tally.outside + 1] = code.code
  else
    tally.unknown = true
  end
end

-- true when a route serves the sighting; nil when none does and one can't be
-- told (nothing is recorded then, neither confirmation nor finding); false
-- otherwise, with the codes it falls outside of as text, or nil for none
local function Verdict(tally)
  if tally.served then return true end
  if tally.unknown then return nil end
  if #tally.outside > 0 then return false, table.concat(tally.outside, ",") end
  return false
end

local function AddBossLoot(tally, itemID, encounters, owner)
  if not next(encounters) then return end
  for _, code in ipairs(Host.CodesOf(itemID, "D", owner)) do
    if not code.gone and encounters[code.id] then Count(tally, code, owner) end
  end
  for _, code in ipairs(Host.CodesOf(itemID, "c", owner)) do
    local journal = not code.gone and Host.EncounterOf(code.id)
    if journal and encounters[journal] then Count(tally, code, owner) end
  end
end

-- Whether a live code of the item names it the loot of one of the journal
-- encounters given (encounters = { [journalID] = true }): a D<encounter>,
-- or a c<npc> of a boss the data maps (J, Host.EncounterOf) to one. With
-- owner (the observation's character, Context.OwnerOf) only a route that
-- serves it counts: true, nil when that can't be told, false otherwise (with
-- the codes a restriction leaves it out of, as Verdict gives them)
function Compare.BossLoot(itemID, encounters, owner)
  local tally = Tally()
  AddBossLoot(tally, itemID, encounters, owner)
  return Verdict(tally)
end

-- What a source's shipped codes may name it as, besides its own ID: for an
-- object, the treasure containers its spawn is filed under (Host.ObjectAlias)
-- and the journal encounters whose loot chest it or one of them is
-- (Host.EncounterOfObject); for a creature, the encounter of the boss it is
-- (Host.EncounterOf, J). Returns aliases (a list) and encounters ({ [id] = true })
local function Stands(source)
  local aliases, encounters = {}, {}
  if source.kind == "object" then
    aliases = Host.ObjectAlias(source.id)
    for _, object in ipairs({ source.id, unpack(aliases) }) do
      for _, journal in ipairs(Host.EncounterOfObject(object)) do encounters[journal] = true end
    end
  elseif source.kind == "drop" then
    local journal = Host.EncounterOf(source.id)
    if journal then encounters[journal] = true end
  end
  return aliases, encounters
end

-- Whether an item's shipped codes already say it comes from the source:
-- its own code (i<object>, c<npc> ...), an object's code under a container
-- its spawn is filed under (2026-09-28: a relic looted from 652482 ships as
-- found in 653064), or the loot of an encounter the source stands for: a
-- boss's loot chest holds its boss's loot (20 findings in three chests,
-- 2026-09-28), and a boss with several creature IDs drops what its first one
-- is coded with (the pipeline's shipped_now reads all three the same way).
-- Only a live code counts: a source the data ships only as no longer
-- available (|x) is back when it is looted, an addition (review CUR-01, Task #316).
-- Only a route that serves the character who looted it counts (owner,
-- Context.OwnerOf: its faction, class, race and the instance difficulty):
-- a sighting outside a route's restriction is an addition naming that route,
-- never its confirmation, and one whose restriction can't be told is neither
-- (Task #421). Returns Verdict's answers.
-- A pickpocket's loot: a live G921 on that creature, on a zone's enemies of a
-- map the window lies in (zones), or anywhere (/recollect-data's gathered
-- with npc reads it the same way, a zone by the sighting's map)
local function Pickpocketed(itemID, source, zones, owner)
  local tally = Tally()
  for _, code in ipairs(Host.CodesOf(itemID, "G", owner)) do
    if not code.gone and code.id == Compare.PICK_POCKET and not code.made
      and (code.npc == source.id or (code.mapID and zones and zones[code.mapID]) or not (code.npc or code.mapID)) then
      Count(tally, code, owner)
    end
  end
  return Verdict(tally)
end

-- Whether a container's item is what a held copy of a removed container gave:
-- the item ships the route only gone (Y<container>|x) while the container
-- still says it holds the item (a live H<item>). The data build writes that
-- pair only for a container its X table keeps (Task #447: a removed container's
-- Y is flagged gone and its own H stays live; a route AllTheThings marks gone
-- flags both), and a copy still in the bags opens and gives it, so the sighting
-- says nothing about the route now (Task #467: Scale of the Earth-Warder from a
-- Timerunner's Parting Pack opened after Legion Remix ended)
local function HeldCopy(itemID, container)
  local stated = false
  for _, code in ipairs(Host.CodesOf(itemID, "Y")) do
    if code.id == container then
      if not code.gone then return false end
      stated = true
    end
  end
  if not stated then return false end
  for _, code in ipairs(Host.CodesOf(container, "H")) do
    if code.id == itemID and not code.gone then return true end
  end
  return false
end

local function Known(itemID, def, source, aliases, encounters, owner, zones)
  if def.gathered and Compare.Gathered(itemID, Compare[def.gathered]) then return true end
  if def.pickpocket then return Pickpocketed(itemID, source, zones, owner) end
  if not def.letter then return false end
  local own = { [source.id] = true }
  for _, alias in ipairs(aliases) do own[alias] = true end
  local tally = Tally()
  for _, code in ipairs(Host.CodesOf(itemID, def.letter, owner)) do
    if not code.gone and own[code.id] then Count(tally, code, owner) end
  end
  AddBossLoot(tally, itemID, encounters, owner)
  return Verdict(tally)
end

-- Loot(window, ctx): window = { sources = { [key] = { kind, id, items =
-- { [itemID] = true }, extra } }, zones }, one source per corpse, object,
-- container or fishing catch. zones (optional): the maps a zone drop counts
-- in (Loot.ZoneMaps). An item the data already has there (Known) goes in
-- the source's stamp; a creature's world drop, or its zone drop in that
-- zone, records nothing, and neither does a seasonal drop from any source. A
-- skinned corpse compares against what is skinned from it and stamps
-- nothing: its loot says nothing about the creature's drops. An item whose
-- only codes for the source are routes the looting character falls outside
-- of (another faction, class or race, or another instance difficulty) is an
-- addition whose shipped names them; one whose route can't be told for it
-- records nothing (Task #421).
function Compare.Loot(window, ctx)
  local owner = Curator.Context.OwnerOf(ctx)
  for _, source in pairs(window.sources) do
    local skinned = Compare.Skinned(source)
    local def = skinned and LOOT.skinning or LOOT[source.kind]
    local aliases, encounters = Stands(source)
    local matched = {}
    for itemID in pairs(source.items) do
      Compare.SawItem(itemID, (def.place or def.prefix) .. ":" .. source.id, ctx)
      local known, outside = Known(itemID, def, source, aliases, encounters, owner, window.zones)
      if known then
        matched[#matched + 1] = itemID
      elseif known == nil then
        -- a route whose restriction can't be told for this character: neither
      elseif Compare.SeasonDrop(itemID, owner) then
        -- a seasonal drop: no one source's finding
      elseif source.kind == "drop" and not skinned
        and (Compare.WorldDrop(itemID, owner) or Compare.ZoneDrop(itemID, window.zones, owner)) then
        -- a world or zone drop: neither a finding nor a confirmation of a drop code
      elseif source.kind == "container" and HeldCopy(itemID, source.id) then
        -- a held copy of a removed container: the data ships what it gave, gone
      else
        Record("addition", def.prefix .. ":" .. source.id .. ":i:" .. itemID, "1", outside, ctx, source.extra)
      end
    end
    if not skinned then Curator.Store.Confirm(def.prefix .. ":" .. source.id, matched, 0, ctx) end
  end
end

-------------------------------------------------------------------------------
-- Recipes
-------------------------------------------------------------------------------
local function ReagentsText(reagents)
  local parts = {}
  for _, reagent in ipairs(reagents) do
    parts[#parts + 1] = table.concat(reagent.itemIDs, "/") .. "x" .. reagent.count
  end
  return table.concat(parts, ",")
end

-- One item of a required reagent slot against its reagent code for the
-- recipe (on a route that serves the character): "ok", "addition" or
-- "conflict". Every item a slot accepts (each quality of a reagent) is its
-- own fact: one with no code is a missing alternative, never covered by
-- another quality's code (Task #421)
local function Reagent(spell, itemID, count, ctx)
  local serving, other = Shipped(itemID, "reagentOf", ctx, "g")
  local shippedCount = serving[spell]
  local fact = "g:" .. spell .. ":i:" .. itemID
  if not shippedCount then
    Record("addition", fact, tostring(count), other[spell], ctx)
    return "addition"
  end
  if shippedCount ~= true and shippedCount ~= count then
    Record("conflict", fact, tostring(count), tostring(shippedCount), ctx)
    return "conflict"
  end
  return "ok"
end

-- The shipped reagents the schematic no longer lists: every live reagent
-- code of the recipe (set, Host.ReagentsInBucket's entries) on an item none
-- of its required slots accepts is not seen, "g:<recipe>:i:<item>" =
-- "schematic", unless the curator hints mark it verified unseen. Returns
-- whether there was one
local function Obsolete(spell, schematic, set, ctx)
  local listed, any = {}, false
  for _, reagent in ipairs(schematic.reagents) do
    for _, itemID in ipairs(reagent.itemIDs) do listed[itemID] = true end
  end
  local hints = Host.Hints().unseen
  for _, entry in ipairs(set) do
    local fact = "g:" .. spell .. ":i:" .. tostring(entry.item)
    if not entry.gone and not listed[entry.item] and not hints[fact] then
      Record("notseen", fact, "schematic", nil, ctx)
      any = true
    end
  end
  return any
end

-- Recipe(spell, schematic, ctx, mayAdd, shippedSet): schematic = { product,
-- quantity, reagents = { { itemIDs, count } } } (every required reagent slot,
-- Recipe.ReadSchematic). shippedSet = { reagents = { { item, count, gone } }
-- (every reagent code the data ships for the recipe), salvage (true, false,
-- or nil when the game's recipe info can't be read) }. A shipped recipe is
-- "confirmed" only when its product, every required slot's every item and
-- the whole shipped reagent set match: a missing alternative is an addition,
-- a count that differs a conflict, a shipped reagent no slot lists not seen
-- (Obsolete; Task #421). A salvage recipe's inputs are no schematic slot, so
-- only its product is compared; without the set or the recipe's info the
-- reagents can't be compared as a whole and an otherwise matching recipe is
-- "unjudged", never confirmed. Returns "confirmed", "addition", "conflict",
-- "notseen" or "unjudged"; mayAdd false (Recipe.MayAdd: a dummy or salvage
-- recipe) records nothing for an unshipped recipe and returns "skipped".

-- Whether a shipped recipe's product is made by it only on routes no longer
-- available: a y<recipe> code on the product, every one gone
local function Dead(spell, product)
  if not product or product <= 0 then return false end
  local any = false
  for _, code in ipairs(Host.CodesOf(product, "y")) do
    if code.id == spell then
      if not code.gone then return false end
      any = true
    end
  end
  return any
end
Compare.RecipeDead = Dead

-- { [recipe] = { [item] = true } }: a salvage recipe's own required-slot items,
-- from the schematic Compare.Recipe just read, until Compare.Salvage takes them
local ownSlots = {}

-- A shipped recipe whose product the data ships made by it only gone (Dead: no
-- one can make it now) records nothing for its reagents: the window lists
-- recipes nobody can learn (GetAllRecipeIDs), and the data ships such a
-- recipe's reagents gone (the build's R7; Task #467: 96 reagents of 25 Classic
-- Leatherworking and Blacksmithing recipes removed in 4.0.3 read as
-- additions). A salvage recipe's own required slots (a plain reagent it takes
-- beside what it salvages) are kept for Compare.Salvage.
function Compare.Recipe(spell, schematic, ctx, mayAdd, shippedSet)
  local observed = ("%dx%d"):format(schematic.product or 0, schematic.quantity or 0)
  local shipped = Host.Recipe(spell)
  if not shipped and mayAdd == false then return "skipped" end   -- a dummy or salvage recipe (Recipe.MayAdd)
  if not shipped then
    -- the recipe as one value when it fits a value's 200 characters, and each
    -- item a required slot accepts as its own reagent fact either way, so a
    -- recipe of many reagents still reaches the review item by item (Task #423)
    local value = observed .. "|" .. ReagentsText(schematic.reagents)
    if #value <= Compare.VALUE_MAX then
      Record("addition", "R:" .. spell, value, nil, ctx)
    else
      Host.Log("Recipe %d's schematic is %d characters, past a value's %d: its reagents are recorded one by one", spell,
        #value, Compare.VALUE_MAX)
    end
    for _, reagent in ipairs(schematic.reagents) do
      for _, itemID in ipairs(reagent.itemIDs) do Reagent(spell, itemID, reagent.count, ctx) end
    end
    return "addition"
  end
  local result = "confirmed"
  if (shipped.product or 0) ~= (schematic.product or 0) or (shipped.quantity or 0) ~= (schematic.quantity or 0) then
    Record("conflict", "R:" .. spell, observed, ("%dx%d"):format(shipped.product or 0, shipped.quantity or 0), ctx)
    result = "conflict"
  end
  local dead = Dead(spell, shipped.product)
  for _, reagent in ipairs(schematic.reagents) do
    for _, itemID in ipairs(reagent.itemIDs) do
      local answer = dead and "ok" or Reagent(spell, itemID, reagent.count, ctx)
      if answer == "conflict" or (answer == "addition" and result == "confirmed") then result = answer end
    end
  end
  local salvage
  if type(shippedSet) == "table" then salvage = shippedSet.salvage end
  if salvage == true then
    local own = {}
    for _, reagent in ipairs(schematic.reagents) do
      for _, itemID in ipairs(reagent.itemIDs) do own[itemID] = true end
    end
    ownSlots[spell] = own
    return result
  end
  if salvage == nil or type(shippedSet.reagents) ~= "table" then
    return result == "confirmed" and "unjudged" or result
  end
  if Obsolete(spell, schematic, shippedSet.reagents, ctx) and result == "confirmed" then result = "notseen" end
  return result
end

-- The longest value a finding may carry (the pipeline's VALUE_TEXT bound)
Compare.VALUE_MAX = 200

-- RecipeQualities(recipe, items, ctx): every quality's item of what a
-- recipe crafts, in the game's order (Recipe.Qualities; 2 or more). An item
-- the data ships as crafted by the recipe (a live y code on a route that
-- serves the character) goes in the stamp "qy:<recipe>"; any other is an
-- addition, "qy:<recipe>:i:<item>" = "<tier>", its 1-based place in the list
-- (Task #423: the window alone answers this, so curators of any profession
-- fill the data's quality items and its F table). No not seen. Returns how
-- many matched
function Compare.RecipeQualities(recipe, items, ctx)
  local matched = {}
  for tier, itemID in ipairs(items) do
    local serving, gone = Shipped(itemID, "craftedBy", ctx, "y")
    if serving[recipe] then
      matched[#matched + 1] = itemID
    else
      Record("addition", "qy:" .. recipe .. ":i:" .. itemID, tostring(tier), gone[recipe], ctx)
    end
  end
  if #matched > 0 then Curator.Store.Confirm("qy:" .. recipe, matched, 0, ctx) end
  return #matched
end

-- Salvage(skillLine, recipe, items, quantity, set, ctx): a salvage recipe's
-- inputs as the open profession window lists them (Recipe.SalvageInputs: a
-- list read and not empty), each taking quantity, against the data's
-- reagent codes for the recipe (set: Host.ReagentsInBucket's entries). Each
-- input is "sv:<skillLine>:<recipe>:i:<item>" = "<quantity>": an addition
-- with no live code, a conflict when the shipped quantity differs, in the
-- stamp "sv:<recipe>" when it matches; a live shipped input the list doesn't
-- hold is not seen ("window"). Returns "confirmed" when every input matched
-- and none is missing (Task #423). own (optional; { [item] = true }): the
-- recipe's own required-slot items, a plain reagent it takes beside what it
-- salvages; by default the ones Compare.Recipe kept from the schematic it read
-- for this recipe. They ship as reagent codes too and are no salvage input, so
-- they are never not seen here (Task #467: Protein Slurp's 5 Fine Egg Powder,
-- Everything-on-a-Stick's Coagulated Yolk)
function Compare.Salvage(skillLine, recipe, items, quantity, set, ctx, own)
  own = own or ownSlots[recipe] or {}
  ownSlots[recipe] = nil
  local result, matched, listed = "confirmed", {}, {}
  local prefix = "sv:" .. skillLine .. ":" .. recipe .. ":i:"
  for _, itemID in ipairs(items) do
    listed[itemID] = true
    local serving, gone = Shipped(itemID, "reagentOf", ctx, "g")
    local shipped = serving[recipe]
    if not shipped then
      Record("addition", prefix .. itemID, tostring(quantity), gone[recipe], ctx)
      result = "addition"
    elseif shipped ~= true and shipped ~= quantity then
      Record("conflict", prefix .. itemID, tostring(quantity), tostring(shipped), ctx)
      result = "conflict"
    else
      matched[#matched + 1] = itemID
    end
  end
  local hints = Host.Hints().unseen
  for _, entry in ipairs(type(set) == "table" and set or {}) do
    local fact = prefix .. tostring(entry.item)
    if not entry.gone and not listed[entry.item] and not own[entry.item] and not hints[fact] then
      Record("notseen", fact, "window", nil, ctx)
      listed[entry.item] = true
      if result == "confirmed" then result = "notseen" end
    end
  end
  if #matched > 0 then Curator.Store.Confirm("sv:" .. recipe, matched, 0, ctx) end
  return result
end

-- RecipeList(skillLine, listed, confirmed, ctx, comparable): listed =
-- { [recipe] = true }, what the profession's window listed; confirmed =
-- { [recipe] = true }, the listed ones whose schematic was read and matched
-- the shipped one; comparable = { [recipe] = true }, the shipped recipes the
-- window could have listed: those of an expansion tier (child skill line) it
-- listed at least one recipe of. The window lists only the tiers this
-- character has (2026-09-26: a Blacksmithing window listed 4 of its 12
-- tiers, and every recipe of the other 8 read "not seen", 2,242 false
-- findings), so a shipped recipe it didn't list is not seen only when
-- comparable; a nil comparable records no not seen at all. A stamp names
-- the positions (in the shipped profession index) of the confirmed ones only
-- (a listed recipe with a conflict or an unread schematic is neither).
-- Returns matched, shipped counts.
function Compare.RecipeList(skillLine, listed, confirmed, ctx, comparable)
  local shipped = Host.RecipesOf(skillLine)
  local matched = {}
  for position, spell in ipairs(shipped) do
    if not listed[spell] then
      if comparable and comparable[spell] then Record("notseen", "R:" .. skillLine .. ":" .. spell, "window", nil, ctx) end
    elseif confirmed[spell] then
      matched[#matched + 1] = position
    end
  end
  if #shipped > 0 then Curator.Store.Confirm("R:" .. skillLine, matched, #shipped, ctx) end
  return #matched, #shipped
end

-------------------------------------------------------------------------------
-- What an item teaches, what it is used on, what its use gives
-------------------------------------------------------------------------------
-- Each comparison below confirms only a relation on a route that serves the
-- character (Shipped); a sighting of one no longer available or for someone
-- else is an addition naming that route (Task #421).
-- Teaches(itemID, recipeID, ctx): an item used, then the recipe learned
function Compare.Teaches(itemID, recipeID, ctx)
  local shipped, gone = Shipped(itemID, "teaches", ctx, "r")
  if shipped[recipeID] then
    Curator.Store.Confirm("r:" .. itemID, { recipeID }, 1, ctx)
    return "confirmed"
  end
  local other = next(shipped)
  Record(other and "conflict" or "addition", "r:" .. itemID, tostring(recipeID), other and tostring(other) or gone[recipeID], ctx)
  return other and "conflict" or "addition"
end

-- UsedAt(itemID, targetKind ("npc" or "obj"), targetID, ctx)
function Compare.UsedAt(itemID, targetKind, targetID, ctx)
  local shipped, gone = Shipped(itemID, "usedAt", ctx, "n")
  if targetKind == "npc" and shipped[targetID] then
    Curator.Store.Confirm("n:" .. itemID, { targetID }, 0, ctx)
    return "confirmed"
  end
  Record("addition", "n:" .. itemID .. ":" .. targetKind .. ":" .. targetID, "1", targetKind == "npc" and gone[targetID] or nil, ctx)
  return "addition"
end

-- Transform(itemID, consumed, gained, spell, ctx): one use of an item that
-- consumed and gave items (Recorders/ContainerUse.lua's Transformation;
-- consumed and gained as { { id, n } } by item ID, the used item among the
-- consumed), as one addition "tf:<item>" = "<consumed>|<gained>", each
-- "<item>x<n>" comma separated, with the Use spell kept as the
-- observation's cast. The client never judges one: the pipeline sorts it
-- into a simple combine, a combine of several parts or one for review.
-- Nothing when the value would pass VALUE_MAX. Returns the record or nil
function Compare.Transform(itemID, consumed, gained, spell, ctx)
  local function Text(list)
    local parts = {}
    for _, entry in ipairs(list) do parts[#parts + 1] = ("%dx%d"):format(entry.id, entry.n) end
    return table.concat(parts, ",")
  end
  local value = Text(consumed) .. "|" .. Text(gained)
  if #value > Compare.VALUE_MAX then
    Host.Log("Item %d's use moved %d items, past a value's %d characters: not recorded", itemID, #consumed + #gained,
      Compare.VALUE_MAX)
    return nil
  end
  return Record("addition", "tf:" .. itemID, value, nil, ctx, { cast = spell or false })
end

-- Grant(itemID, currencyID, amount, ctx): using the item gave amount
function Compare.Grant(itemID, currencyID, amount, ctx)
  local serving, gone = Shipped(itemID, "currency", ctx, "$")
  local shipped = serving[currencyID]
  if shipped == amount then
    Curator.Store.Confirm("$:" .. itemID, { currencyID }, 1, ctx)
    return "confirmed"
  end
  Record("addition", "$:" .. itemID .. ":c:" .. currencyID, tostring(amount),
    shipped and tostring(shipped) or gone[currencyID], ctx)
  return "addition"
end
