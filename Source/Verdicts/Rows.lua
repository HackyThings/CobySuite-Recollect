-------------------------------------------------------------------------------
-- Verdicts.Rows: every stack this character can account for, with its verdict
--
--   bags     read live, every time
--   bank     read live while the bank is open and viewable, else the stored
--            snapshot (with its capture time)
--   warband  likewise, when viewable and unlocked
--
-- A live slot's tooltip is read on demand for the checks that need it; a
-- snapshot row uses the tooltip facts captured with it, except that captured
-- facts with no Use line, for an item that has a spell, give way to the
-- item's link tooltip once that has the line: the line comes with the
-- spell's data, which can arrive after the capture (contract rule 14).
--
-- Other characters' stored bags and banks (the list's "other characters"
-- option) are listed read-only, as of their capture (contract rule 30): only
-- the account-wide checks run on them (collections, known uses, currencies,
-- decor, achievements, what it buys, every use gone, junk and season), their
-- tooltip comes from the item's link, and their faction from the
-- snapshot (none when it names neither Horde nor Alliance). Their counts
-- can't be checked against the live bank (it counts this character only),
-- and a per-character check that can't run there might disagree, so a
-- Junk, Outdated or Lower level verdict reads Unknown ("checked fully only
-- on <name>"), and so does Use now (whether that character can use the item
-- was read on this one: its tooltip's red lines, its mount flags); Purpose
-- done stays only when a collection check decided it. A downgraded row's
-- note carries the reason, so the audit panel leads with it rather than one
-- check's words.
--
-- Snapshot rows are verified per item before they are believed. With the
-- bank closed its slots cannot be read, but C_Item.GetItemCount with the bank
-- flags still counts the bank and warband bank (the Lab, 2026-09-23: 106 of
-- 106 items matched, before and after the bank was opened that session). An
-- item whose stored count (bank plus warband) differs from that live count,
-- or whose count cannot be read, has changed since the snapshot: its rows
-- are Unknown, with that as their note. Two readings of the bags guard the
-- subtraction: the bags-only GetItemCount must equal the bags just read plus
-- the copies worn, or the item is unverifiable. That count includes what is
-- worn in the gear slots, the profession slots and the bag slots (the Lab's
-- "worn" probe, 2026-09-24: 17 gear, 9 profession and 3 bag items, every one
-- counted); the worn copies cancel out of the subtraction, so only the guard
-- needs them. When they can't all be read (WornCounts is nil unless every
-- worn slot list was read, CR-05), a worn item's bank copies stay
-- unverifiable.
--
-- A stored tab the bank closed on with a read still owed (Snapshots:
-- entry.changed, BA-01) gives Unknown rows until it is read again. With the
-- bank open, a tab whose live read fails shows its stored snapshot instead,
-- with its capture time and the same checks (BA-08), rather than no rows.
--
-- Every row carries its owner (Rows.Owner: faction, class, whether it is
-- the character logged in), which the checks, the panel's lines and the
-- purchase states read (BA-05): a quest, loot or recipe state is read only
-- for the character logged in.
-------------------------------------------------------------------------------
local Rows = {}
Recollect.Verdicts.Rows = Rows

local Locations = Recollect.Inventory.Locations
local Reader = Recollect.Inventory.Reader
local Snapshots = Recollect.Inventory.Snapshots
local Registry = Recollect.Purposes.Registry
local Config = Recollect.Config
local Try = Recollect.Utilities.Try
local IsPositiveID = Recollect.Utilities.IsPositiveID
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber

