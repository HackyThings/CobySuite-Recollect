-------------------------------------------------------------------------------
-- Curator.Compare, continued: loot, recipes, what an item teaches, what a
-- quest item is used on, and what an item's use gives (curator plan, phase
-- 4c), against the shipped data through Host only
--
-- Facts (the store's fact names; values are text):
--   c:<npc>:i:<item>          dropped by a creature (shipped: dropsFrom)
--   ob:<object>:i:<item>      found in an object or node (shipped: foundIn)
--   f:<map>:i:<item>          fished in a zone (shipped: zoneDrop)
--   x:<container>:i:<item>    found in a container item (no shipped code yet)
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
  fishing = { prefix = "f", kind = "zoneDrop" },
  container = { prefix = "x" },
  disenchant = { prefix = "de" },
  pickpocket = { prefix = "pp" },
}
Compare.LOOT = LOOT

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

-- Loot(window, ctx): window = { sources = { [key] = { kind, id, items =
-- { [itemID] = true }, extra } } }, one source per corpse, object,
-- container or fishing catch. A creature's world drop records nothing.
function Compare.Loot(window, ctx)
  for _, source in pairs(window.sources) do
    local def = LOOT[source.kind]
    local matched = {}
    for itemID in pairs(source.items) do
      if def.kind and Shipped(itemID, def.kind)[source.id] then
        matched[#matched + 1] = itemID
      elseif source.kind == "drop" and Compare.WorldDrop(itemID) then
        -- a world drop: neither a finding nor a confirmation of a drop code
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
-- "confirmed", "addition" or "conflict".
function Compare.Recipe(spell, schematic, ctx)
  local observed = ("%dx%d"):format(schematic.product or 0, schematic.quantity or 0)
  local shipped = Host.Recipe(spell)
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
