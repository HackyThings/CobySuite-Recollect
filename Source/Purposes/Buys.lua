-------------------------------------------------------------------------------
-- Purpose: an item that buys things at vendors (Facts.Relations "buys", from
-- AllTheThings and the Lab's vendor recorder; each thing read live through
-- Facts.Buys)
--
--   anything collectible it buys still missing (a toy, mount, pet, decor,
--   ensemble, heirloom, illusion, a recipe not known)  Useful, naming a few
--   an achievement it counts toward not earned         Useful, naming it
--                                                      (AllTheThings lists
--                                                      what an achievement
--                                                      needs as a cost)
--   plain gear it buys whose appearance you haven't    Useful, naming it
--   collected (the logged-in character's copy; the     ("Buys 3 appearances
--   item's tooltip agreeing, rule 5)                   you haven't collected:
--                                                      ...")
--   a plain item it buys that leads to a collectible   Useful, naming the
--   still missing (Facts.Chains, contract rule 39:     chain ("Buys Phoenix
--   every link read and serving this character, no     Ash Talisman (1),
--   one-time quest on the way done)                    which leads to ...")
--   otherwise                                          Unknown, "Buys N things
--                                                      from M vendors": a
--                                                      plain item it buys may
--                                                      still be wanted
-- Only the first MAX_FOLLOW plain items are followed (Mark of Honor buys
-- thousands); the reason says how many more weren't, and how many chains
-- can't be read yet, never that none leads anywhere. The looks of the first
-- MAX_LOOKS plain items that are gear are read (Facts.Buys.Product, as a
-- recipe's product), asking for at most MAX_LOADS item loads per evaluation;
-- the reason counts the looks you have, can't collect or can't read yet.
-- Each thing is tallied by its state (BA-04): have, missing, not for this
-- character (unavailable), still unread, and unassessed (a recipe on
-- another character's copy). "You have every collectible among them" is
-- said only when every collectible read as owned; otherwise the reason says
-- how many are still unread or unassessed.
-- A route no longer in the game is left out entirely (SRC-01); one for
-- another faction or class (Relations.Applies) never makes the item Useful
-- and is only counted in the reason. A purchase that takes other costs too
-- ("+") is still a use of this item, never a sign it buys the thing alone.
-- The journals' mounts and pets and the catalog's decor stay with their own
-- checks (Currency, BuysDecor), which also answer.
--
-- Also here, the "removed" check: when every use the data knows is no
-- longer in the game (each use relation's route flagged unavailable, a
-- quest's on any code naming it, Relations.QuestAppliesOf), the item is
-- Outdated, saying what it was for and that it is gone: "Every use Recollect
-- knows is gone from the game: it bought 55 things at 2 vendors (A (100), B
-- (45) and 53 more)". Any use still in the game, even one only linked,
-- keeps it silent. Verdicts.OtherUses still blocks it for a reagent flag or
-- a quest item, and Verdicts.Settle makes it Unknown for an item with a Use
-- effect that nothing else answered. The patch the item itself was removed
-- in (Relations.RemovedIn) is added as a fact. An item the data gives no use
-- at all, only sources, that can no longer be obtained (RemovedIn, at or
-- before this client's patch: Puzzling Cartel Dinar) only informs, saying
-- so, in place of "No check covers this item yet": with no use known,
-- nothing says what it was for, so it is never Outdated.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict

local NAMED = 2   -- things named in the reason
local MAX_FOLLOW = 20   -- plain items followed to what they lead to (Facts.Chains)
local MAX_LOOKS = 120   -- plain items whose look is read, if gear
local MAX_LOADS = 8   -- item loads asked for per evaluation (BA-11)
-- Plain items kept in a tally's plainList: only the first MAX_FOLLOW and
-- MAX_LOOKS are ever read, and t.plain counts them all
local MAX_PLAIN_KEPT = math.max(MAX_FOLLOW, MAX_LOOKS)
-- Inventory types with an appearance to collect: gear's slots and the
-- look-only ones (shirts, tabards)
local LOOK_ONLY = { INVTYPE_BODY = true, INVTYPE_TABARD = true }

-- The things one set of routes buys, each once: a tally by state
local function Tally(relations, owner, seen)
  local t = { have = 0, missing = 0, unavailable = 0, unread = 0, failed = 0, unassessed = 0, plain = 0, total = 0,
    names = {}, vendors = {}, vendorCount = 0 }
  for _, relation in ipairs(relations) do
    local thing = Recollect.Facts.Buys.Resolve(relation, owner)
    if thing and thing.what == "achievement" then
      if thing.state == "missing" then t.achievement = t.achievement or thing
      elseif thing.state == "have" then t.earned = t.earned or thing
      else t.achievementUnread = (t.achievementUnread or 0) + 1 end   -- PI-08
    elseif thing and not seen[thing.key] then
      seen[thing.key] = true
      t.total = t.total + 1
      for _, npc in ipairs(relation.vendors or {}) do
        if not t.vendors[npc] then
          t.vendors[npc] = true
          t.vendorCount = t.vendorCount + 1
        end
      end
      if not thing.collectible then
        t.plain = t.plain + 1
        if t.plain <= MAX_PLAIN_KEPT then
          t.plainList = t.plainList or {}
          t.plainList[#t.plainList + 1] = { thing = thing, relation = relation }
        end
      else
        local state = thing.state or "unread"
        if state == "unread" and thing.failed then state = "failed" end
        t[state] = (t[state] or 0) + 1
        if state == "missing" and #t.names < NAMED then
          local name = Recollect.Facts.Buys.Name(thing) or (thing.what .. " " .. thing.id)
          t.names[#t.names + 1] = ("%s (%d)"):format(name, relation.count or 1)
        end
      end
    end
  end
  return t
end

-- The plain items it buys, followed to what they lead to: the first open
-- chain ({ entry, summary }), how many chains can't be read yet, and how
-- many plain items weren't followed
local function FollowPlain(t, owner, itemID)
  local unread, followed = 0, 0
  for _, p in ipairs(t.plainList or {}) do
    if followed >= MAX_FOLLOW then break end
    followed = followed + 1
    local summary = Recollect.Facts.Chains.Summary(p.thing.id, owner, Recollect.Facts.QuestInfo.FrameBudget(), itemID)
    if summary and summary.best.state == "open" then return p, summary, 0, 0 end
    if summary and summary.unread > 0 then unread = unread + 1 end
  end
  return nil, nil, unread, t.plain - followed
end

-- The looks of the plain gear it buys, for the logged-in character's copy:
-- { missing = { { thing, relation } }, have, uncollectable, waiting, more }
-- (waiting: a look or item still loading or unreadable; more: plain items past
-- MAX_LOOKS). A plain item that isn't gear, or gear with no look (a ring),
-- counts nowhere
local function Looks(t, owner)
  local looks = { missing = {}, have = 0, uncollectable = 0, waiting = 0, more = 0 }
  local client, Gear, Buys = Recollect.Purposes.client, Recollect.Purposes.Gear, Recollect.Facts.Buys
  local loads = 0
  looks.more = math.max(0, t.plain - MAX_LOOKS)
  for i, p in ipairs(t.plainList or {}) do
    if i > MAX_LOOKS then break end
    local ok, equipLoc = Recollect.Utilities.Try(client.GetItemEquipLoc, p.thing.id)
    if ok and type(equipLoc) == "string" and (Gear.SLOTS[equipLoc] or LOOK_ONLY[equipLoc]) then
      local thing, why = Buys.Product(p.thing.id, owner)
      if thing and thing.what == "appearance" then
        if thing.state == "missing" then looks.missing[#looks.missing + 1] = p
        elseif thing.state == "have" then looks.have = looks.have + 1
        elseif thing.state == "unavailable" then looks.uncollectable = looks.uncollectable + 1
        else looks.waiting = looks.waiting + 1 end
      elseif not thing and why == "loading" then
        -- asked for here, a few per evaluation: its arrival reads it again
        if loads < MAX_LOADS then
          loads = loads + 1
          Recollect.Facts.Item.Get(p.thing.id)
        end
        looks.waiting = looks.waiting + 1
      elseif thing and thing.failed then
        looks.waiting = looks.waiting + 1
      end
    end
  end
  return looks
end

-- "Ceremonial Jacaranda Gown (1), Ceremonial Jacaranda Cape (1 plus 25
-- gold) and 3 more": each price worded as the panel words it
-- (Facts.Chains.CostWords, review F15)
local function LookNames(missing, itemID)
  local names = {}
  for i = 1, math.min(NAMED, #missing) do
    local p = missing[i]
    local name = Recollect.Facts.Buys.Name(p.thing) or ("item " .. p.thing.id)
    names[#names + 1] = ("%s (%d%s)"):format(name, p.relation.count or 1, Recollect.Facts.Chains.CostWords(p.relation, itemID))
  end
  local more = #missing - #names
  return table.concat(names, ", ") .. (more > 0 and (" and %d more"):format(more) or "")
end

-- Words for the looks when none is missing, or nil
local function LookWords(looks)
  if not looks then return nil end
  local parts = {}
  if looks.have > 0 then
    parts[#parts + 1] = ("%d %s gear whose appearance you have"):format(looks.have, looks.have == 1 and "is" or "are")
  end
  if looks.uncollectable > 0 then
    parts[#parts + 1] = ("%d %s gear whose appearance this character can't collect"):format(looks.uncollectable,
      looks.uncollectable == 1 and "is" or "are")
  end
  if looks.waiting > 0 then
    parts[#parts + 1] = ("the appearance of %d can't be read yet"):format(looks.waiting)
  end
  if looks.more > 0 then
    parts[#parts + 1] = ("%d more plain %s checked for an appearance"):format(looks.more,
      looks.more == 1 and "item isn't" or "items aren't")
  end
  return #parts > 0 and table.concat(parts, "; ") or nil
end

-- Words for the plain items' chains when none is open
local function PlainWords(unread, unfollowed)
  local parts = {}
  if unread > 0 then
    parts[#parts + 1] = ("what %d of the plain items %s to can't be read yet"):format(unread, unread == 1 and "leads" or "lead")
  end
  if unfollowed > 0 then
    parts[#parts + 1] = ("what %d more plain %s to isn't checked"):format(unfollowed, unfollowed == 1 and "item leads" or "items lead")
  end
  return #parts > 0 and table.concat(parts, "; ") or nil
end

-- The reason's words for a tally with nothing missing
local function StateWords(t)
  local collectibles = t.have + t.unavailable + t.unread + t.failed + t.unassessed
  if collectibles == 0 then return t.total == 1 and "it isn't a collectible" or "none of them is a collectible" end
  if t.have == collectibles then return "you have every collectible among them" end
  local parts = { ("you have %d of the %d collectibles among them"):format(t.have, collectibles) }
  if t.unread > 0 then parts[#parts + 1] = ("%d can't be read yet"):format(t.unread) end
  if t.failed > 0 then parts[#parts + 1] = ("%d can't be read"):format(t.failed) end
  if t.unassessed > 0 then
    parts[#parts + 1] = ("%d %s known per character and can't be read from here"):format(t.unassessed,
      t.unassessed == 1 and "recipe is" or "recipes are")
  end
  if t.unavailable > 0 then parts[#parts + 1] = ("%d not available to this character"):format(t.unavailable) end
  return table.concat(parts, "; ")
end

-- What routes restrict that the owner fails, and the words for it (PI-14)
local Restrictions, Kinds = R.Restrictions, R.KindWords

-- When every purchase is limited to classes the owner isn't (and nothing
-- else limits them), the words naming those classes and what the data
-- lacks: "all Hunter, Shaman and Evoker only; none recorded yet for
-- Paladin" (Cobanyte, 2026-09-28: a raid curio's vendor shows each class
-- its own armor type's tokens, and the data held only what one class saw).
-- It says what the data holds, never that a vendor sells one for this
-- class. nil when a route has another limit, more than 4 classes, or a
-- name can't be read, so the plain words stay
local MAX_CLASSES_NAMED = 4
local function ClassGap(others, owner)
  local ids, set = {}, {}
  for _, relation in ipairs(others) do
    local flags = relation.flags or {}
    if flags.faction ~= nil or flags.races or not flags.classes then return nil end
    for id in pairs(flags.classes) do
      if not set[id] then set[id], ids[#ids + 1] = true, id end
    end
  end
  if #ids == 0 or #ids > MAX_CLASSES_NAMED or not owner or owner.classID == nil then return nil end
  table.sort(ids)
  local function Name(classID)
    local ok, name = Recollect.Utilities.Try(Recollect.Purposes.client.GetClassName, classID)
    return ok and type(name) == "string" and name ~= "" and name or nil
  end
  local names = {}
  for _, id in ipairs(ids) do
    local name = Name(id)
    if not name then return nil end
    names[#names + 1] = name
  end
  local own = Name(owner.classID)
  if not own then return nil end
  local list = #names == 1 and names[1]
    or (table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names])
  return ("all %s only; none recorded yet for %s"):format(list, own)
end

-- The check's answer for one list of relations and owner
local function Answer(relations, owner, itemID)
  local Relations = Recollect.Facts.Relations
  do
    -- serving this character, for another (a verified mismatch), or not told
    -- (the owner's record lacks what a route is restricted by, PI-14)
    local serving, others, untold = {}, {}, {}
    for _, relation in ipairs(relations) do
      if relation.kind == "buys" then
        local applies = Relations.Applies(relation, owner)
        if applies == true then serving[#serving + 1] = relation
        elseif applies == nil then untold[#untold + 1] = relation
        elseif applies ~= "unavailable" then others[#others + 1] = relation end
      end
    end
    if #serving == 0 and #others == 0 and #untold == 0 then return nil end
    local seen = {}
    local t = Tally(serving, owner, seen)
    local o = Tally(others, owner, seen)
    local u = Tally(untold, owner, seen)
    local mismatch = Restrictions(others, owner)
    local _, unknown = Restrictions(untold, owner)
    local untoldWords = u.total > 0 and ("%d more depend on this character's %s, not recorded yet (log in to it once)")
      :format(u.total, Kinds(unknown)) or nil
    if t.missing > 0 then
      local more = t.missing - #t.names
      return R.Result(V.USEFUL, ("Buys %d you don't have yet: %s%s"):format(t.missing, table.concat(t.names, ", "),
        more > 0 and (" and %d more"):format(more) or ""))
    end
    if t.achievement then
      return R.Result(V.USEFUL, ("Counts toward \"%s\", which you haven't earned"):format(t.achievement.name or "an achievement"))
    end
    -- plain gear it buys with a look still to collect: only the logged-in
    -- character's copy, since whether a look can be collected is that
    -- character's (playerCanCollect)
    local looks = owner.isViewer and t.plain > 0 and Looks(t, owner) or nil
    if looks and #looks.missing > 0 then
      return R.Result(V.USEFUL, ("Buys %d %s you haven't collected: %s"):format(#looks.missing,
        #looks.missing == 1 and "appearance" or "appearances", LookNames(looks.missing, itemID)))
    end
    -- a plain item it buys that leads to a collectible still missing (rule 39)
    local open, summary, chainUnread, unfollowed = FollowPlain(t, owner, itemID)
    if open then
      local Chains, best = Recollect.Facts.Chains, summary.best
      local name = Recollect.Facts.Buys.Name(open.thing) or ("item " .. open.thing.id)
      return R.Result(V.USEFUL, ("Buys %s (%d%s), which leads to %s"):format(name, open.relation.count or 1,
        Chains.CostWords(open.relation, itemID), Chains.Words(best.entry, owner, best.thing, best.quests)))
    end
    local plainWords = PlainWords(chainUnread, unfollowed)
    local otherWords = o.total > 0 and ("%d more for another %s"):format(o.total, Kinds(mismatch)) or nil
    if t.total == 0 then
      -- an achievement whose state can't be read holds an earned one's note back (PI-08)
      if t.achievementUnread then
        return R.Unknown("Whether it still counts toward an achievement can't be read yet", nil, "loading")
      end
      if t.earned and u.total == 0 then return R.Info(("Counts toward \"%s\", which you've earned"):format(t.earned.name or "an achievement")) end
      if u.total > 0 then
        local headline = ("Buys %d %s this character's record can't match yet"):format(u.total, u.total == 1 and "thing" or "things")
        return R.Unknown(headline .. "; " .. untoldWords .. (otherWords and ("; " .. otherWords) or ""), headline, "character")
      end
      if o.total > 0 then
        local gap = ClassGap(others, owner)
        local headline = gap and ("Buys %d %s, %s"):format(o.total, o.total == 1 and "thing" or "things", gap)
          or ("Buys %d %s for another %s"):format(o.total, o.total == 1 and "thing" or "things", Kinds(mismatch))
        return R.Unknown(headline, headline)
      end
      return R.Unknown("What it buys can't be read yet", nil, "unreadable")
    end
    local headline = ("Buys %d %s"):format(t.total, t.total == 1 and "thing" or "things")
    if t.vendorCount > 0 then headline = headline .. (" from %d %s"):format(t.vendorCount, t.vendorCount == 1 and "vendor" or "vendors") end
    local lookWords = LookWords(looks)
    local reason = headline .. "; " .. StateWords(t) .. (lookWords and ("; " .. lookWords) or "")
      .. (plainWords and ("; " .. plainWords) or "")
      .. (otherWords and ("; " .. otherWords) or "") .. (untoldWords and ("; " .. untoldWords) or "")
    local category = ((t.unread > 0 or chainUnread > 0 or (looks and looks.waiting > 0)) and "loading")
      or (t.failed > 0 and "unreadable") or (t.unassessed > 0 and "character") or nil
    return R.Unknown(reason, headline, category)
  end
end

-- Answers kept while every thing's state is (Facts.Buys.Stamp: until data
-- changes or its memo's seconds pass), per parsed list and owner: Mark of
-- Honor's purchases (about 8,700) are tallied once, not at every redraw. Each call
-- gets a copy, since a check's result is written to (Verdicts.RunCheck).
local answers, answersStamp = nil, nil
local function Kept(relations, owner, itemID)
  local stamp = Recollect.Facts.Buys.Stamp()
  if stamp ~= answersStamp then answers, answersStamp = setmetatable({}, { __mode = "k" }), stamp end
  local byOwner = answers[relations]
  if not byOwner then
    byOwner = {}
    answers[relations] = byOwner
  end
  local key = ("%s:%s"):format(owner.isViewer and "viewer" or tostring(owner.guid or owner.name), tostring(owner.faction))
  local result = byOwner[key]
  if result == nil then
    result = Answer(relations, owner, itemID) or false
    byOwner[key] = result
  end
  if not result then return nil end
  local copy = {}
  for k, v in pairs(result) do copy[k] = v end
  return copy
end

R.Register({
  key = "buys",
  accountWide = true,   -- collections and achievements are the account's
  label = "Buys",
  order = 8,
  Evaluate = function(ctx)
    local owner = ctx.owner or { faction = ctx.playerFaction, isViewer = not ctx.otherCharacter, name = ctx.otherCharacter }
    return Kept(Recollect.Facts.Relations.For(ctx.stack.itemID), owner, ctx.stack.itemID)
  end,
})

-------------------------------------------------------------------------------
-- Every use gone: the "removed" check (contract rule 42)
-------------------------------------------------------------------------------
local QUEST_USES = { objective = true, questItem = true, starts = true }
local REMOVED_WORDS = {
  quests = { "it was used in %d quest", "it was used in %d quests" },
  opens = { "it opened %d treasure", "it opened %d treasures" },
  usedAt = { "it was used at %d NPC", "it was used at %d NPCs" },
  achievements = { "it counted toward %d achievement", "it counted toward %d achievements" },
  other = { "%d other use", "%d other uses" },
}
local ACHIEVEMENT_USES = { criterion = true, linked = true }

local function Counted(kind, n)
  local words = REMOVED_WORDS[kind]
  return (n == 1 and words[1] or words[2]):format(n)
end

-- Every use relation of the item, when each one is no longer in the game:
-- { buys = { relation }, quests, opens, usedAt, achievements, other } counts;
-- nil when there is none or any use is still in the game. A use that isn't
-- a quest is checked first, so an item with a live purchase (Mark of
-- Honor's thousands) stops at its first relation, before the quests are read
local function RemovedUses(relations, owner)
  local Relations = Recollect.Facts.Relations
  local anyQuest = false
  for _, relation in ipairs(relations) do
    if not Relations.SOURCE[relation.kind] then
      if QUEST_USES[relation.kind] then
        anyQuest = true
      elseif not (relation.flags ~= nil and relation.flags.unavailable == true) then
        return nil
      end
    end
  end
  local quests = anyQuest and Relations.QuestAppliesOf(relations, owner) or {}
  local gone = { buys = {}, quests = 0, opens = 0, usedAt = 0, achievements = 0, other = 0, total = 0 }
  local seenQuest = {}
  for _, relation in ipairs(relations) do
    if not Relations.SOURCE[relation.kind] then
      local removed
      if QUEST_USES[relation.kind] then
        removed = quests[relation.id] == "unavailable"
      else
        removed = relation.flags ~= nil and relation.flags.unavailable == true
      end
      if not removed then return nil end
      gone.total = gone.total + 1
      -- grouped as the panel's closing line groups them (UI.UsedFor's
      -- GoneGroup): a cost that counted toward an achievement (thing "a")
      -- was never bought, and decor it bought is a purchase
      if relation.kind == "buys" and relation.thing == "a" then
        gone.achievements = gone.achievements + 1
      elseif relation.kind == "buys" or relation.kind == "buysDecor" then
        gone.buys[#gone.buys + 1] = relation
      elseif QUEST_USES[relation.kind] then
        if not seenQuest[relation.id] then
          seenQuest[relation.id] = true
          gone.quests = gone.quests + 1
        end
      elseif relation.kind == "opens" or relation.kind == "usedAt" then
        gone[relation.kind] = gone[relation.kind] + 1
      elseif ACHIEVEMENT_USES[relation.kind] then
        gone.achievements = gone.achievements + 1
      else
        gone.other = gone.other + 1
      end
    end
  end
  return gone.total > 0 and gone or nil
end

-- "it bought 55 things at 2 vendors (A (100), B (45) and 53 more)", each
-- thing once however many vendors sold it
local function BoughtWords(list, owner)
  local seen, names, count, vendors, vendorCount = {}, {}, 0, {}, 0
  for _, relation in ipairs(list) do
    for _, npc in ipairs(relation.vendors or {}) do
      if not vendors[npc] then
        vendors[npc] = true
        vendorCount = vendorCount + 1
      end
    end
    local key = tostring(relation.thing) .. ":" .. tostring(relation.id)
    if not seen[key] then
      seen[key] = true
      count = count + 1
      if #names < NAMED then
        local thing = Recollect.Facts.Buys.Resolve(relation, owner)
        local name = thing and Recollect.Facts.Buys.Name(thing)
        if name then names[#names + 1] = ("%s (%d)"):format(name, relation.count or 1) end
      end
    end
  end
  local at = vendorCount > 0 and ("%d %s"):format(vendorCount, vendorCount == 1 and "vendor" or "vendors") or "vendors"
  local text = ("it bought %d %s at %s"):format(count, count == 1 and "thing" or "things", at)
  if #names > 0 then
    local more = count - #names
    text = text .. (" (%s%s)"):format(table.concat(names, ", "), more > 0 and (" and %d more"):format(more) or "")
  end
  return text
end

-- The answer for an item with no use relation that can no longer be
-- obtained: informs only; nil for any other
local function NoUse(ctx, relations)
  local SOURCE = Recollect.Facts.Relations.SOURCE
  for _, relation in ipairs(relations) do
    if not SOURCE[relation.kind] then return nil end
  end
  local Season = Recollect.Purposes.Season
  local patch = Season and Season.RemovedIn(ctx.stack.itemID)
  if not patch then return nil end
  local okKnown, known = pcall(Recollect.Purposes.KnownUse.EntriesFor, ctx.stack.itemID)
  if not okKnown or (type(known) == "table" and #known > 0) then return nil end
  -- the words of COMES FROM's removal line, which then shows it once (review F11)
  return R.Info(("Can no longer be obtained (removed in patch %s)"):format(Season.PatchText(patch)))
end

R.Register({
  key = "removed",
  accountWide = true,   -- the data's routes are the same for every character
  label = "No longer available",
  order = 9,
  Evaluate = function(ctx)
    local owner = ctx.owner or { faction = ctx.playerFaction, isViewer = not ctx.otherCharacter, name = ctx.otherCharacter }
    local relations = Recollect.Facts.Relations.For(ctx.stack.itemID)
    local gone = RemovedUses(relations, owner)
    if not gone then return NoUse(ctx, relations) end
    -- a confirmed known use (Data.Uses) is a use the data's routes don't
    -- list: its own check answers, and nothing here says every use is gone
    local okKnown, known = pcall(Recollect.Purposes.KnownUse.EntriesFor, ctx.stack.itemID)
    if not okKnown or (type(known) == "table" and #known > 0) then return nil end
    local parts = {}
    if #gone.buys > 0 then parts[#parts + 1] = BoughtWords(gone.buys, owner) end
    for _, kind in ipairs({ "quests", "opens", "usedAt", "achievements", "other" }) do
      if gone[kind] > 0 then parts[#parts + 1] = Counted(kind, gone[kind]) end
    end
    local Season = Recollect.Purposes.Season
    local removedIn = Season and Season.RemovedWords(ctx.stack.itemID) or ""
    return R.Result(V.OUTDATED, "Every use Recollect knows is gone from the game: " .. table.concat(parts, "; ") .. removedIn)
  end,
})
