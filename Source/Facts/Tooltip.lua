-------------------------------------------------------------------------------
-- Facts.Tooltip: the few tooltip lines Recollect compares against
--
-- The tooltip is Blizzard's own summary of an item for this character, so it
-- is the independent second source for the collection checks (contract rule
-- 5): a collected toy or mount shows "Already known", a pet shows
-- "Collected (n/m)". It also carries what no other call gives: "Locked" on a
-- lockbox, "This Item Begins a Quest", and red lines for requirements this
-- character does not meet.
--
-- Parse(data) returns
--   { known, locked, beginsQuest, redLines, lineCount,
--     useText,                   -- the first "Use: ..." line (ITEM_SPELL_TRIGGER_ONUSE)
--     seasonExpansion, seasonNumber,  -- a "<Expansion> Season <n>" tag line (English)
--     appearanceMissing,         -- "You haven't collected this appearance"
--     appearanceOther,           -- "...collected this appearance, but not from this item"
--     factionOnly,               -- 0 (Horde) or 1 (Alliance) for a "Horde Only" /
--                                --  "Alliance Only" line (ITEM_REQ_HORDE / _ALLIANCE), as PvPFaction
--     bagSlots, bagKind,         -- a bag's "36 Slot Bag" line (CONTAINER_SLOTS)
--     decorReadable,             -- whether the two decor formats below exist
--     decorOwned,                -- { total, placed, stored } from "Total Owned: 3 (Placed: 1,
--                                --  Storage: 2)" (HOUSING_DECOR_OWNED_COUNT_FORMAT)
--     decorBonus,                -- n from "First-Time Collection Bonus: +n House XP"
--                                --  (HOUSING_DECOR_FIRST_ACQUISITION_FORMAT)
--     lineTypes,                 -- { [Enum.TooltipDataLineType] = true } for every line
--     petCollected, petLimit,    -- the pet numbers only when that line shows
--     questLines }               -- { { type, text } } for quest title,
--                                --  objective and player lines (8, 17, 18)
-- or nil when there is no data or any line is secret. Lines are matched
-- against the client's own localized global strings, so this works in every
-- locale. Data comes from C_TooltipInfo getters, which build no frame and
-- touch no GameTooltip.
-------------------------------------------------------------------------------
local Tooltip = {}
Recollect.Facts.Tooltip = Tooltip

local Try = Recollect.Utilities.Try

local function IsSecret(value) return Recollect.Utilities.IsSecret(value) end

local seams = {
  GetBagItem = function(bagID, slot) return C_TooltipInfo.GetBagItem(bagID, slot) end,
  GetHyperlink = function(link) return C_TooltipInfo.GetHyperlink(link) end,
  GetItemByID = function(itemID) return C_TooltipInfo.GetItemByID(itemID) end,
}

local function Global(name)
  local value = _G[name]
  return type(value) == "string" and value ~= "" and value or nil
end

-- Text without color codes (CobySuite.Utilities.StripColors: "|cFFxxxxxx",
-- "|cFF 0FF 0", named "|cnHIGHLIGHT_FONT_COLOR:", "|r" / "|R")
Tooltip.StripColors = CobySuite_Recollect.Utilities.StripColors

-- A format string such as "Collected (%d/%d)" or "%d Slot %s" as a pattern
-- with captures; nil for a format with positional arguments ("%1$d"), whose
-- captures could come back in another order
function Tooltip.FormatToPattern(fmt)
  if fmt:find("%%%d") then return nil end
  local escaped = CobySuite_Recollect.Utilities.EscapePattern(fmt)
  escaped = escaped:gsub("%%%%d", "(%%d+)"):gsub("%%%%s", "(.+)")
  return "^" .. escaped .. "$"
end

local STRINGS                -- resolved on first use: the globals load before us,
local function Strings()     -- but suites may swap them
  if STRINGS then return STRINGS end
  local pet, slots = Global("ITEM_PET_KNOWN"), Global("CONTAINER_SLOTS")
  local owned, bonus = Global("HOUSING_DECOR_OWNED_COUNT_FORMAT"), Global("HOUSING_DECOR_FIRST_ACQUISITION_FORMAT")
  STRINGS = {
    known = Global("ITEM_SPELL_KNOWN"),
    locked = Global("LOCKED"),
    beginsQuest = Global("ITEM_STARTS_QUEST"),
    useTrigger = Global("ITEM_SPELL_TRIGGER_ONUSE"),
    appearanceMissing = Global("TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN"),
    appearanceOther = Global("TRANSMOGRIFY_TOOLTIP_ITEM_UNKNOWN_APPEARANCE_KNOWN"),
    petPattern = pet and Tooltip.FormatToPattern(pet) or nil,
    horde = Global("ITEM_REQ_HORDE"),
    alliance = Global("ITEM_REQ_ALLIANCE"),
    slotsPattern = slots and Tooltip.FormatToPattern(slots) or nil,
    -- Matched against color-stripped text: the numbers carry color codes
    decorOwned = owned and Tooltip.FormatToPattern(Tooltip.StripColors(owned)) or nil,
    decorBonus = bonus and Tooltip.FormatToPattern(Tooltip.StripColors(bonus)) or nil,
  }
  return STRINGS
