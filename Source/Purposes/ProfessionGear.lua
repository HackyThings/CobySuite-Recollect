-------------------------------------------------------------------------------
-- Purpose: profession tools and accessories (item class 19)
--
-- The item's profession comes from its subclass (Enum.ItemProfessionSubclass,
-- matched by name to Enum.Profession). Whether this character has that
-- profession: C_TradeSkillUI.GetProfessionSkillLineID(profession) among the
-- skill lines of GetProfessions / GetProfessionInfo (7th return). Its slots:
-- C_TradeSkillUI.GetProfessionSlots(profession), the call Blizzard's crafting
-- page uses; only slots holding the same kind (tool or accessory) are
-- compared, and the item's level must beat the lowest of them. Each
-- profession has one tool slot and the rest take accessories (the crafting
-- page's tool and gear slot buttons), so an accessory slot is empty when
-- fewer accessories are worn than the profession has slots, less one. A slot
-- that can't be read makes the comparison unreadable.
--
-- With nothing of its kind worn (the tool slot, or every accessory slot,
-- empty), what wearing it gives is read from C_Item.GetItemStats(link), the
-- stats the item adds (Blizzard's generated docs, 12.1.0): any stat above 0
-- is Use now once the tooltip shows this character can use it. None read is
-- Unknown with the facts: an Equip or proc effect in its tooltip (line types
-- 45, 46) is named as not checked; with none, an item from before
-- Dragonflight (expansion 9, when profession equipment got its stats) "adds
-- no profession stats Recollect can read, so wearing it likely does
-- nothing", and no tooltip says nothing either way; a newer one only says no
-- stats could be read, since how GetItemStats reads modern tools is what the
-- Lab's toolStats probe measures (unmeasured until its first run).
--
--   a profession this character doesn't have   Unknown (an alt might use it)
--   at or above what is equipped there         Useful
--   below, with an empty accessory slot        Unknown (a unique-equipped copy
--                                              may not go in it)
--   below what is equipped there               Outdated when from before this
--                                              season, else Lower level (Gear)
--   nothing of that kind equipped, stats read  Use now ("equip it")
--   nothing of that kind equipped, no stats    Unknown, naming the facts
--   a slot or the stats can't be read          Unknown
-- Useful and Use now need the tooltip to show this character can use it,
-- else Unknown.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber
local Ready = Recollect.Facts.Ready

local CLASS_PROFESSION = (Enum and Enum.ItemClass and Enum.ItemClass.Profession) or 19
local ACCESSORY = "INVTYPE_PROFESSION_GEAR"
local KIND_WORDS = { INVTYPE_PROFESSION_TOOL = "tool", [ACCESSORY] = "accessory" }
-- LE_EXPANSION_DRAGONFLIGHT: profession equipment has had stats since then
local DRAGONFLIGHT = 9
-- Enum.TooltipDataLineType ItemSpellTriggerOnEquip 45 and OnProc 46 (12.1.0)
local LineType = Enum and Enum.TooltipDataLineType or {}
local LINE_ON_EQUIP = LineType.ItemSpellTriggerOnEquip or 45
local LINE_ON_PROC = LineType.ItemSpellTriggerOnProc or 46

-- Does this character have the profession? true, false, or nil (unreadable)
local function HasProfession(client, profession)
  local okLine, skillLine = Try(client.GetProfessionSkillLineID, profession)
  if not okLine or not IsFiniteNumber(skillLine) or skillLine <= 0 then return nil end
  local okList, a, b, c, d, e = Try(client.GetProfessions)
  if not okList then return nil end
  local unread = false
  for _, index in pairs({ a, b, c, d, e }) do
    local okInfo, _, _, _, _, _, _, line = Try(client.GetProfessionInfo, index)
    if okInfo and line == skillLine then return true end
    -- a profession that can't be read may be this one: never "doesn't have"
    if not okInfo then unread = true end
  end
  if unread then return nil end
  return false
end

-- What is worn in the profession's slots of this kind: { lowest (the lowest
-- level, nil when none of that kind is worn), count, emptySlot (an accessory
-- slot of the profession is empty) }, or nil when a slot can't be read
local function Worn(client, profession, equipLoc)
  local ok, slots = Try(client.GetProfessionSlots, profession)
  -- No slots listed is a read that didn't answer, never an empty slot
  if not ok or type(slots) ~= "table" or #slots == 0 then return nil end
  local lowest, count = nil, 0
  for _, slot in ipairs(slots) do
    local okLoc, loc = Try(client.GetEquippedEquipLoc, slot)
    if not okLoc then return nil end
    if loc == equipLoc then
      local okLevel, exists, level = Try(client.GetEquippedItemLevel, slot)
      if not okLevel or not exists or not IsFiniteNumber(level) then return nil end
      count = count + 1
      if not lowest or level < lowest then lowest = level end
    end
  end
  return { lowest = lowest, count = count, emptySlot = equipLoc == ACCESSORY and count < #slots - 1 }
end

-- How many stats above 0 the item adds (0 for none or an empty answer), or
-- nil when the read fails or there is no link to read
local function StatCount(client, link)
  if type(link) ~= "string" or link == "" then return nil end
  local ok, stats = Try(client.GetItemStats, link)
  if not ok then return nil end
  if stats == nil then return 0 end
  if type(stats) ~= "table" then return nil end
  local n = 0
  for _, value in pairs(stats) do
    if IsFiniteNumber(value) and value > 0 then n = n + 1 end
  end
  return n
end

-- The expansion a player would say the item is from: Facts.Item.Expansion
-- when it is there, else the game's own expansionID
local function ExpansionOf(ctx)
  local Expansion = Recollect.Facts.Item.Expansion
  if type(Expansion) == "function" then
    local ok, expansion = pcall(Expansion, ctx.facts, ctx.stack.itemID)
    if ok and IsFiniteNumber(expansion) then return expansion end
  end
  return ctx.facts.expansionID
end

-- Useful (or verdict) once the tooltip shows this character can use it, else Unknown
local function Usable(ctx, text, verdict)
  local tip = ctx.Tooltip()
  if not tip then return R.Unknown(text .. "; its tooltip can't be read to confirm you can use it") end
  if tip.redLines > 0 then return R.Unknown(text .. ", but its tooltip shows this character can't use it") end
  return R.Result(verdict or V.USEFUL, text)
end

-- Nothing of its kind worn: equip it when it adds stats, else say what was read
local function EmptySlot(ctx, client, what, name, kind)
  local slotWords = kind == "tool" and ("your %s tool slot is empty"):format(name)
    or ("every %s accessory slot is empty"):format(name)
  local stats = StatCount(client, ctx.stack.link)
  if stats == nil then
    return R.Unknown(("%s; %s, and its stats can't be read"):format(what, slotWords), nil, "unreadable")
  end
  if stats > 0 then return Usable(ctx, ("%s; %s; equip it"):format(what, slotWords), V.USE) end
  -- An Equip or proc effect is a spell, not a stat (the Shadowlands fishing
  -- tool that finds bait): never "likely does nothing" over one
  local tip = ctx.Tooltip()
  if not tip then
    return R.Unknown(("%s; %s; it adds no stats Recollect can read, and its tooltip can't be read for an Equip effect"):format(what, slotWords))
  end
  local lineTypes = tip.lineTypes or {}
  if lineTypes[LINE_ON_EQUIP] or lineTypes[LINE_ON_PROC] then
    return R.Unknown(("%s; %s; it adds no stats Recollect can read, but it has an Equip effect, which isn't checked"):format(what, slotWords))
  end
  local expansion = ExpansionOf(ctx)
  if IsFiniteNumber(expansion) and expansion < DRAGONFLIGHT then
    return R.Unknown(("%s from %s; %s, but it adds no profession stats Recollect can read, so wearing it likely does nothing"):format(
      what, R.ExpansionName(expansion), slotWords))
  end
  return R.Unknown(("%s; %s, but no stats could be read from it, so what wearing it gives isn't known"):format(what, slotWords))
end

R.Register({
  key = "professionGear",
  label = "Profession gear",
  order = 62,
  Evaluate = function(ctx)
    if ctx.facts.classID ~= CLASS_PROFESSION then return nil end
    local kind = KIND_WORDS[ctx.facts.equipLoc]
    if not kind then return nil end
    local client = Recollect.Purposes.client
    local ok, profession, name = Try(client.GetItemProfession, ctx.facts.subclassID)
    if not ok or not IsFiniteNumber(profession) or type(name) ~= "string" then
      return R.Unknown("Profession gear; its profession can't be read")
    end
    local has = HasProfession(client, profession)
    local what = ("%s %s %s"):format(R.Article(name), name, kind)
    if has == nil then return R.Unknown(what .. "; your professions can't be read") end
    if not has then return R.Unknown(what .. "; this character doesn't have " .. name) end
    if not Ready.Equipment() then return R.Unknown(what .. "; your equipped items can't be read yet") end
    local worn = Worn(client, profession, ctx.facts.equipLoc)
    if not worn then
      return R.Unknown(("%s; what you have equipped for %s can't be read"):format(what, name), nil, "unreadable")
    end
    if not worn.lowest then return EmptySlot(ctx, client, what, name, kind) end
    local level = Recollect.Purposes.Gear.ItemLevel(client, ctx)
    if not level then return R.Unknown(what .. "; its item level can't be read") end
    if level < worn.lowest then
      local below = ("%s; item level %d is below the %s you use (%d)"):format(what, level, kind, worn.lowest)
      if worn.emptySlot then
        return R.Unknown(below .. "; you have an empty " .. name .. " accessory slot, so it may still be worn there")
      end
      -- Outdated only from before this season, as for gear (Gear.OlderWords)
      local older = Recollect.Purposes.Gear.OlderWords(ctx)
      if older then return R.Result(V.OUTDATED, below .. "; " .. older) end
      return R.Result(V.LOWER, below)
    end
    return Usable(ctx, ("%s; item level %d, at or above the %s you use (%d)"):format(what, level, kind, worn.lowest))
  end,
})
