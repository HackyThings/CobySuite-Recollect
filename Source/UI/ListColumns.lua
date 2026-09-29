-------------------------------------------------------------------------------
-- UI.ListColumns: the list window's columns and how a row paints them
-------------------------------------------------------------------------------
local Columns = {}
Recollect.UI.ListColumns = Columns

local U = CobySuite_Recollect.Utilities
local V = Recollect.Purposes.Registry.Verdict

local ICON_SIZE = 16

-- Keys are the row fields each column sorts on. The columns before Reason
-- add up to 764, so the default window (1100) leaves Reason about 300, and
-- the list keeps it at least REASON_MIN (BA-15: the old defaults added up to
-- 900 in a 1000-wide window and left it about 60)
Columns.REASON_MIN = 240
Columns.DEFS = {
  { key = "name", label = "Item", width = 200,
    tooltip = "The item, in its quality's color. Hover a row for its tooltip; click it for everything about it." },
  { key = "count", label = "Count", width = 44, justify = "RIGHT", tooltip = "How many are in this stack." },
  { key = "where", label = "Where", width = 120,
    tooltip = "The bag or bank tab it is in. Another character's rows start with that character's name." },
  { key = "purposeText", label = "Checks", width = 100,
    tooltip = "The checks that answered for it, such as Toy, Reagent, Gear, Buys or Season. The item details window's Checks section gives each one's answer." },
  { key = "usedForText", label = "Used for", width = 130,
    tooltip = "What the game's own data links the item to. The audit panel beside a hovered row (hold Alt, or the key chosen in the settings) sums it up; click the row for the full list, each with its state." },
  { key = "verdictRank", label = "Verdict", width = 90,
    tooltip = "Whether you still need it. Sorted by what to act on first: Needed, Use now, Useful, Can't tell, Junk, Outdated, Lower level, then Purpose done." },
  { key = "asOf", label = "Last read", width = 80,
    tooltip = "When Recollect last read this copy: live for what it reads now, else the date of the bank visit or login it was stored at." },
  { key = "reason", label = "Reason", width = 300, stretch = true,
    tooltip = "Why: the facts behind the verdict. The audit panel and the details window say more." },
}

-- One color per verdict, for the list, the audit panel, the details window
-- and the feature guide
local VERDICT_COLORS = {
  [V.NEEDED] = U.Colors.STATUS_GOLD,
  [V.USE] = U.Colors.SUCCESS_GREEN,
  [V.USEFUL] = U.Colors.INFO_BLUE,
  [V.UNKNOWN] = U.Colors.SLATE_GRAY,   -- light gray read like plain text (Cobanyte, 2026-09-27)
  [V.OUTDATED] = U.Colors.CAUTION_ORANGE,
  [V.LOWER] = U.Colors.SAND_TAN,
  [V.JUNK] = U.Colors.DISABLED_GRAY,   -- the gray of the game's own junk
  [V.DONE] = U.Colors.SAGE_GREEN,
}
Recollect.UI.VerdictColors = VERDICT_COLORS

local function QualityColor(quality)
  local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  if color then return color.r, color.g, color.b end
  return 1, 1, 1
end

-- Builds the row's regions once
function Columns.EnsureRow(row, columns)
  if row._cells then return end
  row._cells = {}
  for i, col in ipairs(columns) do
    local text = row:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
    text:SetJustifyH(col.justify or "LEFT")
    text:SetWordWrap(false)
    row._cells[i] = text
  end
  row.Icon = row:CreateTexture(nil, "ARTWORK")
  row.Icon:SetSize(ICON_SIZE, ICON_SIZE)
  CobySuite_Recollect.UI.AddHoverHighlight(row)
end

-- Places each cell under its column. The stretch column (Reason) runs to the
-- row's right edge, as its header does: the header never changes its width,
-- so anchoring both edges is what keeps the cell as wide as the header
-- through window and column resizes.
function Columns.Layout(row, columns)
  local x = 0
  for i, col in ipairs(columns) do
    local text = row._cells[i]
    if not text then break end
    local width = col.width or 50
    text:ClearAllPoints()
    if col.key == "name" then
      row.Icon:ClearAllPoints()
      row.Icon:SetPoint("LEFT", row, "LEFT", x + 4, 0)
      text:SetPoint("LEFT", row, "LEFT", x + ICON_SIZE + 8, 0)
      text:SetWidth(math.max(width - ICON_SIZE - 12, 10))
    elseif col.stretch then
      text:SetPoint("LEFT", row, "LEFT", x + 4, 0)
      text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    else
      text:SetPoint("LEFT", row, "LEFT", x + 4, 0)
      text:SetWidth(math.max(width - 8, 10))
    end
    x = x + width
  end
end

local function AsOfText(entry)
  if entry.live then return "live" end
  if type(entry.asOf) == "number" then return date("%m-%d %H:%M", entry.asOf) end
  return "?"
end

-- The text a row's cell shows for a column key; Paint and Measure both use
-- it, so a fitted column is as wide as what it paints
local CELL_TEXT = {
  name = function(entry) return entry.name or "?" end,
  count = function(entry) return tostring(entry.count or 1) end,
  where = function(entry) return entry.where or "" end,
  purposeText = function(entry) return entry.purposeText or "-" end,
  usedForText = function(entry) return entry.usedForText or "" end,
  verdictRank = function(entry) return entry.verdictLabel or "" end,
  asOf = AsOfText,
  reason = function(entry) return entry.reason or "" end,
}

function Columns.CellText(entry, key)
  local text = CELL_TEXT[key]
  return text and text(entry) or ""
end

-- The width a column needs for the rows given (a divider's double-click, the
-- header's measureColumn): the widest cell text, measured on fontString in
-- the cells' font, plus Layout's insets (the Item column's icon included).
-- At most MEASURE_ROWS rows are read; nil when none has text.
local MEASURE_ROWS = 2000

function Columns.Measure(rows, key, fontString)
  local widest = 0
  for i = 1, math.min(#rows, MEASURE_ROWS) do
    local text = Columns.CellText(rows[i], key)
    if text ~= "" then
      fontString:SetText(text)
      local width = fontString:GetUnboundedStringWidth() or 0
      if width > widest then widest = width end
    end
  end
  if widest <= 0 then return nil end
  local inset = key == "name" and (ICON_SIZE + 12) or 8
  return math.ceil(widest + inset + 2)
end

function Columns.Paint(row, entry, columns, index)
  row._entry = entry
  row.Icon:SetTexture(entry.icon or 134400)
  for i, col in ipairs(columns) do
    local text = row._cells[i]
    if not text then break end
    text:SetText(Columns.CellText(entry, col.key))
    local white = U.Colors.HIGHLIGHT_WHITE
    text:SetTextColor(white[1], white[2], white[3])
    if col.key == "name" then
      text:SetTextColor(QualityColor(entry.quality))
    elseif col.key == "usedForText" or col.key == "reason" then
      local c = U.Colors.LIGHT_GRAY
      text:SetTextColor(c[1], c[2], c[3])
    elseif col.key == "verdictRank" then
      local c = VERDICT_COLORS[entry.verdict] or U.Colors.HIGHLIGHT_WHITE
      text:SetTextColor(c[1], c[2], c[3])
    elseif col.key == "asOf" then
      local c = entry.live and U.Colors.LABEL_GRAY or U.Colors.STATUS_GOLD
      text:SetTextColor(c[1], c[2], c[3])
    end
  end
  U.AddAlternatingRowBg(row, index or 0)
end
