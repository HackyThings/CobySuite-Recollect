-------------------------------------------------------------------------------
-- Facts.Chains: what a quest rewards, and what a plain item a purchase names
-- leads to (contract rule 39)
--
-- Rewards(questID) lists what a quest rewards from the shipped W table
-- (Relations.QuestRewards), each thing as a relation Facts.Buys can read
-- ({ kind = "buys", thing, id }, one table per thing for the session, so
-- Facts.Buys' memo holds), with choice = true for a choice reward.
--
-- Leads(itemID, from) follows a plain item through its own relations, at most
-- MAX_DEPTH items deep (the item, then a plain item it buys or makes), and
-- returns the ends it reaches: { thing (a relation Facts.Buys reads), via =
-- { steps } }, a step being { kind = "quest", questID, of } (of is the item
-- followed; the quest is one it is used in, is an objective of, or starts,
-- and the quest's rewards are the ends), { kind = "makes", itemID,
-- relation } or { kind = "buys", itemID, count, relation }, and since Task
-- #438 { kind = "opens", objectID, of, relation } (a key's object: each
-- item the object holds, Facts.Vendors.Object's contents, is an end) and
-- { kind = "holds", container, relation } (a container item's H codes: each
-- item opening it can give is an end). An end that is an item the data
-- doesn't type (an object's contents, a container's) carries product = its
-- ID, read live through Facts.Buys.Product (a toy, a mount, an appearance...),
-- else a plain item. At most
-- MAX_RELATIONS of an item's relations are looked at and MAX_ENDS ends
-- kept; an item already on the path is never followed again. The structure
-- is the data's alone and kept per item (bounded at KEEP items); states are
-- read at every call.
--
-- State(entry, owner, budget) reads one end now: "open" (every link serves
-- the owner, a quest on the way is not done, on it, repeatable or recurs, a
-- treasure on the way not looted yet, and the end is a collectible still
-- missing), "done" (the end is had, or a one-time quest on the way is done,
-- or a treasure on the way is looted), "other" (a link, or the end's own
-- purchase, is for another faction, class or race, or no longer in the
-- game), "plain" (the end is a plain item with nothing to own, every link
-- read) or "unread" (a link or
-- the end can't be read yet, or is another character's to read), and the
-- thing as Facts.Buys resolved it; a fourth answer is the end's item when it
-- is still loading (the caller asks for it). A treasure's state is its loot
-- quest's, the logged-in character's, read once the quest history has loaded
-- (as Purposes/Opens.lua reads it); one with no loot quest can't be read.
-- Summary(itemID, owner, budget, from, keep) tallies the ends (keep(entry),
-- when given, picks which count) and names the first open one (else the
-- first unread, else any) as best, the first of each state as first[state],
-- and the ends still loading as loading = { itemID }.
-- Words(entry, owner, thing, quests) and ThingWords(thing) word them for a
-- line.
-- SetNamer(fn) lets the panel hear each name the words use (fn(kind, id,
-- name, quality): an item, a quest's title, a thing, a currency), so it can
-- color them as the game colors their links; it returns the namer it replaced.
-- TradeWords(relation, itemID) words what a purchase costs in all, this
-- item first ("50 Mark of Honor and 25 gold"), PriceWords(costs) a seller's whole
-- price ("350 Honor and 10 gold"), and GoldWords(copper) a gold price: the
-- one wording the checks' reasons and the panel share (review F15).
-------------------------------------------------------------------------------
local Chains = {}
Recollect.Facts.Chains = Chains

local IsPositiveID = Recollect.Utilities.IsPositiveID
-- A count as the player reads it, with the game's thousands separators
-- ("1,000 Vile Essence"; Task #438)
local function Count(n) return Recollect.Utilities.Count(n) end

local MAX_DEPTH = 2        -- items followed: the one bought, then one it buys or makes
local MAX_RELATIONS = 200  -- relations of one item looked at
local MAX_ENDS = 6         -- ends kept per item
local KEEP = 400           -- items whose structure is kept

local QUEST_LINKS = { questItem = true, objective = true, starts = true }

local function Relations() return Recollect.Facts.Relations end

-- Who hears the names the words use (UI.UsedFor), or nil
local namer = nil
function Chains.SetNamer(fn)
  local previous = namer
  namer = fn
  return previous
end

local function Named(kind, id, name, quality)
  if namer and name then namer(kind, id, name, quality) end
  return name
end

-- One relation table per typed thing, kept for the session
local pseudo = {}
local function ThingRelation(letter, id)
  local key = letter .. id
  local relation = pseudo[key]
  if not relation then
    relation = { kind = "buys", thing = letter, id = id, count = 1 }
    pseudo[key] = relation
  end
  return relation
end

-- Rewards(questID): { { relation, choice } } or an empty list
local rewardsOf = {}
local keptRewards
local Current
function Chains.Rewards(questID)
  Current()
  local kept = rewardsOf[questID]
  if kept then return kept end
  kept = {}
  for _, entry in ipairs(Relations().QuestRewards(questID) or {}) do
    kept[#kept + 1] = { relation = ThingRelation(entry.thing, entry.id), choice = entry.choice }
  end
  rewardsOf[questID] = kept
  return kept
end

local structures, kept = {}, 0

local function Copy(list, extra)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  out[#out + 1] = extra
  return out
end

-- An end that is an item: typed when the data's K says what it is, else
-- read live as a product (Facts.Buys.Product) when the state is read
local function ItemEnd(itemID, via)
  local letter, id = Relations().ItemThing(itemID)
  if id then return { thing = ThingRelation(letter, id), via = via } end
  return { thing = ThingRelation("", itemID), product = itemID, via = via }
end

local Follow
Follow = function(itemID, depth, via, visited, out)
  visited[itemID] = true
  local relations = Relations().For(itemID)
  for i = 1, math.min(#relations, MAX_RELATIONS) do
    if #out.ends >= MAX_ENDS then return end
    local relation = relations[i]
    local kind = relation.kind
    if QUEST_LINKS[kind] and IsPositiveID(relation.id) then
      local step = { kind = "quest", questID = relation.id, of = itemID }
      for _, reward in ipairs(Chains.Rewards(relation.id)) do
        if #out.ends < MAX_ENDS then
          out.ends[#out.ends + 1] = { thing = reward.relation, choice = reward.choice, via = Copy(via, step) }
        end
      end
    elseif (kind == "makes" or kind == "partOf") and IsPositiveID(relation.id) and not visited[relation.id] then
      local step = { kind = "makes", itemID = relation.id, relation = relation }
      local letter, id = Relations().ItemThing(relation.id)
      if id then
        out.ends[#out.ends + 1] = { thing = ThingRelation(letter, id), via = Copy(via, step) }
      elseif depth < MAX_DEPTH then
        Follow(relation.id, depth + 1, Copy(via, step), visited, out)
      end
    elseif kind == "buys" and relation.thing ~= "a" and IsPositiveID(relation.id) then
      if relation.thing ~= "" then
        out.ends[#out.ends + 1] = { thing = relation, via = via }
      elseif depth < MAX_DEPTH and not visited[relation.id] then
        local step = { kind = "buys", itemID = relation.id, count = relation.count, relation = relation }
        Follow(relation.id, depth + 1, Copy(via, step), visited, out)
      end
    elseif kind == "opens" and IsPositiveID(relation.id) then
      -- a key: what the treasure it opens holds (Task #438, the Diver's Key)
      local object = Recollect.Facts.Vendors.Object(relation.id)
      if object then
        local step = { kind = "opens", objectID = relation.id, of = itemID, relation = relation }
        for _, content in ipairs(object.contents) do
          if #out.ends >= MAX_ENDS then return end
          if not visited[content] then out.ends[#out.ends + 1] = ItemEnd(content, Copy(via, step)) end
        end
      end
    elseif kind == "holds" and IsPositiveID(relation.id) and not visited[relation.id] then
      -- a container: what opening it can give
      out.ends[#out.ends + 1] = ItemEnd(relation.id, Copy(via, { kind = "holds", container = itemID, relation = relation }))
    end
  end
end

-- The kept structures and rewards hold only while the data and its reader
-- are the same (a test that scripts Relations.For never leaves its answers
-- behind for the session)
local keptFor, keptData
Current = function()
  local R = Relations()
  local data = Recollect.Data and Recollect.Data.Relations
  if keptFor ~= R.For or keptData ~= data or keptRewards ~= R.QuestRewards then
    structures, kept, rewardsOf = {}, 0, {}
    keptFor, keptData, keptRewards = R.For, data, R.QuestRewards
  end
end

-- Leads(itemID, from): { ends } for a plain item (see the header); from is
-- an item counted as already on the path
function Chains.Leads(itemID, from)
  if not IsPositiveID(itemID) then return { ends = {} } end
  Current()
  local key = itemID .. ":" .. tostring(from or 0)
  local structure = structures[key]
  if structure then return structure end
  structure = { ends = {} }
  local visited = {}
  if from then visited[from] = true end
  Follow(itemID, 1, {}, visited, structure)
  if kept >= KEEP then structures, kept = {}, 0 end
  structures[key] = structure
  kept = kept + 1
  return structure
end

-- A quest on the way: "open", "done" or "unread", and its facts
local function QuestState(questID, owner, budget)
  if not owner.isViewer then return "unread", nil end   -- quest states are the logged-in character's
  local quest = Recollect.Facts.QuestInfo.Get(questID, budget)
  if not quest then return "unread", nil end
  if quest.onQuest or quest.repeatable then return "open", quest end
  local done = Recollect.Facts.QuestInfo.Done(quest)
  if done and Relations().Frequency(questID) then return "open", quest end
  if done == true then return "done", quest end
  if done == false then return "open", quest end
  return "unread", quest
end

-- Whether a step's relation serves the owner: true, "other" or nil (unread)
local function StepApplies(step, owner)
  if step.kind == "quest" then
    local applies = Relations().QuestApplies(step.of, owner)[step.questID]
    if applies == true then return true end
    if applies == "other" or applies == "unavailable" then return "other" end
    return nil
  end
  local applies = Relations().Applies(step.relation, owner)
  if applies == true then return true end
  if applies == "other" or applies == "unavailable" then return "other" end
  return nil
end

local END_STATE = { missing = "open", have = "done", unavailable = "other" }

-- A treasure on the way: "done" (its loot quest is complete: looted),
-- "open" (not looted yet) or "unread" (no loot quest, the quest history
-- still loading, a read that failed, or another character's copy)
local function LootState(objectID, owner)
  if not owner.isViewer then return "unread" end   -- the loot quest is the logged-in character's
  local object = Recollect.Facts.Vendors.Object(objectID)
  if not object or not object.questID or not Recollect.Facts.Ready.Quests() then return "unread" end
  local ok, done = Recollect.Utilities.Try(Recollect.Purposes.client.IsQuestFlaggedCompleted, object.questID)
  if not ok or type(done) ~= "boolean" then return "unread" end
  return done and "done" or "open"
end
Chains.LootState = LootState

-- The thing an end stands for: the data's typed thing, or for an item the
-- data doesn't type the product read live (a collectible), else the plain
-- item; nil and the item while it is still loading
local function EndThing(entry, owner)
  local Buys = Recollect.Facts.Buys
  if entry.product then
    local thing, why = Buys.Product(entry.product, owner)
    if thing then return thing end
    if why == "loading" then return nil, entry.product end
  end
  return Buys.Resolve(entry.thing, owner)
end

-- State(entry, owner, budget): "open", "done", "other", "plain" or "unread"; the
-- thing Facts.Buys resolved; the quests on the way { [questID] = facts }, with
-- each treasure's loot state under "o<objectID>"; the end's item while it loads
function Chains.State(entry, owner, budget)
  owner = owner or Recollect.Verdicts.Rows.Owner()
  local state, quests = nil, {}
  -- the end's own route: a purchase no longer in the game, or for another
  -- faction, class or race, serves no one here (a quest's rewards carry no
  -- conditions of their own and pass)
  local own = Relations().Applies(entry.thing, owner)
  if own == "other" or own == "unavailable" then return "other", nil, quests end
  if own == nil then state = "unread" end
  for _, step in ipairs(entry.via) do
    local applies = StepApplies(step, owner)
    if applies == "other" then return "other", nil, quests end
    if applies == nil then state = "unread" end
    if step.kind == "quest" then
      local questState, quest = QuestState(step.questID, owner, budget)
      quests[step.questID] = quest or false
      if questState == "done" then
        local thing, loading = EndThing(entry, owner)
        return "done", thing, quests, loading
      end
      if questState == "unread" then state = "unread" end
    elseif step.kind == "opens" then
      -- a treasure looted is a one-time step done (Task #438)
      local looted = LootState(step.objectID, owner)
      quests["o" .. step.objectID] = looted
      if looted == "done" then
        local thing, loading = EndThing(entry, owner)
        return "done", thing, quests, loading
      end
      if looted == "unread" then state = "unread" end
    end
  end
  local thing, loading = EndThing(entry, owner)
  if not thing then return "unread", nil, quests, loading end
  if not thing.collectible then return state or "plain", thing, quests end
  local own = END_STATE[thing.state]
  if own == "done" or own == "other" then return own, thing, quests end
  if not own then return "unread", thing, quests end
  return state or "open", thing, quests
end

-- Summary(itemID, owner, budget, from, keep): { open, done, other, unread,
-- plain, total, best = { entry, state, thing, quests }, first = { [state] =
-- the same }, reads = every end read, in order, loading = { itemID } } or nil
-- when the item leads nowhere the data names (or keep, when given, keeps none
-- of its ends)
function Chains.Summary(itemID, owner, budget, from, keep)
  local structure = Chains.Leads(itemID, from)
  if #structure.ends == 0 then return nil end
  local out = { open = 0, done = 0, other = 0, unread = 0, plain = 0, total = 0, first = {}, reads = {}, loading = {} }
  local rank = { open = 1, unread = 2, plain = 3, done = 4, other = 5 }
  for _, entry in ipairs(structure.ends) do
    if not keep or keep(entry) then
      local state, thing, quests, loading = Chains.State(entry, owner, budget)
      out[state] = out[state] + 1
      out.total = out.total + 1
      if loading then out.loading[#out.loading + 1] = loading end
      local read = { entry = entry, state = state, thing = thing, quests = quests }
      out.first[state] = out.first[state] or read
      out.reads[#out.reads + 1] = read
      if not out.best or rank[state] < rank[out.best.state] then out.best = read end
    end
  end
  if out.total == 0 then return nil end
  return out
end

-------------------------------------------------------------------------------
-- Words
-------------------------------------------------------------------------------
local KIND_WORDS = { toy = "a toy", mount = "a mount", pet = "a pet", decor = "a decor item", ensemble = "an ensemble",
  heirloom = "an heirloom", recipe = "a recipe", illusion = "a weapon illusion", achievement = "an achievement" }
local HAVE_WORDS = { recipe = "you know", achievement = "you've earned" }
local MISSING_WORDS = { recipe = "you don't know", achievement = "you haven't earned" }

local function ItemName(itemID)
  return Named("item", itemID, Recollect.Facts.Item.Name(itemID)) or ("item " .. tostring(itemID))
end

-- The kind and ID a thing's name is heard as: its item when it has one
local ITEM_THINGS = { item = true, toy = true, heirloom = true, decor = true }
local function ThingNamed(thing, name)
  if ITEM_THINGS[thing.what] then return Named("item", thing.id, name) end
  if IsPositiveID(thing.itemID) then return Named("item", thing.itemID, name) end
  return Named(thing.what, thing.id, name)
end
Chains.ThingNamed = ThingNamed

-- A thing's name and state: "Phoenix Wishwing, a pet you don't have";
-- a plain item by its name
function Chains.ThingWords(thing)
  if not thing then return "something that can't be read" end
  local name = ThingNamed(thing, Recollect.Facts.Buys.Name(thing)) or (thing.what == "item" and ItemName(thing.id))
    or ((KIND_WORDS[thing.what] or thing.what) .. " " .. tostring(thing.id))
  if not thing.collectible then return name end
  local kind = KIND_WORDS[thing.what] or thing.what
  local state = thing.state
  if state == "missing" then return ("%s, %s %s"):format(name, kind, MISSING_WORDS[thing.what] or "you don't have") end
  if state == "have" then return ("%s, %s %s"):format(name, kind, HAVE_WORDS[thing.what] or "you have") end
  if state == "unavailable" then return ("%s, %s not for this character"):format(name, kind) end
  if state == "unassessed" then return ("%s, %s known per character"):format(name, kind) end
  return ("%s, %s whose state can't be read yet"):format(name, kind)
end

local function QuestWords(questID, quest, owner)
  if quest and quest.title then Named("quest", questID, quest.title) end
  local title = quest and quest.title and ("\"" .. quest.title .. "\"") or ("quest " .. questID)
  if not owner.isViewer or not quest then return title end
  if quest.onQuest then return title .. " (you're on it)" end
  if quest.repeatable then return title .. " (repeatable)" end
  local done = Recollect.Facts.QuestInfo.Done(quest)
  if done and Relations().Frequency(questID) then return title .. " (done for now; it comes back)" end
  if done == true then return title .. " (done)" end
  if done == false then return title .. " (not done)" end
  return title
end

local LOOT_WORDS = { done = " (looted)", open = " (not looted yet)" }

-- TreasureWords(objectID, looted): "a treasure in Zul'Aman (65.4, 5.6) (not
-- looted yet)"; "a treasure" for one with no known place. The data ships no
-- object's name, so the place names it
function Chains.TreasureWords(objectID, looted)
  local object = Recollect.Facts.Vendors.Object(objectID)
  local text = "a treasure"
  if object and object.mapID then
    local zone = Recollect.Facts.Vendors.ZoneName(object.mapID) or ("map " .. object.mapID)
    text = ("a treasure in %s (%.1f, %.1f)"):format(zone, object.x * 100, object.y * 100)
  end
  return text .. (LOOT_WORDS[looted] or "")
end

-- Words(entry, owner, thing, quests): "Phoenix Wishwing, a pet you don't
-- have, through "Tale of the Phoenix" (not done)"; "..., by buying Phoenix
-- Ash Talisman with 1"; "Ancient Amani Mask, a toy you don't have, by
-- making Diver's Key, then through a treasure in Zul'Aman (65.4, 5.6) (not
-- looted yet)"
function Chains.Words(entry, owner, thing, quests)
  owner = owner or Recollect.Verdicts.Rows.Owner()
  local text = Chains.ThingWords(thing)
  local steps = {}
  for _, step in ipairs(entry.via) do
    if step.kind == "quest" then
      local quest = quests and quests[step.questID] or nil
      steps[#steps + 1] = "through " .. QuestWords(step.questID, quest or nil, owner)
    elseif step.kind == "makes" then
      steps[#steps + 1] = "by making " .. ItemName(step.itemID)
    elseif step.kind == "buys" then
      steps[#steps + 1] = ("by buying %s with %s"):format(ItemName(step.itemID), Count(step.count or 1))
    elseif step.kind == "opens" then
      steps[#steps + 1] = "through " .. Chains.TreasureWords(step.objectID, quests and quests["o" .. step.objectID])
    elseif step.kind == "holds" then
      steps[#steps + 1] = "by opening " .. ItemName(step.container)
    end
  end
  if #steps > 0 then text = text .. ", " .. table.concat(steps, ", then ") end
  if entry.choice then text = text .. " (a choice reward)" end
  return text
end

-- RewardWords(questID, owner, max): "rewards Phoenix Wishwing, a pet you
-- don't have; and 1 more", whether a reward is a collectible still missing,
-- and how many things the quest rewards; nil when the data names none
function Chains.RewardWords(questID, owner, max)
  local rewards = Chains.Rewards(questID)
  if #rewards == 0 then return nil, false, 0 end
  owner = owner or Recollect.Verdicts.Rows.Owner()
  max = max or 2
  local names, open = {}, false
  -- collectibles still missing first: what a player looks for
  local order = {}
  for i, reward in ipairs(rewards) do
    local thing = Recollect.Facts.Buys.Resolve(reward.relation, owner)
    local missing = thing and thing.collectible and thing.state == "missing" or false
    if missing then open = true end
    order[#order + 1] = { thing = thing, missing = missing, choice = reward.choice, i = i }
  end
  table.sort(order, function(a, b)
    if a.missing ~= b.missing then return a.missing end
    return a.i < b.i
  end)
  for i = 1, math.min(#order, max) do
    names[i] = Chains.ThingWords(order[i].thing) .. (order[i].choice and " (a choice)" or "")
  end
  local more = #order - #names
  return "rewards " .. table.concat(names, "; ") .. (more > 0 and ("; and %d more"):format(more) or ""), open, #order
end

-- "25 gold", "25 gold 50 silver", "40 copper": a price in words
function Chains.GoldWords(copper)
  copper = math.floor(copper)
  local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local parts = {}
  if gold > 0 then parts[#parts + 1] = Count(gold) .. " gold" end
  if silver > 0 then parts[#parts + 1] = silver .. " silver" end
  if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. " copper" end
  return table.concat(parts, " ")
end

-- "and" between the last two of a list: "A", "A and B", "A, B and C"
local function JoinAnd(list)
  if #list <= 1 then return list[1] or "" end
  return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- One cost in words ("4 Apexis Crystal", "350 Honor", "25 gold"), each
-- name heard as a link; nil for a cost that can't be worded
local function CostPart(cost)
  if cost.kind == "gold" and type(cost.count) == "number" then
    return Chains.GoldWords(cost.count)
  elseif cost.kind == "item" and cost.id then
    local okName, name = pcall(Recollect.Facts.Item.Name, cost.id)
    name = okName and type(name) == "string" and name or nil
    return ("%s %s"):format(Count(cost.count or 1), Named("item", cost.id, name) or ("item " .. cost.id))
  elseif cost.kind == "currency" and cost.id then
    local okInfo, info = Recollect.Utilities.Try(Recollect.Purposes.client.GetCurrencyInfo, cost.id)
    local name = okInfo and type(info) == "table" and type(info.name) == "string" and info.name or nil
    return ("%s %s"):format(Count(cost.count or 1), name and Named("currency", cost.id, name, info.quality) or ("currency " .. cost.id))
  end
  return nil
end

-- A whole price in words, every cost of the list: "350 Honor", "350 Honor
-- and 10 gold" (a V code's costs, data format 8, 2026-09-29). A list that
-- says part of the price is unknown (costs.unlisted) ends with "other costs
-- not listed" or "a gold price not recorded", so it never reads as whole
-- (rule 50). nil when no cost can be worded
function Chains.PriceWords(costs)
  if type(costs) ~= "table" then return nil end
  local parts = {}
  for _, cost in ipairs(costs) do parts[#parts + 1] = CostPart(cost) end
  if #parts == 0 then return nil end
  if costs.unlisted == "costs" then
    parts[#parts + 1] = "other costs not listed"
  elseif costs.unlisted == "gold" then
    parts[#parts + 1] = "a gold price not recorded"
  end
  return JoinAnd(parts)
end

-- What a purchase costs in all, worded (rule 50): "1 Phoenix Feather and 20
-- Apexis Crystal", this item first with how many the trade takes, then
-- every other cost, each name heard as a link (Cobanyte, 2026-09-30: "for 1
-- plus 20 Apexis Crystal" left a new player guessing what the 1 was);
-- "other costs" when the data says there are some but not which, and "not
-- listed" / "a gold price not recorded" when the data says part of the
-- price is unknown, so a price never reads as whole when it isn't. "" with
-- no relation
function Chains.TradeWords(relation, itemID)
  if type(relation) ~= "table" then return "" end
  local count = tonumber(relation.count) or 1
  local okName, name = pcall(Recollect.Facts.Item.Name, itemID)
  name = IsPositiveID(itemID) and okName and type(name) == "string" and name or nil
  local parts = { name and ("%s %s"):format(Count(count), Named("item", itemID, name)) or ("%s of this item"):format(Count(count)) }
  local ok, costs = pcall(Relations().Costs, relation, itemID)
  for i, cost in ipairs(ok and type(costs) == "table" and costs or {}) do
    if i > 1 then parts[#parts + 1] = CostPart(cost) end
  end
  if relation.unlisted == "costs" then
    parts[#parts + 1] = #parts > 1 and "other costs not listed" or "other costs"
  elseif relation.unlisted == "gold" then
    parts[#parts + 1] = "a gold price not recorded"
  elseif #parts == 1 and relation.plus then
    parts[2] = "other costs"
  end
  return JoinAnd(parts)
end

-- QuestPath(questID): the chain of quests that ends in it (the data's E
-- table, Relations.QuestChain), first quest first and questID last: { {
-- questID, chain } } where chain is its E record (nil when it has none).
-- Earlier quests are followed only when every one of them is needed; a quest
-- that needs only some of them (chain.any) is where the walk stops. At most
-- MAX_PATH quests, the latest kept; earlier (second return) counts the ones
-- left out. A quest with no record is a path of one
local MAX_PATH, MAX_WALK = 12, 60
function Chains.QuestPath(questID)
  local order, seen = {}, {}
  local function Visit(quest, depth)
    if seen[quest] or depth > MAX_WALK then return end
    seen[quest] = true
    local ok, chain = pcall(Relations().QuestChain, quest)
    chain = ok and chain or nil
    if chain and not chain.any then
      for _, before in ipairs(chain.before) do Visit(before, depth + 1) end
    end
    order[#order + 1] = { questID = quest, chain = chain }
  end
  if not IsPositiveID(questID) then return {}, 0 end
  Visit(questID, 0)
  if #order <= MAX_PATH then return order, 0 end
  local kept = {}
  for i = #order - MAX_PATH + 1, #order do kept[#kept + 1] = order[i] end
  return kept, #order - MAX_PATH
end

Chains._test = {
  Reset = function()
    structures, kept, rewardsOf = {}, 0, {}
  end,
}
