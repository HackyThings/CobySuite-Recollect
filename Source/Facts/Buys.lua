-------------------------------------------------------------------------------
-- Facts.Buys: what a "buys" relation's thing is, and whether its owner has it
--
-- Facts.Relations "buys" (AllTheThings and the Lab's vendor recorder, IDs
-- only) types each thing by what its state is read from, so nothing here
-- loads an item or asks what an item stands for (BA-11). Resolve(relation,
-- owner) returns { key, what, id, collectible, state, name }:
--   key    names the thing for de-duplication against the journals' and the
--          housing catalog's own costs ("mount:123", "pet:45", "decor:6789",
--          "item:6789", "toy:6789", ...)
--   what   "item", "toy", "mount", "pet", "decor", "ensemble", "heirloom",
--          "recipe", "illusion" or "achievement"
--   state  "have", "missing", "unavailable" (a mount this character can't
--          have), "unread" (its source isn't ready yet, or with failed =
--          true, the read failed or the client has no such thing),
--          "unassessed" (a recipe on another character's copy: recipes are
--          known per character, and only the one logged in can be asked), or
--          nil for a plain item, which has nothing to own
--   name   when the state read gave it (mounts, pets, ensembles,
--          achievements); Name(thing) reads any other for a line shown
-- Each source is read behind its ready gate (Facts.Ready, BA-03). owner is
-- Verdicts.Rows.Owner(): { faction, classID, isViewer, guid }. Answers are
-- kept (per owner for mounts and recipes, BY_OWNER; the account's for the
-- rest) until data changes (InventoryChanged: a collection, a quest, the
-- bags) or MEMO_SECONDS pass, so a redraw, and Mark of Honor's
-- purchases (about 8,700) on a held panel, read each thing once. A
-- failed read carries failed = true, so "can't be read" is told from "not
-- loaded yet".
--
-- RecipeKnown(spellID) answers from C_SpellBook.IsSpellKnown, which the Lab
-- measured only on player professions' recipes (Blacksmithing and
-- Leatherworking, 400 of 400 right with the window closed, 2026-09-23).
-- Recipes of other systems the data names (Protoform Synthesis, skill line
-- 2819: every one of Genesis Mote's 52 recipes; Junkyard Tinkering,
-- Abominable Stitching, Ascension Crafting and the like: Facts.Recipes
-- IsProfession) were never measured: the Lab's recipe truth (2026-09-24)
-- holds none of them, and their recipes are used at a forge or the like,
-- not in a profession window the Lab reads. So a "true" stands (a spell the
-- character has), and a "false" there is nil, "unverified": can't be read,
-- never "Not known". A recipe the data has no skill line for is read as
-- before.
--
-- Product(itemID, owner) says what a recipe's or combine's product is when
-- it is a collectible, and whether owner has it (see its comment).
-------------------------------------------------------------------------------
local Buys = {}
Recollect.Facts.Buys = Buys

local Try = Recollect.Utilities.Try
local IsPositiveID = Recollect.Utilities.IsPositiveID

local seams = {
  HasHeirloom = function(itemID) return C_Heirloom.PlayerHasHeirloom(itemID) end,
  MountFromSpell = function(spellID) return C_MountJournal.GetMountFromSpell(spellID) end,
  SpellName = function(spellID) return C_Spell.GetSpellName(spellID) end,
  SpellKnown = function(spellID) return C_SpellBook.IsSpellKnown(spellID, Enum.SpellBookSpellBank.Player) end,
  Now = function() return GetTime() end,
  IsCached = function(itemID) return C_Item.IsItemDataCachedByID(itemID) end,
  ClassOf = function(itemID)
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    return classID
  end,
}

local function Client() return Recollect.Purposes.client end
local function Registry() return Recollect.Purposes.Registry end
local function Ready() return Recollect.Facts.Ready end