local seams = {
  GetItemCount = function(itemID, includeBank, includeUses, includeReagentBank, includeAccountBank)
    return C_Item.GetItemCount(itemID, includeBank, includeUses, includeReagentBank, includeAccountBank)
  end,
  InventoryItemID = function(slot) return GetInventoryItemID("player", slot) end,
  ProfessionSlots = function(profession) return C_TradeSkillUI.GetProfessionSlots(profession) end,
  BagInventorySlot = function(bagID) return C_Container.ContainerIDToInventoryID(bagID) end,
  FactionGroup = function() return UnitFactionGroup("player") end,
  ClassBase = function() return UnitClassBase("player") end,
  Race = function() return UnitRace("player") end,
  PlayerGUID = function() return UnitGUID("player") end,
  PlayerName = function() return UnitName("player") end,
}

-- ClassFile to class ID (the IDs AllTheThings' class conditions use)
local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8,
  WARLOCK = 9, MONK = 10, DRUID = 11, DEMONHUNTER = 12, EVOKER = 13 }

-- Owner(other): whose copy a row is. other = { guid, name, faction, class,
-- race } from a stored character, or nil for the character logged in.
-- Returns { guid, name, faction (0 Horde, 1 Alliance, nil), classID, raceID,
-- isViewer }; a race not stored (a snapshot from before it was) is nil.
function Rows.Owner(other)
  if other then
    return { guid = other.guid, name = other.name, faction = Registry.FactionIndex(other.faction),
      classID = CLASS_IDS[other.class], raceID = IsPositiveID(other.race) and other.race or nil, isViewer = false }
  end
  local okF, faction = Try(seams.FactionGroup)
  local okC, classFile, classID = Try(seams.ClassBase)
  local okG, guid = Try(seams.PlayerGUID)
  local okN, name = Try(seams.PlayerName)
  local okR, _, _, raceID = Try(seams.Race)
  if not (okC and IsPositiveID(classID)) then classID = okC and CLASS_IDS[classFile] or nil end
  return { guid = okG and guid or nil, name = okN and name or nil, faction = okF and Registry.FactionIndex(faction) or nil,
    classID = classID, raceID = okR and IsPositiveID(raceID) and raceID or nil, isViewer = true }
end

-- A snapshot's tooltip facts. Captured with no Use line for an item that has
-- a spell, they may predate the spell's data (contract rule 14): the item's
-- link tooltip is used instead once it shows the line.
local function StoredTooltip(stack, facts)
  local tip = stack.tooltip
  if type(tip) ~= "table" or type(tip.useText) == "string" then return tip end
  if not (facts and facts.hasSpell == true) then return tip end
  local fromLink = Recollect.Facts.Tooltip.FromLink(stack.link)
  if fromLink and type(fromLink.useText) == "string" then return fromLink end
  return tip
end

-- Another character's tooltip (BA-06): what it captured, with the fields
-- that change when the account collects something (already known, pet and
-- decor counts) read now from the item's link, and the logged-in
-- character's faction, since the link tooltip is read by it
local DYNAMIC = { "known", "petCollected", "petLimit", "decorOwned", "decorBonus" }
local function OtherTooltip(stack, facts)
  local stored = StoredTooltip(stack, facts)
  local fromLink = Recollect.Facts.Tooltip.FromLink(stack.link)
  local okF, faction = Try(seams.FactionGroup)
  local viewerFaction = okF and Registry.FactionIndex(faction) or nil
  if not stored then
    if fromLink then fromLink.viewerFaction = viewerFaction end
    return fromLink
  end
  if not fromLink then return stored end   -- the captured answers alone
  local merged = {}
  for k, v in pairs(stored) do merged[k] = v end
  for _, k in ipairs(DYNAMIC) do merged[k] = fromLink[k] end
  merged.viewerFaction = viewerFaction
  return merged
end

