-------------------------------------------------------------------------------
-- Purposes.Registry: the purpose checks and the calls they make
--
-- A purpose check is { key, label, order, accountWide, Evaluate = function(ctx) }.
-- accountWide marks a check whose answer holds for any character's copy
-- (collections, known uses, achievements, junk): only those run on another
-- character's stored items (ctx.otherCharacter, contract rule 30).
-- Evaluate returns nil when the purpose does not apply to the item, else a
-- result { verdict, reason }. ctx carries:
--   stack     the slot read (Reader): itemID, link, count, isBound, hasLoot,
--             quest = { isQuestItem, questID, isActive }, tooltip (captured)
--   facts     Facts.Item for the item (always present: Verdicts gives
--             Unknown before any check runs when facts are missing)
--   kind      "bags", "bank" or "warband"
--   live      true when the slot was read just now (the item is in reach of
--             tooltip and use calls); false for a stored snapshot
--   bagID, slot
--   Tooltip() the tooltip facts: read now for a live slot, the captured ones
--             for a snapshot, nil when neither exists
--   playerFaction  0 (Horde) or 1 (Alliance), as PvPFaction, or nil
--   owner     whose copy it is (Verdicts.Rows.Owner): { faction, classID,
--             raceID, isViewer (the character logged in), name, guid }
--
-- Every client call a check makes goes through Purposes.client (Legacy's
-- spell reads through its own seams), so suites can script the client with
-- Tests.Override on its fields.
-------------------------------------------------------------------------------
local Registry = {}
Recollect.Purposes.Registry = Registry

-- Needed: something unfinished uses it. Use now: learn, open or start it.
-- Useful: worth keeping (current-expansion consumables, gems and reagents,
-- gear at or above what is worn in its slot, the keystone, owned decor, a
-- purchase, quest or endeavor task still open). Outdated: the facts say it
-- has been replaced (gear of a past season or an older expansion below what
-- is worn there with its appearance collected, in none of your equipment
-- sets and with no empty slot it could go in, older-expansion potions,
-- flasks and food, older gems and permanent enchantments, trade goods none
-- of your recipes use, an older season's item, every use gone, a bag no
-- bigger than every bag worn); the reason names the
-- facts, never "delete" or "sell". Lower level: the same gear not shown to
-- be from before this season (Cobanyte, 2026-09-26: gear merely below what
-- is worn isn't "outdated").
-- Junk: the game's own label, a gray item with a vendor price (Cobanyte,
-- 2026-09-24: junk is not "outdated"; the reason says what junk is).
-- Purpose done: every use Recollect checks is finished.
Registry.Verdict = {
  NEEDED = "needed",
  USE = "use",
  USEFUL = "useful",
  DONE = "done",
  OUTDATED = "outdated",
  LOWER = "lower",
  JUNK = "junk",
  UNKNOWN = "unknown",
}

Registry.VerdictLabel = {
  needed = "Needed",
  use = "Use now",
  useful = "Useful",
  done = "Purpose done",
  outdated = "Outdated",
  lower = "Lower level",
  junk = "Junk",
  unknown = "Can't tell",
}

local checks = {}

function Registry.Register(def)
  assert(type(def.key) == "string" and type(def.Evaluate) == "function", "purpose needs key and Evaluate")
  checks[#checks + 1] = def
  -- By order, then key: table.sort is not stable, and a tie decided the reason shown first
  table.sort(checks, function(a, b)
    local oa, ob = a.order or 100, b.order or 100
    if oa ~= ob then return oa < ob end
    return a.key < b.key
  end)
end

function Registry.All()
  return checks
end

-- brief (optional): the answer band's short why (UI.DetailWindow's
-- Detail.Brief), a glance answer with no costs, vendors, lists or chains
-- ("Leads to Phoenix Wishwing, a pet you don't have"); the reason keeps the
-- whole, which WHAT IT'S FOR and CHECKS show (Task #262). A check whose
-- reason is short already gives none: the band shortens the reason itself
function Registry.Result(verdict, reason, brief)
  return { verdict = verdict, reason = reason, brief = brief }
end

