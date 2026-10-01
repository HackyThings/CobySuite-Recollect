-------------------------------------------------------------------------------
-- UI.DataTable: rows in columns, one header per view, a fixed pool of rows
--
-- A table widget that knows nothing of Recollect (a candidate for the shared
-- library, /shared):
--   local t = DataTable.Create(parent, {
--     name, pool = 40, rowHeight = 20, maxCells = 8, utilities,
--     persistence = { savedVariable = "NAME", path = "key" },   -- column widths
--     onRowClick = function(row, columnKey, mouseButton, frame) end,
--     onRowEnter = function(frame, row, columnKey) end,   -- again whenever
--                  -- the column under the cursor changes; the first column
--                  -- (the thing itself) counts only over its icon and text,
--                  -- elsewhere in it columnKey is nil
--     onRowLeave = function(frame, row) end,
--     onSort = function(viewKey, columnKey, ascending) end,
--     rowButton = function(parent) -> button,   -- one icon button a row,
--                  -- made here, for a column with button
--     rowAltButton = function(row) -> button,   -- optional: a second one in
--                  -- the same place, shown instead when the column's
--                  -- button.alt(row) is true; it handles its own clicks
--                  -- (the details window's secure achievement button)
--   })
--   t:AddView(key, columns, { minStretch, sortKey, ascending })
--     columns = { { key, label, width, stretch, justify, tooltip, sortable,
--       text = function(row) -> string, color = function(row) -> { r, g, b },
--       markup = function(row) -> string,   (inline markup painted before the
--         text, such as a state icon, UI.Icons; never part of text)
--       bar = function(row) -> 0 to 1 or nil,   (a progress bar behind the
--         cell's text, as wide as that share of the column)
--       barColor = { r, g, b, a },
--       fill = function(row) -> { r, g, b, a } or nil,   (the whole cell's
--         background, behind any bar: a muted tint that keeps the text readable)
--       aside = { width, text = function(row) -> string },   (a second text
--         in a slot of its own at the cell's right, left-justified, so it
--         starts at the same place on every row: the curator console's
--         "75 (6.0 KB)", the count right-justified before it)
--       icon = function(row) -> fileID or atlas, true,    (first column)
--       button = { shown = function(row), onClick = function(row, button),
--         onEnter = function(button, row), alt = function(row),
--         onAltEnter = function(altButton, row) } } }   (the row's button,
--         centered; alt true shows the alternate button there)
--   t:ShowView(key)   t:SetRows(key, rows)   t:Refresh()   t:GetSort(key)
-- Double-clicking a column's divider fits it to its title and its cells'
-- text (the header's measureColumn: Table:MeasureColumn, the first
-- MEASURE_ROWS rows in their order), as a spreadsheet does.
--   t:FitView(key)   every column fitted to what the view shows, except
--                    the ones the user sized (Cobanyte, 2026-09-26): a drag
--                    keeps that column's width, saved beside the widths
--                    (persistence path .. "User"), for every item after;
--                    a double-click or Reset Column Widths hands it back
-- A view's rows are shown as given: sorting and filtering are the caller's
-- (onSort says what was asked). Every frame is made by Create and AddView,
-- none later, so showing, scrolling and resizing the table are safe in
-- combat; the pool is as many rows as the tallest window shows, and the
-- rest are reached by scrolling (FauxScrollFrameTemplate, Blizzard_SharedXML).
-------------------------------------------------------------------------------
local DataTable = {}
Recollect.UI.DataTable = DataTable

local U = CobySuite_Recollect.Utilities
local SortDir = CobySuite_Recollect.SortDir

local HEADER_HEIGHT = 20
local ICON = 16
local SCROLL_ROOM = 22   -- the scroll bar sits right of the rows
local ASIDE_GAP = 4      -- between a cell's text and its aside
local MEASURE_ROWS = 2000   -- rows a divider's double-click measures
local FIT_ROWS = 300        -- rows FitView measures, so opening an item never hitches

local Table = {}
Table.__index = Table

local seams = {
  Cursor = function() return GetCursorPosition() end,
}

-- Where each column of a view sits: the header's own bounds (a stretch
-- column, when a view has one, takes what the others leave), so rows and
-- header never disagree
local function Bounds(view)
  return view.header:GetColumnBounds()
end

local function ColumnAt(t, frame)
  local view = t.views[t.active]
  if not view then return nil end
  local scale = frame:GetEffectiveScale()
  local x = (seams.Cursor() / scale) - (frame:GetLeft() or 0)
  for i, b in ipairs(view.bounds or Bounds(view)) do
    if x >= b.left and x < b.left + b.width then
      -- the first column is the thing itself: only its icon and text count
      if i == 1 then
        local shown = math.min(frame.cells[1]:GetStringWidth() or 0, b.width)
        if x > b.left + ICON + 8 + shown + 4 then return nil end
      end
      return b.key
    end
  end
  return nil
end

-- The column under the cursor, told to onRowEnter whenever it changes, and
-- when the row's data does (the list scrolled under a still cursor)
local function Hover(t, frame)
  local key = ColumnAt(t, frame)
  if key == frame.hoverKey and frame.data == frame.hoverData then return end
  frame.hoverKey, frame.hoverData = key, frame.data
  if frame.data and t.opts.onRowEnter then t.opts.onRowEnter(frame, frame.data, key) end
end

local function MakeRow(t, list, i)
  local rowHeight = t.rowHeight
  local row = CreateFrame("Button", nil, list)
  row:SetHeight(rowHeight)
  row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * rowHeight)
  row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  CobySuite_Recollect.UI.AddHoverHighlight(row)
  row.Icon = row:CreateTexture(nil, "ARTWORK")
  row.Icon:SetSize(ICON, ICON)
  row.cells, row.asides, row.bars, row.barRoom, row.fills = {}, {}, {}, {}, {}
  for c = 1, t.maxCells do
    local text = row:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
    text:SetWordWrap(false)
    row.cells[c] = text
    local aside = row:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
    aside:SetWordWrap(false)
    aside:SetJustifyH("LEFT")
    aside:Hide()
    row.asides[c] = aside
    local fill = row:CreateTexture(nil, "BORDER", nil, -1)
    fill:SetHeight(math.max(2, rowHeight - 2))
    fill:Hide()
    row.fills[c] = fill
    local bar = row:CreateTexture(nil, "BORDER")
    bar:SetHeight(math.max(2, rowHeight - 6))
    bar:Hide()
    row.bars[c] = bar
  end
  row:SetScript("OnClick", function(self, button)
    if self.data and t.opts.onRowClick then t.opts.onRowClick(self.data, ColumnAt(t, self), button, self) end
  end)
  local function Track(self) Hover(t, self) end
  row:SetScript("OnEnter", function(self)
    self.hoverKey, self.hoverData = false, nil
    Hover(t, self)
    self:SetScript("OnUpdate", Track)   -- only while the row is hovered
  end)
  row:SetScript("OnLeave", function(self)
    self:SetScript("OnUpdate", nil)
    self.hoverKey, self.hoverData = nil, nil
    if t.opts.onRowLeave then t.opts.onRowLeave(self, self.data) end
  end)
  if t.opts.rowButton then
    local button = t.opts.rowButton(row)
    button:Hide()
    button:SetScript("OnClick", function(self)
      local spec = self.column and self.column.button
      if spec and spec.onClick and row.data then spec.onClick(row.data, self) end
    end)
    button:SetScript("OnEnter", function(self)
      row:LockHighlight()
      local spec = self.column and self.column.button
      if spec and spec.onEnter and row.data then spec.onEnter(self, row.data) end
    end)
    button:SetScript("OnLeave", function()
      row:UnlockHighlight()
      if t.opts.onRowLeave then t.opts.onRowLeave(row, row.data) end
    end)
    row.Button = button
  end
  if t.opts.rowAltButton then
    local alt = t.opts.rowAltButton(row)
    alt:Hide()
    alt:HookScript("OnEnter", function(self)
      row:LockHighlight()
      local spec = self.column and self.column.button
      if spec and spec.onAltEnter and row.data then spec.onAltEnter(self, row.data) end
    end)
    alt:HookScript("OnLeave", function()
      row:UnlockHighlight()
      if t.opts.onRowLeave then t.opts.onRowLeave(row, row.data) end
    end)
    row.AltButton = alt
  end
  row:Hide()
  return row
