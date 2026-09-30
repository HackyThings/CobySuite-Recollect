-------------------------------------------------------------------------------
-- The curator dashboard window, /rec curator (Cobanyte, 2026-09-28): whether
-- curator mode works, what the curator has found, whether the author got it
-- and whether anything needs fixing, in three tabs. Informative: the only
-- actions are the ones curator mode already has (settings, feedback, ask
-- first, review or cancel a collection, the join link, the connection test,
-- turning it off through the existing opt-out dialog).
--   Overview  a status banner (a sentence in the state's color and three
--             numbers), then collapsible sections (the objective tracker's
--             plus and minus) of tiles, lines, a bar and buttons:
--             Curator.Dashboard.Overview
--   Findings  a sortable table of every finding, stamp and note, with a
--             search box and a filter menu (kind, type, state, older
--             database): Dashboard.FindingRows
--   History   every collection the author asked for (Dashboard.HistoryRows),
--             or a short note on what will show there while there is none
-- The window paints what the model says and nothing else. Built at load out
-- of combat (and when combat ends), every frame made then, so showing,
-- scrolling and resizing are safe in combat. Resizable; its place, size,
-- tab, open sections and column widths are kept in
-- RECOLLECT_CURATOR_DB.windows. The title counts what waits to be sent.
-- Escape closes it. Repainted every 2 seconds while shown and whenever a
-- collection moves (Sharing.OnChanged, chained); the Findings rows are
-- rebuilt on a tab switch, and while shown only when the store changed, at
-- most every 10 seconds.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Dashboard = Curator.Dashboard
local U = CobySuite_Recollect.Utilities

local Window = {}
Curator.DashboardWindow = Window

local NAME = "RecollectCuratorDashboard"
local L = { WIDTH = 1000, HEIGHT = 660, PAD = 14, TOP = 64, FOOTER = 40, HEADER = 32, ICON = 22, BODY_X = 12,
  TILE_W = 150, TILE_MAX = 230, TILE_H = 42, TILE_GAP = 6, TILE_ICON = 24, LINE_GAP = 3, SECTION_GAP = 6,
  BANNER_ICON = 28, BAR_H = 14, BUTTON_H = 22, HEADERS = 8, TILES = 24, FONTS = 90, BARS = 3, REFRESH = 2, REBUILD = 10 }
Window.LAYOUT = L

local TABS = { { key = "overview", label = "Overview" }, { key = "findings", label = "Findings" },
  { key = "history", label = "History" } }
Window.TABS = TABS

-- The window's state: frames, pools, the tab, filters, the rows built
local W = { tab = "overview", filters = { kind = {}, group = {}, state = {} }, search = "", sort = { key = "last",
  ascending = false }, historySort = { key = "at", ascending = false } }

-- The saved place of the dashboard: { tab, sections = { [key] = open } }.
-- The first layout's keys (2026-09-28 morning: its open sections and column
-- widths) are dropped, so the redesign starts from its own defaults.
local function Saved()
  local db = Curator.Main.DB()
  if type(db.windows) ~= "table" then db.windows = {} end
  local windows = db.windows
  windows.curatorDashboard_findings, windows.curatorDashboard_history = nil, nil
  if type(windows.dashboard) ~= "table" then windows.dashboard = {} end
  local saved = windows.dashboard
  saved.open = nil
  if type(saved.sections) ~= "table" then saved.sections = {} end
  return saved, windows
end

local function SetColor(region, color)
  if color then region:SetTextColor(color[1], color[2], color[3]) end
end

-- A texture set from a path, a file ID or "atlas:<name>"
local function SetIcon(texture, icon)
  Curator.DashTable.SetIcon(texture, icon)
end

-------------------------------------------------------------------------------
-- Tooltips
-------------------------------------------------------------------------------
local function ShowTip(owner, tip)
  if type(tip) ~= "table" then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(tostring(tip.title or ""), 1, 1, 1)
  local light, gray = U.Colors.LIGHT_GRAY, U.Colors.LABEL_GRAY
  if tip.note then GameTooltip:AddLine(tip.note, gray[1], gray[2], gray[3], true) end
  for _, line in ipairs(tip.lines or {}) do
    GameTooltip:AddDoubleLine(line[1], line[2], light[1], light[2], light[3], 1, 1, 1)
  end
  GameTooltip:Show()
end

