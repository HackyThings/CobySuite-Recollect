-------------------------------------------------------------------------------
-- Purpose: an item that buys mounts or pets (Facts.Journals)
--
-- For every collectible the journals list this item as a cost of, its state
-- (Registry.CollectibleState: a mount collected, or not available to this
-- character; a pet collected).
-- Any collectible still to get: Needed, naming a few with their cost. All of
-- them collected: Unknown, since the journals list only mounts and pets and
-- the item may buy other things. A collectible that a confirmed Data.Uses
-- entry already links to this item is left to that check. Until the index is
-- built (a moment after login) every item is Unknown here, so no item shows
-- Outdated or Purpose done before its costs are known.
-- An index with entries that couldn't be read (Facts.Journals.Incomplete,
-- BA-02 / CR-02) can't clear an item: one missing from it, or one whose
-- every target is a known use's, stays Unknown here; a collectible still to
-- get wins as always.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict

local NAMED = 2   -- collectibles named in the reason

-- Targets a confirmed known use already covers for this item
local function Covered(itemID)
  local covered = {}
  for _, entry in ipairs(Recollect.Purposes.KnownUse.EntriesFor(itemID)) do
    local target = entry.target or {}
    if target.mount then covered["mount:" .. target.mount] = true end
    if target.pet then covered["pet:" .. target.pet] = true end
  end
  return covered
end

local function Tally(ctx, targets)
  local covered = Covered(ctx.stack.itemID)
  local t = { have = 0, missing = 0, unavailable = 0, unread = 0, names = {} }
  for _, target in ipairs(targets) do
    if not covered[target.kind .. ":" .. target.id] then
      local state, name = R.CollectibleState(target, ctx.playerFaction, not ctx.otherCharacter)
      if not state then
        t.unread = t.unread + 1
      else
        t[state] = t[state] + 1
        if state == "missing" and #t.names < NAMED then
          t.names[#t.names + 1] = ("%s (%d)"):format(tostring(name or (target.kind .. " " .. target.id)), target.count)
        end
      end
    end
  end
  return t
end

R.Register({
  key = "currency",
  accountWide = true,   -- the same answer for any character's copy
  label = "Buys collectibles",
  order = 6,
  Evaluate = function(ctx)
    local index = Recollect.Facts.Journals.Get()
    if not index then return R.Unknown("The collection journals are still being read", nil, "loading") end
    local partial = Recollect.Facts.Journals.Incomplete() > 0
    local PARTIAL = "some collection journal entries couldn't be read, so what else it buys isn't known"
    local targets = index[ctx.stack.itemID]
    if not targets then
      if partial then return R.Unknown("Whether it buys a mount or pet can't be told: " .. PARTIAL, nil, "unreadable") end
      return nil
    end
    local t = Tally(ctx, targets)
    local total = t.have + t.missing + t.unavailable + t.unread
    if total == 0 then
      -- every one is a confirmed known use's
      if partial then return R.Unknown("Its journal costs are known uses; " .. PARTIAL, nil, "unreadable") end
      return nil
    end
    if t.missing > 0 then
      local more = t.missing - #t.names
      return R.Result(V.NEEDED, ("Buys %d %s you don't have: %s%s"):format(t.missing,
        t.missing == 1 and "collectible" or "collectibles", table.concat(t.names, ", "),
        more > 0 and (" and %d more"):format(more) or ""))
    end
    if t.unread > 0 then return R.Unknown("Buys collectibles whose collection can't be read yet", nil, "loading") end
    local what = ("Buys %d %s"):format(total, total == 1 and "mount or pet" or "mounts and pets")
    if partial then return R.Unknown(what .. ", all in your collection or not available to you; " .. PARTIAL, what, "unreadable") end
    return R.Unknown(what .. ", all in your collection or not available to you; anything else it buys isn't checked yet", what)
  end,
})
