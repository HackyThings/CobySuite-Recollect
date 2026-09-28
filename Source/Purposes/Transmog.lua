-------------------------------------------------------------------------------
-- Purposes: ensembles and weapon illusions, items that teach appearances
--
-- Both are mostly consumables (item class 0, subclass 8) whose Use line
-- collects appearances; the tooltip says "Already known" once they are
-- collected (Lab catalog 2026-09-23). Two sources must agree (contract
-- rule 5):
--   ensemble   C_Item.GetItemLearnTransmogSet(item) gives the set, and
--              C_TransmogSets.GetSetInfo(set).collected whether you have it
--   illusion   no call links the item to its illusion, so the name in its
--              Use line ("Use: Collect the weapon enchantment appearance of
--              Felshatter.", English clients) is looked up among
--              C_TransmogCollection.GetIllusions() by GetIllusionStrings'
--              name, and that illusion's isCollected read
-- Collected is Purpose done; not collected is Use now unless the tooltip has
-- a red line. Appearances are account-wide, so any copy is a duplicate once
-- collected.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try
local IsPositiveID = Recollect.Utilities.IsPositiveID
local Ready = Recollect.Facts.Ready

local Transmog = {}
Recollect.Purposes.Transmog = Transmog

local ILLUSION_USE = "Collect the weapon enchantment appearance of (.+)%.$"

-- The illusion a Use line names, or nil (English clients only)
function Transmog.IllusionName(ctx)
  local tip = ctx.Tooltip()
  if not tip or type(tip.useText) ~= "string" or not R.EnglishClient() then return nil end
  local plain = Recollect.Facts.Tooltip.StripColors(tip.useText)
  return plain:match(ILLUSION_USE)
end

-- The set an ensemble teaches, or nil; true second when the read failed
-- (it may be an ensemble)
function Transmog.EnsembleSet(ctx)
  local ok, setID = Try(Recollect.Purposes.client.GetItemLearnTransmogSet, ctx.stack.itemID)
  if ok and IsPositiveID(setID) then return setID end
  return nil, not ok
end

-- name -> illusion ID, built once the collection answers (names never change)
local illusionsByName = nil

local function IllusionID(name)
  if not illusionsByName then
    local client = Recollect.Purposes.client
    local ok, list = Try(client.GetIllusions)
    if not ok or type(list) ~= "table" or #list == 0 then return nil, false end
    local map = {}
    for _, info in ipairs(list) do
      if type(info) == "table" and IsPositiveID(info.sourceID) then
        local okName, illusionName = Try(client.GetIllusionName, info.sourceID)
        if okName and type(illusionName) == "string" then map[illusionName] = info.sourceID end
      end
    end
    illusionsByName = map
  end
  return illusionsByName[name], true
end

-- The shared verdict once collected is read and the tooltip agrees
local function Collected(tip, collected, what, doneText, useText)
  if tip.known ~= collected then return R.Unknown(what .. "; the collection and the tooltip disagree") end
  if collected then return R.Result(V.DONE, doneText) end
  if tip.redLines > 0 then return R.Unknown(what .. " not collected, but this character can't use it yet (see its tooltip)") end
  return R.Result(V.USE, useText)
end

R.Register({
  key = "ensemble",
  accountWide = true,   -- appearances are account-wide
  label = "Ensemble",
  order = 32,
  Evaluate = function(ctx)
    local setID, failed = Transmog.EnsembleSet(ctx)
    if failed then return R.Unknown("Whether it teaches an ensemble can't be read", nil, "unreadable") end
    if not setID then return nil end
    if not Ready.Transmog() then return R.Unknown("Ensemble; the appearance collection hasn't loaded yet") end
    local ok, set = Try(Recollect.Purposes.client.GetTransmogSetInfo, setID)
    if not ok or type(set) ~= "table" or type(set.collected) ~= "boolean" then
      return R.Unknown("Ensemble; its set can't be read")
    end
    local tip = ctx.Tooltip()
    if not tip then return R.Unknown("Ensemble; its tooltip can't be read to confirm") end
    return Collected(tip, set.collected, "Ensemble",
      "Duplicate: you already have this ensemble's appearances",
      "Ensemble with appearances you haven't collected; use it to learn them")
  end,
})

R.Register({
  key = "illusion",
  accountWide = true,
  label = "Weapon illusion",
  order = 34,
  Evaluate = function(ctx)
    local name = Transmog.IllusionName(ctx)
    if not name then return nil end
    if not Ready.Transmog() then return R.Unknown("Weapon illusion; the appearance collection hasn't loaded yet") end
    local illusionID, answered = IllusionID(name)
    if not answered then return R.Unknown("Weapon illusion; the illusion collection can't be read yet") end
    if not illusionID then return R.Unknown("Weapon illusion; " .. name .. " isn't in the illusion collection") end
    local ok, info = Try(Recollect.Purposes.client.GetIllusionInfo, illusionID)
    if not ok or type(info) ~= "table" or type(info.isCollected) ~= "boolean" then
      return R.Unknown("Weapon illusion; its collection state can't be read")
    end
    return Collected(ctx.Tooltip(), info.isCollected, "Weapon illusion",
      "Duplicate: you already have this weapon illusion", "Weapon illusion not collected; use it to learn")
  end,
})

Transmog._test = {
  Reset = function() illusionsByName = nil end,
}
