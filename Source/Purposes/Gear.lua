-------------------------------------------------------------------------------
-- Purpose: gear (weapons and armor): its appearance, and wearing it
--
-- Appearance (C_TransmogCollection.GetItemInfo on the item's link, or on its
-- item ID when the link answers nothing, as warbound-until-equipped gear did
-- in the Lab; the tooltip check below catches a base appearance that differs
-- from this copy's): this item's source collected, the same
-- look collected from another item (GetAllAppearanceSources), not collected
-- but collectable by this character (the source's playerCanCollect), not
-- collectable, or no appearance at all (necks, rings, trinkets only; any
-- other slot without an answer is unreadable). The tooltip must agree
-- (contract rule 5): "You haven't collected this appearance" shows exactly
-- when the look is not collected and could be, so it must be absent for a
-- look this character can't collect. With no tooltip to confirm, it is
-- Unknown.
--
-- Wearing: the item's own level (C_Item.GetCurrentItemLevel for a slot in
-- reach, GetDetailedItemLevelInfo on the stored link otherwise) against what
-- is worn in the same slot; for two-slot kinds (rings, trinkets, one-handed
-- weapons) the lower of the two, since that is the one it would replace.
-- The off-hand counts for a one-hander when it holds a weapon, or anything
-- else while this character can dual-wield (CanDualWield: a shield or
-- held-in-off-hand item it could replace); for a two-hander only when it
-- holds a two-hander (Titan's Grip). An empty ring or trinket slot, or an
-- empty main hand beside a weapon it could replace, is a place it could go;
-- an empty off-hand says nothing (a two-hander, or a class that can't
-- dual-wield).
--
--   appearance not collected, collectable   Needed
--   at or above what is worn there          Useful (Unknown when the tooltip
--                                           shows this character can't use it)
--   below, with an empty slot it could go   Unknown (a unique-equipped copy
--                                           may not go in it)
--   below, saved in an equipment set        Unknown, naming the set
--                                           (C_EquipmentSet, read once per
--                                           frame; unreadable sets: Unknown)
--   below what is worn there, appearance
--   collected or none                       Outdated when shown to be from
--                                           before this season, else Lower
--                                           level (below)
--   below, appearance not collectable here  the same when this copy can only
--                                           serve this character, else Unknown
-- Outdated gear is gear of a previous season or earlier (Cobanyte,
-- 2026-09-26): its tooltip's season tag names a past season or an older
-- expansion's (Purposes.Season), or, with no tag, the game and the added
-- patch agree it is from an older expansion (Registry.Age). Anything else
-- below what is worn is Lower level: a season tag of this season, one that
-- can't be placed, or current-expansion gear with no tag, whose season isn't
-- known.
-- Cosmetic armor, shirts and tabards are only their look: collected is
-- Purpose done, not collected is Needed.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try
local IsSecret = Recollect.Utilities.IsSecret
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber
local Ready = Recollect.Facts.Ready

local Gear = {}
Recollect.Purposes.Gear = Gear

-- Equipment slots per inventory type (INVSLOT_* numbers)
Gear.SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
  INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
  INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
  INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
  INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 16 }, INVTYPE_RANGEDRIGHT = { 16 },
}
-- Kinds that never have an appearance, and kinds that are only a look
local NO_APPEARANCE = { INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true }
local LOOK_ONLY = { INVTYPE_BODY = true, INVTYPE_TABARD = true }

-- What a weapon is compared with in the off-hand: a one-hander a weapon
-- there (anything else only while this character can dual-wield), a
-- two-hander only a two-hander there (Titan's Grip)
local MAIN_HAND, OFF_HAND = 16, 17
local OFF_HAND_PEERS = {
  INVTYPE_WEAPON = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_2HWEAPON = true },
  INVTYPE_2HWEAPON = { INVTYPE_2HWEAPON = true },
}
-- Slots where an empty one is a place the item could go, named for the
-- reason; the main hand counts only beside a worn weapon it is compared with
local EMPTY_SLOT_WORDS = { [11] = "ring", [12] = "ring", [13] = "trinket", [14] = "trinket", [MAIN_HAND] = "main hand" }

-- "collected", "other", "missing", "uncollectable", "none", or nil (unreadable)
function Gear.Appearance(client, ctx)
  local equipLoc = ctx.facts.equipLoc
  local ok, appearanceID, sourceID = Try(client.GetTransmogItemInfo, ctx.stack.link or ctx.stack.itemID)
  if ok and type(sourceID) ~= "number" and ctx.stack.link then
    ok, appearanceID, sourceID = Try(client.GetTransmogItemInfo, ctx.stack.itemID)
  end
  if not ok then return nil end
  if type(sourceID) ~= "number" then return NO_APPEARANCE[equipLoc] and "none" or nil end
  local okS, info = Try(client.GetSourceInfo, sourceID)
  if not okS or type(info) ~= "table" or type(info.isCollected) ~= "boolean" then return nil end
  if info.isCollected then return "collected" end
  local okA, sources = Try(client.GetAllAppearanceSources, appearanceID)
  if okA and type(sources) == "table" then
    for _, otherID in ipairs(sources) do
      local okO, other = Try(client.GetSourceInfo, otherID)
      if okO and type(other) == "table" and other.isCollected == true then return "other" end
    end
  end
  if info.playerCanCollect == true then return "missing" end
  if info.playerCanCollect == false then return "uncollectable" end
  return nil
end

-- Does the tooltip agree with the appearance state? true, false, or nil when
-- there is no tooltip with the appearance lines read
local function TooltipAgrees(tip, state)
  if not tip or tip.appearanceMissing == nil then return nil end
  if state == "collected" then return not tip.appearanceMissing and not tip.appearanceOther end
  if state == "other" then return not tip.appearanceMissing end
  if state == "missing" then return tip.appearanceMissing == true end
  -- The "missing" line shows only for a look this character could collect,
  -- and "uncollectable" means no other item's source is collected either
  if state == "uncollectable" then return not tip.appearanceMissing and not tip.appearanceOther end
  return true   -- "none": no appearance, no line to compare
end

-- The item's own level, or nil (also used by ProfessionGear)
local function ItemLevel(client, ctx)
  if ctx.live and ctx.bagID and ctx.slot then
    local ok, level = Try(client.GetBagItemLevel, ctx.bagID, ctx.slot)
    if ok and IsFiniteNumber(level) and level > 0 then return level end
  end
  if type(ctx.stack.link) == "string" then
    local ok, level = Try(client.GetItemLevelFromLink, ctx.stack.link)
    if ok and IsFiniteNumber(level) and level > 0 then return level end
  end
  return nil
end

Gear.ItemLevel = ItemLevel

-- Whether a weapon is compared with the off-hand: true when it holds a
-- weapon this one could replace (or, for a one-hander, anything while this
-- character can dual-wield), false when it holds anything else or is empty,
-- nil when its kind or the dual-wield answer can't be read
local function OffHandCounts(client, peers, equipLoc)
  local okLoc, loc = Try(client.GetEquippedEquipLoc, OFF_HAND)
  if not okLoc then return nil end
  if loc ~= nil then
    if peers[loc] then return true end
    if equipLoc ~= "INVTYPE_WEAPON" then return false end
    local okDual, dual = Try(client.CanDualWield)
    if not okDual or type(dual) ~= "boolean" then return nil end
    return dual
  end
  local ok, exists = Try(client.GetEquippedItemLevel, OFF_HAND)
  if not ok or exists ~= false then return nil end   -- something there whose kind can't be read
  return false
end

-- The level it would be compared with: the lowest worn among its slots, or
-- nil when nothing is worn there or a slot can't be read; and the word for an
-- empty slot it could go in ("ring"), or nil
local function WornLevel(client, equipLoc)
  local slots = Gear.SLOTS[equipLoc] or {}
  local peers = OFF_HAND_PEERS[equipLoc]
  if peers then
    local counts = OffHandCounts(client, peers, equipLoc)
    if counts == nil then return nil end
    slots = counts and { MAIN_HAND, OFF_HAND } or { MAIN_HAND }
  end
  local lowest, empty = nil, nil
  for _, slot in ipairs(slots) do
    local ok, exists, level = Try(client.GetEquippedItemLevel, slot)
    if not ok or type(exists) ~= "boolean" then return nil end
    if exists then
      if not IsFiniteNumber(level) or level <= 0 then return nil end
      if not lowest or level < lowest then lowest = level end
    elseif EMPTY_SLOT_WORDS[slot] then
      empty = EMPTY_SLOT_WORDS[slot]
    end
  end
  return lowest, empty
end

-- The player's equipment sets as item ID -> set names, or false when a set
-- can't be read. GetItemIDs is keyed by equipment slot, with 0 for an empty
-- slot, 1 an ignored one and -1 a missing item (EQUIPMENT_SET_* in
-- Blizzard's Constants.lua), so only IDs above 1 are items. Set IDs start
-- at 0.
local function ReadSets(client)
  local ok, setIDs = Try(client.GetEquipmentSetIDs)
  if not ok or type(setIDs) ~= "table" then return false end
  local index = {}
  for _, setID in ipairs(setIDs) do
    if IsSecret(setID) or not IsFiniteNumber(setID) or setID < 0 then return false end
    local okItems, itemIDs = Try(client.GetEquipmentSetItemIDs, setID)
    local okInfo, name = Try(client.GetEquipmentSetInfo, setID)
    if not okItems or type(itemIDs) ~= "table" or not okInfo or type(name) ~= "string" then return false end
    for _, itemID in pairs(itemIDs) do
      if IsSecret(itemID) then return false end
      if IsFiniteNumber(itemID) and itemID > 1 then
        local names = index[itemID]
        if not names then names = {}; index[itemID] = names end
        if names[#names] ~= name then names[#names + 1] = name end
      end
    end
  end
  return index
end

-- Read once per frame: a redraw evaluates every row in one frame, and
-- GetTime is the frame's time. Read again when a suite scripts other seams.
local setsRead = {}

-- The names of the equipment sets holding this item ID ({} for none), or nil
-- when the sets can't be read
local function SetsHolding(client, itemID)
  local okNow, now = Try(client.GetTime)
  if not okNow or not IsFiniteNumber(now) then now = nil end
  local c = setsRead
  if now == nil or c.at ~= now or c.ids ~= client.GetEquipmentSetIDs
    or c.items ~= client.GetEquipmentSetItemIDs or c.info ~= client.GetEquipmentSetInfo then
    c.at, c.ids, c.items, c.info = now, client.GetEquipmentSetIDs, client.GetEquipmentSetItemIDs, client.GetEquipmentSetInfo
    c.index = ReadSets(client)
  end
  if not c.index then return nil end
  return c.index[itemID] or {}
end

Gear.SetsHolding = SetsHolding

Gear._test = {
  -- Forget the sets read this frame (a test that changes its scripted sets
  -- without replacing the seams)
  ForgetEquipmentSets = function() setsRead = {} end,
}

local APPEARANCE_TEXT = {
  collected = "Appearance collected",
  other = "Appearance collected from another item",
  none = "No appearance",
  uncollectable = "This character can't collect its appearance",
}

local function LookOnly(state)
  if state == "collected" or state == "other" then
    return R.Result(V.DONE, (state == "other" and "Appearance collected from another item" or "Appearance collected")
      .. "; this item is only its look")
  end
  if state == "missing" then return R.Result(V.NEEDED, "Its appearance isn't in your collection yet") end
  return R.Unknown("This character can't collect its appearance; it is only its look")
end

-- Why gear is from before this season, or nil: a past season's or an older
-- expansion's tag, else an older expansion by both the game and the added
-- patch; a tag of this season (or one that can't be placed) says it isn't
-- shown older. Also used by ProfessionGear.
function Gear.OlderWords(ctx)
  local Season = Recollect.Purposes.Season
  local tag = Season and Season.Of(ctx)
  if tag then
    if tag.state == "older" then return ("from %s Season %d, a season of an older expansion"):format(tag.name, tag.number) end
    if tag.state == "past" then
      return ("from %s Season %d, a past season (Season %d is current)"):format(tag.name, tag.number, tag.current)
    end
    return nil
  end
  local age, expansion, source, patch = R.Age(ctx)
  if age ~= "older" then return nil end
  return Recollect.Purposes.UseEffect.From(expansion, source, patch) .. ", an older expansion"
end

-- Below what is worn there: Outdated when it is from before this season,
-- else Lower level, unless a slot it could go in is empty (Unknown: a
-- unique-equipped copy may not go there), another character could collect
-- its look, or an equipment set holds it
local function Below(ctx, client, state, level, worn, emptySlot)
  local text = ("%s; item level %d is below what you wear there (%d)"):format(APPEARANCE_TEXT[state], level, worn)
  if emptySlot then
    return R.Unknown(text .. "; you have an empty " .. emptySlot .. " slot, so it may still be worn there")
  end
  if state == "uncollectable" and not R.CharacterOnlyCopy(ctx) then
    return R.Unknown(text .. "; it isn't bound to this character, so another character could collect its appearance")
  end
  local sets = SetsHolding(client, ctx.stack.itemID)
  if not sets then return R.Unknown(text .. "; your equipment sets can't be read") end
  if #sets > 0 then
    return R.Unknown(("%s, but it's saved in your equipment %s %s"):format(text, #sets == 1 and "set" or "sets",
      table.concat(sets, ", ")))
  end
  local older = Gear.OlderWords(ctx)
  if older then return R.Result(V.OUTDATED, text .. "; " .. older .. R.BindNote(ctx)) end
  return R.Result(V.LOWER, text .. R.BindNote(ctx))
end

R.Register({
  key = "gear",
  label = "Gear",
  order = 60,
  Evaluate = function(ctx)
    local classID = ctx.facts.classID
    if classID ~= R.CLASS_WEAPON and classID ~= R.CLASS_ARMOR then return nil end
    local equipLoc = ctx.facts.equipLoc
    local lookOnly = LOOK_ONLY[equipLoc] or (classID == R.CLASS_ARMOR and ctx.facts.subclassID == R.ARMOR_COSMETIC)
    if not lookOnly and not Gear.SLOTS[equipLoc] then return nil end   -- not wearable gear
    if not Ready.Transmog() then return R.Unknown("Gear; your appearance collection hasn't loaded yet") end
    local client = Recollect.Purposes.client
    local state = Gear.Appearance(client, ctx)
    if not state then
      local quality = ctx.facts.quality
      if quality == 5 or quality == 6 then
        return R.Unknown("A legendary or artifact item; its look comes from its own collection, which isn't checked")
      end
      return R.Unknown("Gear; its appearance can't be read")
    end
    local agrees = TooltipAgrees(ctx.Tooltip(), state)
    if agrees == nil then return R.Unknown("Gear; its tooltip can't be read to confirm the appearance") end
    if not agrees then return R.Unknown("Gear; the appearance collection and the tooltip disagree") end
    if lookOnly then return LookOnly(state) end
    if state == "missing" then return R.Result(V.NEEDED, "Its appearance isn't in your collection yet") end
    if not Ready.Equipment() then return R.Unknown(APPEARANCE_TEXT[state] .. "; your equipped items can't be read yet") end
    local level = ItemLevel(client, ctx)
    local worn, emptySlot = WornLevel(client, equipLoc)
    if not level then return R.Unknown(APPEARANCE_TEXT[state] .. "; its item level can't be read") end
    if not worn then return R.Unknown(APPEARANCE_TEXT[state] .. "; nothing you wear in that slot to compare") end
    if level < worn then return Below(ctx, client, state, level, worn, emptySlot) end
    local compare = ("Item level %d, at or above what you wear there (%d)"):format(level, worn)
    local tip = ctx.Tooltip()
    if tip.redLines > 0 then return R.Unknown(compare .. ", but its tooltip shows this character can't use it") end
    return R.Result(V.USEFUL, compare)
  end,
})
