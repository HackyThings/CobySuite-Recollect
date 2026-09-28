-------------------------------------------------------------------------------
-- Facts.Item: what the client says about an item, only once its data is
-- cached
--
-- Get(itemID) returns facts or nil and why. An item the client has not
-- cached yet is asked for once (LoadItemThen) and reported as loading; a
-- purpose check never runs on an item without facts, so it can only be
-- Unknown until the data arrives. When a load settles, InventoryChanged
-- fires so open windows re-evaluate.
--
-- An item with a spell (C_Item.GetItemSpell) shows its "Use:" line only once
-- that spell's data is loaded (Lab catalog 2026-09-23: 666 enchant scrolls
-- read with no Use line). Get asks for the spell's data too and marks the
-- facts spellLoading until it arrives; SPELL_DATA_LOAD_RESULT then fires
-- InventoryChanged, so a check that needs the line reads it on the redraw.
--
-- facts.hasSpell is whether GetItemSpell names a spell: true, false when it
-- names none, nil when the read failed. spellLoading describes the spell
-- cache now, not any tooltip read earlier (a bank snapshot keeps a read that
-- may predate the spell), so a missing Use line means "no Use effect" only
-- when hasSpell is false.
--
-- A spell load can fail (BA-09): the request throws, SPELL_DATA_LOAD_RESULT
-- answers success false, or SPELL_PENDING seconds pass with neither an
-- answer nor the cache filling. Then facts.spellFailed is true (a check says
-- the Use line can't be loaded, never "still loading" forever) and the spell
-- is asked for again only after SPELL_RETRY_AFTER seconds. A cache hit
-- clears both marks.
--
-- Name(itemID) is an item's name for a panel line: read when cached, else
-- asked for within NAME_LOADS_PER_FRAME new requests a frame, so a line list
-- naming thousands of items asks only for the ones it shows (BA-11).
--
-- Expansion(facts, itemID) is the expansion a player would say the item is
-- from. The game's expansionID is its data's, not where the item is used:
-- Seal Breaker Key reads Battle for Azeroth and opens treasures in The Maw,
-- Fragment of Val'anyr reads Classic and drops in Ulduar. AllTheThings' added
-- patch (Relations.AddedIn) names the later expansion for such items, and it
-- wins only when it is later. Age(facts, itemID, current) is what a check
-- that judges age may use: older only when both sources agree, current when
-- the game says so, "disagree" when the game says older and the added patch
-- says current (never Outdated, never "current-expansion").
-------------------------------------------------------------------------------
local Item = {}
Recollect.Facts.Item = Item

local Try = Recollect.Utilities.Try
local IsPositiveID = Recollect.Utilities.IsPositiveID

local LOAD_TIMEOUT = 5
local RETRY_AFTER = 30     -- seconds before a failed load is asked for again
local SPELL_PENDING = 10   -- seconds a spell request may go unanswered before it counts as failed
local SPELL_RETRY_AFTER = 30
local NAME_LOADS_PER_FRAME = 8

local seams = {
  IsCached = function(itemID) return C_Item.IsItemDataCachedByID(itemID) end,
  GetItemInfo = function(itemID) return C_Item.GetItemInfo(itemID) end,
  Load = function(itemID, opts) return CobySuite_Recollect.Utilities.LoadItemThen(itemID, opts) end,
  Now = function() return GetTime() end,
  After = function(delay, fn) C_Timer.After(delay, fn) end,
  GetItemSpell = function(itemID) return C_Item.GetItemSpell(itemID) end,
  IsSpellCached = function(spellID) return C_Spell.IsSpellDataCached(spellID) end,
  RequestSpell = function(spellID) return C_Spell.RequestLoadSpellData(spellID) end,
}

local loading = {}   -- [itemID] = true while a load is out
local failed = {}    -- [itemID] = time of the last failed load
local spells = {}    -- [spellID] = time its data was asked for, while the request is out
local spellFailed = {}   -- [spellID] = when its load failed
local names = { now = nil, used = 0 }   -- Name's requests this frame

local notify = CobySuite_Recollect.Utilities.Coalesce(0.3, function()
  Recollect.EventBus:Fire(Recollect.Events.InventoryChanged, "items")
end)
-- The redraw a spell's answer asks for (a seam, so the suites see it)
seams.Notify = function() notify:Call() end

-- Asks for an item's data; true when a request went out (not already
-- loading, and not in its back-off after a failed load)
local function RequestLoad(itemID)
  if loading[itemID] then return false end
  local failedAt = failed[itemID]
  if failedAt and seams.Now() - failedAt < RETRY_AFTER then return false end
  loading[itemID] = true
  seams.Load(itemID, {
    timeout = LOAD_TIMEOUT,
    onReady = function()
      loading[itemID] = nil
      failed[itemID] = nil
      notify:Call()
    end,
    onFail = function()
      loading[itemID] = nil
      failed[itemID] = seams.Now()
      notify:Call()
    end,
  })
  return true