local MEMO_SECONDS = 5
local memo = { at = nil, generation = nil, byOwner = {} }
local generation = 0   -- moves on when data changes (InventoryChanged)
-- A plain item has no state, so its thing is kept for the session, by relation
local plain = setmetatable({}, { __mode = "k" })

-- A state from a read, and true second when the read failed
local function Bool(ok, value)
  if not ok or type(value) ~= "boolean" then return "unread", true end
  return value and "have" or "missing", false
end

-- The things a typed letter stands for, each read from its own source
local READERS = {}

READERS[""] = function(id)
  return { key = "item:" .. id, what = "item", id = id, collectible = false }
end

READERS.t = function(id)
  local state, failed = "unread", false
  if Ready().Toys() then state, failed = Bool(Try(Client().PlayerHasToy, id)) end
  return { key = "toy:" .. id, what = "toy", id = id, collectible = true, state = state, failed = failed }
end

READERS.h = function(id)
  local state, failed = "unread", false
  if Ready().Heirlooms() then state, failed = Bool(Try(seams.HasHeirloom, id)) end
  return { key = "heirloom:" .. id, what = "heirloom", id = id, collectible = true, state = state, failed = failed }
end

READERS.d = function(id)
  -- nil: no catalog entry for it, or a count unreadable (no gate says when
  -- the housing catalog has loaded; see the audit report)
  local owned = Registry().DecorOwned(id)
  local state = owned == nil and "unread" or (owned > 0 and "have" or "missing")
  return { key = "decor:" .. id, what = "decor", id = id, collectible = true, state = state, failed = owned == nil }
end

READERS.m = function(spellID, owner)
  local ok, mountID = Try(seams.MountFromSpell, spellID)
  if not ok or not IsPositiveID(mountID) then
    return { key = "mountspell:" .. spellID, what = "mount", id = spellID, collectible = true, state = "unread", failed = true }
  end
  local state, name = Registry().CollectibleState({ kind = "mount", id = mountID }, owner.faction, owner.isViewer)
  return { key = "mount:" .. mountID, what = "mount", id = mountID, collectible = true, state = state or "unread", name = name,
    failed = state == nil and Ready().Mounts() }
end

READERS.p = function(speciesID, owner)
  local state, name = Registry().CollectibleState({ kind = "pet", id = speciesID }, owner.faction, owner.isViewer)
  return { key = "pet:" .. speciesID, what = "pet", id = speciesID, collectible = true, state = state or "unread", name = name,
    failed = state == nil and Ready().Pets() }
end

READERS.e = function(setID)
  local state, name, failed = "unread", nil, false
  if Ready().Transmog() then
    local ok, info = Try(Client().GetTransmogSetInfo, setID)
    if ok and type(info) == "table" and type(info.collected) == "boolean" then
      state = info.collected and "have" or "missing"
      name = type(info.name) == "string" and info.name or nil
    else
      failed = true
    end
  end
  return { key = "ensemble:" .. setID, what = "ensemble", id = setID, collectible = true, state = state, name = name, failed = failed }
end

READERS.l = function(illusionID)
  local state, failed = "unread", false
  if Ready().Transmog() then
    local ok, info = Try(Client().GetIllusionInfo, illusionID)
    if ok and type(info) == "table" and type(info.isCollected) == "boolean" then
      state = info.isCollected and "have" or "missing"
    else
      failed = true
    end
  end
  return { key = "illusion:" .. illusionID, what = "illusion", id = illusionID, collectible = true, state = state, failed = failed }
end

READERS.r = function(spellID, owner)
  -- Only the logged-in character's spellbook can be asked (the Lab, 2026-09-23:
  -- IsSpellKnown was right on 400 of 400 recipes with the window closed); a
  -- recipe outside the professions reads as RecipeKnown says
  local state, failed = "unassessed", false
  if owner.isViewer then
    local known = Buys.RecipeKnown(spellID)
    if known == nil then
      state, failed = "unread", true
    else
      state = known and "have" or "missing"
    end
  end
  return { key = "recipe:" .. spellID, what = "recipe", id = spellID, collectible = true, state = state, failed = failed }
