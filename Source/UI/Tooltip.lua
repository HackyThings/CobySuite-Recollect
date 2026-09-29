-------------------------------------------------------------------------------
-- UI.Tooltip: Recollect on the tooltip of any item
--
-- The tooltip itself gets one line only, saying how to see the audit
-- ("Recollect: hold Alt for details"); the audit shows in its own panel
-- beside the tooltip (UI.AuditPanel) while the configured key is held (Alt
-- by default; Shift or Ctrl, or always, in the settings window).
--
-- Added through TooltipDataProcessor.AddTooltipPostCall for items, the hook
-- Blizzard provides for this (its callbacks run isolated from its own code),
-- on GameTooltip and ItemRefTooltip (a clicked chat link).
--   * An item in your bags, bank or warband bank (found from the tooltip
--     data's GUID: C_Item.GetItemLocation, then its bag and slot) is read
--     live and every check runs: the model holds the verdict, USED FOR,
--     COMES FROM, ABOUT and every check, which the details window shows
--     whole; the panel shows a short summary of it (UI.AuditPanel.Compact).
--   * Any other item (a link, a vendor's or the auction house's, loot, a
--     quest reward, an equipped item) gets reference mode: no verdict, how
--     many you have, and USED FOR and COMES FROM (contract rule 28). Where it was
--     shown comes from the tooltip's own processing info (its getter name),
--     never from its owner, which can be a bag frame's button.
--   * A mount (a mount link in chat, the Mount Journal) is shown as the item
--     that teaches it (Relations.MountItem, from AllTheThings), in reference
--     mode, so a linked mount says where it drops or who sells it. A mount or
--     pet also gets its journal's own source text under COMES FROM ("Mount
--     Journal: Drop: Time-Lost Proto-Drake; Zone: The Storm Peaks"), which
--     covers the mounts no item teaches.
-- The panel's model is built only when the panel would show (the key held,
-- or always): a hovered bag slot's tooltip is set again 5 times a second,
-- and a model nobody sees is wasted work. For the same tooltip showing the
-- same item it is built at most once in MODEL_REUSE seconds (Mark of Honor's
-- model reads about 8,700 purchases); data arriving (InventoryChanged) or a
-- setting changing builds it again at once. MODIFIER_STATE_CHANGED shows or
-- hides the panel while the tooltip stays up, building the model on the key
-- press; InventoryChanged (a quest's or an item's data arriving) builds the
-- shown model again, or marks a hidden one to be built again when it next
-- shows (a chat link's or a list row's tooltip is never set again by itself).
-- The settings are read at every refresh (BA-16): turning the tooltip off
-- hides the panel (and frees its keys) even while the same tooltip stays
-- up, turning it on or changing the key shows it again for that tooltip,
-- with no need to hover the item again.
--
-- The Tip (owner's decision, 2026-09-25): the verdict stays strict, and a
-- clearly labeled Tip under it may say what the player could do, the
-- choice left to them (TooltipUI.Tip, model.tip; the details window shows
-- the same words). When every check that decided is Purpose done, and the
-- verdict is Purpose done or Can't tell only because of a sign of a use no
-- check covers (Verdicts.OtherUses' note), it names the checks that are
-- done and those signs, and says the item is "most likely safe to sell or
-- delete, but that's your call". Junk gets the same words for selling it
-- to a vendor. Nothing else gets a Tip: never Outdated (the owner: no
-- delete wording unless clearly safe), never a row made Can't tell for
-- another character, a stale bank copy or a failed read, never reference
-- mode.
--
-- COMES FROM also opens with the item's season tag, where the game's own
-- season numbers put it (TooltipUI.SeasonLine, Purposes.Season: "From
-- Midnight Season 1 (a past season; Midnight Season 2 is current)"), and
-- the model carries the item's guide notes (model.notes, UI.UsedFor
-- NoteLines), which the panel shows apart under GUIDE NOTES.
-------------------------------------------------------------------------------
local TooltipUI = {}
Recollect.UI.Tooltip = TooltipUI

local U = CobySuite_Recollect.Utilities
local Try = Recollect.Utilities.Try
local IsPositiveID = Recollect.Utilities.IsPositiveID
local Config = Recollect.Config
local Locations = Recollect.Inventory.Locations

local seams = {
  Now = function() return GetTime() end,
  GetItemLocation = function(guid) return C_Item.GetItemLocation(guid) end,
  KeyDown = function(key)
    if key == "alt" then return IsAltKeyDown() end
    if key == "shift" then return IsShiftKeyDown() end
    if key == "ctrl" then return IsControlKeyDown() end
    return key == "always"
  end,
  -- The identity of the item a tooltip shows now (UI.AuditPanel.Identity)
  PrimaryGuid = function(tooltip) return Recollect.UI.AuditPanel.Identity(tooltip:GetPrimaryTooltipData()) end,
  -- Which getter filled the tooltip ("GetBagItem", "GetHyperlink", "GetMerchantItem", ...)
  Source = function(tooltip)
    local info = tooltip.GetProcessingTooltipInfo and tooltip:GetProcessingTooltipInfo()
    return type(info) == "table" and info.getterName or nil
  end,
  ItemCount = function(itemID, includeBank, includeAccount)
    return C_Item.GetItemCount(itemID, includeBank, false, includeBank, includeAccount)
  end,
  MountFromSpell = function(spellID) return C_MountJournal.GetMountFromSpell(spellID) end,
  MountSpell = function(mountID) return select(2, C_MountJournal.GetMountInfoByID(mountID)) end,
  MountName = function(mountID) return (C_MountJournal.GetMountInfoByID(mountID)) end,
  MountIcon = function(mountID) return select(3, C_MountJournal.GetMountInfoByID(mountID)) end,
  WornCounts = function() return Recollect.Verdicts.Rows.WornCounts() end,
  -- A clicked slot's tooltip data and the item's GUID (ClickModel)
  BagTooltip = function(bagID, slot) return C_TooltipInfo.GetBagItem(bagID, slot) end,
  ItemGUID = function(itemLocation) return C_Item.GetItemGUID(itemLocation) end,
  -- The tooltips the panel follows: the game's own and a clicked chat link's
  IsItemTooltip = function(tooltip) return tooltip == GameTooltip or tooltip == ItemRefTooltip end,
}

-- Where an item not in your bags was shown, by the tooltip's getter
local SOURCE_LABELS = {
  GetHyperlink = "Linked item", GetMerchantItem = "At this vendor", GetBuybackItem = "Buyback", GetLootItem = "Loot",
  GetLootRollItem = "Loot roll", GetQuestItem = "Quest reward", GetQuestLogItem = "Quest reward",
  GetInventoryItem = "Equipped", GetGuildBankItem = "Guild bank", GetItemKey = "Auction House",
  GetTradePlayerItem = "Trade", GetTradeTargetItem = "Trade", GetInboxItem = "Mail", GetSendMailItem = "Mail",
  GetRecipeResultItem = "Profession", GetRecipeReagentItem = "Profession", mount = "Mount",
  detail = "Opened from another item's details", click = "Clicked item",
}

local KEY_NAMES = { alt = "Alt", shift = "Shift", ctrl = "Ctrl" }

local current = nil   -- { tooltip, data, source, guid, model, dirty } for the item the tooltip showed last
local rowContext = nil   -- the list row being hovered (UI.ListWindow)

-- The list window says which row its next tooltip is for, and nil on leave
function TooltipUI.SetRowContext(entry)
  rowContext = entry
end

-- The configured key: "alt", "shift", "ctrl" or "always"
local function Key()
  local key = Config.Get(Config.Options.TOOLTIP_KEY)
  return (KEY_NAMES[key] or key == "always") and key or "alt"
end

-- The line the tooltip shows, or nil when the panel always shows
function TooltipUI.HintText(key)
  local name = KEY_NAMES[key]
  if not name then return nil end
  return U.WrapColor(Recollect.BRAND_COLOR, "Recollect") .. ": hold " .. name .. " for details"
end

-- The purposes in the order to show them: by the list's order of verdicts,
-- which puts the ones that decided the verdict first (Combine picks the
-- highest), a soft note (Registry.Info, which never decides) after the
-- checks of its rank, then in check order
local function Ordered(result)
  local rank = Recollect.Verdicts.RANK
  local list, position = {}, {}
  for i, purpose in ipairs(result.purposes) do
    list[i] = purpose
    position[purpose] = i
  end
  table.sort(list, function(a, b)
    local ra, rb = rank[a.verdict] or 9, rank[b.verdict] or 9
    if ra ~= rb then return ra < rb end
    local softA, softB = a.soft and true or false, b.soft and true or false
    if softA ~= softB then return softB end
    return position[a] < position[b]   -- the check order, so equal verdicts never swap
  end)
  return list
end

local NOT_TOLD = "Still needed? Can't tell yet"

-------------------------------------------------------------------------------
-- The Tip (see the header)
-------------------------------------------------------------------------------
TooltipUI.TIP_LABEL = "Tip"
local YOUR_CALL = "It's most likely safe to sell or delete, but that's your call."
local JUNK_TIP = "It's most likely safe to sell to any vendor with your other junk, but that's your call."
-- Verdicts.OtherUses' words, as what isn't checked
local UNCHECKED_WORDS = {
  reagent = "whether a recipe uses it",
  ["quest item"] = "whether a quest needs it",
  ["quest info (unreadable)"] = "its quest info, which can't be read",
}

-- The signs of a use no check covers, from Verdicts.Combine's note ("other
-- uses (reagent, quest item) not checked yet"); nil for any other note
local function Unchecked(note)
  local list = type(note) == "string" and note:match("^other uses %((.+)%) not checked yet$")
  if not list then return nil end
  local words = {}
  for part in (list .. ", "):gmatch("(.-), ") do
    if part ~= "" then words[#words + 1] = UNCHECKED_WORDS[part] or part end
  end
  return #words > 0 and words or nil
end

-- Tip(result): the Tip's words for a verdict, or nil when there is none
function TooltipUI.Tip(result)
  if type(result) ~= "table" then return nil end
  local V = Recollect.Purposes.Registry.Verdict
  if result.verdict == V.JUNK then return "The game marks it as junk. " .. JUNK_TIP end
  local unchecked
  if result.verdict == V.UNKNOWN then
    unchecked = Unchecked(result.note)
    if not unchecked then return nil end
  elseif result.verdict ~= V.DONE then
    return nil
  end
  local labels, seen = {}, {}
  for _, purpose in ipairs(result.purposes or {}) do
    if not purpose.soft then
      if purpose.verdict ~= V.DONE then return nil end
      local label = tostring(purpose.label or purpose.key or "a check")
      if not seen[label] then
        seen[label] = true
        labels[#labels + 1] = label
      end
    end
  end
  if #labels == 0 then return nil end
  local text = ("Every use Recollect read is done (%s)."):format(table.concat(labels, ", "))
  if unchecked then text = text .. " Not checked: " .. table.concat(unchecked, "; ") .. "." end
  return text .. " " .. YOUR_CALL
end

-- The item's season tag as the first COMES FROM line, where the game's own
-- season numbers put it (Purposes.Season, English clients), or nil
function TooltipUI.SeasonLine(tip)
  local Season = Recollect.Purposes.Season
  if not Season or type(tip) ~= "table" then return nil end
  local ok, tag = pcall(Season.Of, { Tooltip = function() return tip end })
  if not ok or type(tag) ~= "table" then return nil end
  local V, colors = Recollect.Purposes.Registry.Verdict, Recollect.UI.VerdictColors
  local label = ("%s Season %d"):format(tag.name, tag.number)
  local state, color, tier = "which season is current can't be read", U.Colors.LABEL_GRAY, nil
  if tag.state == "older" then
    state, color, tier = "a season of an older expansion", colors[V.OUTDATED], 3
  elseif tag.state == "past" then
    state, color, tier = ("a past season; %s Season %d is current"):format(tag.name, tag.current), colors[V.OUTDATED], 3
  elseif tag.state == "current" then
    state, color = "the current season", colors[V.USEFUL]
  elseif tag.state == "later" then
    state = ("the game shows %s Season %d as current"):format(tag.name, tag.current)
  elseif tag.state == "disagree" then
    state = "the game's season numbers disagree on which is current"
  end
  return { text = ("From %s (%s)"):format(label, state), color = color, tier = tier, season = true }
end

-- A tooltip's data parsed (Facts.Tooltip.Parse), or nil; USED FOR reads its
-- Use line (an older system, what using it gives)
local function ParsedTip(data)
  if type(data) ~= "table" then return nil end
  local ok, tip = pcall(Recollect.Facts.Tooltip.Parse, data)
  return ok and type(tip) == "table" and tip or nil
end

-- The season line for a parsed tooltip, first in comesFrom; the line or nil
local function AddSeasonLine(comesFrom, tip)
  local line = tip and TooltipUI.SeasonLine(tip) or nil
  if line then table.insert(comesFrom, 1, line) end
  return line
end

-- The panel says what an item is used for. It never repeats the item's own
-- tooltip, which shows beside it (Use and Equip text, flavor text, "This
-- Item Begins a Quest", the sell price), and never says what an item does
-- not do (Cobanyte, 2026-09-24).

-- The item's kind and expansion, which its tooltip doesn't name:
-- { "Miscellaneous: Other, from Dragonflight" }. The expansion is
-- Facts.Item.Expansion's (item 3): the game's own, unless AllTheThings'
-- added patch names a later one, and then both are said ("Key, from
-- Shadowlands (added in patch 9.1.0; the game files it under Battle for
-- Azeroth)"): the game's expansionID is where its data sits, not where the
-- item is used (the Seal Breaker Key opens a treasure in the Maw).
function TooltipUI.About(facts)
  if type(facts) ~= "table" then return {} end
  local R = Recollect.Purposes.Registry
  local kind = facts.itemType
  if kind and facts.itemSubType and facts.itemSubType ~= kind then kind = kind .. ": " .. facts.itemSubType end
  local okE, expansion, source, patch = pcall(Recollect.Facts.Item.Expansion, facts, facts.itemID)
  if not okE then expansion = nil end
  if not kind and type(expansion) ~= "number" then return {} end
  local from
  if type(expansion) == "number" then
    from = "from " .. R.ExpansionName(expansion)
    local patchText = source == "added" and Recollect.Facts.Item.PatchText(patch)
    if patchText then
      local game = facts.expansionID
      from = type(game) == "number" and game >= 0
        and ("%s (added in patch %s; the game files it under %s)"):format(from, patchText, R.ExpansionName(game))
        or ("%s (added in patch %s)"):format(from, patchText)
    end
  end
  return { kind and from and (kind .. ", " .. from) or kind or (from:gsub("^%l", string.upper)) }
end

-- What an Unknown item is used for, which the panel leads with in place of
-- the verdict: the words of a check with the verdict, else the first USED
-- FOR line (never a note such as "and 3 more"); nil when no use is known.
-- A reagent's line counts one profession's recipes, so the headline names
-- them all instead ("A crafting reagent in 11 recipes", as Purposes.Reagent
-- words it: item 11, one count stated one way)
local function Headline(result, extra)
  for _, purpose in ipairs(Ordered(result)) do
    if purpose.headline and purpose.verdict == result.verdict then return purpose.headline end
  end
  -- a line whose thing can't be read ("Linked to achievement 9539 (can't
  -- be read)") leads only when no other line can
  local unread
  for _, line in ipairs(extra.usedFor or {}) do
    if not line.note then
      if line.reagentTotal then
        return ("A crafting reagent in %d %s"):format(line.reagentTotal, line.reagentTotal == 1 and "recipe" or "recipes")
      end
      if not line.unread then return line.text end   -- a "Buys at ..." heading says a use too
      unread = unread or line.text
    end
  end
  return unread
end

-- The one step that can change an Unknown (G-04): the result's own words,
-- else its category's (Registry.CATEGORY); nil for any other verdict
function TooltipUI.Recovery(result)
  if result.verdict ~= Recollect.Purposes.Registry.Verdict.UNKNOWN then return nil end
  if result.recovery then return result.recovery end
  local category = result.category and Recollect.Purposes.Registry.CATEGORY[result.category]
  return category and category.recovery or nil
end

-- Every name USED FOR and COMES FROM heard (UI.UsedFor's line.links), so
-- the panel colors the same names where the verdict's and the checks'
-- reasons use them; a check doesn't say which of its words are names
function TooltipUI.Links(...)
  local out = {}
  for i = 1, select("#", ...) do
    for _, line in ipairs(select(i, ...) or {}) do
      for _, link in ipairs(line.links or {}) do out[#out + 1] = link end
    end
  end
  return out
end

-- Model(result, extra): what the panel shows.
-- extra: { guid (the identity), icon, where, about, usedFor, comesFrom,
-- notes, seasonLine, waypoint, buySummary, source } where source = { itemID,
-- stack, owner } names the copy for the pinned view (UI.DetailWindow) and
-- buySummary is UI.UsedFor's one line for every purchase (extra.buys), which
-- the audit panel shows in place of the "Buys at" groups; the model adds
-- tip (TooltipUI.Tip) and links (TooltipUI.Links)
-- The reason shows once: alone when one check ran, else each check with its own.
-- An Unknown with a known use leads with it (headline) and names the verdict
-- under the reason (verdictNote); with none, the verdict leads as any other.
-- An Unknown also names its one recovery step (recovery).
function TooltipUI.Model(result, extra)
  extra = extra or {}
  local colors = Recollect.UI.VerdictColors
  local model = {
    guid = extra.guid, icon = extra.icon, where = extra.where,
    verdict = result.verdict,
    label = Recollect.Purposes.Registry.VerdictLabel[result.verdict] or tostring(result.verdict),
    color = colors[result.verdict] or U.Colors.HIGHLIGHT_WHITE,
    reason = tostring(result.reason),
    recovery = TooltipUI.Recovery(result),
    result = result,
    source = extra.source,
    purposes = {},
    about = extra.about or {},
    usedFor = extra.usedFor or {},
    comesFrom = extra.comesFrom or {},
    notes = extra.notes or {},
    seasonLine = extra.seasonLine,
    waypoint = extra.waypoint,
    buySummary = extra.buySummary,
    tip = TooltipUI.Tip(result),
  }
  model.links = TooltipUI.Links(model.usedFor, model.comesFrom)
  if #result.purposes > 1 then
    local lead
    for _, purpose in ipairs(Ordered(result)) do
      model.purposes[#model.purposes + 1] = {
        label = purpose.label, reason = purpose.reason, color = colors[purpose.verdict] or U.Colors.LABEL_GRAY,
      }
      -- The deciding check: the first of the verdict's own, never a soft note
      if not lead and not purpose.soft and purpose.verdict == result.verdict then lead = purpose.reason end
    end
    -- The deciding check's words, not all of them joined; a note (an
    -- unchecked use, or a row made Unknown after its checks ran) says why
    -- instead, and with no deciding check the result's own reason stands
    model.reason = result.note and (result.note:gsub("^%l", string.upper)) or lead or tostring(result.reason)
  end
  model.headline = result.verdict == Recollect.Purposes.Registry.Verdict.UNKNOWN and Headline(result, extra) or nil
  if model.headline then
    model.verdictNote = NOT_TOLD
    -- A reason that opens with the headline's words says the rest only
    local headline, reason = model.headline, model.reason
    if #reason > #headline and reason:sub(1, #headline) == headline then
      local rest = reason:sub(#headline + 1):gsub("^[%s,;:]+", "")
      if rest ~= "" then model.reason = (rest:gsub("^%l", string.upper)) end
    end
  end
  -- The reason's own words never show again under COMES FROM (review F11:
  -- an item with only sources, every one gone, whose reason is its removal)
  local dropped = false
  for i = #model.comesFrom, 1, -1 do
    local text = model.comesFrom[i].text
    if text == model.reason or text == tostring(result.reason) then
      table.remove(model.comesFrom, i)
      dropped = true
    end
  end
  if dropped then model.links = TooltipUI.Links(model.usedFor, model.comesFrom) end
  return model
end

-- The bag and slot of the item a tooltip shows, from its GUID
local function SlotOf(data)
  local guid = data and data.guid
  if type(guid) ~= "string" or Recollect.Utilities.IsSecret(guid) then return nil end
  local ok, location = Try(seams.GetItemLocation, guid)
  if not ok or type(location) ~= "table" then return nil end
  local okKind, isBagAndSlot = pcall(location.IsBagAndSlot, location)
  if not okKind or not isBagAndSlot then return nil end
  local okSlot, bagID, slot = pcall(location.GetBagAndSlot, location)
  if not okSlot then return nil end
  return bagID, slot
end

-- The evaluated result for the item a tooltip shows, its facts, its stack,
-- its bag, its tooltip facts and its slot, or nil
function TooltipUI.Evaluate(data)
  local bagID, slot = SlotOf(data)
  local kind = bagID and Locations.KindOf(bagID)
  if not kind then return nil end
  local stack = Recollect.Inventory.Reader.ReadSlot(bagID, slot)
  if not stack or stack.itemID ~= data.id then return nil end
  local ctx = Recollect.Verdicts.Rows.ContextFor(stack, kind, bagID, slot, true)
  local tipFacts = Recollect.Facts.Tooltip.Parse(data)
  ctx.Tooltip = function() return tipFacts end
  return Recollect.Verdicts.Evaluate(ctx), ctx.facts, stack, bagID, tipFacts, slot
end

-- How many you have, place by place: { total, places = { { label, count,
-- words } } } (Bags, Worn, Bank, Warband bank), or nil
-- when a count can't be read. The bags-only count includes what is worn
-- (the Lab, 2026-09-24), so worn copies are named apart when every worn
-- slot could be read, and the bags are "on this character" when they
-- couldn't (BA-17, CR-05: never a count made up from part of the slots).
function TooltipUI.HeldCounts(itemID)
  local okBags, bags = Try(seams.ItemCount, itemID, false, false)
  local okBank, withBank = Try(seams.ItemCount, itemID, true, false)
  local okAll, all = Try(seams.ItemCount, itemID, true, true)
  local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber
  if not (okBags and okBank and okAll and IsFiniteNumber(bags) and IsFiniteNumber(withBank) and IsFiniteNumber(all)) then
    return nil
  end
  local okWorn, worn = pcall(seams.WornCounts)
  local wornHere = okWorn and type(worn) == "table" and (worn[itemID] or 0) or nil
  local places = {}
  if wornHere and wornHere <= bags then
    places[#places + 1] = { label = "Bags", count = bags - wornHere, words = "%d in your bags" }
    places[#places + 1] = { label = "Worn", count = wornHere, words = "%d worn", worn = true }
  else
    places[#places + 1] = { label = "On this character", count = bags, words = "%d on this character" }
  end
  places[#places + 1] = { label = "Bank", count = withBank - bags, words = "%d in your bank" }
  places[#places + 1] = { label = "Warband bank", count = all - withBank, words = "%d in the warband bank" }
  return { total = all, places = places }
end

-- How many you have, for reference mode: the label and the reason. A count
-- that can't be read says so.
function TooltipUI.HeldText(itemID)
  local held = TooltipUI.HeldCounts(itemID)
  if not held then return "How many you have can't be read", "" end
  if held.total <= 0 then return "You have none", "None in your bags, bank or warband bank" end
  local parts = {}
  for _, place in ipairs(held.places) do
    if not (place.worn and place.count == 0) then parts[#parts + 1] = place.words:format(place.count) end
  end
  return ("You have %d"):format(held.total), table.concat(parts, "; ")
end

-- The journal's own words for where a mount or pet comes from, as COMES
-- FROM lines ("Mount Journal: Drop: X; Zone: Y"); nothing when it has none
local JOURNAL_CHARS = 200
function TooltipUI.JournalLines(kind, id)
  local text = IsPositiveID(id) and Recollect.Facts.Journals.SourceText(kind, id)
  if not text or text == "" then return {} end
  local parts = {}
  for line in (text:gsub("\r?\n", "|n") .. "|n"):gmatch("(.-)|n") do
    local plain = CobySuite_Recollect.Utilities.StripColors(line):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
    plain = plain:match("^%s*(.-)%s*$")
    if plain ~= "" then parts[#parts + 1] = plain end
  end
  if #parts == 0 then return {} end
  local label = kind == "mount" and "Mount Journal: " or "Pet Journal: "
  return { { text = label .. U.Truncate(table.concat(parts, "; "), JOURNAL_CHARS), color = U.Colors.LIGHT_GRAY } }
end

-- The journal lines for an item that teaches a mount or a pet
local function ItemJournalLines(itemID)
  local client = Recollect.Purposes.client
  local okMount, mountID = Try(client.GetMountFromItem, itemID)
  if okMount and IsPositiveID(mountID) then return TooltipUI.JournalLines("mount", mountID) end
  local okPet, _, _, _, _, _, _, _, _, _, _, _, _, species = Try(client.GetPetInfoByItemID, itemID)
  if okPet and IsPositiveID(species) then return TooltipUI.JournalLines("pet", species) end
  return {}
end

local function Append(into, list)
  for _, line in ipairs(list) do into[#into + 1] = line end
  return into
end

-- Reference mode (contract rule 28): no verdict for an item you are not
-- holding in that slot; how many you have, then the same USED FOR and ABOUT
function TooltipUI.ReferenceModel(data, source)
  local itemID = data and data.id
  if not Recollect.Utilities.IsPositiveID(itemID) then return nil end
  local facts = Recollect.Facts.Item.Get(itemID)
  local label, reason = TooltipUI.HeldText(itemID)
  local owner = Recollect.Verdicts.Rows.Owner()
  local tip = ParsedTip(data)
  local usedFor, waypoint, comesFrom, lineExtra = Recollect.UI.UsedFor.Lines(itemID, nil, owner, { tip = tip, facts = facts })
  Append(comesFrom, ItemJournalLines(itemID))
  local seasonLine = AddSeasonLine(comesFrom, tip)
  return {
    guid = data.guid or Recollect.UI.AuditPanel.Identity(data), icon = facts and facts.texture,
    where = SOURCE_LABELS[source] or "Not in your bags", reference = true,
    label = label, color = U.Colors.HIGHLIGHT_WHITE, reason = reason, purposes = {},
    about = TooltipUI.About(facts), usedFor = usedFor, comesFrom = comesFrom, waypoint = waypoint,
    notes = Recollect.UI.UsedFor.NoteLines(itemID, owner), seasonLine = seasonLine,
    buySummary = lineExtra and lineExtra.buys or nil,
    source = { itemID = itemID, owner = owner, reference = true },
  }
end

-- A list row's model: the row's own verdict (its checks already ran), with
-- USED FOR and ABOUT read for the row's owner
function TooltipUI.RowModel(entry, data)
  local facts = Recollect.Facts.Item.Get(entry.itemID)
  local owner = entry.owner or Recollect.Verdicts.Rows.Owner()
  local tip = ParsedTip(data)
  local usedFor, waypoint, comesFrom, lineExtra = Recollect.UI.UsedFor.Lines(entry.itemID, entry.stack, owner,
    { tip = tip, facts = facts })
  local seasonLine = AddSeasonLine(comesFrom, tip)
  return TooltipUI.Model({ verdict = entry.verdict, reason = entry.reason, purposes = entry.purposes or {}, note = entry.note,
    category = entry.category, recovery = entry.recovery }, {
    guid = Recollect.UI.AuditPanel.Identity(data), icon = facts and facts.texture, where = entry.where,
    about = TooltipUI.About(facts), usedFor = usedFor, comesFrom = comesFrom, waypoint = waypoint,
    notes = Recollect.UI.UsedFor.NoteLines(entry.itemID, owner), seasonLine = seasonLine,
    buySummary = lineExtra and lineExtra.buys or nil,
    source = { itemID = entry.itemID, stack = entry.stack, owner = owner, where = entry.where, asOf = entry.asOf,
      live = entry.live, kind = entry.kind, bagID = entry.bagID, slot = entry.slot, other = entry.other,
      changed = entry.changed, stale = entry.stale },
  })
end

-- A mount's model: the item that teaches it, in reference mode, or, when no
-- item is known, the mount's own name with its journal's source text
function TooltipUI.MountModel(data)
  if data.itemID then
    local model = TooltipUI.ReferenceModel({ id = data.itemID, guid = data.guid }, "mount")
    if model and data.mountID and #ItemJournalLines(data.itemID) == 0 then
      Append(model.comesFrom, TooltipUI.JournalLines("mount", data.mountID))
    end
    return model
  end
  if not data.mountID then return nil end
  local okName, name = Try(seams.MountName, data.mountID)
  local okIcon, icon = Try(seams.MountIcon, data.mountID)
  local comesFrom = TooltipUI.JournalLines("mount", data.mountID)
  return { guid = data.guid, icon = okIcon and icon or nil, where = "Mount", reference = true,
    label = okName and type(name) == "string" and name or "Mount", color = U.Colors.HIGHLIGHT_WHITE,
    reason = #comesFrom > 0 and "Where it comes from is below" or "No item teaches it in Recollect's data", purposes = {},
    about = {}, usedFor = {}, comesFrom = comesFrom, notes = {}, source = { mountID = data.mountID, reference = true } }
end

-- A mount tooltip's data (its ID is the mount's spell, or its mount ID) as
-- { itemID, mountID, spellID, guid }, or nil
local function MountData(data)
  local id = type(data) == "table" and data.id
  if Recollect.Utilities.IsSecret(id) or not IsPositiveID(id) then return nil end
  local spellID, mountID = id, nil
  local ok, fromSpell = Try(seams.MountFromSpell, id)
  if ok and IsPositiveID(fromSpell) then
    mountID = fromSpell
  else
    local okSpell, spell = Try(seams.MountSpell, id)
    if okSpell and IsPositiveID(spell) then spellID, mountID = spell, id end
  end
  local itemID = Recollect.Facts.Relations.MountItem(spellID)
  if not itemID and not mountID then return nil end
  return { itemID = itemID, mountID = mountID, spellID = spellID, guid = Recollect.UI.AuditPanel.Identity(data) }
end
TooltipUI.MountData = MountData

-- The panel's model for a tooltip's item: a hovered list row's own verdict,
-- the full audit for a held slot, reference mode otherwise, or nil
local function BuildModel(data, source)
  if source == "mount" then return TooltipUI.MountModel(data) end
  if rowContext and type(data) == "table" and data.id == rowContext.itemID then return TooltipUI.RowModel(rowContext, data) end
  local result, facts, stack, bagID, tipFacts, slot = TooltipUI.Evaluate(data)
  if not result then return TooltipUI.ReferenceModel(data, source) end
  local owner = Recollect.Verdicts.Rows.Owner()
  local usedFor, waypoint, comesFrom, lineExtra = Recollect.UI.UsedFor.Lines(stack.itemID, stack, owner,
    { tip = tipFacts, facts = facts })
  Append(comesFrom, ItemJournalLines(stack.itemID))
  local seasonLine = TooltipUI.SeasonLine(tipFacts)
  if seasonLine then table.insert(comesFrom, 1, seasonLine) end
  return TooltipUI.Model(result, {
    guid = Recollect.UI.AuditPanel.Identity(data), icon = facts and facts.texture, where = Locations.Label(bagID),
    about = TooltipUI.About(facts), usedFor = usedFor, comesFrom = comesFrom, waypoint = waypoint,
    notes = Recollect.UI.UsedFor.NoteLines(stack.itemID, owner), seasonLine = seasonLine,
    buySummary = lineExtra and lineExtra.buys or nil,
    source = { itemID = stack.itemID, stack = stack, owner = owner, where = Locations.Label(bagID), live = true,
      kind = Locations.KindOf(bagID), bagID = bagID, slot = slot },
  })
end

-- The pin key's click on an item (UI.DetailWindow): a bag or bank slot gets
-- the full audit, as its tooltip would; an equipped item, a chat link, loot
-- or a vendor's item reference mode. link is the clicked item's link,
-- itemLocation its place when it has one. Returns a model or nil.
function TooltipUI.ClickModel(link, itemLocation)
  local itemID = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)"))
  if not IsPositiveID(itemID) then return nil end
  local located = type(itemLocation) == "table"
  local okBag, isBag = false, false
  if located then okBag, isBag = pcall(itemLocation.IsBagAndSlot, itemLocation) end
  if okBag and isBag then
    local okSlot, bagID, slot = pcall(itemLocation.GetBagAndSlot, itemLocation)
    local okTip, data = false, nil
    if okSlot then okTip, data = Try(seams.BagTooltip, bagID, slot) end
    local okGuid, guid = Try(seams.ItemGUID, itemLocation)
    if okTip and type(data) == "table" and okGuid and type(guid) == "string" then
      data.id = itemID
      data.guid = guid
      return BuildModel(data, "GetBagItem")
    end
  end
  local okWorn, worn = false, false
  if located then okWorn, worn = pcall(itemLocation.IsEquipmentSlot, itemLocation) end
  return TooltipUI.ReferenceModel({ id = itemID }, (okWorn and worn) and "GetInventoryItem" or "click")
end

-- A pinned model built again for new data (B3): a copy's verdict evaluated
-- again the way the list does (Rows.Verdict, with the staleness found when
-- it was pinned), or a reference model's counts read again. A live copy no
-- longer in its slot keeps what it said, marked gone. Returns the model.
-- opts.keepLines keeps the model's USED FOR and COMES FROM (the pinned view
-- reads its own tables, so only the verdict needs reading again).
function TooltipUI.Rebuild(model, opts)
  local source = type(model) == "table" and model.source
  if not source or not Recollect.Utilities.IsPositiveID(source.itemID) then return model end
  if source.reference then
    model.label, model.reason = TooltipUI.HeldText(source.itemID)
    return model
  end
  if type(source.stack) ~= "table" or not source.kind then return model end
  local stack = source.stack
  if source.live then
    local now = source.bagID and source.slot and Recollect.Inventory.Reader.ReadSlot(source.bagID, source.slot)
    if not now or now.itemID ~= source.itemID then
      model.gone = true
      return model
    end
    stack = now
    source.stack = now
  else
    -- a stored copy: found again where the list finds it now, with its current
    -- freshness, never the flags it had when pinned (PI-11); gone, it says so
    local now = Recollect.Verdicts.Rows.Locate(source)
    if not now then
      model.gone = true
      return model
    end
    stack = now.stack
    source.stack, source.changed, source.stale, source.asOf = now.stack, now.changed, now.stale, now.asOf
    if now.live then source.live = true end
  end
  local result = Recollect.Verdicts.Rows.Verdict(stack, source, source.bagID, source.slot, source.stale)
  local usedFor, waypoint, comesFrom, notes, buySummary
  if opts and opts.keepLines then
    usedFor, waypoint, comesFrom, notes, buySummary = model.usedFor, model.waypoint, model.comesFrom, model.notes,
      model.buySummary
  else
    -- no tooltip here: an older system's line reads the item's spell text
    local lineExtra
    usedFor, waypoint, comesFrom, lineExtra = Recollect.UI.UsedFor.Lines(source.itemID, stack, source.owner,
      { facts = Recollect.Facts.Item.Get(source.itemID) })
    buySummary = lineExtra and lineExtra.buys or nil
    -- the season tag came from the tooltip it was pinned from
    if model.seasonLine then table.insert(comesFrom, 1, model.seasonLine) end
    notes = Recollect.UI.UsedFor.NoteLines(source.itemID, source.owner)
  end
  return TooltipUI.Model(result, { guid = model.guid, icon = model.icon, where = model.where, about = model.about,
    usedFor = usedFor, comesFrom = comesFrom, notes = notes, seasonLine = model.seasonLine, waypoint = waypoint,
    buySummary = buySummary, source = source })
end

-- Show or hide the panel for what the tooltip shows now, building its model
-- first when there is none yet or data arrived since
-- The last model built, for the same tooltip still showing the same item
local MODEL_REUSE = 1
local built = nil   -- { tooltip, guid, source, model, at }

local function ModelFor(entry)
  local now = seams.Now()
  if built and built.tooltip == entry.tooltip and built.guid == entry.guid and built.source == entry.source
      and now - built.at < MODEL_REUSE then
    return built.model
  end
  local model = BuildModel(entry.data, entry.source)
  built = model and { tooltip = entry.tooltip, guid = entry.guid, source = entry.source, model = model, at = now } or nil
  return model
end

local function Refresh()
  local panel = Recollect.UI.AuditPanel
  if Config.Get(Config.Options.SHOW_TOOLTIP) == false then
    if panel.IsShown() then panel.Hide() end
    return
  end
  local showing = current and current.tooltip:IsShown()
  if showing then
    local ok, guid = pcall(seams.PrimaryGuid, current.tooltip)
    local want = current.guid or (current.model and current.model.guid)
    showing = ok and guid ~= nil and guid == want   -- still that item, not a later unit or spell
  end
  if not showing or not seams.KeyDown(Key()) then
    if panel.IsShown() then panel.Hide() end
    return
  end
  if current.dirty or not current.model then
    if current.dirty then built = nil end
    local ok, model = pcall(ModelFor, current)
    current.dirty = nil
    if ok and model then
      current.model = model
    elseif not ok then
      Recollect.Debug.Warn("UI", "Audit panel model failed: %s", tostring(model))
    end
  end
  if not current.model then
    if panel.IsShown() then panel.Hide() end
    return
  end
  panel.Show(current.tooltip, current.model)
end

local SafeRefresh
local refreshSoon = CobySuite_Recollect.Utilities.Coalesce(0, function() SafeRefresh() end)

function SafeRefresh()
  local ok, err = pcall(Refresh)
  if not ok then Recollect.Debug.Warn("UI", "Audit panel refresh failed: %s", tostring(err)) end
end

local function Section(tooltip, data, kind)
  if not seams.IsItemTooltip(tooltip) then return end
  if current and current.tooltip == tooltip then current = nil end
  if kind == "mount" then
    local mount = MountData(data)
    if not mount then
      Refresh()
      return
    end
    data = mount
  end
  -- A panel needs an item ID (BuildModel gives none without one), or a mount
  local guid = kind == "mount" and data.guid or Recollect.UI.AuditPanel.Identity(data)
  local itemID = guid and (kind == "mount" and (data.itemID or data.mountID) or data.id)
  if Recollect.Utilities.IsSecret(itemID) or not Recollect.Utilities.IsPositiveID(itemID) then
    Refresh()
    return
  end
  local okSource, source = pcall(seams.Source, tooltip)
  source = kind == "mount" and "mount" or (okSource and source or nil)
  -- Kept even while the tooltip setting is off, so turning it on shows the
  -- panel for the tooltip still up (BA-16)
  current = { tooltip = tooltip, data = data, source = source, guid = guid }
  if Config.Get(Config.Options.SHOW_TOOLTIP) == false then
    Refresh()
    return
  end
  -- Built now only when the panel would show; else on the key press (Refresh)
  if seams.KeyDown(Key()) then current.model = ModelFor(current) end
  local hint = TooltipUI.HintText(Key())
  if hint then
    local gray = U.Colors.LABEL_GRAY
    tooltip:AddLine(hint, gray[1], gray[2], gray[3])
  end
  refreshSoon:Call()   -- the tooltip shows after its post-calls; decide once it has (one per frame)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    local ok, err = pcall(Section, tooltip, data)
    if not ok then Recollect.Debug.Warn("UI", "Tooltip section failed: %s", tostring(err)) end
  end)
  -- A mount link in chat, or a mount in the Mount Journal (TooltipDataType 10)
  if Enum.TooltipDataType.Mount then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Mount, function(tooltip, data)
      local ok, err = pcall(Section, tooltip, data, "mount")
      if not ok then Recollect.Debug.Warn("UI", "Mount tooltip section failed: %s", tostring(err)) end
    end)
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("MODIFIER_STATE_CHANGED")
frame:SetScript("OnEvent", SafeRefresh)

-- A quest's, an achievement's or an item's data arriving: build the shown
-- model again; a hidden one is built again when the key is next pressed
local listener = {}
function listener:ReceiveEvent()
  built = nil   -- data arrived: the next model is built afresh
  if not current then return end
  if not Recollect.UI.AuditPanel.IsShown() then
    current.dirty = true
    return
  end
  local ok, model = pcall(ModelFor, current)
  if ok and model then
    current.model = model
    SafeRefresh()
  end
end
Recollect.EventBus:Register(listener, { Recollect.Events.InventoryChanged })

-- A setting changed (BA-16): the tooltip turned off hides the panel at once
-- (Hide frees the waypoint and pin keys); turned on, or a key changed, the
-- panel is decided again for the tooltip still up, its model built afresh
local configListener = {}
function configListener:ReceiveEvent()
  built = nil
  if current then current.dirty = true end
  SafeRefresh()
end
Recollect.EventBus:Register(configListener, { Recollect.Events.ConfigChanged })

TooltipUI._test = {
  seams = seams,
  Refresh = Refresh,
  Section = Section,
  SetCurrent = function(value) current = value end,
  Current = function() return current end,
  DataArrived = function() listener:ReceiveEvent() end,
  ConfigChanged = function() configListener:ReceiveEvent() end,
}