end

local function Facts(itemID, name, link, quality, itemType, itemSubType, equipLoc, texture, sellPrice, classID, subclassID,
    bindType, expansionID, isCraftingReagent)
  return {
    itemID = itemID,
    name = name,
    link = link,
    quality = quality,
    itemType = type(itemType) == "string" and itemType ~= "" and itemType or nil,          -- "Miscellaneous" (localized)
    itemSubType = type(itemSubType) == "string" and itemSubType ~= "" and itemSubType or nil,  -- "Other" (localized)
    equipLoc = type(equipLoc) == "string" and equipLoc ~= "" and equipLoc or nil,   -- "INVTYPE_HEAD", ...
    texture = texture,
    sellPrice = sellPrice,
    classID = classID,
    subclassID = subclassID,
    bindType = bindType,
    expansionID = expansionID,
    isCraftingReagent = isCraftingReagent == true,
  }
end

-- The item's spell ID; false when GetItemSpell names none (it returns
-- nothing), nil when the read failed or answered something else
local function ItemSpell(itemID)
  local ok, _, spellID = Try(seams.GetItemSpell, itemID)
  if not ok then return nil end
  if IsPositiveID(spellID) then return spellID end
  if spellID == nil then return false end
  return nil
end

-- Is the item's spell (the text of its "Use:" line) still loading? Asks for
-- it when it is. false when the item has no spell, it is loaded, or its load
-- failed. The second result is facts.hasSpell (true, false or nil, as
-- ItemSpell), the third facts.spellFailed.
function Item.SpellLoading(itemID)
  local spellID = ItemSpell(itemID)
  if not spellID then return false, spellID, false end
  local okCached, cached = Try(seams.IsSpellCached, spellID)
  if okCached and cached == true then
    spells[spellID], spellFailed[spellID] = nil, nil
    return false, true, false
  end
  local now = seams.Now()
  local askedAt = spells[spellID]
  if askedAt and now - askedAt >= SPELL_PENDING then
    spells[spellID], spellFailed[spellID] = nil, now   -- no answer and no cache fill
  end
  local failedAt = spellFailed[spellID]
  if failedAt then
    if now - failedAt < SPELL_RETRY_AFTER then return false, true, true end
    spellFailed[spellID] = nil
  end
  if not spells[spellID] then
    spells[spellID] = now
    if not pcall(seams.RequestSpell, spellID) then
      spells[spellID], spellFailed[spellID] = nil, now
      return false, true, true
    end
    -- An unanswered request is noticed on the next read after SPELL_PENDING
    seams.After(SPELL_PENDING + 0.1, function() notify:Call() end)
  end
  return true, true, false
end

