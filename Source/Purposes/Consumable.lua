-------------------------------------------------------------------------------
-- Purpose: a consumable (item class 0)
--
-- Potions, elixirs, flasks and phials, food and drink, bandages, Vantus runes
-- and item enhancements are made anew for each expansion, so one from an
-- older expansion is Outdated: both the item's expansionID and AllTheThings'
-- added patch below GetServerExpansionLevel (Facts.Item.Age "older"; the
-- reason names the later of the two: "from Shadowlands (added in patch
-- 9.0.2)"). When the game says older and the added patch says current
-- ("disagree"), a replaced kind is Unknown and any other kind only informs,
-- naming both. Other kinds from older expansions (devices, pet treats,
-- curios) are not replaced that way: those only inform, with what using it
-- gives and where it works when the game's own words say so
-- (Purposes.UseEffect.Describe, in UseItem.lua).
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
local NOT_REPLACED = "; this kind isn't replaced each expansion"
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
    local words = REPLACED[ctx.facts.subclassID]
    local UseEffect = Recollect.Purposes.UseEffect
    if age == "older" then
      -- Both sources place it in an older expansion (Facts.Item.Age)
      local text = ("%s %s, an older expansion"):format((words or OTHER)[1], UseEffect.From(expansion, source, patch))
      if words then return R.Result(V.OUTDATED, text) end
      return UseEffect.Info(text, UseEffect.Describe(ctx), NOT_REPLACED)
    end
    if age == "disagree" then
      -- The game says older, the added patch says current: never Outdated,
      -- never "current-expansion"
      local text = ("%s; %s"):format((words or OTHER)[1], UseEffect.Disagree(ctx.facts, expansion, patch))
      if words then return R.Unknown(text .. ", so whether a newer one replaces it can't be told") end
      return UseEffect.Info(text, UseEffect.Describe(ctx), NOT_REPLACED)
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
