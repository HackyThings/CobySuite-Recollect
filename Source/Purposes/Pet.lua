-------------------------------------------------------------------------------
-- Purpose: an item that teaches a battle pet
--
-- The Pet Journal is account-wide. Use now only when the species is not in
-- the journal at all and the tooltip has no red line (a requirement this
-- character does not meet); with at least one it is done ("You already have
-- this pet (n/limit collected)"), since the purpose, having the pet, is met.
-- Two sources must agree: GetNumCollectedInfo and the tooltip's "Collected
-- (n/m)" line.
-- Caged pets (battlepet links) are not checked yet.
--
-- GetPetInfoByItemID returns name, icon, petType, creatureID, sourceText,
-- description, isWild, canBattle, isTradeable, isUnique, obtainable,
-- displayID, speciesID (13).
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try
local IsPositiveID = Recollect.Utilities.IsPositiveID
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber

local function Agrees(collected, tipCount)
  if collected > 0 then return tipCount == collected end
  return tipCount == nil or tipCount == 0
end

R.Register({
  key = "pet",
  accountWide = true,   -- the same answer for any character's copy
  label = "Pet",
  order = 40,
  Evaluate = function(ctx)
    local client = Recollect.Purposes.client
    local link = ctx.stack.link
    if type(link) == "string" and link:find("|Hbattlepet:", 1, true) then
      return R.Unknown("Caged battle pet; not checked yet")
    end
    local ok, _, _, _, _, _, _, _, _, _, _, _, _, speciesID = Try(client.GetPetInfoByItemID, ctx.stack.itemID)
    -- A failed read may hide a pet: Unknown, never silence (BA-02)
    if not ok then return R.Unknown("Whether it teaches a pet can't be read", nil, "unreadable") end
    if not IsPositiveID(speciesID) then return nil end
    if not Recollect.Facts.Ready.Pets() then return R.Unknown("Pet; the Pet Journal hasn't loaded yet", nil, "loading") end
    local okCount, collected, limit = Try(client.GetNumCollectedInfo, speciesID)
    if not okCount or not IsFiniteNumber(collected) or not IsFiniteNumber(limit) or collected < 0 then
      return R.Unknown("Pet; couldn't read the Pet Journal", nil, "unreadable")
    end
    local tip = ctx.Tooltip()
    if not tip then return R.Unknown("Pet; its tooltip can't be read to confirm", nil, "unreadable") end
    if not Agrees(collected, tip.petCollected) then return R.Unknown("Pet; the Pet Journal and the tooltip disagree", nil, "disagree") end
    if collected == 0 then
      if tip.redLines > 0 then return R.Unknown("Pet not collected, but this character can't use it yet (see its tooltip)") end
      return R.Result(V.USE, "Pet not collected; use it to learn")
    end
    return R.Result(V.DONE, ("You already have this pet (%d/%d collected)"):format(collected, limit))
  end,
})
