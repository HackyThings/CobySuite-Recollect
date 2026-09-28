-------------------------------------------------------------------------------
-- Purpose: an item that buys housing decor (Facts.Relations "buysDecor")
--
-- The housing catalog's source text for a decor lists what a vendor takes
-- for it ("Cost: 125 Brewfest Prize Token"); /recollect-data turns those into
-- relations on the cost item. For each decor it buys, the catalog's owned
-- count (Registry.DecorOwned) is read live:
--   * any decor not owned: Useful, naming a few with their cost. Not Needed:
--     another copy of decor never has to be bought, and the Decor check calls
--     an owned decor Useful too.
--   * every one owned: Unknown, since the catalog lists only decor and the
--     item may buy other things (Brewfest tokens also buy pets and clothes)
--   * a count unreadable, and none known missing: Unknown
-- The decor's own tooltip is not read here: its owned line leaves out granted
-- copies not yet placed (contract rule 20), and the catalog count was right
-- on every one of the 149 decor items where the two differed.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict

local NAMED = 2   -- decor named in the reason

local function DecorName(itemID)
  local facts = Recollect.Facts.Item.Get(itemID)
  return facts and facts.name or ("decor " .. itemID)
end

R.Register({
  key = "buysDecor",
  accountWide = true,   -- the housing catalog is the account's
  label = "Buys decor",
  order = 7,
  Evaluate = function(ctx)
    local relations = Recollect.Facts.Relations.Of(ctx.stack.itemID, "buysDecor")
    if #relations == 0 then return nil end
    local missing, owned, unread, names = 0, 0, 0, {}
    for _, relation in ipairs(relations) do
      local count = R.DecorOwned(relation.id)
      if count == nil then
        unread = unread + 1
      elseif count > 0 then
        owned = owned + 1
      else
        missing = missing + 1
        if #names < NAMED then names[#names + 1] = ("%s (%d)"):format(DecorName(relation.id), relation.count or 1) end
      end
    end
    if missing > 0 then
      local more = missing - #names
      return R.Result(V.USEFUL, ("Buys %d decor you don't own: %s%s"):format(missing, table.concat(names, ", "),
        more > 0 and (" and %d more"):format(more) or ""))
    end
    if unread > 0 then return R.Unknown("Buys decor whose owned count can't be read") end
    return R.Unknown(("Buys %d decor, all of which you own; anything else it buys isn't checked yet"):format(owned))
  end,
})
