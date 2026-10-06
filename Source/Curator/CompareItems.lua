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
--   de:<item>:i:<out>         disenchanting the item gave out (none yet)
--   pp:<npc>:i:<item>         pickpocketed from a creature (none yet)
--   R:<recipe>                a recipe's product and count, "<item>x<n>"
--                             (plus "|<reagents>" when the recipe isn't
--                             shipped at all; shipped: the C table)
--   R:<skillLine>:<recipe>    a shipped recipe of a profession its window
--                             didn't list (not seen)
--   g:<recipe>:i:<reagent>    how many of a reagent a recipe takes
--   r:<item>                  the recipe an item taught (shipped: teaches)
--   n:<item>:npc:<id> / :obj:<id>   what a quest item was used on (usedAt)
--   $:<item>:c:<currency>     how much of a currency using the item gave
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

-- The shipped relations of a kind for an item: { [id] = count or true }
local function Shipped(itemID, kind)
  local out = {}
  for _, relation in ipairs(Host.Sources(itemID, kind)) do
    if relation.id then out[relation.id] = relation.count or true end
  end
  return out
end
Compare.Shipped = Shipped

local function Record(kind, fact, value, shipped, ctx, extra)
  return Curator.Store.Record(kind, fact, value, shipped, ctx, extra)
end

-------------------------------------------------------------------------------
-- Loot
-------------------------------------------------------------------------------
local LOOT = {
  drop = { prefix = "c", kind = "dropsFrom" },
  object = { prefix = "ob", kind = "foundIn" },
  fishing = { prefix = "f", kind = "fishedIn" },
  container = { prefix = "x", kind = "openedFrom" },
  disenchant = { prefix = "de" },
  pickpocket = { prefix = "pp" },
}

-- Whether the data ships an item as a world drop still in the game (a live
-- z0: any enemy anywhere can drop it). One creature's copy of a world drop
-- says nothing about where to farm it, so it is no finding (2026-09-27: a
-- world-drop ore recorded from two creatures)
function Compare.WorldDrop(itemID)
  for _, code in ipairs(Host.CodesOf(itemID, "z")) do
    if code.id == 0 and not code.gone then return true end
  end
  return false
end

-- Whether the data ships an item as a drop of any enemy in one of the zones
-- given (a live z<map>: zones = { [mapID] = true }, the loot window's map
-- and the zone it lies in). One creature's copy of a zone drop, looted in
-- that zone, says no more than the zone code does; in another zone it is a
-- real difference, so only these maps count
function Compare.ZoneDrop(itemID, zones)
  if not zones then return false end
  for _, code in ipairs(Host.CodesOf(itemID, "z")) do
    if code.id ~= 0 and not code.gone and zones[code.id] then return true end
  end
  return false
end

