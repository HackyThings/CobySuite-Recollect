-------------------------------------------------------------------------------
-- Purpose: item enhancements (item class 8): enchant scrolls, armor kits,
-- spellthreads, scopes, belt and shoulder add-ons, weapon illusions
--
-- A weapon illusion is left to its own check (Purposes/Transmog.lua; the
-- tooltip line type 40, LearnTransmogIllusion, never appeared in the Lab
-- catalog). Any other enhancement the tooltip calls known is done only for
-- a copy no other character could use.
--
-- Permanent enchantments are made anew for each expansion, so one from an
-- older expansion is Outdated; the tooltip's Use line says which are
-- permanent ("Use: Permanently enchants ..."), read on English clients
-- only. Older means both the game's expansionID and AllTheThings' added
-- patch (Facts.Item.Age, as Consumable); when the game says older and the
-- added patch current, a permanent one is Unknown naming both. Temporary ones (Illusory Adornment) are not replaced that way and
-- stay Unknown with the expansion named, as does any enhancement whose Use
-- line hasn't loaded (tooltip text can arrive late, contract rule 14). A
-- current-expansion one this character can use is Useful.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try

-- Does a Use line describe a permanent enchantment? The word can follow a
-- colored category ("Use: |cn...:Earthen Enhancements - Wondrous Weapons|r
-- Permanently enchants a weapon ...", The War Within's scrolls)
local function IsPermanent(useText)
  local plain = useText:gsub("|cn[%w_]*:", ""):gsub("|c........", ""):gsub("|[rR]", "")
  return (" " .. plain .. " "):find("[%s:]Permanently%s") ~= nil
end

R.Register({
  key = "enhancement",
  label = "Item enhancement",
  order = 71,
  Evaluate = function(ctx)
    if ctx.facts.classID ~= R.CLASS_ENHANCEMENT then return nil end
    local collection = R.CollectionItem(ctx)
    if collection == true then return nil end
    if collection == "unreadable" then
      return R.Unknown("Item enhancement; whether it's a weapon illusion can't be read", nil, "unreadable")
    end
    local tip = ctx.Tooltip()
    if not tip then return R.Unknown("Item enhancement; its tooltip can't be read") end
    local client = Recollect.Purposes.client
    if tip.known then
      if R.CharacterOnlyCopy(ctx) then return R.Result(V.DONE, "Duplicate: this character already knows it") end
      return R.Unknown("Already known here; another character may still need it")
    end
    local age, expansion, source, patch = R.Age(ctx)
    if not age then return R.Unknown("Item enhancement; its expansion can't be read") end
    if age ~= "current" then
      local UseEffect = Recollect.Purposes.UseEffect
      -- " from Shadowlands, an older expansion", or both expansions named
      local from = age == "older" and (" " .. UseEffect.From(expansion, source, patch) .. ", an older expansion")
        or ("; " .. UseEffect.Disagree(ctx.facts, expansion, patch))
      if not R.EnglishClient() then return R.Info("An item enhancement" .. from) end
      if type(tip.useText) ~= "string" then
        if ctx.facts.spellFailed then
          return R.Unknown("An item enhancement" .. from .. "; its Use line can't be loaded", nil, "unreadable")
        end
        return R.Unknown("An item enhancement" .. from .. (ctx.facts.spellLoading and "; its Use line is still loading"
          or "; its tooltip hasn't said what it does yet"), nil, "loading")
      end
      if IsPermanent(tip.useText) then
        if age == "disagree" then
          return R.Unknown("A permanent enchantment" .. from .. ", so whether a newer one replaces it can't be told")
        end
        return R.Result(V.OUTDATED, "A permanent enchantment" .. from .. "; each expansion brings its own" .. R.BindNote(ctx))
      end
      return R.Info("An item enhancement" .. from .. "; only permanent enchantments are replaced each expansion")
    end
    local okUse, canUse = Try(client.CanUseItem, ctx.stack.itemID)
    if okUse and canUse == true then return R.Result(V.USEFUL, "A current-expansion item enhancement") end
    return R.Unknown("A current-expansion item enhancement, but this character can't use it yet")
  end,
})
