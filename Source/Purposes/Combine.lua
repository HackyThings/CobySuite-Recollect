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
-- softens it under a season result. Its progress Unknown carries settled
-- when what the combine leads to is settled (the "leads" check below).
--
-- The "leads" check (Task #438, the Diver's Key Fragment; contract rule 39
-- through a combine): what the item's confirmed combines (m, e codes, on any
-- client language) lead to, followed by Facts.Chains: the product's own
-- purchases and quests, the treasure a product key opens and what it holds,
-- what a product container can give. Only the ends reached by combining the
-- item count here; its own quests and purchases are other checks'.
--   an end that is a collectible still missing, every link read and serving
--   the owner, no one-time step on the way done (a quest completed, a
--   treasure looted)                                Useful, naming the end
--   no end open, one that can't be read yet          Unknown, naming it
--   no end open or unread, one done (the end had,
--   or a step on the way done)                       Unknown, settled
--   every end plain or for someone else, or none     nothing
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

-- What the item's combines lead to (the "leads" check), read once per
-- evaluation and kept on ctx for the Combine check: a Facts.Chains summary of
-- the ends reached by combining it, or nil
local MAX_LOADS = 8   -- end items asked for per evaluation; their arrival reads it again
local function CombineEnd(entry) return entry.via[1] ~= nil and entry.via[1].kind == "makes" end
local function Owner(ctx)
  return ctx.owner or { faction = ctx.playerFaction, isViewer = not ctx.otherCharacter, name = ctx.otherCharacter }
end
-- Whether the item has a confirmed combine the chains can follow (a cheap
-- read of its own codes, so most items never build a chain)
local function Combines(itemID)
  local Relations = Recollect.Facts.Relations
  for _, kind in ipairs({ "makes", "partOf" }) do
    for _, relation in ipairs(Relations.Of(itemID, kind)) do
      if not relation.unresolved and Recollect.Utilities.IsPositiveID(relation.id) then return true end
    end
  end
  return false
end

local function LeadsOf(ctx)
  local owner = Owner(ctx)
  if ctx.combineLeads ~= nil then return ctx.combineLeads or nil, owner end
  if not Combines(ctx.stack.itemID) then
    ctx.combineLeads = false
    return nil, owner
  end
  local summary = Recollect.Facts.Chains.Summary(ctx.stack.itemID, owner, Recollect.Facts.QuestInfo.FrameBudget(), nil,
    CombineEnd)
  for i = 1, math.min(summary and #summary.loading or 0, MAX_LOADS) do Recollect.Facts.Item.Get(summary.loading[i]) end
  ctx.combineLeads = summary or false
  return summary, owner
end

-- Whether every end the combines reach is settled: none open or unread, one done
local function LeadsSettled(summary)
  return summary ~= nil and summary.open == 0 and summary.unread == 0 and summary.done > 0
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
    -- the combine its Use names is gone from the game (every m code flagged x):
    -- the removed check speaks (Task #446)
    if R.AllGone(itemID, { "makes" }) then return nil end
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
      local result = R.Unknown(("You have %d of the %d it takes%s"):format(inAll, need, where and (", " .. where) or ""), headline)
      -- what combining it leads to is done: the combine is only the way there
      if LeadsSettled(LeadsOf(ctx)) then result.settled = true end
      return result
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

R.Register({
  key = "leads",
  label = "Leads to",
  order = 62,   -- before Parts and Combine: where combining it leads says the most
  Evaluate = function(ctx)
    local summary, owner = LeadsOf(ctx)
    if not summary then return nil end
    local Chains = Recollect.Facts.Chains
    local open = summary.first.open
    if open then
      local more = summary.open > 1 and ("; and %d more"):format(summary.open - 1) or ""
      return R.Result(V.USEFUL, "Leads to " .. Chains.Words(open.entry, owner, open.thing, open.quests) .. more,
        "Leads to " .. Chains.ThingWords(open.thing))
    end
    local unread = summary.first.unread
    if unread then
      local category = (not owner.isViewer and "character") or (#summary.loading > 0 and "loading")
        or (not Recollect.Facts.Ready.Quests() and "loading") or "unreadable"
      local headline = unread.thing and ("Leads to " .. Chains.ThingWords(unread.thing)) or nil
      return R.Unknown("Leads to " .. Chains.Words(unread.entry, owner, unread.thing, unread.quests)
        .. "; part of the way can't be read yet", headline, category)
    end
    if LeadsSettled(summary) then
      local done = summary.first.done
      local result = R.Unknown("Leads to " .. Chains.Words(done.entry, owner, done.thing, done.quests),
        "Leads to " .. Chains.ThingWords(done.thing))
      result.settled = true
      return result
    end
    return nil
  end,
})
