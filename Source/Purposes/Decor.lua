-------------------------------------------------------------------------------
-- Purpose: housing decor (item class 20)
--
-- C_HousingCatalog.GetCatalogEntryInfoByItem gives the decor's catalog entry
-- (HousingCatalogEntryInfo, 12.1 docs): totalNumStored (in storage, not
-- counting unredeemed copies), remainingRedeemable (granted copies not yet
-- placed), totalNumPlaced (across every house and plot), and
-- firstAcquisitionBonus (the House XP its first collection gives). Blizzard's
-- catalog counts owned copies as those three added together
-- (Blizzard_HousingCatalogUtil.lua). Another copy can always be placed, so
-- an owned decor is Useful with the counts in the reason; one the catalog
-- counts none of is Use now. An item with no catalog entry (dyes, room
-- items, services) is not decor: Unknown.
--
-- The tooltip must agree (contract rule 5): its "Total Owned: n (Placed: p,
-- Storage: s)" line shows exactly when a copy is stored or placed, with
-- those numbers, and its "First-Time Collection Bonus" line the same House
-- XP. Unlike the catalog's own tooltip, the item tooltip leaves out granted
-- copies not yet placed (remainingRedeemable): Lab catalog 2026-09-23, 149 of
-- 149 decor items that differed were exactly those. A copy in the bags is
-- not counted: its Use line adds it to the House Chest.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber

local function Count(value)
  return IsFiniteNumber(value) and value >= 0 and value or nil
end

R.Register({
  key = "decor",
  accountWide = true,   -- the same answer for any character's copy
  label = "Decor",
  order = 61,
  Evaluate = function(ctx)
    if ctx.facts.classID ~= R.CLASS_HOUSING then return nil end
    local ok, info = Try(Recollect.Purposes.client.GetDecorInfo, ctx.stack.itemID)
    if not ok or type(info) ~= "table" then return R.Unknown("Housing item; the housing catalog has no entry for it") end
    local stored, redeemable, placed = Count(info.totalNumStored), Count(info.remainingRedeemable), Count(info.totalNumPlaced)
    if not stored or not redeemable or not placed then return R.Unknown("Decor; the housing catalog's counts can't be read") end
    local owned, bonus = stored + redeemable + placed, Count(info.firstAcquisitionBonus) or 0
    local tip = ctx.Tooltip()
    if not tip or not tip.decorReadable then return R.Unknown("Decor; its tooltip can't be read to confirm the counts") end
    local shown = tip.decorOwned
    local countsAgree = (shown == nil and stored + placed == 0)
      or (shown ~= nil and shown.total == stored + placed and shown.placed == placed and shown.stored == stored)
    if not countsAgree or (tip.decorBonus or 0) ~= bonus then
      return R.Unknown("Decor; the housing catalog and the tooltip disagree")
    end
    if owned == 0 then
      if bonus > 0 then
        return R.Result(V.USE, ("Decor you haven't collected; its first collection gives %d House XP"):format(bonus))
      end
      return R.Result(V.USE, "Decor you don't own in your house or its storage")
    end
    return R.Result(V.USEFUL, ("Decor you own %d of (%d placed, %d in storage); another copy can be placed too")
      :format(owned, placed, stored + redeemable))
  end,
})