end

READERS.a = function(achievementID)
  local a = Recollect.Facts.Achievements.Get(achievementID)
  return { key = "achievement:" .. achievementID, what = "achievement", id = achievementID, collectible = true,
    state = a and (a.earned and "have" or "missing") or "unread", name = a and a.name or nil, failed = a == nil }
end

-- Letters whose state depends on whose copy it is (the owner's faction, or
-- the logged-in character's spellbook); every other thing is the account's
local BY_OWNER = { m = true, r = true }

local function OwnerKey(owner)
  return owner.isViewer and "viewer" or tostring(owner.guid or owner.name)
end

-- The memo, started again when data changed or MEMO_SECONDS passed
local function Fresh()
  local now = seams.Now()
  if memo.generation ~= generation or memo.at == nil or now < memo.at or now - memo.at >= MEMO_SECONDS then
    memo.at, memo.generation, memo.byOwner = now, generation, {}
  end
  return memo.byOwner
end

-- Stamp(): a value that stays the same while every answer Resolve gives
-- does, so a result built from them can be kept that long
function Buys.Stamp()
  return Fresh()
end

-- Resolve(relation, owner): the thing a "buys" relation buys, or nil for a
-- thing this build can't read
function Buys.Resolve(relation, owner)
  local letter = relation.thing or ""
  if letter == "" then
    local thing = plain[relation]
    if thing == nil then
      thing = IsPositiveID(relation.id) and READERS[""](relation.id) or false
      plain[relation] = thing
    end
    return thing or nil
  end
  owner = owner or Recollect.Verdicts.Rows.Owner()
  local id, reader = relation.id, READERS[letter]
  if not IsPositiveID(id) or not reader then return nil end
  Fresh()
  local key = BY_OWNER[letter] and OwnerKey(owner) or "account"
  local kept = memo.byOwner[key]
  if not kept then
    kept = {}
    memo.byOwner[key] = kept
  end
  local thing = kept[relation]
  if thing == nil then
    thing = reader(id, owner) or false
    kept[relation] = thing
  end
  return thing or nil
end

-- Whether the character logged in knows a recipe spell: true, false, or nil
-- when it can't be read, with why second: "failed" (the read errored or
-- gave no answer) or "unverified" (a recipe of a system outside the player
-- professions, where a "false" was never measured; see the header)
function Buys.RecipeKnown(spellID)
  local ok, known = Try(seams.SpellKnown, spellID)
  if not ok or type(known) ~= "boolean" then return nil, "failed" end
  if known then return true end
  local recipe = Recollect.Facts.Relations.Recipe(spellID)
  if recipe and not Recollect.Facts.Recipes.IsProfession(recipe.skillLine) then return nil, "unverified" end
  return false
end

-------------------------------------------------------------------------------
-- Products: what a recipe or a combine makes, as a collectible (contract
-- rule 44)
-------------------------------------------------------------------------------
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber

local function Thing(what, id, itemID, state, failed, extra)
  local thing = { key = what .. ":" .. id, what = what, id = id, itemID = itemID, collectible = true,
    state = state, failed = failed }
  for k, v in pairs(extra or {}) do thing[k] = v end
  return thing
end

-- A pet: its species' collected count against the limit ("1/3")
local function PetThing(speciesID, itemID)
  if not Ready().Pets() then return Thing("pet", speciesID, itemID, "unread", false) end
  local ok, collected, limit = Try(Client().GetNumCollectedInfo, speciesID)
  if not ok or not IsFiniteNumber(collected) or collected < 0 then return Thing("pet", speciesID, itemID, "unread", true) end
  local okName, name = Try(Client().GetPetInfoBySpeciesID, speciesID)
  return Thing("pet", speciesID, itemID, collected > 0 and "have" or "missing", false, { collected = collected,
    limit = IsFiniteNumber(limit) and limit or nil, name = okName and type(name) == "string" and name or nil })
