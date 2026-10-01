-------------------------------------------------------------------------------
-- Curator.DashTable: the curator dashboard's tables (Findings, History)
--
-- A small sortable table on the shared TableHeader (CobySuite.UI): a header
-- with sortable, resizable columns fitted to the window's width (fitToWidth:
-- the stretch column takes what the others leave, never less than
-- minStretch), widths kept in RECOLLECT_CURATOR_DB.windows under
-- "curator_<key>", and a fixed pool of rows made at build and scrolled with
-- FauxScrollFrameTemplate, so showing, scrolling and resizing are safe in
-- combat. Curator code may not use Recollect's own table (the boundary), so
-- this is the curator's.
--   local t = DashTable.Create(parent, {
--     key, pool, rowHeight, minStretch, columns (Dashboard's: key, label,
--     width, stretch, justify, tooltip, text(row), color(row), icon(row) for
--     the one column that shows an icon, load(row) called when a row is
--     painted, sortValue(row)),
--     sortKey, ascending, onSort(key, ascending), onRowEnter(frame, row) })
--   t:SetRows(rows)   t:Refresh()   t.frame
-- Rows are shown as given: sorting and filtering are the caller's.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local U = CobySuite_Recollect.Utilities

local DashTable = {}
Curator.DashTable = DashTable

local HEADER_H = 20
local ICON = 16
local SCROLL_ROOM = 22
DashTable.SCROLL_ROOM = SCROLL_ROOM

local Table = {}
Table.__index = Table

local function MakeRow(t, i)
  local row = CreateFrame("Button", nil, t.list)
  row:SetHeight(t.rowHeight)
  row:SetPoint("TOPLEFT", t.list, "TOPLEFT", 0, -(i - 1) * t.rowHeight)
  row:SetPoint("RIGHT", t.list, "RIGHT", 0, 0)
  CobySuite_Recollect.UI.AddHoverHighlight(row)
  row.Icon = row:CreateTexture(nil, "ARTWORK")
  row.Icon:SetSize(ICON, ICON)
  row.cells = {}
  for c = 1, #t.columns do
    local text = row:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
    text:SetWordWrap(false)
    row.cells[c] = text
  end
  row:SetScript("OnEnter", function(self)
    if self.data and t.opts.onRowEnter then t.opts.onRowEnter(self, self.data) end
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:Hide()
  return row
end

local function BuildHeader(t, opts)
  local header = CreateFrame("Frame", nil, t.frame)
  Mixin(header, CobySuite_Recollect.UI.TableHeaderMixin)
  header:SetPoint("TOPLEFT", t.frame, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", t.frame, "TOPRIGHT", -SCROLL_ROOM, 0)
  header:SetHeight(HEADER_H)
  local columns = {}
  for i, col in ipairs(opts.columns) do
    columns[i] = { key = col.key, label = col.label, width = col.width, stretch = col.stretch, justify = col.justify,
      tooltip = col.tooltip, sortable = col.sortable ~= false }
  end
  header:Init({
    columns = columns, persistenceKey = "curator_" .. opts.key,
    persistence = { savedVariable = "RECOLLECT_CURATOR_DB", path = "windows" },
    utilities = U, headerHeight = HEADER_H, fitToWidth = true, minStretch = opts.minStretch or 120,
    onSort = function(key, dir)
      if opts.onSort then opts.onSort(key, dir == CobySuite_Recollect.SortDir.ASC) end
    end,
    onColumnResize = function() t:Layout() end,
  })
  header:HookScript("OnSizeChanged", function() t:Layout() end)
  if opts.sortKey then
    header:SetSort(opts.sortKey, opts.ascending == false and CobySuite_Recollect.SortDir.DESC or CobySuite_Recollect.SortDir.ASC)
  end
  t.header = header
end

-- Create(parent, opts): the table; every frame is made here
function DashTable.Create(parent, opts)
  local t = setmetatable({ opts = opts, columns = opts.columns, rows = {}, pool = {}, rowHeight = opts.rowHeight or 20 }, Table)
  for c, col in ipairs(opts.columns) do
    if col.icon and not t.iconColumn then t.iconColumn = c end
  end
  local frame = CreateFrame("Frame", nil, parent)
  t.frame = frame
  local list = CreateFrame("Frame", nil, frame)
  list:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -HEADER_H - 2)
  list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SCROLL_ROOM, 0)
  list:SetClipsChildren(true)
  t.list = list
  local scroll = CreateFrame("ScrollFrame", nil, frame, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, t.rowHeight, function() t:Paint() end)
  end)
  t.scroll = scroll
  BuildHeader(t, opts)
  for i = 1, opts.pool or 30 do t.pool[i] = MakeRow(t, i) end
  frame:SetScript("OnSizeChanged", function() t:Layout() t:Refresh() end)
  return t
