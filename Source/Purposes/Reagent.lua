-------------------------------------------------------------------------------
-- Purpose: a crafting reagent (the isCraftingReagent flag, or trade goods,
-- item class 7)
--
-- Facts.Recipes knows which reagents this character's learned recipes use
-- (a salvage recipe's inputs too: the herbs milling takes, the ore
-- prospecting takes), once each crafting profession's window has been
-- opened; the shipped data names the recipes the Lab read that take the
-- item, with their skill lines (Recipes.DataUses):
--   used by any of your learned recipes           Useful, naming how many
--   from the current expansion                    Useful
--   older, a profession whose recipes the data    Unknown, naming only those
--   says use it not read yet (or read before its  windows (every unread one
--   index read salvage recipes)                   when the data names no
--                                                 recipe, or one of unknown
--                                                 skill line)
--   older, a recipe of a system the index         Useful, naming what they
--   doesn't read makes a collectible you don't    make ("Used in 3 Protoform
--   have (a mount, pet, toy, ensemble, decor or   Synthesis recipes, which make
--   an appearance, Facts.Buys.Product, with the   2 things you don't have:
--   product's tooltip agreeing, rule 5)           Buzz (a mount), ..."); never
--                                                 that you can craft it
--   older, the data names recipes of a system     Unknown, led by "Used in 52
--   the recipe index doesn't read (Protoform      Protoform Synthesis
--   Synthesis, Junkyard Tinkering, a gathering    recipes", no window to
--   profession's), nothing they make missing      open: never Outdated
--   older, the data's recipes all in professions  Unknown: the unread window
--   read or not had, one not read yet             is unrelated, so none named
--   older trade goods (item class 7), every one
--   of your crafting professions read, none of
--   them uses it                                  Outdated (with the binding:
--                                                 a tradeable or warbound copy
--                                                 could still serve someone)
--   the same for any other class                  Unknown: such reagents (item
--                                                 class 15: Protoform Synthesis,
--                                                 Mechagon tinkering, covenant
--                                                 crafting) serve systems no
--                                                 profession recipe lists
-- Older means both the game's expansionID and AllTheThings' added patch
-- (Facts.Item.Age, as Consumable); when the game says older and the added
-- patch current, the reason names both and it is never Outdated.
-- Every answer where the data names recipes carries a headline with their
-- whole count ("A crafting reagent in 11 recipes; you know 2 of them"), the
-- count WHAT IT'S FOR states, never one profession's share (item 11,
-- 2026-09-25); the one for recipes only of systems the index can't read
-- keeps "Used in 52 Protoform Synthesis recipes". An Unknown that waits on a
-- read (the index, a profession window) carries readOwed.
-- What those systems' recipes make is read for at most MAX_PRODUCTS products,
-- asking for at most MAX_LOADS item loads per evaluation (as Season's crafted
-- look), and kept until data changes (Facts.Buys.Stamp, rule 9).
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber
local IsPositiveID = Recollect.Utilities.IsPositiveID

local MAX_PRODUCTS = 120
local MAX_LOADS = 8
local NAMED = 2   -- products named in the reason

-- "12 Leatherworking and 3 Blacksmithing recipes"
local function UsedText(byName)
  local names = {}
  for name in pairs(byName) do names[#names + 1] = name end
  table.sort(names)
  local parts = {}
  for _, name in ipairs(names) do parts[#parts + 1] = ("%d %s"):format(byName[name], name) end
  local total = 0
  for _, n in pairs(byName) do total = total + n end
  return table.concat(parts, " and ") .. (total == 1 and " recipe" or " recipes")
end

-- "52 Protoform Synthesis recipes", "3 Tailoring and 2 other recipes": the
-- data's lines (Recipes.DataUses), most first, with the ones whose skill
-- line has no readable name counted together
local function DataText(lines)
  local parts, unnamed, total = {}, 0, 0
  for _, line in ipairs(lines) do
    total = total + line.count
    if line.name then parts[#parts + 1] = ("%d %s"):format(line.count, line.name) else unnamed = unnamed + line.count end
  end
  if unnamed > 0 then parts[#parts + 1] = #parts > 0 and ("%d other"):format(unnamed) or tostring(unnamed) end
  return table.concat(parts, " and ") .. (total == 1 and " recipe" or " recipes")
end

local function Only(lines, indexed)
  local out = {}
  for _, line in ipairs(lines) do
    if line.indexed == indexed then out[#out + 1] = line end
  end
  return out
end

-- The unread windows worth opening: those of the professions whose recipes
-- the data says use the item, or every unread one when the data can't
-- narrow it (no recipe named, one of unknown skill line, or an index that
-- doesn't give its skill lines)
local function WindowsToOpen(index, data)
  if not data or data.unsure or type(index.missingLines) ~= "table" then return index.missing end
  local open = {}
  for skillLine, name in pairs(index.missingLines) do
    if data.covered[skillLine] then open[#open + 1] = name end
  end
  table.sort(open)
  return open
end

local function ListWords(names, joiner)
  if #names <= 1 then return names[1] or "" end
  return table.concat(names, ", ", 1, #names - 1) .. " " .. joiner .. " " .. names[#names]
end

-- The headline the panel leads an Unknown with (item 11, 2026-09-25): the
-- whole count the data gives, the same count WHAT IT'S FOR states ("A
-- crafting reagent in 11 recipes", Recipes.DataUses' total), with how many
-- of them this character's index says it knows ("; you know 2 of them"),
-- never one profession's share of it. The index may count recipes the data
-- doesn't list, so a known count above the total is left out. nil when the
-- data names no recipe.
local function Headline(data, known)
  if not data or not IsFiniteNumber(data.total) or data.total <= 0 then return nil end
  local text = ("A crafting reagent in %d %s"):format(data.total, data.total == 1 and "recipe" or "recipes")
  if known and known > 0 and known <= data.total then text = ("%s; you know %d of them"):format(text, known) end
  return text
end

-- An Unknown that waits on a read (the recipe index, a profession window):
-- readOwed marks it, so a headline it carries is never taken for a use's
-- progress (Verdicts.Settle softens those under a season result)
local function Owed(result)
  result.readOwed = true
  return result
end

-- How many recipes the index says this character knows that use the item
local function Known(index, itemID)
  local n = 0
  for _, count in pairs(index and index.uses[itemID] or {}) do
    if IsFiniteNumber(count) then n = n + count end
  end
  return n
end

-- A product's kind, for a reason
local WHAT = { mount = "a mount", pet = "a pet", toy = "a toy", ensemble = "an ensemble", decor = "decor",
  appearance = "an appearance", illusion = "a weapon illusion", heirloom = "an heirloom" }

-- What the recipes of systems the index never reads make (data.covered holds
-- the indexed skill lines): { missing = { thing }, have, unread, loading,
-- more } over distinct products, each read through Facts.Buys.Product (a
-- collectible only; a plain product, or one this character can't collect,
-- counts nowhere)
local function ReadProducts(itemID, data, owner)
  local Relations, Recipes, Buys = Recollect.Facts.Relations, Recollect.Facts.Recipes, Recollect.Facts.Buys
  local made = { missing = {}, have = 0, unread = 0, loading = 0, more = 0 }
  local seen, count, loads = {}, 0, 0
  for _, relation in ipairs(Relations.For(itemID)) do
    if relation.kind == "reagentOf" and not (relation.flags and relation.flags.unavailable) then
      local recipe = Relations.Recipe(relation.id)
      local skillLine = recipe and IsPositiveID(recipe.skillLine) and Recipes.ProfessionOf(recipe.skillLine) or 0
      local product = recipe and recipe.product
      if data.covered[skillLine] == nil and IsPositiveID(product) and not seen[product] then
        seen[product] = true
        count = count + 1
        if count > MAX_PRODUCTS then
          made.more = made.more + 1
        else
          local thing, why = Buys.Product(product, owner)
          if thing then
            if thing.state == "missing" then made.missing[#made.missing + 1] = thing
            elseif thing.state == "have" then made.have = made.have + 1
            elseif thing.state == "unavailable" then   -- not for this character: never counted as unread
            else made.unread = made.unread + 1 end
          elseif why == "loading" then
            -- nothing loads it there: ask here, a few per evaluation (Facts.Item
            -- fires InventoryChanged when it arrives, which reads it again)
            if loads < MAX_LOADS then
              loads = loads + 1
              Recollect.Facts.Item.Get(product)
            end
            made.loading = made.loading + 1
          end
        end
      end
    end
  end
  return made
end

-- ReadProducts' answer, kept per parsed relation list and owner while every
-- state it read is (Facts.Buys.Stamp: until data changes, rule 9)
local products, productsStamp = setmetatable({}, { __mode = "k" }), nil
local function Products(ctx, data)
  local itemID = ctx.stack.itemID
  local owner = ctx.owner or { faction = ctx.playerFaction, isViewer = not ctx.otherCharacter, name = ctx.otherCharacter }
  local stamp = Recollect.Facts.Buys.Stamp()
  if stamp ~= productsStamp then products, productsStamp = setmetatable({}, { __mode = "k" }), stamp end
  local list = Recollect.Facts.Relations.For(itemID)
  local byOwner = products[list]
  if not byOwner then
    byOwner = {}
    products[list] = byOwner
  end
  local key = owner.isViewer and "viewer" or tostring(owner.guid or owner.name)
  local made = byOwner[key]
  if not made then
    made = ReadProducts(itemID, data, owner)
    byOwner[key] = made
  end
  return made
end

-- "Buzz (a mount), Pale Regal Cervid (a mount) and 1 more"
local function MissingWords(missing)
  local names = {}
  for i = 1, math.min(NAMED, #missing) do
    local thing = missing[i]
    local what = WHAT[thing.what] or thing.what
    local name = Recollect.Facts.Buys.Name(thing) or (thing.itemID and Recollect.Facts.Item.Name(thing.itemID))
    names[#names + 1] = name and ("%s (%s)"):format(name, what) or what
  end
  local more = #missing - #names
  return table.concat(names, ", ") .. (more > 0 and (" and %d more"):format(more) or "")
end

-- What the reason adds when nothing they make is missing: "; you have all 3
-- collectibles they make", "; 2 things they make can't be read yet"
local function MadeWords(made)
  if not made then return "" end
  local parts = {}
  local waiting = made.unread + made.loading
  if made.have > 0 and waiting == 0 and made.more == 0 then
    parts[#parts + 1] = made.have == 1 and "you have the one collectible they make"
      or ("you have all %d collectibles they make"):format(made.have)
  end
  if waiting > 0 then
    parts[#parts + 1] = ("%d %s they make can't be read yet"):format(waiting, waiting == 1 and "thing" or "things")
  end
  if made.more > 0 then
    parts[#parts + 1] = ("%d more %s they make %s checked"):format(made.more, made.more == 1 and "thing" or "things",
      made.more == 1 and "isn't" or "aren't")
  end
  return #parts > 0 and ("; " .. table.concat(parts, "; ")) or ""
end

-- The verdict for a reagent, from this character's recipe index and the
-- recipes the shipped data names (data, Recipes.DataUses, or nil)
local function Judge(ctx, index, data)
  local byName = index and index.uses[ctx.stack.itemID]
  if byName and next(byName) then
    local reason = "Used by " .. UsedText(byName) .. " you know"
    local head = Headline(data)
    if head then reason = reason .. "; " .. head:gsub("^A c", "a c") end
    return R.Result(V.USEFUL, reason)
  end
  local age, expansion, source, patch = R.Age(ctx)
  -- A failed read: never softened by a season result (review F12)
  if not age then return Owed(R.Unknown("Crafting reagent; its expansion can't be read")) end
  if age == "current" then return R.Result(V.USEFUL, "A current-expansion crafting reagent") end
  local UseEffect = Recollect.Purposes.UseEffect
  -- "from Shadowlands", or both expansions named when they disagree
  local tag = age == "older" and UseEffect.From(expansion, source, patch)
    or ("(" .. UseEffect.Disagree(ctx.facts, expansion, patch) .. ")")
  local what = "A crafting reagent " .. tag
  if data then what = ("%s, used in %s"):format(what, DataText(data.lines)) end
  -- A recipe of a system the index never reads that makes a collectible
  -- still to get (Protoform Sentience Crown): Useful, whatever else is unread
  local made = data and data.other > 0 and Products(ctx, data) or nil
  if made and #made.missing > 0 then
    local result = R.Result(V.USEFUL, ("Used in %s, which %s %d %s you don't have: %s; a crafting reagent %s"):format(
      DataText(Only(data.lines, false)), data.other == 1 and "makes" or "make", #made.missing,
      #made.missing == 1 and "thing" or "things",
      MissingWords(made.missing), tag))
    -- A missing collectible it still makes is no gear power a past season
    -- replaced: a season result never softens it (Verdicts.Settle, review F12)
    result.noSettle = true
    return result
  end
  if index and not index.complete then
    local open = WindowsToOpen(index, data)
    if #open > 0 then
      local windows = table.concat(open, " and ")
      local result = R.Unknown(("%s; open your %s window once so Recollect can read which recipes use it"):format(
        what, windows), nil, "profession")
      result.recovery = ("Open your %s %s once"):format(windows, #open == 1 and "window" or "windows")
      result.readOwed = true
      return result
    end
  end
  -- Recipes the index never reads (Protoform Synthesis): said plainly, with
  -- no window to open, and never Outdated
  if data and data.other > 0 then
    local other = Only(data.lines, false)
    local used = "Used in " .. DataText(other)
    local count = 0
    for _, line in ipairs(other) do count = count + line.count end
    -- The panel shows the headline, then the reason without its words; with
    -- recipes of read professions too, the headline is the whole count
    local headline = next(data.covered) and Headline(data, Known(index, ctx.stack.itemID)) or used
    local result = R.Unknown(("%s; Recollect can't read %s; a crafting reagent %s%s%s"):format(used,
      count == 1 and "that recipe" or "those recipes", tag,
      next(data.covered) and (", also used in " .. DataText(Only(data.lines, true))) or "", MadeWords(made)), headline)
    -- What they make still being read (or not checked) is a read owed, not
    -- a use's progress (review F12)
    if made and (made.unread + made.loading > 0 or made.more > 0) then result.readOwed = true end
    return result
  end
  if not index then return Owed(R.Unknown(what .. "; which recipes use it can't be read")) end
  if not index.complete then
    -- The data names recipes, none of them of the unread professions
    return Owed(R.Unknown(("%s, none of them %s recipes; your %s recipes aren't read yet"):format(what,
      ListWords(index.missing, "or"), ListWords(index.missing, "and"))))
  end
  if #index.names == 0 then return R.Unknown(what .. "; this character has no crafting profession") end
  if age == "disagree" then
    return R.Unknown(("%s; none of your recipes (%s) use it, but whether it's of an older expansion can't be told"):format(
      what, table.concat(index.names, ", ")))
  end
  if ctx.facts.classID ~= R.CLASS_TRADEGOODS then
    return R.Unknown(("%s; none of your recipes (%s) use it; it may belong to another crafting system (such as Protoform Synthesis), which isn't checked"):format(
      what, table.concat(index.names, ", ")))
  end
  return R.Result(V.OUTDATED, ("%s; none of your recipes (%s) use it%s"):format(what,
    table.concat(index.names, ", "), R.BindNote(ctx)))
end

R.Register({
  key = "reagent",
  label = "Reagent",
  order = 70,
  Evaluate = function(ctx)
    if not ctx.facts.isCraftingReagent and ctx.facts.classID ~= R.CLASS_TRADEGOODS then return nil end
    -- One shared answer per frame (Facts.Recipes keeps it), so every reagent
    -- row of a redraw reads the same merged index; never change it here
    local okIndex, index = pcall(Recollect.Facts.Recipes.ForCharacter)
    index = okIndex and type(index) == "table" and index or nil
    local okData, data = pcall(Recollect.Facts.Recipes.DataUses, ctx.stack.itemID)
    data = okData and type(data) == "table" and data or nil
    local result = Judge(ctx, index, data)
    -- Every answer with the data's recipes leads with their whole count; the
    -- one for recipes the index can't read keeps its own words
    if result and result.headline == nil then result.headline = Headline(data, Known(index, ctx.stack.itemID)) end
    return result
  end,
})