end

-- An item's appearance: collected from this item or another, missing, or
-- one this character can't collect (unavailable), each only when the item's
-- tooltip agrees (rule 5). nil and false when it has none; nil and true when
-- the read failed
local function AppearanceThing(itemID)
  local client = Client()
  local ok, appearanceID, sourceID = Try(client.GetTransmogItemInfo, itemID)
  if not ok then return nil, true end
  if type(sourceID) ~= "number" then return nil, false end
  if not Ready().Transmog() then return Thing("appearance", sourceID, itemID, "unread", false) end
  local okS, info = Try(client.GetSourceInfo, sourceID)
  if not okS or type(info) ~= "table" or type(info.isCollected) ~= "boolean" then
    return Thing("appearance", sourceID, itemID, "unread", true)
  end
  -- the item's own tooltip must agree (rule 5): "You haven't collected this
  -- appearance" shows exactly when the look is missing and collectable. A
  -- tooltip not read yet can't be read yet; one that disagrees can't be read
  local tip = Recollect.Facts.Tooltip.FromItemID(itemID)
  local function Agreed(state, missingLine, extra)
    if not tip then return Thing("appearance", sourceID, itemID, "unread", false) end
    if (tip.appearanceMissing == true) ~= missingLine then return Thing("appearance", sourceID, itemID, "unread", true) end
    return Thing("appearance", sourceID, itemID, state, false, extra)
  end
  if info.isCollected then return Agreed("have", false) end
  local okA, sources = Try(client.GetAllAppearanceSources, appearanceID)
  if okA and type(sources) == "table" then
    for _, otherID in ipairs(sources) do
      local okO, other = Try(client.GetSourceInfo, otherID)
      if okO and type(other) == "table" and other.isCollected == true then
        return Agreed("have", false, { otherItem = true })
      end
    end
  end
  if info.playerCanCollect == false then return Agreed("unavailable", false) end
  return Agreed("missing", true)
end

-- The product's thing, read live: the data's own answer first (K), then a
-- toy, a mount, a pet, an ensemble, decor, an appearance. nil and false
-- when it is none of them; nil and true when a read that could have found
-- one failed
local function ReadProduct(itemID, owner)
  local letter, id = Recollect.Facts.Relations.ItemThing(itemID)
  if letter and letter ~= "" and READERS[letter] and IsPositiveID(id) then
    if letter == "p" then return PetThing(id, itemID) end
    local thing = READERS[letter](id, owner)
    thing.itemID = itemID
    return thing
  end
  local client = Client()
  local okToy, toy = Try(client.GetToyInfo, itemID)
  if okToy and toy ~= nil then
    local thing = READERS.t(itemID)
    thing.itemID = itemID
    return thing
  end
  local okMount, mountID = Try(client.GetMountFromItem, itemID)
  if okMount and IsPositiveID(mountID) then
    local state, name = Registry().CollectibleState({ kind = "mount", id = mountID }, owner.faction, owner.isViewer)
    return Thing("mount", mountID, itemID, state or "unread", state == nil and Ready().Mounts() or false, { name = name })
  end
  local okPet, _, _, _, _, _, _, _, _, _, _, _, _, speciesID = Try(client.GetPetInfoByItemID, itemID)
  if okPet and IsPositiveID(speciesID) then return PetThing(speciesID, itemID) end
  local okSet, setID = Try(client.GetItemLearnTransmogSet, itemID)
  if okSet and IsPositiveID(setID) then
    local thing = READERS.e(setID)
    thing.itemID = itemID
    return thing
  end
  -- Decor: a housing item (class 20, as the Decor check asks) with a
  -- catalog entry; nil counts for one are unreadable
  local okClass, classID = Try(seams.ClassOf, itemID)
  if okClass and classID == Registry().CLASS_HOUSING then
    local owned = Registry().DecorOwned(itemID)
    if owned == nil then return Thing("decor", itemID, itemID, "unread", true) end
    return Thing("decor", itemID, itemID, owned > 0 and "have" or "missing", false, { owned = owned })
  end
  local appearance, appearanceFailed = AppearanceThing(itemID)
  if appearance then return appearance end
  return nil, not okToy or not okMount or not okPet or not okSet or not okClass or appearanceFailed
