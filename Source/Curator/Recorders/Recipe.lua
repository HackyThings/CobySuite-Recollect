-------------------------------------------------------------------------------
-- Curator recorder: recipes (curator spec, "v1 recorders": recipe; research
-- note I section 4)
--
-- Schematics: when the character's own profession window is ready (the
-- gates Facts/Recipes.lua uses: ready, and not a linked, guild or NPC
-- crafting list), every recipe it lists is read a slice at a time
-- (GetRecipeSchematic: the product, how many, and the required basic
-- reagents with their counts) and compared with the shipped schematics; the
-- shipped recipes the window didn't list are not seen, but only those of an
-- expansion tier it listed (the window lists only the tiers the character
-- has): each recipe's tier is C_TradeSkillUI.GetTradeSkillLineForRecipe's
-- first return (its child skill line; Blizzard's ProfessionsUtil.lua reads
-- it the same way), read for the listed recipes while their schematics are
-- read, then for the unlisted shipped ones, a slice at a time. A tier that
-- can't be read makes that recipe no finding.
-- Once per profession per session; a window closed or switched mid-read
-- (the "trade" generation) writes nothing further, and records no "not
-- seen".
--
-- What a recipe item teaches: no API maps a recipe item to its recipe
-- (note I 4.3), so it is the combine rule applied to learning. An item gone
-- down by one whose own Use spell was cast just before (the bag observer),
-- and NEW_RECIPE_LEARNED within the observer's window either side, is the
-- item teaching that recipe; with two candidates, nothing is recorded.
--
-- Only while curator mode may record, and never while a test run scripts
-- the client. Client reads go through Recipe.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Bags = Curator.Recorders.Bags

local Recipe = {}
Curator.Recorders.Recipe = Recipe

local SLICE = 20
local TIER_SLICE = 100   -- unlisted shipped recipes whose tier is read in one frame
local SETTLE = 1
local BASIC = 1   -- Enum.CraftingReagentType.Basic

Recipe.seams = {
  IsReady = function() return C_TradeSkillUI.IsTradeSkillReady() end,
  IsOther = function()
    return C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild()
      or C_TradeSkillUI.IsTradeSkillGuildMember() or C_TradeSkillUI.IsNPCCrafting()
  end,
  BaseProfession = function() return C_TradeSkillUI.GetBaseProfessionInfo() end,
  RecipeIDs = function() return C_TradeSkillUI.GetAllRecipeIDs() end,
  Schematic = function(recipeID) return C_TradeSkillUI.GetRecipeSchematic(recipeID, false) end,
  TierOf = function(recipeID) return (C_TradeSkillUI.GetTradeSkillLineForRecipe(recipeID)) end,
  After = function(delay, fn) C_Timer.After(delay, fn) end,
}

local scanned = {}      -- [skillLine] = true once read this session
local scanning = nil     -- the read in progress (the list updates keep coming)
local candidate = nil   -- { itemID, at }: a recipe item just used
local learned = nil     -- { recipeID, at }: a recipe just learned

local function Seam(name, ...)
  local ok, value = pcall(Recipe.seams[name], ...)
  if not ok or Host.IsSecret(value) then return nil end
  return value
end

