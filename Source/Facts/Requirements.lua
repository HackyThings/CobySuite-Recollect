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
--                   out first; its capture time is named (warbandAsOf)
--          others   what other characters' snapshots hold, listed with
--                   their capture time and never counted: this copy can't
--                   reach them from here
--          missing  need minus bags, bank and warband
--          uncertain  a count that couldn't be read: nothing is certified
--   done   whether the use's target is finished (KnownUse.TargetDone), nil
--          when unknown
-- Nothing here says the reward can be had now: other requirements (a
-- reputation, a quest, the vendor's stock) aren't read, and the view says
-- so. Lines(records, nameOf, owner) words the records for the view. The
-- counts are always the logged-in character's (only its bags and bank can
-- be counted live); for another character's copy the view says so first,
-- since that character's own copies are then among the others, not counted
-- (B1).
-------------------------------------------------------------------------------
local Requirements = {}
Recollect.Facts.Requirements = Requirements

local Try = Recollect.Utilities.Try
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber
local U = CobySuite_Recollect.Utilities

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

-- When the warband bank was last read, or nil
local function WarbandAsOf()
  local warband = Recollect.Inventory.Snapshots.Warband()
  local newest
  for _, stored in pairs(warband or {}) do
    if type(stored) == "table" and type(stored.captured) == "number" and (not newest or stored.captured > newest) then
      newest = stored.captured
    end
  end
  return newest
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

local function When(at)
  return type(at) == "number" and date("%b %d %H:%M", at) or "an unknown time"
end

local function PartLine(part, name, warbandAsOf)
  local bits = { ("needs %d"):format(part.need) }
  if part.uncertain then
    bits[#bits + 1] = "how many you have can't be read"
  else
    if part.bags > 0 then bits[#bits + 1] = ("%d with this character"):format(part.bags) end
    if part.bank > 0 then bits[#bits + 1] = ("%d in your bank"):format(part.bank) end
    if part.warband > 0 then
      bits[#bits + 1] = ("%d in the warband bank (shared; last read %s)"):format(part.warband, When(warbandAsOf))
    end
    if part.missing > 0 then bits[#bits + 1] = ("%d missing"):format(part.missing) end
  end
  for _, other in ipairs(part.others) do
    bits[#bits + 1] = ("%s holds %d (as of %s; not counted)"):format(other.name, other.count, When(other.asOf))
  end
  return name .. ": " .. table.concat(bits, "; ")
end

-- The steps before a use, from where its parts are: take them out of the
-- banks first
local function Steps(record)
  local steps = {}
  for _, part in ipairs(record.parts) do
    if not part.uncertain and part.bags < part.need then
      local fromBank = math.min(part.bank, part.need - part.bags)
      local fromWarband = math.min(part.warband, part.need - part.bags - fromBank)
      if fromBank > 0 then steps[#steps + 1] = { part = part, where = "your bank", count = fromBank } end
      if fromWarband > 0 then steps[#steps + 1] = { part = part, where = "the warband bank", count = fromWarband } end
    end
  end
  return steps
end

-- Title(record, nameOf): what a record's parts are for ("Combine into X",
-- "The secret Y (reward)")
function Requirements.Title(record, nameOf)
  if record.kind == "combine" then return ("Combine into %s"):format(nameOf(record.product)) end
  local title = (KIND_TITLE[record.kind] or "%s"):format(record.title or "a use")
  if record.reward then title = title .. (" (%s)"):format(record.reward) end
  return title
end

-- Lines(records, nameOf, owner): { { text, color, header } } for the view;
-- nameOf(itemID) gives an item's name, and owner (Rows.Owner) adds a first
-- line when the copy is another character's
function Requirements.Lines(records, nameOf, owner)
  local lines = {}
  if #records > 0 and type(owner) == "table" and owner.isViewer == false then
    lines[1] = { text = ("Counted for the character logged in, not %s: %s's own copies are listed with other characters and not counted")
      :format(owner.name or "this copy's owner", owner.name or "that character"), color = U.Colors.LABEL_GRAY }
  end
  local warbandAsOf = WarbandAsOf()
  local V = Recollect.Purposes.Registry.Verdict
  local colors = Recollect.UI.VerdictColors or {}
  for _, record in ipairs(records) do
    local title = Requirements.Title(record, nameOf)
    if record.done == true then title = title .. " (you have its reward)" end
    lines[#lines + 1] = { text = title, header = true, color = U.Colors.HIGHLIGHT_WHITE }
    local uncertain, missing = false, 0
    for _, part in ipairs(record.parts) do
      lines[#lines + 1] = { text = PartLine(part, nameOf(part.itemID), warbandAsOf),
        color = part.uncertain and U.Colors.LABEL_GRAY or (part.missing > 0 and colors[V.NEEDED]) or colors[V.USE] or U.Colors.LIGHT_GRAY }
      if part.uncertain then uncertain = true else missing = missing + part.missing end
    end
    for _, step in ipairs(Steps(record)) do
      lines[#lines + 1] = { text = ("First take %d %s out of %s"):format(step.count, nameOf(step.part.itemID), step.where),
        color = U.Colors.INFO_BLUE }
    end
    local summary
    if uncertain then
      summary = "Some counts can't be read, so whether you have every part isn't known"
    elseif missing > 0 then
      summary = ("%d more %s to get"):format(missing, missing == 1 and "part" or "parts")
    else
      summary = "You have every part it takes"
    end
    lines[#lines + 1] = { text = summary .. "; anything else it needs (a reputation, a quest, a vendor's stock) isn't checked here",
      color = U.Colors.LABEL_GRAY }
  end
  return lines
end

Requirements._test = { seams = seams }