-- ContextFor(stack, kind, bagID, slot, live, other): the ctx a purpose check
-- reads; other = { guid, name, faction, class, race } for another
-- character's stored copy
function Rows.ContextFor(stack, kind, bagID, slot, live, other)
  local facts, why = Recollect.Facts.Item.Get(stack.itemID)
  -- Another character's faction is the snapshot's alone: one that names
  -- neither Horde nor Alliance ("Neutral", or none stored) stays nil
  local owner = Rows.Owner(other)
  local ctx = {
    stack = stack, facts = facts, factsReason = why,
    kind = kind, live = live and true or false, bagID = bagID, slot = slot,
    playerFaction = owner.faction,
    owner = owner,
    otherCharacter = other and other.name or nil,
  }
  local tipRead, tipFacts = false, nil
  ctx.Tooltip = function()
    if not tipRead then
      if other then
        tipFacts = OtherTooltip(stack, facts)
      elseif not ctx.live then
        tipFacts = StoredTooltip(stack, facts)
      else
        tipFacts = Recollect.Facts.Tooltip.FromBagSlot(bagID, slot)
      end
      tipRead = true
    end
    return tipFacts
  end
  return ctx
end

-------------------------------------------------------------------------------
-- Snapshot freshness
-------------------------------------------------------------------------------

-- Totals(reads): { [itemID] = count } summed over a list of container reads
function Rows.Totals(reads)
  local totals = {}
  for _, read in ipairs(reads) do
    for slot = 1, read.numSlots or 0 do
      local stack = read.slots and read.slots[slot]
      if stack and IsPositiveID(stack.itemID) then
        totals[stack.itemID] = (totals[stack.itemID] or 0) + (stack.count or 1)
      end
    end
  end
  return totals
end

-- The inventory slots whose items the bags-only GetItemCount counts: gear
-- (INVSLOT_FIRST_EQUIPPED to INVSLOT_LAST_EQUIPPED), every profession's slots
-- and the equipped bags; and whether every list was read. Kept once every
-- list was read.
local wornSlots
local function WornSlots()
  if wornSlots then return wornSlots, true end
  local slots, seen, complete = {}, {}, true
  local function Add(slot)
    if IsPositiveID(slot) and not seen[slot] then
      seen[slot] = true
      slots[#slots + 1] = slot
    end
  end
  for slot = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do Add(slot) end
  for _, profession in pairs(Enum.Profession or {}) do
    local ok, list = Try(seams.ProfessionSlots, profession)
    if ok and type(list) == "table" then
      for _, slot in ipairs(list) do Add(slot) end
    else
      complete = false
    end
  end
  for _, bagID in ipairs(Locations.Bags()) do
    if bagID ~= Locations.BACKPACK then
      local ok, slot = Try(seams.BagInventorySlot, bagID)
      if ok then Add(slot) else complete = false end
    end
  end
  if complete then wornSlots = slots end
  return slots, complete
end

-- WornCounts(): { [itemID] = copies worn } over those slots, or nil when a
-- slot list or a slot can't be read (complete or nothing, CR-05: a partial
-- count would pass a worn copy off as a bank one, or subtract too little)
function Rows.WornCounts()
  local slots, complete = WornSlots()
  if not complete then return nil end
  local counts = {}
  for _, slot in ipairs(slots) do
    local ok, itemID = Try(seams.InventoryItemID, slot)
    if not ok then return nil end
    if IsPositiveID(itemID) then counts[itemID] = (counts[itemID] or 0) + 1 end
  end
  return counts
end

-- LiveBankCount(itemID, bagTotals, worn): what the client says the bank and
-- warband bank hold now, or nil when it cannot be read or the two bag
-- readings differ. worn is Rows.WornCounts(); nil counts no worn copies, so
-- a worn item is then unverifiable.
function Rows.LiveBankCount(itemID, bagTotals, worn)
  local okAll, all = Try(seams.GetItemCount, itemID, true, false, true, true)
  local okBags, bags = Try(seams.GetItemCount, itemID, false, false, false, false)
  if not okAll or not okBags or not IsFiniteNumber(all) or not IsFiniteNumber(bags) then return nil end
  if bags ~= ((bagTotals and bagTotals[itemID]) or 0) + ((worn and worn[itemID]) or 0) then return nil end
  return all - bags
end