end

-- Places each row's cells under the header's columns
function Table:Layout()
  local header = self.header
  if header.FitColumns then pcall(header.FitColumns, header) end
  header:RepositionHeaders()
  local bounds = header:GetColumnBounds()
  for _, row in ipairs(self.pool) do
    for c, text in ipairs(row.cells) do
      local b, col = bounds[c], self.columns[c]
      text:ClearAllPoints()
      if b and col then
        text:Show()
        text:SetJustifyH(col.justify or "LEFT")
        local inset = 4
        if c == self.iconColumn then
          row.Icon:ClearAllPoints()
          row.Icon:SetPoint("LEFT", row, "LEFT", b.left + 4, 0)
          inset = ICON + 8
        end
        text:SetPoint("LEFT", row, "LEFT", b.left + inset, 0)
        text:SetWidth(math.max(b.width - inset - 4, 10))
      else
        text:Hide()
      end
    end
  end
end

function Table:SetRows(rows)
  self.rows = rows or {}
  self:Refresh()
end

-- How many rows fit now (never more than the pool)
function Table:Visible()
  local height = self.list:GetHeight() or 0
  return math.max(0, math.min(#self.pool, math.floor(height / self.rowHeight)))
end

function Table:Refresh()
  FauxScrollFrame_Update(self.scroll, #self.rows, self:Visible(), self.rowHeight)
  self:Paint()
end

local function Cell(fn, row)
  if not fn then return nil end
  local ok, value = pcall(fn, row)
  return ok and value or nil
end

-- Sets an icon that is a texture or "atlas:<name>"
local function SetIcon(texture, icon)
  local atlas = type(icon) == "string" and icon:match("^atlas:(.+)$")
  if atlas then
    texture:SetAtlas(atlas)
  else
    texture:SetTexture(icon or 134400)
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  end
end
DashTable.SetIcon = SetIcon

-- Paints the rows on screen from the scroll offset (names are read here,
-- for these rows only, and each column's load hook runs for them)
function Table:Paint()
  local offset = FauxScrollFrame_GetOffset(self.scroll)
  local visible = self:Visible()
  local white = U.Colors.HIGHLIGHT_WHITE
  local iconCol = self.iconColumn and self.columns[self.iconColumn]
  for i, frame in ipairs(self.pool) do
    local index = offset + i
    local data = i <= visible and self.rows[index] or nil
    frame.data = data
    if not data then
      frame:Hide()
    else
      frame:Show()
      U.AddAlternatingRowBg(frame, index)
      frame.Icon:SetShown(iconCol ~= nil)
      if iconCol then SetIcon(frame.Icon, Cell(iconCol.icon, data)) end
      for c, col in ipairs(self.columns) do
        if col.load then Cell(col.load, data) end
        local text = frame.cells[c]
        text:SetText(tostring(Cell(col.text, data) or ""))
        local color = (col.color and Cell(col.color, data)) or white
        text:SetTextColor(color[1], color[2], color[3])
      end
    end
  end
end
