-------------------------------------------------------------------------------
-- Purpose: a key that opens something, or an item used at an NPC
-- (Facts.Relations "opens" and "usedAt", from AllTheThings)
--
-- An opened object's place, loot quest and contents come from
-- Facts.Vendors.Object; the loot quest's state is read live, once the quest
-- history has loaded (Facts.Ready.Quests: before that the flag reads false
-- for a treasure already looted, BA-03):
--   a treasure you haven't looted                  Useful, naming where
--   every one looted                               Unknown, "Opens a treasure
--                                                  in Zone": the key may open
--                                                  another, or respawn; settled
--                                                  unless it is also used at an
--                                                  NPC
--   no loot quest to read, or history loading      Unknown, the same headline
--   only NPCs it is used at                        Unknown, "Used at Name"
-- An object with no known position still counts; it just names no place.
-- A route no longer in the game, or of another faction or class
-- (Relations.Applies), never counts. The loot quest is this character's, so
-- another character's copy is not judged here.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try

-- "Zone (x, y)" and the zone, or nil for an object with no known place
local function Where(object)
  if not object.mapID then return nil, nil end
  local zone = Recollect.Facts.Vendors.ZoneName(object.mapID) or ("map " .. object.mapID)
  return ("%s (%.1f, %.1f)"):format(zone, object.x * 100, object.y * 100), zone
end

-- What a treasure holds, in words (Cobanyte, 2026-09-28: say what it gives,
-- or that it can give several things): ", which holds Amani War Axe",
-- ", which can hold Axe, Spear or Bow", ", which can hold any of 12 items";
-- "" for a spot with no known contents. Names are read live; one not loaded
-- yet is counted instead of named.
local HOLDS_NAMED = 3
local function Holds(object)
  local n = #object.contents
  if n == 0 then return "" end
  local Name = Recollect.Facts.Item.Name
  if n == 1 then
    local name = Name(object.contents[1])
    return name and (", which holds " .. name) or ", which holds 1 item"
  end
  if n <= HOLDS_NAMED then
    local names = {}
    for i, itemID in ipairs(object.contents) do
      names[i] = Name(itemID)
      if not names[i] then return (", which can hold any of %d items"):format(n) end
    end
    return (", which can hold %s or %s"):format(table.concat(names, ", ", 1, n - 1), names[n])
  end
  return (", which can hold any of %d items"):format(n)
end

-- Shared with the details window's explanation (UI.DetailWindow)
Recollect.Purposes.Opens = { Holds = Holds }

R.Register({
  key = "opens",
  label = "Opens",
  order = 9,
  Evaluate = function(ctx)
    local Relations = Recollect.Facts.Relations
    local owner = ctx.owner or { faction = ctx.playerFaction }
    local opens, usedAt = {}, {}
    for _, relation in ipairs(Relations.Of(ctx.stack.itemID, "opens")) do
      if Relations.Applies(relation, owner) == true then opens[#opens + 1] = relation end
    end
    for _, relation in ipairs(Relations.Of(ctx.stack.itemID, "usedAt")) do
      if Relations.Applies(relation, owner) == true then usedAt[#usedAt + 1] = relation end
    end
    if #opens == 0 and #usedAt == 0 then return nil end
    local questsReady = Recollect.Facts.Ready.Quests()
    local open, looted, unread
    for _, relation in ipairs(opens) do
      local object = Recollect.Facts.Vendors.Object(relation.id)
      if object then
        local done
        if object.questID and questsReady then
          local ok, value = Try(Recollect.Purposes.client.IsQuestFlaggedCompleted, object.questID)
          if ok and type(value) == "boolean" then done = value end
        end
        if done == false then open = open or object
        elseif done == true then looted = looted or object
        else unread = unread or object end
      end
    end
    local noun = function(object) return #object.contents > 0 and "a treasure" or "a spot" end
    if open then
      local where, zone = Where(open)
      local opens = where and ("Opens %s in %s you haven't looted yet"):format(noun(open), where)
        or ("Opens %s you haven't looted yet"):format(noun(open))
      -- the band's short why names the zone, never the spot (Task #262)
      return R.Result(V.USEFUL, opens .. Holds(open), zone and ("Opens %s in %s you haven't looted yet"):format(noun(open), zone)
        or opens)
    end
    local any = unread or looted
    if any then
      local _, zone = Where(any)
      local headline = (zone and ("Opens %s in %s"):format(noun(any), zone) or ("Opens %s"):format(noun(any))) .. Holds(any)
      if looted and not unread then
        local result = R.Unknown(headline .. "; you've looted it", headline)
        -- an NPC it is also used at is a use with no state read
        result.settled = #usedAt == 0 or nil
        return result
      end
      if not questsReady and any.questID then return R.Unknown(headline .. "; your quest history hasn't loaded yet", headline, "loading") end
      return R.Unknown(headline .. "; whether you've looted it can't be read", headline)
    end
    local who = Recollect.Facts.Vendors.Describe(usedAt[1] and usedAt[1].id, "an NPC")
    if who then return R.Unknown("Used at " .. who, "Used at " .. who) end
    return R.Unknown("What it opens can't be read")
  end,
})
