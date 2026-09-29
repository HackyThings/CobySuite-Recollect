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
--                             "g<copper>x<stack>" (the stack one purchase gives)
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
-- A gold-only listing's shipped price: this vendor's gold-only seller code
-- (V) on a route that serves the character
local function ShippedGold(npc, itemID, context, named)
  for _, source in ipairs(Host.Sources(itemID, "soldBy", context)) do
    if source.id == npc and source.price and source.serves == true then
      named[Compare.GoldText(source.price, source.count)] = true
    end
  end
end

-- The shipped prices of a listing at this vendor, from the purchase codes of
-- its item costs. Only a route that serves this character counts (one that
-- doesn't, or can't be told, says nothing about what this character sees):
-- named = { [costText] = true } for routes naming this vendor, vendorless
-- likewise for routes naming none, partial when a counted route's price is
-- only partly known
local function ShippedPrices(npc, itemID, listing, context)
  local named, vendorless, partial = {}, {}, false
  if #listing.costs == 0 then ShippedGold(npc, itemID, context, named) end
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
  return named, vendorless, partial
end


local function ListingPrice(listing)
  if #listing.costs == 0 and (listing.price or 0) > 0 then return Compare.GoldText(listing.price, listing.stack) end
  local costs = {}
  for _, cost in ipairs(listing.costs) do costs[#costs + 1] = cost end
  if (listing.price or 0) > 0 then costs[#costs + 1] = { kind = "gold", count = listing.price } end
  return Compare.CostText(costs)
end


-- One item's listings at the vendor (an item can be listed twice, for two
-- prices): the item matches when any complete listing's price is a shipped
-- one. A listing that doesn't match is a conflict only when no listing
-- matched and a complete shipped price names this vendor on a route that
-- serves this character; otherwise it is an addition. Returns true when the
-- item goes in the vendor's stamp: it matched a shipped trade here, or it
-- was listed and the data ships no price this visit could judge (a price
-- paid in a currency has no code yet), so the stamp confirms it is sold
-- here and contradicts no shipped price (curator audit, 2026-09-27: a
-- currency vendor's stamp matched 0 of 19 items it listed).
local function Item(visit, itemID, listings, shippedHere, ctx)
  local base = "v:" .. visit.npc .. ":i:" .. itemID
  if not shippedHere then
    Curator.Store.Record("addition", base .. ":sold", "1", nil, ctx)
  end
  local seen, anyMatch, anyNamed, anyPartial, judged = {}, false, {}, false, false
  for _, listing in ipairs(listings) do
    if listing.complete then
      local named, vendorless, partial = ShippedPrices(visit.npc, itemID, listing, visit.context)
      local observed = ListingPrice(listing)
      local matched = named[observed] or vendorless[observed] or false
      anyMatch = anyMatch or matched
      anyPartial = anyPartial or partial
      judged = judged or partial or next(named) ~= nil or next(vendorless) ~= nil
      for text in pairs(named) do anyNamed[text] = true end
      seen[#seen + 1] = { observed = observed, matched = matched, named = named, vendorless = vendorless }
    end
  end
  local namedText = SortedText(anyNamed)
  for _, entry in ipairs(seen) do
    if not entry.matched then
      if not anyMatch and namedText and not anyPartial then
        Curator.Store.Record("conflict", base .. ":price", entry.observed, namedText, ctx, { reaction = visit.reaction })
      else
        Curator.Store.Record("addition", base .. ":price", entry.observed,
          namedText or SortedText(entry.vendorless), ctx)
      end
    end
  end
  return shippedHere and (anyMatch or (#seen > 0 and not judged))
end

-- Whether a shipped item's absence here may be recorded: a seller code must
-- name this vendor on a route that serves this character. With none (the
-- pair known only from a purchase route, or the vendor past the seller cap)
-- or one that can't be told, eligibility is unknown and nothing is recorded.
local function MayBeMissing(visit, itemID)
  for _, source in ipairs(Host.Sources(itemID, "soldBy", visit.context)) do
    if source.id == visit.npc then return source.serves == true end
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
-- conflict: a reputation discount is not an error) }. unread: an entry
-- couldn't be read, so the visit gives no not seen and no confirmation
-- (recorder contract rule 1); its readable additions are kept.
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

-- Position(npc, mapID, x, y, ctx, questRef, addWhenUnshipped). On the
-- shipped map: near is a confirmation, far a conflict carrying the quest
-- state (questRef, else the character's current one), so the pipeline can
-- tell a phased NPC from wrong data. On another map (a sub-map, a floor, or
-- a second place the NPC stands, which the data keeps only one of) both
-- are compared in world coordinates: the same continent within
-- WORLD_TOLERANCE is a confirmation, anywhere else an addition (a place the
-- data doesn't list), never a conflict; a map that can't be translated
-- records nothing.
function Compare.Position(npc, mapID, x, y, ctx, questRef, addWhenUnshipped)
  if not (npc and mapID and x and y) then return end
  local observed = ("%d:%.2f,%.2f"):format(mapID, Round(x), Round(y))
  local fact = "p:" .. npc
  local shipped = Host.NpcPosition(npc)
  if not shipped then
    if addWhenUnshipped then Curator.Store.Record("addition", fact, observed, nil, ctx) end
    return
  end
  local shippedText = ("%d:%.2f,%.2f"):format(shipped.mapID, Round(shipped.x), Round(shipped.y))
  if shipped.mapID == mapID then
    if math.abs(shipped.x - x) <= Compare.POSITION_TOLERANCE and math.abs(shipped.y - y) <= Compare.POSITION_TOLERANCE then
      Curator.Store.Confirm(fact, { 1 }, 1, ctx)
    else
      Curator.Store.Record("conflict", fact, observed, shippedText, ctx, { quests = questRef or Curator.Context.QuestRef() })
    end
    return
  end
  local c1, x1, y1 = World(shipped.mapID, shipped.x, shipped.y)
  local c2, x2, y2 = World(mapID, x, y)
  if not (c1 and c2) then return end
  local dx, dy = x1 - x2, y1 - y2
  if c1 == c2 and dx * dx + dy * dy <= Compare.WORLD_TOLERANCE * Compare.WORLD_TOLERANCE then
    Curator.Store.Confirm(fact, { 1 }, 1, ctx)
  else
    Curator.Store.Record("addition", fact, observed, shippedText, ctx)
  end
end
