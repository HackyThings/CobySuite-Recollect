-------------------------------------------------------------------------------
-- Facts.Recipes: which reagents this character's learned recipes use
--
-- Recipe data is only complete while the character's own profession window
-- is open (the Lab: C_TradeSkillUI.GetRecipeInfo(id).learned is the truth
-- then, and unreliable with the window closed). So when that window is open
-- and ready (IsTradeSkillReady; not a linked, guild, guild member's or NPC
-- window), every recipe of the profession (GetAllRecipeIDs) is read a chunk
-- per frame: for each learned one, GetRecipeSchematic(id, false) lists its
-- reagent slots, and each reagent item counts that recipe once. A salvage
-- recipe (milling, prospecting, crushing, thaumaturgy) takes its input in a
-- slot of its own, outside the reagent slots, so its inputs come from
-- GetSalvagableItemIDs, as Blizzard's salvage slot reads them. The result is
-- kept per character:
--   characters[key].recipes[skillLine] = { name, at, build, learned, version,
--     uses = { [itemID] = learned recipes that use it } }
-- An index of another INDEX_VERSION (one built before salvage inputs were
-- read) counts as missing. A scan cut short is dropped, never stored half
-- done: the window closed, the data source changing or changed, a recipe
-- learned, an unreadable recipe or salvage list, or a step finding the
-- window no longer this character's own copy of that profession. Learning a
-- recipe marks the profession stale until its window is opened again. A
-- profession is scanned once per window open: once its scan is stored, the
-- list updates that follow (TRADE_SKILL_LIST_UPDATE fires again and again
-- while the window is up) scan nothing until the window closes, its data
-- source changes or a recipe is learned.
--
-- ForCharacter() answers for the reagent check: every crafting profession
-- the character has (GetProfessions: the two primary ones and cooking) must
-- be indexed and not stale, or it names the ones still to open. Its answer
-- is kept for the frame (GetTime) until an index or the professions change,
-- so a list redraw merges the stored indexes once, not once per reagent.
--
-- It also gives the skill lines apart (missingLines, indexedLines:
-- { [skillLine] = name }), so the reagent check can name only the unread
-- professions whose recipes use an item.
--
-- DataUses(itemID) says which recipes the shipped data names for an item
-- (its reagent codes, g, each recipe's skill line from Relations.Recipe),
-- grouped by skill line. The recipe index reads only the crafting
-- professions (CRAFTING); a recipe of any other skill line (Protoform
-- Synthesis 2819, Junkyard Tinkering 2720, Abominable Stitching 2787, a
-- gathering profession's, or one whose skill line the Lab couldn't read)
-- belongs to a system the index never reads. The data lists only the
-- schematics the Lab read, so it narrows which windows to open and names
-- what the index can't see; it never says a recipe is absent.
--
-- IsProfession(skillLine): whether a recipe of that skill line is a player
-- profession's, whose known state C_SpellBook.IsSpellKnown answers (the Lab,
-- 2026-09-23: right on 400 of 400 Blacksmithing and Leatherworking
-- recipes). Recipes of other systems were never measured (Facts.Buys).
--
-- Recorded alt use (F-02): at login and on SKILL_LINES_CHANGED the
-- character's crafting professions are stored (char.professions, a set of
-- skill lines, with professionsAt), and an index of a profession it no
-- longer has is marked stale and dropped (CR-09). RecordedByOthers(itemID)
-- lists what other characters' current scans recorded: { name, profession,
-- count, scannedAt }, only for indexes of the current INDEX_VERSION, not
-- stale, of a profession the character still had at its last login. It is
-- history, never a claim that the recipe is still known or that this copy
-- can reach that character.
-------------------------------------------------------------------------------
local Recipes = {}
Recollect.Facts.Recipes = Recipes

local Try = Recollect.Utilities.Try

