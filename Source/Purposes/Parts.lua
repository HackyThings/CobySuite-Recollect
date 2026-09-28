-------------------------------------------------------------------------------
-- Purpose: one of several different parts that combine into one item ("Use:
-- Combine the Reinforced Amani Haft, Tempered Amani Spearhead, and Toughened
-- Amani Leather Wrap to reform the Amani Warrior's Spear.")
--
-- The parts and the product come from the data (Facts.Relations "partOf",
-- read from the Use text when the data was built), so this runs on any
-- client language. Every part's count is read with the bank and the warband
-- bank included:
--   every part held, all in your bags, and the item usable   Use now
--   every part held, some in a bank                          Use now, with
--                                                            how many to
--                                                            take out first
--   a part still missing                                     Useful: what it
--                                                            makes, how many
--                                                            of the parts you
--                                                            have, which to get
--   a count that can't be read                               Unknown
-- The reason names the product, never the Use line itself.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber

local function Count(client, itemID, ...)
  local ok, n = Try(client.GetItemCount, itemID, ...)
  return ok and IsFiniteNumber(n) and n >= 0 and n or nil
end

local function Name(itemID)
  return Recollect.Facts.Item.Name(itemID) or ("item " .. itemID)
end

-- "A", "A and B", "A, B and C"
local function Join(names)
  if #names <= 1 then return names[1] or "" end
  return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- A part's words: its name, with how many when more than one
local function PartWords(part)
  return part.count > 1 and ("%d %s"):format(part.count, Name(part.itemID)) or Name(part.itemID)
end

R.Register({
  key = "parts",
  label = "Parts",
  order = 63,   -- before Combine and the Use effect: what the parts make says the most
  Evaluate = function(ctx)
    local itemID = ctx.stack.itemID
    local relation = Recollect.Facts.Relations.Of(itemID, "partOf")[1]
    if not relation then return nil end
    local client = Recollect.Purposes.client
    local product = Name(relation.id)
    local total = #relation.parts
    local missing, toTake, held = {}, 0, 0
    for _, part in ipairs(relation.parts) do
      local bags, all = Count(client, part.itemID), Count(client, part.itemID, true, false, true, true)
      if not bags or not all then
        return R.Unknown(("How many of the %d parts of %s you have can't be read"):format(total, product),
          "Part of " .. product, "unreadable")
      end
      if all < part.count then
        missing[#missing + 1] = PartWords(part)
      else
        held = held + 1
        if bags < part.count then toTake = toTake + (part.count - bags) end
      end
    end
    if #missing > 0 then
      return R.Result(V.USEFUL, ("One of %d parts that combine into %s; you have %d of them, still to get: %s")
        :format(total, product, held, Join(missing)))
    end
    -- whether it can be used at all is read wherever the parts are
    local okUse, usable = Try(client.IsUsableItem, itemID)
    if not okUse or usable ~= true then
      return R.Result(V.USEFUL, ("You have all %d parts of %s, but it can't be used right now"):format(total, product))
    end
    if toTake > 0 then
      return R.Result(V.USE, ("You have all %d parts of %s; take %d out of your bank first, then use it to combine them")
        :format(total, product, toTake))
    end
    return R.Result(V.USE, ("You have all %d parts of %s in your bags; use it to combine them"):format(total, product))
  end,
})

Recollect.Purposes.Parts = { Join = Join, PartWords = PartWords }
