-------------------------------------------------------------------------------
-- Facts.Requirements: what finishing one use of an item takes, part by part
-- (F-01, first version; the pinned view shows it, UI.DetailWindow)
--
-- Only records complete by construction are admitted (CR-06):
--   * a confirmed Data.Uses entry: its parts and how many of each
--   * a combine the data names with its product and count (Facts.Relations
--     "makes"); never one whose product is unconfirmed (an "mx<n>" code)
--   * a combine of several different parts the data names (Facts.Relations
--     "partOf"): every part, with how many of each
-- For(itemID, owner, relations) returns { { title, kind, reward, done,
-- parts } } (a combine's record: { kind = "combine", product, parts }):
--   parts  { { itemID, need, bags, bank, warband, have, missing, uncertain,
--          others = { { name, count, bags, bank, asOf } } } }
--          bags     with this character (the bags-only count, worn copies
--                   included, as C_Item.GetItemCount counts them)
--          bank     in this character's bank
--          warband  in the warband bank: shared storage, so a copy there
--                   lowers what is left to get but adds a step to take it
--                   out first
--          others   what other characters' snapshots hold, listed with
--                   their capture time and never counted: this copy can't
--                   reach them from here
--          missing  need minus bags, bank and warband
--          uncertain  a count that couldn't be read: nothing is certified
--   done   whether the use's target is finished (KnownUse.TargetDone), nil
--          when unknown
-- Nothing here says the reward can be had now: other requirements (a
-- reputation, a quest, the vendor's stock) aren't read, so the details
-- window's What it takes rows (UI.DetailData) only count parts. The
-- counts are always the logged-in character's (only its bags and bank can
-- be counted live); for another character's copy the view says so first,
-- since that character's own copies are then among the others, not counted
-- (B1).
-------------------------------------------------------------------------------
local Requirements = {}
Recollect.Facts.Requirements = Requirements

local Try = Recollect.Utilities.Try
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber

local seams = {
  GetItemCount = function(itemID, includeBank, includeUses, includeReagentBank, includeAccountBank)
    return C_Item.GetItemCount(itemID, includeBank, includeUses, includeReagentBank, includeAccountBank)
  end,
}

local function Count(itemID, ...)
  local ok, n = Try(seams.GetItemCount, itemID, ...)
  return ok and IsFiniteNumber(n) and n >= 0 and n or nil
end

-- What other characters' snapshots hold of an item: { { name, count, bags,
-- bank, asOf } } (count is bags plus bank)
local function OthersHolding(itemID)
  local Locations = Recollect.Inventory.Locations
  local out = {}
  for _, entry in ipairs(Recollect.Inventory.Snapshots.OtherCharacters()) do
    local n, asOf, where = 0, nil, { bags = 0, bank = 0 }
    for bagID, stored in pairs(entry.char.locations or {}) do
      local kind = Locations.KindOf(bagID)
      if kind and kind ~= Locations.KIND_WARBAND and type(stored) == "table" and type(stored.read) == "table" then
        local key = kind == Locations.KIND_BANK and "bank" or "bags"
        for _, stack in pairs(stored.read.slots or {}) do
          if type(stack) == "table" and stack.itemID == itemID then
            local c = tonumber(stack.count) or 1
            n, where[key] = n + c, where[key] + c
          end
        end
        if type(stored.captured) == "number" and (not asOf or stored.captured > asOf) then asOf = stored.captured end
      end
    end
    if n > 0 then
      out[#out + 1] = { name = tostring(entry.char.name or "another character"), count = n, bags = where.bags,
        bank = where.bank, asOf = asOf }
    end
  end
  return out
end

-- Part(items, need): one part, where its copies are and what is missing.
-- items is an item ID, or a list of the items that fill it (a reagent slot's
-- qualities or choices): their copies count together, as the game's own
-- allocation sums them (PI-05); part.itemID is the first, part.alternatives
-- the whole list when there are several
function Requirements.Part(items, need)
  local list = type(items) == "table" and items or { items }
  local part = { itemID = list[1], alternatives = #list > 1 and list or nil, need = need, others = {} }
  local bags, bank, warband, uncertain, byName = 0, 0, 0, false, {}
  for _, itemID in ipairs(list) do
    local b, withBank, all = Count(itemID), Count(itemID, true, false, true, false), Count(itemID, true, false, true, true)
    if b and withBank and all and withBank >= b and all >= withBank then
      bags, bank, warband = bags + b, bank + withBank - b, warband + all - withBank
    else
      uncertain = true
    end
    for _, other in ipairs(OthersHolding(itemID)) do
      local kept = byName[other.name]
      if kept then
        kept.count, kept.bags, kept.bank = kept.count + other.count, kept.bags + other.bags, kept.bank + other.bank
        if other.asOf and (not kept.asOf or other.asOf > kept.asOf) then kept.asOf = other.asOf end
      else
        kept = { name = other.name, count = other.count, bags = other.bags, bank = other.bank, asOf = other.asOf }
        byName[other.name] = kept
        part.others[#part.others + 1] = kept
      end
    end
  end
  if uncertain then
    part.uncertain = true
  else
    part.bags, part.bank, part.warband, part.have = bags, bank, warband, bags + bank + warband
    part.missing = math.max(0, need - part.have)
  end
  return part
end

local function SortParts(parts)
  table.sort(parts, function(a, b) return a.itemID < b.itemID end)
  return parts
end

-- For(itemID, owner): the eligible records that use itemID
-- relations: the item's relations when the caller has them already parsed
-- (UI.DetailData parses a big item a slice at a time); else Relations.For
function Requirements.For(itemID, owner, relations)
  local records = {}
  local KnownUse = Recollect.Purposes.KnownUse
  for _, entry in ipairs(KnownUse and KnownUse.EntriesFor(itemID) or {}) do
    local parts = {}
    for partID, need in pairs(entry.parts) do parts[#parts + 1] = Requirements.Part(partID, tonumber(need) or 1) end
    records[#records + 1] = { title = entry.name or entry.key, kind = entry.kind, reward = entry.reward,
      done = KnownUse.TargetDone(entry.target), parts = SortParts(parts) }
  end
  local Relations = Recollect.Facts.Relations
  for _, relation in ipairs(relations or Relations.For(itemID)) do
    if relation.kind == "makes" and not relation.unresolved and Recollect.Utilities.IsPositiveID(relation.id)
        and Relations.Applies(relation, owner) == true then
      records[#records + 1] = { kind = "combine", product = relation.id,
        parts = { Requirements.Part(itemID, relation.count or 1) } }
    elseif relation.kind == "partOf" and Recollect.Utilities.IsPositiveID(relation.id) then
      local parts = {}
      for _, part in ipairs(relation.parts) do parts[#parts + 1] = Requirements.Part(part.itemID, part.count) end
      records[#records + 1] = { kind = "combine", product = relation.id, parts = SortParts(parts) }
    end
  end
  return records
end

-------------------------------------------------------------------------------
-- Wording, for the pinned view
-------------------------------------------------------------------------------
local KIND_TITLE = { secret = "The secret %s", cache = "%s", exchange = "Buy %s", collection = "The collection %s" }

-- Title(record, nameOf): what a record's parts are for ("Combine into X",
-- "The secret Y (reward)")
function Requirements.Title(record, nameOf)
  if record.kind == "combine" then return ("Combine into %s"):format(nameOf(record.product)) end
  local title = (KIND_TITLE[record.kind] or "%s"):format(record.title or "a use")
  if record.reward then title = title .. (" (%s)"):format(record.reward) end
  return title
end

Requirements._test = { seams = seams }