end

-- RED_FONT_COLOR is 1, 0.125, 0.125
local function IsRed(color)
  if type(color) ~= "table" then return false end
  local r, g, b = color.r, color.g, color.b
  if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return false end
  return r > 0.95 and g < 0.2 and b < 0.2
end

-- Enum.TooltipDataLineType: QuestObjective 8, QuestTitle 17, QuestPlayer 18
local QUEST_LINE_TYPES = { [8] = true, [17] = true, [18] = true }

local function ReadLine(facts, s, line)
  local text = line.leftText
  if IsSecret(text) or IsSecret(line.leftColor) then return false end
  if type(line.type) == "number" then facts.lineTypes[line.type] = true end
  if type(text) ~= "string" then return true end
  if QUEST_LINE_TYPES[line.type] then facts.questLines[#facts.questLines + 1] = { type = line.type, text = text } end
  if s.known and text == s.known then
    facts.known = true
  elseif s.locked and text == s.locked then
    facts.locked = true
  elseif s.beginsQuest and text == s.beginsQuest then
    facts.beginsQuest = true
  elseif s.appearanceMissing and text == s.appearanceMissing then
    facts.appearanceMissing = true
  elseif s.appearanceOther and text == s.appearanceOther then
    facts.appearanceOther = true
  elseif s.horde and text == s.horde then
    facts.factionOnly = 0
  elseif s.alliance and text == s.alliance then
    facts.factionOnly = 1
  elseif s.slotsPattern and not facts.bagSlots and text:find(s.slotsPattern) then
    local count, kind = text:match(s.slotsPattern)
    facts.bagSlots, facts.bagKind = tonumber(count), kind
  elseif s.petPattern then
    local collected, limit = text:match(s.petPattern)
    if collected then
      facts.petCollected = tonumber(collected)
      facts.petLimit = tonumber(limit)
    end
  end
  if s.useTrigger and not facts.useText and text:sub(1, #s.useTrigger) == s.useTrigger then facts.useText = text end
  -- Lines read without their color codes: season tags and the decor counts carry them
  local plain = Tooltip.StripColors(text)
  if s.decorOwned and not facts.decorOwned then
    local total, placed, stored = plain:match(s.decorOwned)
    if total then facts.decorOwned = { total = tonumber(total), placed = tonumber(placed), stored = tonumber(stored) } end
  end
  if s.decorBonus and not facts.decorBonus then
    local bonus = plain:match(s.decorBonus)
    if bonus then facts.decorBonus = tonumber(bonus) end
  end
  if not facts.seasonExpansion then
    local expansion, season = plain:match("^(.-) Season (%d+)$")
    if expansion and expansion ~= "" then
      facts.seasonExpansion, facts.seasonNumber = expansion, tonumber(season)
    end
  end
  if IsRed(line.leftColor) then facts.redLines = facts.redLines + 1 end
  return true
end

function Tooltip.Parse(data)
  if type(data) ~= "table" or type(data.lines) ~= "table" or #data.lines == 0 then return nil end
  local s = Strings()
  local facts = { known = false, locked = false, beginsQuest = false, redLines = 0, lineCount = #data.lines, questLines = {},
    appearanceMissing = false, appearanceOther = false, lineTypes = {},
    decorReadable = s.decorOwned ~= nil and s.decorBonus ~= nil }
  for _, line in ipairs(data.lines) do
    if type(line) == "table" and not ReadLine(facts, s, line) then return nil end
  end
  return facts
end

function Tooltip.FromBagSlot(bagID, slot)
  local ok, data = Try(seams.GetBagItem, bagID, slot)
  if not ok then return nil end
  return Tooltip.Parse(data)
end

function Tooltip.FromItemID(itemID)
  local ok, data = Try(seams.GetItemByID, itemID)
  if not ok then return nil end
  return Tooltip.Parse(data)
end

function Tooltip.FromLink(link)
  if type(link) ~= "string" then return nil end
  local ok, data = Try(seams.GetHyperlink, link)
  if not ok then return nil end
  return Tooltip.Parse(data)
end

Tooltip._test = {
  seams = seams,
  ResetStrings = function() STRINGS = nil end,
}
