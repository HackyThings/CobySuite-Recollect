-------------------------------------------------------------------------------
-- Purpose: an unopened container (a cache, a bag of loot)
--
-- Use now only when this character can open it: the client says the item is
-- usable, and its tooltip has no "Locked" line (a lockbox needs a key or
-- lockpicking). Anything else is Unknown.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try

R.Register({
  key = "container",
  label = "Container",
  order = 10,
  Evaluate = function(ctx)
    if not ctx.stack.hasLoot then return nil end
    local tip = ctx.Tooltip()
    if not tip then return R.Unknown("Unopened container; its tooltip can't be read here") end
    if tip.locked then return R.Unknown("Locked container; it needs a key or lockpicking") end
    local ok, usable = Try(Recollect.Purposes.client.CanUseItem, ctx.stack.itemID)
    if not ok or type(usable) ~= "boolean" then return R.Unknown("Couldn't check whether you can open it") end
    if not usable then return R.Unknown("Unopened container you can't open yet") end
    return R.Result(V.USE, "Unopened container")
  end,
})
