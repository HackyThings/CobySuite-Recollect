-------------------------------------------------------------------------------
-- UI.ListWindow: one sortable table of every stack this character can
-- account for (Verdicts.Rows), with its purpose, verdict, what it is used for
-- and why; other characters' stored items too when the settings say so
--
-- Built at login (no CreateFrame in combat), refreshed when shown and on
-- InventoryChanged while shown. The scroll box makes its row frames when
-- rows first fill it, on the first show, so a first open asked for in combat
-- waits for combat to end. A search box matches the item, where it is,
-- its purpose, what it is used for and its reason; the funnel narrows by
-- verdict, by place and to items with a known use. Hovering a row shows the
-- item's tooltip, and the audit panel beside it (the configured key) shows
-- that row's own verdict (UI.Tooltip.SetRowContext); clicking a row pins its
-- full details (UI.DetailWindow, G-05). The funnel also narrows by why an
-- item reads Can't tell (G-04) and to items another character's recipe
-- scan recorded a use for (F-02). The columns fit the window, and Reason
-- keeps at least ListColumns.REASON_MIN (BA-15).
-------------------------------------------------------------------------------
local UI = Recollect.UI
local Columns = UI.ListColumns
local U = CobySuite_Recollect.Utilities
local SortDir = CobySuite_Recollect.SortDir
local V = Recollect.Purposes.Registry.Verdict

local ROW_HEIGHT = 20
local HEADER_HEIGHT = 20
local PAD = 12
local SCROLLBAR_WIDTH = 10
local FOOTER_TEXT = "Outdated: the facts say it has been replaced. Lower level: gear below what you wear, not "
  .. "shown to be from an earlier season. Junk: the game's label for gray items with a vendor price. Purpose done: "
  .. "every use Recollect checks is finished. Can't tell: not confirmed yet. Not checked yet: reputation tokens, and "
  .. "secrets not in Recollect's list."

local window, header, scrollBox, funnel
local rows, allRows = {}, {}
local sortKey, sortAscending = "verdictRank", true
local searchText = ""
local filters = {}   -- [key] = true, for this session
local rowsMade = false         -- a row frame exists (the first ones are made out of combat)
local openAfterCombat = false  -- a first open asked for in combat is waiting

