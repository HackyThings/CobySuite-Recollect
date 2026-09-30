-------------------------------------------------------------------------------
-- UI.ListWindow: the Recollect Audit, one sortable table of every stack this
-- character can account for (Verdicts.Rows), with what it is, its verdict,
-- what it is used for and why; other characters' stored items too when the
-- settings say so
--
-- Built at login (no CreateFrame in combat), refreshed when shown and on
-- InventoryChanged while shown. The scroll box makes its row frames when
-- rows first fill it, on the first show, so a first open asked for in combat
-- waits for combat to end.
--
-- The top says what the window is for, then a summary of the listed stacks
-- by verdict (UI.ListSummary). A search box matches the item, where it is,
-- the checks that answered, what it is used for and its reason; the funnel's
-- menu is grouped (UI.ListFilterDefs): the verdict, where it is, its uses
-- (a known use, an alt's recorded recipes, F-02) and why Recollect can't tell
-- (G-04). Hovering a row shows the item's tooltip, and the audit panel
-- beside it (the configured key) shows that row's own verdict
-- (UI.Tooltip.SetRowContext); clicking a row pins its full details
-- (UI.DetailWindow, G-05). The columns fit the window, and Reason keeps at
-- least ListColumns.REASON_MIN (BA-15). With nothing to show, the list says
-- why (UI.ListEmptyText).
--
-- Tabs along the bottom (UI.ListTabDefs), while list_other_characters is on
-- and another character has stored data: My Items (this character and the
-- warband bank), All Characters, then one per other character. They are
-- made at login from the characters stored then; the one chosen is kept in
-- RECOLLECT_WINDOW_STATE.listTab. Other characters' rows come from
-- Verdicts.Rows as before, with only the account-wide checks (contract rule
-- 30); a tab only chooses which rows show.
-------------------------------------------------------------------------------
local UI = Recollect.UI
local Columns = UI.ListColumns
local U = CobySuite_Recollect.Utilities
local SortDir = CobySuite_Recollect.SortDir
local Registry = Recollect.Purposes.Registry
local V = Registry.Verdict

local ROW_HEIGHT = 20
local HEADER_HEIGHT = 20
local HEADER_TOP = -72       -- below the intro and the summary
local PAD = 12
local SCROLLBAR_WIDTH = 10
local TAB_MIN_WIDTH = 48     -- a tab is never squeezed narrower than this
local INTRO_TEXT = "Every item you hold: what it's for, and whether you still need it."
local FOOTER_TEXT = "Outdated: the facts say it has been replaced. Lower level: gear below what you wear, not "
  .. "shown to be from an earlier season. Junk: the game's label for gray items with a vendor price. Purpose done: "
  .. "every use Recollect checks is finished. Can't tell: not confirmed yet. Not checked yet: reputation tokens, and "
  .. "hidden uses (secrets) Recollect doesn't list yet."
UI.ListTexts = { intro = INTRO_TEXT, footer = FOOTER_TEXT }   -- read by the suites

local window, header, scrollBox, funnel
local rows, allRows = {}, {}
local tabDefs = {}             -- UI.ListTabDefs, made at login
local activeTab = "mine"
local sortKey, sortAscending = "verdictRank", true
local searchText = ""
local filters = {}   -- [key] = true, for this session
local rowsMade = false         -- a row frame exists (the first ones are made out of combat)
local openAfterCombat = false  -- a first open asked for in combat is waiting

-------------------------------------------------------------------------------
-- Filters
-------------------------------------------------------------------------------
-- The verdicts in the order the list sorts them: what to act on first
local VERDICT_ORDER = { V.NEEDED, V.USE, V.USEFUL, V.UNKNOWN, V.JUNK, V.OUTDATED, V.LOWER, V.DONE }

-- What each verdict means, as the feature guide says it (a menu row's tooltip)
local VERDICT_MEANING = {
  [V.NEEDED] = "Something unfinished still uses it.",
  [V.USE] = "Learn it, open it, or start its quest.",
  [V.USEFUL] = "It still has a use, like something it buys that you lack.",
  [V.UNKNOWN] = "Not confirmed yet. Its audit says what would settle it.",
  [V.JUNK] = "A gray item the game itself marks as junk.",
  [V.OUTDATED] = "The facts say it has been replaced, such as gear of a past season.",
  [V.LOWER] = "Gear below what you wear, not shown to be from an earlier season.",
  [V.DONE] = "Every use Recollect checks is finished.",
}

-- A verdict's name in its list color
local function Colored(verdict)
  local color = UI.VerdictColors and UI.VerdictColors[verdict] or U.Colors.HIGHLIGHT_WHITE
  return U.WrapColor(color, Registry.VerdictLabel[verdict] or tostring(verdict))
end

-- Why an item reads Can't tell (Registry.CATEGORY), one filter each, every
-- category included (review F6: a row of a category with no filter vanished
-- under every Can't tell filter); the labels are the audit panel's
local CATEGORY_ORDER = { "loading", "bank", "profession", "disagree", "unreadable", "character", "unsupported", "finished" }
local CATEGORY_TOOLTIP = {
  unsupported = "No check Recollect has covers this kind of item yet.",
  finished = "Every use Recollect found is done, but something it can't rule out keeps it from Purpose done, "
    .. "such as a quest that may come back.",
}

-- The funnel's menu: group titles (header) over the filters they hold
local FILTER_DEFS = { { header = "Verdict" } }
for _, verdict in ipairs(VERDICT_ORDER) do
  FILTER_DEFS[#FILTER_DEFS + 1] = { key = "v:" .. verdict, label = Colored(verdict), tooltip = VERDICT_MEANING[verdict] }
end
FILTER_DEFS[#FILTER_DEFS + 1] = { header = "Where it is" }
FILTER_DEFS[#FILTER_DEFS + 1] = { key = "l:bags", label = "Bags" }
FILTER_DEFS[#FILTER_DEFS + 1] = { key = "l:bank", label = "Bank",
  tooltip = "The character bank's tabs: read live while the bank is open, else as of your last visit." }
FILTER_DEFS[#FILTER_DEFS + 1] = { key = "l:warband", label = "Warband bank",
  tooltip = "The warband bank's tabs: read live while the bank is open, else as of your last visit." }
FILTER_DEFS[#FILTER_DEFS + 1] = { header = "Uses" }
FILTER_DEFS[#FILTER_DEFS + 1] = { key = "hasUse", label = "Has a known use",
  tooltip = "Only items the game's data links to a quest, an achievement, a recipe, a currency or another item." }
FILTER_DEFS[#FILTER_DEFS + 1] = { key = "altUse", label = "In an alt's recorded recipes",
  tooltip = "Items another character's recipe scan recorded a use for. That is history: the character may have changed since." }
FILTER_DEFS[#FILTER_DEFS + 1] = { header = "Why Recollect can't tell" }
for _, key in ipairs(CATEGORY_ORDER) do
  local category = Registry.CATEGORY[key]
  FILTER_DEFS[#FILTER_DEFS + 1] = { key = "k:" .. key, label = category.label,
    tooltip = category.recovery or CATEGORY_TOOLTIP[key] }
end

UI.ListFilterDefs = FILTER_DEFS   -- read by the suites

-- Does a row pass the search text and the filters? (a group with nothing
-- checked lets everything through; a place is the row's kind, on any
-- character's tab)
function UI.ListRowMatches(row, text, active)
  local anyVerdict, anyPlace, anyCategory = false, false, false
  for key in pairs(active) do
    if key:sub(1, 2) == "v:" then anyVerdict = true end
    if key:sub(1, 2) == "l:" then anyPlace = true end
    if key:sub(1, 2) == "k:" then anyCategory = true end
  end
  if anyVerdict and not active["v:" .. tostring(row.verdict)] then return false end
  if anyPlace and not active["l:" .. tostring(row.kind)] then return false end
  if anyCategory and not active["k:" .. tostring(row.category)] then return false end
  if active.hasUse and (row.usedForText or "") == "" then return false end
  if active.altUse and not row.altUse then return false end
  if text ~= "" then
    local hay = table.concat({ row.name or "", row.where or "", row.purposeText or "", row.usedForText or "", row.reason or "" }, "\n"):lower()
    if not hay:find(text, 1, true) then return false end
  end
  return true
end

-------------------------------------------------------------------------------
-- Tabs
-------------------------------------------------------------------------------
-- ListTabDefs(characters): the tabs, from Snapshots.OtherCharacters()'s list
-- ({ { key = guid, char } }, by name): My Items, All Characters, then one
-- per character with a stored bag or bank tab read (what Verdicts.Rows lists
-- for it; its warband copies are the account's, under My Items). Two of one
-- name get their realms.
function UI.ListTabDefs(characters)
  local tabs = {
    { key = "mine", label = "My Items" },
    { key = "all", label = "All Characters" },
  }
  local Locations = Recollect.Inventory.Locations
  local chars, names = {}, {}
  for _, entry in ipairs(characters or {}) do
    local char = entry.char
    local stored = false
    if type(char) == "table" and type(char.locations) == "table" then
      for bagID, location in pairs(char.locations) do
        local kind = Locations.KindOf(bagID)
        if kind and kind ~= Locations.KIND_WARBAND and type(location) == "table" and type(location.read) == "table" then
          stored = true
        end
      end
    end
    if stored then
      local name = tostring(char.name or "another character")
      names[name] = (names[name] or 0) + 1
      chars[#chars + 1] = { guid = entry.key, name = name, realm = char.realm }
    end
  end
  for _, c in ipairs(chars) do
    local label = c.name
    if names[c.name] > 1 and type(c.realm) == "string" and c.realm ~= "" then label = c.name .. "-" .. c.realm end
    tabs[#tabs + 1] = { key = "char:" .. tostring(c.guid), label = label, guid = c.guid, name = c.name }
  end
  return tabs
end

-- Whether the tabs show: other characters are listed and one has data (with
-- none, My Items and All Characters would list the same rows)
function UI.ListTabsShown(tabs, othersOn)
  return othersOn == true and #tabs > 2
end

-- The tab in effect: the saved one while the tabs show and it is still
-- there, else My Items
function UI.ListActiveTab(saved, tabs, othersOn)
  if not UI.ListTabsShown(tabs, othersOn) then return "mine" end
  for _, tab in ipairs(tabs) do
    if tab.key == saved then return saved end
  end
  return "mine"
end

-- Whether a row belongs on a tab: My Items is this character and the
-- warband bank, All Characters everything, a character's tab its own rows
function UI.ListRowInTab(row, key)
  if key == "all" then return true end
  if key == "mine" or key == nil then return row.character == nil end
  local guid = key:match("^char:(.+)$")
  return guid ~= nil and row.other ~= nil and tostring(row.other.guid) == guid
end

local function TabDef(key)
  for _, tab in ipairs(tabDefs) do
    if tab.key == key then return tab end
  end
  return tabDefs[1]
end

-------------------------------------------------------------------------------
-- Summary and empty state
-------------------------------------------------------------------------------
local function Stacks(n)
  return n == 1 and "1 stack" or ("%d stacks"):format(n)
end

-- ListSummary(shown, total): the stacks listed and how many of each verdict,
-- in the verdicts' colors and the list's order, none for a verdict no row has
-- ("40 of 142 stacks shown: 3 Needed, 12 Useful, 25 Can't tell"); "" when the
-- tab lists nothing
function UI.ListSummary(shown, total)
  if (total or 0) == 0 then return "" end
  local counts = {}
  for _, row in ipairs(shown) do counts[row.verdict] = (counts[row.verdict] or 0) + 1 end
  local parts = {}
  for _, verdict in ipairs(VERDICT_ORDER) do
    local n = counts[verdict]
    if n and n > 0 then parts[#parts + 1] = ("%d %s"):format(n, Colored(verdict)) end
  end
  local head = #shown == total and Stacks(total) or ("%d of %s shown"):format(#shown, Stacks(total))
  if #parts == 0 then return head end
  return head .. ": " .. table.concat(parts, ", ")
end

-- ListEmptyText(tab, total, shown): what the list says when it shows no row,
-- or nil while it shows one. tab is a ListTabDefs entry; total the rows on
-- that tab before the search and filters
function UI.ListEmptyText(tab, total, shown)
  if (shown or 0) > 0 then return nil end
  if (total or 0) > 0 then
    return "Nothing matches your search and filters. Clear the search box, or the filters with the red x on the funnel."
  end
  if tab and tab.guid then
    return ("Nothing in what Recollect last read of %s's bags and bank. Log in to %s to read them again."):format(tab.name, tab.name)
  end
  return "Nothing to list yet. Recollect reads your bags once the game has loaded them; open your bank once so it can list that too."
end

-- The hint on the summary's line: how to see why, and every detail
local function HintText()
  local key = Recollect.PanelKeyName and Recollect.PanelKeyName() or "Alt"
  if key == nil then return "Click a row for everything about it." end
  if key == "always" then return "Point at a row for its audit; click it for everything." end
  return ("Hold %s over a row for its audit; click it for everything."):format(key)
end

-------------------------------------------------------------------------------
-- The list
-------------------------------------------------------------------------------
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

local function OthersOn()
  return Recollect.Config.Get(Recollect.Config.Options.LIST_OTHERS) == true
end

local function SavedTab()
  return type(RECOLLECT_WINDOW_STATE) == "table" and RECOLLECT_WINDOW_STATE.listTab or nil
end

-- Shows the tabs while they apply, lays them out along the bottom edge, each
-- as wide as its name up to an equal share of the window, and marks the
-- tab in effect
local function UpdateTabs()
  if not window or not window.Tabs then return end
  local shown = UI.ListTabsShown(tabDefs, OthersOn())
  local count = shown and #window.Tabs or 0
  local share = math.max(TAB_MIN_WIDTH, math.floor(((window:GetWidth() or 0) - 30) / math.max(count, 1)))
  local previous
  for i, button in ipairs(window.Tabs) do
    button:SetShown(shown)
    if shown then
      PanelTemplates_TabResize(button, 0, nil, nil, share)
      button:ClearAllPoints()
      if previous then
        button:SetPoint("LEFT", previous, "RIGHT", 0, 0)
      else
        button:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 15, 3)
      end
      previous = button
    end
    if tabDefs[i].key == activeTab then PanelTemplates_SetTab(window, i) end
  end
end

function UI.RefreshList()
  if not window or not window:IsShown() then return end
  local ok, built = pcall(Recollect.Verdicts.Rows.Build)
  if not ok then
    Recollect.Debug.Warn("UI", "List build failed: %s", tostring(built))
    built = {}
  end
  activeTab = UI.ListActiveTab(SavedTab(), tabDefs, OthersOn())
  UpdateTabs()
  allRows = {}
  for _, row in ipairs(built) do
    if UI.ListRowInTab(row, activeTab) then allRows[#allRows + 1] = row end
  end
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
  window.Summary:SetText(UI.ListSummary(rows, #allRows))
  window.Hint:SetText(HintText())
  local empty = UI.ListEmptyText(TabDef(activeTab), #allRows, #rows)
  window.Empty:SetText(empty or "")
  window.Empty:SetShown(empty ~= nil)
end

local refreshFold = U.Coalesce(0.3, function() UI.RefreshList() end)

function listener:ReceiveEvent()
  if window and window:IsShown() then refreshFold:Call() end
end

local function BuildHeader()
  header = CreateFrame("Frame", nil, window)
  Mixin(header, CobySuite_Recollect.UI.TableHeaderMixin)
  header:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, HEADER_TOP)
  header:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD - SCROLLBAR_WIDTH - 4, HEADER_TOP)
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

  -- Said over the empty list: why nothing shows (UI.ListEmptyText)
  window.Empty = window:CreateFontString(nil, "OVERLAY", U.Fonts.BODY)
  window.Empty:SetPoint("TOPLEFT", scrollBox, "TOPLEFT", 20, -40)
  window.Empty:SetPoint("TOPRIGHT", scrollBox, "TOPRIGHT", -20, -40)
  window.Empty:SetJustifyH("CENTER")
  window.Empty:SetWordWrap(true)
  local gray = U.Colors.LABEL_GRAY
  window.Empty:SetTextColor(gray[1], gray[2], gray[3])
  window.Empty:Hide()
end

-- The search box, the funnel and Refresh, right of the intro
local function BuildToolbar()
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
    tooltipIdle = "Narrow the list by verdict, by where it is, by its uses, or by why Recollect can't tell.",
    menu = { name = "RecollectListFilterMenu", parent = window },
  })
end

-- The intro (what the window is for), the summary with the hint beside it,
-- and the footer
local function BuildTexts()
  window.Intro = window:CreateFontString(nil, "OVERLAY", U.Fonts.BODY)
  window.Intro:SetPoint("TOPLEFT", window, "TOPLEFT", PAD + 2, -32)
  window.Intro:SetPoint("RIGHT", funnel, "LEFT", -10, 0)
  window.Intro:SetJustifyH("LEFT")
  window.Intro:SetWordWrap(false)
  window.Intro:SetText(INTRO_TEXT)

  window.Hint = window:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  window.Hint:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD - 4, -53)
  window.Hint:SetJustifyH("RIGHT")
  window.Hint:SetWordWrap(false)
  local gray = U.Colors.LABEL_GRAY
  window.Hint:SetTextColor(gray[1], gray[2], gray[3])

  window.Summary = window:CreateFontString(nil, "OVERLAY", U.Fonts.BODY)
  window.Summary:SetPoint("TOPLEFT", window, "TOPLEFT", PAD + 2, -52)
  window.Summary:SetPoint("RIGHT", window.Hint, "LEFT", -12, 0)
  window.Summary:SetJustifyH("LEFT")
  window.Summary:SetWordWrap(false)

  window.Footer = window:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  window.Footer:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", PAD + 2, 12)
  window.Footer:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, 12)
  window.Footer:SetJustifyH("LEFT")
  window.Footer:SetWordWrap(true)
  window.Footer:SetTextColor(gray[1], gray[2], gray[3])
  window.Footer:SetText(FOOTER_TEXT)
end

-- One tab per ListTabDefs entry, made now (login, out of combat); shown or
-- hidden later by UpdateTabs, never made again
local function BuildTabs()
  local ok, characters = pcall(Recollect.Inventory.Snapshots.OtherCharacters)
  tabDefs = UI.ListTabDefs(ok and characters or {})
  window.Tabs = {}
  for i, tab in ipairs(tabDefs) do
    local b = CreateFrame("Button", "RecollectListWindowTab" .. i, window, "PanelTabButtonTemplate")
    b:SetText(tab.label)
    b:SetID(i)
    b:SetScript("OnClick", function()
      PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
      if type(RECOLLECT_WINDOW_STATE) == "table" then RECOLLECT_WINDOW_STATE.listTab = tab.key end
      UI.RefreshList()
    end)
    PanelTemplates_TabResize(b, 0)
    b:Hide()
    window.Tabs[i] = b
  end
  window.numTabs = #window.Tabs
  PanelTemplates_SetTab(window, 1)
  window:HookScript("OnSizeChanged", function() UpdateTabs() end)
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

  BuildToolbar()
  BuildTexts()
  BuildHeader()
  BuildList()
  BuildTabs()

  window:HookScript("OnShow", function() UI.RefreshList() end)
  window:Hide()
  Recollect.EventBus:Register(listener, { Recollect.Events.InventoryChanged, Recollect.Events.ConfigChanged })
end

function UI.ToggleList()
  if not window then
    Recollect.Utilities.Message.Warn("The Recollect Audit opens once login finishes; try again in a moment.")
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