end

local NONE = {}

-- Product(itemID, owner): what an item a recipe or combine makes is as a
-- collectible, and whether owner has it: a thing as Resolve gives ({ key,
-- what, id, itemID, collectible, state, failed, name }), what "toy",
-- "mount", "pet", "ensemble", "illusion", "heirloom", "decor", "recipe",
-- "achievement" or "appearance"; a pet adds collected and limit (the Pet
-- Journal's "1/3"), decor owned, an appearance collected from another item
-- otherItem. States as Resolve's; "unavailable" is also an appearance this
-- character can't collect. Returns nil, why otherwise: "none" (nothing
-- collectible this reads: a plain item), "loading" (the item's data isn't
-- cached: nothing is loaded here, so a caller that shows the row loads the
-- item and asks again), "invalid"; a read that failed before anything was
-- found gives a thing with what "unknown", state "unread", failed true. Kept
-- per owner like Resolve's answers (rule 9), never while loading.
function Buys.Product(itemID, owner)
  if not IsPositiveID(itemID) then return nil, "invalid" end
  owner = owner or Recollect.Verdicts.Rows.Owner()
  Fresh()
  local key = OwnerKey(owner)
  local kept = memo.byOwner[key]
  if not kept then
    kept = {}
    memo.byOwner[key] = kept
  end
  local slot = "product:" .. itemID
  local thing = kept[slot]
  if thing == nil then
    local okCached, cached = Try(seams.IsCached, itemID)
    if not okCached or cached ~= true then return nil, "loading" end
    local found, failed = ReadProduct(itemID, owner)
    if found then
      thing = found
    elseif failed then
      thing = { key = "product:" .. itemID, what = "unknown", id = itemID, itemID = itemID, collectible = true,
        state = "unread", failed = true }
    else
      thing = NONE
    end
    kept[slot] = thing
  end
  if thing == NONE then return nil, "none" end
  return thing
end

-- RecipeProduct(spellID, owner): Product of what the recipe makes (the data's
-- schematic, Relations.Recipe), or nil, why ("no product" when the data
-- names none)
function Buys.RecipeProduct(spellID, owner)
  local recipe = Recollect.Facts.Relations.Recipe(spellID)
  if not recipe or not IsPositiveID(recipe.product) then return nil, "no product" end
  return Buys.Product(recipe.product, owner)
end

-- A thing's name for a line shown: read now, never loading more than the
-- line needs (Facts.Item.Name asks for an item within a per-frame budget);
-- nil until the client has it
function Buys.Name(thing)
  if thing.name then return thing.name end
  local what, id = thing.what, thing.id
  if what == "item" or what == "toy" or what == "heirloom" or what == "decor" then return Recollect.Facts.Item.Name(id) end
  if what == "recipe" then
    local ok, name = Try(seams.SpellName, id)
    return ok and type(name) == "string" and name ~= "" and name or nil
  end
  if what == "illusion" then
    local ok, name = Try(Client().GetIllusionName, id)
    return ok and type(name) == "string" and name ~= "" and name or nil
  end
  return nil
end

-- Data changed: every thing is read again
local listener = {}
function listener:ReceiveEvent() generation = generation + 1 end
Recollect.EventBus:Register(listener, { Recollect.Events.InventoryChanged })

Buys._test = { seams = seams, Reset = function() memo.at, memo.byOwner = nil, {} end,
  DataChanged = function() listener:ReceiveEvent() end }
