-------------------------------------------------------------------------------
-- Purpose: a consumable (item class 0)
--
-- Potions, elixirs, flasks and phials, food and drink, bandages, Vantus runes,
-- item enhancements and temporary weapon enhancements (oils, sharpening
-- stones, weightstones and weapon runes, which the game files as Other: an
-- English Use line applying to "your ... weapon" for a set time; Cobanyte,
-- 2026-09-29, after a curator's flag on Algari Mana Oil), and Other items
-- whose English Use line makes them an elixir or a timed stat boost
-- (StatKind, Task #339) are made anew for each expansion, so one from an
-- older expansion is Outdated: both the item's expansionID and AllTheThings'
-- added patch below GetServerExpansionLevel (Facts.Item.Age "older"; the
-- reason names the later of the two: "from Shadowlands (added in patch
-- 9.0.2)"). When the game says older and the added patch says current
-- ("disagree"), a replaced kind is Unknown and any other kind only informs,
-- naming both. Other kinds from older expansions (devices, pet treats,
-- curios) are not replaced that way: those only inform, with what using it
-- gives and where it works when the game's own words say so
-- (Purposes.UseEffect.Describe, in UseItem.lua); one whose Use line says it
-- is only a drink for fun (ForFun, English clients) is marked flavor, which
-- the details window's Still needed? band reads (Just for fun), never a
-- verdict. Every such informing result carries optional, the kind of
-- optional use the band reads (UseEffect.Optional: a novelty, for pet
-- battles, an older item that still works, or the drink). Such a drink
-- filed as Food & Drink is no replaced kind either
-- (Cobanyte, 2026-10-01: about 300 older ales read Outdated before), so it
-- only informs too; while its Use line loads it is Unknown, never Outdated.
-- A consumable from the current expansion whose tooltip has a Use
-- line and that this character can use (C_PlayerInfo.CanUseItem) is Useful;
-- with no tooltip it is Unknown. A tooltip without a Use line only informs
-- ("what it's for isn't in its tooltip") when the item has no spell
-- (facts.hasSpell false):
-- a tooltip read before the spell loaded lacks the line (contract rule 14,
-- and a bank snapshot keeps such a read), so an item with a spell, or one
-- whose spell can't be read, stays Unknown. Toys, mounts, pets, ensembles and
-- weapon illusions are left to their own checks (Registry.CollectionItem);
-- when that read fails the item is Unknown, since it may be one of them.
-- An item tagged with a season of this expansion that isn't the current one
-- ("Midnight Season 1" while Season 2 runs), or whose season can't be told,
-- is left to the Season check: it is never "a current-expansion"
-- consumable. One this character can't use says why when its tooltip shows
-- it (a requirement in red) and who else could use it (its binding).
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber

-- Enum.ItemConsumableSubclass (12.1): the kinds each expansion replaces, as
-- { older, current } wording
local Sub = Enum and Enum.ItemConsumableSubclass or {}
local REPLACED = {
  [Sub.Potion or 1] = { "A potion", "A current-expansion potion" },
  [Sub.Elixir or 2] = { "An elixir", "A current-expansion elixir" },
  [Sub.Flasksphials or 3] = { "A flask or phial", "A current-expansion flask or phial" },
  [Sub.Fooddrink or 5] = { "Food or drink", "Current-expansion food or drink" },
  [Sub.Itemenhancement or 6] = { "An item enhancement", "A current-expansion item enhancement" },
  [Sub.Bandage or 7] = { "A bandage", "A current-expansion bandage" },
  [Sub.VantusRune or 9] = { "A Vantus rune", "A current-expansion Vantus rune" },
}
local OTHER = { "A consumable", "A current-expansion consumable" }
local WEAPON = { "A temporary weapon enhancement", "A current-expansion temporary weapon enhancement" }
local ELIXIR = REPLACED[Sub.Elixir or 2]
local STAT = { "A temporary stat boost", "A current-expansion temporary stat boost" }
-- Every Other consumable of the 2026-09-28 dump whose Use line reads this way
-- (73, from Classic's Rough Sharpening Stone to Midnight's Oil of Dawn) is a
-- weapon oil, stone or rune; a permanent coating ("lasts until canceled") and
-- an artifact relic name no time, and stay Other
local function IsTimedWeaponBuff(useText)
  local plain = CobySuite_Recollect.Utilities.StripColors(useText):lower()
  local weapon = plain:find("your weapons?%f[%A]") or plain:find("your [%a%-]+ weapons?%f[%A]")
    or plain:find("your [%a%-]+ [%a%-]+ weapons?%f[%A]")
  local timed = plain:find("for %d+ min") or plain:find("for %d+ hour") or plain:find("for %d+ sec")
    or plain:find("lasts %d+ min") or plain:find("lasts %d+ hour")
  return weapon ~= nil and timed ~= nil
end

-- An Other consumable that is an elixir by its Use line ("This effect counts
-- as a Battle Elixir": the old stat scrolls, Oil of Olaf), or a timed boost
-- to a stat ("Increases the target's Strength by 1 for 30 min", "grant 16
-- primary stat to all nearby allies for 1 hour"; Task #339: 93 such older
-- items read Can't tell in the 2026-10-10 dump), is a kind each expansion
-- replaces like a potion or a flask; a permanent one, a chance to proc or a
-- boost with no time stays Other
local STATS = { "strength", "agility", "intellect", "stamina", "spirit", "versatility", "critical strike", "haste",
  "mastery", "armor", "all stats", "primary stat", "attack power", "spell power" }
local function StatKind(useText)
  local plain = Recollect.Facts.Tooltip.StripColors(useText):lower()
  if plain:find("permanent", 1, true) or plain:find("chance to", 1, true) then return nil end
  if plain:find("counts as a battle elixir", 1, true) or plain:find("counts as a guardian elixir", 1, true)
    or plain:find("%.%s+battle elixir%.") or plain:find("%.%s+guardian elixir%.") then
    return ELIXIR
  end
  -- "for 30 min", "for 1 |4hour:hrs;" (the game's plural code, kept in the line)
  local timed = plain:find("for %d+ min") or plain:find("for %d+ hour") or plain:find("for %d+ sec")
    or plain:find("for %d+ |4")
  if not timed then return nil end
  for _, stat in ipairs(STATS) do
    if plain:find("increases? [%a' ]-" .. stat .. " by %d") or plain:find("grants? %d+ " .. stat) then return STAT end
  end
  return nil
end

-- The kind's { older, current } wording, or nil for a kind no expansion
-- replaces; and, for an Other consumable whose Use line decides it but hasn't
-- loaded, why it can't be told yet
local function Kind(ctx)
  local words = REPLACED[ctx.facts.subclassID]
  if words or ctx.facts.subclassID ~= (Sub.Other or 8) or not R.EnglishClient() then return words end
  local tip = ctx.Tooltip()
  if tip and tip.useText then return IsTimedWeaponBuff(tip.useText) and WEAPON or StatKind(tip.useText) end
  if ctx.facts.spellLoading then return nil, "its Use line is still loading" end
  if ctx.facts.spellFailed then return nil, "its Use line can't be loaded" end
  return nil
end
local NOT_REPLACED = "; this kind isn't replaced each expansion"

-- A drink that is only for fun (Cobanyte, 2026-10-01: alcohol is "purely RP
-- only ... not a game necessity"): an English Use line that calls it
-- alcohol and states no number, so no amount, stat or time it gives. In the
-- Lab's catalog (2026-10-01) 368 consumables read this way, every one a drink
-- ("A strong alcoholic beverage."); the 14 alcohols with a number are stat
-- buffs, mana drinks or timed effects, and stay as they are.
local FUN_WORDS = { "alcohol", "drunk", "tipsy", "intoxicat", "inebriat" }
local function ForFun(ctx)
  if not R.EnglishClient() then return false end
  local tip = ctx.Tooltip()
  if not tip or type(tip.useText) ~= "string" then return false end
  local plain = Recollect.Facts.Tooltip.StripColors(tip.useText):lower()
  if plain:find("%d") then return false end
  for _, word in ipairs(FUN_WORDS) do
    if plain:find(word, 1, true) then return true end
  end
  return false
end

-- An informing result for a kind no expansion replaces; marked flavor (a
-- drink only for fun, which the details window's Still needed? band reads)
-- when it gives nothing (no currency gain) and ForFun says so, and optional
-- with the kind of optional use its Use line names (UseEffect.Optional:
-- a novelty, for pet battles, or an older item that still works)
local function NotReplaced(ctx, text, age)
  local UseEffect = Recollect.Purposes.UseEffect
  local described = UseEffect.Describe(ctx)
  local result = UseEffect.Info(text, described, NOT_REPLACED)
  if not (described and described.headline) and ForFun(ctx) then result.flavor = "drink" end
  result.optional = result.flavor and "drink" or UseEffect.Optional(ctx, age)
  return result
end

-- Food and drink is a kind each expansion replaces, but a drink only for fun
-- is not (Cobanyte, 2026-10-01): whether a Food & Drink item is one; false,
-- with why, while its Use line loads or can't load (contract rule 14: it is
-- never Outdated before the line decides it)
local FUN_DRINK = "A drink"
local function FoodForFun(ctx)
  if ctx.facts.subclassID ~= (Sub.Fooddrink or 5) or not R.EnglishClient() then return false end
  local tip = ctx.Tooltip()
  if tip and type(tip.useText) == "string" then return ForFun(ctx) end
  if ctx.facts.spellLoading then return false, "its Use line is still loading" end
  if ctx.facts.spellFailed then return false, "its Use line can't be loaded" end
  return false
end
-- Enum.TooltipDataLineType.UsageRequirement (43 in 12.1): "Requires Midnight Herbalism (1)"
local USAGE_REQUIREMENT = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.UsageRequirement) or 43

R.Register({
  key = "consumable",
  label = "Consumable",
  order = 65,
  Evaluate = function(ctx)
    if ctx.facts.classID ~= R.CLASS_CONSUMABLE then return nil end
    local collection = R.CollectionItem(ctx)
    if collection == true then return nil end
    if collection == "unreadable" then
      return R.Unknown("Consumable; whether it's a toy, mount or pet can't be read", nil, "unreadable")
    end
    local client = Recollect.Purposes.client
    local okE, current = Try(client.GetServerExpansionLevel)
    local age, expansion, source, patch = nil, nil, nil, nil
    if okE and IsFiniteNumber(current) then
      age, expansion, source, patch = Recollect.Facts.Item.Age(ctx.facts, ctx.stack.itemID, current)
    end
    if not age then
      return R.Unknown("Consumable; its expansion can't be read")
    end
    local words, pending = Kind(ctx)
    local fun = false
    if words and age ~= "current" then
      local why
      fun, why = FoodForFun(ctx)
      pending = pending or why
    end
    local UseEffect = Recollect.Purposes.UseEffect
    if pending and age ~= "current" then
      -- whether it is a kind each expansion replaces can't be told before the
      -- Use line reads (contract rule 14): never "isn't replaced" meanwhile
      return R.Unknown(("%s %s; %s"):format((words or OTHER)[1], UseEffect.From(expansion, source, patch), pending), nil,
        ctx.facts.spellLoading and "loading" or "unreadable")
    end
    local lead = fun and FUN_DRINK or (words or OTHER)[1]
    -- A kind each expansion replaces, unless its Use line makes it an
    -- optional use no newer one replaces (rule 51): pet-battle food that heals
    -- battle pets, or a novelty (Task #442, audit R11: Little Buddy Biscuits
    -- read Outdated)
    local replaced = words and not fun
    if replaced and age ~= "current" then
      local optional = UseEffect.Optional(ctx, age)
      if optional == "petBattle" or optional == "novelty" then replaced = false end
    end
    if age == "older" then
      -- Both sources place it in an older expansion (Facts.Item.Age)
      local text = ("%s %s"):format(lead, UseEffect.Older(expansion, source, patch))
      if replaced then return R.Result(V.OUTDATED, text) end
      return NotReplaced(ctx, text, age)
    end
    if age == "disagree" then
      -- The game says older, the added patch says current: never Outdated,
      -- never "current-expansion"
      local text = ("%s; %s"):format(lead, UseEffect.Disagree(ctx.facts, expansion, patch))
      if replaced then return R.Unknown(text .. ", so whether a newer one replaces it can't be told") end
      return NotReplaced(ctx, text, age)
    end
    -- A season of this expansion that isn't the current one: Season speaks
    local Season = Recollect.Purposes.Season
    local tag = Season and Season.Of(ctx)
    if tag and tag.state ~= "current" and tag.state ~= "older" then return nil end
    local text = (words or OTHER)[2]
    -- Class 0 holds items with nothing to use (Vile Essence: "There's probably a
    -- use for this"); only one whose tooltip has a Use line is Useful
    local tip = ctx.Tooltip()
    if not tip then return R.Unknown(text .. "; its tooltip can't be read") end
    if not tip.useText then
      if ctx.facts.spellLoading then return R.Unknown(text .. "; its Use line is still loading", nil, "loading") end
      if ctx.facts.spellFailed then return R.Unknown(text .. "; its Use line can't be loaded", nil, "unreadable") end
      if ctx.facts.hasSpell == false then
        return R.Info(text .. "; what it's for isn't in its tooltip")
      end
      if ctx.facts.hasSpell then return R.Unknown(text .. "; it has a spell, but the tooltip read shows no Use line") end
      return R.Unknown(text .. "; whether it has a Use effect can't be read")
    end
    local okUse, canUse = Try(client.CanUseItem, ctx.stack.itemID)
    -- an item every way to get is gone for (an X record) and every use the
    -- data names is gone too is no live current-expansion consumable: it
    -- only informs, and the removed check speaks (Task #446: Memory of
    -- Kalimdor, whose Use is a combine no longer in the game, read Keep it).
    -- One with no use codes (a perfume) still works when held, so stays
    if okUse and canUse == true and Recollect.Facts.Relations.Removed(ctx.stack.itemID) ~= nil
      and R.UsesGone(ctx.stack.itemID) then
      return R.Info(text .. "; it can no longer be obtained")
    end
    if okUse and canUse == true then return R.Result(V.USEFUL, text) end
    if not okUse or canUse ~= false then
      return R.Unknown(text .. "; whether this character can use it can't be read", nil, "unreadable")
    end
    -- Why not, when the tooltip shows it (a line in red: a usage requirement,
    -- Enum.TooltipDataLineType 43, or another), and who else could
    local why = ""
    if tip.redLines > 0 then
      why = (tip.lineTypes and tip.lineTypes[USAGE_REQUIREMENT]) and ": its tooltip shows a requirement in red that it doesn't meet"
        or ": its tooltip shows a line in red"
    end
    return R.Unknown(text .. ", but this character can't use it" .. why .. R.BindNote(ctx))
  end,
})