-- StaleItems(bankTotals, bagTotals, worn): { [itemID] = { stored, live } } for
-- every item whose bank total (stored and live reads together) differs from
-- the live count, or whose live count cannot be read
function Rows.StaleItems(bankTotals, bagTotals, worn)
  local stale = {}
  for itemID, stored in pairs(bankTotals) do
    local live = Rows.LiveBankCount(itemID, bagTotals, worn)
    if live ~= stored then stale[itemID] = { stored = stored, live = live } end
  end
  return stale
end

-- ApplyFreshness(result, staleEntry): the verdict for a snapshot row whose
-- item changed since the snapshot; the note is what the panel leads with
function Rows.ApplyFreshness(result, staleEntry)
  if not staleEntry then return result end
  local reason
  if staleEntry.live == nil then
    reason = "Stored at your last bank visit; the bank's count for it can't be confirmed now"
  else
    reason = ("Changed since your last bank visit: the bank holds %d now, %d when stored"):format(staleEntry.live, staleEntry.stored)
  end
  return { verdict = Registry.Verdict.UNKNOWN, reason = reason, note = reason, purposes = result.purposes, category = "bank" }
end

-- A row from a stored tab the bank closed on before reading it again
-- (entry.changed, BA-01). name: another character's tab, which only that
-- character can read again (its own bank, not the one logged in)
local CHANGED = "This bank tab changed after Recollect last read it"
function Rows.ApplyChanged(result, name)
  if name then
    local reason = ("%s's bank tab changed after Recollect last read it"):format(name)
    return { verdict = Registry.Verdict.UNKNOWN, reason = reason, note = reason, purposes = result.purposes,
      category = "character", recovery = ("Log in to %s and open the bank once"):format(name) }
  end
  return { verdict = Registry.Verdict.UNKNOWN, reason = CHANGED, note = CHANGED, purposes = result.purposes, category = "bank" }
end

