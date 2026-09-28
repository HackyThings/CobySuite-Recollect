-------------------------------------------------------------------------------
-- Purpose: an item whose Use line combines several copies ("Use: Combine 50
-- Leftover Elemental Slimes to create something new.")
--
-- The count is read from the tooltip's own Use line (the line that starts
-- with ITEM_SPELL_TRIGGER_ONUSE). The verbs are English, so this check runs
-- on English clients only; elsewhere it stays silent and the item is covered
-- by whatever else applies. A count may be digits or a word from WORDS
-- (two to ten, twelve, fifteen, twenty: "Combine two"); any other word is
-- not read.
--   enough in your bags and the item usable (C_Item.IsUsableItem)   Use now
--   enough counting the bank, fewer in your bags                   Use now,
--                                                                  "move N to your bags first"
--   fewer than the Use line needs                                  Unknown,
--                                                                  with both counts
-- An Unknown carries a headline for the audit panel: "Combine 30 into
-- <product>" when Facts.Relations names what it makes, "Combine 3 of these;
-- what they make is unconfirmed" when the sources disagree on the product
-- (an "mx3" relation, CR-01: neither product is named), else "Collect 30 to
-- combine" (never the Use line itself, which the tooltip shows). A Use line
-- that is loading, or failed to load, may say "Combine": Unknown then. A
-- count or usable read that fails carries readOwed, so Verdicts.Settle never
-- softens it under a season result.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber

local PATTERNS = { "Combines? (%w+)", "Assemble (%w+)", "Piece together (%w+)", "Weave (%w+)" }
local WORDS = { two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9, ten = 10,
  twelve = 12, fifteen = 15, twenty = 20 }

-- The count a Use line combines ("Combine 50", "Combine six", "Weave 15"), or nil
local function CombineCount(useText)
  for _, pattern in ipairs(PATTERNS) do
    local word = useText:match(pattern)
    local n = word and (tonumber(word) or WORDS[word:lower()])
    if n and n > 1 then return n end
  end
  return nil
end

-- What the item is used for, for the panel: combining into the product the
-- relations name, else combining
local function Headline(itemID, need)
  local made = Recollect.Facts.Relations.Of(itemID, "makes")[1]
  if made and made.unresolved then return ("Combine %d of these; what they make is unconfirmed"):format(need) end
  local name = made and Recollect.Facts.Item.Name(made.id)
  if name then return ("Combine %d into %s"):format(need, name) end
  return ("Collect %d to combine"):format(need)
end

local PLACES = { "in your bags", "in your bank", "in the warband bank" }

-- Where the copies are: "all in your bank", "3 in your bags, 1 in the warband
-- bank"; with no bank count, only the bags are named; nil when none is held
local function Where(inBags, inBank, inAll)
  if inAll <= 0 then return nil end
  if not inBank or inBank < inBags or inBank > inAll then
    if inBags == inAll then return "all in your bags" end
    return inBags == 0 and "none in your bags" or ("%d in your bags"):format(inBags)
  end
  local counts, held = { inBags, inBank - inBags, inAll - inBank }, {}
  for i, n in ipairs(counts) do
    if n > 0 then held[#held + 1] = i end
  end
  if #held == 1 then return "all " .. PLACES[held[1]] end
  local parts = {}
  for _, i in ipairs(held) do parts[#parts + 1] = counts[i] .. " " .. PLACES[i] end
  return table.concat(parts, ", ")
end

R.Register({
  key = "combine",
  label = "Combine",
  order = 64,   -- before Consumable: its counts say more than the consumable's age
  Evaluate = function(ctx)
    local client = Recollect.Purposes.client
    if not R.EnglishClient() then return nil end
    local tip = ctx.Tooltip()
    if not tip or type(tip.useText) ~= "string" then
      -- A Use line still loading may say "Combine": hold other checks back
      if ctx.facts.spellLoading then return R.Unknown("Its Use line is still loading", nil, "loading") end
      if ctx.facts.spellFailed then return R.Unknown("Its Use line can't be loaded", nil, "unreadable") end
      -- whether it has a Use line at all couldn't be read: it may combine
      if tip and ctx.facts.hasSpell == nil then return R.Unknown("Whether it has a Use line can't be read", nil, "unreadable") end
      return nil
    end
    local need = CombineCount(tip.useText)
    if not need then return nil end
    local itemID = ctx.stack.itemID
    local headline = Headline(itemID, need)
    local okBags, inBags = Try(client.GetItemCount, itemID)
    local okAll, inAll = Try(client.GetItemCount, itemID, true, false, true, true)
    if not okBags or not okAll or not IsFiniteNumber(inBags) or not IsFiniteNumber(inAll) then
      -- a failed read, not a use's progress: readOwed keeps a season result
      -- from softening it (Verdicts.Settle)
      local result = R.Unknown("It takes " .. need .. "; how many you hold can't be read", headline)
      result.readOwed = true
      return result
    end
    if inAll < need then
      local okBank, inBank = Try(client.GetItemCount, itemID, true, false, true, false)
      local where = Where(inBags, okBank and IsFiniteNumber(inBank) and inBank or nil, inAll)
      return R.Unknown(("You have %d of the %d it takes%s"):format(inAll, need, where and (", " .. where) or ""), headline)
    end
    local okUse, usable = Try(client.IsUsableItem, itemID)
    if not okUse or usable ~= true then
      local result = R.Unknown(("You have %d of the %d it takes, but it can't be used right now"):format(inAll, need), headline)
      if not okUse then result.readOwed = true end   -- the read failed (as above)
      return result
    end
    if inBags >= need then
      return R.Result(V.USE, ("You have %d in your bags; its Use combines %d"):format(inBags, need))
    end
    return R.Result(V.USE, ("You have %d, enough for its Use to combine %d; move %d to your bags first"):format(
      inAll, need, need - inBags))
  end,
})