-- headline (optional): what the item is for, in a few words, which the audit
-- panel leads with instead of the verdict ("Combine 30 into Val'anyr").
-- category (optional, G-04): why it can't be told, one of Registry.CATEGORY's
-- keys; the panel adds that category's one recovery step, and the list
-- filters by it
function Registry.Unknown(reason, headline, category)
  return { verdict = Registry.Verdict.UNKNOWN, reason = reason, headline = headline, category = category }
end

-- Why an item reads Can't tell, each with the one thing that can change it
-- (a result's own recovery text, when it has one, names it more exactly:
-- "Open your Leatherworking window once")
Registry.CATEGORY = {
  loading = { label = "Waiting for game data", recovery = "The game is still sending its data; the panel reads it again when it arrives" },
  bank = { label = "Bank not read again", recovery = "Open your bank once so Recollect can read it again" },
  profession = { label = "A profession not read", recovery = "Open each crafting profession's window once" },
  unsupported = { label = "No check covers it", recovery = nil },
  disagree = { label = "Two answers disagree", recovery = "Hover it again after a moment; if they still differ, a /reload reads both again" },
  unreadable = { label = "A read failed", recovery = "A /reload reads everything again" },
  character = { label = "On another character", recovery = "Log in to that character to check it fully" },
  -- every use a check read is finished (a quest completed, an achievement
  -- earned), and only what can't be ruled out keeps it Can't tell: a quest
  -- that may come back, a use no data lists (Verdicts.Combine's settled)
  finished = { label = "Every use found is done", recovery = nil },
}

-- An Unknown that only informs ("this kind isn't replaced each expansion"):
-- it gives the reason when no other check has a verdict, and never holds
-- another check's verdict back (Verdicts.Combine)
function Registry.Info(reason)
  return { verdict = Registry.Verdict.UNKNOWN, reason = reason, soft = true }
end

-------------------------------------------------------------------------------
-- The client, as the checks see it
-------------------------------------------------------------------------------
Recollect.Purposes.client = {
  GetToyInfo = function(itemID) return C_ToyBox.GetToyInfo(itemID) end,
  PlayerHasToy = function(itemID) return PlayerHasToy(itemID) end,
  GetMountFromItem = function(itemID) return C_MountJournal.GetMountFromItem(itemID) end,
  GetMountInfoByID = function(mountID) return C_MountJournal.GetMountInfoByID(mountID) end,
  GetPetInfoByItemID = function(itemID) return C_PetJournal.GetPetInfoByItemID(itemID) end,
  GetNumCollectedInfo = function(speciesID) return C_PetJournal.GetNumCollectedInfo(speciesID) end,
  IsOnQuest = function(questID) return C_QuestLog.IsOnQuest(questID) end,
  IsQuestFlaggedCompleted = function(questID) return C_QuestLog.IsQuestFlaggedCompleted(questID) end,
  IsQuestFlaggedCompletedOnAccount = function(questID) return C_QuestLog.IsQuestFlaggedCompletedOnAccount(questID) end,
  IsAccountQuest = function(questID) return C_QuestLog.IsAccountQuest(questID) end,
  IsRepeatableQuest = function(questID) return C_QuestLog.IsRepeatableQuest(questID) end,
  GetQuestClassification = function(questID) return C_QuestInfoSystem.GetQuestClassification(questID) end,
  CanUseItem = function(itemID) return C_PlayerInfo.CanUseItem(itemID) end,
  GetAchievementInfo = function(achievementID) return GetAchievementInfo(achievementID) end,
  GetItemCount = function(itemID, includeBank, includeUses, includeReagentBank, includeAccountBank)
    return C_Item.GetItemCount(itemID, includeBank, includeUses, includeReagentBank, includeAccountBank)
  end,
  GetPetInfoBySpeciesID = function(speciesID) return C_PetJournal.GetPetInfoBySpeciesID(speciesID) end,
  GetServerExpansionLevel = function() return GetServerExpansionLevel() end,
  GetExpansionName = function(expansionID) return _G["EXPANSION_NAME" .. expansionID] end,
  -- a class's name in the player's language, for reasons that name classes
  GetClassName = function(classID)
    local info = C_CreatureInfo.GetClassInfo(classID)
    return info and info.className or nil
  end,
  -- Gear: the appearance (C_TransmogCollection) and item levels (C_Item)
  GetTransmogItemInfo = function(itemInfo) return C_TransmogCollection.GetItemInfo(itemInfo) end,
  GetSourceInfo = function(sourceID) return C_TransmogCollection.GetSourceInfo(sourceID) end,
  GetAllAppearanceSources = function(appearanceID) return C_TransmogCollection.GetAllAppearanceSources(appearanceID) end,
  GetItemLevelFromLink = function(link) return C_Item.GetDetailedItemLevelInfo(link) end,
  GetBagItemLevel = function(bagID, slot)
    return C_Item.GetCurrentItemLevel(ItemLocation:CreateFromBagAndSlot(bagID, slot))
  end,
  IsUsableItem = function(itemID) return C_Item.IsUsableItem(itemID) end,
  GetLocale = function() return GetLocale() end,
  -- Professions: skill lines, and the equipment slots each profession uses
  -- (Enum.Profession, name) for an Enum.ItemProfessionSubclass value, matched by name
  GetItemProfession = function(subclassID)
    for name, value in pairs(Enum.ItemProfessionSubclass) do
      if value == subclassID then return Enum.Profession[name], name end
    end
    return nil
  end,
  GetProfessions = function() return GetProfessions() end,
  GetProfessionInfo = function(index) return GetProfessionInfo(index) end,
  GetProfessionSkillLineID = function(profession) return C_TradeSkillUI.GetProfessionSkillLineID(profession) end,
  GetProfessionSlots = function(profession) return C_TradeSkillUI.GetProfessionSlots(profession) end,
  GetEquippedEquipLoc = function(slot)
    local itemID = GetInventoryItemID("player", slot)
    if not itemID then return nil end
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
    return equipLoc
  end,
  -- Bags: (exists, numSlots, subclassID) for an equipped bag slot (Enum.BagIndex
  -- 1 to 5); exists is false for an empty slot
  GetEquippedBag = function(bagID)
    local itemID = GetInventoryItemID("player", C_Container.ContainerIDToInventoryID(bagID))
    if not itemID then return false, nil, nil end
    local _, _, _, _, _, _, subclassID = C_Item.GetItemInfoInstant(itemID)
    return true, C_Container.GetContainerNumSlots(bagID), subclassID
  end,
  GetCurrencyInfo = function(currencyID) return C_CurrencyInfo.GetCurrencyInfo(currencyID) end,
  -- The faction a currency is turned into reputation with, or nil
  GetFactionGrantedByCurrency = function(currencyID) return C_CurrencyInfo.GetFactionGrantedByCurrency(currencyID) end,
  -- Ensembles and weapon illusions (Purposes/Transmog.lua)
  GetItemLearnTransmogSet = function(itemID) return C_Item.GetItemLearnTransmogSet(itemID) end,
  GetTransmogSetInfo = function(setID) return C_TransmogSets.GetSetInfo(setID) end,
  GetIllusions = function() return C_TransmogCollection.GetIllusions() end,
  GetIllusionName = function(illusionID) return (C_TransmogCollection.GetIllusionStrings(illusionID)) end,
  GetIllusionInfo = function(illusionID) return C_TransmogCollection.GetIllusionInfo(illusionID) end,
  -- Housing: the catalog entry for a decor item (HousingCatalogEntryInfo), or nil
  GetDecorInfo = function(itemID) return C_HousingCatalog.GetCatalogEntryInfoByItem(itemID) end,
  -- (exists, level): exists is false for an empty slot
  GetEquippedItemLevel = function(slot)
    local location = ItemLocation:CreateFromEquipmentSlot(slot)
    if not C_Item.DoesItemExist(location) then return false, nil end
    return true, C_Item.GetCurrentItemLevel(location)
  end,
  -- Equipment sets (Gear: a piece saved in one is never Outdated): the set
  -- IDs, a set's item IDs keyed by equipment slot, and its name (1st return);
  -- and the frame's time, so Gear reads the sets once per frame
  GetEquipmentSetIDs = function() return C_EquipmentSet.GetEquipmentSetIDs() end,
  GetEquipmentSetItemIDs = function(setID) return C_EquipmentSet.GetItemIDs(setID) end,
  GetEquipmentSetInfo = function(setID) return C_EquipmentSet.GetEquipmentSetInfo(setID) end,
  GetTime = function() return GetTime() end,
  CanDualWield = function() return CanDualWield() end,
  -- The season the game's UI shows (Season: Blizzard_ChallengesUI titles the
  -- Mythic+ tab with the first, PVPUtil.GetCurrentSeasonText uses the PvP
  -- season with the season's expansion); the client's version ("12.1.0",
  -- GetBuildInfo's first return); an item's inventory type by ID, with no load
  GetSeasonExpansion = function() return C_SeasonInfo.GetCurrentDisplaySeasonExpansion() end,
  GetMythicPlusSeason = function() return C_MythicPlus.GetCurrentUIDisplaySeason() end,
  GetPvPSeason = function() return C_PvP.GetUIDisplaySeason() end,
  GetClientVersion = function() return (GetBuildInfo()) end,
  GetItemEquipLoc = function(itemID)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
    return equipLoc
  end,
  -- The stats an item adds ({ ITEM_MOD_... = n }, or nothing): ProfessionGear
  -- reads a profession tool's with its slot empty
  GetItemStats = function(link) return C_Item.GetItemStats(link) end,
}

-- PvPFaction of the player: 0 Horde, 1 Alliance, nil otherwise
function Registry.FactionIndex(factionGroup)
  if factionGroup == "Horde" then return 0 end
  if factionGroup == "Alliance" then return 1 end
  return nil
end

-- Enum.ItemBind (12.1): OnAcquire 1, OnEquip 2, OnUse 3, Quest 4; 7 to 9
-- are warband bindings
local Bind = Enum and Enum.ItemBind or {}
local BIND_ON_ACQUIRE = Bind.OnAcquire or 1
local BIND_ON_EQUIP = Bind.OnEquip or 2
local BIND_ON_USE = Bind.OnUse or 3
local BIND_QUEST = Bind.Quest or 4

-- Whether this copy can only ever serve the character holding it: bound on
-- pickup, a quest item, or a bind-on-equip or bind-on-use item that is now
-- bound. A warbound or unbound copy could still go to an alt, so a check
-- that is done for this character alone must not call it done.
function Registry.CharacterOnlyCopy(ctx)
  local bindType = ctx.facts and ctx.facts.bindType
  if bindType == BIND_ON_ACQUIRE or bindType == BIND_QUEST then return true end
  if ctx.stack and ctx.stack.isBound and (bindType == BIND_ON_EQUIP or bindType == BIND_ON_USE) then return true end
  return false
end

-- Whether a collection check (toy, mount, pet, ensemble, weapon illusion)
-- covers the item: the kind checks (Consumable, Enhancement, Use effect,
-- Season) then leave it to that check, so a known toy is never also "a current consumable".
-- true, false, or "unreadable" when a read failed and none found it (BA-02:
-- the kind checks then say Unknown, never pass it as a plain consumable).
-- Cached on ctx.
function Registry.CollectionItem(ctx)
  if ctx.collectionItem ~= nil then return ctx.collectionItem end
  local client, Try, itemID = Recollect.Purposes.client, Recollect.Utilities.Try, ctx.stack.itemID
  local IsPositiveID = Recollect.Utilities.IsPositiveID
  local found, failed = false, false
  local okToy, toy = Try(client.GetToyInfo, itemID)
  if okToy and toy ~= nil then found = true elseif not okToy then failed = true end
  if not found then
    local okMount, mountID = Try(client.GetMountFromItem, itemID)
    found = okMount and IsPositiveID(mountID)
    if not okMount then failed = true end
  end
  if not found then
    local okPet, _, _, _, _, _, _, _, _, _, _, _, _, species = Try(client.GetPetInfoByItemID, itemID)
    found = okPet and IsPositiveID(species)
    if not okPet then failed = true end
  end
  local Transmog = Recollect.Purposes.Transmog
  if not found and Transmog then
    local setID, setFailed = Transmog.EnsembleSet(ctx)
    if setFailed then failed = true end
    found = setID ~= nil or Transmog.IllusionName(ctx) ~= nil
  end
  if found then
    ctx.collectionItem = true
  else
    ctx.collectionItem = failed and "unreadable" or false
  end
  return ctx.collectionItem
end

-- A mount or pet an item buys (Facts.Journals: { kind, id }): "have",
-- "missing", "unavailable" (a mount hidden from this character or of the
-- other faction), or nil when unreadable; and its name.
--   mount  GetMountInfoByID: collected (11th), shouldHideOnChar (10th),
--          faction-specific (8th) with its faction (9th)
--   pet    GetNumCollectedInfo above 0
-- faction is the copy's owner's (0 Horde, 1 Alliance); viewer false for
-- another character's copy, where shouldHideOnChar (the logged-in
-- character's flag) says nothing.
function Registry.CollectibleState(target, faction, viewer)
  local client, Try = Recollect.Purposes.client, Recollect.Utilities.Try
  local Ready = Recollect.Facts.Ready
  if target.kind == "mount" then
    if not Ready.Mounts() then return nil end
    local ok, name, _, _, _, _, _, _, isFactionSpecific, mountFaction, shouldHideOnChar, isCollected =
      Try(client.GetMountInfoByID, target.id)
    if not ok or type(isCollected) ~= "boolean" then return nil end
    if isCollected then return "have", name end
    if (shouldHideOnChar and viewer ~= false) or (isFactionSpecific and mountFaction ~= faction) then return "unavailable", name end
    return "missing", name
  end
  if not Ready.Pets() then return nil end
  local ok, collected = Try(client.GetNumCollectedInfo, target.id)
  if not ok or not CobySuite_Recollect.Utilities.IsFiniteNumber(collected) then return nil end
  local okName, name = Try(client.GetPetInfoBySpeciesID, target.id)
  return collected > 0 and "have" or "missing", okName and name or nil
end

-- How many copies of a decor the housing catalog counts as owned (stored,
-- granted not yet placed, placed; Blizzard_HousingCatalogUtil.lua adds the
-- same three), or nil when there is no entry or a count is unreadable
function Registry.DecorOwned(itemID)
  local ok, info = Recollect.Utilities.Try(Recollect.Purposes.client.GetDecorInfo, itemID)
  if not ok or type(info) ~= "table" then return nil end
  local total = 0
  for _, field in ipairs({ "totalNumStored", "remainingRedeemable", "totalNumPlaced" }) do
    local n = info[field]
    if not CobySuite_Recollect.Utilities.IsFiniteNumber(n) or n < 0 then return nil end
    total = total + n
  end
  return total, info
end

-- "A" or "An" for a reason that starts with text: a vowel ("An Enchanting
-- tool") or a number said with one ("An 8-slot bag", "An 18-slot bag")
function Registry.Article(text)
  text = tostring(text)
  if text:find("^[AEIOUaeiou]") or text:find("^8") or text:find("^1[18]%D") or text:find("^1[18]$") then return "An" end
  return "A"
end

-- Whether the client's language is one whose tooltip words a check reads
-- (English); checks that parse words stay silent in other languages
function Registry.EnglishClient()
  local ok, locale = Recollect.Utilities.Try(Recollect.Purposes.client.GetLocale)
  return ok and (locale == "enUS" or locale == "enGB")
end

-- For an Outdated reason: who else this copy could serve. Nothing for a
-- character-only copy; warband bindings (Enum.ItemBind 7 to 9, heirlooms
-- among them) go to your own characters; anything else unbound can be traded.
function Registry.BindNote(ctx)
  if Registry.CharacterOnlyCopy(ctx) then return "" end
  local bindType = ctx.facts and ctx.facts.bindType
  if type(bindType) == "number" and bindType >= 7 and bindType <= 9 then
    return "; it's warbound, so another of your characters could use it"
  end
  return "; it isn't bound, so it can be traded"
end

-- Enum.QuestClassification.Recurring (5 in 12.1)
Registry.QUEST_RECURRING = (Enum and Enum.QuestClassification and Enum.QuestClassification.Recurring) or 5
-- Enum.ItemClass values (12.1): Recipe 9, Questitem 12
Registry.CLASS_RECIPE = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
Registry.CLASS_QUEST = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
-- Weapon 2, Armor 4 (the Gear check); Consumable 0, Reagent 5 (keystones),
-- Tradegoods 7
local ItemClass = Enum and Enum.ItemClass or {}
Registry.CLASS_WEAPON = ItemClass.Weapon or 2
Registry.CLASS_ARMOR = ItemClass.Armor or 4
Registry.CLASS_CONSUMABLE = ItemClass.Consumable or 0
Registry.CLASS_REAGENT = ItemClass.Reagent or 5
Registry.CLASS_TRADEGOODS = ItemClass.Tradegoods or 7
-- Container 1 (bags), ItemEnhancement 8, Miscellaneous 15, Glyph 16, Housing 20
Registry.CLASS_CONTAINER = ItemClass.Container or 1
Registry.CLASS_MISC = ItemClass.Miscellaneous or 15
Registry.CLASS_ENHANCEMENT = ItemClass.ItemEnhancement or 8
Registry.CLASS_GLYPH = ItemClass.Glyph or 16
Registry.CLASS_HOUSING = ItemClass.Housing or 20
-- Enum.ItemQuality.Poor (0): grey items
Registry.QUALITY_POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
-- Enum.ItemArmorSubclass.Cosmetic 5, Enum.ItemReagentSubclass.Keystone 1
Registry.ARMOR_COSMETIC = (Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Cosmetic) or 5
Registry.REAGENT_KEYSTONE = (Enum and Enum.ItemReagentSubclass and Enum.ItemReagentSubclass.Keystone) or 1

-- How old the item is against the current expansion (Facts.Item.Age: the
-- game's expansionID and AllTheThings' added patch): "older", "current",
-- "disagree" or nil when unreadable, then the expansion, its source ("game"
-- or "added") and the patch. For a check that judges age: Outdated only
-- when "older", "current-expansion" only when "current"
function Registry.Age(ctx)
  local ok, current = Recollect.Utilities.Try(Recollect.Purposes.client.GetServerExpansionLevel)
  if not ok or not CobySuite_Recollect.Utilities.IsFiniteNumber(current) then return nil end
  return Recollect.Facts.Item.Age(ctx.facts, ctx.stack.itemID, current)
end

-- What routes restrict that a character fails (mismatch) or has no record
-- of (unknown), as { faction, class, race } sets (PI-14); owner is
-- Rows.Owner()'s { faction, classID, raceID }
function Registry.Restrictions(relations, owner)
  local mismatch, unknown = {}, {}
  owner = owner or {}
  for _, relation in ipairs(relations) do
    local flags = relation.flags or {}
    if flags.faction ~= nil then
      if owner.faction == nil then unknown.faction = true elseif owner.faction ~= flags.faction then mismatch.faction = true end
    end
    if flags.classes then
      if owner.classID == nil then unknown.class = true elseif not flags.classes[owner.classID] then mismatch.class = true end
    end
    if flags.races then
      if owner.raceID == nil then unknown.race = true elseif not flags.races[owner.raceID] then mismatch.race = true end
    end
  end
  return mismatch, unknown
end

-- "faction", "faction or class", "faction, class or race" for a set of
-- Restrictions; "faction or class" when it names none
function Registry.KindWords(set)
  local list = {}
  for _, kind in ipairs({ "faction", "class", "race" }) do
    if set[kind] then list[#list + 1] = kind end
  end
  if #list == 0 then return "faction or class" end
  if #list == 1 then return list[1] end
  return table.concat(list, ", ", 1, #list - 1) .. " or " .. list[#list]
end

-- The expansion's name for a reason line ("Dragonflight"), from the client's
-- EXPANSION_NAME<n> globals, or "expansion <n>"
function Registry.ExpansionName(expansionID)
  local ok, name = false, nil
  if type(expansionID) == "number" then ok, name = pcall(Recollect.Purposes.client.GetExpansionName, expansionID) end
  if ok and type(name) == "string" and name ~= "" then return name end
  return "expansion " .. tostring(expansionID)
end