end

-- Create(parent, opts): the table; every row frame is made here
function DataTable.Create(parent, opts)
  local t = setmetatable({ opts = opts, views = {}, active = nil, pool = {}, rowHeight = opts.rowHeight or 20,
    maxCells = opts.maxCells or 8 }, Table)
  local frame = CreateFrame("Frame", opts.name, parent)
  t.frame = frame
  local list = CreateFrame("Frame", nil, frame)
  list:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -HEADER_HEIGHT - 2)
  list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SCROLL_ROOM, 0)
  list:SetClipsChildren(true)
  t.list = list
  local scroll = CreateFrame("ScrollFrame", opts.name and (opts.name .. "Scroll") or nil, frame, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, t.rowHeight, function() t:Paint() end)
  end)
  t.scroll = scroll
  for i = 1, opts.pool or 40 do t.pool[i] = MakeRow(t, list, i) end
  -- measures cell text for auto-fit, in the cells' own font; never shown
  t.measure = frame:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
  t.measure:Hide()
  frame:SetScript("OnSizeChanged", function() t:Layout() t:Refresh() end)
  return t
end

-- AddView(key, columns, viewOpts): a header of its own, hidden until shown
function Table:AddView(key, columns, viewOpts)
  viewOpts = viewOpts or {}
  local view = { key = key, columns = columns, rows = {}, sortKey = viewOpts.sortKey, ascending = viewOpts.ascending ~= false }
  for _, col in ipairs(columns) do
    if col.button then view.buttonColumn = col end
  end
  local header = CreateFrame("Frame", nil, self.frame)
  Mixin(header, CobySuite_Recollect.UI.TableHeaderMixin)
  header:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -SCROLL_ROOM, 0)
  header:SetHeight(HEADER_HEIGHT)
  local t = self
  header:Init({
    columns = columns, persistenceKey = "detail_" .. key, persistence = self.opts.persistence,
    utilities = self.opts.utilities, headerHeight = HEADER_HEIGHT, fitToWidth = true, minStretch = viewOpts.minStretch,
    onSort = function(columnKey, dir)
      view.sortKey, view.ascending = columnKey, dir == SortDir.ASC
      if t.opts.onSort then t.opts.onSort(key, columnKey, view.ascending) end
    end,
    onColumnResize = function() if t.active == key then t:Layout() end end,
    measureColumn = function(colIndex) return t:MeasureColumn(key, colIndex, t.measureLimit) end,
    onUserResize = function(colIndex, how)
      local user = t:UserSized(key)
      local col = colIndex and columns[colIndex]
      if how == "drag" and col then
        user[col.key] = true
      elseif how == "fit" and col then
        user[col.key] = nil
      elseif how == "reset" then
        wipe(user)
        t:FitView(key)
      end
    end,
  })
  -- The rows follow the header's own resize, after its columns are fitted
  -- and placed (hooked after Init's hooks): the table frame's OnSizeChanged
  -- can run while the header still reports its old width, and fitting
  -- calls onColumnResize only when a width changed, so a wider window left
  -- the cells where they were (Cobanyte, 2026-09-26)
  header:HookScript("OnSizeChanged", function() if t.active == key then t:Layout() end end)
  if view.sortKey then header:SetSort(view.sortKey, view.ascending and SortDir.ASC or SortDir.DESC) end
  header:Hide()
  view.header = header
  self.views[key] = view
  return view
end

function Table:GetSort(key)
  local view = self.views[key]
  if not view then return nil end
  return view.sortKey, view.ascending
end

-- ShowView(key): that view's header and rows
function Table:ShowView(key)
  for k, view in pairs(self.views) do view.header:SetShown(k == key) end
  self.active = key
  FauxScrollFrame_SetOffset(self.scroll, 0)
  self.scroll:SetVerticalScroll(0)
  self:Layout()
  self:Refresh()
end

-- Places each row's cells under the active view's columns
function Table:Layout()
  local view = self.views[self.active]
  if not view then return end
  local header = view.header
  if header.FitColumns then pcall(header.FitColumns, header) end
  header:RepositionHeaders()
  local columns, bounds = header:GetColumns(), Bounds(view)
  view.bounds = bounds
  for _, row in ipairs(self.pool) do
    if row.Button and not view.buttonColumn then row.Button:Hide() end
    if row.AltButton and not view.buttonColumn then row.AltButton:Hide() end
    for c = 1, self.maxCells do
      local col, text, b = columns[c], row.cells[c], bounds[c]
      local aside, asideSpec = row.asides[c], col and view.columns[c] and view.columns[c].aside
      text:ClearAllPoints()
      aside:ClearAllPoints()
      aside:SetShown(asideSpec ~= nil)
      if not col then
        text:Hide()
      elseif view.columns[c] and view.columns[c].button then
        text:Hide()
        for _, button in ipairs({ row.Button or false, row.AltButton or false }) do
          if button then
            button:ClearAllPoints()
            button:SetPoint("CENTER", row, "LEFT", b.left + b.width / 2, 0)
          end
        end
      else
        text:Show()
        text:SetJustifyH(col.justify or "LEFT")
        local inset = 4
        if c == 1 then
          row.Icon:ClearAllPoints()
          row.Icon:SetPoint("LEFT", row, "LEFT", b.left + 4, 0)
          inset = ICON + 8
        end
        -- every cell has its column's width, so a long text ends in "..."
        -- inside its own column
        text:SetPoint("LEFT", row, "LEFT", b.left + inset, 0)
        local room = b.width - inset - 4
        if asideSpec then
          local asideW = math.min(asideSpec.width or 0, math.max(room - 10, 0))
          aside:SetPoint("LEFT", row, "LEFT", b.left + b.width - 4 - asideW, 0)
          aside:SetWidth(math.max(asideW, 1))
          room = room - asideW - ASIDE_GAP
        end
        text:SetWidth(math.max(room, 10))
        local bar = row.bars[c]
        bar:ClearAllPoints()
        bar:SetPoint("LEFT", row, "LEFT", b.left + 2, 0)
        row.barRoom[c] = math.max(b.width - 4, 1)
        local fill = row.fills[c]
        fill:ClearAllPoints()
        fill:SetPoint("LEFT", row, "LEFT", b.left + 1, 0)
        fill:SetWidth(math.max(b.width - 2, 1))
      end
    end
  end
end

-- MeasureColumn(key, c): the width column c needs to show its widest cell
-- whole among the view's first MEASURE_ROWS rows, placed as Layout places
-- it (after the icon in the first column), or nil for a button column or no
-- text (the header then fits its title alone)
function Table:MeasureColumn(key, c, limit)
  local view = self.views[key]
  local col = view and view.columns[c]
  if not col or col.button or not col.text then return nil end
  local fs, widest = self.measure, 0
  for i = 1, math.min(#view.rows, limit or MEASURE_ROWS) do
    local ok, text = pcall(col.text, view.rows[i])
    if ok and type(text) == "string" and text ~= "" then
      local okMark, mark = pcall(col.markup or function() return "" end, view.rows[i])
      fs:SetText((okMark and type(mark) == "string" and mark or "") .. text)
      local w = fs:GetUnboundedStringWidth() or 0
      if w > widest then widest = w end
    end
  end
  if widest <= 0 then return nil end
  local inset = c == 1 and (ICON + 8) or 4
  local aside = col.aside and (col.aside.width or 0) + ASIDE_GAP or 0
  return math.ceil(widest + aside + inset + 4 + 2)   -- Layout's inset and right gap, and a pixel each side
end

-- The columns of a view the user sized ({ [colKey] = true }), kept in the
-- persistence's saved variable under path .. "User"; a scratch table when
-- there is none
function Table:UserSized(key)
  local p = self.opts.persistence
  local sv = p and _G[p.savedVariable]
  if type(sv) ~= "table" or type(p.path) ~= "string" then
    self.userScratch = self.userScratch or {}
    self.userScratch[key] = self.userScratch[key] or {}
    return self.userScratch[key]
  end
  local all = sv[p.path .. "User"]
  if type(all) ~= "table" then
    all = {}
    sv[p.path .. "User"] = all
  end
  if type(all[key]) ~= "table" then all[key] = {} end
  return all[key]
end

-- FitView(key): see the header; the rows measured are the view's first
-- FIT_ROWS in their order
function Table:FitView(key)
  local view = self.views[key]
  if not view or not view.header.AutoFitColumns then return end
  self.measureLimit = FIT_ROWS
  local ok, err = pcall(view.header.AutoFitColumns, view.header, self:UserSized(key))
  self.measureLimit = nil
  if not ok then error(err, 0) end
  if self.active == key then self:Layout() end
end

-- SetRows(key, rows): the rows the view shows, in order
function Table:SetRows(key, rows)
  local view = self.views[key]
  if not view then return end
  view.rows = rows or {}
  if self.active == key then self:Refresh() end
end

-- How many rows fit now (never more than the pool)
function Table:Visible()
  local height = self.list:GetHeight() or 0
  return math.max(0, math.min(#self.pool, math.floor(height / self.rowHeight)))
end

function Table:Refresh()
  local view = self.views[self.active]
  if not view then return end
  FauxScrollFrame_Update(self.scroll, #view.rows, self:Visible(), self.rowHeight)
  self:Paint()
end

-- Paints the rows on screen from the scroll offset
function Table:Paint()
  local view = self.views[self.active]
  if not view then return end
  local offset = FauxScrollFrame_GetOffset(self.scroll)
  local visible = self:Visible()
  local columns = view.columns
  for i, frame in ipairs(self.pool) do
    local index = offset + i
    local data = i <= visible and view.rows[index] or nil
    frame.data = data
    if not data then
      frame:Hide()
      if frame.Button then frame.Button:Hide() end
      if frame.AltButton then frame.AltButton:Hide() end
    else
      frame:Show()
      U.AddAlternatingRowBg(frame, index)
      local first = columns[1]
      local icon, isAtlas
      if first and first.icon then icon, isAtlas = first.icon(data) end
      if isAtlas then
        frame.Icon:SetAtlas(icon)
      else
        frame.Icon:SetTexture(icon or 134400)
      end
      frame.Icon:SetShown(icon ~= nil)
      local spec = view.buttonColumn
      local useAlt = frame.AltButton ~= nil and spec ~= nil and spec.button.alt ~= nil and spec.button.alt(data) == true
      if frame.Button then
        frame.Button.column = spec
        local show = spec and not useAlt and (not spec.button.shown or spec.button.shown(data))
        frame.Button:SetShown(show and true or false)
      end
      if frame.AltButton then
        frame.AltButton.column = spec
        frame.AltButton:SetShown(useAlt)
      end
      for c = 1, self.maxCells do
        local col, text = columns[c], frame.cells[c]
        if col and not col.button then
          -- a column's markup (a state icon, UI.Icons) goes before its text, on screen only
          text:SetText((col.markup and col.markup(data) or "") .. (col.text and col.text(data) or ""))
          local color = col.color and col.color(data) or U.Colors.HIGHLIGHT_WHITE
          text:SetTextColor(color[1], color[2], color[3])
          if col.aside then
            frame.asides[c]:SetText(col.aside.text and col.aside.text(data) or "")
            frame.asides[c]:SetTextColor(color[1], color[2], color[3])
          end
        end
        local fill, tint = frame.fills[c], col and col.fill and col.fill(data)
        if type(tint) == "table" then
          fill:SetColorTexture(tint[1], tint[2], tint[3], tint[4] or 0.25)
          fill:Show()
        else
          fill:Hide()
        end
        local bar, share = frame.bars[c], col and col.bar and col.bar(data)
        if type(share) == "number" then
          local tint = col.barColor or { 0.2, 0.6, 0.2, 0.45 }
          bar:SetColorTexture(tint[1], tint[2], tint[3], tint[4] or 0.45)
          bar:SetWidth(math.max(1, (frame.barRoom[c] or 1) * math.min(1, math.max(0, share))))
          bar:Show()
        else
          bar:Hide()
        end
      end
    end
  end
end

DataTable._test = { seams = seams, ColumnAt = ColumnAt, Bounds = Bounds, Hover = Hover, Table = Table }