local FILTER_DEFS = {
  { key = "v:" .. V.NEEDED, label = "Needed" },
  { key = "v:" .. V.USE, label = "Use now" },
  { key = "v:" .. V.USEFUL, label = "Useful" },
  { key = "v:" .. V.UNKNOWN, label = "Can't tell" },
  { key = "v:" .. V.OUTDATED, label = "Outdated" },
  { key = "v:" .. V.LOWER, label = "Lower level" },
  { key = "v:" .. V.JUNK, label = "Junk" },
  { key = "v:" .. V.DONE, label = "Purpose done" },
  { key = "l:bags", label = "In your bags" },
  { key = "l:bank", label = "In your bank" },
  { key = "l:warband", label = "In the warband bank" },
  { key = "l:others", label = "On other characters", tooltip = "Turn on \"Include your other characters\" in the settings to list them." },
  { key = "hasUse", label = "Has a known use", tooltip = "Only items the game's data links to a quest, an achievement, a recipe, a currency or another item." },
  { key = "altUse", label = "Recorded alt use", tooltip = "Items another character's recipe scan recorded a use for. That is history: the character may have changed since." },
}
-- Why an item reads Can't tell (Registry.CATEGORY), one filter each, every
-- category included (review F6: a row of a category with no filter vanished
-- under every Can't tell filter)
for _, key in ipairs({ "loading", "bank", "profession", "unsupported", "disagree", "unreadable", "character", "finished" }) do
  local category = Recollect.Purposes.Registry.CATEGORY[key]
  FILTER_DEFS[#FILTER_DEFS + 1] = { key = "k:" .. key, label = "Can't tell: " .. category.label:lower(),
    tooltip = category.recovery }
end

UI.ListFilterDefs = FILTER_DEFS   -- read by the suites

-- Does a row pass the search text and the filters? (a group with nothing
-- checked lets everything through)
function UI.ListRowMatches(row, text, active)
  local anyVerdict, anyPlace, anyCategory = false, false, false
  for key in pairs(active) do
    if key:sub(1, 2) == "v:" then anyVerdict = true end
    if key:sub(1, 2) == "l:" then anyPlace = true end
    if key:sub(1, 2) == "k:" then anyCategory = true end
  end
  if anyVerdict and not active["v:" .. tostring(row.verdict)] then return false end
  if anyPlace and not active["l:" .. (row.character and "others" or tostring(row.kind))] then return false end
  if anyCategory and not active["k:" .. tostring(row.category)] then return false end
  if active.hasUse and (row.usedForText or "") == "" then return false end
  if active.altUse and not row.altUse then return false end
  if text ~= "" then
    local hay = table.concat({ row.name or "", row.where or "", row.purposeText or "", row.usedForText or "", row.reason or "" }, "\n"):lower()
    if not hay:find(text, 1, true) then return false end
  end
  return true
end

local listener = {}

local function SortRows()
  local key, asc = sortKey, sortAscending
  table.sort(rows, function(a, b)
    local va, vb = a[key], b[key]
    if va == vb then
      if a.verdictRank ~= b.verdictRank then return a.verdictRank < b.verdictRank end
      return (a.name or "") < (b.name or "")
    end
    if va == nil then return false end
    if vb == nil then return true end
    if type(va) == "string" and type(vb) == "string" then va, vb = va:lower(), vb:lower() end
    if type(va) ~= type(vb) then va, vb = tostring(va), tostring(vb) end
    if asc then return va < vb end
    return va > vb
  end)
end

local function Summary()
  local counts = { [V.NEEDED] = 0, [V.USE] = 0, [V.USEFUL] = 0, [V.UNKNOWN] = 0, [V.OUTDATED] = 0, [V.LOWER] = 0,
    [V.JUNK] = 0, [V.DONE] = 0 }
  for _, row in ipairs(rows) do counts[row.verdict] = (counts[row.verdict] or 0) + 1 end
  local shown = #rows == #allRows and ("%d stacks"):format(#rows) or ("%d of %d stacks"):format(#rows, #allRows)
  return ("%s: %d needed, %d use now, %d useful, %d unknown, %d outdated, %d lower level, %d junk, %d purpose done"):format(
    shown, counts[V.NEEDED], counts[V.USE], counts[V.USEFUL], counts[V.UNKNOWN], counts[V.OUTDATED], counts[V.LOWER],
    counts[V.JUNK], counts[V.DONE])
end

function UI.RefreshList()
  if not window or not window:IsShown() then return end
  local ok, built = pcall(Recollect.Verdicts.Rows.Build)
  if not ok then
    Recollect.Debug.Warn("UI", "List build failed: %s", tostring(built))
    built = {}
  end
  allRows = built
  rows = {}
  for _, row in ipairs(allRows) do
    if UI.ListRowMatches(row, searchText, filters) then rows[#rows + 1] = row end
  end
  SortRows()
  local provider = CreateDataProvider()
  for i, row in ipairs(rows) do
    row._index = i
    provider:Insert(row)
  end
  scrollBox:SetDataProvider(provider, ScrollBoxConstants.RetainScrollPosition)
  window.Summary:SetText(Summary())
end

local refreshFold = U.Coalesce(0.3, function() UI.RefreshList() end)

function listener:ReceiveEvent()
  if window and window:IsShown() then refreshFold:Call() end
end

local function BuildHeader()
  header = CreateFrame("Frame", nil, window)
  Mixin(header, CobySuite_Recollect.UI.TableHeaderMixin)
  header:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -56)
  header:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD - SCROLLBAR_WIDTH - 4, -56)
  header:SetHeight(HEADER_HEIGHT)
  header:Init({
    columns = Columns.DEFS,
    persistenceKey = "list",
    persistence = { savedVariable = "RECOLLECT_WINDOW_STATE", path = "listColumns" },
    utilities = U,
    headerHeight = HEADER_HEIGHT,
    fitToWidth = true,
    minStretch = Columns.REASON_MIN,
    -- A divider's double-click fits its column to the rows listed now, not
    -- to its title alone
    measureColumn = function(_, key) return Columns.Measure(rows, key, window.MeasureText) end,
    onSort = function(key, dir)
      sortKey, sortAscending = key, dir == SortDir.ASC
      SortRows()
      UI.RefreshList()
    end,
    onColumnResize = function()
      if not scrollBox then return end
      scrollBox:ForEachFrame(function(row)
        if row._cells then Columns.Layout(row, header:GetColumns()) end
      end)
    end,
  })
  header:SetSort(sortKey, SortDir.ASC)
end

local function InitRow(row, entry)
  local columns = header:GetColumns()
  if not row._cells then
    rowsMade = true
    Columns.EnsureRow(row, columns)
    -- The row's own verdict goes to the audit panel before its tooltip shows
    CobySuite_Recollect.UI.AddItemTooltip(row, function(self)
      UI.Tooltip.SetRowContext(self._entry)
      return self._entry and self._entry.link
    end, "ANCHOR_RIGHT")
    row:HookScript("OnLeave", function() UI.Tooltip.SetRowContext(nil) end)
    -- A click pins the row's full details (G-05)
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
      if self._entry and UI.DetailWindow then UI.DetailWindow.OpenRow(self._entry) end
    end)
  end
  Columns.Layout(row, columns)
  Columns.Paint(row, entry, columns, entry._index)
