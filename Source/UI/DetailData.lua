-------------------------------------------------------------------------------
-- UI.DetailData: the pinned view's rows, as data, built a slice at a time
--
-- The pinned view (UI.DetailWindow) shows what an item is for and where it
-- comes from as tables, one per tab. Build(itemID, stack, owner) starts a
-- job that turns the item's relations (Facts.Relations), the journals'
-- costs, the recipe index, recorded alt use, recorded vendors and what a use
-- takes (Facts.Requirements) into rows, spending at most BUDGET_MS of each
-- frame (Data.Start), so an item with thousands of routes (Mark of Honor buys
-- about 8,700 things) never stalls a frame. A row is
--   { tab, kind, what, kindLabel, id, itemID, spellID, questID,
--     achievementID, criteria, currencyID, npcID, npcs, objectID, count,
--     encounterID, factionID, level, month,
--     plus, relation, thing, restricted, untold, gone, tags, dimmed,
--     state, stateText, stateInline, stateColor, filterState, tier,  -- Resolve
--     name, icon, sellerText, place }                      -- read when shown
-- tags are the route's conditions the owner misses, and an event route's
-- for everyone (UsedFor.parts.Tags, D19; display only, D34): a gone,
-- restricted or untold row's state is their words ("Blood Elf only", "No
-- longer obtainable"; stateInline as they read inside a sentence), and an
-- event route that serves the owner adds its tag after its state ("Not
-- done, during a holiday or event"), and so does a display-only condition
-- the owner misses (a profession, a reputation standing, a completed quest;
-- D34), which also sets dimmed: the name is dimmed, nothing else moves.
-- filterState is "missing" (still to get or do), "have", "other" (for
-- another faction, class or race, or no longer available) or "none" (no
-- state to read; also a route whose condition the owner's record can't
-- answer, untold, which is restricted but not for someone else). Resolve
-- reads a row's state now; the window resolves every row again, sliced,
-- when data arrives (Data.Refresh). Names, icons, sellers
-- and places are read only for rows on screen, and cached on the row. Item
-- names load through the view's own loader (NAME_LOADS new requests a frame,
-- ITEM_DATA_LOAD_RESULT noticed here), which fires no InventoryChanged, so
-- the list and the audit panel are never rebuilt for a name.
--
-- The words and states come from the helpers UI.UsedFor uses for the panel
-- (UsedFor.parts), so a row and a panel line never disagree. A plain item a
-- purchase names is followed to what it leads to (Facts.Chains, contract
-- rule 39) for the first MAX_FOLLOW such rows, which then read "Leads to a
-- pet you don't have" and count as still to get; LeadsTo(row) words any
-- shown row's chain, Rewards(row) what a quest row's quest rewards.
--
-- A recipe row (a reagent's recipe, or what a recipe item teaches) also
-- reads what it makes as the game counts it (Facts.Buys.Product: "Pet: 1 of
-- 3 collected"), apart from the recipe's own state, and its still-need
-- filter follows the product. The running neighborhood endeavor's tasks
-- that name the item (Facts.Endeavors.UsesOf) are rows of the quests tab,
-- the logged-in character's only. LinkRow(kind, id) builds a row for a name
-- a line heard, the way the tables' rows are built, so the window's links
-- in text hover and click as rows do; Heard(fn, ...) hears the names
-- Facts.Chains' words use.
--
-- Round two (2026-09-25): every link AllTheThings gives to one achievement
-- is one row (Black Claw of Sethe links to 72 parts of one), its state how
-- many of those parts are still to do (Facts.Achievements.Parts, a
-- criterion whose ID reads 0 found by the item's name), never a need; a
-- criterion row passes the item for the same reason. A purchase keeps its
-- whole price (Costs(row), Relations.Costs; the sliced parse passes the
-- item too), and one whose data names no vendor but its place says where it
-- is ("In Blade's Edge Mountains", Seller). Name(row) says second when a
-- name is only its place, so a line doesn't name the place twice.
-------------------------------------------------------------------------------
local Data = {}
Recollect.UI.DetailData = Data

local U = CobySuite_Recollect.Utilities
local Try = Recollect.Utilities.Try
local IsPositiveID = Recollect.Utilities.IsPositiveID

local BUDGET_MS = 4      -- work per frame, all jobs together
local NAME_LOADS = 8     -- new item loads a frame
local NPC_NAMES = 4      -- new creature tooltips a frame
local SLICED_PARSE = 4000   -- an item's codes longer than this are parsed in slices
local MAX_CRAFTS = 3        -- recipes that make an item whose reagents are listed

local seams = {
  Clock = function() return debugprofilestop() end,
  Now = function() return GetTime() end,
  ItemNameByID = function(itemID) return C_Item.GetItemNameByID(itemID) end,
  RequestItem = function(itemID) C_Item.RequestLoadItemDataByID(itemID) end,
  ItemIcon = function(itemID) return C_Item.GetItemIconByID(itemID) end,
  ItemQuality = function(itemID) return C_Item.GetItemQualityByID(itemID) end,
  ItemLink = function(itemID) return select(2, C_Item.GetItemInfo(itemID)) end,
  EquipLoc = function(itemID) return select(4, C_Item.GetItemInfoInstant(itemID)) end,
  MountInfo = function(mountID) return C_MountJournal.GetMountInfoByID(mountID) end,
  MountLink = function(spellID) return C_MountJournal.GetMountLink(spellID) end,
  PetInfo = function(speciesID) return C_PetJournal.GetPetInfoTableBySpeciesID(speciesID) end,
  AchievementInfo = function(achievementID) return GetAchievementInfo(achievementID) end,
  AchievementLink = function(achievementID) return GetAchievementLink(achievementID) end,
  SpellIcon = function(spellID) return C_Spell.GetSpellTexture(spellID) end,
  SpellLink = function(spellID) return C_Spell.GetSpellLink(spellID) end,
  IllusionInfo = function(illusionID) return C_TransmogCollection.GetIllusionInfo(illusionID) end,
  IllusionStrings = function(illusionID) return C_TransmogCollection.GetIllusionStrings(illusionID) end,
  SetSources = function(setID) return C_TransmogSets.GetAllSourceIDs(setID) end,
  SourceItem = function(sourceID)
    local info = C_TransmogCollection.GetSourceInfo(sourceID)
    return info and info.itemID
  end,
  CurrencyLink = function(currencyID) return C_CurrencyInfo.GetCurrencyLink(currencyID) end,
  ToyLink = function(itemID) return C_ToyBox.GetToyLink(itemID) end,
  HeirloomLink = function(itemID) return C_Heirloom.GetHeirloomLink(itemID) end,
  QuestLink = function(questID) return GetQuestLink(questID) end,
  Schematic = function(spellID) return C_TradeSkillUI.GetRecipeSchematic(spellID, false) end,
  -- An endeavor task's chat link (NeighborhoodInitiativeDocumentation)
  TaskLink = function(taskID) return C_NeighborhoodInitiative.GetInitiativeTaskChatLink(taskID) end,
  -- A quality's color (r, g, b), as UI.UsedFor reads it
  QualityColor = function(quality) return C_Item.GetItemQualityColor(quality) end,
}

local function Parts() return Recollect.UI.UsedFor.parts end
local function Relations() return Recollect.Facts.Relations end
local function Vendors() return Recollect.Facts.Vendors end
local function Colors() return Recollect.UI.VerdictColors end
local function V() return Recollect.Purposes.Registry.Verdict end

-- The tabs, in order; Overview is the window's own (no rows)
Data.TABS = {
  { key = "overview", label = "Overview" },
  { key = "buys", label = "Buys" },
  { key = "quests", label = "Quests & achievements" },
  { key = "crafting", label = "Crafting" },
  { key = "sources", label = "Comes from" },
  { key = "takes", label = "What it takes" },
  { key = "gone", label = "No longer available" },
}

-- Things whose own ID is an item ID (an icon, a name and a link by item)
local ITEM_WHAT = { item = true, toy = true, heirloom = true, decor = true }

-------------------------------------------------------------------------------
-- The job runner: jobs by priority, BUDGET_MS of work a frame between them
-- all. A job that stops before the deadline is waiting on the game (its
-- loads for the frame are spent) and hands the rest of the frame on, so the
-- background name pass never holds up a sort the player asked for.
-------------------------------------------------------------------------------
local jobs = {}   -- { key, step(deadline) -> done, onDone, priority }
local runner = CreateFrame("Frame")
runner:Hide()

local function Finish(i, job)
  table.remove(jobs, i)
  if job.onDone then
    local ok, err = pcall(job.onDone)
    if not ok then Recollect.Debug.Warn("UI", "Detail job %s ended badly: %s", tostring(job.key), tostring(err)) end
  end
end

local function RunFrame()
  local deadline = seams.Clock() + BUDGET_MS
  local i = 1
  while jobs[i] and seams.Clock() < deadline do
    local job = jobs[i]
    local ok, done = pcall(job.step, deadline)
    if not ok then
      Recollect.Debug.Warn("UI", "Detail job %s failed: %s", tostring(job.key), tostring(done))
      done = true
    end
    if done then
      Finish(i, job)
    else
      i = i + 1   -- out of time (the loop ends) or waiting: the next job's turn
    end
  end
  if not jobs[1] then runner:Hide() end
end
runner:SetScript("OnUpdate", RunFrame)

-- Start(key, step, onDone, priority): a job; one of the same key already
-- queued is dropped. Lower priorities run first (default 1; the background
-- name pass is 9).
function Data.Start(key, step, onDone, priority)
  Data.Cancel(key)
  priority = priority or 1
  local at = #jobs + 1
  for i, job in ipairs(jobs) do
    if job.priority > priority then
      at = i
      break
    end
  end
  table.insert(jobs, at, { key = key, step = step, onDone = onDone, priority = priority })
  runner:Show()
end

function Data.Cancel(key)
  for i = #jobs, 1, -1 do
    if jobs[i].key == key then table.remove(jobs, i) end
  end
end

function Data.Running(key)
  for _, job in ipairs(jobs) do
    if job.key == key then return true end
  end
  return false
end

-------------------------------------------------------------------------------
-- Rows from relations
-------------------------------------------------------------------------------
local QUEST_LABEL = { objective = "Objective", questItem = "Used in", starts = "Starts", reward = "Reward",
  choice = "Choice reward" }
local SOURCE_TAB = { reward = true, choice = true, madeFrom = true, taughtBy = true, soldBy = true, dropsFrom = true,
  foundIn = true }

local MAKERS = {}

MAKERS.buys = function(relation, job)
  -- tradeMap: where the trade is when the data names no vendor (item 9)
  if relation.thing == "a" then
    return { tab = "quests", what = "achievement", kindLabel = "Achievement", id = relation.id,
      achievementID = relation.id, count = relation.count, needs = relation.count, tradeMap = relation.mapID }
  end
  local thing = Recollect.Facts.Buys.Resolve(relation, job.owner)
  if not thing then return nil end
  if job.seen[thing.key] then return nil end   -- the journal's own entry for it stands
  -- a plain item: the first few are followed to what they lead to (rule 39)
  local follow = false
  if not thing.collectible and (job.followed or 0) < Parts().MAX_FOLLOW then
    job.followed = (job.followed or 0) + 1
    follow = true
  end
  -- an ensemble, illusion, pet or recipe shows the item that stands for it (its icon, tooltip and link)
  return { tab = "buys", what = thing.what, kindLabel = Parts().WHAT_LABEL[thing.what] or "Item", id = thing.id,
    itemID = ITEM_WHAT[thing.what] and thing.id or Relations().ThingItem(relation.thing, relation.id),
    spellID = relation.thing == "m" and relation.id or nil,
    mountID = thing.key:find("^mount:") and thing.id or nil,
    count = relation.count or 1, plus = relation.plus, npcs = relation.vendors, thing = thing, key = thing.key,
    follow = follow, tradeMap = relation.mapID }
end

MAKERS.achievementReward = function(relation)
  return { tab = "sources", what = "achievement", kindLabel = "Achievement", id = relation.id, achievementID = relation.id }
end

MAKERS.buysDecor = function(relation)
  return { tab = "buys", what = "decor", kindLabel = "Decor", id = relation.id, itemID = relation.id, count = relation.count or 1 }
end

for kind, label in pairs(QUEST_LABEL) do
  MAKERS[kind] = function(relation)
    return { tab = SOURCE_TAB[kind] and "sources" or "quests", what = "quest", kindLabel = label, id = relation.id,
      questID = relation.id, count = relation.count }
  end
end

MAKERS.criterion = function(relation)
  return { tab = "quests", what = "achievement", kindLabel = "Achievement", id = relation.id, achievementID = relation.id,
    criteria = relation.criteria, count = relation.count }
end

-- Every link of one achievement is one row (Black Claw of Sethe links to 72
-- parts of Advanced Husbandry): AddRelation adds the rest's criteria to it
MAKERS.linked = function(relation)
  return { tab = "quests", what = "achievement", kindLabel = "Linked", id = relation.id, achievementID = relation.id,
    criteria = relation.criteria, criteriaList = { relation.criteria }, linked = true }
end

MAKERS.opens = function(relation)
  local object = Vendors().Object(relation.id)
  return { tab = "quests", what = "object", kindLabel = object and #object.contents > 0 and "Treasure" or "Spot",
    id = relation.id, objectID = relation.id, count = relation.count, contents = object and object.contents or nil }
end

MAKERS.usedAt = function(relation)
  return { tab = "quests", what = "npc", kindLabel = "Used at", id = relation.id, npcID = relation.id, count = relation.count }
end

MAKERS.currency = function(relation)
  return { tab = "quests", what = "currency", kindLabel = "Currency", id = relation.id, currencyID = relation.id }
end

MAKERS.teaches = function(relation)
  return { tab = "crafting", what = "recipe", kindLabel = "Teaches", id = relation.id, spellID = relation.id }
end

MAKERS.makes = function(relation)
  return { tab = "crafting", what = "item", kindLabel = "Makes", id = relation.id, itemID = relation.id,
    count = relation.count, unresolved = relation.unresolved }
end

MAKERS.partOf = function(relation)
  return { tab = "crafting", what = "item", kindLabel = "Combines into", id = relation.id, itemID = relation.id,
    parts = relation.parts }
end

MAKERS.reagentOf = function(relation)
  local recipe = Relations().Recipe(relation.id)
  return { tab = "crafting", what = "recipe", kindLabel = "Reagent", id = relation.id, spellID = relation.id,
    count = relation.count, skillLine = recipe and recipe.skillLine or 0, product = recipe and recipe.product or nil }
end

MAKERS.recipeFor = function(relation)
  return { tab = "crafting", what = "item", kindLabel = "Teaches how to make", id = relation.id, itemID = relation.id }
end

MAKERS.madeFrom = function(relation)
  return { tab = "sources", what = "item", kindLabel = "Made from", id = relation.id, itemID = relation.id, count = relation.count }
end

MAKERS.taughtBy = function(relation)
  return { tab = "sources", what = "item", kindLabel = "Crafted with", id = relation.id, itemID = relation.id }
end

MAKERS.soldBy = function(relation)
  return { tab = "sources", what = "npc", kindLabel = "Sold by", id = relation.id, npcID = relation.id }
end

MAKERS.dropsFrom = function(relation)
  return { tab = "sources", what = "npc", kindLabel = "Drops from", id = relation.id, npcID = relation.id }
end

MAKERS.foundIn = function(relation)
  return { tab = "sources", what = "object", kindLabel = "Found at", id = relation.id, objectID = relation.id }
end

MAKERS.zoneDrop = function(relation)
  return { tab = "sources", what = "zone", kindLabel = relation.id == 0 and "World drop" or "Zone drop", id = relation.id,
    mapID = relation.id }
end

-- Sources of data format 4: a boss in the Encounter Journal (a click opens
-- the journal at it), a renown reward (the faction, and whether the owner's
-- renown reached the level), the Black Market and the Trading Post (its month)
MAKERS.journalDrop = function(relation)
  return { tab = "sources", what = "encounter", kindLabel = "Boss loot", id = relation.id, encounterID = relation.id }
end

MAKERS.renownReward = function(relation)
  return { tab = "sources", what = "faction", kindLabel = "Renown", id = relation.id, factionID = relation.id,
    level = relation.level or 0 }
end

MAKERS.blackMarket = function(relation)
  return { tab = "sources", what = "blackMarket", kindLabel = "Black Market", id = relation.id,
    name = "Black Market Auction House" }
end

MAKERS.tradingPost = function(relation)
  local month = Parts().MonthWords(relation.id)
  return { tab = "sources", what = "tradingPost", kindLabel = "Trading Post", id = relation.id, month = relation.id,
    name = month and ("Trading Post (%s)"):format(month) or "Trading Post" }
end

MAKERS.craftedBy = function(relation)
  local recipe = Relations().Recipe(relation.id)
  return { tab = "sources", what = "recipe", kindLabel = "Crafted by", id = relation.id, spellID = relation.id,
    skillLine = recipe and recipe.skillLine or 0 }
end

local function Push(job, row)
  local list = job.tabs[row.tab]
  list[#list + 1] = row
end

-- One relation as a row (or none), resolved for the job's owner. The links
-- of one achievement that serve alike are one row, resolved once they are
-- all in (AddExtras)
local function AddRelation(job, relation)
  local maker = MAKERS[relation.kind]
  if not maker then return end
  local applies
  if Parts().QUEST_KIND[relation.kind] then
    applies = job.questApplies[relation.id]
  else
    applies = Relations().Applies(relation, job.owner)
  end
  local group = relation.kind == "linked" and (tostring(relation.id) .. ":" .. tostring(applies)) or nil
  local kept = group and job.linked and job.linked[group]
  if kept then
    kept.criteriaList[#kept.criteriaList + 1] = relation.criteria
    return
  end
  local row = maker(relation, job)
  if not row then return end
  row.kind, row.relation, row.of = relation.kind, relation, job.itemID
  -- the route's tags (D19, display only): who it serves, whether it's gone,
  -- and an event's for every character
  if applies ~= true or (relation.flags and relation.flags.event) or relation.shows then
    local tags = Parts().Tags(relation, applies, job.owner)
    if #tags > 0 then row.tags = tags end
    if applies == true and Parts().AnyShown(tags) then row.dimmed = true end
  end
  if applies == "unavailable" then
    row.gone, row.tab = true, "gone"
  elseif applies ~= true then
    row.restricted = true
    -- nil or "unknown": the owner's record can't answer the condition (a
    -- stored alt with no race recorded), which is not for someone else
    if applies == nil or applies == "unknown" then row.untold = true end
  end
  if group then
    job.linked = job.linked or {}
    job.linked[group] = row
  else
    Data.Resolve(row, job.owner, job.budget)
  end
  Push(job, row)
end

-- The journals' mounts and pets it buys: first, so ATT's route for the same
-- thing is left out (as the panel does)
local function AddJournal(job)
  local index = Recollect.Facts.Journals.Get()
  for _, target in ipairs((index and index[job.itemID]) or {}) do
    local key = target.kind .. ":" .. target.id
    job.seen[key] = true
    local row = { tab = "buys", kind = "journal", what = target.kind, kindLabel = Parts().WHAT_LABEL[target.kind],
      id = target.id, count = target.count or 1, target = target, key = key, of = job.itemID,
      mountID = target.kind == "mount" and target.id or nil,
      itemID = target.kind == "pet" and Relations().ThingItem("p", target.id) or nil }
    Data.Resolve(row, job.owner, job.budget)
    Push(job, row)
  end
end

-- Rows that aren't relations: the recipe index, other characters' scans,
-- vendors the Lab saw take or sell it, and what a use takes
local function AddExtras(job)
  local itemID, owner = job.itemID, job.owner
  for _, row in pairs(job.linked or {}) do Data.Resolve(row, owner, job.budget) end
  if owner.isViewer then
    local ok, index = pcall(Recollect.Facts.Recipes.ForCharacter)
    for name, n in pairs(ok and index and index.uses and index.uses[itemID] or {}) do
      Push(job, { tab = "crafting", kind = "index", what = "index", kindLabel = "Your recipes", name = name, count = n,
        stateText = "Scanned", filterState = "have", tier = Parts().TIER_INFO, of = itemID })
    end
  end
  -- The running neighborhood endeavor's tasks that name it (the logged-in
  -- character's own endeavor, as the panel reads it)
  if owner.isViewer then
    for _, use in ipairs(Data.EndeavorUses(itemID)) do
      local row = { tab = "quests", kind = "endeavor", what = "endeavor", kindLabel = "Endeavor", id = use.taskID,
        taskID = use.taskID, name = tostring(use.taskName), use = use, of = itemID }
      Data.Resolve(row, owner, job.budget)
      Push(job, row)
    end
  end
  local ok, recorded = pcall(Recollect.Facts.Recipes.RecordedByOthers, itemID)
  for _, r in ipairs(ok and recorded or {}) do
    Push(job, { tab = "crafting", kind = "recorded", what = "index", kindLabel = "Alt's scan",
      name = ("%s's %s"):format(r.name, r.profession), count = r.count,
      stateText = r.scannedAt and ("Recorded " .. date("%b %d", r.scannedAt)) or "Recorded", filterState = "none",
      tier = Parts().TIER_INFO })
  end
  for _, vendor in ipairs(Vendors().ForCostItem(itemID)) do
    Push(job, { tab = "quests", kind = "payment", what = "npc", kindLabel = "Takes it as payment", id = vendor.npcID,
      npcID = vendor.npcID, filterState = "none", tier = Parts().TIER_INFO })
  end
  for _, vendor in ipairs(Vendors().Selling(itemID)) do
    Push(job, { tab = "sources", kind = "sold", what = "npc", kindLabel = "Sold by", id = vendor.npcID,
      npcID = vendor.npcID, filterState = "none", tier = Parts().TIER_INFO })
  end
  -- What crafting it takes: every required reagent of the recipes that make
  -- it, from the game's own schematic (read live, as the Lab's dump reads it)
  local crafts = 0
  for _, relation in ipairs(job.relations) do
    if relation.kind == "craftedBy" and crafts < MAX_CRAFTS and Relations().Applies(relation, owner) == true then
      crafts = crafts + 1
      local ok, schematic = Try(seams.Schematic, relation.id)
      -- a slot is filled by any of its items (its qualities or choices), counted together (PI-05)
      for _, slot in ipairs(ok and type(schematic) == "table" and schematic.reagentSlotSchematics or {}) do
        local need = tonumber(slot.quantityRequired)
        local items = {}
        for _, reagent in ipairs(slot.required == true and type(slot.reagents) == "table" and slot.reagents or {}) do
          if type(reagent) == "table" and IsPositiveID(reagent.itemID) then items[#items + 1] = reagent.itemID end
        end
        if #items > 0 and need and need > 0 then
          local row = { tab = "takes", kind = "part", what = "item", kindLabel = "To craft", id = items[1],
            itemID = items[1], part = Recollect.Facts.Requirements.Part(items, need),
            record = { kind = "craft", spellID = relation.id } }
          Data.Resolve(row, owner, job.budget)
          Push(job, row)
        end
      end
    end
  end
  local okR, records = pcall(Recollect.Facts.Requirements.For, itemID, owner, job.relations)
  for _, record in ipairs(okR and records or {}) do
    for _, part in ipairs(record.parts) do
      local row = { tab = "takes", kind = "part", what = "item", kindLabel = record.kind == "combine" and "Combine" or "Use",
        id = part.itemID, itemID = part.itemID, part = part, record = record }
      Data.Resolve(row, owner, job.budget)
      Push(job, row)
    end
  end
end

-- Parses an item's codes from pos until the deadline (Relations.Parse per
-- code, so a big item's parse is sliced too); the next position, or nil
-- when every code is read. The item is passed on, so a purchase has its
-- costs (Relations.Costs) as For's parse gives them
local function ParseSome(codes, pos, into, deadline, itemID)
  while pos <= #codes do
    local stop = codes:find(";", pos, true) or (#codes + 1)
    local relation = Relations().Parse(codes:sub(pos, stop - 1), itemID)
    if relation then into[#into + 1] = relation end
    pos = stop + 1
    if seams.Clock() >= deadline then return pos end
  end
  return nil
end

-- Build(itemID, stack, owner, onProgress): the job that fills job.tabs;
-- onProgress(job) after each slice and when done. The item's codes are
-- parsed in the same slices (a session's parse, Relations.Parsed, is reused),
-- then each becomes a row.
function Data.Build(itemID, stack, owner, onProgress)
  owner = owner or Recollect.Verdicts.Rows.Owner()
  local job = { itemID = itemID, owner = owner, tabs = {}, seen = {}, done = 0, total = 0,
    finished = false }
  for _, tab in ipairs(Data.TABS) do job.tabs[tab.key] = {} end
  local relations = Relations().Parsed(itemID)
  local codes, pos = "", nil
  if not relations then
    codes = Relations().Codes(itemID) or ""
    if #codes < SLICED_PARSE then
      relations, codes = Relations().For(itemID), ""
    else
      relations, pos = {}, 1
    end
  end
  job.relations = relations
  local _, separators = codes:gsub(";", ";")
  local toParse = codes ~= "" and separators + 1 or 0
  job.total = toParse + (pos and toParse or #relations)
  local i, phase = 0, 0
  Data.Start("build", function(deadline)
    job.budget = Recollect.Facts.QuestInfo.FrameBudget()
    if phase == 0 then
      AddJournal(job)
      phase = pos and 1 or 2
    end
    if phase == 1 then
      pos = ParseSome(codes, pos, relations, deadline, itemID)
      job.done = #relations
      if pos then
        if onProgress then onProgress(job) end
        return false
      end
      job.total = #relations * 2
      phase = 2
    end
    if not job.questApplies then job.questApplies = Relations().QuestAppliesOf(relations, owner) end
    local offset = job.total - #relations
    while i < #relations do
      i = i + 1
      AddRelation(job, relations[i])
      job.done = offset + i
      if seams.Clock() >= deadline then
        if onProgress then onProgress(job) end
        return false
      end
    end
    AddExtras(job)
    job.done, job.finished = job.total, true
    return true
  end, function()
    if onProgress then onProgress(job) end
  end)
  return job
end

-- Refresh(job, onDone): every row's state read again, sliced (data arrived)
function Data.Refresh(job, onDone)
  local order, t, i = {}, 1, 0
  for _, tab in ipairs(Data.TABS) do order[#order + 1] = job.tabs[tab.key] end
  Data.Start("refresh", function(deadline)
    job.budget = Recollect.Facts.QuestInfo.FrameBudget()
    while order[t] do
      local list = order[t]
      i = i + 1
      if i > #list then
        t, i = t + 1, 0
      else
        Data.Resolve(list[i], job.owner, job.budget)
        if seams.Clock() >= deadline then return false end
      end
    end
    return true
  end, onDone)
end

-------------------------------------------------------------------------------
-- States
-------------------------------------------------------------------------------
local function Set(row, state, text, color, filterState)
  local parts = Parts()
  row.state, row.stateText, row.stateColor, row.filterState = state, text, color, filterState or "none"
  row.tier = (filterState == "missing" and parts.TIER_OPEN) or ((filterState == "have" or filterState == "other") and parts.TIER_CLOSED)
    or parts.TIER_INFO
end

-- A collectible's state words ("not owned"), as the panel says them
local function StateWords(what, state)
  local words = Parts().STATE_WORDS[what] and Parts().STATE_WORDS[what][state]
  if words then return (words:gsub("^%l", string.upper)) end
  if state == "unassessed" then return "Known per character" end
  if state == "unread" then return "Can't be read yet" end
  return nil
end

local function CollectibleColor(state)
  local colors = Colors()
  if state == "missing" then return colors[V().USEFUL] end
  if state == "have" or state == "unavailable" then return colors[V().DONE] end
  return U.Colors.LABEL_GRAY
end

local FILTER_OF = { missing = "missing", have = "have", unavailable = "other" }

-- A plain item's state: how many you have, and for gear its look
local function PlainItem(row, owner)
  if not owner.isViewer then return Set(row, nil, nil, U.Colors.LABEL_GRAY, "none") end
  local okLoc, equipLoc = Try(seams.EquipLoc, row.id)
  if okLoc and type(equipLoc) == "string" and Recollect.Purposes.Gear.SLOTS[equipLoc] and Recollect.Facts.Ready.Transmog() then
    local look = Recollect.Purposes.Gear.Appearance(Recollect.Purposes.client,
      { facts = { equipLoc = equipLoc }, stack = { itemID = row.id } })
    if look == "collected" or look == "other" then
      return Set(row, "have", look == "other" and "Look collected (other item)" or "Look collected", Colors()[V().DONE], "have")
    elseif look == "missing" then
      return Set(row, "missing", "Look not collected", Colors()[V().USEFUL], "missing")
    end
  end
  local held = Parts().Owned(row.id)
  if held and held > 0 then return Set(row, "held", ("You have %d"):format(held), U.Colors.LIGHT_GRAY, "have") end
  Set(row, nil, held == 0 and "You have none" or nil, U.Colors.LABEL_GRAY, "none")
end

local RESOLVE = {}

-- A followed plain purchase that leads to a collectible still missing
local KIND_NAME = { toy = "toy", mount = "mount", pet = "pet", decor = "decor item", ensemble = "ensemble",
  heirloom = "heirloom", recipe = "recipe", illusion = "illusion", achievement = "achievement" }

local function Chain(row, owner, budget)
  local summary = Recollect.Facts.Chains.Summary(row.id, owner, budget, row.of)
  row.chain, row.chainStamp = summary or false, Recollect.Facts.Buys.Stamp()
  return summary
end

RESOLVE.buys = function(row, owner, budget)
  local thing = Recollect.Facts.Buys.Resolve(row.relation, owner) or row.thing
  row.thing = thing
  if thing.name then row.name = thing.name end
  if not thing.collectible then
    PlainItem(row, owner)
    if row.follow and not row.restricted then
      local summary = Chain(row, owner, budget)
      local best = summary and summary.best
      if best and best.state == "open" then
        local kind = best.thing and KIND_NAME[best.thing.what] or "collectible"
        Set(row, "missing", ("Leads to a%s %s you lack"):format(kind:find("^[aeiou]") and "n" or "", kind),
          Colors()[V().USEFUL], "missing")
      end
    end
    return
  end
  local state = thing.state
  if state == "unread" and thing.failed then
    return Set(row, "failed", "Can't be read", U.Colors.LABEL_GRAY, "none")
  end
  -- A cost that counts toward an achievement: the words of the panel's
  -- AchievementLine and the criterion rows (earned; not earned, with how
  -- many it needs)
  if thing.what == "achievement" and (state == "have" or state == "missing") then
    if state == "have" then return Set(row, "have", "Earned", Colors()[V().DONE], "have") end
    local needs = row.needs
    return Set(row, "missing", type(needs) == "number" and needs > 1 and ("Needs %d; not earned"):format(needs) or "Not earned",
      Colors()[V().NEEDED], "missing")
  end
  Set(row, state, StateWords(thing.what, state), CollectibleColor(state), FILTER_OF[state] or "none")
end

RESOLVE.journal = function(row, owner)
  local state, name = Recollect.Purposes.Registry.CollectibleState(row.target, owner.faction, owner.isViewer)
  if name then row.name = name end
  Set(row, state, StateWords(row.what, state) or (state == nil and "Can't be read yet" or nil), CollectibleColor(state),
    FILTER_OF[state] or "none")
end

RESOLVE.buysDecor = function(row)
  local owned, info = Recollect.Purposes.Registry.DecorOwned(row.id)
  if info and info.sourceText and not row.sellerText then
    row.sellerText = Parts().SourceSellers(info.sourceText, row.of)
  end
  if owned == nil then return Set(row, nil, "Can't be read yet", U.Colors.LABEL_GRAY, "none") end
  local state = owned > 0 and "have" or "missing"
  Set(row, state, StateWords("decor", state), CollectibleColor(state), state)
end

local function QuestRow(row, owner, budget)
  local title, rank, words, color = Parts().QuestState(row.questID, budget, not owner.isViewer)
  if not title then return Set(row, "loading", "Checking", U.Colors.LABEL_GRAY, "none") end
  row.name = title:gsub('^"(.*)"$', "%1")
  local filter = (rank == 5 or rank == 3 or rank == 2) and "missing" or (rank == 4 and "have") or "none"
  Set(row, "quest", words and (words:gsub("^%l", string.upper)) or nil, color, filter)
end
for kind in pairs(QUEST_LABEL) do RESOLVE[kind] = QuestRow end

-- A criterion's achievement: found by its ID, or, where the game reads the
-- ID as 0, by the item's name (Facts.Achievements.Get's third argument)
local function AchievementRow(row)
  local a = Recollect.Facts.Achievements.Get(row.achievementID, row.criteria, row.of)
  if not a then return Set(row, nil, "Can't be read", U.Colors.LABEL_GRAY, "none") end
  row.name = a.name
  local colors = Colors()
  if a.earned then return Set(row, "have", "Earned", colors[V().DONE], "have") end
  if a.criterionDone then return Set(row, "have", "That part done", colors[V().DONE], "have") end
  if type(a.required) == "number" and a.required > 1 and type(a.quantity) == "number" then
    row.bar = { done = a.quantity, total = a.required }   -- the Overview's progress bar
    return Set(row, "missing", ("%d of %d"):format(a.quantity, a.required), colors[V().NEEDED], "missing")
  end
  Set(row, "missing", "Not earned", colors[V().NEEDED], "missing")
end
RESOLVE.criterion = AchievementRow

-- The achievement AllTheThings links the item to (item 4, as the panel's
-- "Linked to" line reads it): earned, or how many of the parts it links the
-- item to are still to do (Facts.Achievements.Parts, the criteria read once,
-- a criterion whose ID reads 0 matched by the item's name). Never a need:
-- a part to do is Useful, as the linked check says. Another character's
-- copy shows a progress only for an account-wide achievement.
RESOLVE.linked = function(row, owner)
  local A = Recollect.Facts.Achievements
  local progress = A.Progress(row.achievementID)
  if not progress then return Set(row, nil, "Can't be read", U.Colors.LABEL_GRAY, "none") end
  row.name = progress.name
  local colors = Colors()
  if not owner.isViewer and progress.accountWide ~= true then return Set(row, nil, nil, U.Colors.LIGHT_GRAY, "none") end
  local words = A.ProgressWords(progress)
  if progress.earned then return Set(row, "have", (words:gsub("^%l", string.upper)), colors[V().DONE], "have") end
  local parts = A.Parts(row.achievementID, row.criteriaList or { row.criteria }, row.of)
  -- A part that failed to read, or wasn't found, is never done (review F14)
  local state = A.PartsState(parts)
  if state == nil then
    return Set(row, nil, (words:gsub("^%l", string.upper)), U.Colors.LIGHT_GRAY, "none")
  end
  local open, many = parts.found - parts.done, parts.found > 1
  if many then row.bar = { done = parts.done, total = parts.found } end
  if state == "open" then
    return Set(row, "missing", many and ("%d of %d linked parts to do"):format(open, parts.found) or "Linked part to do",
      colors[V().USEFUL], "missing")
  end
  Set(row, "have", many and "Linked parts done" or "Linked part done", colors[V().DONE], "have")
end

-- An achievement that rewards the item: its progress (Facts.Achievements)
RESOLVE.achievementReward = function(row)
  local A = Recollect.Facts.Achievements
  local progress = A.Progress(row.achievementID)
  if not progress then return Set(row, nil, "Can't be read", U.Colors.LABEL_GRAY, "none") end
  row.name = progress.name
  local words, open = A.ProgressWords(progress)
  words = words:gsub("^%l", string.upper)
  if type(progress.done) == "number" and type(progress.total) == "number" and progress.total > 1 then
    row.bar = { done = progress.done, total = progress.total }
  end
  if open then return Set(row, "missing", words, Colors()[V().USEFUL], "missing") end
  Set(row, "have", words, Colors()[V().DONE], "have")
end

-- A renown reward: whether the owner's renown reached its level, read only
-- on the logged-in character's copy (UsedFor.parts.Renown, as the panel's
-- line reads it); the faction's name, and its icon when the game gives one
RESOLVE.renownReward = function(row, owner)
  local state, name, now, data = Parts().Renown(row.factionID, row.level, owner.isViewer)
  row.name = name
  local kit = data and data.textureKit
  if not row.icon and type(kit) == "string" and kit ~= "" and not Recollect.Utilities.IsSecret(kit) then
    row.icon, row.iconAtlas = ("majorfactions_icons_%s512"):format(kit), true
  end
  local colors = Colors()
  if state == "reached" then return Set(row, "have", "Reached", colors[V().DONE], "have") end
  if state == "short" then return Set(row, "missing", ("You're at %d"):format(now), colors[V().USEFUL], "missing") end
  if state == "unread" then return Set(row, nil, "Can't be read", U.Colors.LABEL_GRAY, "none") end
  Set(row, nil, nil, U.Colors.LIGHT_GRAY, "none")
end

RESOLVE.opens = function(row, owner)
  local object = Vendors().Object(row.objectID)
  if not (object and object.questID) or not owner.isViewer or not Recollect.Facts.Ready.Quests() then
    return Set(row, nil, nil, U.Colors.LIGHT_GRAY, "none")
  end
  local ok, done = Try(Recollect.Purposes.client.IsQuestFlaggedCompleted, object.questID)
  local treasure = #object.contents > 0
  if ok and done == true then return Set(row, "have", treasure and "Looted" or "Done", Colors()[V().DONE], "have") end
  if ok and done == false then return Set(row, "missing", treasure and "Not looted" or "Not done", Colors()[V().USEFUL], "missing") end
  Set(row, nil, nil, U.Colors.LABEL_GRAY, "none")
end

RESOLVE.currency = function(row, owner)
  local parts = Parts()
  local factionID = parts.GrantedFaction(row.currencyID)
  if factionID then
    row.name = row.name or parts.FactionName(factionID)
    return Set(row, nil, "Reputation", U.Colors.LIGHT_GRAY, "none")
  end
  local info = parts.Currency(row.currencyID)
  if not info then return Set(row, nil, "Can't be read", U.Colors.LABEL_GRAY, "none") end
  row.name = info.name
  row.icon = row.icon or info.iconFileID
  local quantity = owner.isViewer and CobySuite_Recollect.Utilities.IsFiniteNumber(info.quantity) and info.quantity or nil
  Set(row, "held", quantity and ("You hold %d"):format(quantity) or nil, Colors()[V().USEFUL], "none")
end

-- A recipe's own state for the logged-in character; a recipe of a system
-- whose "not known" was never measured (Facts.Buys.RecipeKnown "unverified":
-- Protoform Synthesis and the like) can't be read for it
local function RecipeRow(row, owner)
  if not owner.isViewer then return Set(row, "unassessed", "Known per character", U.Colors.LABEL_GRAY, "none") end
  local known, why = Recollect.Facts.Buys.RecipeKnown(row.spellID)
  if known == true then return Set(row, "have", "Known", Colors()[V().DONE], "have") end
  if known == false then return Set(row, "missing", "Not known", Colors()[V().USEFUL], "missing") end
  local system = why == "unverified" and Data.Profession(row)
  Set(row, nil, system and ("Can't be read for " .. system) or "Can't be read", U.Colors.LABEL_GRAY, "none")
end
RESOLVE.craftedBy = RecipeRow

-- What a recipe makes, as the game counts it (Facts.Buys.Product): "Pet: 1
-- of 3 collected", "Toy: not collected"; its own words and color, apart
-- from the recipe's state. The row's still-need filter follows the product
-- (Cobanyte, 2026-09-25: Genesis Mote's recipes read "Not known" while
-- Archetype of Discovery says Collected (1/3)).
local PRODUCT_KIND = { toy = "Toy", mount = "Mount", pet = "Pet", ensemble = "Ensemble", illusion = "Illusion",
  heirloom = "Heirloom", decor = "Decor", recipe = "Recipe", achievement = "Achievement", appearance = "Appearance" }
local PRODUCT_WORDS = {
  recipe = { have = "known", missing = "not known" },
  achievement = { have = "earned", missing = "not earned" },
  appearance = { unavailable = "this character can't collect it" },
  mount = { unavailable = "not for this character" },
}

function Data.ProductWords(thing)
  local kind = PRODUCT_KIND[thing.what]
  if not kind or (thing.state == "unread" and thing.failed) then return kind and (kind .. ": can't be read") or "Can't be read" end
  local state = thing.state
  if state == "unread" then return kind .. ": can't be read yet" end
  if state == "unassessed" then return kind .. ": known per character" end
  if thing.what == "pet" and IsPositiveID(thing.limit) and type(thing.collected) == "number" then
    return ("Pet: %d of %d collected"):format(thing.collected, thing.limit)
  end
  if thing.what == "decor" and type(thing.owned) == "number" then
    return thing.owned > 0 and ("Decor: %d owned"):format(thing.owned) or "Decor: none owned"
  end
  if thing.what == "appearance" and state == "have" and thing.otherItem then return "Appearance: collected from another item" end
  local words = PRODUCT_WORDS[thing.what] and PRODUCT_WORDS[thing.what][state]
    or (state == "have" and "collected") or (state == "missing" and "not collected") or "can't be read"
  return kind .. ": " .. words
end

-- The product's state on the row (read again while its item loads); nil
-- when the recipe makes nothing collectible
function Data.Product(row, owner)
  local productID = row.product
  if row.kind == "teaches" and productID == nil then
    local recipe = Relations().Recipe(row.spellID)
    productID = recipe and IsPositiveID(recipe.product) and recipe.product or false
    row.product = productID
  end
  if not IsPositiveID(productID) then return nil end
  if row.productThing ~= nil and not row.productLoading and row.productStamp == Recollect.Facts.Buys.Stamp() then
    return row.productThing or nil
  end
  owner = owner or row.productOwner or Recollect.Verdicts.Rows.Owner()
  row.productOwner = owner
  local thing, why = Recollect.Facts.Buys.Product(productID, owner)
  row.productLoading = why == "loading"
  if row.productLoading then Data.ItemName(productID) end   -- loads it; the column asks again when shown
  row.productThing, row.productStamp = thing or false, Recollect.Facts.Buys.Stamp()
  if not thing then
    row.productText, row.productColor = row.productLoading and "Loading" or nil, U.Colors.LABEL_GRAY
    return nil
  end
  row.productText = Data.ProductWords(thing)
  local color = U.Colors.LABEL_GRAY
  if not (thing.state == "unread" or thing.state == "unassessed") then
    color = thing.state == "missing" and Colors()[V().USEFUL] or Colors()[V().DONE]
  end
  row.productColor = color
  -- the still-need filter and the order follow what the recipe makes; a
  -- product whose state can't be read yet has none
  local filter = FILTER_OF[thing.state] or "none"
  local parts = Parts()
  row.filterState = filter
  row.tier = (filter == "missing" and parts.TIER_OPEN) or (filter == "none" and parts.TIER_INFO) or parts.TIER_CLOSED
  return thing
end

-- ProductText(row): the Product cell's words, asked again while loading
function Data.ProductText(row)
  if row.productLoading or row.productThing == nil then Data.Product(row) end
  return row.productText
end

local function RecipeWithProduct(row, owner)
  RecipeRow(row, owner)
  row.productThing, row.productText, row.productLoading = nil, nil, nil
  Data.Product(row, owner)
end
RESOLVE.teaches = RecipeWithProduct
RESOLVE.reagentOf = RecipeWithProduct

local function HeldRow(row, owner)
  if row.unresolved then return Set(row, nil, "Unconfirmed", U.Colors.LABEL_GRAY, "none") end
  if not owner.isViewer then return Set(row, nil, nil, U.Colors.LIGHT_GRAY, "none") end
  local held = Parts().Owned(row.itemID)
  if held == nil then return Set(row, nil, "Can't be read", U.Colors.LABEL_GRAY, "none") end
  Set(row, "held", held > 0 and ("You have %d"):format(held) or "You have none", U.Colors.LIGHT_GRAY,
    held > 0 and "have" or "none")
end
RESOLVE.makes = HeldRow
RESOLVE.madeFrom = HeldRow

-- A combine of several parts: how many of the parts you have
RESOLVE.partOf = function(row, owner)
  if not owner.isViewer then return Set(row, nil, nil, U.Colors.LIGHT_GRAY, "none") end
  local held = 0
  for _, part in ipairs(row.parts) do
    local have = Parts().Owned(part.itemID)
    if have == nil then return Set(row, nil, "Can't be read", U.Colors.LABEL_GRAY, "none") end
    if have >= part.count then held = held + 1 end
  end
  if held == #row.parts then return Set(row, "have", "You have every part", Colors()[V().USE], "have") end
  Set(row, "missing", ("You have %d of %d parts"):format(held, #row.parts), Colors()[V().USEFUL], "missing")
end

-- A part of what a use takes: counted again at every refresh (PI-06), with
-- what to take out of the banks first (PI-07)
RESOLVE.part = function(row)
  local old = row.part
  local part = Recollect.Facts.Requirements.Part(old.alternatives or old.itemID, old.need)
  row.part = part
  if part.uncertain then return Set(row, nil, "Can't be counted", U.Colors.LABEL_GRAY, "none") end
  if part.missing > 0 then return Set(row, "missing", ("%d missing"):format(part.missing), Colors()[V().NEEDED], "missing") end
  local fromBanks = part.need - part.bags
  if fromBanks > 0 then
    local fromBank = math.min(part.bank, fromBanks)
    local where = fromBank == fromBanks and "your bank" or (fromBank == 0 and "the warband bank" or "your banks")
    return Set(row, "have", ("Take %d from %s"):format(fromBanks, where), Colors()[V().USEFUL], "have")
  end
  Set(row, "have", "In your bags", Colors()[V().USE], "have")
end

-- The recipe index's count, read again at every refresh (PI-06)
RESOLVE.index = function(row)
  local ok, index = pcall(Recollect.Facts.Recipes.ForCharacter)
  local uses = ok and index and index.uses and index.uses[row.of]
  row.count = uses and uses[row.name] or 0
end

-- The endeavor's tasks that name an item (Facts.Endeavors.UsesOf), or {}
function Data.EndeavorUses(itemID)
  local Endeavors = Recollect.Facts.Endeavors
  if not Endeavors or type(Endeavors.UsesOf) ~= "function" then return {} end
  local ok, uses = pcall(Endeavors.UsesOf, itemID)
  return ok and type(uses) == "table" and uses or {}
end

-- An endeavor task: open (its requirement line, as the game words it),
-- done, or a state that can't be read; read again at every refresh
RESOLVE.endeavor = function(row)
  local now
  for _, use in ipairs(Data.EndeavorUses(row.of)) do
    if (row.taskID ~= nil and use.taskID == row.taskID) or (row.taskID == nil and tostring(use.taskName) == row.name) then
      now = use
      break
    end
  end
  if not now then return Set(row, nil, "Not in the running endeavor", U.Colors.LABEL_GRAY, "none") end
  row.use = now
  if now.done == false then
    local words = type(now.progressText) == "string" and now.progressText ~= "" and now.progressText or "Open"
    return Set(row, "missing", words, Colors()[V().USEFUL], "missing")
  end
  if now.done == true then return Set(row, "have", "Done", Colors()[V().DONE], "have") end
  Set(row, nil, "State can't be read", U.Colors.LABEL_GRAY, "none")
end

-- An endeavor row's Where: 'Neighborhood endeavor "Candle Culture", at 340 of 1000'
local function EndeavorWhere(row)
  local use = row.use or {}
  local Endeavors = Recollect.Facts.Endeavors
  local okGet, endeavor = pcall(Endeavors.Get)
  local okWords, progress = false, nil
  if okGet and type(endeavor) == "table" then okWords, progress = pcall(Endeavors.ProgressWords, endeavor) end
  progress = okWords and type(progress) == "string" and progress or nil
  return ('Neighborhood endeavor "%s"%s'):format(tostring(use.title or "?"), progress and (", at " .. progress) or "")
end

-- LeadsTo(row): what a plain purchase leads to ("Phoenix Wishwing, a pet
-- you don't have, through ..."), read for a row on screen and kept until
-- data changes; nil when it leads nowhere the data names
-- keptOnly (the column's sort key): only a summary already built and still
-- current, never a new one, so sorting a tab of thousands of purchases builds
-- none (the rows on screen build theirs; Mark of Honor buys about 8,700)
function Data.LeadsTo(row, owner, keptOnly)
  if row.kind ~= "buys" or not row.thing or row.thing.collectible or row.restricted or row.gone then return nil end
  owner = owner or Recollect.Verdicts.Rows.Owner()
  local summary = row.chain
  if summary == nil or row.chainStamp ~= Recollect.Facts.Buys.Stamp() then
    if keptOnly then return nil end
    summary = Chain(row, owner, Recollect.Facts.QuestInfo.FrameBudget())
  end
  local best = summary and summary.best
  if not best then return nil end
  return Recollect.Facts.Chains.Words(best.entry, owner, best.thing, best.quests)
end

-- Rewards(row): what a quest row's quest rewards, with states ("Phoenix
-- Wishwing, a pet you don't have"), or nil
local REWARD_ROWS = { objective = true, questItem = true, starts = true }
function Data.Rewards(row, owner)
  if not REWARD_ROWS[row.kind] or not row.questID then return nil end
  local words = Recollect.Facts.Chains.RewardWords(row.questID, owner or Recollect.Verdicts.Rows.Owner())
  return words and words:gsub("^rewards ", "") or nil
end

-- For(row): what a part is for ("Craft Adorned Fang", "Combine into X"), or nil
function Data.For(row)
  if row.forText then return row.forText end
  local record = row.record
  if not record then return nil end
  local text, complete = nil, true
  if record.kind == "craft" then
    local name = Parts().SpellName(record.spellID)
    text, complete = name and ("Craft " .. name) or ("Recipe " .. tostring(record.spellID)), name ~= nil
  else
    text = Recollect.Facts.Requirements.Title(record, function(id)
      local name = Data.ItemName(id)
      if not name then complete = false end
      return name or ("item " .. tostring(id))
    end)
  end
  if complete then row.forText = text end
  return text
end

-- Others(row): other characters' copies of a part, as last read: "Tanklite 3"
-- or "Tanklite 3 and 2 more"; never counted
function Data.Others(row)
  local others = row.part and row.part.others
  if not others or #others == 0 then return nil end
  local text = ("%s %d"):format(others[1].name, others[1].count)
  if #others > 1 then text = ("%s and %d more"):format(text, #others - 1) end
  return text
end

-- Resolve(row, owner, budget): the row's state read now
-- A quest row's title, when its state isn't read (another faction's quest,
-- or one no longer in the game): its name only, through the same budget
local function QuestTitle(row, budget)
  if not row.questID or row.name then return end
  local quest = Recollect.Facts.QuestInfo.Get(row.questID, budget)
  if quest and quest.title then row.name = quest.title:gsub('^"(.*)"$', "%1") end
end

-- A gone, restricted or untold row's state: its tags' words (UsedFor.Tags),
-- capitalized for the Status column; stateInline keeps them as they read
-- inside a sentence ("(Blood Elf only)", never "(blood Elf only)")
local function Tagged(row, state, applies, owner, filterState)
  local parts = Parts()
  local tags = row.tags or parts.Tags(row.relation or {}, applies, owner)
  row.tags = #tags > 0 and tags or nil
  local text = parts.TagText(tags) or "Not for this character"
  Set(row, state, (text:gsub("^%l", string.upper)), U.Colors.LABEL_GRAY, filterState)
  row.stateInline = parts.TagText(tags, true)
end

-- A route that serves the owner keeps its state, with its display-only tags
-- after it (an event's, and a profession, standing or quest the owner
-- misses: "Not done, Engineering only, during a holiday or event"), said
-- once however often the row is read again
local SHOWN_KINDS = { event = true, profession = true, standing = true, quest = true, achievement = true, renown = true }
local function EventState(row)
  local tags = row.tags
  if not tags or row.restricted or row.gone then return end
  local first, words = nil, {}
  for _, tag in ipairs(tags) do
    if SHOWN_KINDS[tag.kind] and tag.after then
      first = first or tag.words
      words[#words + 1] = tag.after
    end
  end
  if #words == 0 then return end
  local after = table.concat(words, ", ")
  local text = row.stateText
  if text and (text == first or text:sub(-#after) == after) then return end
  row.stateText = text and ("%s, %s"):format(text, after) or (first .. (#words > 1 and (", " .. table.concat(words, ", ", 2)) or ""))
end

function Data.Resolve(row, owner, budget)
  if row.gone or row.restricted then QuestTitle(row, budget) end
  row.stateInline = nil
  row.bar = nil   -- set again only by a read that still has progress to show
  if row.gone then return Tagged(row, "gone", "unavailable", owner, "other") end
  if row.untold then return Tagged(row, "untold", nil, owner, "none") end
  if row.restricted then return Tagged(row, "other", "other", owner, "other") end
  -- what a route requires, read live again at every refresh (an
  -- achievement's progress, a renown level move while the row is open)
  local relation = row.relation
  if type(relation) == "table" and relation.shows then
    local tags = Parts().Tags(relation, true, owner or Recollect.Verdicts.Rows.Owner())
    row.tags = #tags > 0 and tags or nil
    row.dimmed = Parts().AnyShown(tags) or nil
  end
  local resolve = RESOLVE[row.kind]
  if resolve then
    resolve(row, owner or Recollect.Verdicts.Rows.Owner(), budget)
    return EventState(row)
  end
  if not row.stateText then Set(row, nil, nil, U.Colors.LIGHT_GRAY, row.filterState or "none") end
  EventState(row)
end

-------------------------------------------------------------------------------
-- Names, icons, sellers, places: read for the rows on screen, kept on the row
-------------------------------------------------------------------------------
local itemLoads = { at = nil, used = 0 }
local npcLoads = { at = nil, used = 0 }
local waiting = {}   -- [itemID] = when its load was asked for, while it is out
local LOAD_WAIT = 10   -- seconds before an unanswered load is asked again
Data.onItemLoaded = nil   -- the window's repaint, set by UI.DetailWindow
Data.onNameMissed = nil   -- the window's repaint a moment later: a creature's name was asked for

local function Spend(counter, cap)
  local now = seams.Now()
  if counter.at ~= now then counter.at, counter.used = now, 0 end
  if counter.used >= cap then return false end
  counter.used = counter.used + 1
  return true
end

-- An item's name, or nil while it loads (asked for within NAME_LOADS a frame)
-- A load that fails, or is never answered, is asked again after LOAD_WAIT
-- seconds (PI-13)
local function Waiting(itemID)
  local at = waiting[itemID]
  return at ~= nil and seams.Now() - at < LOAD_WAIT
end

function Data.ItemName(itemID)
  if not IsPositiveID(itemID) then return nil end
  local ok, name = Try(seams.ItemNameByID, itemID)
  if ok and type(name) == "string" and name ~= "" then return name end
  if not Waiting(itemID) and Spend(itemLoads, NAME_LOADS) then
    waiting[itemID] = seams.Now()   -- before the call: the answer can come during it
    pcall(seams.RequestItem, itemID)
  end
  return nil
end

local function NpcName(npcID)
  if not IsPositiveID(npcID) then return nil end
  -- a name read before costs nothing; a new tooltip is rationed
  local name = Vendors().KnownName(npcID)
  if name then return name end
  -- A name not read now (this frame's reads spent, a read that missed, or
  -- one waiting out its retry) asks the window for a later repaint, or the
  -- ID would stay on screen until something else repainted it
  if not Spend(npcLoads, NPC_NAMES) then
    if Data.onNameMissed then pcall(Data.onNameMissed) end
    return nil
  end
  name = Vendors().NpcName(npcID)
  if not name and Data.onNameMissed then pcall(Data.onNameMissed) end
  return name
end

-- A place's words: "Zone (x, y)"
local function PlaceWords(place)
  if not place then return nil end
  return ("%s (%.1f, %.1f)"):format(place.zone or ("map " .. place.mapID), place.x * 100, place.y * 100)
end

local function NpcPlace(npcID)
  local vendor = Vendors().Position(npcID)
  if vendor then
    vendor.zone = Vendors().ZoneName(vendor.mapID) or ("map " .. vendor.mapID)
    vendor.what = "the NPC"
  end
  return vendor
end

-- Where a quest starts (Relations.QuestGiver): its giver's place, named
-- once the giver's name is known
local function QuestPlace(questID)
  local giver = Relations().QuestGiver(questID)
  if not giver then return nil end
  return { mapID = giver.mapID, x = giver.x, y = giver.y, npcID = giver.npcID, what = "where the quest starts",
    zone = Vendors().ZoneName(giver.mapID) or ("map " .. giver.mapID) }
end

local function ObjectPlace(objectID)
  local object = Vendors().Object(objectID)
  if not (object and object.mapID) then return nil end
  return { mapID = object.mapID, x = object.x, y = object.y, what = #object.contents > 0 and "the treasure" or "the spot",
    zone = Vendors().ZoneName(object.mapID) or ("map " .. object.mapID) }
end

-- Where the row's thing is, whoever it is for (kept on the row)
local function RawPlace(row)
  if row.place ~= nil then return row.place or nil end
  local place
  if row.npcID then
    place = NpcPlace(row.npcID)
  elseif row.objectID then
    place = ObjectPlace(row.objectID)
  elseif row.npcs then
    for _, npc in ipairs(row.npcs) do
      place = NpcPlace(npc)
      if place then break end
    end
  elseif row.currencyID then
    local vendor = Vendors().ForCurrency(row.currencyID)[1]
    if vendor then place = NpcPlace(vendor.npcID) end
  elseif row.questID then
    place = QuestPlace(row.questID)
  end
  row.place = place or false
  return place
end

-- Place(row): where the row's thing is, for its Map action, or nil; a route
-- for someone else gives no waypoint
function Data.Place(row)
  if row.restricted then return nil end
  return RawPlace(row)
end

-- Profession(row): the profession of a recipe row ("Leatherworking"), or nil
function Data.Profession(row)
  if row.profession == nil then
    local skill = row.skillLine and row.skillLine > 0 and Parts().SkillLineName(row.skillLine)
    row.profession = skill or false
  end
  return row.profession or nil
end

-- ProfessionGroup(row): the profession a recipe row counts under in a
-- reagent's summary, as the reagent check counts them (a specialization
-- under its profession, Facts.Recipes.ProfessionOf), or nil when its name
-- can't be read
function Data.ProfessionGroup(row)
  if row.professionGroup == nil then
    local skill = row.skillLine
    local ok, parent = pcall(Recollect.Facts.Recipes.ProfessionOf, skill)
    local line = ok and IsPositiveID(parent) and parent or skill
    row.professionGroup = IsPositiveID(line) and Parts().SkillLineName(line) or false
  end
  return row.professionGroup or nil
end

-- Costs(row): every cost of a purchase row's trade, the pinned item's own
-- first ({ kind = "item" | "currency" | "gold", id, count }: Relations.Costs,
-- which a relation parsed without its item fills too), or nil
function Data.Costs(row)
  if type(row.relation) ~= "table" then return nil end
  local ok, costs = pcall(Relations().Costs, row.relation, row.of)
  return ok and type(costs) == "table" and costs or nil
end

-- Where(row): who and where, for a Where or Sold by column: "Belbi
-- Quikswitch (Dun Morogh)", "Dun Morogh (53.1, 38.2)", a recipe's
-- profession, or nil
function Data.Where(row)
  if row.kind == "endeavor" then return EndeavorWhere(row) end
  if row.what == "recipe" and row.skillLine and row.skillLine > 0 then return Data.Profession(row) end
  if row.what == "encounter" then
    local encounter = Vendors().Encounter(row.encounterID)   -- its dungeon or raid
    return encounter and encounter.instance or nil
  end
  if row.what == "faction" then return ("Renown %d"):format(row.level or 0) end
  local seller = Data.Seller(row)   -- a purchase's vendor, a journal's or the decor catalog's source
  if seller then return seller end
  local place = RawPlace(row)
  if not place then
    -- a boss with no place in the data: its dungeon or raid
    local boss = row.npcID and Vendors().Boss(row.npcID)
    return boss and boss.instance or nil
  end
  -- a creature's or vendor's row already names it: its place only
  local name = place.npcID and NpcName(place.npcID)
  if name then return ("%s (%s)"):format(name, place.zone) end
  return PlaceWords(place)
end

-- Name(row): the row's name for its first column; nil while it loads. A
-- creature whose name isn't read yet, or a spot, is named by its place ("An
-- NPC in Silvermoon City (52.8, 77.9)"), and true comes second then, so a
-- line that names the place after the name leaves it out
function Data.Name(row)
  if row.name then return row.name end
  local name
  local what = row.what
  if row.kind == "buys" and not ITEM_WHAT[what] and row.thing then
    name = Recollect.Facts.Buys.Name(row.thing)
  elseif row.itemID then
    name = Data.ItemName(row.itemID)
  elseif what == "recipe" then
    name = Parts().SpellName(row.spellID)
  elseif what == "npc" then
    name = NpcName(row.npcID)
    if not name then
      local place = Data.Place(row)
      if not place then return nil end
      return "An NPC in " .. PlaceWords(place), true
    end
  elseif what == "object" then
    local place = Data.Place(row)
    if not place then return "A treasure" end
    return (row.kindLabel == "Spot" and "A spot in " or "A treasure in ") .. PlaceWords(place), true
  elseif what == "quest" then
    return nil   -- Resolve sets it once the quest answers
  elseif what == "encounter" then
    local encounter = Vendors().Encounter(row.encounterID)
    name = encounter and encounter.name
  elseif what == "faction" then
    name = select(2, Parts().Renown(row.factionID, row.level, false))
  elseif what == "zone" then
    name = row.mapID == 0 and "Any enemy, anywhere" or Vendors().ZoneName(row.mapID)
    if name and row.mapID ~= 0 then name = "Enemies in " .. name end
  end
  if row.unresolved then name = "Unconfirmed product" end
  -- a part any of several items fill: the first, and how many others would do
  if name and row.part and row.part.alternatives then
    name = ("%s (or %d more)"):format(name, #row.part.alternatives - 1)
  end
  row.name = name
  return name
end

-- WarmName(row): reads the row's name, or asks for it; false when this
-- frame's loads are spent (the background pass tries again next frame)
function Data.WarmName(row)
  if row.name or row.what == "quest" then return true end
  local now = seams.Now()
  if row.itemID then
    if Waiting(row.itemID) then return true end
    if itemLoads.at == now and itemLoads.used >= NAME_LOADS then return false end
  elseif row.what == "npc" and not Vendors().KnownName(row.npcID) then
    if npcLoads.at == now and npcLoads.used >= NPC_NAMES then return false end
  end
  Data.Name(row)
  return true
end

function Data.Clock() return seams.Clock() end

-- A name to show now: the name, or its kind and ID while it loads
function Data.DisplayName(row)
  local name = Data.Name(row)
  if name then return name end
  if row.what == "quest" then return ("Quest %s (name not loaded)"):format(tostring(row.questID)) end
  if row.what == "encounter" then return ("Encounter %s"):format(tostring(row.encounterID or row.id or "?")) end
  if row.what == "npc" then
    return ("%s %s"):format(row.kind == "dropsFrom" and "Creature" or "NPC", tostring(row.npcID or row.id or "?"))
  end
  return ("%s %s"):format(row.kindLabel or row.what or "?", tostring(row.id or "?"))
end

local ICON_ATLAS = { quest = "QuestNormal", npc = "UI-HUD-MicroMenu-Communities-Mouseover", object = "Object",
  index = "Professions-Crafting-Orders-Icon", zone = "poi-worldmap", endeavor = "UI-HUD-MicroMenu-Housing-Mouseover",
  encounter = "UI-HUD-MicroMenu-AdventureGuide-Mouseover", faction = "UI-HUD-MicroMenu-AdventureGuide-Mouseover",
  blackMarket = "UI-HUD-MicroMenu-Shop-Mouseover", tradingPost = "UI-HUD-MicroMenu-Shop-Mouseover" }
local FALLBACK_ICON = 134400

-- Icon(row): a file ID, or an atlas name and true
function Data.Icon(row)
  if row.icon then return row.icon, row.iconAtlas end
  local icon
  local what = row.what
  if row.itemID then
    local ok, id = Try(seams.ItemIcon, row.itemID)
    icon = ok and id or nil
  elseif what == "mount" and row.mountID then
    local ok, _, spellID, id = Try(seams.MountInfo, row.mountID)
    if ok and IsPositiveID(spellID) then row.spellID = row.spellID or spellID end
    icon = ok and id or nil
  elseif what == "pet" then
    local ok, info = Try(seams.PetInfo, row.id)
    icon = ok and type(info) == "table" and info.icon or nil
  elseif what == "achievement" then
    local ok, _, _, _, _, _, _, _, _, _, id = Try(seams.AchievementInfo, row.achievementID)
    icon = ok and id or nil
  elseif what == "recipe" then
    local ok, id = Try(seams.SpellIcon, row.spellID or row.id)
    icon = ok and id or nil
  elseif what == "illusion" then
    local ok, info = Try(seams.IllusionInfo, row.id)
    icon = ok and type(info) == "table" and info.icon or nil
  elseif what == "ensemble" then
    local ok, sources = Try(seams.SetSources, row.id)
    local okItem, itemID = false, nil
    if ok and type(sources) == "table" and sources[1] then okItem, itemID = Try(seams.SourceItem, sources[1]) end
    if okItem and IsPositiveID(itemID) then
      local okIcon, id = Try(seams.ItemIcon, itemID)
      icon = okIcon and id or nil
    end
  end
  if icon then
    row.icon = icon
    return icon, nil
  end
  if ICON_ATLAS[what] then
    row.icon, row.iconAtlas = ICON_ATLAS[what], true
    return row.icon, true
  end
  return FALLBACK_ICON, nil
end

-- Quality(row): an item's quality, for its name's color, or nil
function Data.Quality(row)
  if not row.itemID then return nil end
  if row.quality == nil then
    local ok, q = Try(seams.ItemQuality, row.itemID)
    row.quality = ok and type(q) == "number" and q or false
  end
  return row.quality or nil
end

-- Seller(row): who sells a purchase ("Fizz Alechux (Razorwind Shores) and 2
-- more"), where the trade is when the data names no vendor but its place
-- ("In Blade's Edge Mountains", item 9), or nil
function Data.Seller(row)
  if row.sellerText then return row.sellerText end
  if row.kind == "journal" and row.target then
    local text = Recollect.Facts.Journals.SourceText(row.target.kind, row.target.id)
    row.sellerText = text and Parts().SourceSellers(text, row.of) or ""
    return row.sellerText ~= "" and row.sellerText or nil
  end
  if (not row.npcs or #row.npcs == 0) and IsPositiveID(row.tradeMap) then
    local zone = Vendors().ZoneName(row.tradeMap)
    if not zone then return "In map " .. row.tradeMap end
    row.sellerText = "In " .. zone   -- kept once the zone's name is read, and searched
    return row.sellerText
  end
  if not row.npcs or #row.npcs == 0 then return nil end
  local first = row.npcs[1]
  local name = NpcName(first)
  local place = NpcPlace(first)
  local words = name and (place and ("%s (%s)"):format(name, place.zone) or name)
    or (place and ("A vendor in " .. PlaceWords(place))) or nil
  if not words then return nil end
  if #row.npcs > 1 then words = ("%s and %d more"):format(words, #row.npcs - 1) end
  if name then row.sellerText = words end   -- kept once the name is known
  return words
end

-------------------------------------------------------------------------------
-- Links and tooltips
-------------------------------------------------------------------------------
local function MountSpell(row)
  if row.spellID or not row.mountID then return row.spellID end
  local ok, _, spellID = Try(seams.MountInfo, row.mountID)
  row.spellID = ok and IsPositiveID(spellID) and spellID or nil
  return row.spellID
end

local function LinkOf(row)
  local what = row.what
  if what == "mount" then MountSpell(row) end
  local function Try1(fn, ...)
    local ok, link = Try(fn, ...)
    return ok and type(link) == "string" and link ~= "" and link or nil
  end
  if what == "toy" then return Try1(seams.ToyLink, row.id) or Try1(seams.ItemLink, row.id) end
  if what == "heirloom" then return Try1(seams.HeirloomLink, row.id) or Try1(seams.ItemLink, row.id) end
  if row.itemID then return Try1(seams.ItemLink, row.itemID) end
  if what == "mount" and row.spellID then return Try1(seams.MountLink, row.spellID) end
  if what == "achievement" then return Try1(seams.AchievementLink, row.achievementID) end
  if what == "currency" then return Try1(seams.CurrencyLink, row.currencyID) end
  if what == "recipe" then return Try1(seams.SpellLink, row.spellID) end
  if what == "quest" then
    -- the game's link, else one made from the quest's name once it's known
    -- (a quest the log doesn't hold has no link until its data loads;
    -- Cobanyte, 2026-09-28: a quest must open its tooltip like any link).
    -- The one made here serves the tooltip and a click only, never chat:
    -- its second field is a value only the game knows (-1 is right for a
    -- holiday quest alone), and chat sends such a link as plain text
    local link = Try1(seams.QuestLink, row.questID)
    if link then return link end
    local name = row.questID and Data.Name(row)
    if type(name) == "string" and name ~= "" and IsPositiveID(row.questID) then
      return ("|cffffff00|Hquest:%d:-1|h[%s]|h|r"):format(row.questID, name)
    end
    return nil
  end
  if what == "illusion" then
    local ok, _, link = Try(seams.IllusionStrings, row.id)
    return ok and type(link) == "string" and link ~= "" and link or nil
  end
  if what == "endeavor" then return row.taskID and Try1(seams.TaskLink, row.taskID) or nil end
  if what == "npc" then
    local boss = Vendors().Boss(row.npcID)   -- its Encounter Journal link: a click opens the journal at it
    return boss and boss.link or nil
  end
  if what == "encounter" then
    local encounter = Vendors().Encounter(row.encounterID)
    return encounter and encounter.link or nil
  end
  return nil
end

-- Link(row): a chat link for the row's thing, or nil (an item not loaded
-- yet is asked for, so a second click links it)
function Data.Link(row)
  local link = LinkOf(row)
  if not link and row.itemID then Data.ItemName(row.itemID) end
  return link
end

-- ChatLink(row): a link chat will send whole, or nil. A quest's only when
-- the game gives it (GetQuestLink, which Blizzard's own Shift-clicks use and
-- insert nothing without); a miss asks for the quest's data, so a later
-- Shift-click may get it. Everything else is Link's
function Data.ChatLink(row)
  if row.what ~= "quest" then return Data.Link(row) end
  if not IsPositiveID(row.questID) then return nil end
  local ok, link = Try(seams.QuestLink, row.questID)
  if ok and type(link) == "string" and link:find("|Hquest:", 1, true) then return link end
  Recollect.Facts.QuestInfo.Get(row.questID)
  return nil
end

-- PlainWords(text): text with every escape taken out (colors, textures,
-- atlases, stray bars), since chat drops a whole message holding one outside
-- a real link
function Data.PlainWords(text)
  text = tostring(text or "")
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|", "")
  return text
end

-- Tooltip(row, tooltip): fills the tooltip for the row's thing; false when
-- the row has nothing to show beyond its text. A thing that is an item, or a
-- mount an item teaches, shows the item's own tooltip, the one the bags show
-- ("Already known" included; Cobanyte, 2026-09-24); the collections' own
-- tooltips (Toy Box, Heirlooms, Mount Journal) only when there is no item
function Data.Tooltip(row, tooltip)
  local what = row.what
  local ok = false
  if what == "mount" then MountSpell(row) end
  local mountItem = what == "mount" and row.spellID and Relations().MountItem(row.spellID)
  if row.itemID or mountItem then
    ok = pcall(tooltip.SetItemByID, tooltip, row.itemID or mountItem)
  elseif what == "toy" then
    ok = pcall(tooltip.SetToyByItemID, tooltip, row.id)
  elseif what == "heirloom" then
    ok = pcall(tooltip.SetHeirloomByItemID, tooltip, row.id)
  elseif what == "mount" and row.spellID then
    ok = pcall(tooltip.SetMountBySpellID, tooltip, row.spellID)
  elseif what == "achievement" then
    ok = pcall(tooltip.SetAchievementByID, tooltip, row.achievementID)
  elseif what == "currency" then
    ok = pcall(tooltip.SetCurrencyByID, tooltip, row.currencyID)
  elseif what == "recipe" then
    ok = pcall(tooltip.SetSpellByID, tooltip, row.spellID)
  elseif what == "quest" then
    ok = pcall(tooltip.SetHyperlink, tooltip, "quest:" .. row.questID)
  end
  -- an NPC, a journal encounter, a faction, the Black Market or the Trading
  -- Post: the row's words only (a journal link opens the journal on a click)
  return ok
end

-- ItemOf(row): the item a row stands for, which Alt-click opens here: its
-- own, or the item that teaches a mount; nil
function Data.ItemOf(row)
  if row.itemID then return row.itemID end
  if row.what ~= "mount" then return nil end
  local spellID = MountSpell(row)
  return spellID and Relations().MountItem(spellID) or nil
end

-- Wowhead(row): the row's thing's page on Wowhead, for the menu's Copy
-- Wowhead link (Cobanyte, 2026-09-28), or nil. Only an address built from
-- the row's own ID; nothing is read from the site. An item (a toy, an
-- heirloom, decor, or the item behind a pet, an ensemble, an illusion or a
-- mount) is its item page; the rest by what they are. A zone has none: its
-- ID is the game's map ID, which is not Wowhead's zone ID.
local WOWHEAD = "https://www.wowhead.com/"
local WOWHEAD_PAGE = {
  quest = function(row) return "quest", row.questID end,
  achievement = function(row) return "achievement", row.achievementID end,
  currency = function(row) return "currency", row.currencyID end,
  recipe = function(row) return "spell", row.spellID end,
  npc = function(row) return "npc", row.npcID end,
  object = function(row) return "object", row.objectID end,
  faction = function(row) return "faction", row.factionID end,
  mount = function(row) return "spell", MountSpell(row) end,
  pet = function(row) return "battle-pet", row.id end,   -- a species with no item behind it
}

function Data.Wowhead(row)
  local itemID = Data.ItemOf(row)
  if not itemID and (row.what == "toy" or row.what == "heirloom" or row.what == "decor") then itemID = row.id end
  if IsPositiveID(itemID) then return WOWHEAD .. "item=" .. itemID end
  local page = WOWHEAD_PAGE[row.what]
  if not page then return nil end
  local kind, id = page(row)
  return IsPositiveID(id) and (WOWHEAD .. kind .. "=" .. id) or nil
end

-------------------------------------------------------------------------------
-- Names in text as game links (the details window's Overview and header)
-------------------------------------------------------------------------------
-- LinkRow(kind, id): a row for a name a line heard (UI.UsedFor's line.links,
-- Facts.Chains' namer: "item", "quest", "achievement", "currency", "spell"
-- or "recipe" (a spell), "mount" (a mount ID), "pet" (a species), "ensemble",
-- "illusion", "toy", "heirloom", "decor", "npc", "encounter" (a journal
-- encounter)), built the way the tables'
-- rows are, so its tooltip, link and clicks are a table row's; or nil
local LINK_ROWS = {
  item = function(id) return { what = "item", itemID = id } end,
  quest = function(id) return { what = "quest", questID = id } end,
  achievement = function(id) return { what = "achievement", achievementID = id } end,
  currency = function(id) return { what = "currency", currencyID = id } end,
  spell = function(id) return { what = "recipe", spellID = id } end,
  mount = function(id) return { what = "mount", mountID = id } end,
  pet = function(id) return { what = "pet", itemID = Relations().ThingItem("p", id) } end,
  ensemble = function(id) return { what = "ensemble", itemID = Relations().ThingItem("e", id) } end,
  illusion = function(id) return { what = "illusion", itemID = Relations().ThingItem("l", id) } end,
  npc = function(id) return { what = "npc", npcID = id } end,
  encounter = function(id) return { what = "encounter", encounterID = id } end,
}
LINK_ROWS.recipe = LINK_ROWS.spell
for _, what in ipairs({ "toy", "heirloom", "decor" }) do
  LINK_ROWS[what] = function(id) return { what = what, itemID = id } end
end

function Data.LinkRow(kind, id)
  local make = LINK_ROWS[kind]
  if not make or not IsPositiveID(id) then return nil end
  local row = make(id)
  row.id = id
  return row
end

local LINK_YELLOW = U.Colors.LINK_YELLOW   -- a quest's or an achievement's link
local LINK_BLUE = U.Colors.LINK_BLUE       -- a spell's link: a mount, a recipe, an illusion

local function QualityColor(quality)
  if type(quality) ~= "number" then return nil end
  local ok, r, g, b = Try(seams.QualityColor, quality)
  if not ok or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
  return { r, g, b }
end

-- LinkColor(row): the color the game gives the row's link, or nil
function Data.LinkColor(row)
  local what = row.what
  if what == "quest" or what == "achievement" then return LINK_YELLOW end
  if row.itemID then return QualityColor(Data.Quality(row)) end
  if what == "mount" or what == "recipe" or what == "illusion" then return LINK_BLUE end
  if what == "encounter" then return Vendors().JOURNAL_COLOR end
  if what == "npc" or what == "object" then
    local boss = what == "npc" and row.npcID and Vendors().Boss(row.npcID)
    if boss and boss.link then return Vendors().JOURNAL_COLOR end
    return U.Colors.INFO_BLUE
  end
  if what == "currency" then
    local info = Parts().Currency(row.currencyID)
    return info and QualityColor(info.quality) or nil
  end
  return nil
end

-- Linkable(row): whether a row's name can be a link (a thing the game
-- links; an NPC or a spot, as a link of Recollect's own; a journal
-- encounter only when the journal gives its link)
local LINKABLE = { item = true, toy = true, heirloom = true, decor = true, mount = true, pet = true, ensemble = true,
  illusion = true, recipe = true, achievement = true, currency = true, quest = true, endeavor = true }
function Data.Linkable(row)
  if row.itemID or LINKABLE[row.what] then return true end
  -- an NPC or a spot is a link of Recollect's own even with no game link
  -- (Cobanyte, 2026-09-28): hover says what it is, a click opens its menu
  if row.what == "npc" and row.npcID then return true end
  if row.what == "object" and row.objectID then return true end
  if row.what == "encounter" then
    local encounter = Vendors().Encounter(row.encounterID)
    return encounter ~= nil and encounter.link ~= nil
  end
  return false
end

-- Heard(fn, ...): fn's answer and the names its words used (Facts.Chains'
-- namer: { { kind, id, text } }); the namer before it is always put back
function Data.Heard(fn, ...)
  local names = {}
  local Chains = Recollect.Facts.Chains
  local previous = Chains.SetNamer(function(kind, id, name)
    if type(name) == "string" and name ~= "" then names[#names + 1] = { kind = kind, id = id, text = name } end
  end)
  local ok, answer = pcall(fn, ...)
  Chains.SetNamer(previous)
  if not ok then error(answer, 0) end
  return answer, names
end

-------------------------------------------------------------------------------
-- Sorting and filtering, sliced for big tables
-------------------------------------------------------------------------------
-- Compare two sort keys: nils last, numbers before strings, then by value
local function Less(a, b)
  if a == nil then return false end
  if b == nil then return true end
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta == "number" end
  return a < b
end

-- -1, 0 or 1 for two sort keys, a missing key after any other
local function Compare(a, b)
  if a == nil or b == nil then return (a == nil and 1 or 0) - (b == nil and 1 or 0) end
  if Less(a, b) then return -1 end
  if Less(b, a) then return 1 end
  return 0
end

-- Order(key, rows, keyOf, ascending, filter, onDone): a job (Start's key)
-- giving the rows that pass filter, sorted by keyOf(row), then by name
-- (always A to Z), then in the rows' own order (a stable merge sort), a
-- slice at a time; a missing key goes last either way. onDone(shown) gets
-- the new list
function Data.Order(key, rows, keyOf, ascending, filter, onDone)
  local shown, keys, names, n, i = {}, {}, {}, 0, 0
  local width, src, dst, merged = 1, nil, nil, 0
  local phase = 1
  Data.Start(key, function(deadline)
    if phase == 1 then
      while i < #rows do
        i = i + 1
        local row = rows[i]
        if not filter or filter(row) then
          n = n + 1
          shown[n] = row
          if keyOf then
            keys[row] = keyOf(row)
            local name = Data.Name(row)
            names[row] = name and name:lower() or nil
          end
        end
        if seams.Clock() >= deadline then return false end
      end
      if not keyOf or n < 2 then
        onDone(shown)
        phase = 3
        return true
      end
      src, dst, phase = shown, {}, 2
    end
    -- bottom-up merge sort, one run pair at a time
    while width < n do
      while merged < n do
        local lo, mid = merged + 1, math.min(merged + width, n)
        local hi = math.min(merged + 2 * width, n)
        local a, b, k = lo, mid + 1, lo
        while k <= hi do
          local take
          if a > mid then
            take = false
          elseif b > hi then
            take = true
          else
            local ka, kb = keys[src[a]], keys[src[b]]
            local order = Compare(ka, kb)
            if not ascending and ka ~= nil and kb ~= nil then order = -order end
            if order == 0 then order = Compare(names[src[a]], names[src[b]]) end
            take = order <= 0
          end
          if take then dst[k], a = src[a], a + 1 else dst[k], b = src[b], b + 1 end
          k = k + 1
        end
        merged = hi
        if seams.Clock() >= deadline then return false end
      end
      src, dst, merged, width = dst, src, 0, width * 2
    end
    onDone(src)
    return true
  end)
end

Data._test = {
  seams = seams,
  -- Runs the queued jobs as frames would, until each is done or only
  -- waiting on the game (a pass that finishes none)
  RunAll = function()
    local guard = 0
    while jobs[1] and guard < 100000 do
      guard = guard + 1
      local finished, i = false, 1
      while jobs[i] do
        local job = jobs[i]
        local ok, done = pcall(job.step, math.huge)
        if not ok or done then
          Finish(i, job)
          finished = true
        else
          i = i + 1
        end
      end
      if not finished then break end
    end
  end,
  RunFrame = RunFrame,
  Jobs = function() return jobs end,
  Reset = function()
    wipe(jobs)
    wipe(waiting)
    itemLoads.at, itemLoads.used, npcLoads.at, npcLoads.used = nil, 0, nil, 0
  end,
  ItemLoaded = function(itemID) waiting[itemID] = nil end,
  -- Isolate(): the session's queued jobs, outstanding item loads and load
  -- budgets set aside for a test (Reset in their place, so a test's RunAll
  -- never runs a real job on scripted seams); returns the function that drops
  -- what the test queued and puts the session's back
  Isolate = function()
    local savedJobs, savedWaiting = {}, {}
    for i, job in ipairs(jobs) do savedJobs[i] = job end
    for itemID, at in pairs(waiting) do savedWaiting[itemID] = at end
    local loads = { itemLoads.at, itemLoads.used, npcLoads.at, npcLoads.used }
    Data._test.Reset()
    return function()
      wipe(jobs)
      wipe(waiting)
      for i, job in ipairs(savedJobs) do jobs[i] = job end
      for itemID, at in pairs(savedWaiting) do waiting[itemID] = at end
      itemLoads.at, itemLoads.used, npcLoads.at, npcLoads.used = loads[1], loads[2], loads[3], loads[4]
      if jobs[1] then runner:Show() else runner:Hide() end
    end
  end,
}

-- ITEM_DATA_LOAD_RESULT: an item this view asked for arrived; the window
-- repaints the rows that show it
local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "ITEM_DATA_LOAD_RESULT")
events:SetScript("OnEvent", function(_, _, itemID)
  if Recollect.Utilities.IsSecret(itemID) or not waiting[itemID] then return end
  waiting[itemID] = nil
  if Data.onItemLoaded then pcall(Data.onItemLoaded, itemID) end
end)