-- Whether a live code of the item names it the loot of one of the journal
-- encounters given (encounters = { [journalID] = true }): a D<encounter>,
-- or a c<npc> of a boss the data maps (J, Host.EncounterOf) to one
function Compare.BossLoot(itemID, encounters)
  if not next(encounters) then return false end
  for _, code in ipairs(Host.CodesOf(itemID, "D")) do
    if not code.gone and encounters[code.id] then return true end
  end
  for _, code in ipairs(Host.CodesOf(itemID, "c")) do
    local journal = not code.gone and Host.EncounterOf(code.id)
    if journal and encounters[journal] then return true end
  end
  return false
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
-- is coded with (the pipeline's shipped_now reads all three the same way)
local function Known(itemID, def, source, aliases, encounters)
  if not def.kind then return false end
  local shipped = Shipped(itemID, def.kind)
  if shipped[source.id] then return true end
  for _, alias in ipairs(aliases) do
    if shipped[alias] then return true end
  end
  return Compare.BossLoot(itemID, encounters)
end

-- Loot(window, ctx): window = { sources = { [key] = { kind, id, items =
-- { [itemID] = true }, extra } }, zones }, one source per corpse, object,
-- container or fishing catch. zones (optional): the maps a zone drop counts
-- in (Loot.ZoneMaps). An item the data already has there (Known) goes in
-- the source's stamp; a creature's world drop, or its zone drop in that
-- zone, records nothing.
function Compare.Loot(window, ctx)
  for _, source in pairs(window.sources) do
    local def = LOOT[source.kind]
    local aliases, encounters = Stands(source)
    local matched = {}
    for itemID in pairs(source.items) do
      Compare.SawItem(itemID, def.prefix .. ":" .. source.id, ctx)
      if Known(itemID, def, source, aliases, encounters) then
        matched[#matched + 1] = itemID
      elseif source.kind == "drop" and (Compare.WorldDrop(itemID) or Compare.ZoneDrop(itemID, window.zones)) then
        -- a world or zone drop: neither a finding nor a confirmation of a drop code
      else
        Record("addition", def.prefix .. ":" .. source.id .. ":i:" .. itemID, "1", nil, ctx, source.extra)
      end
    end
    Curator.Store.Confirm(def.prefix .. ":" .. source.id, matched, 0, ctx)
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

-- One reagent slot against the reagent codes of its items: "ok", "addition"
-- or "conflict"
local function Reagent(spell, reagent, ctx)
  local shippedCount
  for _, itemID in ipairs(reagent.itemIDs) do
    shippedCount = Shipped(itemID, "reagentOf")[spell]
    if shippedCount then break end
  end
  local fact = "g:" .. spell .. ":i:" .. reagent.itemIDs[1]
  if not shippedCount then
    Record("addition", fact, tostring(reagent.count), nil, ctx)
    return "addition"
  end
  if shippedCount ~= true and shippedCount ~= reagent.count then
    Record("conflict", fact, tostring(reagent.count), tostring(shippedCount), ctx)
    return "conflict"
  end
  return "ok"
end

-- Recipe(spell, schematic, ctx): schematic = { product, quantity, reagents =
-- { { itemIDs, count } } } (the required basic reagents). Returns
-- "confirmed", "addition" or "conflict"; mayAdd false (Recipe.MayAdd: a
-- dummy or salvage recipe) records nothing for an unshipped recipe and
-- returns "skipped".
function Compare.Recipe(spell, schematic, ctx, mayAdd)
  local observed = ("%dx%d"):format(schematic.product or 0, schematic.quantity or 0)
  local shipped = Host.Recipe(spell)
  if not shipped and mayAdd == false then return "skipped" end   -- a dummy or salvage recipe (Recipe.MayAdd)
  if not shipped then
    Record("addition", "R:" .. spell, observed .. "|" .. ReagentsText(schematic.reagents), nil, ctx)
    return "addition"
  end
  local result = "confirmed"
  if (shipped.product or 0) ~= (schematic.product or 0) or (shipped.quantity or 0) ~= (schematic.quantity or 0) then
    Record("conflict", "R:" .. spell, observed, ("%dx%d"):format(shipped.product or 0, shipped.quantity or 0), ctx)
    result = "conflict"
  end
  for _, reagent in ipairs(schematic.reagents) do
    local answer = Reagent(spell, reagent, ctx)
    if answer == "conflict" or (answer == "addition" and result == "confirmed") then result = answer end
  end
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
-- Teaches(itemID, recipeID, ctx): an item used, then the recipe learned
function Compare.Teaches(itemID, recipeID, ctx)
  local shipped = Shipped(itemID, "teaches")
  if shipped[recipeID] then
    Curator.Store.Confirm("r:" .. itemID, { recipeID }, 1, ctx)
    return "confirmed"
  end
  local other = next(shipped)
  Record(other and "conflict" or "addition", "r:" .. itemID, tostring(recipeID), other and tostring(other) or nil, ctx)
  return other and "conflict" or "addition"
end

-- UsedAt(itemID, targetKind ("npc" or "obj"), targetID, ctx)
function Compare.UsedAt(itemID, targetKind, targetID, ctx)
  if targetKind == "npc" and Shipped(itemID, "usedAt")[targetID] then
    Curator.Store.Confirm("n:" .. itemID, { targetID }, 0, ctx)
    return "confirmed"
  end
  Record("addition", "n:" .. itemID .. ":" .. targetKind .. ":" .. targetID, "1", nil, ctx)
  return "addition"
end

-- Grant(itemID, currencyID, amount, ctx): using the item gave amount
function Compare.Grant(itemID, currencyID, amount, ctx)
  local shipped = Shipped(itemID, "currency")[currencyID]
  if shipped == amount then
    Curator.Store.Confirm("$:" .. itemID, { currencyID }, 1, ctx)
    return "confirmed"
  end
  Record("addition", "$:" .. itemID .. ":c:" .. currencyID, tostring(amount),
    shipped and tostring(shipped) or nil, ctx)
  return "addition"
end