end

local function BuildList()
  scrollBox = CreateFrame("Frame", nil, window, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  scrollBox:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD - SCROLLBAR_WIDTH - 4, 40)
  local scrollBar = CreateFrame("EventFrame", nil, window, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(ROW_HEIGHT)
  view:SetElementInitializer("Button", InitRow)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
end

local function Build()
  window = CobySuite_Recollect.UI.CreateWindow({
    name = "RecollectListWindow",
    title = "Recollect Audit",
    icon = Recollect.ICON,
    width = 1100, height = 520,
    resizable = { minWidth = 900, minHeight = 300, maxWidth = 1800, maxHeight = 1200 },
    escapeCloses = true,
    persist = {
      svTable = function() return RECOLLECT_WINDOW_STATE end,
      key = "list",
      defaults = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
    },
  })

  -- The "?" beside the close button opens the feature guide
  window.HelpButton = CobySuite_Recollect.UI.CreateHelpButton(window, {
    name = "RecollectListWindowHelpButton",
    tooltip = "What Recollect can do",
    onClick = function() if UI.Guide then UI.Guide.Toggle() end end,
  })

  -- Measures cell text for a divider's double-click (ListColumns.Measure)
  window.MeasureText = window:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
  window.MeasureText:Hide()

  window.Summary = window:CreateFontString(nil, "OVERLAY", U.Fonts.BODY)
  window.Summary:SetPoint("TOPLEFT", window, "TOPLEFT", PAD + 2, -32)
  window.Summary:SetJustifyH("LEFT")

  window.Refresh = CobySuite_Recollect.UI.CreateButton(window, {
    text = "Refresh", size = { 80, 20 }, fontSize = 10,
    point = { "TOPRIGHT", window, "TOPRIGHT", -PAD - 4, -28 },
    tooltip = "Read the bags again and re-check every item",
    onClick = function() UI.RefreshList() end,
  })
  window.Search = CobySuite_Recollect.UI.CreateSearchBox(window, {
    name = "RecollectListSearch", width = 180,
    point = { "RIGHT", window.Refresh, "LEFT", -10, 0 },
    placeholder = "Search items, uses, reasons",
    onSearch = function(text)
      searchText = (text or ""):lower()
      UI.RefreshList()
    end,
  })
  funnel = CobySuite_Recollect.UI.CreateFilterButton(window, {
    name = "RecollectListFilterButton",
    point = { "RIGHT", window.Search, "LEFT", -10, 0 },
    defs = FILTER_DEFS,
    isChecked = function(key) return filters[key] == true end,
    setChecked = function(key, on)
      filters[key] = on and true or nil
      UI.RefreshList()
    end,
    onClear = function()
      wipe(filters)
      UI.RefreshList()
    end,
    tooltipIdle = "Narrow the list by verdict, by place, by why Recollect can't tell, or to items with a known or recorded use.",
    menu = { name = "RecollectListFilterMenu", parent = window },
  })
  window.Summary:SetPoint("RIGHT", funnel, "LEFT", -10, 0)
  window.Summary:SetWordWrap(false)

  BuildHeader()
  BuildList()

  window.Footer = window:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  window.Footer:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", PAD + 2, 12)
  window.Footer:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, 12)
  window.Footer:SetJustifyH("LEFT")
  window.Footer:SetWordWrap(true)
  local gray = U.Colors.LABEL_GRAY
  window.Footer:SetTextColor(gray[1], gray[2], gray[3])
  window.Footer:SetText(FOOTER_TEXT)

  window:HookScript("OnShow", function() UI.RefreshList() end)
  window:Hide()
  Recollect.EventBus:Register(listener, { Recollect.Events.InventoryChanged, Recollect.Events.ConfigChanged })
end

function UI.ToggleList()
  if not window then
    Recollect.Utilities.Message.Warn("The list opens after login finishes; try again in a moment.")
    return
  end
  -- The first show makes the row frames, which never happens in combat
  if not rowsMade and not window:IsShown() and InCombatLockdown() then
    if not openAfterCombat then
      openAfterCombat = true
      EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_REGEN_ENABLED", function()
        openAfterCombat = false
        if not window:IsShown() then window:Toggle() end
      end)
    end
    Recollect.Utilities.Message("The Recollect Audit opens when combat ends.")
    return
  end
  window:Toggle()
end

EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_LOGIN", function()
  if InCombatLockdown() then
    EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_REGEN_ENABLED", Build)
  else
    Build()
  end
end)