-------------------------------------------------------------------------------
-- Rows
-------------------------------------------------------------------------------
local function PurposeText(result)
  local labels = {}
  for _, p in ipairs(result.purposes) do labels[#labels + 1] = p.label end
  return #labels > 0 and table.concat(labels, ", ") or "-"
end

-- What the game's data says the item is for, in a few words (the list's
-- "Used for" column); the panel shows each with its live state. Where an
-- item comes from (quest rewards, what it is made from) is not a use.
-- A route no longer in the game says nothing here (SRC-01).
local USED_FOR_WORDS = {
  objective = "Quest objective", criterion = "Achievement", buysDecor = "Buys decor", makes = "Combines", partOf = "Combines",
  recipeFor = "Recipe", currency = "Currency", questItem = "Quest item", starts = "Starts a quest", buys = "Buys things",
  opens = "Opens something", usedAt = "Used at an NPC", reagentOf = "Crafting reagent", teaches = "Recipe",
  linked = "Linked achievement",   -- a link, never a need (B10)
}
-- The words an item's data gives, kept per parsed list (weakly: they go when
-- the parse does), so a list redraw reads each item's relations once
local wordsOf = setmetatable({}, { __mode = "k" })
local function DataWords(relations)
  local words = wordsOf[relations]
  if words then return words end
  words = {}
  local Relations, seen = Recollect.Facts.Relations, {}
  local function Add(word)
    if word and not seen[word] then
      seen[word] = true
      words[#words + 1] = word
    end
  end
  for _, relation in ipairs(relations) do
    if Relations.Applies(relation) == "unavailable" then
      -- no longer in the game: not a use
    elseif relation.kind == "currency" then
      local ok, factionID = Recollect.Utilities.Try(Recollect.Purposes.client.GetFactionGrantedByCurrency, relation.id)
      if ok then Add(IsPositiveID(factionID) and "Reputation" or "Currency") end
    else
      Add(USED_FOR_WORDS[relation.kind])
    end
  end
  wordsOf[relations] = words
  return words
end

function Rows.UsedForText(itemID, stack)
  local words, seen = {}, {}
  local function Add(word)
    if word and not seen[word] then
      seen[word] = true
      words[#words + 1] = word
    end
  end
  if stack and stack.quest and IsPositiveID(stack.quest.questID) then Add("Starts a quest") end
  for _, word in ipairs(DataWords(Recollect.Facts.Relations.For(itemID))) do Add(word) end
  local index = Recollect.Facts.Journals.Get()
  if index and index[itemID] then Add("Buys mounts or pets") end
  return table.concat(words, ", ")
end

-- Collection checks: their Purpose done holds for any character's copy
local COLLECTION_DONE = { toy = true, mount = true, pet = true, ensemble = true, illusion = true, knownUse = true, decor = true }

-- Another character's row: Junk, Outdated, Lower level, and a done no collection check decided,
-- read Unknown (a per-character check that could not run might disagree);
-- so does Use now, since whether that character can use the item was read
-- on this one (the link tooltip's red lines, the mount's per-character flags)
function Rows.ForOtherCharacter(result, name)
  local V = Registry.Verdict
  local keep = result.verdict ~= V.OUTDATED and result.verdict ~= V.LOWER and result.verdict ~= V.JUNK
    and result.verdict ~= V.DONE
    and result.verdict ~= V.USE
  if result.verdict == V.DONE then
    keep = true
    for _, p in ipairs(result.purposes) do
      if not p.soft and not COLLECTION_DONE[p.key] then keep = false end
    end
  end
  if keep then return result end
  local note = ("checked fully only on %s"):format(name)
  return { verdict = V.UNKNOWN, reason = ("%s; %s"):format(tostring(result.reason), note), note = note, purposes = result.purposes,
    category = "character" }
end

-- Whether another character's recipe scan recorded a use for the item (F-02)
local function RecordedAltUse(itemID)
  local ok, list = pcall(Recollect.Facts.Recipes.RecordedByOthers, itemID)
  return ok and type(list) == "table" and #list > 0 or false
end

-- Verdict(stack, source, bagID, slot, staleEntry): one copy's verdict as the
-- list shows it, and its ctx. source = { kind, live, other, changed }, as a
-- row's source or a pinned copy's (UI.DetailWindow evaluates again with the
-- staleness the list found, B3)
function Rows.Verdict(stack, source, bagID, slot, staleEntry)
  local ctx = Rows.ContextFor(stack, source.kind, bagID, slot, source.live, source.other)
  local result = Recollect.Verdicts.Evaluate(ctx)
  if source.changed then
    result = Rows.ApplyChanged(result, source.other and source.other.name)
  elseif source.other then
    result = Rows.ForOtherCharacter(result, source.other.name)
  elseif not source.live then
    result = Rows.ApplyFreshness(result, staleEntry)
  end
  return result, ctx
end

local function AddRow(out, stack, source, slot, stale)
  if not IsPositiveID(stack.itemID) then return end
  local result, ctx = Rows.Verdict(stack, source, source.read.bagID, slot, stale[stack.itemID])
  local facts = ctx.facts
  out[#out + 1] = {
    itemID = stack.itemID,
    link = stack.link,
    name = (facts and facts.name) or stack.name or ("item:" .. stack.itemID),
    icon = facts and facts.texture or nil,
    quality = (facts and facts.quality) or stack.quality,
    count = stack.count or 1,
    kind = source.kind, bagID = source.read.bagID, slot = slot,
    live = source.live, where = source.where, asOf = source.asOf,
    verdict = result.verdict,
    verdictLabel = Registry.VerdictLabel[result.verdict] or result.verdict,
    verdictRank = Recollect.Verdicts.RANK[result.verdict] or 9,
    reason = result.reason,
    note = result.note,
    unchecked = result.unchecked,
    category = result.verdict == Registry.Verdict.UNKNOWN and result.category or nil,
    -- every use a check read is finished (Verdicts.Combine's settled)
    settled = result.verdict == Registry.Verdict.UNKNOWN and result.settled or nil,
    recovery = result.recovery,
    purposeText = PurposeText(result),
    purposes = result.purposes,
    usedForText = Rows.UsedForText(stack.itemID, stack),
    altUse = RecordedAltUse(stack.itemID),
    stack = stack,
    owner = ctx.owner,
    character = source.other and source.other.name or nil,
    -- what evaluating this copy again needs (the pinned view, B3)
    other = source.other, changed = source.changed, stale = stale[stack.itemID],
  }
end

local function AddSource(out, source, stale)
  local read = source.read
  for slot = 1, read.numSlots or 0 do
    local stack = read.slots[slot]
    if stack then AddRow(out, stack, source, slot, stale) end
  end
end

-- The bags, read now: their sources and item totals
local function BagSources()
  local sources, reads = {}, {}
  for _, bagID in ipairs(Locations.Bags()) do
    local read = Reader.ReadContainer(bagID)
    if read.readable then
      sources[#sources + 1] = { kind = Locations.KIND_BAGS, read = read, live = true, where = Locations.Label(bagID) }
      reads[#reads + 1] = read
    end
  end
  return sources, Rows.Totals(reads)
end

-- One bank type's sources: live while open and viewable (and unlocked for the
-- warband), else the stored snapshot of each tab
local function BankSources(sources, kind, bankType, tabs, names, stored)
  local live = Snapshots.IsBankOpen() and Locations.CanView(bankType) == true
  if live and kind == Locations.KIND_WARBAND then
    local ok, reason = Locations.LockedReason(bankType)
    live = ok and reason == nil
  end
  if live then
    tabs = Locations.PurchasedTabs(bankType) or tabs
    names = Locations.TabNames(bankType)
  end
  for _, bagID in ipairs(tabs or {}) do
    local where = Locations.Label(bagID, names)
    local read = live and Reader.ReadContainer(bagID) or nil
    local entry = stored and stored[bagID]
    local storedRead = type(entry) == "table" and type(entry.read) == "table" and entry.read or nil
    if read and read.readable then
      sources[#sources + 1] = { kind = kind, read = read, live = true, where = where }
      -- A tab read in part (PI-10): the slots that failed keep their last-known
      -- copies, uncertain (changed), rather than dropping them
      if not read.complete and read.failed and storedRead and type(storedRead.slots) == "table" then
        local slots, any = {}, false
        for slot in pairs(read.failed) do
          if storedRead.slots[slot] then slots[slot], any = storedRead.slots[slot], true end
        end
        if any then
          sources[#sources + 1] = { kind = kind, read = { bagID = bagID, numSlots = read.numSlots, slots = slots, readable = true,
            complete = false }, live = false, where = where, asOf = entry.captured, changed = true }
        end
      end
    elseif storedRead then
      -- The stored snapshot: the bank is closed, or open with this tab's live
      -- read failing (BA-08), which would otherwise drop its items; a read still
      -- owed makes it as uncertain as a tab marked changed at close (PI-10)
      sources[#sources + 1] = { kind = kind, read = storedRead, live = false, where = where, asOf = entry.captured,
        changed = entry.changed == true or Snapshots.IsOwed(bagID) }
    end
  end
end

-- Both bank types are gathered even when one is hidden from the list, since
-- the live count covers the bank and the warband bank together
local function BankSourceList()
  local sources = {}
  local char = Snapshots.CurrentCharacter(false)
  BankSources(sources, Locations.KIND_BANK, Locations.BANK_TYPE_CHARACTER,
    char and char.bankTabs, char and char.bankTabNames, char and char.locations)
  local warband, db = Snapshots.Warband()
  BankSources(sources, Locations.KIND_WARBAND, Locations.BANK_TYPE_ACCOUNT,
    db and db.warbandTabs, db and db.warbandTabNames, warband)
  return sources
end

-- Freshness of the stored bank sources: { [itemID] = { stored, live } }
function Rows.BankFreshness(bankSources, bagTotals)
  local reads, anyStored = {}, false
  for _, source in ipairs(bankSources) do
    reads[#reads + 1] = source.read
    if not source.live then anyStored = true end
  end
  if not anyStored then return {} end
  return Rows.StaleItems(Rows.Totals(reads), bagTotals, Rows.WornCounts())
end

-- Other characters' stored bags and bank tabs, as sources
local function OtherSources()
  local sources = {}
  for _, entry in ipairs(Snapshots.OtherCharacters()) do
    local char = entry.char
    local other = { guid = entry.key, name = tostring(char.name or "another character"), faction = char.faction,
      class = char.class, race = char.race }
    local bagIDs = {}
    for bagID in pairs(char.locations) do bagIDs[#bagIDs + 1] = bagID end
    table.sort(bagIDs)
    for _, bagID in ipairs(bagIDs) do
      local stored = char.locations[bagID]
      if type(stored) == "table" and type(stored.read) == "table" then
        local kind = Locations.KindOf(bagID)
        if kind and kind ~= Locations.KIND_WARBAND then
          sources[#sources + 1] = { kind = kind, read = stored.read, live = false, asOf = stored.captured, other = other,
            changed = stored.changed == true,
            where = ("%s: %s"):format(other.name, Locations.Label(bagID, kind == Locations.KIND_BANK and char.bankTabNames or nil)) }
        end
      end
    end
  end
  return sources
end

function Rows.Build()
  local out = {}
  local bagSources, bagTotals = BagSources()
  for _, source in ipairs(bagSources) do AddSource(out, source, {}) end
  local bankSources = BankSourceList()
  local stale = Rows.BankFreshness(bankSources, bagTotals)
  local showBank = Config.Get(Config.Options.SHOW_BANK) ~= false
  local showWarband = Config.Get(Config.Options.SHOW_WARBAND) ~= false
  for _, source in ipairs(bankSources) do
    if (source.kind == Locations.KIND_BANK and showBank) or (source.kind == Locations.KIND_WARBAND and showWarband) then
      AddSource(out, source, stale)
    end
  end
  if Config.Get(Config.Options.LIST_OTHERS) == true then
    for _, source in ipairs(OtherSources()) do AddSource(out, source, {}) end
  end
  return out
end

-- Locate(pinned): where a pinned copy is now (PI-11): the source its bag or
-- tab gives as the list reads it now, with that item's freshness, as
-- { stack, live, changed, stale, asOf }; nil when that slot no longer holds it
function Rows.Locate(pinned)
  local sources, stale = {}, {}
  if pinned.other then
    for _, source in ipairs(OtherSources()) do
      if source.other.guid == pinned.other.guid then sources[#sources + 1] = source end
    end
  elseif pinned.kind == Locations.KIND_BAGS then
    sources = BagSources()
  else
    local _, bagTotals = BagSources()
    sources = BankSourceList()
    stale = Rows.BankFreshness(sources, bagTotals)
  end
  for _, source in ipairs(sources) do
    local stack = source.read.bagID == pinned.bagID and source.read.slots and source.read.slots[pinned.slot]
    if stack and stack.itemID == pinned.itemID then
      return { stack = stack, live = source.live == true, changed = source.changed == true, stale = stale[stack.itemID],
        asOf = source.asOf }
    end
  end
  return nil
end

-- For the Lab: the stored bank sources and their freshness, as the list sees
-- them right now
function Rows.CheckFreshness()
  local _, bagTotals = BagSources()
  local sources = BankSourceList()
  local stored = {}
  for _, source in ipairs(sources) do
    if not source.live then stored[#stored + 1] = source.read end
  end
  local totals = Rows.Totals(stored)
  return CobySuite_Recollect.Utilities.TableCount(totals), Rows.BankFreshness(sources, bagTotals)
end

Rows._test = { seams = seams, ResetWornSlots = function() wornSlots = nil end }
