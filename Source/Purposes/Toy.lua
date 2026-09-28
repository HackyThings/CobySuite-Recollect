-------------------------------------------------------------------------------
-- Purpose: a toy
--
-- The Toy Box is account-wide, so the answer holds for every character.
-- Two sources must agree: PlayerHasToy and the tooltip's "Already known"
-- line. Before the Toy Box has loaded, or when they disagree, it is Unknown,
-- and so is an item whose toy read fails (it may be a toy).
-- A toy not in the Toy Box is Use now only when its tooltip has no red line
-- (a requirement this character does not meet: a profession, a reputation).
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try
local IsPositiveID = Recollect.Utilities.IsPositiveID

R.Register({
  key = "toy",
  accountWide = true,   -- the same answer for any character's copy
  label = "Toy",
  order = 20,
  Evaluate = function(ctx)
    local client = Recollect.Purposes.client
    local itemID = ctx.stack.itemID
    local ok, toyItemID = Try(client.GetToyInfo, itemID)
    -- A failed read may hide a toy: Unknown, never silence (BA-02)
    if not ok then return R.Unknown("Whether it's a toy can't be read", nil, "unreadable") end
    if not IsPositiveID(toyItemID) then return nil end
    if not Recollect.Facts.Ready.Toys() then return R.Unknown("Toy; the Toy Box hasn't loaded yet", nil, "loading") end
    local okHas, has = Try(client.PlayerHasToy, itemID)
    if not okHas or type(has) ~= "boolean" then return R.Unknown("Toy; couldn't read the Toy Box", nil, "unreadable") end
    local tip = ctx.Tooltip()
    if not tip then return R.Unknown("Toy; its tooltip can't be read to confirm", nil, "unreadable") end
    if tip.known ~= has then return R.Unknown("Toy; the Toy Box and the tooltip disagree", nil, "disagree") end
    if has then return R.Result(V.DONE, "Duplicate: you already know this toy") end
    if tip.redLines > 0 then return R.Unknown("Toy not in your Toy Box, but this character can't use it yet (see its tooltip)") end
    return R.Result(V.USE, "Toy not in your Toy Box; use it to learn")
  end,
})