local RECIPES_PER_STEP = 60
-- 2: salvage recipes' inputs are indexed (version 1, unmarked, left them out)
local INDEX_VERSION = 2
local SALVAGE = (Enum and Enum.TradeskillRecipeType and Enum.TradeskillRecipeType.Salvage) or 2
-- Skill lines with recipes that use reagents (gathering, fishing and
-- archaeology have none): Blacksmithing, Leatherworking, Alchemy, Cooking,
-- Mining (smelting), Tailoring, Engineering, Enchanting, Jewelcrafting,
-- Inscription
local CRAFTING = { [164] = true, [165] = true, [171] = true, [185] = true, [186] = true,
  [197] = true, [202] = true, [333] = true, [755] = true, [773] = true }
-- Every player profession's skill line: the crafting ones, and Herbalism,
-- Skinning and Fishing, whose recipes are learned the same way
local PROFESSIONS = { [182] = true, [393] = true, [356] = true }
for skillLine in pairs(CRAFTING) do PROFESSIONS[skillLine] = true end
-- A specialization's recipes carry its spell as their skill line where the
-- game gave none and AllTheThings' requireSkill did (the data build's
-- recipe table): Gnomish and Goblin Engineering; Weaponsmith, Armorsmith and
-- the three master weaponsmiths; Dragonscale, Elemental and Tribal
-- Leatherworking. Each is its profession's (Lab.RecipeLeads keys them so).
local SPECIALIZATION = { [20219] = 202, [20222] = 202, [9787] = 164, [9788] = 164, [17039] = 164, [17040] = 164,
  [17041] = 164, [10656] = 165, [10658] = 165, [10660] = 165 }

local seams = {
  IsReady = function() return C_TradeSkillUI.IsTradeSkillReady() end,
  -- Blizzard's own test for a list that isn't the player's (Professions.InLocalCraftingMode)
  IsOther = function()
    return C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild()
      or C_TradeSkillUI.IsTradeSkillGuildMember() or C_TradeSkillUI.IsNPCCrafting()
  end,
  BaseProfession = function() return C_TradeSkillUI.GetBaseProfessionInfo() end,
  RecipeIDs = function() return C_TradeSkillUI.GetAllRecipeIDs() end,
  RecipeInfo = function(recipeID) return C_TradeSkillUI.GetRecipeInfo(recipeID) end,
  Schematic = function(recipeID) return C_TradeSkillUI.GetRecipeSchematic(recipeID, false) end,
  Salvagable = function(recipeID) return C_TradeSkillUI.GetSalvagableItemIDs(recipeID) end,
  Professions = function() return GetProfessions() end,
  ProfessionInfo = function(index) return GetProfessionInfo(index) end,
  Character = function() return Recollect.Inventory.Snapshots.CurrentCharacter(true) end,
  OtherCharacters = function() return Recollect.Inventory.Snapshots.OtherCharacters() end,
  After = function(delay, fn) C_Timer.After(delay, fn) end,
  Build = function() return Recollect.Utilities.Build() end,
  Now = function() return GetTime() end,   -- the same all through one frame
  SkillLineName = function(skillLine) return C_TradeSkillUI.GetTradeSkillDisplayName(skillLine) end,
}

local scan = nil   -- { skillLine, name, ids, index, learned, uses }
-- [skillLine] = true once a scan of it was stored since its window opened:
-- the list updates that follow scan nothing until the window closes, its
-- data source changes or a recipe is learned
local scanned = {}
-- Bumped whenever a stored index or the character's professions change; with
-- the frame's time it keys ForCharacter's kept answer
local generation = 0
local cache = nil   -- { now, generation, store, result }

local function Store()
  local char = seams.Character()
  if type(char) ~= "table" then return nil end
  if type(char.recipes) ~= "table" then char.recipes = {} end
  return char.recipes
end

-- The reagent items one learned recipe uses, each once, added to uses; a
-- salvage recipe adds the items it can salvage. False when either list
-- can't be read, so the scan is dropped rather than stored without them.
local function AddRecipe(uses, recipeID, info)
  local ok, schematic = Try(seams.Schematic, recipeID)
  if not ok or type(schematic) ~= "table" or type(schematic.reagentSlotSchematics) ~= "table" then return false end
  local seen = {}
  local function Add(itemID)
    if type(itemID) == "number" and not seen[itemID] then
      seen[itemID] = true
      uses[itemID] = (uses[itemID] or 0) + 1
    end
  end
  for _, slot in ipairs(schematic.reagentSlotSchematics) do
    for _, reagent in ipairs(type(slot) == "table" and slot.reagents or {}) do
      Add(type(reagent) == "table" and reagent.itemID)
    end
  end
  if schematic.recipeType == SALVAGE or info.isSalvageRecipe == true then
    local okS, items = Try(seams.Salvagable, recipeID)
    -- An empty list can't be right for a salvage recipe: every one takes an input
    if not okS or type(items) ~= "table" or #items == 0 then return false end
    for _, itemID in ipairs(items) do Add(itemID) end
  end
  return true