-- An item's name, or nil while its data loads; new loads are rationed per
-- frame (nothing here asks for the item's spell)
function Item.Name(itemID)
  if not IsPositiveID(itemID) then return nil end
  local okCached, cached = Try(seams.IsCached, itemID)
  if okCached and cached == true then
    local ok, name = Try(seams.GetItemInfo, itemID)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  if loading[itemID] then return nil end
  local now = seams.Now()
  if names.now ~= now then names.now, names.used = now, 0 end
  if names.used < NAME_LOADS_PER_FRAME and RequestLoad(itemID) then names.used = names.used + 1 end
  return nil
end

-- Get(itemID): facts table, or nil and why ("item data loading", ...)
function Item.Get(itemID)
  if not IsPositiveID(itemID) then return nil, "no item ID" end
  local okCached, cached = Try(seams.IsCached, itemID)
  if not okCached or cached ~= true then
    RequestLoad(itemID)
    return nil, failed[itemID] and "item data did not load" or "item data loading"
  end
  local ok, name, link, quality, _, _, itemType, itemSubType, _, equipLoc, texture, sellPrice, classID, subclassID, bindType,
    expansionID, _, isCraftingReagent = Try(seams.GetItemInfo, itemID)
  if not ok or type(name) ~= "string" then
    RequestLoad(itemID)
    return nil, "item data not available"
  end
  local facts = Facts(itemID, name, link, quality, itemType, itemSubType, equipLoc, texture, sellPrice, classID, subclassID,
    bindType, expansionID, isCraftingReagent)
  facts.spellLoading, facts.hasSpell, facts.spellFailed = Item.SpellLoading(itemID)
  return facts
end

-------------------------------------------------------------------------------
-- The expansion an item is from
-------------------------------------------------------------------------------
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber
local MAX_MAJOR = 30   -- a patch past 30.x is no patch this data knows

-- A patch as AllTheThings numbers them (90100 is 9.1.0) to its expansion
-- (its major version less one: 9.1.0 is Shadowlands, expansion 8; 1.x is
-- Classic, 0), or nil
function Item.PatchExpansion(patch)
  if not IsPositiveID(patch) then return nil end
  local major = math.floor(patch / 10000)
  if major < 1 or major > MAX_MAJOR then return nil end
  return major - 1
end

-- "9.1.0" for 90100, or nil
function Item.PatchText(patch)
  if not Item.PatchExpansion(patch) then return nil end
  return ("%d.%d.%d"):format(math.floor(patch / 10000), math.floor(patch / 100) % 100, patch % 100)
end

-- The item's added patch from the shipped data, or nil (Relations.lua loads
-- after this file; a missing or failing AddedIn is no patch, through Try)
local function AddedPatch(itemID)
  local Relations = Recollect.Facts.Relations
  if not IsPositiveID(itemID) or not Relations then return nil end
  local ok, patch = Try(Relations.AddedIn, itemID)
  return ok and IsPositiveID(patch) and patch or nil
end

-- Expansion(facts, itemID): expansionID, source, patch
--   the added patch's expansion, "added", the patch   when it is later than
--                                                       the game's, or the
--                                                       game's can't be read
--   the game's expansionID, "game", nil                otherwise
--   nil                                                neither is known
-- itemID defaults to facts.itemID
function Item.Expansion(facts, itemID)
  local game = type(facts) == "table" and facts.expansionID or nil
  if not IsFiniteNumber(game) or game < 0 then game = nil end
  local patch = AddedPatch(itemID or (type(facts) == "table" and facts.itemID or nil))
  local added = patch and Item.PatchExpansion(patch)
  if added and (game == nil or added > game) then return added, "added", patch end
  if game ~= nil then return game, "game", nil end
  return nil
end

-- Age(facts, itemID, current): how old the item is against the current
-- expansion, for a check that judges age, then Expansion's three values:
--   "older"      both sources place it before current (the later one is
--                older too)
--   "current"    the game's expansionID is current (or later)
--   "disagree"   the game says older, the added patch says current
--   nil          the game's expansionID or current can't be read
function Item.Age(facts, itemID, current)
  local game = type(facts) == "table" and facts.expansionID or nil
  if not IsFiniteNumber(game) or game < 0 or not IsFiniteNumber(current) then return nil end
  local expansion, source, patch = Item.Expansion(facts, itemID)
  if expansion == nil then return nil end
  if expansion < current then return "older", expansion, source, patch end
  if game >= current then return "current", expansion, source, patch end
  return "disagree", expansion, source, patch
end

-- SPELL_DATA_LOAD_RESULT (spellID, success): an answer to a spell asked for;
-- success false marks the load failed
local function OnSpellLoaded(spellID, success)
  if spellID and not Recollect.Utilities.IsSecret(spellID) and spells[spellID] then
    spells[spellID] = nil
    if success == false then spellFailed[spellID] = seams.Now() end
    seams.Notify()
  end
end

local frame = CreateFrame("Frame")
pcall(frame.RegisterEvent, frame, "SPELL_DATA_LOAD_RESULT")
frame:SetScript("OnEvent", function(_, _, spellID, success) OnSpellLoaded(spellID, success) end)

Item._test = {
  seams = seams,
  SpellLoaded = OnSpellLoaded,
  Reset = function()
    wipe(loading)
    wipe(failed)
    wipe(spells)
    wipe(spellFailed)
    names.now, names.used = nil, 0
  end,
}