-------------------------------------------------------------------------------
-- The Overview's pools
-------------------------------------------------------------------------------
local function MakeTile(parent)
  local tile = CreateFrame("Button", nil, parent)
  tile:SetHeight(L.TILE_H)
  local bg = tile:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  local c = U.Colors.CONTENT_BG
  bg:SetColorTexture(c[1], c[2], c[3], c[4])
  CobySuite_Recollect.UI.AddHoverHighlight(tile)
  tile.Icon = tile:CreateTexture(nil, "ARTWORK")
  tile.Icon:SetSize(L.TILE_ICON, L.TILE_ICON)
  tile.Icon:SetPoint("LEFT", tile, "LEFT", 8, 0)
  tile.Value = tile:CreateFontString(nil, "OVERLAY", U.Fonts.TITLE)
  tile.Value:SetPoint("TOPLEFT", tile.Icon, "TOPRIGHT", 8, 4)
  tile.Value:SetPoint("RIGHT", tile, "RIGHT", -6, 0)
  tile.Value:SetJustifyH("LEFT")
  tile.Value:SetWordWrap(false)
  tile.Label = tile:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
  tile.Label:SetPoint("BOTTOMLEFT", tile.Icon, "BOTTOMRIGHT", 8, -3)
  tile.Label:SetPoint("RIGHT", tile, "RIGHT", -6, 0)
  tile.Label:SetJustifyH("LEFT")
  tile.Label:SetWordWrap(false)
  SetColor(tile.Label, U.Colors.LABEL_GRAY)
  tile:SetScript("OnEnter", function(self) ShowTip(self, self.tip) end)
  tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
  tile:Hide()
  return tile
end

local function MakeBar(parent)
  local bar = { track = parent:CreateTexture(nil, "BORDER"), fill = parent:CreateTexture(nil, "ARTWORK"),
    text = parent:CreateFontString(nil, "OVERLAY", U.Fonts.DATA) }
  local track = U.Colors.BAR_BG
  bar.track:SetColorTexture(track[1], track[2], track[3], track[4] or 0.8)
  bar.track:SetHeight(L.BAR_H)
  bar.fill:SetHeight(L.BAR_H)
  bar.text:SetJustifyH("CENTER")
  bar.track:Hide()
  bar.fill:Hide()
  bar.text:Hide()
  return bar
end

local function MakeHeader(parent)
  local h = CobySuite_Recollect.UI.CreateCollapsibleHeader(parent, { height = L.HEADER, iconSize = L.ICON, pad = 8,
    titleFont = U.Fonts.HEADING, titleY = 2, summaryGap = 1 })
  h:SetScript("OnClick", function(self)
    local saved = Saved()
    local open = not self.open
    saved.sections[self.key] = open
    PlaySound(open and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    Window.PaintOverview()
  end)
  h:Hide()
  return h
end

-- The banner's own regions: a tinted background with an accent stripe in
-- the state's color, and its icon
local function MakeBanner(parent)
  local banner = { bg = parent:CreateTexture(nil, "BACKGROUND"), stripe = parent:CreateTexture(nil, "BORDER"),
    icon = parent:CreateTexture(nil, "ARTWORK") }
  banner.stripe:SetWidth(3)
  banner.icon:SetSize(L.BANNER_ICON, L.BANNER_ICON)
  banner.bg:Hide()
  banner.stripe:Hide()
  banner.icon:Hide()
  return banner
end

-- The buttons a section may show, made once
local function SectionButtons(parent)
  local P = Curator.Provider
  local defs = {
    { key = "join", text = "Join the community", width = 150, tip = "Prints the community's invite link in chat; click it there",
      onClick = function() P.PrintJoinLink() end },
    { key = "test", text = "Test the connection", width = 150,
      tip = "Runs the connection test with the author's character (about five minutes); the report goes to chat. It works only while the author has a test session open, so ask in the community first",
      onClick = function() Window.RunTest() end },
    { key = "review", text = "Review the request", width = 150, tip = "Allow or decline the author's request",
      onClick = function() if Curator.TransferWindow then Curator.TransferWindow.Open() end end },
    { key = "cancel", text = "Cancel the collection", width = 160, tip = "Stops sending; nothing is deleted",
      onClick = function() Curator.Sharing.Cancel() end },
    { key = "history", text = "Show the history", width = 140, tip = "Every collection the author asked for",
      onClick = function() Window.SetTab("history") end },
    { key = "findings", text = "Show the findings", width = 140, tip = "Every finding, confirmation and note, in a table",
      onClick = function() Window.SetTab("findings") end },
    { key = "settings", text = "Curator settings", width = 140, tip = "The Curator page of Recollect's settings",
      onClick = function() Window.OpenSettings() end },
  }
  local out = {}
  for _, def in ipairs(defs) do
    local b = CobySuite_Recollect.UI.CreateButton(parent, { text = def.text, size = { def.width, L.BUTTON_H }, tooltip = def.tip,
      onClick = function()
        def.onClick()
        Window.Refresh(true)
      end })
    b:Hide()
    out[def.key] = b
  end
  return out
end

local function BuildOverview(page)
  local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
  scroll.scrollBarHideable = true
  if scroll.ScrollBar then scroll.ScrollBar:Hide() end
  scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 0)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(1, 1)
  scroll:SetScrollChild(child)
  W.scroll, W.child = scroll, child
  W.banner = MakeBanner(child)
  W.headers, W.tiles, W.fonts, W.bars = {}, {}, {}, {}
  for i = 1, L.HEADERS do W.headers[i] = MakeHeader(child) end
  for i = 1, L.TILES do W.tiles[i] = MakeTile(child) end
  for i = 1, L.FONTS do
    local fs = child:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:Hide()
    W.fonts[i] = fs
  end
  for i = 1, L.BARS do W.bars[i] = MakeBar(child) end
  W.buttons = SectionButtons(child)
  scroll:HookScript("OnSizeChanged", function() Window.PaintOverview() end)