end

local function Finish(s)
  scan = nil
  local store = Store()
  if not store then return end
  store[s.skillLine] = { name = s.name, at = time(), build = seams.Build(), learned = s.learned,
    version = INDEX_VERSION, uses = s.uses }
  scanned[s.skillLine] = true
  generation = generation + 1
  Recollect.Debug.Log("PURPOSE", "Recipe index for %s: %d learned recipes, %d reagent items",
    tostring(s.name), s.learned, CobySuite_Recollect.Utilities.TableCount(s.uses))
  Recollect.EventBus:Fire(Recollect.Events.InventoryChanged, "recipes")
end

local function Step(s)
  if scan ~= s then return end   -- cancelled
  -- Every chunk: still ready, still this character's own list, still this
  -- profession. Another profession or someone else's list may have loaded
  -- with the window left open, and learned then no longer describes s.
  local okReady, ready = Try(seams.IsReady)
  local okOther, other = Try(seams.IsOther)
  local okBase, base = Try(seams.BaseProfession)
  if not okReady or not ready or not okOther or other or not okBase or type(base) ~= "table"
      or base.professionID ~= s.skillLine then
    scan = nil
    return
  end
  for i = s.index, math.min(s.index + RECIPES_PER_STEP - 1, #s.ids) do
    local recipeID = s.ids[i]
    local ok, info = Try(seams.RecipeInfo, recipeID)
    if not ok or type(info) ~= "table" or type(info.learned) ~= "boolean" then
      scan = nil   -- an unreadable recipe: drop the scan rather than store a partial one
      return
    end
    if info.learned then
      if not AddRecipe(s.uses, recipeID, info) then
        scan = nil
        return
      end
      s.learned = s.learned + 1
    end
  end
  s.index = s.index + RECIPES_PER_STEP
  if s.index > #s.ids then
    Finish(s)
  else
    seams.After(0, function() Step(s) end)
  end
end

-- Start a scan of the open window's profession, if it is this character's own
function Recipes.Scan()
  local okReady, ready = Try(seams.IsReady)
  if not okReady or not ready then return end
  local okOther, other = Try(seams.IsOther)
  if not okOther or other then return end
  local okBase, base = Try(seams.BaseProfession)
  if not okBase or type(base) ~= "table" or type(base.professionID) ~= "number" then return end
  if not CRAFTING[base.professionID] then return end
  if scanned[base.professionID] then return end   -- read once already since the window opened
  local okIDs, ids = Try(seams.RecipeIDs)
  if not okIDs or type(ids) ~= "table" or #ids == 0 then return end
  if scan and scan.skillLine == base.professionID then return end   -- already scanning it
  scan = { skillLine = base.professionID, name = base.professionName, ids = ids, index = 1, learned = 0, uses = {} }
  Step(scan)
end

-- The crafting professions this character has: { [skillLine] = name } or nil
local function CraftingProfessions()
  local ok, a, b, _, _, cooking = Try(seams.Professions)
  if not ok then return nil end
  local list = {}
  for _, index in pairs({ a, b, cooking }) do
    local okInfo, name, _, _, _, _, _, skillLine = Try(seams.ProfessionInfo, index)
    if not okInfo then return nil end
    if CRAFTING[skillLine] then list[skillLine] = name end
  end
  return list
end

-- ForCharacter(): { complete, missing = { names }, names = { indexed names },
-- missingLines, indexedLines = { [skillLine] = name }, uses = { [itemID] =
-- { [name] = n } } }, or nil when the professions can't be read. The answer
-- is shared for the rest of the frame: read it, never change it.
function Recipes.ForCharacter()
  local now, stored = seams.Now(), Store()
  if cache and cache.now == now and cache.generation == generation and cache.store == stored then
    return cache.result
  end
  local professions = CraftingProfessions()
  if not professions then return nil end
  local store = stored or {}
  local result = { complete = true, missing = {}, uses = {}, names = {}, missingLines = {}, indexedLines = {} }
  for skillLine, name in pairs(professions) do
    local entry = store[skillLine]
    if type(entry) ~= "table" or type(entry.uses) ~= "table" or entry.stale or entry.version ~= INDEX_VERSION then
      result.complete = false
      result.missing[#result.missing + 1] = name
      result.missingLines[skillLine] = name
    else
      result.names[#result.names + 1] = name
      result.indexedLines[skillLine] = name
      for itemID, n in pairs(entry.uses) do
        local byName = result.uses[itemID]
        if not byName then
          byName = {}
          result.uses[itemID] = byName
        end
        byName[name] = n
      end
    end
  end
  table.sort(result.missing)
  table.sort(result.names)
  cache = { now = now, generation = generation, store = stored, result = result }
  return result
end

-- The profession a skill line belongs to: a specialization's parent, else
-- the skill line itself
function Recipes.ProfessionOf(skillLine)
  return SPECIALIZATION[skillLine] or skillLine
end

-- Whether the recipe index reads a skill line (a crafting profession, or
-- one of its specializations)
function Recipes.IsIndexed(skillLine)
  return CRAFTING[Recipes.ProfessionOf(skillLine)] == true
end

-- Whether a skill line is a player profession's, or one of its
-- specializations (see the header)
function Recipes.IsProfession(skillLine)
  return PROFESSIONS[Recipes.ProfessionOf(skillLine)] == true
end

-- A skill line's name in the client's language ("Protoform Synthesis"), or nil
function Recipes.SkillLineName(skillLine)
  if not Recollect.Utilities.IsPositiveID(skillLine) then return nil end
  local ok, name = Try(seams.SkillLineName, skillLine)
  return ok and type(name) == "string" and name ~= "" and name or nil
end

-- DataUses(itemID): the recipes the shipped data names for an item, or nil
-- when it names none. { total, other (recipes of skill lines the index
-- doesn't read), covered = { [skillLine] = n } (those it does), unsure
-- (true when a recipe's skill line isn't known, so which profession it is
-- can't be told), lines = { { skillLine (0 unknown), count, indexed, name } }
-- (most recipes first) }. Recipes no longer in the game are left out. The
-- counts are kept with the item's parsed relations (Relations.For keeps one
-- list per item while it is in use; the data doesn't change in a session),
-- so a redraw of many older reagents looks each recipe up once; the names
-- are read at each call.
local countsOf = setmetatable({}, { __mode = "k" })   -- [relations list] = { bySkill, total }

local function DataCounts(list)
  local kept = countsOf[list]
  if kept then return kept end
  local Relations = Recollect.Facts.Relations
  local bySkill, total = {}, 0
  for _, relation in ipairs(list) do
    if relation.kind == "reagentOf" and not (relation.flags and relation.flags.unavailable) then
      local recipe = Relations.Recipe(relation.id)
      local skillLine = recipe and Recollect.Utilities.IsPositiveID(recipe.skillLine) and Recipes.ProfessionOf(recipe.skillLine) or 0
      bySkill[skillLine] = (bySkill[skillLine] or 0) + 1
      total = total + 1
    end
  end
  kept = { bySkill = bySkill, total = total }
  countsOf[list] = kept
  return kept
end

function Recipes.DataUses(itemID)
  local list = Recollect.Facts.Relations.For(itemID)
  if type(list) ~= "table" then return nil end
  local counts = DataCounts(list)
  local bySkill, total = counts.bySkill, counts.total
  if total == 0 then return nil end
  local result = { total = total, other = 0, covered = {}, unsure = bySkill[0] ~= nil, lines = {} }
  for skillLine, count in pairs(bySkill) do
    local indexed = CRAFTING[skillLine] == true
    if indexed then result.covered[skillLine] = count else result.other = result.other + count end
    result.lines[#result.lines + 1] = { skillLine = skillLine, count = count, indexed = indexed,
      name = Recipes.SkillLineName(skillLine) }
  end
  table.sort(result.lines, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.skillLine < b.skillLine
  end)
  return result
end

-- A recipe was learned: every stored profession is stale until reopened
local function MarkStale()
  for _, entry in pairs(Store() or {}) do
    if type(entry) == "table" then entry.stale = true end
  end
  generation = generation + 1
end

-- The character's crafting professions, stored as a set of skill lines; an
-- index of one it no longer has is marked stale (CR-09). Nothing is stored
-- when the professions can't be read.
function Recipes.RecordProfessions()
  local professions = CraftingProfessions()
  local char = seams.Character()
  if not professions or type(char) ~= "table" then return false end
  local set = {}
  for skillLine in pairs(professions) do set[skillLine] = true end
  char.professions, char.professionsAt = set, time()
  for skillLine, entry in pairs(type(char.recipes) == "table" and char.recipes or {}) do
    if type(entry) == "table" and not set[skillLine] then entry.stale, entry.dropped = true, true end
  end
  generation = generation + 1
  return true
end

-- The recipes other characters' scans recorded, by item, kept for the frame
local recorded = nil   -- { now, generation, byItem }

local function RecordedIndex()
  local now = seams.Now()
  if recorded and recorded.now == now and recorded.generation == generation then return recorded.byItem end
  local byItem = {}
  for _, other in ipairs(seams.OtherCharacters()) do
    local char = other.char
    local professions = type(char.professions) == "table" and char.professions or nil
    for skillLine, entry in pairs(type(char.recipes) == "table" and char.recipes or {}) do
      -- membership must be known and hold the profession; the index current
      if professions and professions[skillLine] and type(entry) == "table" and type(entry.uses) == "table"
          and not entry.stale and entry.version == INDEX_VERSION then
        for itemID, n in pairs(entry.uses) do
          local list = byItem[itemID]
          if not list then
            list = {}
            byItem[itemID] = list
          end
          list[#list + 1] = { name = tostring(char.name or "another character"), profession = tostring(entry.name or "a profession"),
            count = n, scannedAt = entry.at }
        end
      end
    end
  end
  for _, list in pairs(byItem) do
    table.sort(list, function(a, b)
      if a.name ~= b.name then return a.name < b.name end
      return a.profession < b.profession
    end)
  end
  recorded = { now = now, generation = generation, byItem = byItem }
  return byItem
end

-- RecordedByOthers(itemID): { { name, profession, count, scannedAt } }, read-only
function Recipes.RecordedByOthers(itemID)
  return RecordedIndex()[itemID] or {}
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_DATA_SOURCE_CHANGING", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE", "NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED", "PLAYER_ENTERING_WORLD" }) do
  pcall(frame.RegisterEvent, frame, event)
end
local function OnEvent(_, event)
  if event == "TRADE_SKILL_CLOSE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGING" then
    scan = nil
    scanned = {}
  elseif event == "NEW_RECIPE_LEARNED" then
    scan = nil   -- it may have read the new recipe before it was learned
    scanned = {}
    MarkStale()
  elseif event == "SKILL_LINES_CHANGED" then
    generation = generation + 1   -- a profession learned or dropped
    seams.After(0.5, Recipes.RecordProfessions)
  elseif event == "PLAYER_ENTERING_WORLD" then
    seams.After(2, Recipes.RecordProfessions)   -- the professions are readable once in the world
  else
    if event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then scan, scanned = nil, {} end
    seams.After(0.5, Recipes.Scan)   -- let the list settle first
  end
end
frame:SetScript("OnEvent", OnEvent)

Recipes._test = {
  seams = seams,
  CRAFTING = CRAFTING,
  PROFESSIONS = PROFESSIONS,
  INDEX_VERSION = INDEX_VERSION,
  IsScanning = function() return scan ~= nil end,
  Cancel = function() scan = nil end,
  Invalidate = function() generation = generation + 1 end,
  OnEvent = function(event) OnEvent(nil, event) end,
  -- the skill lines scanned since their window opened, set aside for a test and put back
  GetScanned = function() return scanned end,
  SetScanned = function(set) scanned = set end,
}
