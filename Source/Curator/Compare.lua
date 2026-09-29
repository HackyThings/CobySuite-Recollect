-------------------------------------------------------------------------------
-- Curator.Compare: what an observation says against the shipped data
-- (curator spec, "The recorder contract"), using only Host for the data
--
-- Kinds written to the store: "addition" (seen, not shipped), "conflict" (a
-- value the game gives deterministically differs from the shipped one),
-- "notseen" (shipped, not seen on this visit, recorded with the visit's
-- conditions; never for a fact the curator hints mark verified-unseen or
-- whose shipped conditions exclude this character), and confirmation stamps
-- naming the shipped facts that matched. The client never judges: a single
-- "not seen" is never a removal (D28).
--
-- Facts written here (values are text):
--   v:<npc>:i:<item>:sold     an item a vendor sells ("1" when seen and not
--                             shipped; "filter N[, costs loading]" not seen)
--   v:<npc>:i:<item>:price    what it costs there: "i<item>x<n>+c<currency>x<n>
--                             +g<copper>", sorted; gold only is
--                             "g<copper>x<stack>" (the stack one purchase gives);
--                             a price with a currency and no item cost ends in
--                             the stack, "c1813x25+g50000+s5" (Compare.PriceText,
--                             2026-09-29; none when the game gave no stack, and
--                             records from before then have none). A shipped
--                             currency price (a V code) is written the same way,
--                             without "+s" when the data doesn't know the stack
--   m:<input>:x<n>            what combining n of an item made, "<item>x<n>"
--   p:<npc>                   where an NPC stands, "<map>:<x>,<y>" (0 to 1)
-- Stamps: "v:<npc>" (positions in the shipped vendor index), "m:<input>"
-- (positions among the item's shipped combines), "p:<npc>".
-- Every item a vendor lists is also handed to the items-with-no-information
-- recorder as seen at "v:<npc>" (SawItem, Recorders/NoInfo.lua: the fact
-- ni:<item>).
--
-- The generation guard: the vendor ("merchant") and profession ("trade")
-- windows have a number raised when they close or change. A read notes the
-- number and writes only if it is unchanged, so a read of a closed window
-- writes nothing, above all no "not seen". Loot and quest windows are read
-- inside their own event, so they need no guard.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host

local Compare = {}
Curator.Compare = Compare

Compare.POSITION_TOLERANCE = 0.02   -- map units (0 to 1), NPCs wander

-------------------------------------------------------------------------------
-- The generation guard
-------------------------------------------------------------------------------
local generation = {}

function Compare.Generation(kind)
  return generation[kind] or 0
end

function Compare.Invalidate(kind)
  generation[kind] = (generation[kind] or 0) + 1
end

function Compare.StillValid(kind, noted)
  return (generation[kind] or 0) == noted
end

-------------------------------------------------------------------------------
-- An item seen at a place ("v:<npc>", "c:<npc>", "q:<quest>" ...), for the
-- items-with-no-information recorder (Recorders/NoInfo.lua, which loads
-- after the comparisons); it records only an item the shipped data says
-- nothing about
-------------------------------------------------------------------------------
function Compare.SawItem(itemID, where, ctx)
  local noInfo = Curator.Recorders and Curator.Recorders.NoInfo
  if noInfo then noInfo.Saw(itemID, where, ctx) end
end

-------------------------------------------------------------------------------
-- Costs as text: "i32572x4+c1813x25+g250000", sorted, so equal prices compare equal
-------------------------------------------------------------------------------
local LETTER = { item = "i", currency = "c", gold = "g" }

function Compare.CostText(costs)
  local parts = {}
  for _, cost in ipairs(costs or {}) do
    if cost.kind == "gold" then
      parts[#parts + 1] = "g" .. tostring(cost.count)
    else
      parts[#parts + 1] = (LETTER[cost.kind] or "?") .. tostring(cost.id) .. "x" .. tostring(cost.count)
    end
  end
  table.sort(parts)
  return table.concat(parts, "+")
end

-- A price with no item cost and at least one currency (what a V code can
-- state since data format 8, 2026-09-29): its costs as CostText, gold
-- included, then "+s<stack>", the stack one purchase gives, when known
-- ("c1813x25+s5", "c1792x350+g100000+s1"). "s" sorts after every cost
-- letter, so the text is still sorted. The listing and the shipped code
-- are both written here, so equal prices are equal texts
function Compare.PriceText(costs, stack)
  local text = Compare.CostText(costs)
  if type(stack) == "number" then text = text .. "+s" .. stack end
  return text
end

-- Whether a price's costs are ones a V code states: a currency, no item
function Compare.CurrencyPriced(costs)
  local currency = false
  for _, cost in ipairs(costs or {}) do
    if cost.kind == "item" then return false end
    if cost.kind == "currency" then currency = true end
  end
  return currency
end

-- A price text's costs and stack: "c1813x25+s5" is "c1813x25", 5
local function SplitStack(text)
  local costs, stack = text:match("^(.*)%+s(%d+)$")
  if costs then return costs, tonumber(stack) end
  return text, nil
end

-------------------------------------------------------------------------------
-- A vendor visit
-------------------------------------------------------------------------------
local function Contains(list, value)
  for _, v in ipairs(list or {}) do if v == value then return true end end
  return false
end

local function SortedText(set)
  local list = {}
  for text in pairs(set) do list[#list + 1] = text end
  table.sort(list)
  return #list > 0 and table.concat(list, "|") or nil
end

-- A gold-only trade's price text: "g<copper>x<stack>" (the shipped V code
-- carries the stack, so the price is compared with it)
function Compare.GoldText(copper, stack)
  return ("g%dx%d"):format(copper, stack or 1)
end
-- A vendor's reputation discount (Friendly to Exalted with its faction), in
-- percent: the game shows a discounted gold price rounded up (125 copper at
-- 5% off shows as 119). A price the shipped one less a discount is no
-- difference (2026-09-28: every price at three Stormwind vendors read 0.95
-- of the shipped one); /recollect-data's DISCOUNTS matches it
Compare.DISCOUNTS = { 5, 10, 15, 20 }

function Compare.Discounted(copper, percent)
  return math.ceil(copper * (100 - percent) / 100)
end

-- A price's costs with its gold part less a reputation discount: the
-- discount applies to gold alone, never to a currency
local function DiscountedCosts(costs, percent)
  local out = {}
  for i, cost in ipairs(costs) do
    out[i] = cost.kind == "gold" and { kind = "gold", count = Compare.Discounted(cost.count, percent) } or cost
  end
  return out
end

-- A listing's shipped price at this vendor with no item cost: this vendor's
-- priced seller codes (V) on a route that serves the character. A gold-only
-- one, whole or less a reputation discount (keyed by the shipped price's
-- text, so a discounted match names it); a price in a currency (data format
-- 8, 2026-09-29) as one entry of priced, { costs = { [text] = true } whole
-- and with its gold part discounted, stack (nil when the data says "?") },
-- its text in named for a conflict to name. A V whose price is only partly
-- known makes partial true
local function ShippedPriced(npc, itemID, context, named, discounted, priced)
  local partial = false
  for _, source in ipairs(Host.Sources(itemID, "soldBy", context)) do
    if source.id == npc and source.serves == true then
      if source.price then
        local text = Compare.GoldText(source.price, source.count)
        named[text] = true
        for _, percent in ipairs(Compare.DISCOUNTS) do
          discounted[Compare.GoldText(Compare.Discounted(source.price, percent), source.count)] = text
        end
      elseif type(source.costs) == "table" then
        -- a V whose price is partly unknown judges nothing, whatever it
        -- lists: a gold part with "+?" has no price of its own, so without
        -- this it read as no V at all (2026-09-29)
        if source.unlisted ~= nil then
          partial = true
        elseif Compare.CurrencyPriced(source.costs) then
          local entry = { costs = { [Compare.CostText(source.costs)] = true }, stack = source.count }
          for _, percent in ipairs(Compare.DISCOUNTS) do
            entry.costs[Compare.CostText(DiscountedCosts(source.costs, percent))] = true
          end
          priced[#priced + 1] = entry
          named[Compare.PriceText(source.costs, source.count)] = true
        end
      end
    end
  end
  return partial
end

-- Whether a listing's price text matches a shipped price in a currency: the
-- same costs (the gold part whole or discounted), and the stack unknown on
-- either side or the same
local function PricedMatch(priced, observed)
  local costs, stack = SplitStack(observed)
  for _, entry in ipairs(priced) do
    if entry.costs[costs] and (entry.stack == nil or stack == nil or entry.stack == stack) then return true end
  end
  return false
end

-- The shipped prices of a listing at this vendor: with no item cost, this
-- vendor's V codes (ShippedPriced), else the purchase codes of its item
-- costs. Only a route that serves this character counts (one that doesn't,
-- or can't be told, says nothing about what this character sees): named = {
-- [costText] = true } for routes naming this vendor, vendorless likewise
-- for routes naming none, partial when a counted route's price is only
-- partly known, priced the shipped prices in a currency (PricedMatch)
local function ShippedPrices(npc, itemID, listing, context)
  local named, vendorless, partial, discounted, priced = {}, {}, false, {}, {}
  if #listing.costs == 0 or Compare.CurrencyPriced(listing.costs) then
    partial = ShippedPriced(npc, itemID, context, named, discounted, priced)
  end
  for _, cost in ipairs(listing.costs) do
    if cost.kind == "item" then
      for _, purchase in ipairs(Host.PurchasesOf(cost.id, itemID, context)) do
        if purchase.serves == true then
          local here = Contains(purchase.vendors, npc)
          if here or #purchase.vendors == 0 then
            if purchase.unlisted ~= nil then
              partial = true
            elseif here then
              named[Compare.CostText(purchase.costs)] = true
            else
              vendorless[Compare.CostText(purchase.costs)] = true
            end
          end
        end
      end
    end
  end
  return named, vendorless, partial, discounted, priced
end


local function ListingPrice(listing)
  if #listing.costs == 0 and (listing.price or 0) > 0 then return Compare.GoldText(listing.price, listing.stack) end
  local costs = {}
  for _, cost in ipairs(listing.costs) do costs[#costs + 1] = cost end
  if (listing.price or 0) > 0 then costs[#costs + 1] = { kind = "gold", count = listing.price } end
  if Compare.CurrencyPriced(costs) then return Compare.PriceText(costs, listing.stack) end
  return Compare.CostText(costs)
end


-- One item's listings at the vendor (an item can be listed twice, for two
-- prices): the item matches when any complete listing's price is a shipped
-- one. A listing that doesn't match is a conflict only when no listing
-- matched and a complete shipped price names this vendor on a route that
-- serves this character (a price in a currency against this vendor's V code
-- too, since data format 8); otherwise it is an addition, unless it costs
-- nothing (an empty price, which no code can state). Returns true when the
-- item goes in the vendor's stamp: it matched a shipped trade here, a price
-- in a currency included (a V code whose costs are the listing's), or it
-- was listed and the data ships no price this visit could judge (no V or
-- purchase code of this vendor states one), so the stamp confirms it is
-- sold here and contradicts no shipped price (curator audit, 2026-09-27: a
-- currency vendor's stamp matched 0 of 19 items it listed, before any code
-- could state a price in a currency; 2026-09-29, V's currency prices).
local function Item(visit, itemID, listings, shippedHere, ctx)
  local base = "v:" .. visit.npc .. ":i:" .. itemID
  if not shippedHere then
    Curator.Store.Record("addition", base .. ":sold", "1", nil, ctx)
  end
  local seen, anyMatch, anyNamed, anyPartial, judged = {}, false, {}, false, false
  for _, listing in ipairs(listings) do
    if listing.complete then
      local named, vendorless, partial, discounted, priced = ShippedPrices(visit.npc, itemID, listing, visit.context)
      local observed = ListingPrice(listing)
      local matched = named[observed] or vendorless[observed] or discounted[observed] ~= nil
        or PricedMatch(priced, observed)
      anyMatch = anyMatch or matched
      anyPartial = anyPartial or partial
      judged = judged or partial or next(named) ~= nil or next(vendorless) ~= nil
      for text in pairs(named) do anyNamed[text] = true end
      seen[#seen + 1] = { observed = observed, matched = matched, vendorless = vendorless }
    end
  end
  local namedText = SortedText(anyNamed)
  for _, entry in ipairs(seen) do
    if not entry.matched then
      if not anyMatch and namedText and not anyPartial then
        Curator.Store.Record("conflict", base .. ":price", entry.observed, namedText, ctx, { reaction = visit.reaction })
      elseif entry.observed ~= "" then
        -- A listing with no cost at all (a tabard given again for free) has
        -- no price any code can state, so only a shipped one it differs
        -- from is worth a record. A gold price keeps the reaction, as a
        -- conflict does: with no shipped price to match a discount against,
        -- the pipeline needs it to tell a discounted price from the full one
        local extra = entry.observed:find("g%d") and { reaction = visit.reaction } or nil
        Curator.Store.Record("addition", base .. ":price", entry.observed,
          namedText or SortedText(entry.vendorless), ctx, extra)
      end
    end
  end
  return shippedHere and (anyMatch or (#seen > 0 and not judged))
end

-- Whether a shipped item's absence here may be recorded: a seller code must
-- name this vendor on a route that serves this character. With none (the
-- pair known only from a purchase route, or the vendor past the seller cap)
-- or only ones that can't be told, eligibility is unknown and nothing is
-- recorded.
-- A route only during a holiday or event ("h") never counts: out of season
-- the vendor doesn't list it, and the data names no holiday to check. An
-- item with another route here that serves is still eligible; every route
-- of an item and vendor is read, never only the first (2026-09-28, as
-- /recollect-data's event_seller: every seller code there an event route)
local function MayBeMissing(visit, itemID)
  for _, source in ipairs(Host.Sources(itemID, "soldBy", visit.context)) do
    if source.id == visit.npc and not source.event and source.serves == true then return true end
  end
  return false
end

local function NotSeen(visit, itemID, ctx, hints)
  local fact = "v:" .. visit.npc .. ":i:" .. itemID .. ":sold"
  if hints[fact] or not MayBeMissing(visit, itemID) then return end
  Curator.Store.Record("notseen", fact, "filter " .. tostring(visit.filter) .. (visit.costsLoaded and "" or ", costs loading"),
    nil, ctx)
end

-- VendorStart(visit): the comparison's state, for VendorItems and VendorEnd.
-- visit = { npc, filter, costsLoaded, unread, trades = { [itemID] = { { stack,
-- price, costs = { { kind, id, count } }, complete } } }, context = {
-- faction, classID, raceID }, reaction (UnitReaction, kept on a price
-- conflict and a gold price addition: a reputation discount is not an
-- error) }. unread: an entry couldn't be read, so the visit gives no not
-- seen and no confirmation (recorder contract rule 1); its readable
-- additions are kept.
function Compare.VendorStart(visit)
  local state = { shipped = Host.ItemsOf(visit.npc), position = {}, matched = {}, items = {} }
  for i, itemID in ipairs(state.shipped) do state.position[itemID] = i end
  for itemID in pairs(visit.trades) do state.items[#state.items + 1] = itemID end
  table.sort(state.items)
  return state
end

-- VendorItems(state, visit, ctx, from, to): compares items from..to of state.items
function Compare.VendorItems(state, visit, ctx, from, to)
  for i = from, math.min(to, #state.items) do
    local itemID = state.items[i]
    Compare.SawItem(itemID, "v:" .. visit.npc, ctx)
    if Item(visit, itemID, visit.trades[itemID], state.position[itemID] ~= nil, ctx) then
      state.matched[#state.matched + 1] = state.position[itemID]
    end
  end
end

-- The merchant filter that lists everything (Blizzard's MerchantFrame uses
-- the global; 1 where it is missing, as the Lab's probe reads it)
Compare.FILTER_ALL = LE_LOOT_FILTER_ALL or 1

-- VendorEnd(state, visit, ctx): the not seens and the stamp; returns matched,
-- shipped. A not seen only when the merchant filter was All: any other
-- filter hides items (class, spec, BoE), and the window opens on the class
-- filter (2026-09-26: 65 false not seens from one visit with filter 2)
function Compare.VendorEnd(state, visit, ctx)
  if not visit.unread then
    local hints = Host.Hints().unseen
    if visit.filter ~= nil and visit.filter == Compare.FILTER_ALL then
      for _, itemID in ipairs(state.shipped) do
        if not visit.trades[itemID] then NotSeen(visit, itemID, ctx, hints) end
      end
    end
    if #state.shipped > 0 then Curator.Store.Confirm("v:" .. visit.npc, state.matched, #state.shipped, ctx) end
  end
  return #state.matched, #state.shipped
end

-- Vendor(visit, ctx): the whole visit at once; returns matched, shipped
function Compare.Vendor(visit, ctx)
  local state = Compare.VendorStart(visit)
  Compare.VendorItems(state, visit, ctx, 1, #state.items)
  return Compare.VendorEnd(state, visit, ctx)
end

-------------------------------------------------------------------------------
-- A combine seen in the bags
-------------------------------------------------------------------------------
-- Combine(seen, ctx): seen = { input, inCount, output, outCount, spell, also }
-- (one input of a combine the recorder judged). The fact is
-- "m:<input>:x<inCount>" with the value "<output>x<outCount>": a shipped
-- combine of that count making the same item is confirmed (its position
-- among the item's shipped combines), one whose product is unconfirmed
-- ("mx") gets the addition that settles it, one making another item a
-- conflict. Returns "confirmed", "addition", "conflict" or nil.
function Compare.Combine(seen, ctx)
  local shipped = Host.Combines(seen.input)
  local fact = "m:" .. seen.input .. ":x" .. seen.inCount
  local observed = seen.output .. "x" .. seen.outCount
  local extra = { cast = seen.spell }   -- the Use spell cast, kept per observation
  local other, unresolved
  for position, combine in ipairs(shipped) do
    if combine.count == seen.inCount then
      if combine.product == seen.output then
        Curator.Store.Confirm("m:" .. seen.input, { position }, #shipped, ctx)
        return "confirmed"
      end
      if combine.product == nil then unresolved = true else other = other or combine.product end
    end
  end
  if other then
    Curator.Store.Record("conflict", fact, observed, tostring(other), ctx, extra)
    return "conflict"
  end
  if unresolved then
    Curator.Store.Record("addition", fact, observed, nil, ctx, extra)
    return "addition"
  end
  return nil
end

-------------------------------------------------------------------------------
-- An NPC's position
-------------------------------------------------------------------------------
Compare.WORLD_TOLERANCE = 25   -- yards, for positions on different maps

Compare.seams = {
  -- continentID, world x, world y of a map position, or nothing
  WorldPos = function(mapID, x, y)
    local continent, position = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if continent and position then
      local wx, wy = position:GetXY()
      return continent, wx, wy
    end
  end,
}

local function Round(value)
  return math.floor(value * 100 + 0.5) / 100
end

local function World(mapID, x, y)
  local ok, continent, wx, wy = pcall(Compare.seams.WorldPos, mapID, x, y)
  if not ok or Host.IsSecret(continent) or Host.IsSecret(wx) or Host.IsSecret(wy) then return nil end
  if type(continent) ~= "number" or type(wx) ~= "number" or type(wy) ~= "number" then return nil end
  return continent, wx, wy
end

local function PlaceText(place)
  return ("%d:%.2f,%.2f"):format(place.mapID, Round(place.x), Round(place.y))
end

-- Whether a place on the sighting's own map is within POSITION_TOLERANCE
local function Near(place, x, y)
  return math.abs(place.x - x) <= Compare.POSITION_TOLERANCE and math.abs(place.y - y) <= Compare.POSITION_TOLERANCE
end

-- How places on other maps than the sighting's compare with it in world
-- coordinates: "near" when one is on the same continent within
-- WORLD_TOLERANCE, "far" when every one was translated and none is, nil
-- when the sighting or any of them can't be translated
local function WorldMatch(places, mapID, x, y)
  local c2, x2, y2 = World(mapID, x, y)
  if not c2 then return nil end
  local unknown = false
  for _, place in ipairs(places) do
    local c1, x1, y1 = World(place.mapID, place.x, place.y)
    if not c1 then
      unknown = true
    else
      local dx, dy = x1 - x2, y1 - y2
      if c1 == c2 and dx * dx + dy * dy <= Compare.WORLD_TOLERANCE * Compare.WORLD_TOLERANCE then return "near" end
    end
  end
  return not unknown and "far" or nil
end

-- A giver with no shipped place, against the place its quest starts
-- (fallback, Host.QuestPlace; only when the G record lists this NPC among
-- the quest's givers): near is a confirmation; far is left to the caller.
-- Never a conflict, since G's place is the quest's first spot, which may be
-- another giver's (2026-09-28: 9 of the 64 position findings were quest
-- givers standing where G already had them). Returns true when confirmed
local function GiverPlace(npc, fallback, mapID, x, y)
  if type(fallback) ~= "table" or type(fallback.mapID) ~= "number" then return false end
  local listed = fallback.npcID == npc
  for _, giver in ipairs(fallback.npcIDs or {}) do listed = listed or giver == npc end
  if not listed then return false end
  if fallback.mapID == mapID then return Near(fallback, x, y) end
  return WorldMatch({ fallback }, mapID, x, y) == "near"
end

-- Position(npc, mapID, x, y, ctx, questRef, addWhenUnshipped, fallback).
-- The data may give an NPC several places (data format 7: a walking vendor,
-- a rare with several spawns, one NPC in several cities; 2026-09-28: 344
-- shipped NPCs had AllTheThings points beyond the tolerance of the one the
-- data kept). Near any place on the sighting's map is a confirmation. Places
-- on other maps (a sub-map, a floor, another zone) are compared in world
-- coordinates: the same continent within WORLD_TOLERANCE is a confirmation.
-- With none near, a conflict only when the sighting's map has places, every
-- one of them far, and every place elsewhere was translated and none
-- matched; it carries the quest state (questRef, else the character's
-- current one), so the pipeline can tell a phased NPC from wrong data. With
-- no place on the sighting's map, an addition (a place the data doesn't
-- list), never a conflict. Whenever a place elsewhere or the sighting's map
-- can't be translated and nothing matched, nothing is recorded: a match
-- can't be ruled out. An NPC with no place at all is compared with its
-- quest's start (fallback: GiverPlace) when given, else added only when
-- addWhenUnshipped.
function Compare.Position(npc, mapID, x, y, ctx, questRef, addWhenUnshipped, fallback)
  if not (npc and mapID and x and y) then return end
  local observed = ("%d:%.2f,%.2f"):format(mapID, Round(x), Round(y))
  local fact = "p:" .. npc
  local places = Host.NpcPlaces(npc)
  if #places == 0 then
    if GiverPlace(npc, fallback, mapID, x, y) then
      Curator.Store.Confirm(fact, { 1 }, 1, ctx)
    elseif addWhenUnshipped then
      Curator.Store.Record("addition", fact, observed, nil, ctx)
    end
    return
  end
  local elsewhere, nearest, best = {}, nil, nil
  for _, place in ipairs(places) do
    if place.mapID == mapID then
      if Near(place, x, y) then
        Curator.Store.Confirm(fact, { 1 }, 1, ctx)
        return
      end
      local d = (place.x - x) ^ 2 + (place.y - y) ^ 2
      if not best or d < best then nearest, best = place, d end
    else
      elsewhere[#elsewhere + 1] = place
    end
  end
  if #elsewhere > 0 then
    local match = WorldMatch(elsewhere, mapID, x, y)
    if match == "near" then
      Curator.Store.Confirm(fact, { 1 }, 1, ctx)
      return
    end
    if match == nil then return end
  end
  if nearest then
    Curator.Store.Record("conflict", fact, observed, PlaceText(nearest), ctx, { quests = questRef or Curator.Context.QuestRef() })
  else
    Curator.Store.Record("addition", fact, observed, PlaceText(places[1]), ctx)
  end
end