-------------------------------------------------------------------------------
-- Schematics
-------------------------------------------------------------------------------
-- A schematic as { product, quantity, reagents = { { itemIDs, count } } }, or nil
function Recipe.ReadSchematic(recipeID)
  local schematic = Seam("Schematic", recipeID)
  if type(schematic) ~= "table" then return nil end
  local out = { product = schematic.outputItemID, quantity = schematic.quantityMin, reagents = {} }
  for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
    if slot.reagentType == BASIC and slot.required then
      local itemIDs = {}
      for _, reagent in ipairs(slot.reagents or {}) do
        if Bags.PositiveID(reagent.itemID) then itemIDs[#itemIDs + 1] = reagent.itemID end
      end
      if #itemIDs > 0 then out.reagents[#out.reagents + 1] = { itemIDs = itemIDs, count = slot.quantityRequired } end
    end
  end
  return out
end

-- The tier (child skill line) of a recipe, or nil when it can't be read
-- A recipe's expansion tier (its child skill line), or nil. A recipe filed
-- under the profession's own skill line has no tier: the Cooking window
-- lists a few such recipes, and taking 185 as a tier made every shipped rank
-- spell and campfire of Cooking read "not seen" (curator audit, 2026-09-27)
local function Tier(recipeID, skillLine)
  local tier = Seam("TierOf", recipeID)
  if not Bags.PositiveID(tier) or tier == skillLine then return nil end
  return tier
end

local function StillOn(scan)
  if scanning ~= scan or not Curator.Compare.StillValid("trade", scan.generation)
    or not Curator.Main.StillCurrent(scan.epoch) then
    if scanning == scan then scanning = nil end
    return false
  end
  return true
end

-- The last step: which unlisted shipped recipes are of a tier the window
-- listed, TIER_SLICE a frame, then the list compared
local function Judge(scan, from)
  if not StillOn(scan) then return end
  local shipped = scan.shipped
  local last = math.min(#shipped, from + TIER_SLICE - 1)
  for index = from, last do
    local spell = shipped[index]
    if not scan.listed[spell] then
      local tier = Tier(spell, scan.skillLine)
      if tier and scan.tiers[tier] then scan.comparable[spell] = true end
    end
  end
  if last < #shipped then
    Recipe.seams.After(0, function() Judge(scan, last + 1) end)
    return
  end
  local ctx = Curator.Context.Current()
  local matched, count = Curator.Compare.RecipeList(scan.skillLine, scan.listed, scan.confirmed, ctx, scan.comparable)
  scanned[scan.skillLine], scanning = true, nil
  Host.Log("Recipes of skill line %d read: %d listed, %d of %d shipped confirmed", scan.skillLine, #scan.ids, matched, count)
end

-- One slice of a scan, in a later frame than the event: reads and compares
-- 20 recipes and notes their tiers. A scan stops when its window closed or
-- switched, curator mode was turned off, or a newer scan replaced it; it
-- clears only its own mark.
local function Step(scan, from)
  if not StillOn(scan) then return end
  local ctx = Curator.Context.Current()
  local last = math.min(#scan.ids, from + SLICE - 1)
  for index = from, last do
    local recipeID = scan.ids[index]
    local tier = Tier(recipeID, scan.skillLine)
    if tier then scan.tiers[tier] = true end
    local schematic = Recipe.ReadSchematic(recipeID)
    if schematic and Curator.Compare.Recipe(recipeID, schematic, ctx) == "confirmed" then
      scan.confirmed[recipeID] = true
    end
  end
  if last < #scan.ids then
    Recipe.seams.After(0, function() Step(scan, last + 1) end)
    return
  end
  scan.shipped = Host.RecipesOf(scan.skillLine)
  Judge(scan, 1)
end

-- Scan(): reads the open profession window's recipes, once per session
function Recipe.Scan()
  if scanning or not Curator.Main.MayRecord() or not Seam("IsReady") or Seam("IsOther") ~= false then return false end
  local base = Seam("BaseProfession")
  local skillLine = type(base) == "table" and base.professionID
  if not Bags.PositiveID(skillLine) or scanned[skillLine] then return false end
  local ids = Seam("RecipeIDs")
  if type(ids) ~= "table" or #ids == 0 then return false end
  local listed = {}
  for _, recipeID in ipairs(ids) do listed[recipeID] = true end
  local scan = { skillLine = skillLine, ids = ids, listed = listed, confirmed = {}, tiers = {}, comparable = {},
    generation = Curator.Compare.Generation("trade"), epoch = Curator.Main.Epoch() }
  scanning = scan
  Step(scan, 1)
  return true
end

-------------------------------------------------------------------------------
-- What a recipe item teaches
-------------------------------------------------------------------------------
local function Pair()
  if not (candidate and learned) then return end
  if math.abs(candidate.at - learned.at) <= Bags.CAST_WINDOW then
    local itemID, recipeID = candidate.itemID, learned.recipeID
    Curator.Main.Defer(function() Curator.Compare.Teaches(itemID, recipeID, Curator.Context.Current()) end)
  end
  candidate, learned = nil, nil
end

-- A bag change: exactly one item gone down by one, its Use spell just cast
function Recipe.OnBagsChanged(before, after)
  local down = Bags.Changes(before, after)
  local found
  for _, d in ipairs(down) do
    if d.n == 1 and Bags.CastJustNow(d.id) then
      if found then return end   -- two candidates: no answer
      found = d.id
    end
  end
  if not found then return end
  candidate = { itemID = found, at = Bags.seams.Clock() }
  Pair()
end

-- NEW_RECIPE_LEARNED (recipeID, recipeLevel, baseRecipeID)
function Recipe.OnLearned(recipeID)
  if not Curator.Main.MayRecord() or not Bags.PositiveID(recipeID) then return end
  learned = { recipeID = recipeID, at = Bags.seams.Clock() }
  Pair()
end

-- Forgets what was read this session and the pending pair (tests)
function Recipe.Reset()
  wipe(scanned)
  scanning, candidate, learned = nil, nil, nil
end

Bags.Subscribe(function(before, after) Recipe.OnBagsChanged(before, after) end)

local timer = CobySuite_Recollect.Utilities.Debounce(SETTLE, function() Recipe.Scan() end)

local handlers = {
  TRADE_SKILL_SHOW = function() timer:Call() end,
  TRADE_SKILL_LIST_UPDATE = function() timer:Call() end,
  TRADE_SKILL_DATA_SOURCE_CHANGED = function()
    Curator.Compare.Invalidate("trade")
    timer:Call()
  end,
  TRADE_SKILL_CLOSE = function()
    timer:Cancel()
    Curator.Compare.Invalidate("trade")
  end,
  NEW_RECIPE_LEARNED = function(recipeID) Recipe.OnLearned(recipeID) end,
}

local frame = CreateFrame("Frame")
for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...)
  if Curator.Main.IsScripted() then return end
  local ok, err = pcall(handlers[event], ...)
  if not ok then Host.Log("Recipe recorder %s failed: %s", event, tostring(err)) end
end)