end

-------------------------------------------------------------------------------
-- Painting the Overview
-------------------------------------------------------------------------------
local P = { fonts = 0, tiles = 0, bars = 0 }

local function Font(text, font, color, x, y, width)
  if P.fonts >= #W.fonts then return 0 end
  P.fonts = P.fonts + 1
  local fs = W.fonts[P.fonts]
  fs:SetFontObject(font)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", W.child, "TOPLEFT", x, y)
  fs:SetWidth(math.max(width, 40))
  fs:SetText(text)
  SetColor(fs, color or U.Colors.LIGHT_GRAY)
  fs:Show()
  return fs:GetStringHeight() or 12
end

-- Tiles in rows; fill: one row of them shares the whole width (the banner's
-- numbers), else each is at most TILE_MAX wide
local function PaintTiles(tiles, x, y, width, fill)
  local fit = math.max(1, math.floor((width + L.TILE_GAP) / (L.TILE_W + L.TILE_GAP)))
  local perRow = math.max(1, math.min(#tiles, fit))
  local tileW = (width - (perRow - 1) * L.TILE_GAP) / perRow
  if not fill then tileW = math.min(L.TILE_MAX, tileW) end
  local gray = U.Colors.LABEL_GRAY
  for i, def in ipairs(tiles) do
    if P.tiles >= #W.tiles then break end
    P.tiles = P.tiles + 1
    local tile = W.tiles[P.tiles]
    local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
    tile:ClearAllPoints()
    tile:SetPoint("TOPLEFT", W.child, "TOPLEFT", x + col * (tileW + L.TILE_GAP), y - row * (L.TILE_H + L.TILE_GAP))
    tile:SetWidth(tileW)
    SetIcon(tile.Icon, def.icon)
    tile.Icon:SetDesaturated(def.dim == true)
    tile.Icon:SetAlpha(def.dim and 0.5 or 1)
    tile.Value:SetText(def.value)
    SetColor(tile.Value, def.dim and gray or def.color or U.Colors.HIGHLIGHT_WHITE)
    tile.Label:SetText(def.label or "")
    tile.tip = def.tip
    tile:Show()
  end
  local rows = math.ceil(#tiles / perRow)
  return rows * L.TILE_H + (rows - 1) * L.TILE_GAP
end

local function PaintBar(def, x, y, width)
  if P.bars >= #W.bars then return 0 end
  P.bars = P.bars + 1
  local bar = W.bars[P.bars]
  local w = math.min(width, 420)
  bar.track:ClearAllPoints()
  bar.track:SetPoint("TOPLEFT", W.child, "TOPLEFT", x, y)
  bar.track:SetWidth(w)
  bar.track:Show()
  local share = math.max(0, math.min(1, tonumber(def.share) or 0))
  local color = def.color or U.Colors.INFO_BLUE
  bar.fill:SetColorTexture(color[1], color[2], color[3], 0.8)
  bar.fill:ClearAllPoints()
  bar.fill:SetPoint("TOPLEFT", bar.track, "TOPLEFT", 0, 0)
  bar.fill:SetWidth(math.max(1, w * share))
  bar.fill:SetShown(share > 0)
  bar.text:ClearAllPoints()
  bar.text:SetPoint("CENTER", bar.track, "CENTER", 0, 0)
  bar.text:SetText(def.text or "")
  bar.text:Show()
  return L.BAR_H
end

local function PaintButtons(section, x, y, used)
  local left = x
  local disabled = section.disabled or {}
  for _, key in ipairs(section.buttons) do
    local b = W.buttons[key]
    if b and not used[key] then
      used[key] = true
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", W.child, "TOPLEFT", left, y)
      b:SetEnabled(disabled[key] == nil)
      b:Show()
      left = left + b:GetWidth() + 6
    end
  end
  return L.BUTTON_H
end

local BULLET = "\226\128\162 "

local function PaintLines(lines, x, y, inner)
  for _, line in ipairs(lines or {}) do
    local text = line.bullet and (BULLET .. line.text) or line.text
    local h = Font(text, line.small and U.Fonts.DATA or U.Fonts.SMALL, line.color, x + (line.bullet and 8 or 0), y,
      inner - (line.bullet and 8 or 0))
    y = y - h - L.LINE_GAP
  end
  return y
end

-- One section's body under its header; returns the new y
local function PaintBody(section, y, width, used)
  local x = L.BODY_X
  local inner = width - x - 8
  if section.tiles and #section.tiles > 0 then
    y = y - 6
    y = y - PaintTiles(section.tiles, x, y, inner, section.fill) - 6
  end
  if section.bar then y = y - PaintBar(section.bar, x, y, inner) - 6 end
  y = PaintLines(section.lines, x, y, inner)
  if section.buttons and #section.buttons > 0 then
    y = y - 4
    y = y - PaintButtons(section, x, y, used) - 4
  end
  return y
end

-- The status banner: its icon and sentence, then its lines, numbers, bar
-- and buttons, over a background tinted in the state's color
local function PaintBanner(section, y, width, used)
  local top, banner = y, W.banner
  local color = section.color or U.Colors.LIGHT_GRAY
  local x = L.BODY_X
  SetIcon(banner.icon, section.icon)
  banner.icon:ClearAllPoints()
  banner.icon:SetPoint("TOPLEFT", W.child, "TOPLEFT", x, y - 8)
  banner.icon:Show()
  local textX = x + L.BANNER_ICON + 10
  local h = Font(section.text or "", U.Fonts.HEADING, color, textX, y - 13, width - textX - 8)
  y = y - 8 - math.max(L.BANNER_ICON, h + 5) - 4
  y = PaintLines(section.lines, textX, y, width - textX - 8)
  local body = { tiles = section.tiles, fill = section.fill, bar = section.bar, buttons = section.buttons,
    disabled = section.disabled }
  y = PaintBody(body, y, width, used) - 6
  banner.bg:ClearAllPoints()
  banner.bg:SetPoint("TOPLEFT", W.child, "TOPLEFT", 0, top)
  banner.bg:SetSize(width, top - y)
  banner.bg:SetColorTexture(color[1], color[2], color[3], 0.08)
  banner.bg:Show()
  banner.stripe:ClearAllPoints()
  banner.stripe:SetPoint("TOPLEFT", W.child, "TOPLEFT", 0, top)
  banner.stripe:SetHeight(top - y)
  banner.stripe:SetColorTexture(color[1], color[2], color[3], 0.9)
  banner.stripe:Show()
  return y
end

local function HideAll()
  for _, h in ipairs(W.headers) do h:Hide() end
  for _, t in ipairs(W.tiles) do t:Hide() end
  for _, f in ipairs(W.fonts) do f:Hide() end
  for _, b in ipairs(W.bars) do b.track:Hide() b.fill:Hide() b.text:Hide() end
  for _, b in pairs(W.buttons) do b:Hide() end
  W.banner.bg:Hide()
  W.banner.stripe:Hide()
  W.banner.icon:Hide()
  P.fonts, P.tiles, P.bars = 0, 0, 0
end

-- IsOpen(section): the player's choice, else open unless the section starts shut
function Window.IsOpen(section)
  local saved = Saved().sections[section.key]
  if saved ~= nil then return saved == true end
  return not section.closed
end

function Window.PaintOverview()
  if not W.window or not W.window:IsShown() or W.tab ~= "overview" then return end
  HideAll()
  local width = W.scroll:GetWidth()
  if not width or width <= 0 then width = L.WIDTH - 2 * L.PAD - 24 end
  W.child:SetWidth(width)
  local y, used, n = -2, {}, 0
  for _, section in ipairs(Dashboard.Overview()) do
    if section.banner then
      y = PaintBanner(section, y, width, used) - L.SECTION_GAP - 4
    else
      n = n + 1
      local h = W.headers[n]
      if not h then break end
      local open = Window.IsOpen(section)
      h.key, h.open = section.key, open
      SetIcon(h.Icon, section.icon)
      h.Title:SetText(section.title or "")
      h.Summary:SetText(section.summary or "")
      h:SetOpen(open)
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", W.child, "TOPLEFT", 0, y)
      h:SetWidth(width)
      h:Show()
      y = y - L.HEADER - 2
      if open then y = PaintBody(section, y, width, used) end
      y = y - L.SECTION_GAP
    end
  end
  W.child:SetHeight(math.max(1, -y + 8))
end

-------------------------------------------------------------------------------
-- The Findings tab
-------------------------------------------------------------------------------
-- The store's fingerprint: rows are built again only when it changes
local function Fingerprint()
  local db = Curator.Store.DB()
  local status = Curator.Sharing.Status()
  local notes = Curator.Notes.DB()
  local n = 0
  for _ in pairs(db.awaiting) do n = n + 1 end
  return table.concat({ tostring(db.records), tostring(db.nextRev), tostring(db.nextID), tostring(#db.frozen), n,
    tostring(notes.nextN), tostring(status and status.request), tostring(db.bytes) }, "|")
end

-- The filter menu's entries: { header } titles, then keys "<set>:<key>"
local function FilterDefs()
  local defs = { { header = "Kind" } }
  for _, kind in ipairs(Dashboard.KINDS) do
    defs[#defs + 1] = { key = "kind:" .. kind.key, label = kind.label, tooltip = kind.tooltip }
  end
  defs[#defs + 1] = { header = "Type" }
  for _, group in ipairs(Curator.Decode.GROUPS) do defs[#defs + 1] = { key = "group:" .. group.key, label = group.label } end
  defs[#defs + 1] = { key = "group:note", label = "Your notes" }
  defs[#defs + 1] = { header = "State" }
  for _, state in ipairs(Dashboard.STATES) do
    defs[#defs + 1] = { key = "state:" .. state.key, label = state.label, tooltip = state.tooltip }
  end
  defs[#defs + 1] = { header = "Database" }
  defs[#defs + 1] = { key = "older", label = "From an older database", tooltip = "Findings kept from before the database changed" }
  return defs
end

local function FilterChecked(key)
  if key == "older" then return W.filters.older == true end
  local set, value = key:match("^(%a+):(.+)$")
  return set ~= nil and W.filters[set] ~= nil and W.filters[set][value] == true
end

local function SetFilter(key, on)
  if key == "older" then
    W.filters.older = on or nil
  else
    local set, value = key:match("^(%a+):(.+)$")
    if set and W.filters[set] then W.filters[set][value] = on or nil end
  end
  Window.PaintFindings(false)
end

-- FindingsNote(shown, all): the line over an empty table, or nil
function Window.FindingsNote(shown, all)
  if shown > 0 then return nil end
  if all == 0 then return "Nothing recorded yet. What curator mode records while you play shows here." end
  return "Nothing matches the search or the filter."
end

function Window.PaintFindings(rebuild)
  if not W.window or not W.window:IsShown() or W.tab ~= "findings" then return end
  -- the rows are built again on a tab switch, and at most every
  -- L.REBUILD seconds while recording changes the store under them (a
  -- store near its cap holds thousands)
  local stamp = Fingerprint()
  local due = not W.builtAt or GetTime() - W.builtAt >= L.REBUILD
  if rebuild or not W.allRows or (W.rowsFor ~= stamp and due) then
    W.allRows, W.rowsFor, W.builtAt = Dashboard.FindingRows(), stamp, GetTime()
  end
  local rows = Dashboard.Filter(W.allRows, W.filters, W.search)
  Dashboard.Sort(rows, W.sort.key, W.sort.ascending, Dashboard.FINDING_COLUMNS)
  W.findings:SetRows(rows)
  local waiting = Dashboard.Waiting()
  W.findingsSummary:SetText(("%d of %d shown; %d waiting to be sent. Hover a row for all of it."):format(#rows,
    #W.allRows, waiting.total))
  local note = Window.FindingsNote(#rows, #W.allRows)
  W.findingsEmpty:SetText(note or "")
  W.findingsEmpty:SetShown(note ~= nil)
  if W.filterButton then W.filterButton:Refresh() end
end

local function BuildFindings(page)
  W.searchBox = CobySuite_Recollect.UI.CreateSearchBox(page, { name = NAME .. "Search", width = 220,
    point = { "TOPLEFT", page, "TOPLEFT", 6, 0 }, placeholder = "Search names, types or IDs",
    onSearch = function(text) W.search = text or "" Window.PaintFindings(false) end })
  W.filterButton = CobySuite_Recollect.UI.CreateFilterButton(page, { name = NAME .. "Filter",
    point = { "LEFT", W.searchBox, "RIGHT", 8, 0 }, defs = FilterDefs(), isChecked = FilterChecked, setChecked = SetFilter,
    onClear = function()
      W.filters = { kind = {}, group = {}, state = {} }
      Window.PaintFindings(false)
    end,
    tooltipTitle = "Filter", tooltipIdle = "Show only some kinds, types or states.",
    menu = { name = NAME .. "FilterMenu", parent = page, strata = "DIALOG" } })
  W.findingsSummary = page:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
  W.findingsSummary:SetPoint("LEFT", W.filterButton, "RIGHT", 10, 0)
  W.findingsSummary:SetPoint("RIGHT", page, "RIGHT", -4, 0)
  W.findingsSummary:SetJustifyH("LEFT")
  W.findingsSummary:SetWordWrap(false)
  SetColor(W.findingsSummary, U.Colors.LABEL_GRAY)
  W.findings = Curator.DashTable.Create(page, { key = "findings", pool = 30, rowHeight = 20,
    minStretch = Dashboard.FINDINGS_MIN_STRETCH,
    columns = Dashboard.FINDING_COLUMNS, sortKey = W.sort.key, ascending = W.sort.ascending,
    onSort = function(key, ascending)
      W.sort = { key = key, ascending = ascending }
      Window.PaintFindings(false)
    end,
    onRowEnter = function(frame, row) ShowTip(frame, Dashboard.FindingTooltip(row)) end })
  W.findings.frame:SetPoint("TOPLEFT", W.searchBox, "BOTTOMLEFT", -6, -8)
  W.findings.frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
  W.findingsEmpty = page:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  W.findingsEmpty:SetPoint("TOP", W.findings.frame, "TOP", 0, -60)
  W.findingsEmpty:SetWidth(460)
  W.findingsEmpty:SetJustifyH("CENTER")
  SetColor(W.findingsEmpty, U.Colors.LABEL_GRAY)
  W.findingsEmpty:Hide()
end

-------------------------------------------------------------------------------
-- The History tab
-------------------------------------------------------------------------------
function Window.PaintHistory()
  if not W.window or not W.window:IsShown() or W.tab ~= "history" then return end
  local empty = Dashboard.HistoryEmpty()
  local hidden = not W.history.frame:IsShown()
  W.history.frame:SetShown(empty == nil)
  -- the first collection of a session shows a table that was never laid out
  if empty == nil and hidden then W.history:Layout() end
  W.historyIntro:SetShown(empty == nil)
  for _, region in ipairs(W.historyEmpty) do region:SetShown(empty ~= nil) end
  if empty then
    W.historyEmptyTitle:SetText(empty.title)
    W.historyEmptyText:SetText(table.concat(empty.lines, "\n\n"))
    return
  end
  W.historyIntro:SetText(Dashboard.HistoryIntro())
  local rows = Dashboard.HistoryRows()
  if W.historySort.key == "at" and not W.historySort.ascending then
    -- newest first, as kept
  else
    Dashboard.Sort(rows, W.historySort.key, W.historySort.ascending, Dashboard.HISTORY_COLUMNS, "at")
  end
  W.history:SetRows(rows)
end

local function BuildHistory(page)
  W.historyIntro = page:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  W.historyIntro:SetPoint("TOPLEFT", page, "TOPLEFT", 4, 0)
  W.historyIntro:SetPoint("RIGHT", page, "RIGHT", -4, 0)
  W.historyIntro:SetJustifyH("LEFT")
  W.historyIntro:SetWordWrap(true)
  SetColor(W.historyIntro, U.Colors.LIGHT_GRAY)
  W.history = Curator.DashTable.Create(page, { key = "history", pool = 30, rowHeight = 20, minStretch = 200,
    columns = Dashboard.HISTORY_COLUMNS, sortKey = W.historySort.key, ascending = W.historySort.ascending,
    onSort = function(key, ascending)
      W.historySort = { key = key, ascending = ascending }
      Window.PaintHistory()
    end,
    onRowEnter = function(frame, row) ShowTip(frame, Dashboard.HistoryTooltip(row)) end })
  W.history.frame:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -24)
  W.history.frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
  -- With no collection yet: an icon, a title and a few lines, centered
  local icon = page:CreateTexture(nil, "ARTWORK")
  icon:SetSize(48, 48)
  icon:SetPoint("TOP", page, "TOP", 0, -90)
  SetIcon(icon, Dashboard.ICONS.collections)
  local title = page:CreateFontString(nil, "OVERLAY", U.Fonts.HEADING)
  title:SetPoint("TOP", icon, "BOTTOM", 0, -12)
  local text = page:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  text:SetPoint("TOP", title, "BOTTOM", 0, -10)
  text:SetWidth(440)
  text:SetJustifyH("CENTER")
  text:SetWordWrap(true)
  SetColor(text, U.Colors.LABEL_GRAY)
  W.historyEmptyTitle, W.historyEmptyText = title, text
  W.historyEmpty = { icon, title, text }
  for _, region in ipairs(W.historyEmpty) do region:Hide() end
end

-------------------------------------------------------------------------------
-- Actions
-------------------------------------------------------------------------------
function Window.OpenSettings()
  if not Host.OpenSettings("curator") then Host.Print("Type /rec settings, then choose Curator.") end
end

-- The connection test against the author's character, when known
function Window.RunTest()
  local author = Dashboard.AuthorName()
  if not (author and Curator.Ping) then
    Host.Print("The connection test needs the author's character; it's known once the author's client has been in touch this session.")
    return false
  end
  return Curator.Ping.Start(author)
end

-- Turning curator mode off goes through the existing opt-out dialog
-- (Config's change hook opens it: delete or keep, how to leave)
function Window.TurnOff()
  Curator.Config.Set("curator_enabled", false)
end

local function BuildFooter(window)
  local size = { 130, L.BUTTON_H }
  W.settingsButton = CobySuite_Recollect.UI.CreateButton(window, { text = "Settings", size = size,
    point = { "BOTTOMLEFT", window, "BOTTOMLEFT", L.PAD, 12 }, tooltip = "The Curator page of Recollect's settings",
    onClick = function() Window.OpenSettings() end })
  W.feedbackButton = CobySuite_Recollect.UI.CreateButton(window, { text = "Send feedback", size = size,
    point = { "LEFT", W.settingsButton, "RIGHT", 6, 0 },
    tooltip = "Write to Recollect's author (/rec feedback); it goes with your next collection",
    onClick = function() Curator.Provider.OpenFeedback() end })
  W.askBox = CobySuite_Recollect.UI.CreateCheckbox(window, { size = 22, label = "Ask me before each collection",
    point = { "LEFT", W.feedbackButton, "RIGHT", 10, 0 },
    tooltip = "Recollect asks before the author collects your findings, instead of sending in the background",
    onChange = function(checked)
      Curator.Config.Set("curator_ask", checked == true)
      Window.Refresh(false)
    end })
  W.modeButton = CobySuite_Recollect.UI.CreateButton(window, { text = "Turn curator mode off", size = { 170, L.BUTTON_H },
    point = { "BOTTOMRIGHT", window, "BOTTOMRIGHT", -L.PAD - 16, 12 },
    tooltip = "Stops recording; a window then asks whether to delete your findings",
    onClick = function()
      if Curator.Main.IsEnabled() then Window.TurnOff() else Window.OpenSettings() end
      Window.Refresh(false)
    end })
end

local function PaintFooter()
  local enabled = Curator.Main.IsEnabled()
  W.askBox:SetShown(enabled)
  W.askBox:SetChecked(Curator.Config.Get("curator_ask") == true)
  W.feedbackButton:SetEnabled(enabled)
  W.modeButton:SetText(enabled and "Turn curator mode off" or "Turn it on in settings")
end

-------------------------------------------------------------------------------
-- Tabs and the window
-------------------------------------------------------------------------------
-- The title, counting what waits to be sent
function Window.Title()
  local waiting = Dashboard.Waiting().total
  if waiting > 0 then return ("Recollect: Curator (%d waiting)"):format(waiting) end
  return "Recollect: Curator"
end

local function TabLabel(key)
  if key == "findings" then
    local waiting = Dashboard.Waiting()
    return waiting.total > 0 and ("Findings (%d)"):format(waiting.total) or "Findings"
  elseif key == "history" then
    local n = #Curator.History.Entries()
    return n > 0 and ("History (%d)"):format(n) or "History"
  end
  return "Overview"
end

-- Each part repaints on its own, so one that fails leaves the others
-- painted; the error goes to the debug log
local function Try(what, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then Host.Log("Curator dashboard: painting %s failed: %s", what, tostring(err)) end
end

function Window.Refresh(rebuild)
  if not W.window or not W.window:IsShown() then return end
  if W.window.TitleText then W.window.TitleText:SetText(Window.Title()) end
  for i, def in ipairs(TABS) do
    W.tabs[i]:SetText(TabLabel(def.key))
    PanelTemplates_TabResize(W.tabs[i], 0)
  end
  Try("the footer", PaintFooter)
  Try("the Overview", Window.PaintOverview)
  Try("the Findings", Window.PaintFindings, rebuild)
  Try("the History", Window.PaintHistory)
end

function Window.SetTab(key)
  if not W.window then return end
  local found = false
  for i, def in ipairs(TABS) do
    local on = def.key == key
    W.pages[def.key]:SetShown(on)
    if on then
      PanelTemplates_SetTab(W.window, i)
      found = true
    end
  end
  if not found then return Window.SetTab("overview") end
  W.tab = key
  Saved().tab = key
  Window.Refresh(key == "findings")
end

local function BuildTabs(window)
  W.tabs, W.pages = {}, {}
  local previous
  for i, def in ipairs(TABS) do
    local tab = CreateFrame("Button", NAME .. "Tab" .. i, window, "PanelTopTabButtonTemplate")
    tab:SetText(def.label)
    tab:SetID(i)
    tab:SetScript("OnClick", function() Window.SetTab(def.key) end)
    PanelTemplates_TabResize(tab, 0)
    if previous then
      tab:SetPoint("LEFT", previous, "RIGHT", 4, 0)
    else
      tab:SetPoint("TOPLEFT", window, "TOPLEFT", L.PAD, -28)
    end
    W.tabs[i] = tab
    previous = tab
    local page = CreateFrame("Frame", nil, window)
    page:SetPoint("TOPLEFT", window, "TOPLEFT", L.PAD, -L.TOP)
    page:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -L.PAD, L.FOOTER + 6)
    page:Hide()
    W.pages[def.key] = page
  end
  window.numTabs = #W.tabs
end

local function Build()
  if W.window or InCombatLockdown() or not CobySuite_Recollect.UI.CreateWindow then return end
  local saved = Saved()
  local window = CobySuite_Recollect.UI.CreateWindow({
    name = NAME, title = "Recollect: Curator", icon = Host.Icon(), width = L.WIDTH, height = L.HEIGHT,
    escapeCloses = true, resizable = { minWidth = 760, minHeight = 460, maxWidth = 1800, maxHeight = 1200 },
    persist = { svTable = function() return select(2, Saved()) end, key = NAME,
      defaults = { point = "CENTER", relPoint = "CENTER", x = 0, y = 40 } },
  })
  W.window = window
  BuildTabs(window)
  BuildOverview(W.pages.overview)
  BuildFindings(W.pages.findings)
  BuildHistory(W.pages.history)
  BuildFooter(window)
  W.tab = saved.tab or "overview"
  local ticker
  window:HookScript("OnShow", function()
    Window.SetTab(W.tab)
    if not ticker then ticker = C_Timer.NewTicker(L.REFRESH, function() Window.Refresh(false) end) end
  end)
  window:HookScript("OnHide", function()
    if ticker then ticker:Cancel() end
    ticker = nil
  end)
  window:Hide()
end

-- Toggle(): shows or hides the dashboard; false when it can't open (in
-- combat before it was built)
function Window.Toggle()
  Build()
  if not W.window then return false end
  if W.window:IsShown() then
    W.window:Hide()
  else
    W.window:RestoreState()
    W.window:Show()
  end
  return true
end

function Window.Open(tab)
  Build()
  if not W.window then return false end
  if not W.window:IsShown() then
    W.window:RestoreState()
    W.window:Show()
  end
  if tab then Window.SetTab(tab) end
  return true
end

function Window.Close()
  if W.window then W.window:Hide() end
end

-- A collection moved: repaint (chained after the transfer window's)
Curator.Sharing.OnChanged = (function(previous)
  return function()
    if previous then previous() end
    Window.Refresh(false)
  end
end)(Curator.Sharing.OnChanged)

Host.OnLoaded(function() C_Timer.After(0, Build) end)
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", Build)
