-------------------------------------------------------------------------------
-- UI.DetailWindow: everything about one item, pinned in a window (G-05)
--
-- The audit panel beside a tooltip shows a few lines; this window answers,
-- for a player who knows nothing of the game's websites (Cobanyte,
-- 2026-09-24): what is it, what is it for and how many does that take, how
-- do I get more and where, and what do I have. Its tabs:
--   Overview            the verdict (or what the item is for), its reason,
--                       recovery step and the panel's Tip (UI.Tooltip.Tip);
--                       the header's Still needed? box (Detail.Keep), a
--                       suggestion for an item held; WHAT IT'S FOR, opening
--                       with what the item is (FOR.Explain; the game's own
--                       filing of it only when it names an added patch),
--                       then its groups of uses (with the endeavor's tasks
--                       that name it, and, when every use is gone, what they
--                       were: the No longer available tab summed up as the
--                       panel sums it), ACHIEVEMENTS (with their metas),
--                       HOW TO GET MORE (the season tag and the patch that
--                       removed it first; what crafting it takes), GUIDE NOTES (UI.
--                       UsedFor.NoteLines), WHAT YOU HAVE; every check with
--                       its reason. Each titled section is a header like
--                       the feature guide's that opens and closes (Sections,
--                       below). Every name the Overview, the checks and
--                       the header's reason use that the game links is a
--                       real link (Links in the text, below). A section
--                       names its rows, never a count alone, what is still
--                       to get or do first; rows that read alike are one
--                       line; the rest is a container whose plus button lists
--                       them in an indented box, a slice at a time (Lists in
--                       the Overview, below; items 4a and 10). An older
--                       system's line (Purposes.Legacy) leads WHAT IT'S FOR
--   Buys, Quests & achievements, Crafting, Comes from, What it takes, No
--   longer available    one table each (UI.DataTable over UI.DetailData's
--                       rows): sortable columns, a search box, a filter for
--                       what you still need, have, can't use, and by kind
-- A tab shows only when it has rows, with how many. The rows are built a
-- slice at a time (UI.DetailData), with a loading bar, so an item with
-- thousands of uses never stalls a frame; names load for the rows on screen,
-- then for the rest in the background.
--
-- A row (Cobanyte, 2026-09-24):
--   hover       over the thing itself (its icon and name) the game's own
--               tooltip (the item, mount, toy, achievement, currency, recipe
--               or quest) as it is, with what the clicks do under it, one a
--               line; over the Where or Sold by cell, who and where in full;
--               anywhere else, nothing
--   click       the click on its link in chat, the game's own SetItemRef: a
--               click opens its tooltip pinned (ItemRefTooltip), Shift-click
--               links it in chat, Ctrl-click previews it in the dressing
--               room, Shift-right-click opens what the game opens for it
--   Alt-click   (no item click of the game's uses Alt) opens that item here,
--               Back and Forward walking the history
--   right-click a menu: open, link, waypoint, preview
--   waypoint    the Map column's button, the world map's own pin (lit on
--               hover, darker while pressed), and a plain click on the Map
--               column around it, set a waypoint (UI.Waypoint.Set)
--   cost        hovering a purchase's Cost cell lists every part of the
--               trade (Relations.Costs), each with its icon and how many
--               you have, gold included, and what the data doesn't list
--               (item 9); "+" in the cell says there is more than this item
--
-- It opens two ways (the owner's choice, 2026-09-24): the pin key while the
-- audit panel shows (Alt+D by default, PIN_KEY; turned off with PIN_ENABLED)
-- and a left click on a row of the item list. The pin key can be a click
-- instead ("ALT-BUTTON1", the owner's ask, 2026-09-25): that click on any
-- item opens it, in combat too, through a post-hook on the game's
-- HandleModifiedItemClick, which bags, the bank, chat links (SetItemRef),
-- loot, vendors and the character sheet call for every modified click on an
-- item (Blizzard's ContainerFrame, BankFrame, ItemRef, PaperDollFrame). A
-- click the game uses (CHATLINK, DRESSUP, EXPANDITEM) is left to the game;
-- a bag or bank slot opens with its verdict, anything else in reference
-- mode. A key is bound with
-- SetOverrideBindingClick to this module's own hidden button and owner (the
-- waypoint key's owner clears every binding it holds), only out of combat,
-- as UI.Waypoint does: a panel first shown in combat binds it when combat
-- ends. Every frame (the table's rows, the tabs, the menus, the Map buttons)
-- is built at login (or when combat ends), so the window works in combat.
-------------------------------------------------------------------------------
local Detail = {}
Recollect.UI.DetailWindow = Detail

local U = CobySuite_Recollect.Utilities
local Config = Recollect.Config

local BUTTON_NAME = "RecollectPinButton"
local WINDOW_NAME = "RecollectDetailWindow"
local WIDTH, HEIGHT = 780, 580
local PAD = 12
local TOP = 30
local ICON = 32
local HEADER_GAP = 4         -- between the header and what's under it
-- The header and its answer band: the item's icon, the header's height
-- above the band, the band's icon, padding above and below its text, least
-- height, most lines, and how strongly the answer's color tints it
local HERO = { ICON = 40, H = 50, BAND_ICON = 16, BAND_PAD = 7, BAND_MIN = 30, BAND_LINES = 2, BAND_TINT = 0.13 }
local KEEP_ICONS   -- each answer's icon (set beside Detail.Keep)
local OVERVIEW_TOP = 3       -- the Overview's first line starts this far down: the scroll frame clips
                             -- whatever reaches past its top, and tall letters rise above their line
local BULLET = 6
local INDENT = 14
local LINE_GAP = 4
local SECTION_GAP = 10
-- room above a group's title inside a section (Group), the lines under it,
-- WHAT YOU HAVE's tiles (width, height, gap, icon), and an achievement's
-- progress bar (width, height)
local LAYOUT = { GROUP_GAP = 8, GROUP_INDENT = 12, TILE_W = 128, TILE_H = 38, TILE_GAP = 6, TILE_ICON = 24,
  BAR_W = 220, BAR_H = 4, TILES_MIN = 6, TILES_GAP = 6 }
local MAP_BUTTONS = 16
local MAP_WIDTH = 18     -- the waypoint button: the world map's own pin
local MAP_HEIGHT = 18    -- the tables' waypoint button
local LINE_MAP = 13      -- the Overview's: no taller than a line of text, so rows with and
                         -- without a pin keep one spacing (Cobanyte, 2026-09-28)
local PIN_ATLAS, PIN_HIGHLIGHT = "Waypoint-MapPin-Untracked", "Waypoint-MapPin-Highlight"
local POOL = 44           -- table rows: the tallest window shows no more
local ROW_HEIGHT = 20
local APPLY_EVERY = 0.3   -- seconds between table updates while rows load
local VERDICT_EVERY = 2   -- seconds between reads of the pinned copy's verdict
local NAME_REPAINTS = 12  -- repaints for creature names still loading, per item shown

local seams = {
  InCombat = function() return InCombatLockdown() end,
  Bind = function(owner, key) SetOverrideBindingClick(owner, true, key, BUTTON_NAME) end,
  Clear = function(owner) ClearOverrideBindings(owner) end,
  Now = function() return GetTime() end,
  -- A click on a link, as the chat frame makes it: SetItemRef(link data,
  -- link text, button)
  ItemRef = function(link, button)
    local data = link:match("|H([^|]+)|h")
    if data then SetItemRef(data, link, button) end
  end,
  OnlyAlt = function() return IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() end,
  -- The click being handled, as the pin key's click chord reads it
  MouseButton = function() return GetMouseButtonClicked() end,
  Modifiers = function() return IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown() end,
  -- The game handles this modified click itself (a link, a preview, expanding)
  GameClick = function()
    return IsModifiedClick("CHATLINK") or IsModifiedClick("DRESSUP") or IsModifiedClick("EXPANDITEM")
  end,
  AnyModifier = function() return IsModifierKeyDown() end,
  Tooltip = function() return GameTooltip end,
  ViewerName = function() return UnitName("player") end,
  After = function(seconds, fn) C_Timer.After(seconds, fn) end,
  Dressable = function(itemID) return C_Item.IsDressableItemByID(itemID) end,
  -- the game's achievement window at it: selected at once when the window
  -- is shown, else one click on our prompt's secure button opens it
  -- (UI/AchievementPrompt.lua)
  ShowAchievement = function(achievementID) return Recollect.UI.AchievementPrompt.Show(achievementID) end,
  -- Shift-click, as the game reads it (IsModifiedClick CHATLINK)
  ChatLinkClick = function() return IsModifiedClick ~= nil and IsModifiedClick("CHATLINK") == true end,
  -- the game's own map pin link for a place: the player's waypoint is set
  -- there only to read C_Map.GetUserWaypointHyperlink, then put back as it
  -- was (or cleared when there was none), its tracking too, even when the
  -- read fails; nil when the game didn't take the place (SetUserWaypoint's
  -- wasSet), since the link would then be the old waypoint's
  PinLink = function(mapID, x, y)
    local had = C_Map.HasUserWaypoint() and C_Map.GetUserWaypoint() or nil
    local tracked = C_SuperTrack.IsSuperTrackingUserWaypoint()
    local ok, link = pcall(function()
      if not C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y)) then return nil end
      return C_Map.GetUserWaypointHyperlink()
    end)
    pcall(function()
      if had then C_Map.SetUserWaypoint(had) else C_Map.ClearUserWaypoint() end
      if C_SuperTrack.IsSuperTrackingUserWaypoint() ~= tracked then C_SuperTrack.SetSuperTrackedUserWaypoint(tracked) end
    end)
    return ok and link or nil
  end,
  -- The game's context menu at the cursor (Blizzard_Menu's MenuUtil)
  ContextMenu = function(owner, generator) return MenuUtil.CreateContextMenu(owner, generator) end,
  Hidden = function(frame) return frame ~= nil and not frame:IsShown() end,
  -- An item's own tooltip facts, for its season tag (Facts.Tooltip)
  ItemTooltip = function(itemID) return Recollect.Facts.Tooltip.FromItemID(itemID) end,
  -- The gold on hand, and a price in gold, silver and copper with their icons
  -- (PlayerScriptDocumentation, CurrencyInfoDocumentation), for a cost's tooltip
  Money = function() return GetMoney() end,
  Coins = function(copper) return C_CurrencyInfo.GetCoinTextureString(copper) end,
}

local target = nil        -- the panel model the key pins now
local bound, boundKey, clearAfterCombat = false, nil, false
local button, window
local shown = nil         -- the model the window shows
local nameRepaints = 0    -- repaints asked for creature names since it was shown
local job = nil           -- UI.DetailData's build for it
local back, forward = {}, {}   -- models, for Back and Forward

local function Data() return Recollect.UI.DetailData end

-------------------------------------------------------------------------------
-- The key
-------------------------------------------------------------------------------
-- The configured key ("ALT-D"), or nil when the pin key is turned off; nil
-- and true when it is the waypoint key too (two override bindings on one
-- key: the waypoint key keeps it, and the panel says so)
function Detail.Key()
  if Config.Get(Config.Options.PIN_ENABLED) == false then return nil end
  local key = Config.Get(Config.Options.PIN_KEY)
  if type(key) ~= "string" or key == "" then return nil end
  if key == Recollect.UI.Waypoint.Key() then return nil, true end
  return key
end

-- A click chord's parts ("CTRL-ALT-BUTTON1": LeftButton, no Shift, Ctrl,
-- Alt), or nil for a key
local CLICK_BUTTONS = { BUTTON1 = "LeftButton", BUTTON2 = "RightButton", BUTTON3 = "MiddleButton" }
local function ClickChord(key)
  local n = type(key) == "string" and key:match("BUTTON(%d+)$")
  if not n then return nil end
  return { button = CLICK_BUTTONS["BUTTON" .. n] or ("Button" .. n),
    shift = key:find("SHIFT-", 1, true) ~= nil, ctrl = key:find("CTRL-", 1, true) ~= nil,
    alt = key:find("ALT-", 1, true) ~= nil }
end
Detail.ClickChord = ClickChord

-- The panel's line when the pin key is the waypoint key, else nil
function Detail.ClashText()
  local _, clash = Detail.Key()
  return clash and "Pin key: the same key as the waypoint key; choose another in /rec settings" or nil
end

-- The panel's line for the key, or nil when it is off
function Detail.HintText(afterCombat)
  local key = Detail.Key()
  if not key then return nil end
  return ("%s%s: pin the full details"):format(Recollect.UI.Waypoint.KeyText(key), afterCombat and " after combat" or "")
end

local function Unbind()
  if not bound then return end
  if seams.InCombat() then
    clearAfterCombat = true
    return
  end
  pcall(seams.Clear, button)
  bound, boundKey, clearAfterCombat = false, nil, false
end

-- The panel shows a model: bind the key out of combat. Returns live and
-- afterCombat, as UI.Waypoint.Arm
function Detail.Arm(model)
  target = model and model.source and model or nil
  local key = target and Detail.Key()
  if not key then
    Unbind()
    return false, false
  end
  -- a click needs no binding, and works in combat
  if ClickChord(key) then
    Unbind()
    return true, false
  end
  if bound and boundKey == key then
    clearAfterCombat = false
    return true, false
  end
  if seams.InCombat() then return false, true end
  if bound then pcall(seams.Clear, button) end
  local ok = pcall(seams.Bind, button, key)
  bound, boundKey, clearAfterCombat = ok, ok and key or nil, false
  return bound, false
end

function Detail.Disarm()
  target = nil
  Unbind()
end

local function OnCombatEnded()
  if target then
    Detail.Arm(target)
  elseif clearAfterCombat then
    Unbind()
  end
end

-------------------------------------------------------------------------------
-- The Overview: sections of lines from the model and the rows
--
-- A line is { text, color, place, links, plain, big, sub, header, display }:
-- text stays plain words (the tests read it); links = { { text, color, row }
-- or { text, color, kind, id } } names the things it uses that the game
-- links, which the painter turns into real links (see Links in the text).
-------------------------------------------------------------------------------
local function ItemName(itemID)
  return Recollect.Facts.Item.Name(itemID) or ("item " .. tostring(itemID))
end

local function Plain(text, color)
  return { text = text, color = color or U.Colors.LIGHT_GRAY, plain = true }
end

-- A group's title inside a section ("Buys: 3", "What it takes: 4"): painted
-- white with room above it, and the lines after it, up to the next group,
-- indented under it (Cobanyte, 2026-09-28: "like titles almost that the
-- bullets fall under")
local function Group(text, color)
  local line = Plain(text, color or U.Colors.HIGHLIGHT_WHITE)
  line.group = true
  return line
end

-- A state's words inside a line: its first letter lowered, names kept
local function Lowered(text)
  return (tostring(text):gsub("^%u", string.lower))
end

-- A row's state inside a line: a route's tags as they read there
-- ("Blood Elf only" keeps its capitals, D19), else its state lowered
local function RowState(row)
  return row.stateInline or Lowered(row.stateText)
end

-- The kinds of source a new player looks for first
local SOURCE_ORDER = { ["Drops from"] = 1, ["Boss loot"] = 2, ["Zone drop"] = 3, ["World drop"] = 4, ["Sold by"] = 5,
  ["Crafted by"] = 6, ["Found at"] = 7, Reward = 8, Achievement = 9, Renown = 10, ["Choice reward"] = 11,
  ["Trading Post"] = 12, ["Made from"] = 13, ["Crafted with"] = 14, ["Black Market"] = 15 }
local MAX_SUMMARY = 5

-------------------------------------------------------------------------------
-- Lists in the Overview (items 4a and 10, 2026-09-25). A section never
-- gives a count alone: it names its rows, still to get or do first, then
-- those with no state, then what is done, then what is for someone else,
-- MAX_SUMMARY of them. Rows that read alike are one line: different things
-- (four recipe ranks of one name, creatures at one spot) say how many,
-- ", 4 of them", where the state begins; the same thing twice (one toy at
-- two vendors) or quests of one title (rule 26) join silently. The rest sit
-- in a container, "and 12 more on the Buys tab" with a plus button, that lists
-- them here in an indented box, with the same links and states as the
-- tab's rows, SLICE at a time ("Show 25 more"), up to MAX lines, and the
-- tab holds the rest. Which containers are open is kept per section for the
-- session (expanded); how far each is shown, for the item shown (shown).
-------------------------------------------------------------------------------
-- The container's button is the objective tracker's plus and minus, as the
-- feature guide's sections use (CobySuite.UI.CreateGuideWindow; Cobanyte,
-- 2026-09-26: the list arrow was too faint to see)
local Fold = { expanded = {}, shown = {}, SLICE = 25, MAX = 200, BOX_INDENT = 20, HEIGHT = 20, ICON = 16,
  COLLAPSED = CobySuite_Recollect.UI.FOLD_ATLAS.closed, EXPANDED = CobySuite_Recollect.UI.FOLD_ATLAS.open }

local FILTER_RANK = { missing = 1, none = 2, have = 3, other = 4 }

-- Ordered(rows, keep, need): the rows keep accepts (every row when keep is
-- nil): still to get or do, then no state, then done, then for someone
-- else, each group in the tab's own order; only the first need of them
-- when need is given (Mark of Honor's Overview reads about 8,700 rows at every
-- paint, and shows a few), and how many there are in all
function Fold.Ordered(rows, keep, need)
  local groups, sizes, total = { {}, {}, {}, {} }, { 0, 0, 0, 0 }, 0
  for _, row in ipairs(rows) do
    if not keep or keep(row) then
      total = total + 1
      local g = (row.restricted and not row.untold) and 4 or FILTER_RANK[row.filterState or "none"] or 2
      if not need or sizes[g] < need then
        sizes[g] = sizes[g] + 1
        groups[g][sizes[g]] = row
      end
    end
  end
  local out = groups[1]
  for g = 2, 4 do
    for _, row in ipairs(groups[g]) do
      if need and #out >= need then return out, total end
      out[#out + 1] = row
    end
  end
  return out, total
end

local function Identity(row)
  return tostring(row.kind) .. ":" .. tostring(row.id or row.itemID or row.questID or row.name)
end

-- Take(rows, from, limit, lineOf): the lines of rows[from], rows[from + 1],
-- ..., at most limit of them, a row that reads like a line already taken
-- joining it (see above; line.cut is where a line's state begins); the
-- lines and the index of the first row not shown
function Fold.Take(rows, from, limit, lineOf)
  local lines, byText, i = {}, {}, from
  while rows[i] do
    local row = rows[i]
    local line = lineOf(row)
    local key = tostring(line.text) .. "\0" .. tostring(line.color)
    local kept = byText[key]
    if kept then
      local id = Identity(row)
      if row.what ~= "quest" and not kept.ids[id] then
        kept.ids[id], kept.alike = true, kept.alike + 1
      end
    elseif #lines < limit then
      line.ids, line.alike = { [Identity(row)] = true }, 1
      lines[#lines + 1] = line
      byText[key] = line
    else
      break
    end
    i = i + 1
  end
  for _, line in ipairs(lines) do
    if line.alike > 1 then
      local text = tostring(line.text)
      local cut = math.min(line.cut or #text, #text)
      line.text = ("%s, %d of them%s"):format(text:sub(1, cut), line.alike, text:sub(cut + 1))
    end
    line.ids, line.alike, line.cut = nil, nil, nil
  end
  return lines, i
end

-- A tab's label, as its button reads ("Comes from")
function Fold.TabLabel(key)
  for _, tab in ipairs(Data().TABS) do
    if tab.key == key then return tab.label end
  end
  return key
end

-- Container(lines, key, rows, from, tab, lineOf, total): the rows from
-- rows[from] on as a container after a section's first lines: its header,
-- and while it is open, a slice of them in its box, then "Show 25 more" or,
-- past MAX, the tab's. total is how many rows there are when rows holds
-- only the first of them (Ordered's need)
function Fold.Container(lines, key, rows, from, tab, lineOf, total)
  total = total or #rows
  local rest = total - from + 1
  if rest <= 0 then return end
  local open = Fold.expanded[key] == true
  local label = Fold.TabLabel(tab)
  lines[#lines + 1] = { text = ("and %d more on the %s tab"):format(rest, label), plain = true, toggle = key,
    expanded = open, count = rest }
  if not open then return end
  local want = math.min(Fold.shown[key] or Fold.SLICE, Fold.MAX)
  local slice, nextIndex = Fold.Take(rows, from, want, lineOf)
  for _, line in ipairs(slice) do
    line.box = key
    lines[#lines + 1] = line
  end
  local left = total - nextIndex + 1
  if left <= 0 then return end
  if want < Fold.MAX then
    lines[#lines + 1] = { text = ("Show %d more (%d left)"):format(math.min(Fold.SLICE, left), left), plain = true,
      more = key, box = key, color = U.Colors.INFO_BLUE }
  else
    lines[#lines + 1] = { text = ("and %d more on the %s tab"):format(left, label), plain = true, box = key,
      color = U.Colors.LABEL_GRAY }
  end
end

-- Need(key, limit): how many of a section's rows its lines can show: its
-- first limit, its container's slices while open, and room for rows that
-- join a line already shown
function Fold.Need(key, limit)
  local open = Fold.expanded[key] and math.min(Fold.shown[key] or Fold.SLICE, Fold.MAX) or 0
  return limit + open + 64
end

-- Links for names a line heard ({ kind, id, text, color? }: UI.UsedFor's
-- line.links, Facts.Chains' namer), added to into
local function HeardLinks(names, into)
  into = into or {}
  for _, name in ipairs(names or {}) do
    local row = type(name.text) == "string" and name.text ~= "" and Data().LinkRow(name.kind, name.id)
    if row then into[#into + 1] = { text = name.text, color = name.color or Data().LinkColor(row), row = row } end
  end
  return into
end

-- A row's own name as a link, added to into (a thing the game links)
local function RowLink(row, name, into)
  into = into or {}
  if type(name) == "string" and name ~= "" and Data().Linkable(row) then
    into[#into + 1] = { text = name, color = Data().LinkColor(row), row = row }
  end
  return into
end

-- The names of a purchase's other costs as links, as UI.UsedFor.CostWords
-- words them (an item by its name, a currency by its own)
local function CostLinks(row, links)
  for i, cost in ipairs(Data().Costs(row) or {}) do
    if i > 1 and cost.id then
      local name
      if cost.kind == "item" then
        name = Recollect.Facts.Item.Name(cost.id)
      elseif cost.kind == "currency" then
        local info = Recollect.UI.UsedFor.parts.Currency(cost.id)
        name = info and info.name
      end
      if name then HeardLinks({ { kind = cost.kind, id = cost.id, text = name } }, links) end
    end
  end
  return links
end

-- A purchase: "Item: Phoenix Ash Talisman for 1 plus other costs, at Zektar
-- (Spires of Arak): leads to Phoenix Wishwing, a pet you don't have,
-- through "Tale of the Phoenix" (not done)"; every other cost the data
-- lists is named ("for 50 plus 1 Apexis Crystal and 25 gold", item 9), and
-- a trade with no vendor named says where it is ("in Blade's Edge
-- Mountains")
local function BuyRowLine(row, label, name, links)
  local data = Data()
  local okCost, cost = pcall(Recollect.UI.UsedFor.CostWords, row.relation, row.of)
  cost = okCost and type(cost) == "string" and cost or ""
  if cost == "" and row.plus then cost = " plus other costs" end
  local text = ("%s: %s for %d%s"):format(label, name, row.count or 1, cost)
  CostLinks(row, links)
  local seller = data.Where(row)
  if seller then
    text = seller:find("^In ") and ("%s, %s"):format(text, Lowered(seller)) or ("%s, at %s"):format(text, seller)
  end
  local cut = #text
  local leads, heard = data.Heard(data.LeadsTo, row)
  if leads then
    text = ("%s: leads to %s"):format(text, leads)
    HeardLinks(heard, links)
  elseif row.stateText then
    text = ("%s (%s)"):format(text, RowState(row))
  end
  return { text = text, color = row.stateColor or U.Colors.LIGHT_GRAY, place = data.Place(row), links = links, cut = cut }
end

local PURCHASE = { buys = true, journal = true, buysDecor = true }

local function RowLine(row, withPlace)
  local data = Data()
  local label = row.kindLabel or ""
  if row.kind == "craftedBy" and data.Profession(row) then label = "Crafted by " .. data.Profession(row) end
  -- An item still loading reads "item 239198", never "To craft: To craft 239198";
  -- a creature or spot named by its place names it once
  local own, byPlace = data.Name(row)
  local name = own or (row.itemID and ("item " .. tostring(row.itemID))) or data.DisplayName(row)
  local links = RowLink(row, not byPlace and own or nil)
  -- a purchase (the data's, the journals', the housing catalog's) says what it
  -- costs and where; an achievement it counts toward reads as the others do
  if withPlace and PURCHASE[row.kind] and row.what ~= "achievement" then return BuyRowLine(row, label, name, links) end
  local text = ("%s: %s"):format(label, name)
  -- the sources of data format 4 read as the panel's lines do
  if row.kind == "renownReward" then
    text = ("Renown %d with %s"):format(row.level or 0, name)
  elseif row.kind == "blackMarket" then
    text = Recollect.UI.UsedFor.parts.BLACK_MARKET_TEXT
  elseif row.kind == "tradingPost" then
    text = Recollect.UI.UsedFor.parts.TradingPostText(row.month)
  end
  local place = withPlace and data.Place(row) or nil
  if place then
    if not byPlace then text = ("%s (%s)"):format(text, place.zone or ("map " .. place.mapID)) end
  elseif withPlace and row.kind == "endeavor" then
    text = ("%s, %s"):format(text, Lowered(data.Where(row)))
  elseif withPlace and row.npcID then
    local boss = Recollect.Facts.Vendors.Boss(row.npcID)
    if boss and boss.instance then text = ("%s (%s)"):format(text, boss.instance) end
  elseif withPlace and row.what == "encounter" then
    local instance = data.Where(row)   -- the boss's dungeon or raid
    if instance then text = ("%s (%s)"):format(text, instance) end
  end
  local cut = #text
  if row.stateText then text = ("%s (%s)"):format(text, RowState(row)) end
  -- a quest says what it rewards, with each reward's state
  if withPlace then
    local rewards, heard = data.Heard(data.Rewards, row)
    if rewards then
      text = ("%s: rewards %s"):format(text, rewards)
      HeardLinks(heard, links)
    end
  end
  return { text = text, color = row.stateColor or U.Colors.LIGHT_GRAY, place = place, links = links, cut = cut }
end

-- A reagent (Cobanyte, 2026-09-24): which professions use it and in how
-- many recipes, then a few of them, the ones you know first: "A crafting
-- reagent in 42 recipes: 30 Leatherworking, 12 Blacksmithing". A recipe
-- that makes a collectible says its state as the game counts it (item 6):
-- "Protoform Synthesis: Archetype of Discovery, takes 1, recipe can't be
-- read for Protoform Synthesis (pet: 1 of 3 collected)"
local MAX_RECIPES = 3
local function RecipeLine(row)
  local data = Data()
  local name = data.DisplayName(row)
  local links = RowLink(row, (data.Name(row)))   -- the name alone: its second return is not a list (review F13)
  local text = ("%s: %s, takes %d"):format(data.Profession(row) or "Recipe", name, row.count or 1)
  local cut = #text
  local product = data.ProductText(row)
  if product and row.productThing then
    if row.stateText then text = ("%s, recipe %s"):format(text, RowState(row)) end
    return { text = ("%s (%s)"):format(text, Lowered(product)), color = row.productColor or U.Colors.LIGHT_GRAY, links = links,
      cut = cut }
  end
  if row.stateText then text = ("%s (%s)"):format(text, RowState(row)) end
  return { text = text, color = row.stateColor or U.Colors.LIGHT_GRAY, links = links, cut = cut }
end

-- The recipe index's rows ("Your recipes", one per profession): how many
-- this character knows in all, and the words the panel uses for them ("8
-- Blacksmithing, 9 Leatherworking")
local function YourRecipes(rows)
  local names, byName, known = {}, {}, 0
  for _, row in ipairs(rows) do
    if row.kind == "index" and type(row.count) == "number" and row.count > 0 then
      local name = tostring(row.name)
      if not byName[name] then names[#names + 1] = name end
      byName[name] = (byName[name] or 0) + row.count
      known = known + row.count
    end
  end
  table.sort(names)
  local parts = {}
  for _, name in ipairs(names) do parts[#parts + 1] = ("%d %s"):format(byName[name], name) end
  return known, table.concat(parts, ", ")
end

-- The reagent's summary (item 11): the same count the headline names ("A
-- crafting reagent in 11 recipes", the data's recipes, Purposes.Reagent),
-- by profession, most first, the ones whose name can't be read counted as
-- "other" (as the check counts them), with "; you know 2 of them" from the
-- recipe index when that count fits in it; a count above it, or recipes
-- known that the data doesn't list, read as the panel's own line ("Used in
-- 21 of your recipes (21 Blacksmithing)"). The index's rows stay on the
-- Crafting tab and never add a count of their own here.
local function ReagentLines(rows)
  local data = Data()
  local count, order, total, known, other, making, unnamed = {}, {}, 0, {}, {}, 0, 0
  for _, row in ipairs(rows) do
    if row.kind == "reagentOf" then
      total = total + 1
      local profession = data.ProfessionGroup(row)
      if not profession then
        unnamed = unnamed + 1
      else
        if not count[profession] then
          count[profession] = 0
          order[#order + 1] = profession
        end
        count[profession] = count[profession] + 1
      end
      if row.productThing and row.filterState == "missing" then making = making + 1 end
      local list = row.state == "have" and known or other
      list[#list + 1] = row
    end
  end
  local yours, yourWords = YourRecipes(rows)
  local lines = {}
  if total > 0 then
    table.sort(order, function(a, b)
      if count[a] ~= count[b] then return count[a] > count[b] end
      return a < b
    end)
    local parts = {}
    for _, profession in ipairs(order) do parts[#parts + 1] = ("%d %s"):format(count[profession], profession) end
    if unnamed > 0 and #parts > 0 then parts[#parts + 1] = ("%d other"):format(unnamed) end
    local head = ("A crafting reagent in %d %s"):format(total, total == 1 and "recipe" or "recipes")
    if #parts > 0 then head = ("%s: %s"):format(head, table.concat(parts, ", ")) end
    if yours > 0 and yours <= total then head = ("%s; you know %d of them"):format(head, yours) end
    if making > 0 then head = ("%s; %d %s something you don't have yet"):format(head, making, making == 1 and "makes" or "make") end
    lines[1] = Group(head)
  end
  if yours > 0 and (total == 0 or yours > total) then
    -- a group of its own when no recipe count heads the lines
    local text = ("Used in %d of your %s (%s)"):format(yours, yours == 1 and "recipe" or "recipes", yourWords)
    lines[#lines + 1] = total == 0 and Group(text) or Plain(text)
  end
  if total == 0 then return lines end
  -- the recipes you know, then the rest, what they make still to get first
  local ordered = known
  for _, row in ipairs(Fold.Ordered(other)) do ordered[#ordered + 1] = row end
  local named, nextIndex = Fold.Take(ordered, 1, MAX_RECIPES, RecipeLine)
  for _, line in ipairs(named) do lines[#lines + 1] = line end
  Fold.Container(lines, "for:reagent", ordered, nextIndex, "crafting", RecipeLine)
  return lines
end

-- Every use gone (item 7): what the No longer available tab held, counted as
-- the panel counts it (UI.UsedFor's closing line: one thing bought at
-- several vendors, or one quest by several codes, counts once)
local Gone = {
  PHRASES = {
    buys = { "bought %d thing", "bought %d things" },
    quests = { "was used in %d quest", "was used in %d quests" },
    opens = { "opened %d treasure", "opened %d treasures" },
    usedAt = { "was used at %d NPC", "was used at %d NPCs" },
    achievements = { "counted toward %d achievement", "counted toward %d achievements" },
    reagent = { "was a reagent in %d recipe", "was a reagent in %d recipes" },
    other = { "had %d other use", "had %d other uses" },
  },
  ORDER = { "buys", "quests", "opens", "usedAt", "achievements", "reagent", "other" },
  GROUP = { objective = "quests", questItem = "quests", starts = "quests", opens = "opens", usedAt = "usedAt",
    criterion = "achievements", linked = "achievements", reagentOf = "reagent", buysDecor = "buys", buys = "buys" },
  SHOWN = 3,   -- removed uses named under the summary
}

function Gone.Group(relation)
  local kind = relation.kind
  if kind == "buys" and relation.thing == "a" then return "achievements", nil end
  local group = Gone.GROUP[kind] or "other"
  if kind == "buys" then return group, "b" .. tostring(relation.thing) .. ":" .. tostring(relation.id) end
  if kind == "buysDecor" then return group, "d:" .. tostring(relation.id) end
  if group == "quests" then return group, "q:" .. tostring(relation.id) end
  return group, nil
end

-- The removed uses' words ("bought 55 things and was used in 1 quest") and
-- the rows they came from, or nil; and how many ways to get it are gone
function Gone.Read(rows)
  local SOURCE = Recollect.Facts.Relations.SOURCE or {}
  local counts, seen, uses, sources = {}, {}, {}, 0
  for _, row in ipairs(rows or {}) do
    local relation = row.relation
    if relation and SOURCE[relation.kind] then
      sources = sources + 1
    elseif relation then
      uses[#uses + 1] = row
      local group, key = Gone.Group(relation)
      if not key or not seen[key] then
        if key then seen[key] = true end
        counts[group] = (counts[group] or 0) + 1
      end
    end
  end
  if #uses == 0 then return nil, uses, sources end
  local parts = {}
  for _, group in ipairs(Gone.ORDER) do
    local n = counts[group]
    if n then parts[#parts + 1] = (n == 1 and Gone.PHRASES[group][1] or Gone.PHRASES[group][2]):format(n) end
  end
  local words = #parts > 1 and (table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]) or parts[1]
  return words, uses, sources
end

function Gone.RowLine(row) return RowLine(row, false) end

-- The summary lines: the panel's words, then a few of the removed uses and
-- the rest in a container
function Gone.Lines(j, every)
  local words, uses = Gone.Read(j.tabs.gone)
  if not words then return {} end
  local lead = every and "Every use Recollect knows is gone from the game: it " or "Also no longer in the game: it "
  local colors, V = Recollect.UI.VerdictColors, Recollect.Purposes.Registry.Verdict
  -- a group's title when the removed uses are listed under it; else one line
  -- of its own (it still ends the group above, so it isn't indented under it)
  local lines = { { text = lead .. words, color = colors[V.OUTDATED] or U.Colors.LABEL_GRAY, plain = true, group = every,
    ungroup = not every } }
  if every then
    local named, nextIndex = Fold.Take(uses, 1, Gone.SHOWN, Gone.RowLine)
    for _, line in ipairs(named) do lines[#lines + 1] = line end
    Fold.Container(lines, "gone", uses, nextIndex, "gone", Gone.RowLine)
  end
  return lines
end

-- The item's own tooltip facts, read once per model and kept (model.detailTip);
-- nil while they can't be read yet: asked once a paint (TipPaint, which
-- Detail.Content moves on), however many parts of the paint ask
local TipPaint = { n = 0 }
local function ItemTip(model, itemID)
  if type(model) == "table" and model.detailTip then return model.detailTip end
  if type(model) == "table" then
    if model.detailTipAsked == TipPaint.n then return nil end
    model.detailTipAsked = TipPaint.n
  end
  local ok, tip = pcall(seams.ItemTooltip, itemID)
  if not ok or type(tip) ~= "table" then return nil end
  if type(model) == "table" then model.detailTip = tip end
  return tip
end

-- WHAT IT'S FOR (Cobanyte, 2026-09-28: it explains the item, spelled out,
-- and never lists what crafting the item takes, which is HOW TO GET MORE's):
-- per group (what it buys, quests and places, crafting with it, what a use
-- takes) how many uses it holds and how many are still open, then its rows
-- named (Fold: still to get or do first, never a count alone), then the rest
-- in a container; a reagent's recipes as ReagentLines words them; and what
-- the uses no longer in the game were. Achievements are a section of their
-- own (AchievementLines).
local FOR = {}

-- What crafting the item takes: how to make it, not a use of it
function FOR.IsCraft(row) return row.record ~= nil and row.record.kind == "craft" end
function FOR.IsAchievement(row) return row.what == "achievement" end

-- The rows a group's count names: a reagent's recipes and the recipe index
-- have ReagentLines' words
function FOR.Counted(row) return row.kind ~= "reagentOf" and row.kind ~= "index" end
function FOR.RowLine(row) return RowLine(row, true) end

FOR.GROUPS = {
  { key = "buys", tab = "buys", label = "Buys" },
  { key = "quests", tab = "quests", label = "Quests and places", keep = function(row) return not FOR.IsAchievement(row) end },
  { key = "crafting", tab = "crafting", label = "Crafting with it" },
  { key = "takes", tab = "takes", label = "What using it takes", keep = function(row) return not FOR.IsCraft(row) end },
}

-- A group's rows, as its filter keeps them
function FOR.Rows(j, group)
  local rows = {}
  for _, row in ipairs(j.tabs[group.tab] or {}) do
    if not group.keep or group.keep(row) then rows[#rows + 1] = row end
  end
  return rows
end

-- One group: its title with its counts, its rows named, the rest folded
function FOR.Group(lines, rows, key, tab, label)
  local n, missing = 0, 0
  for _, row in ipairs(rows) do
    if FOR.Counted(row) then
      n = n + 1
      if row.filterState == "missing" then missing = missing + 1 end
    end
  end
  if n == 0 then return nil end
  lines[#lines + 1] = Group(("%s: %d%s"):format(label, n, missing > 0 and ("; %d still to get or do"):format(missing) or ""))
  local ordered = Fold.Ordered(rows, FOR.Counted, Fold.Need(key, MAX_SUMMARY))
  local named, nextIndex = Fold.Take(ordered, 1, MAX_SUMMARY, FOR.RowLine)
  for _, line in ipairs(named) do lines[#lines + 1] = line end
  Fold.Container(lines, key, ordered, nextIndex, tab, FOR.RowLine, n)
  return ("%s: %d%s"):format(label, n, missing > 0 and (" (%d still to get or do)"):format(missing) or "")
end

-- The uses a new player asks about first, spelled out when there are few
-- (Cobanyte, 2026-09-28: "say what treasure it opens and what item we get
-- out of it"): each treasure or spot it opens, where, what it holds and
-- whether you've looted it; each NPC it is used at, and where; and what a
-- use takes together with it. Returns the sentences and which kinds they
-- covered, so UseWords doesn't count those again.
FOR.SPELLED = 2
function FOR.Specific(j)
  local sentences, handled = {}, {}
  local objects, npcs, parts = {}, {}, {}
  for _, row in ipairs(j.tabs.quests or {}) do
    if not row.restricted then
      if row.what == "object" then objects[#objects + 1] = row
      elseif row.kind == "usedAt" then npcs[#npcs + 1] = row end
    end
  end
  local function State(row)
    return type(row.stateText) == "string" and row.stateText ~= "" and (" (%s)"):format(Lowered(row.stateText)) or ""
  end
  if #objects > 0 and #objects <= FOR.SPELLED then
    handled.object = true
    local Opens = Recollect.Purposes.Opens
    for _, row in ipairs(objects) do
      local object = Recollect.Facts.Vendors.Object(row.objectID)
      local holds = object and Opens and Opens.Holds(object) or ""
      sentences[#sentences + 1] = ("It opens %s%s%s."):format(Lowered(Data().DisplayName(row)), holds, State(row))
    end
  end
  if #npcs > 0 and #npcs <= FOR.SPELLED then
    handled.npc = true
    for _, row in ipairs(npcs) do
      local place = Data().Place(row)
      local name = Data().DisplayName(row)
      sentences[#sentences + 1] = (place and place.zone and not name:find(place.zone, 1, true))
        and ("It is used at %s in %s."):format(name, place.zone) or ("It is used at %s."):format(name)
    end
  end
  -- what a use takes, one sentence per use (its record: a known use, a
  -- combine), never parts of two uses joined; "you have them all" only when
  -- every part was counted as held
  local records, order = {}, {}
  for _, row in ipairs(j.tabs.takes or {}) do
    if not FOR.IsCraft(row) and row.record then
      if not records[row.record] then
        records[row.record] = {}
        order[#order + 1] = row.record
      end
      local list = records[row.record]
      list[#list + 1] = row
    end
  end
  if #order > 0 and #order <= FOR.SPELLED then
    handled.takes = true
    for _, record in ipairs(order) do
      parts = records[record]
      if #parts > 1 then
        local names, missing, have = {}, 0, 0
        for i, row in ipairs(parts) do
          names[i] = Data().DisplayName(row)
          if row.filterState == "missing" then missing = missing + 1
          elseif row.filterState == "have" then have = have + 1 end
        end
        local unread = #parts - missing - have
        local state
        if have == #parts then state = " (you have them all)"
        elseif missing > 0 then state = (" (%d still to get)"):format(missing)
        else state = (" (%d can't be counted)"):format(unread) end
        local list = table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
        local verb = record.kind == "combine" and "Combining it takes" or "Using it takes"
        sentences[#sentences + 1] = ("%s %d items together: %s%s."):format(verb, #parts, list, state)
      end
    end
  end
  return sentences, handled
end

-- "is used in 3 quests, counts toward 1 achievement and buys 12 things": the
-- item's uses counted in words, for the explanation (without the kinds
-- FOR.Specific spelled out); nil when it has none
function FOR.UseWords(j, handled)
  handled = handled or {}
  local counts = { quest = 0, place = 0, achievement = 0, linked = 0, buys = 0, reagent = 0, makes = 0, endeavor = 0,
    currency = 0 }
  for _, row in ipairs(j.tabs.buys or {}) do if FOR.Counted(row) then counts.buys = counts.buys + 1 end end
  for _, row in ipairs(j.tabs.quests or {}) do
    if row.kind == "linked" then counts.linked = counts.linked + 1
    elseif row.what == "achievement" then counts.achievement = counts.achievement + 1
    elseif row.what == "quest" then counts.quest = counts.quest + 1
    elseif row.what == "endeavor" then counts.endeavor = counts.endeavor + 1
    elseif row.what == "currency" then counts.currency = counts.currency + 1
    elseif (row.what == "object" and handled.object) or (row.kind == "usedAt" and handled.npc) then   -- spelled out
    else counts.place = counts.place + 1 end
  end
  for _, row in ipairs(j.tabs.crafting or {}) do
    if row.kind == "reagentOf" then counts.reagent = counts.reagent + 1
    elseif row.kind == "makes" or row.kind == "partOf" or row.kind == "recipeFor" or row.kind == "teaches" then
      counts.makes = counts.makes + 1
    end
  end
  local function N(n, one, many) return ("%d %s"):format(n, n == 1 and one or many) end
  local parts = {}
  if counts.quest > 0 then parts[#parts + 1] = "is used in " .. N(counts.quest, "quest", "quests") end
  if counts.achievement > 0 then parts[#parts + 1] = "counts toward " .. N(counts.achievement, "achievement", "achievements") end
  if counts.linked > 0 then parts[#parts + 1] = "is linked to " .. N(counts.linked, "achievement", "achievements") end
  if counts.place > 0 then parts[#parts + 1] = "is used at " .. N(counts.place, "place", "places") end
  if counts.endeavor > 0 then parts[#parts + 1] = "is named by " .. N(counts.endeavor, "neighborhood endeavor task", "neighborhood endeavor tasks") end
  if counts.buys > 0 then parts[#parts + 1] = "buys " .. N(counts.buys, "thing", "things") .. FOR.BuyKinds(j) end
  if counts.reagent > 0 then parts[#parts + 1] = "is a reagent in " .. N(counts.reagent, "recipe", "recipes") end
  if counts.makes > 0 then parts[#parts + 1] = "makes or teaches " .. N(counts.makes, "thing", "things") end
  if counts.currency > 0 then parts[#parts + 1] = "is worth a currency" end
  if #parts == 0 then return nil end
  if #parts == 1 then return parts[1] end
  return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

-- What its purchases are, by kind: ": 4 decor, 2 pets, 1 toy and 126 other
-- items"; "" when they are all plain items
FOR.BUY_WORDS = { decor = { "decor", "decor" }, toy = { "toy", "toys" }, mount = { "mount", "mounts" },
  pet = { "pet", "pets" }, ensemble = { "appearance set", "appearance sets" }, heirloom = { "heirloom", "heirlooms" },
  recipe = { "recipe", "recipes" }, illusion = { "weapon illusion", "weapon illusions" },
  achievement = { "achievement", "achievements" } }
FOR.BUY_ORDER = { "mount", "pet", "toy", "decor", "ensemble", "heirloom", "illusion", "recipe", "achievement" }
function FOR.BuyKinds(j)
  local counts, other = {}, 0
  for _, row in ipairs(j.tabs.buys or {}) do
    if FOR.Counted(row) then
      if FOR.BUY_WORDS[row.what] then counts[row.what] = (counts[row.what] or 0) + 1 else other = other + 1 end
    end
  end
  local parts = {}
  if next(counts) == nil then
    -- only plain items: a few are named ("Illegal Cosmic Emitter, ...")
    if other == 0 or other > 3 then return "" end
    local names = {}
    for _, row in ipairs(j.tabs.buys or {}) do
      if FOR.Counted(row) then names[#names + 1] = Data().DisplayName(row) end
    end
    if #names == 1 then return " (" .. names[1] .. ")" end
    return " (" .. table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names] .. ")"
  end
  for _, what in ipairs(FOR.BUY_ORDER) do
    local n = counts[what]
    if n then parts[#parts + 1] = ("%d %s"):format(n, n == 1 and FOR.BUY_WORDS[what][1] or FOR.BUY_WORDS[what][2]) end
  end
  if #parts == 0 then return "" end
  if other > 0 then parts[#parts + 1] = ("%d other %s"):format(other, other == 1 and "item" or "items") end
  if #parts == 1 then return " (" .. parts[1] .. ")" end
  return " (" .. table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts] .. ")"
end

-- A "quest item" that buys things and no quest uses is a token you spend
-- (the Brewfest Prize Token): the game's class says quest item
function FOR.IsToken(j)
  if not j then return false end
  local buys = 0
  for _, row in ipairs(j.tabs.buys or {}) do if FOR.Counted(row) then buys = buys + 1 end end
  if buys == 0 then return false end
  for _, row in ipairs(j.tabs.quests or {}) do
    if row.what == "quest" and (row.kind == "objective" or row.kind == "questItem" or row.kind == "starts") then return false end
  end
  return true
end

-- The professions whose recipes craft it ("Jewelcrafting"), or nil
function FOR.CraftedBy(j)
  local seen, names = {}, {}
  for _, row in ipairs(j and j.tabs.sources or {}) do
    if row.kind == "craftedBy" and not row.restricted and not row.gone then
      local profession = Data().Profession(row)
      if profession and not seen[profession] then
        seen[profession] = true
        names[#names + 1] = profession
      end
    end
  end
  if #names == 0 then return nil end
  if #names == 1 then return names[1] end
  return table.concat(names, ", ", 1, #names - 1) .. " or " .. names[#names]
end

-- The explanation that opens WHAT IT'S FOR, spelled out for a new player:
-- what the item is and where it's from, how it's made, and what it's used
-- for, counted; then the game's own filing of it (model.about) in gray
function FOR.Explain(model, j, itemID)
  local lines = {}
  -- (collects: it teaches a collectible, which is its use)
  local okD, what, collects = pcall(Detail.Describe, itemID, model, true)
  what, collects = okD and what or nil, okD and collects or false
  if what == "A quest item" and FOR.IsToken(j) then what, collects = "A token you spend at vendors", true end
  local facts = Recollect.Utilities.IsPositiveID(itemID) and Recollect.Facts.Item.Get(itemID) or nil
  local from
  if type(facts) == "table" then
    local okE, expansion = pcall(Recollect.Facts.Item.Expansion, facts, itemID)
    if okE and type(expansion) == "number" then
      local okN, name = pcall(Recollect.Purposes.Registry.ExpansionName, expansion)
      from = okN and name or nil
    end
  end
  local sentences = {}
  if what then
    sentences[#sentences + 1] = from and ("%s, from %s."):format(what, from) or (what .. ".")
  elseif from then
    sentences[#sentences + 1] = ("An item from %s."):format(from)
  end
  local pvp = Detail.PvpLevel(itemID, model)
  if pvp then
    sentences[#sentences + 1] = ("It's PvP gear: in Arenas and Battlegrounds it counts as item level %d."):format(pvp)
  end
  -- what the item does, in our own words, where its tooltip leaves a new
  -- player guessing (Data/Descriptions.lua, written from the game's own text)
  local described = Recollect.Data.Descriptions and Recollect.Data.Descriptions[itemID]
  if type(described) == "string" and described ~= "" then
    sentences[#sentences + 1] = described
    collects = true   -- it says what the item is for
  end
  local crafted = FOR.CraftedBy(j)
  if crafted then sentences[#sentences + 1] = ("Crafted with %s."):format(crafted) end
  if j then
    local specific, handled = FOR.Specific(j)
    local uses = FOR.UseWords(j, handled)
    for _, sentence in ipairs(specific) do sentences[#sentences + 1] = sentence end
    if uses then
      sentences[#sentences + 1] = ("%s %s."):format(#specific > 0 and "It also" or "It", uses)
    elseif #specific == 0 and not collects and j.finished and #(j.tabs.gone or {}) == 0 then
      -- (when every use is gone, the section's closing line says what they
      -- were; a guide note says what the data can't)
      local okN, notes = pcall(Recollect.Facts.Notes.For, itemID)
      if okN and type(notes) == "table" and #notes > 0 then
        sentences[#sentences + 1] = "What it's for comes from a guide note below, not confirmed in game yet."
      else
        sentences[#sentences + 1] = "Recollect knows no use for it yet."
      end
    end
  end
  if #sentences > 0 then
    local line = Plain(table.concat(sentences, " "), U.Colors.HIGHLIGHT_WHITE)
    line.explain, line.lead = true, true
    lines[#lines + 1] = line
  end
  -- the item's own Use line, quoted, so it needn't be hovered (Cobanyte,
  -- 2026-09-28: the details window may quote the tooltip; the audit panel
  -- still never does)
  local tip = Recollect.Utilities.IsPositiveID(itemID) and ItemTip(model, itemID) or nil
  if tip and type(tip.useText) == "string" and tip.useText ~= "" then
    lines[#lines + 1] = { text = ("\"%s\""):format(tip.useText), sub = true, textColor = U.Colors.LIGHT_GRAY, lead = true,
      quote = true }
  end
  -- the game's own filing of it only when it says more than the sentence:
  -- a patch the game files under an older expansion (rule 45)
  for _, text in ipairs(type(model.about) == "table" and model.about or {}) do
    if tostring(text):find("added in patch", 1, true) then
      lines[#lines + 1] = { text = text, sub = true, textColor = U.Colors.LABEL_GRAY, lead = true }
    end
  end
  return lines
end

-- WHAT IT'S FOR's tiles: a tile per kind of use, the count large and, on
-- the label line, what is still open in that kind's own words (Cobanyte,
-- 2026-09-28: "1 · 1 open" and "80 · 79 open" said nothing), with a tooltip
-- that breaks the count down; only when there are two kinds or more, else
-- the group's title says it. Words: { one open of one, all open, some open,
-- all done }; "open" is a row still to get or do (filterState "missing"),
-- which for a recipe means it makes something you don't have yet.
FOR.TILES = {
  { key = "buys", label = "Buys", icon = "Interface\\Icons\\INV_Misc_Coin_01", title = "What it buys",
    words = { "not owned yet", "none owned yet", "%d not owned yet", "all owned" },
    open = "Not owned yet", done = "Owned",
    note = "Collectibles and items it can be traded for; those you don't have yet come first in the list." },
  { key = "quests", label = "Quests, places", icon = "Interface\\Icons\\INV_Misc_Note_01", title = "Quests and places",
    words = { "not done yet", "none done yet", "%d not done", "all done" }, open = "Not done yet", done = "Done",
    note = "Quests that use it and places or NPCs it's used at." },
  { key = "achievements", label = "Achievements", icon = "Interface\\Icons\\Achievement_General", title = "Achievements",
    words = { "not earned yet", "none earned yet", "%d not earned", "all earned" }, open = "Not earned yet", done = "Earned",
    note = "Achievements it counts toward." },
  { key = "crafting", label = "Crafting", icon = "Interface\\Icons\\Trade_Engineering", title = "Crafting with it",
    words = { "makes something you lack", "all make things you lack", "%d make things you lack", "you have all they make" },
    open = "Make something you don't have", done = "Make what you already have",
    note = "Recipes that use it. A recipe counts as open when what it makes is something you don't have yet." },
  { key = "takes", label = "A use takes", icon = "Interface\\Icons\\INV_Misc_Bag_10", title = "What using it takes",
    words = { "still needed", "all still needed", "%d still needed", "all ready" }, open = "Still needed", done = "Ready",
    note = "The other parts a use of it needs." },
}

-- The label line's words for a tile: its kind's words for how much is open
function FOR.TileWords(def, n, open, have)
  local w = def.words
  if open > 0 and open == n then return n == 1 and w[1] or w[2] end
  if open > 0 then return w[3]:format(open) end
  if have == n then return w[4] end
  return nil   -- nothing open, but not every one read as done: no words
end
function FOR.Tiles(j)
  local counts = {}
  local function Count(key, row)
    local c = counts[key] or { n = 0, open = 0, have = 0 }
    counts[key] = c
    c.n = c.n + 1
    if row.filterState == "missing" then c.open = c.open + 1 end
    if row.filterState == "have" then c.have = c.have + 1 end
  end
  for _, group in ipairs(FOR.GROUPS) do
    for _, row in ipairs(FOR.Rows(j, group)) do
      if group.key ~= "crafting" or FOR.Counted(row) or row.kind == "reagentOf" then Count(group.key, row) end
    end
  end
  for _, row in ipairs(j.tabs.quests or {}) do
    if FOR.IsAchievement(row) then Count("achievements", row) end
  end
  local tiles = {}
  for _, def in ipairs(FOR.TILES) do
    local c = counts[def.key]
    if c and c.n > 0 then
      local words = FOR.TileWords(def, c.n, c.open, c.have)
      local lines = { { "In all", tostring(c.n) } }
      if c.open > 0 then lines[#lines + 1] = { def.open, tostring(c.open) } end
      if c.have > 0 then lines[#lines + 1] = { def.done, tostring(c.have) } end
      local rest = c.n - c.open - c.have
      if rest > 0 then lines[#lines + 1] = { "No state to show, or not read yet", tostring(rest) } end
      tiles[#tiles + 1] = { label = words and (def.label .. ": " .. words) or def.label, icon = def.icon, count = c.n,
        tip = { title = def.title, lines = lines, note = def.note } }
    end
  end
  local total = 0
  for _, tile in ipairs(tiles) do total = total + tile.count end
  -- only where they add something: two kinds or more, and enough entries
  -- that the lines below don't already say it at a glance (Cobanyte,
  -- 2026-09-28: "getting a lil jumbled")
  return #tiles >= 2 and total >= LAYOUT.TILES_MIN and tiles or nil
end

local function ForLines(j)
  local lines, live = {}, 0
  lines.tallies = {}   -- each group's count, for the section's summary
  local tiles = FOR.Tiles(j)
  if tiles then lines.tiles = { text = "", tiles = tiles, lead = true } end   -- painted with the section's lead
  for _, key in ipairs({ "buys", "quests", "crafting", "takes" }) do
    for _, row in ipairs(j.tabs[key] or {}) do
      -- what crafting the item takes is how to make it, not a use of it (the
      -- panel's USED FOR has no line for it either)
      if not FOR.IsCraft(row) then live = live + 1 end
    end
  end
  for _, group in ipairs(FOR.GROUPS) do
    local rows = FOR.Rows(j, group)
    if group.key == "crafting" then
      for _, line in ipairs(ReagentLines(rows)) do lines[#lines + 1] = line end
    end
    local tally = FOR.Group(lines, rows, "for:" .. group.key, group.tab, group.label)
    if tally then lines.tallies[#lines.tallies + 1] = tally end
  end
  -- "every use is gone" is decided from the relations too (UI.UsedFor.LiveUse):
  -- a row that couldn't be built is still a use
  local every = live == 0 and not Recollect.UI.UsedFor.LiveUse(j.itemID, j.relations, j.owner, j.questApplies)
  for _, line in ipairs(Gone.Lines(j, every)) do lines[#lines + 1] = line end
  return lines
end

-- ACHIEVEMENTS (Cobanyte, 2026-09-28: a section of its own): each
-- achievement the item counts toward or is linked to, still to do first,
-- then the meta achievements those are part of (Facts.Relations.MetasOf,
-- when the data has them), each once, with its progress
local function MetaIDs(rows)
  local MetasOf = Recollect.Facts.Relations.MetasOf
  local ids, seen = {}, {}
  if type(MetasOf) ~= "function" then return ids end
  for _, row in ipairs(rows) do
    local ok, metas = pcall(MetasOf, row.achievementID)
    for _, metaID in ipairs(ok and type(metas) == "table" and metas or {}) do
      if not seen[metaID] then
        seen[metaID] = true
        ids[#ids + 1] = metaID
      end
    end
  end
  return ids
end

local function MetaLine(metaID)
  local okP, progress = pcall(Recollect.Facts.Achievements.Progress, metaID)
  progress = okP and progress or nil
  local name = progress and progress.name
  if type(name) ~= "string" or name == "" then return nil end
  local okW, words = pcall(Recollect.Facts.Achievements.ProgressWords, progress)
  local bar = type(progress.done) == "number" and type(progress.total) == "number" and progress.total > 1
    and { done = progress.done, total = progress.total } or nil
  return { text = ("%s (%s)"):format(name, okW and words or "can't be read"), color = U.Colors.LIGHT_GRAY, bar = bar,
    links = HeardLinks({ { kind = "achievement", id = metaID, text = name } }) }
end

local function AchievementLines(j)
  local lines = {}
  if not j then return lines end
  local rows = {}
  for _, row in ipairs(j.tabs.quests or {}) do
    if FOR.IsAchievement(row) then rows[#rows + 1] = row end
  end
  if #rows == 0 then return lines end
  local missing = 0
  for _, row in ipairs(rows) do if row.filterState == "missing" then missing = missing + 1 end end
  -- no title over them: the section's summary counts them already
  local ordered = Fold.Ordered(rows, nil, Fold.Need("ach", MAX_SUMMARY))
  local function WithBar(row)
    local line = FOR.RowLine(row)
    if type(line) == "table" then line.bar = row.bar end
    return line
  end
  local named, nextIndex = Fold.Take(ordered, 1, MAX_SUMMARY, WithBar)
  for _, line in ipairs(named) do lines[#lines + 1] = line end
  Fold.Container(lines, "ach", ordered, nextIndex, "quests", WithBar, #rows)
  local metas = {}
  for _, metaID in ipairs(MetaIDs(rows)) do
    local line = MetaLine(metaID)
    if line then metas[#metas + 1] = line end
  end
  if #metas > 0 then
    lines[#lines + 1] = Group(("Part of %d meta %s"):format(#metas, #metas == 1 and "achievement" or "achievements"))
    for _, line in ipairs(metas) do lines[#lines + 1] = line end
  end
  lines.summary = ("%d %s%s%s"):format(#rows, #rows == 1 and "achievement" or "achievements",
    missing > 0 and (" (%d still to do)"):format(missing) or "",
    #metas > 0 and ("; part of %d meta %s"):format(#metas, #metas == 1 and "achievement" or "achievements") or "")
  return lines
end

-- An older system the item belongs to (Purposes.Legacy.System, item 5), as
-- the panel's USED FOR line says it: what the system was, then whether it
-- still does anything, with its page
local function LegacyLines(model)
  local lines = {}
  for _, line in ipairs(type(model.usedFor) == "table" and model.usedFor or {}) do
    if line.legacy then
      lines[#lines + 1] = { text = tostring(line.text), color = line.color or U.Colors.LIGHT_GRAY }
      if type(line.detail) == "string" then
        lines[#lines + 1] = { text = line.detail, sub = true, textColor = U.Colors.LABEL_GRAY }
      end
    end
  end
  return lines
end

-- The item's season tag as COMES FROM opens with it (UI.Tooltip.SeasonLine):
-- the model's, else read once from the item's own tooltip (a model built
-- from an item ID alone has none), kept on the model; nil
local function SeasonLine(model, itemID)
  if model.seasonLine then return model.seasonLine end
  if not Recollect.Utilities.IsPositiveID(itemID) then return nil end
  if model.detailSeason ~= nil then return model.detailSeason or nil end
  local tip = ItemTip(model, itemID)
  if not tip then return nil end   -- not read yet: asked again on the next paint
  local okLine, line = pcall(Recollect.UI.Tooltip.SeasonLine, tip)
  model.detailSeason = okLine and type(line) == "table" and line or false
  return model.detailSeason or nil
end

-- "Can no longer be obtained (removed in patch 12.1.0)" (Purposes.Season:
-- AllTheThings' patch, once this client is at or past it), or nil
local function RemovedLine(itemID)
  local Season = Recollect.Purposes.Season
  if not Season or not Recollect.Utilities.IsPositiveID(itemID) then return nil end
  local ok, patch = pcall(Season.RemovedIn, itemID)
  if not ok or not patch then return nil end
  local colors, V = Recollect.UI.VerdictColors, Recollect.Purposes.Registry.Verdict
  return { text = ("Can no longer be obtained (removed in patch %s)"):format(Season.PatchText(patch)),
    color = colors[V.OUTDATED] or U.Colors.LABEL_GRAY }
end

-- HOW TO GET MORE's one-line summary: how many ways, by kind, most first
-- ("22 ways to get it: Reward 20, Sold by 2"), and how many are gone
local SUMMARY_KINDS = 3
local function GetSummary(rows, removed, goneSources)
  local counts, order = {}, {}
  for _, row in ipairs(rows) do
    local kind = row.kindLabel or "Other"
    if not counts[kind] then order[#order + 1] = kind end
    counts[kind] = (counts[kind] or 0) + 1
  end
  table.sort(order, function(a, b)
    if counts[a] ~= counts[b] then return counts[a] > counts[b] end
    return (SOURCE_ORDER[a] or 20) < (SOURCE_ORDER[b] or 20)
  end)
  local parts = {}
  for i = 1, math.min(#order, SUMMARY_KINDS) do parts[i] = ("%s %d"):format(order[i], counts[order[i]]) end
  if #order > SUMMARY_KINDS then parts[#parts + 1] = "and more" end
  local words
  if #rows > 0 then
    words = ("%d %s: %s"):format(#rows, #rows == 1 and "way to get it" or "ways to get it", table.concat(parts, ", "))
  elseif removed then
    return removed.text
  end
  if goneSources > 0 then
    words = (words and (words .. "; ") or "") .. ("%d no longer in the game"):format(goneSources)
  end
  return words
end

-- HOW TO GET MORE's tiles: a tile per kind of way to get it, most first
-- (only with two kinds or more)
local SOURCE_ICONS = {
  ["Sold by"] = "Interface\\Icons\\INV_Misc_Coin_01", ["Drops from"] = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
  ["Boss loot"] = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", Reward = "Interface\\Icons\\INV_Misc_Note_01",
  ["Choice reward"] = "Interface\\Icons\\INV_Misc_Note_01", ["Found at"] = "Interface\\Icons\\INV_Box_01",
  ["Crafted by"] = "Interface\\Icons\\Trade_BlackSmithing", ["Made from"] = "Interface\\Icons\\Trade_Engineering",
  ["Zone drop"] = "Interface\\Icons\\INV_Misc_Map_01", ["World drop"] = "Interface\\Icons\\INV_Misc_Map_01",
  Achievement = "Interface\\Icons\\Achievement_General", Renown = "Interface\\Icons\\Achievement_Reputation_01",
}
local function GetTiles(rows)
  local counts, order = {}, {}
  for _, row in ipairs(rows) do
    local kind = row.kindLabel or "Other"
    if not counts[kind] then order[#order + 1] = kind end
    counts[kind] = (counts[kind] or 0) + 1
  end
  if #order < 2 or #rows < LAYOUT.TILES_MIN then return nil end
  table.sort(order, function(a, b)
    if counts[a] ~= counts[b] then return counts[a] > counts[b] end
    return (SOURCE_ORDER[a] or 20) < (SOURCE_ORDER[b] or 20)
  end)
  -- each tile's tooltip: the first few of its kind with where each is, and
  -- where the rest are (Cobanyte, 2026-09-28: the tiles had no tooltip)
  local SHOWN = 6
  local byKind = {}
  for _, row in ipairs(rows) do
    local kind = row.kindLabel or "Other"
    byKind[kind] = byKind[kind] or {}
    table.insert(byKind[kind], row)
  end
  local tiles = {}
  for _, kind in ipairs(order) do
    local lines = {}
    for i, row in ipairs(byKind[kind]) do
      if i > SHOWN then break end
      local okN, name = pcall(Data().DisplayName, row)
      local okW, where = pcall(Data().Where, row)
      lines[#lines + 1] = { (okN and type(name) == "string" and name ~= "") and name or "Loading",
        (okW and type(where) == "string") and where or "" }
    end
    local more = counts[kind] - #lines
    tiles[#tiles + 1] = { label = kind, count = counts[kind],
      icon = SOURCE_ICONS[kind] or "Interface\\Icons\\INV_Misc_QuestionMark",
      tip = { title = ("%s (%d)"):format(kind, counts[kind]), lines = lines,
        note = more > 0 and ("And %d more on the Comes from tab."):format(more) or "All of them are on the Comes from tab too." } }
  end
  return tiles
end

-- HOW TO GET MORE: the season tag and the patch that removed it first, then
-- its sources, the ones this character can use first, then the kinds a new
-- player looks for first, the rest in a container (Fold), then how many
-- ways to get it are gone
local function GetLines(j, model, itemID)
  local lines = {}
  local okSeason, season = pcall(SeasonLine, model, itemID)
  if okSeason and season then lines[#lines + 1] = { text = season.text, color = season.color } end
  local removed = RemovedLine(itemID)
  -- shown once: not when it is the verdict's own reason (review F11)
  if removed and not (model and (removed.text == model.reason or (model.result and removed.text == model.result.reason))) then
    lines[#lines + 1] = removed
  end
  if not j then return lines end
  local rows = {}
  for _, row in ipairs(j.tabs.sources) do rows[#rows + 1] = row end
  table.sort(rows, function(a, b)
    if (a.restricted or false) ~= (b.restricted or false) then return not a.restricted end
    local oa, ob = SOURCE_ORDER[a.kindLabel] or 20, SOURCE_ORDER[b.kindLabel] or 20
    if oa ~= ob then return oa < ob end
    return (a.id or 0) < (b.id or 0)
  end)
  local tiles = GetTiles(rows)
  if tiles then lines.tiles = { text = "", tiles = tiles, lead = true } end   -- painted before the lines
  local named, nextIndex = Fold.Take(rows, 1, MAX_SUMMARY, FOR.RowLine)
  for _, line in ipairs(named) do lines[#lines + 1] = line end
  Fold.Container(lines, "get", rows, nextIndex, "sources", FOR.RowLine)
  -- what crafting it takes, under its own title (Cobanyte, 2026-09-28: it
  -- belongs with how to get more, not with what the item is for)
  local crafts = {}
  for _, row in ipairs(j.tabs.takes or {}) do if FOR.IsCraft(row) then crafts[#crafts + 1] = row end end
  local craftTally = FOR.Group(lines, crafts, "get:craft", "takes", "What crafting it takes")
  local _, _, goneSources = Gone.Read(j.tabs.gone)
  if goneSources > 0 and not removed then
    lines[#lines + 1] = Plain(("%d %s no longer in the game (the No longer available tab)"):format(goneSources,
      goneSources == 1 and "way to get it is" or "ways to get it are"), U.Colors.LABEL_GRAY)
  end
  lines.summary = GetSummary(rows, removed, goneSources)
  if craftTally then
    lines.summary = lines.summary and (lines.summary .. "; " .. craftTally:gsub("^%u", string.lower)) or craftTally
  end
  return lines
end

-- GUIDE NOTES (UI.UsedFor.NoteLines, never a use or a verdict): each note,
-- its details, a named achievement's or quest's state, then whose words
local function NoteLines(model, itemID, owner)
  local notes = model.notes
  if type(notes) ~= "table" then
    if not Recollect.Utilities.IsPositiveID(itemID) then return {} end
    local ok, read = pcall(Recollect.UI.UsedFor.NoteLines, itemID, owner)
    notes = ok and type(read) == "table" and read or {}
  end
  local lines = {}
  for _, note in ipairs(notes) do
    lines[#lines + 1] = { text = tostring(note.text), color = note.color or U.Colors.LABEL_GRAY }
    for _, detail in ipairs(note.details or {}) do
      lines[#lines + 1] = { text = detail, sub = true, textColor = U.Colors.LABEL_GRAY }
    end
    if type(note.state) == "table" then
      lines[#lines + 1] = { text = tostring(note.state.text), color = note.state.color, links = HeardLinks(note.state.links),
        sub = true, textColor = U.Colors.LABEL_GRAY, colorState = true }
    end
    if note.label then lines[#lines + 1] = { text = note.label, sub = true, textColor = U.Colors.INFO_BLUE } end
  end
  return lines
end

-- Where another character holds it, as last seen: "1 in their bags and 2 in
-- their bank"
local function OtherWords(other)
  local parts = {}
  if (other.bags or 0) > 0 then parts[#parts + 1] = ("%d in their bags"):format(other.bags) end
  if (other.bank or 0) > 0 then parts[#parts + 1] = ("%d in their bank"):format(other.bank) end
  if #parts == 0 then parts[1] = tostring(other.count) end
  return table.concat(parts, " and ")
end

-- Each place's icon on WHAT YOU HAVE's tiles
local PLACE_ICONS = {
  Bags = "Interface\\Icons\\INV_Misc_Bag_08", ["On this character"] = "Interface\\Icons\\INV_Misc_Bag_08",
  Worn = "Interface\\Icons\\INV_Shirt_White_01", Bank = "Interface\\Icons\\INV_Box_02",
  ["Warband bank"] = "Interface\\Icons\\INV_Box_04",
  ["Other characters"] = "Interface\\Icons\\Achievement_Character_Human_Male",
}

-- Where this character's copies are, place by place, for the tiles' hover
-- (Cobanyte, 2026-09-28: "Bank Tab 1" and the like): the bags read now, the
-- bank tabs and warband tabs as last stored (with their own names and when
-- they were read); { Bags = { { label, count } }, Bank = ..., ["Warband bank"] = ... }
local BAG_LABELS = { [0] = "Backpack" }
function Detail.Where(itemID)
  local Locations, Snapshots = Recollect.Inventory.Locations, Recollect.Inventory.Snapshots
  local out = { Bags = {}, Bank = {}, ["Warband bank"] = {} }
  local function Count(read)
    local n = 0
    for _, stack in pairs(type(read) == "table" and type(read.slots) == "table" and read.slots or {}) do
      if type(stack) == "table" and stack.itemID == itemID then n = n + (tonumber(stack.count) or 1) end
    end
    return n
  end
  local okBags, bags = pcall(Locations.Bags)
  for _, bagID in ipairs(okBags and bags or {}) do
    local ok, read = pcall(Recollect.Inventory.Reader.ReadContainer, bagID)
    local n = ok and type(read) == "table" and read.readable and Count(read) or 0
    if n > 0 then
      local label = BAG_LABELS[bagID] or (bagID == Locations.REAGENT_BAG and "Reagent bag") or ("Bag " .. bagID)
      out.Bags[#out.Bags + 1] = { label = label, count = n, order = bagID }
    end
  end
  local function Stored(list, locations, kind, names)
    for bagID, stored in pairs(type(locations) == "table" and locations or {}) do
      if Locations.KindOf(bagID) == kind and type(stored) == "table" then
        local n = Count(stored.read)
        if n > 0 then
          list[#list + 1] = { label = Locations.Label(bagID, names), count = n, order = bagID, asOf = stored.captured }
        end
      end
    end
    table.sort(list, function(a, b) return a.order < b.order end)
  end
  local char = Snapshots.CurrentCharacter(false)
  Stored(out.Bank, char and char.locations, Locations.KIND_BANK, char and char.bankTabNames)
  local warband, db = Snapshots.Warband()
  Stored(out["Warband bank"], warband, Locations.KIND_WARBAND, db and db.warbandTabNames)
  return out
end

-- A tile's hover: the place, then where in it, with when a stored read was made
local function PlaceTip(title, entries, empty)
  local lines = {}
  local asOf
  for _, e in ipairs(entries or {}) do
    lines[#lines + 1] = { e.label, tostring(e.count) }
    if e.asOf and (not asOf or e.asOf > asOf) then asOf = e.asOf end
  end
  return { title = title, lines = lines, empty = empty,
    note = asOf and ("As last read, %s"):format(date("%b %d %H:%M", asOf)) or nil }
end

-- WHAT YOU HAVE (Cobanyte, 2026-09-28): every place this character's copies
-- can be, as tiles (the icon, the count, the place); then, while
-- "Include your other characters" is on, each other character holding it,
-- as last seen ("Tanklite has 1 in their bank (as of Sep 24)"). The
-- section's summary names only the places that hold it.
local function HaveLines(itemID)
  local held = Recollect.UI.Tooltip.HeldCounts(itemID)
  local lines = {}
  local found = {}
  local okW, where = pcall(Detail.Where, itemID)
  where = okW and where or {}
  if held then
    local tiles, words = {}, {}
    for _, place in ipairs(held.places) do
      local tip
      if place.label == "Worn" then
        tip = { title = "Worn", lines = {}, empty = place.count > 0 and ("%d equipped on this character"):format(place.count)
          or "None equipped" }
      else
        tip = PlaceTip(place.label, where[place.label] or where.Bags, place.count > 0 and nil or ("None in your " .. place.label:lower()))
      end
      tiles[#tiles + 1] = { label = place.label, count = place.count, icon = PLACE_ICONS[place.label] or PLACE_ICONS.Bags, tip = tip }
      words[#words + 1] = ("%s: %d"):format(place.label, place.count)
      if place.count > 0 then found[#found + 1] = place.words:format(place.count) end
    end
    lines[#lines + 1] = { text = table.concat(words, "; "), tiles = tiles }
  else
    lines[#lines + 1] = Plain("How many you have can't be read")
  end
  local others = {}
  local listOthers = Recollect.Config.Get(Recollect.Config.Options.LIST_OTHERS) == true
  if listOthers then
    local ok, part = pcall(Recollect.Facts.Requirements.Part, itemID, 0)
    others = ok and part and part.others or {}
  end
  -- the other characters' total as a tile of its own, each one on its hover
  local tileLine = lines[1] and lines[1].tiles and lines[1]
  if tileLine and listOthers then
    local total, tipLines = 0, {}
    for _, other in ipairs(others) do
      total = total + other.count
      tipLines[#tipLines + 1] = { other.name, OtherWords(other) }
    end
    tileLine.tiles[#tileLine.tiles + 1] = { label = "Other characters", count = total, icon = PLACE_ICONS["Other characters"],
      tip = { title = "Your other characters", lines = tipLines, empty = total == 0 and "None of your other characters has it" or nil,
        note = "As each one was last seen" } }
  end
  if #others > 0 then lines[#lines + 1] = Group("Your other characters, as last seen") end
  local elsewhere = 0
  for _, other in ipairs(others) do
    elsewhere = elsewhere + other.count
    lines[#lines + 1] = { text = ("%s has %s (as of %s)"):format(other.name, OtherWords(other),
      other.asOf and date("%b %d", other.asOf) or "an unknown time") }
  end
  local summary
  if not held then
    summary = "How many you have can't be read"
  elseif held.total > 0 then
    summary = ("You have %d: %s"):format(held.total, table.concat(found, "; "))
  else
    summary = "You have none"
  end
  if elsewhere > 0 then
    summary = ("%s; %d on your other characters"):format(summary, elsewhere)
  end
  lines.summary = summary
  return lines
end

-- The names the verdict's and the checks' reasons may use, as links: the
-- names USED FOR and COMES FROM heard (model.links), a check's own links
-- when it gives them (purpose.links), and a known use's reward (Data.Uses:
-- the Ancestral War Bear, whose item's tooltip says "Already known")
function Detail.ReasonLinks(model)
  local links = HeardLinks(model.links)
  local result = model.result
  local itemID = model.source and model.source.itemID
  for _, purpose in ipairs(type(result) == "table" and result.purposes or {}) do
    if type(purpose.links) == "table" then HeardLinks(purpose.links, links) end
    if purpose.key == "knownUse" and Recollect.Utilities.IsPositiveID(itemID) then
      local ok, entries = pcall(Recollect.Purposes.KnownUse.EntriesFor, itemID)
      for _, entry in ipairs(ok and entries or {}) do
        if type(entry.reward) == "string" and Recollect.Utilities.IsPositiveID(entry.rewardItem) then
          HeardLinks({ { kind = "item", id = entry.rewardItem, text = (entry.reward:gsub("^the ", "")) } }, links)
        end
      end
    end
  end
  return links
end

-- The model's title and where it is: "Bank tab 1, as of Sep 24 10:12 (Tanklite's)"
local function TitleAndWhere(model)
  local source = model.source or {}
  local owner = source.owner or Recollect.Verdicts.Rows.Owner()
  local where = source.where or model.where
  if source.asOf and not source.live then where = ("%s, as of %s"):format(where or "stored", date("%b %d %H:%M", source.asOf)) end
  if owner and not owner.isViewer and owner.name then where = ("%s (%s's)"):format(where or "", owner.name) end
  local title = Recollect.Utilities.IsPositiveID(source.itemID) and ItemName(source.itemID) or (model.label or "Item")
  return title, where
end

-- One section's lines read safely: a reader that fails leaves its section
-- out, never the whole Overview
local function Safely(fn, ...)
  local ok, lines = pcall(fn, ...)
  if ok and type(lines) == "table" then return lines end
  if not ok then Recollect.Debug.Warn("UI", "Detail section failed: %s", tostring(lines)) end
  return {}
end

-- Content(model, j): { title, where, icon, sections = { { title, lines,
-- summary, inline } } }, summary the header's one line, inline a section
-- painted without a header
-- for the Overview; j (UI.DetailData's build) adds what it's for, how to
-- get more and what you have
function Detail.Content(model, j)
  TipPaint.n = TipPaint.n + 1
  local source = model.source or {}
  local itemID = source.itemID
  local owner = source.owner or Recollect.Verdicts.Rows.Owner()
  local sections = {}
  local okLinks, reasonLinks = pcall(Detail.ReasonLinks, model)
  reasonLinks = okLinks and reasonLinks or {}
  -- the verdict and its reason are the header strip's (header = true: the
  -- Overview paints the reason only when the strip had to cut it)
  local head = {}
  if model.headline then
    head[#head + 1] = { text = model.headline, color = U.Colors.HIGHLIGHT_WHITE, big = true, header = "verdict" }
  else
    head[#head + 1] = { text = model.label, color = model.color or U.Colors.HIGHLIGHT_WHITE, big = true, header = "verdict" }
  end
  local reasons = {}
  if model.reason and model.reason ~= "" then
    for _, part in ipairs(Recollect.UI.AuditPanel.Segments(model.reason)) do
      local line = Plain(part)
      line.header = "reason"
      head[#head + 1] = line
      reasons[#reasons + 1] = line
    end
  end
  -- the panel's "Still needed?" line is the header box's here (Detail.Keep)
  local boxed = type(model.verdictNote) == "string" and model.verdictNote:find("^Still needed%?") and Detail.Keep(model)
  if model.verdictNote and not boxed then head[#head + 1] = Plain(model.verdictNote, U.Colors.LABEL_GRAY) end
  if model.gone then
    head[#head + 1] = Plain("This copy has moved or been used since it was pinned; its verdict is as of then", U.Colors.LABEL_GRAY)
  end
  local banded = Detail.Keep(model)   -- the answer band says the recovery step and carries the Tip
  if model.recovery and not banded then head[#head + 1] = Plain(model.recovery, U.Colors.INFO_BLUE) end
  -- the Tip (UI.Tooltip.Tip): its label in gold, as the panel shows it
  if type(model.tip) == "string" and model.tip ~= "" and not banded then
    local label = Recollect.UI.Tooltip.TIP_LABEL or "Tip"
    local line = Plain(("%s: %s"):format(label, model.tip))
    line.display, line.tip = Recollect.UI.AuditPanel.TipText(model.tip), true
    head[#head + 1] = line
  end
  sections[#sections + 1] = { lines = head }
  -- WHAT IT'S FOR opens with what the item is, spelled out (FOR.Explain,
  -- with the game's own filing of it, WHAT IT IS, under it), then an older
  -- system's line (it needs no rows), then the groups of uses
  -- (section.lead: painted before its lines, kept apart from the uses)
  local lead = Safely(FOR.Explain, model, j, itemID)
  local explained = lead[1] and lead[1].explain and lead[1].text or nil
  local uses = Safely(LegacyLines, model)
  local tallies = {}
  if j then
    local forLines = Safely(ForLines, j)
    for _, line in ipairs(forLines) do uses[#uses + 1] = line end
    tallies = forLines.tallies or {}
    if forLines.tiles then table.insert(lead, 2, forLines.tiles) end   -- under the explanation, above the quote
  end
  if #uses > 0 or #lead > 0 then
    sections[#sections + 1] = { title = "WHAT IT'S FOR", lines = uses, lead = lead,
      summary = (#tallies > 0 and table.concat(tallies, "; ")) or explained or (uses[1] and uses[1].text) }
  end
  local achievements = Safely(AchievementLines, j)
  if #achievements > 0 then
    sections[#sections + 1] = { title = "ACHIEVEMENTS", lines = achievements, summary = achievements.summary }
  end
  local gets = Safely(GetLines, j, model, itemID)
  if #gets > 0 then
    sections[#sections + 1] = { title = "HOW TO GET MORE", lines = gets, summary = gets.summary or gets[1].text,
      lead = gets.tiles and { gets.tiles } or nil }
  end
  local notes = Safely(NoteLines, model, itemID, owner)
  if #notes > 0 then sections[#sections + 1] = { title = "GUIDE NOTES", lines = notes, summary = notes[1].text } end
  if Recollect.Utilities.IsPositiveID(itemID) and owner.isViewer ~= false then
    local have = Safely(HaveLines, itemID)
    sections[#sections + 1] = { title = "WHAT YOU HAVE", lines = have, summary = have.summary or (have[1] and have[1].text) }
  end
  -- every name linked above is linked in the reasons too
  for _, section in ipairs(sections) do
    for _, line in ipairs(section.lines) do
      for _, link in ipairs(line.links or {}) do reasonLinks[#reasonLinks + 1] = link end
    end
  end
  for _, line in ipairs(reasons) do line.links = reasonLinks end
  local result = model.result
  if result and result.purposes and #result.purposes > 0 then
    local checks, labels, colors = {}, {}, Recollect.UI.VerdictColors
    for _, purpose in ipairs(result.purposes) do
      checks[#checks + 1] = { text = ("%s: %s"):format(tostring(purpose.label), tostring(purpose.reason)),
        color = colors[purpose.verdict] or U.Colors.LABEL_GRAY, links = reasonLinks }
      labels[#labels + 1] = tostring(purpose.label)
    end
    sections[#sections + 1] = { title = "CHECKS", lines = checks,
      summary = ("%d %s: %s"):format(#checks, #checks == 1 and "check" or "checks", table.concat(labels, ", ")) }
  end
  local title, where = TitleAndWhere(model)
  return { title = title, where = where, icon = model.icon, sections = sections }
end

-------------------------------------------------------------------------------
-- Links in the text (item 3, Cobanyte 2026-09-25): a name a line links is a
-- real link in its link's color. Hovering it shows the game's own tooltip,
-- and its clicks are a table row's (the chat link's click, Alt-click opens
-- it here, right-click the menu): the link's data names a row this paint
-- keeps ("addon:Recollect:o:3", "h" for the header strip's), so hover and
-- click use that row itself. The handlers are under Rows below.
-------------------------------------------------------------------------------
local Hex = U.ColorToHex

local Hyper = { rows = { h = {}, o = {} } }

-- Whether a name found at first..last stands alone, not inside a longer word
local function Alone(text, first, last)
  local function Word(b) return b ~= nil and (b >= 128 or string.char(b):find("%w") ~= nil) end
  return not Word(text:byte(first - 1)) and not Word(text:byte(last + 1))
end

-- Text(text, links, prefix): text with every name links holds as a link,
-- longer names first, never one inside another or inside a longer word, in
-- brackets as the game's chat links are (Cobanyte, 2026-09-25); each link's
-- row kept under prefix for the handlers
function Hyper.Text(text, links, prefix)
  text = tostring(text)
  if type(links) ~= "table" or #links == 0 then return text end
  local order = {}
  for _, link in ipairs(links) do
    local row = link.row or (link.kind and Data().LinkRow(link.kind, link.id))
    if row and type(link.text) == "string" and link.text ~= "" then
      order[#order + 1] = { text = link.text, color = link.color, row = row }
    end
  end
  table.sort(order, function(a, b) return #a.text > #b.text end)
  local spans = {}
  for _, link in ipairs(order) do
    local from = 1
    while true do
      local first, last = text:find(link.text, from, true)
      if not first then break end
      local free = Alone(text, first, last)
      for _, span in ipairs(spans) do
        if free and first <= span[2] and last >= span[1] then free = false end
      end
      if free then spans[#spans + 1] = { first, last, link } end
      from = last + 1
    end
  end
  if #spans == 0 then return text end
  table.sort(spans, function(a, b) return a[1] < b[1] end)
  local rows = Hyper.rows[prefix or "o"]
  local out, at = {}, 1
  for _, span in ipairs(spans) do
    rows[#rows + 1] = span[3].row
    out[#out + 1] = text:sub(at, span[1] - 1)
    out[#out + 1] = ("|cFF%s|Haddon:Recollect:%s:%d|h[%s]|h|r"):format(Hex(span[3].color or U.Colors.HIGHLIGHT_WHITE),
      prefix or "o", #rows, text:sub(span[1], span[2]))
    at = span[2] + 1
  end
  out[#out + 1] = text:sub(at)
  return table.concat(out)
end

-- Line(line, prefix): a bulleted line's text, light gray with only its
-- closing "(state)" in the line's color (as UI.AuditPanel.LineText) and its
-- names as links
function Hyper.Line(line, prefix)
  if line.display then return line.display end
  local text = tostring(line.text)
  local head, state = text:match("^(.-)(%b())$")
  if not head or type(line.color) ~= "table" then return Hyper.Text(text, line.links, prefix) end
  return ("%s|cFF%s%s|r"):format(Hyper.Text(head, line.links, prefix), Hex(line.color), state)
end

-- Row(link): the row a link's data names, or nil
function Hyper.Row(link)
  local prefix, n = tostring(link):match("^addon:Recollect:(%a):(%d+)$")
  local rows = prefix and Hyper.rows[prefix]
  return rows and rows[tonumber(n)] or nil
end

-------------------------------------------------------------------------------
-- Painting the Overview
-------------------------------------------------------------------------------
local fonts, fontsUsed = {}, 0
local textures, texturesUsed = {}, 0
local maps = {}
-- The containers' pieces (Fold): their buttons, made at login with the Map
-- buttons, and their boxes' textures
local folds, foldsUsed = {}, 0
local boxes, boxesUsed = {}, 0

local function Font(template, color)
  fontsUsed = fontsUsed + 1
  local fs = fonts[fontsUsed]
  if not fs then
    fs = window.Overview.Child:CreateFontString(nil, "OVERLAY")
    fs:SetWordWrap(true)
    fonts[fontsUsed] = fs
  end
  fs:SetJustifyH("LEFT")   -- a pooled string may have been a right-aligned count
  fs:SetFontObject(template)
  fs:SetTextColor(color[1], color[2], color[3])
  fs:ClearAllPoints()
  fs:Show()
  return fs
end

local function Dot(color, x, y)
  texturesUsed = texturesUsed + 1
  local tex = textures[texturesUsed]
  if not tex then
    tex = window.Overview.Child:CreateTexture(nil, "ARTWORK")
    textures[texturesUsed] = tex
  end
  tex:SetTexCoord(0, 1, 0, 1)
  tex:SetDesaturated(false)
  tex:SetAlpha(1)
  tex:SetColorTexture(color[1], color[2], color[3], 1)
  tex:SetSize(BULLET, BULLET)
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", window.Overview.Child, "TOPLEFT", x, y)
  tex:Show()
end

-- An icon from the same pool as the dots, dimmed and gray when dim
local function PoolIcon(file, x, y, size, dim)
  texturesUsed = texturesUsed + 1
  local tex = textures[texturesUsed]
  if not tex then
    tex = window.Overview.Child:CreateTexture(nil, "ARTWORK")
    textures[texturesUsed] = tex
  end
  tex:SetTexture(file)
  tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  tex:SetDesaturated(dim == true)
  tex:SetAlpha(dim and 0.45 or 1)
  tex:SetSize(size, size)
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", window.Overview.Child, "TOPLEFT", x, y)
  tex:Show()
end

-- The tiles' hover frames, made at login with the Overview (never in
-- combat): one over each tile that has a tip
local tileHovers, tileHoversUsed = {}, 0
local TILE_HOVERS = 12
local function TileHover(tip, x, y, width, height)
  if tileHoversUsed >= #tileHovers then return end
  tileHoversUsed = tileHoversUsed + 1
  local f = tileHovers[tileHoversUsed]
  f.tip = tip
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", window.Overview.Child, "TOPLEFT", x, y)
  f:SetSize(width, height)
  f:Show()
end

local function TileTooltip(self)
  local tip = self.tip
  if not tip then return end
  local GameTooltip = seams.Tooltip()
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(tip.title, 1, 1, 1)
  local light, gray = U.Colors.LIGHT_GRAY, U.Colors.LABEL_GRAY
  for _, line in ipairs(tip.lines or {}) do
    GameTooltip:AddDoubleLine(line[1], line[2], light[1], light[2], light[3], 1, 1, 1)
  end
  if tip.empty and #(tip.lines or {}) == 0 then GameTooltip:AddLine(tip.empty, gray[1], gray[2], gray[3], true) end
  if tip.note then GameTooltip:AddLine(tip.note, gray[1], gray[2], gray[3], true) end
  GameTooltip:Show()
end

local function Block(template, color, text, x, y, width)
  local fs = Font(template, color)
  fs:SetPoint("TOPLEFT", window.Overview.Child, "TOPLEFT", x, y)
  fs:SetWidth(math.max(width, 40))
  fs:SetText(text)
  return fs:GetStringHeight(), fs
end

-- A line's Map button, placed once its text is painted (MapAfter)
local function MapButton(index, place)
  local b = maps[index]
  if not b then return nil end
  b.place = place
  b:ClearAllPoints()
  b:Show()
  return b
end

-- The Map button just after its line's text, level with its first row
-- (Cobanyte, 2026-09-25: beside the line, not at the window's right edge):
-- past the widest wrapped row, in the room the text left for it; at the
-- right edge only when the line painted no text (a container's button)
local function MapAfter(b, fs, y)
  local okW, w = false, nil
  if fs then okW, w = pcall(fs.GetWrappedWidth, fs) end
  if okW and tonumber(w) then
    b:SetPoint("TOPLEFT", fs, "TOPLEFT", math.min(tonumber(w), fs:GetWidth()) + 4, 1)
  else
    b:SetPoint("TOPRIGHT", window.Overview.Child, "TOPRIGHT", 0, y + 1)
  end
end

-- A shaded texture: a container's box or its left edge, or an open section's
-- body behind it (sublevel: the body's lower, so the box shows over it)
function Fold.Texture(color, x, top, width, height, sublevel)
  boxesUsed = boxesUsed + 1
  local tex = boxes[boxesUsed]
  if not tex then
    tex = window.Overview.Child:CreateTexture(nil, "BACKGROUND")
    boxes[boxesUsed] = tex
  end
  tex:SetDrawLayer("BACKGROUND", sublevel or 0)
  tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", window.Overview.Child, "TOPLEFT", x, top)
  tex:SetSize(math.max(width, 1), math.max(height, 1))
  tex:Show()
end

-- A container's box from top to bottom, x0 from the left: shaded, with a
-- line down its left edge, so its rows read apart from the section's own
function Fold.Box(top, bottom, width, x0)
  local x = (x0 or 0) + Fold.BOX_INDENT - 8
  Fold.Texture(U.Colors.CONTENT_BG, x, top + 2, width + (x0 or 0) - x, top - bottom + 2, 1)
  Fold.Texture(U.Colors.DIVIDER_GRAY, x, top + 2, 2, top - bottom + 2, 2)
end

-- A container's header ("and 12 more on the Buys tab", its plus or minus) or its
-- "Show 25 more", as a button at x, y; false when every button is in use
-- (the line is painted as text then)
function Fold.Button(line, x, y, width)
  if foldsUsed >= #folds then return false end
  foldsUsed = foldsUsed + 1
  local b = folds[foldsUsed]
  b.key, b.action = line.toggle or line.more, line.toggle and "toggle" or "more"
  -- minus to close an open container; plus to open one or show more of it
  local atlas = (line.toggle and line.expanded) and Fold.EXPANDED or Fold.COLLAPSED
  b.Arrow:SetAtlas(atlas)
  b.ArrowGlow:SetAtlas(atlas)
  local color = line.color or U.Colors.LIGHT_GRAY
  b.Label:SetText(line.text)
  b.Label:SetTextColor(color[1], color[2], color[3])
  local okW, textWidth = pcall(b.Label.GetStringWidth, b.Label)
  textWidth = okW and tonumber(textWidth) or width
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", window.Overview.Child, "TOPLEFT", x, y)
  b:SetSize(math.min(width, textWidth + Fold.ICON + 10), Fold.HEIGHT)
  b:Show()
  return true
end

-------------------------------------------------------------------------------
-- The Overview's sections (Cobanyte, 2026-09-26): each titled section is a
-- header like the feature guide's (CobySuite.UI.CreateGuideWindow): an icon,
-- its title, a one-line summary, and at its right edge the objective
-- tracker's plus or minus; a click opens or closes its lines, shaded apart.
-- Which are open is kept in RECOLLECT_WINDOW_STATE.detailSections for every
-- item; a section never opened or closed there starts closed, except the
-- first one the item shows. WHAT IT'S FOR paints its lead (the explanation)
-- before its lines.
-------------------------------------------------------------------------------
local ICONS = "Interface\\Icons\\"
local Sections = {
  -- compact (Cobanyte, 2026-09-26: "compact it just a little bit vertically")
  HEADER = 32, ICON = 24, PAD = 8, GAP = 9, TOP_GAP = 6, BODY_PAD = 6, BODY_X = 12, HEADERS = 8,
  META = {
    ["WHAT IT'S FOR"] = { key = "for", heading = "What it's for", icon = ICONS .. "INV_Misc_Book_09" },
    ACHIEVEMENTS = { key = "achievements", heading = "Achievements", icon = ICONS .. "Achievement_General" },
    ["HOW TO GET MORE"] = { key = "get", heading = "How to get more", icon = ICONS .. "INV_Misc_Map_01" },
    ["GUIDE NOTES"] = { key = "notes", heading = "Guide notes", icon = ICONS .. "INV_Misc_Note_02" },
    ["WHAT YOU HAVE"] = { key = "have", heading = "What you have", icon = ICONS .. "INV_Misc_Bag_08" },
    CHECKS = { key = "checks", heading = "Checks", icon = ICONS .. "INV_Misc_Spyglass_02" },
  },
  headers = {}, used = 0,
  session = {},   -- used only while RECOLLECT_WINDOW_STATE isn't a table
}

function Sections.Meta(section)
  return Sections.META[section.title]
    or { key = tostring(section.title):lower(), heading = tostring(section.title), icon = 134400 }
end

function Sections.Saved()
  if type(RECOLLECT_WINDOW_STATE) ~= "table" then return Sections.session end
  if type(RECOLLECT_WINDOW_STATE.detailSections) ~= "table" then RECOLLECT_WINDOW_STATE.detailSections = {} end
  return RECOLLECT_WINDOW_STATE.detailSections
end

-- IsOpen(key, first): the player's choice, else open only when first
function Sections.IsOpen(key, first)
  local saved = Sections.Saved()[key]
  if saved ~= nil then return saved == true end
  return key == first
end

function Sections.Toggle(key, first)
  local open = not Sections.IsOpen(key, first)
  Sections.Saved()[key] = open
  PlaySound(open and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
  Fold.Paint()
end

-- A section's header, made at login with the Overview
function Sections.MakeHeader(parent)
  -- the feature guide's header, compact (CobySuite.UI.CreateCollapsibleHeader)
  local h = CobySuite_Recollect.UI.CreateCollapsibleHeader(parent, { height = Sections.HEADER, iconSize = Sections.ICON,
    pad = Sections.PAD, titleFont = U.Fonts.HEADING, titleY = 2, summaryGap = 1 })
  h.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- the icon border
  h:SetScript("OnClick", function(self) Sections.Toggle(self.key, self.first) end)
  -- a drag on a header still moves the window, as on the lines
  h:RegisterForDrag("LeftButton")
  h:SetScript("OnDragStart", function()
    local start = window:GetScript("OnDragStart")
    if start then start(window) end
  end)
  h:SetScript("OnDragStop", function()
    local stop = window:GetScript("OnDragStop")
    if stop then stop(window) end
  end)
  h:Hide()
  return h
end

-- A section's header at y, as wide as the Overview; false when every header
-- is in use (the title is painted as text then)
function Sections.Header(meta, summary, open, first, y, width)
  if Sections.used >= #Sections.headers then return false end
  Sections.used = Sections.used + 1
  local h = Sections.headers[Sections.used]
  h.key, h.first = meta.key, first
  h.Icon:SetTexture(meta.icon)
  h.Title:SetText(meta.heading)
  h.Summary:SetText(summary or "")
  h:SetOpen(open)
  h:ClearAllPoints()
  h:SetPoint("TOPLEFT", window.Overview.Child, "TOPLEFT", 0, y)
  h:SetWidth(width)
  h:Show()
  return true
end

local function PaintOverview()
  if not window or not shown or not window.Overview:IsShown() then return end
  for i = 1, fontsUsed do fonts[i]:Hide() end
  for i = 1, texturesUsed do textures[i]:Hide() end
  for i = 1, boxesUsed do boxes[i]:Hide() end
  for _, b in ipairs(maps) do b:Hide() end
  for _, b in ipairs(folds) do b:Hide() end
  for _, f in ipairs(tileHovers) do f:Hide() end
  for _, h in ipairs(Sections.headers) do h:Hide() end
  fontsUsed, texturesUsed, boxesUsed, foldsUsed, Sections.used = 0, 0, 0, 0, 0
  tileHoversUsed = 0
  wipe(Hyper.rows.o)
  local ok, content = pcall(Detail.Content, shown, job and job.finished and job or nil)
  if not ok then
    Recollect.Debug.Warn("UI", "Detail view failed: %s", tostring(content))
    content = { sections = { { lines = { Plain("These details can't be read right now.", U.Colors.LABEL_GRAY) } } } }
  end
  local width = window.Overview.Scroll:GetWidth()
  if not width or width <= 0 then width = WIDTH - 2 * PAD - 20 end
  window.Overview.Child:SetWidth(width)
  local y, mapsUsed = -OVERVIEW_TOP, 0
  local okCut, cut = pcall(window.Reason.IsTruncated, window.Reason)
  local reasonCut = okCut and cut == true

  -- lines from x0, width wide, from y down; the container whose box is open
  -- and where it starts
  -- indentAll (a titled section, Cobanyte 2026-09-28: "we indent some
  -- sections but not all"): every line but a group's title, a closing note
  -- and the section's lead sits one step in, titled or not, so each
  -- section's lists line up the same way
  local function PaintLines(lines, baseX, baseWidth, small, indentAll)
    local boxKey, boxTop, boxX, boxWidth = nil, 0, baseX, baseWidth
    local grouped = false   -- under a group's title: the lines indented (Group)
    for index, line in ipairs(lines) do
      if line.group then grouped = true elseif line.ungroup then grouped = false end
      local x0, lineWidth = baseX, baseWidth
      if (grouped or indentAll) and not (line.group or line.ungroup or line.lead) then
        x0, lineWidth = baseX + LAYOUT.GROUP_INDENT, baseWidth - LAYOUT.GROUP_INDENT
      end
      -- a container's rows sit in its box, indented
      if line.box ~= boxKey then
        if boxKey then Fold.Box(boxTop, y, boxWidth, boxX) end
        boxKey, boxTop, boxX, boxWidth = line.box, y, x0, lineWidth
      end
      local left = x0 + (line.box and Fold.BOX_INDENT or 0)
      local textWidth, mapped = lineWidth + x0 - left - INDENT, nil
      if line.place and mapsUsed < MAP_BUTTONS then
        mapsUsed = mapsUsed + 1
        mapped = MapButton(mapsUsed, line.place)
        if mapped then textWidth = textWidth - MAP_WIDTH - 4 end
      end
      local top, h, fs = y, 0, nil
      if (line.toggle or line.more) and Fold.Button(line, left, y, textWidth + INDENT) then
        y = y - Fold.HEIGHT - 2
      elseif line.group then
        -- room above every group but the first line's
        if index > 1 then
          y = y - LAYOUT.GROUP_GAP
          top = y
        end
        local text = line.display or Hyper.Text(line.text, line.links, "o")
        h, fs = Block(U.Fonts.BODY, line.color or U.Colors.HIGHLIGHT_WHITE, text, left, y, textWidth + INDENT)
        y = y - (mapped and math.max(h, LINE_MAP) or h) - LINE_GAP
      elseif line.tiles then
        -- WHAT YOU HAVE's places as tiles (Cobanyte, 2026-09-28: "stylize that
        -- more"): each with its icon, the count large and the place under it;
        -- a place with none dimmed, so where the copies are shows at a glance
        local x, T = left, LAYOUT
        local gray, white = U.Colors.LABEL_GRAY, U.Colors.HIGHLIGHT_WHITE
        local right = x0 + lineWidth
        if index > 1 then y = y - T.TILES_GAP end   -- room above, apart from the text
        for _, tile in ipairs(line.tiles) do
          -- a tile is as wide as its label on one line, at least TILE_W
          -- (Cobanyte, 2026-09-28: "Other characters" wrapped out of its tile)
          local _, labelText = Block(U.Fonts.DATA, gray, tile.label, x, y, 400)
          local okL, labelW = pcall(labelText.GetStringWidth, labelText)
          local tileW = math.max(T.TILE_W, T.TILE_ICON + 18 + math.ceil(okL and tonumber(labelW) or 0) + 4)
          if x > left and x + tileW > right then   -- no room: the next row
            x = left
            y = y - T.TILE_H - T.TILE_GAP
          end
          local none = tile.count == 0
          Fold.Texture(U.Colors.CONTENT_BG, x, y, tileW, T.TILE_H, 1)
          PoolIcon(tile.icon, x + 7, y - (T.TILE_H - T.TILE_ICON) / 2, T.TILE_ICON, none)
          local textX, textW = x + T.TILE_ICON + 14, tileW - T.TILE_ICON - 18
          local _, countText = Block(U.Fonts.TITLE, none and gray or white, tostring(tile.count), textX, y - 4, textW)
          if tile.note then
            -- a note beside the count ("8 open"), in its color
            local okW, countW = pcall(countText.GetStringWidth, countText)
            local noteX = textX + (okW and tonumber(countW) or 20) + 5
            Block(U.Fonts.DATA, tile.noteColor or U.Colors.STATUS_GOLD, tile.note, noteX, y - 8, math.max(textX + textW - noteX, 20))
          end
          labelText:ClearAllPoints()
          labelText:SetPoint("TOPLEFT", window.Overview.Child, "TOPLEFT", textX, y - T.TILE_H + 14)
          labelText:SetWidth(math.max(textW, 40))
          if tile.tip then TileHover(tile.tip, x, y, tileW, T.TILE_H) end
          x = x + tileW + T.TILE_GAP
        end
        y = y - T.TILE_H - LINE_GAP - T.TILES_GAP
      elseif line.big then
        h, fs = Block(U.Fonts.TITLE, line.color or U.Colors.HIGHLIGHT_WHITE, line.text, left, y, lineWidth + x0 - left)
        y = y - h - LINE_GAP
      elseif line.plain then
        local text = line.display or Hyper.Text(line.text, line.links, "o")
        h, fs = Block(small and U.Fonts.DATA or U.Fonts.BODY, line.color or U.Colors.LIGHT_GRAY, text, left, y, textWidth)
        -- a line with a Map button is as tall as the button, so buttons never overlap
        y = y - (mapped and math.max(h, LINE_MAP) or h) - 2
      elseif line.sub then
        -- a note's details, the state of what it names, and whose words they are
        local text = line.colorState and Hyper.Line(line, "o") or Hyper.Text(line.text, line.links, "o")
        h, fs = Block(U.Fonts.DATA, line.textColor or U.Colors.LABEL_GRAY, text, left + INDENT, y, textWidth)
        y = y - (mapped and math.max(h, LINE_MAP) or h) - 1
      else
        Dot(line.color or U.Colors.LIGHT_GRAY, left + 2, y - 4)
        h, fs = Block(U.Fonts.SMALL, U.Colors.LIGHT_GRAY, Hyper.Line(line, "o"), left + INDENT, y, textWidth)
        y = y - (mapped and math.max(h, LINE_MAP) or h) - LINE_GAP
        local bar = line.bar
        if type(bar) == "table" and tonumber(bar.total) and bar.total > 0 and tonumber(bar.done) then
          -- how far along it is, as a thin bar under the line (achievements)
          local width = math.min(LAYOUT.BAR_W, textWidth)
          local share = math.max(0, math.min(1, bar.done / bar.total))
          local track = U.Colors.DIVIDER_GRAY
          Fold.Texture({ track[1], track[2], track[3], 0.6 }, left + INDENT, y + 1, width, LAYOUT.BAR_H, 2)
          if share > 0 then
            local fill = line.color or U.Colors.STATUS_GOLD
            Fold.Texture(fill, left + INDENT, y + 1, math.max(1, width * share), LAYOUT.BAR_H, 3)
          end
          y = y - LAYOUT.BAR_H - 3
        end
      end
      if mapped then MapAfter(mapped, fs, top) end
    end
    if boxKey then Fold.Box(boxTop, y, boxWidth, boxX) end
  end

  -- the first section shown is the one open by default
  local first = nil
  for _, section in ipairs(content.sections) do
    if section.title and not section.inline and (#section.lines > 0 or #(section.lead or {}) > 0) then
      first = Sections.Meta(section).key
      break
    end
  end
  local painted, afterHeader = false, false
  for _, section in ipairs(content.sections) do
    local lines = {}
    for _, line in ipairs(section.lead or {}) do lines[#lines + 1] = line end
    for _, line in ipairs(section.lines) do
      if line.header ~= "verdict" and (line.header ~= "reason" or reasonCut) then lines[#lines + 1] = line end
    end
    if #lines > 0 then
      local folded = section.title and not section.inline
      if not folded then
        if painted then y = y - SECTION_GAP end
        PaintLines(lines, 0, width, true)
        afterHeader = false
      else
        local meta = Sections.Meta(section)
        local open = Sections.IsOpen(meta.key, first)
        -- headers stack close; the first one stands apart from the lines above
        if painted then y = y - (afterHeader and Sections.GAP or Sections.TOP_GAP) end
        if Sections.Header(meta, section.summary, open, first, y, width) then
          y = y - Sections.HEADER
        else
          y = y - Block(U.Fonts.SMALL, U.Colors.STATUS_GOLD, meta.heading, 0, y, width) - LINE_GAP
          open = true
        end
        if open then
          local top = y
          y = y - Sections.BODY_PAD
          PaintLines(lines, Sections.BODY_X, width - Sections.BODY_X - Sections.PAD, nil, true)
          y = y - Sections.BODY_PAD + LINE_GAP
          local a = U.Colors.ALT_ROW_BG
          Fold.Texture(a, 0, top, width, top - y, -1)
        end
        afterHeader = true
      end
      painted = true
    end
  end
  window.Overview.Child:SetHeight(math.max(1, -y))
  window.Overview.Scroll:UpdateScrollChildRect()
end

function Fold.Paint() PaintOverview() end

-- A container's plus or minus: open it (its first slice) or close it; "Show 25
-- more": the next slice. The Overview is painted again either way
function Fold.Click(action, key)
  if type(key) ~= "string" then return end
  if action == "more" then
    Fold.shown[key] = math.min((Fold.shown[key] or Fold.SLICE) + Fold.SLICE, Fold.MAX)
  elseif Fold.expanded[key] then
    Fold.expanded[key], Fold.shown[key] = nil, nil
  else
    Fold.expanded[key] = true
  end
  Fold.Paint()
end

-- ForItem(model): another item shown: every open container starts again at
-- its first slice (which are open stays, for the session)
function Fold.ForItem(model)
  if model ~= Fold.item then wipe(Fold.shown) end
  Fold.item = model
end

-------------------------------------------------------------------------------
-- The tables: columns, sort keys and filters per tab
-------------------------------------------------------------------------------
local function White() return U.Colors.HIGHLIGHT_WHITE end
local function Gray() return U.Colors.LIGHT_GRAY end

-- A route no longer in the game, or one that doesn't serve the owner (or
-- whose condition its record can't answer), is dimmed, an item's quality
-- color included (D19); every other name in its quality's color, else white
local function NameColor(row)
  -- dimmed: a display-only condition the owner misses (D34), still sorted as it was
  if row.gone or row.restricted or row.dimmed then return U.Colors.LABEL_GRAY end
  local quality = Data().Quality(row)
  local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  if color then return { color.r, color.g, color.b } end
  return U.Colors.HIGHLIGHT_WHITE
end

local function Lower(text) return text and text:lower() or nil end

-- A plain column, as in a spreadsheet (Cobanyte, 2026-09-26): its divider's
-- double-click fits the names; a window wider than the columns leaves room
-- at the right
local NAME = { key = "name", label = "Name", width = 240,
  text = function(row) return Data().DisplayName(row) end, color = NameColor,
  icon = function(row) return Data().Icon(row) end, sort = function(row) return Lower(Data().DisplayName(row)) end }
local KIND = { key = "kind", label = "Kind", width = 110, text = function(row) return row.kindLabel or "" end, color = Gray,
  sort = function(row) return Lower(row.kindLabel) end }
local STATUS = { key = "status", label = "Status", width = 130, text = function(row) return row.stateText or "" end,
  color = function(row) return row.stateColor or U.Colors.LIGHT_GRAY end,
  sort = function(row) return ("%d %s"):format(row.tier or 2, Lower(row.stateText) or "~") end }
-- The waypoint button (its click and hover are set in BuildBody)
local MAP = { key = "map", label = "Map", width = 36, sortable = false,
  tooltip = "Set a map waypoint to where it is; on an achievement, open it in the achievement window",
  button = { shown = function(row) return Data().Place(row) ~= nil end,
    -- an achievement with no place: the secure achievement button instead
    alt = function(row)
      return row.what == "achievement" and Recollect.Utilities.IsPositiveID(row.achievementID) and Data().Place(row) == nil
    end } }
-- Who and where: the seller, the quest's giver, the creature's or spot's zone
local function WHERE(label, width)
  return { key = "where", label = label or "Where", width = width or 190, color = Gray,
    text = function(row) return Data().Where(row) or "" end, sort = function(row) return Lower(Data().Where(row)) end }
end
-- Whether a trade takes more than the pinned item: other costs listed, or
-- a part of the price the data doesn't list
local function MoreCosts(row)
  if row.plus then return true end
  local relation = row.relation
  return type(relation) == "table" and relation.unlisted ~= nil
end

-- The pinned item's icon after a count of it: "200 [token]", then " +" when
-- the trade takes other costs too (the cell's tooltip lists them)
local function CostText(row)
  local icon = shown and shown.source and shown.source.itemID and Data().Icon({ itemID = shown.source.itemID, what = "item" })
  local text = tostring(row.count or 1)
  if type(icon) == "number" then text = ("%s |T%d:0|t"):format(text, icon) end
  return MoreCosts(row) and (text .. " +") or text
end

-- A price in gold with its icons, or its words when that can't be read
local function Coins(copper)
  local ok, text = pcall(seams.Coins, copper)
  if ok and type(text) == "string" and text ~= "" then return text end
  return Recollect.UI.UsedFor.GoldWords(copper)
end

-- CostLines(row): a cost cell's tooltip (item 9), every part of the trade
-- the data lists, the pinned item's own count first, then other items,
-- currencies and gold (Relations.Costs), each { text, have }: its icon, how
-- many and its name, and how many you have (items with the banks and the
-- warband bank, a currency's own count, the gold on hand; nil when that
-- can't be read); then { text, note = true } for a part of the price the
-- data doesn't list. Counts are the logged-in character's.
function Detail.CostLines(row)
  local data, parts = Data(), Recollect.UI.UsedFor.parts
  local itemID = row.of or (shown and shown.source and shown.source.itemID)
  local costs = data.Costs(row)
  if not costs and Recollect.Utilities.IsPositiveID(itemID) then costs = { { kind = "item", id = itemID, count = row.count or 1 } } end
  local lines = {}
  for _, cost in ipairs(costs or {}) do
    local count = tonumber(cost.count) or 1
    if cost.kind == "gold" then
      local ok, money = pcall(seams.Money)
      lines[#lines + 1] = { text = Coins(count),
        have = ok and CobySuite_Recollect.Utilities.IsFiniteNumber(money) and Coins(money) or nil }
    elseif cost.kind == "currency" then
      local info = parts.Currency(cost.id)
      local icon = info and info.iconFileID
      lines[#lines + 1] = { text = ("%s%d %s"):format(icon and ("|T%s:0|t "):format(tostring(icon)) or "", count,
        info and info.name or ("currency " .. tostring(cost.id))),
        have = info and CobySuite_Recollect.Utilities.IsFiniteNumber(info.quantity) and tostring(info.quantity) or nil }
    elseif cost.id then
      local icon = data.Icon({ itemID = cost.id, what = "item" })
      local held = parts.Owned(cost.id)
      lines[#lines + 1] = { text = ("%s%d %s"):format(type(icon) == "number" and ("|T%d:0|t "):format(icon) or "", count,
        data.ItemName(cost.id) or ("item " .. tostring(cost.id))), have = held and tostring(held) or nil }
    end
  end
  local unlisted = type(row.relation) == "table" and row.relation.unlisted or nil
  if unlisted == "gold" then
    lines[#lines + 1] = { text = "plus a gold price not recorded", note = true }
  elseif unlisted == "costs" or (row.plus and #lines <= 1) then
    lines[#lines + 1] = { text = #lines > 1 and "and other costs not listed" or "plus other costs not listed", note = true }
  end
  return lines
end

local function Count(key, label, width, field)
  return { key = key, label = label, width = width, justify = "RIGHT", color = White,
    text = function(row)
      local n = field(row)
      return n and tostring(n) or ""
    end, sort = field }
end

local function PartField(name)
  return function(row) return row.part and row.part[name] or nil end
end

-- What a plain purchase leads to, and what a quest rewards (UI.DetailData)
local LEADS = { key = "leads", label = "Leads to", width = 150, color = Gray,
  text = function(row) return Data().LeadsTo(row) or "" end, sort = function(row) return Lower(Data().LeadsTo(row, nil, true)) end,
  tooltip = "What a plain item it buys is used for in turn: a quest's reward, or what it makes or buys" }
local REWARDS = { key = "rewards", label = "Rewards", width = 150, color = Gray,
  text = function(row) return Data().Rewards(row) or "" end, sort = function(row) return Lower(Data().Rewards(row)) end,
  tooltip = "What the quest rewards, with whether you have it" }

-- What a recipe makes, as the game counts it ("Pet: 1 of 3 collected"),
-- apart from the recipe's own state under Status (item 6)
local PRODUCT = { key = "product", label = "Makes", width = 150,
  text = function(row) return Data().ProductText(row) or "" end,
  color = function(row) return row.productColor or U.Colors.LABEL_GRAY end,
  sort = function(row)
    local text = Data().ProductText(row)
    return text and ("%d %s"):format(row.tier or 2, text:lower()) or nil
  end,
  tooltip = "What the recipe makes, as the game counts it: collected or not; the filter's still to get follows it" }

-- The last column fills what the others leave, with no divider of its own
-- to drag (Cobanyte, 2026-09-28); the Map button sits beside the place it
-- sets a waypoint to, so Status can be last
local function Last(col)
  local copy = {}
  for k, v in pairs(col) do copy[k] = v end
  copy.stretch = true
  return copy
end

local COLUMNS = {
  buys = { NAME, { key = "kind", label = "Type", width = 80, text = KIND.text, color = Gray, sort = KIND.sort },
    { key = "cost", label = "Cost", width = 70, justify = "RIGHT", color = White, text = CostText,
      sort = function(row) return row.count end,
      tooltip = "How many of this item it takes; + means the trade takes other costs too: hover a cost to see them all" },
    WHERE("Sold by", 150), MAP, LEADS, Last(STATUS) },
  quests = { NAME, KIND, Count("needs", "Needs", 50, function(row) return row.needs or row.count end), WHERE(nil, 140),
    MAP, REWARDS, Last(STATUS) },
  crafting = { NAME, KIND, { key = "profession", label = "Profession", width = 120, color = Gray,
      text = function(row) return Data().Profession(row) or "" end, sort = function(row) return Lower(Data().Profession(row)) end },
    Count("count", "Uses", 60, function(row) return row.count end), PRODUCT, Last(STATUS) },
  sources = { NAME, KIND, WHERE(), MAP, Last(STATUS) },
  -- what each part is for, and other characters' copies, listed and never counted (PI-07)
  takes = { NAME, { key = "for", label = "For", width = 150, color = Gray, text = function(row) return Data().For(row) or "" end,
      sort = function(row) return Lower(Data().For(row)) end },
    Count("need", "Need", 45, PartField("need")), Count("bags", "With you", 60, PartField("bags")),
    Count("bank", "Bank", 45, PartField("bank")), Count("warband", "Warband", 60, PartField("warband")),
    Count("missing", "Missing", 55, PartField("missing")),
    { key = "others", label = "Others", width = 100, color = Gray, text = function(row) return Data().Others(row) or "" end,
      sort = function(row) return Lower(Data().Others(row)) end,
      tooltip = "What your other characters held when last seen: listed, never counted" }, Last(STATUS) },
  gone = { NAME, KIND, Count("count", "Count", 60, function(row) return row.count end), Last(WHERE("Was at", 200)) },
}

local STATUS_DEFS = {
  { key = "s:missing", label = "Still to get or do" },
  { key = "s:have", label = "Already have or done" },
  { key = "s:other", label = "Not for this character" },
  { key = "s:none", label = "Nothing to track" },
}
-- The filter's words for a row kind, where the Kind column's own short
-- word says too little out of its table (Cobanyte, 2026-09-28)
local KIND_WORDS = {
  ["Combines into"] = "What it combines into", Makes = "What it makes", Reagent = "Recipes that use it",
  Teaches = "The recipe it teaches", ["Teaches how to make"] = "What its recipe makes",
  ["Your recipes"] = "Your known recipes", ["Alt's scan"] = "Your other characters' recipes",
  Objective = "Quest objectives", ["Used in"] = "Quests that use it", Starts = "Quests it starts",
  Achievement = "Achievements", Linked = "Linked achievements", Treasure = "Treasures it opens",
  Spot = "Spots it's used at", ["Used at"] = "NPCs it's used at", ["Takes it as payment"] = "Vendors that take it",
  Currency = "Currencies", Endeavor = "Neighborhood endeavors",
  ["Drops from"] = "Creatures that drop it", ["Boss loot"] = "Boss loot", ["Zone drop"] = "Drops anywhere in a zone",
  ["World drop"] = "Drops anywhere in the world", ["Sold by"] = "Vendors that sell it", ["Crafted by"] = "Recipes that craft it",
  ["Found at"] = "Spots it's found at", Reward = "Quest rewards", ["Choice reward"] = "Quest rewards you choose",
  Renown = "Renown rewards", ["Trading Post"] = "Trading Post", ["Made from"] = "Items it's made from",
  ["Crafted with"] = "Recipe items that teach it", ["Black Market"] = "Black Market",
  Use = "What using it takes", Combine = "What combining it takes", ["To craft"] = "What crafting it takes",
  Item = "Other items",
}
local KIND_DEFS = {
  buys = { "Toy", "Mount", "Pet", "Decor", "Ensemble", "Heirloom", "Recipe", "Illusion", "Item" },
  quests = { "Objective", "Used in", "Starts", "Achievement", "Linked", "Treasure", "Spot", "Used at", "Takes it as payment",
    "Currency", "Endeavor" },
  crafting = { "Combines into", "Makes", "Reagent", "Teaches", "Teaches how to make", "Your recipes", "Alt's scan" },
  sources = { "Drops from", "Boss loot", "Zone drop", "World drop", "Sold by", "Crafted by", "Found at", "Reward",
    "Achievement", "Renown", "Choice reward", "Trading Post", "Made from", "Crafted with", "Black Market" },
  takes = { "Use", "Combine", "To craft" },
}

local filters, searches = {}, {}   -- [tab] = { ["s:missing"] = true }, [tab] = "lowered text"
for _, tab in ipairs({ "buys", "quests", "crafting", "sources", "takes", "gone" }) do filters[tab] = {} end

-- Does a row pass its tab's filters and search? Within a group any checked
-- value passes; across groups every group must
function Detail.Matches(tabKey, row)
  local anyS, okS, anyK, okK = false, false, false, false
  for key in pairs(filters[tabKey] or {}) do
    local group, value = key:sub(1, 1), key:sub(3)
    if group == "s" then
      anyS = true
      if row.filterState == value then okS = true end
    elseif group == "k" then
      anyK = true
      if row.kindLabel == value then okK = true end
    end
  end
  if (anyS and not okS) or (anyK and not okK) then return false end
  local text = searches[tabKey]
  if text and text ~= "" then
    local hay = (Data().DisplayName(row) .. " " .. (row.kindLabel or "") .. " " .. (row.sellerText or "")):lower()
    if not hay:find(text, 1, true) then return false end
  end
  return true
end

-------------------------------------------------------------------------------
-- Tabs, the table and the loading bar
-------------------------------------------------------------------------------
local activeTab = "overview"
local lastApply = 0

local function TabIndex(key)
  for i, tab in ipairs(Data().TABS) do
    if tab.key == key then return i end
  end
  return 1
end

local function SortKeyOf(tabKey)
  if not window then return nil end
  local sortKey = window.Table:GetSort(tabKey)
  for _, col in ipairs(COLUMNS[tabKey] or {}) do
    if col.key == sortKey then return col.sort end
  end
  return nil
end

local function UpdateCount(tabKey, n)
  if not window or tabKey ~= activeTab then return end
  local total = job and #job.tabs[tabKey] or 0
  window.Count:SetText(n == total and ("%d shown"):format(n) or ("%d shown of %d"):format(n, total))
end

-- The active table's rows: filtered, and sorted once the rows are all in
-- Each tab's columns fit what it shows (UI.DataTable FitView; Cobanyte,
-- 2026-09-26: every item opens with the columns sized to it, and a column
-- the player sized keeps its width): once its rows are read, and once more
-- after the names load, since a name not loaded yet reads as a placeholder;
-- never on a sort, search or filter
local fitted = {}   -- [tabKey] = { job, stage }
local function FitWidths(tabKey)
  if not job or not job.finished then return end
  local stage = job.namesWarm and 2 or 1
  local f = fitted[tabKey]
  if f and f.job == job and f.stage >= stage then return end
  fitted[tabKey] = { job = job, stage = stage }
  local ok, err = pcall(window.Table.FitView, window.Table, tabKey)
  if not ok then Recollect.Debug.Warn("UI", "Column fit failed: %s", tostring(err)) end
end

local function ApplyView(tabKey)
  if not window or not job or not COLUMNS[tabKey] then return end
  local _, ascending = window.Table:GetSort(tabKey)
  local keyOf = job.finished and SortKeyOf(tabKey) or nil
  Data().Order("order:" .. tabKey, job.tabs[tabKey], keyOf, ascending ~= false,
    function(row) return Detail.Matches(tabKey, row) end,
    function(list)
      window.Table:SetRows(tabKey, list)
      UpdateCount(tabKey, #list)
      FitWidths(tabKey)
    end)
end

-- Tab labels with their counts; a tab with no rows is hidden
local function UpdateTabs()
  if not window then return end
  local previous
  for i, tab in ipairs(Data().TABS) do
    local button = window.Tabs[i]
    local n = tab.key ~= "overview" and job and #job.tabs[tab.key] or nil
    local show = tab.key == "overview" or (n and n > 0) or tab.key == activeTab
    button:SetShown(show and true or false)
    if show then
      button:SetText(n and ("%s (%d)"):format(tab.label, n) or tab.label)
      PanelTemplates_TabResize(button, 0)
      button:ClearAllPoints()
      if previous then
        button:SetPoint("LEFT", previous, "RIGHT", 0, 0)
      else
        button:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 15, 3)
      end
      previous = button
    end
  end
end

local function ShowProgress(done, total, words)
  if not window then return end
  local bar = window.Bar
  if not total or done >= total then
    bar:Hide()
    return
  end
  bar:SetMinMaxValues(0, math.max(total, 1))
  bar:SetValue(done)
  bar.Text:SetText(("%s: %d of %d"):format(words, done, total))
  bar:Show()
end

function Detail.SetTab(key)
  if not window then return end
  activeTab = key
  PanelTemplates_SetTab(window, TabIndex(key))
  local isTable = COLUMNS[key] ~= nil
  window.Overview:SetShown(not isTable)
  window.Table.frame:SetShown(isTable)
  window.Search:SetShown(isTable)
  window.Count:SetShown(isTable)
  for tab, filter in pairs(window.Filters) do filter:SetShown(tab == key) end
  window.TabNote:SetText(Detail.TabNote(key, shown))
  if isTable then
    window.Search:SetText(searches[key] or "")
    window.Table:ShowView(key)
    ApplyView(key)
  else
    PaintOverview()
  end
  UpdateTabs()
end

-------------------------------------------------------------------------------
-- Building the rows for the shown model
-------------------------------------------------------------------------------
local function WarmNames(j)
  local order, t, i, done, total = {}, 1, 0, 0, 0
  for _, tab in ipairs(Data().TABS) do
    if j.tabs[tab.key] then
      order[#order + 1] = j.tabs[tab.key]
      total = total + #j.tabs[tab.key]
    end
  end
  Data().Start("names", function(deadline)
    while order[t] do
      i = i + 1
      local row = order[t][i]
      if not row then
        t, i = t + 1, 0
      else
        done = done + 1
        if not Data().WarmName(row) then
          i = i - 1
          done = done - 1
          ShowProgress(done, total, "Loading names")
          return false
        end
      end
      if Data().Clock() >= deadline then
        ShowProgress(done, total, "Loading names")
        return false
      end
    end
    return true
  end, function()
    ShowProgress(1, 1)
    j.namesWarm = true
    if job == j and activeTab ~= "overview" then ApplyView(activeTab) end
  end, 9)
end

local function OnProgress(j)
  if j ~= job or not window then return end
  ShowProgress(j.done, math.max(j.total, 1), "Reading what it's for")
  local now = seams.Now()
  if j.finished or now - lastApply >= APPLY_EVERY then
    lastApply = now
    UpdateTabs()
    if activeTab ~= "overview" then ApplyView(activeTab) end
  end
  if j.finished then
    ShowProgress(1, 1)
    PaintOverview()
    WarmNames(j)
  end
end

local function CancelJobs()
  local data = Data()
  data.Cancel("build")
  data.Cancel("refresh")
  data.Cancel("names")
  for _, tab in ipairs(data.TABS) do data.Cancel("order:" .. tab.key) end
end

local function StartJob()
  CancelJobs()
  job = nil
  local source = shown and shown.source or {}
  if Recollect.Utilities.IsPositiveID(source.itemID) then
    job = Data().Build(source.itemID, source.stack, source.owner, OnProgress)
  end
end

-------------------------------------------------------------------------------
-- The Curator Flag button (curator spec D35): shown only while curator mode
-- is on, for a model that is an item (a mount's model has no item). What it
-- says comes from the curator's provider, the only way Recollect reaches it.
-------------------------------------------------------------------------------
local FLAG_WIDTH = 96
local JOIN_WIDTH = 150    -- "Want to be a curator?"
local JOIN_TIP = "Curators help Recollect's database grow. With curator mode on, Recollect notes what the game "
  .. "shows you that its database gets wrong or doesn't have yet, as game IDs only, and the author collects it to "
  .. "improve the next version. Click to open the Curator settings, which say exactly what is recorded and turn it on."
local FLAG_TIPS = {
  pending = "Your flag isn't sent yet: click to change it",
  sent = "Your flag was sent; the author hasn't saved it yet. Click to add more information",
  delivered = "Your flag was delivered. Click to add more information",
}

-- FlagButton(model, provider): nil (no button), or { text, tooltip, itemID,
-- join, width }. An item the shipped data says nothing about (the
-- provider's noInfo) reads Request info until it is flagged. With curator
-- mode off the same place offers the curator program (Cobanyte,
-- 2026-09-28): "Want to be a curator?", a click opens the Curator settings.
function Detail.FlagButton(model, provider)
  if model and provider and type(provider.IsEnabled) == "function" then
    local okE, on = pcall(provider.IsEnabled)
    if okE and on == false then
      return { text = "Want to be a curator?", tooltip = JOIN_TIP, join = true, width = JOIN_WIDTH }
    end
  end
  local itemID = model and model.source and model.source.itemID
  if not (itemID and provider and provider.FlagState and provider.OpenFlag) then return nil end
  local ok, state = pcall(provider.FlagState, itemID)
  if not ok or type(state) ~= "table" then return nil end
  if state.flagged then
    return { text = "Flagged", tooltip = FLAG_TIPS[state.state] or FLAG_TIPS.delivered, itemID = itemID }
  end
  if state.noInfo then
    return { text = "Request info", itemID = itemID,
      tooltip = "Recollect's database knows nothing about this item yet. Ask the author to look into it; your own words are optional" }
  end
  return { text = "Curator Flag", itemID = itemID,
    tooltip = "Something missing or wrong here? Flag it for Recollect's author, with a reason and your own words" }
end

local function CuratorProvider()
  return Recollect.CuratorProvider and Recollect.CuratorProvider() or nil
end

local function PaintFlag()
  local flag = Detail.FlagButton(shown, CuratorProvider())
  window.Flag:SetShown(flag ~= nil)
  window.Flag.itemID = flag and flag.itemID or nil
  window.Flag.tip = flag and flag.tooltip or nil
  window.Flag.join = flag and flag.join or nil
  local width = flag and flag.width or FLAG_WIDTH
  window.Flag:SetWidth(width)
  if flag then window.Flag:SetText(flag.text) end
  -- the name and the verdict end left of the header's buttons
  local right = -PAD - 70 - (flag and (width + 6) or 0)
  window.Name:SetPoint("RIGHT", window, "RIGHT", right, 0)
  window.Verdict:SetPoint("RIGHT", window, "RIGHT", right, 0)
end

-------------------------------------------------------------------------------
-- The header strip
-------------------------------------------------------------------------------
-- What the item is, in a few words, for the header of an item not held
-- (Cobanyte, 2026-09-28: "this item is used to gain a mount", "this item goes
-- on the ring slot"): a collection it teaches, the slot it's worn in, the
-- kind of item, else what it's used for; nil when nothing can be read.
-- Read from the game's own answers (Purposes.client), never the tooltip.
local SLOT_WORDS = {
  INVTYPE_HEAD = "Worn in your head slot", INVTYPE_NECK = "Worn in your neck slot",
  INVTYPE_SHOULDER = "Worn in your shoulder slot", INVTYPE_CLOAK = "Worn in your back slot",
  INVTYPE_CHEST = "Worn in your chest slot", INVTYPE_ROBE = "Worn in your chest slot",
  INVTYPE_WRIST = "Worn in your wrist slot", INVTYPE_HAND = "Worn in your hands slot",
  INVTYPE_WAIST = "Worn in your waist slot", INVTYPE_LEGS = "Worn in your legs slot",
  INVTYPE_FEET = "Worn in your feet slot", INVTYPE_FINGER = "Worn in one of your two ring slots",
  INVTYPE_TRINKET = "Worn in one of your two trinket slots",
  INVTYPE_BODY = "A shirt, worn for its look", INVTYPE_TABARD = "A tabard, worn for its look",
  INVTYPE_WEAPON = "A one-handed weapon", INVTYPE_WEAPONMAINHAND = "A main-hand weapon",
  INVTYPE_WEAPONOFFHAND = "An off-hand weapon", INVTYPE_2HWEAPON = "A two-handed weapon",
  INVTYPE_SHIELD = "A shield, held in your off hand", INVTYPE_HOLDABLE = "Held in your off hand",
  INVTYPE_RANGED = "A ranged weapon", INVTYPE_RANGEDRIGHT = "A ranged weapon",
  INVTYPE_PROFESSION_TOOL = "A profession tool, worn in your profession tool slot",
  INVTYPE_PROFESSION_GEAR = "A profession accessory, worn in a profession accessory slot",
  INVTYPE_BAG = "A bag: worn in a bag slot, it gives you more room",
}

-- The item classes the words below name (Enum.ItemClass, with Blizzard's
-- numbers as the fallback)
local ItemClass = Enum and Enum.ItemClass or {}
local CLASS = {
  GEM = ItemClass.Gem or 3, KEY = ItemClass.Key or 13, PROJECTILE = ItemClass.Projectile or 6,
  BATTLEPET = ItemClass.Battlepet or 17, TOKEN = ItemClass.WoWToken or 18, PROFESSION = ItemClass.Profession or 19,
}
-- subclasses: Gem's artifact relics and several stats, Miscellaneous's
-- junk, reagent and holiday, Reagent's keystones
CLASS.GEM_RELIC, CLASS.GEM_MULTIPLE = 11, 10
CLASS.MISC_JUNK, CLASS.MISC_REAGENT, CLASS.MISC_HOLIDAY = 0, 1, 3
CLASS.REAGENT_KEYSTONE = 1

-- What an item's class says it is, for any item: a sentence that stands on
-- its own, or nil (the dump's 65,000 non-gear items, 2026-09-28: gems,
-- keys, holiday items and the rarer classes were left with no words)
local function StrongKind(facts, R)
  local class, sub, subName = facts.classID, facts.subclassID, facts.itemSubType
  -- the second answer: the kind is its own use (wearing, learning,
  -- socketing it), so the explanation never says no use is known
  if class == R.CLASS_HOUSING then return "Decor for your house", true end
  if facts.equipLoc and SLOT_WORDS[facts.equipLoc] then return SLOT_WORDS[facts.equipLoc], true end
  if class == R.CLASS_RECIPE then
    return subName and subName ~= "" and ("Teaches a %s recipe"):format(subName) or "Teaches a recipe", true
  end
  if class == R.CLASS_QUEST then return "A quest item" end
  if class == R.CLASS_GLYPH then return "A glyph: it changes how one of your spells looks or works", true end
  if class == CLASS.GEM then
    if sub == CLASS.GEM_RELIC then return "An artifact relic, from Legion's artifact weapons", true end
    if sub == CLASS.GEM_MULTIPLE then return "A gem: socketed into gear, it adds several stats", true end
    if subName and subName ~= "" and subName ~= "Other" then
      return ("A gem: socketed into gear, it adds %s"):format(subName), true
    end
    return "A gem, socketed into gear", true
  end
  if class == CLASS.KEY then return "A key" end
  if class == CLASS.BATTLEPET then return "A caged battle pet: use it to add the pet to your collection", true end
  if class == CLASS.TOKEN then return "A WoW Token", true end
  if class == CLASS.PROFESSION then return "A profession item" end
  if class == CLASS.PROJECTILE then return "Ammunition, no longer used by the game" end
  if class == R.CLASS_REAGENT and sub == CLASS.REAGENT_KEYSTONE then return "A keystone", true end
  if class == R.CLASS_MISC and sub == CLASS.MISC_HOLIDAY then return "A holiday item" end
  return nil
end

-- Words that say less than what the item is used for: the header prefers
-- the use, the explanation takes these (it counts the uses itself)
local function WeakKind(facts, R)
  local class, sub, subName = facts.classID, facts.subclassID, facts.itemSubType
  if facts.isCraftingReagent then return "A crafting material" end
  if class == R.CLASS_CONSUMABLE then
    if subName and subName ~= "" and subName ~= "Other" and subName ~= "Consumable" then
      return ("A consumable (%s)"):format(subName), true
    end
    return "A consumable", true
  end
  if class == R.CLASS_TRADEGOODS then
    if subName and subName ~= "" and subName ~= "Other" then return ("A crafting material (%s)"):format(subName) end
    return "A crafting material"
  end
  if class == R.CLASS_REAGENT or (class == R.CLASS_MISC and sub == CLASS.MISC_REAGENT) then return "A reagent" end
  if class == R.CLASS_CONTAINER then return "A container" end
  if class == R.CLASS_ENHANCEMENT then return "An item enhancement: it improves a piece of gear", true end
  if class == R.CLASS_MISC and sub == CLASS.MISC_JUNK and facts.quality == 0 then return "Junk, worth a little gold at a vendor" end
  return nil
end

-- kindOnly: what it is alone, never what it's used for, and nil rather
-- than a kind that says nothing ("Miscellaneous: Other"): the explanation
-- that opens WHAT IT'S FOR counts the uses itself (FOR.Explain)
-- PvpLevel(itemID): the item level PvP gear counts as in Arenas and
-- Battlegrounds, from its own tooltip's line (the game's own string,
-- PVP_ITEM_LEVEL_TOOLTIP, any language), or nil
-- (read once per model, kept as model.detailPvp; false when none)
function Detail.PvpLevel(itemID, model)
  if not Recollect.Utilities.IsPositiveID(itemID) then return nil end
  if type(model) == "table" and model.detailPvp ~= nil then return model.detailPvp or nil end
  local tip = ItemTip(model, itemID)
  if not tip then return nil end   -- not read yet: asked again next paint
  local level = tonumber(tip.pvpItemLevel)
  if type(model) == "table" then model.detailPvp = level or false end
  return level
end

function Detail.Describe(itemID, model, kindOnly)
  if not Recollect.Utilities.IsPositiveID(itemID) then return nil end
  local client, Try, IsPositiveID = Recollect.Purposes.client, Recollect.Utilities.Try, Recollect.Utilities.IsPositiveID
  local okMount, mountID = Try(client.GetMountFromItem, itemID)
  if okMount and IsPositiveID(mountID) then return "Teaches a mount for your collection", true end
  local okPet, _, _, _, _, _, _, _, _, _, _, _, _, species = Try(client.GetPetInfoByItemID, itemID)
  if okPet and IsPositiveID(species) then return "Teaches a battle pet for your collection", true end
  local okToy, toy = Try(client.GetToyInfo, itemID)
  if okToy and toy ~= nil then return "A toy for your Toy Box", true end
  local okSet, setID = Try(client.GetItemLearnTransmogSet, itemID)
  if okSet and IsPositiveID(setID) then return "Teaches a set of appearances for your collection", true end
  local facts = Recollect.Facts.Item.Get(itemID)
  local R = Recollect.Purposes.Registry
  local strong, inherent = nil, nil
  if type(facts) == "table" then strong, inherent = StrongKind(facts, R) end
  if strong then return strong, inherent end
  if kindOnly then
    if type(facts) ~= "table" then return nil end
    return WeakKind(facts, R)
  end
  -- what it's used for, as the panel leads with it (a reagent's recipe count, a purchase)
  if type(model) == "table" and type(model.headline) == "string" and model.headline ~= "" then return model.headline end
  local first = type(model) == "table" and type(model.usedFor) == "table" and model.usedFor[1]
  if type(first) == "table" and not first.note and type(first.text) == "string" then return first.text end
  if type(facts) == "table" then
    local weak = WeakKind(facts, R)
    if weak then return weak end
    local kind = facts.itemType
    if kind and facts.itemSubType and facts.itemSubType ~= kind then kind = kind .. ": " .. facts.itemSubType end
    return kind
  end
  return nil
end

-- The Still needed? box (Cobanyte, 2026-09-28): for an item you hold, one
-- suggestion, never a certainty, with a short why: { word, color, why,
-- detail } or nil (an item not held gets none). The answer follows the
-- verdict: a use still open is Keep; Junk is Sell it; Purpose done with the
-- Tip, or a Can't tell whose every use is done (category finished) for an
-- item the research marks as a leftover (Data.Residual), is Likely safe to
-- delete; a finished Can't tell without that mark is Probably done, since a
-- quest may come back (rule 7); Outdated and Lower level say what replaced
-- it; anything else is Can't tell yet with its recovery step.
local function FirstPart(text)
  if type(text) ~= "string" or text == "" then return nil end
  local okS, parts = pcall(Recollect.UI.AuditPanel.Segments, text)
  return okS and type(parts) == "table" and parts[1] or text
end

-- Each answer's icon, all ones Blizzard's own UI uses: a check mark for
-- done, the gold coin for junk, the Great Vault's lock for keep, the dialog
-- alert for a replaced item worth a look, the question mark for can't tell
KEEP_ICONS = {
  done = { atlas = "common-icon-checkmark" },
  sell = { atlas = "coin-gold" },
  keep = { atlas = "ui-journeys-greatvault-lock" },
  check = { file = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew" },
  unknown = { file = "Interface\\Icons\\INV_Misc_QuestionMark" },
  info = { file = "Interface\Icons\INV_Misc_Bag_08" },
}

function Detail.Keep(model)
  if type(model) ~= "table" or model.reference then return nil end
  local result = type(model.result) == "table" and model.result or nil
  if not result then return nil end
  local V, colors = Recollect.Purposes.Registry.Verdict, Recollect.UI.VerdictColors
  local itemID = model.source and model.source.itemID
  local residual = itemID and Recollect.Data and Recollect.Data.Residual and Recollect.Data.Residual[itemID] or nil
  local verdict = result.verdict
  local reason = FirstPart(model.reason) or FirstPart(result.reason)
  -- the panel splits a reason's first words off as its headline ("Buys 3
  -- things from 1 vendor" / "none of them is a collectible"): the band says
  -- them together, never the second half alone
  local whole = reason
  if type(model.headline) == "string" and model.headline ~= "" then
    whole = reason and reason ~= model.headline and (model.headline .. "; " .. reason:gsub("^%u", string.lower))
      or model.headline
  end
  if verdict == V.NEEDED or verdict == V.USE or verdict == V.USEFUL then
    return { word = "Keep it", color = colors[verdict], icon = KEEP_ICONS.keep, why = whole or "It still has a use." }
  end
  if verdict == V.JUNK then
    return { word = "Sell it", color = colors[V.JUNK], icon = KEEP_ICONS.sell, why = "Gray junk: any vendor buys it, and nothing uses it." }
  end
  if verdict == V.DONE then
    if model.tip then
      return { word = "Likely safe to delete", color = colors[V.DONE], icon = KEEP_ICONS.done,
        why = "Every use Recollect knows is done.", detail = model.tip }
    end
    return { word = "Probably done", color = colors[V.DONE], icon = KEEP_ICONS.done, why = reason or "Its uses are done." }
  end
  if verdict == V.UNKNOWN and result.category == "finished" then
    if type(residual) == "table" and type(residual.note) == "string" then
      return { word = "Likely safe to delete", color = colors[V.DONE], icon = KEEP_ICONS.done,
        why = residual.note }   -- the word says every use is done; the note says why it can go
    end
    return { word = "Probably done", color = colors[V.DONE], icon = KEEP_ICONS.done,
      why = "Every use Recollect found is done, but a quest may come back for it." }
  end
  if verdict == V.OUTDATED or verdict == V.LOWER then
    return { word = verdict == V.OUTDATED and "Replaced" or "Lower level", color = colors[verdict], icon = KEEP_ICONS.check,
      why = reason or "You have something better." }
  end
  return { word = "Can't tell yet", color = colors[V.UNKNOWN] or U.Colors.LABEL_GRAY, icon = KEEP_ICONS.unknown,
    why = model.recovery or whole or "Recollect can't read enough about it yet." }
end

-- The kind line under the name: what the item is, its expansion, PvP gear
-- ("Worn in one of your two ring slots · Midnight · PvP gear"); the game's
-- own filing of it when nothing better reads
function Detail.KindLine(model, j)
  local itemID = model and model.source and model.source.itemID
  local parts = {}
  local okD, what = pcall(Detail.Describe, itemID, model, true)
  if okD and what == "A quest item" and FOR.IsToken(j) then what = "A token you spend at vendors" end
  if okD and type(what) == "string" and what ~= "" then parts[#parts + 1] = what end
  local facts = Recollect.Utilities.IsPositiveID(itemID) and Recollect.Facts.Item.Get(itemID) or nil
  if type(facts) == "table" then
    local okE, expansion = pcall(Recollect.Facts.Item.Expansion, facts, itemID)
    if okE and type(expansion) == "number" then
      local okN, name = pcall(Recollect.Purposes.Registry.ExpansionName, expansion)
      if okN and name then parts[#parts + 1] = name end
    end
  end
  local okP, pvp = pcall(Detail.PvpLevel, itemID, model)
  if okP and pvp then parts[#parts + 1] = "PvP gear" end
  if #parts <= (okP and pvp and 1 or 0) and type(model.about) == "table" and model.about[1] then
    return tostring(model.about[1])
  end
  return table.concat(parts, " \194\183 ")
end

-- The answer band (Cobanyte, 2026-09-28, the details window's redesign):
-- the window's one answer, across its whole width on every tab, tinted in
-- the answer's color with a bar of it on the left: the icon, "Still
-- needed?", the answer and its why on one line (two at most; hover for the
-- whole, the verdict's own name, the Tip and "your call"; Cobanyte,
-- 2026-09-28: the verdict's name beside the answer was redundant). An
-- item not held gets how many you have instead, in gray.
local function PaintBand()
  local band = window.Band
  local keep = Detail.Keep(shown)
  local light, gold = U.Colors.LIGHT_GRAY, U.Colors.STATUS_GOLD
  local c, icon, text
  wipe(Hyper.rows.h)
  if keep then
    c = keep.color or U.Colors.HIGHLIGHT_WHITE
    icon = keep.icon or KEEP_ICONS.unknown
    local why = keep.why or ""
    local okLinks, links = pcall(Detail.ReasonLinks, shown)
    why = Hyper.Text(why, okLinks and links or nil, "h")
    text = ("%s  %s   %s"):format(U.WrapColor(Hex(gold), "Still needed?"), U.WrapColor(Hex(c), keep.word),
      U.WrapColor(Hex(light), why))
  else
    -- an item not held (a link, a vendor's, loot): where your copies are, and
    -- that a copy gives the answer
    local source = shown.source or {}
    local okH, held = pcall(Recollect.UI.Tooltip.HeldCounts, source.itemID)
    held = okH and held or nil
    c, icon = U.Colors.LABEL_GRAY, KEEP_ICONS.info
    if held and held.total > 0 then
      local found = {}
      for _, place in ipairs(held.places) do
        if place.count > 0 then found[#found + 1] = place.words:format(place.count) end
      end
      text = ("%s  %s"):format(U.WrapColor(Hex(gold), ("You have %d:"):format(held.total)),
        U.WrapColor(Hex(light), table.concat(found, "; ") .. ". Open one of your copies for whether you still need it."))
    elseif held then
      text = U.WrapColor(Hex(gold), "You don't have this item.")
    else
      text = U.WrapColor(Hex(light), "How many you have can't be read.")
    end
  end
  band.keep = keep
  band.Tint:SetColorTexture(c[1], c[2], c[3], HERO.BAND_TINT)
  band.Bar:SetColorTexture(c[1], c[2], c[3], 1)
  if icon.atlas then band.Icon:SetAtlas(icon.atlas) else band.Icon:SetTexture(icon.file) end
  band.Icon:SetTexCoord(0, 1, 0, 1)
  if icon.file and icon.file:find("Icons") then band.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  band.Text:SetText(text)
  local okH, height = pcall(band.Text.GetStringHeight, band.Text)
  band:SetHeight(math.max(HERO.BAND_MIN, (okH and tonumber(height) or 14) + 2 * HERO.BAND_PAD))
end

-- The header (Cobanyte, 2026-09-28, the redesign): the icon in its
-- quality's frame, the name in that color, and one quiet line of what the
-- item is; the answer band under it. Where the copy is ("Bags", "Linked
-- item") is left out (where the player opened it from isn't about the item)
local function PaintHeader()
  if not window or not shown then return end
  local title = TitleAndWhere(shown)
  local source = shown.source or {}
  local okIcon, icon = pcall(C_Item.GetItemIconByID, source.itemID)
  window.Icon:SetTexture(shown.icon or (okIcon and icon) or 134400)
  window.Name:SetText(title)
  local okQuality, quality = pcall(C_Item.GetItemQualityByID, source.itemID)
  quality = okQuality and quality or nil
  local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  if color then
    window.Name:SetTextColor(color.r, color.g, color.b)
    window.IconFrame:SetColorTexture(color.r, color.g, color.b, 1)
  else
    window.Name:SetTextColor(1, 1, 1)
    local g = U.Colors.DIVIDER_GRAY
    window.IconFrame:SetColorTexture(g[1], g[2], g[3], 1)
  end
  local okK, kind = pcall(Detail.KindLine, shown, job and job.finished and job or nil)
  window.Kind:SetText(okK and kind or "")
  window.Back:SetEnabled(#back > 0)
  window.Forward:SetEnabled(#forward > 0)
  PaintFlag()
  PaintBand()
  window.HeaderEnd:ClearAllPoints()
  window.HeaderEnd:SetPoint("TOPLEFT", window.Band, "BOTTOMLEFT", 0, -HEADER_GAP)
  if activeTab == "overview" then PaintOverview() end
end

-------------------------------------------------------------------------------
-- Rows: tooltips, clicks, the menu
-------------------------------------------------------------------------------
-- the shared Shift-click insert: never into the macro editor, and a chat
-- box opened when none takes the text
local function PutInChat(text)
  CobySuite_Recollect.Chat.PutInChat(text)
end

local function LinkRow(row)
  local link = Data().Link(row)
  if link then
    PutInChat(link)
  else
    Recollect.Utilities.Message("That has no link yet; try again in a moment.")
  end
end

local function Preview(row)
  local link = Data().Link(row)
  if link then pcall(DressUpLink, link) end
end

local function SetWaypoint(place, provider)
  local ok, why = Recollect.UI.Waypoint.Set(place, provider)
  if ok then
    Recollect.Utilities.Message(("%s waypoint set to %s in %s."):format(why == "TomTom" and "TomTom" or "Map",
      place.what or "the place", place.zone or "that zone"))
  else
    Recollect.Utilities.Message.Warn("No waypoint: " .. tostring(why) .. ".")
  end
end

-- The item a row stands for (its own, or a mount's teaching item), opened here
local function OpenRowItem(row)
  local itemID = Data().ItemOf(row)
  if itemID then Detail.OpenItem(itemID) end
end

-- The Copy box: addons can't write to the clipboard, so the text is put in
-- a field, selected, for Ctrl+C; it closes after the copy, on Escape or
-- Enter, or when it loses focus. Built at login (BuildCopy)
function Detail.ShowCopy(text, title)
  local box = window and window.Copy
  if not box or type(text) ~= "string" then return end
  box.Title:SetText((title or "Copy") .. ": press Ctrl+C to copy it")
  box.Field:SetValue(text)
  box:Show()
  box.Field:SelectForCopy()
end

-- The row menu (Cobanyte, 2026-09-28: a traditional right-click menu at
-- the mouse, with sections, like the filter menu): the game's own context
-- menu (MenuUtil, as the column headers' Reset Column Widths), its title the
-- row's name, then what can be done to it; an entry that can't be used is
-- left out, a section with nothing in it too
function Detail.MenuEntries(row)
  local data = Data()
  local entries = {}
  local function Add(section, label, run, sub)
    entries[#entries + 1] = { section = section, label = label, run = run, sub = sub }
  end
  if data.ItemOf(row) then Add("open", "Open its details here", function() OpenRowItem(row) end) end
  if data.Link(row) or row.itemID then Add("open", "Link in chat", function() LinkRow(row) end) end
  if row.itemID or row.what == "mount" then Add("open", "Preview", function() Preview(row) end) end
  -- an achievement: the game's achievement window, opened at it (Cobanyte,
  -- 2026-09-28); Recollect never loads or toggles that window itself
  -- (UI/AchievementPrompt.lua)
  if row.what == "achievement" and Recollect.Utilities.IsPositiveID(row.achievementID) then
    Add("open", "Show Achievement", function() pcall(seams.ShowAchievement, row.achievementID) end)
  end
  local place = data.Place(row)
  if place then
    local Waypoint = Recollect.UI.Waypoint
    local tomtom = Waypoint.TomTomLoaded and Waypoint.TomTomLoaded()
    if tomtom then
      Add("map", "Set a waypoint", nil, {
        { label = "TomTom arrow", run = function() SetWaypoint(place, "tomtom") end },
        { label = "Map pin", run = function() SetWaypoint(place, "game") end },
      })
    else
      Add("map", "Set a waypoint", function() SetWaypoint(place) end)
    end
  end
  local copies = {}
  local url = data.Wowhead(row)
  if url then copies[#copies + 1] = { label = "Wowhead link", run = function() Detail.ShowCopy(url, "Wowhead link") end } end
  local name = data.DisplayName(row)
  if type(name) == "string" and name ~= "" then
    copies[#copies + 1] = { label = "Name", run = function() Detail.ShowCopy(name, "Name") end }
  end
  if #copies > 0 then Add("copy", "Copy", nil, copies) end
  return entries
end

-- The menu's owner must be a frame: Blizzard's menu reads its strata and
-- level (Menu.lua, MenuManagerMixin), which a font string doesn't have, so
-- a link in the Overview's text (whose region is its font string) opened no
-- menu in game (2026-09-28); its frame owns the menu instead
local function MenuOwner(anchor)
  local region = anchor
  for _ = 1, 3 do
    if type(region) ~= "table" then break end
    local ok, isFrame = pcall(function() return region:IsObjectType("Frame") end)
    if ok and isFrame then return region end
    local okP, parent = pcall(function() return region:GetParent() end)
    region = okP and parent or nil
  end
  return window
end
Detail.MenuOwner = MenuOwner

function Detail.ShowRowMenu(row, anchor)
  local entries = Detail.MenuEntries(row)
  if #entries == 0 then return end
  local title = Data().DisplayName(row)
  seams.ContextMenu(MenuOwner(anchor), function(_, root)
    if type(title) == "string" and title ~= "" then root:CreateTitle(title) end
    local section
    for _, entry in ipairs(entries) do
      if section and entry.section ~= section then root:CreateDivider() end
      section = entry.section
      local button = root:CreateButton(entry.label, entry.run)
      for _, sub in ipairs(entry.sub or {}) do button:CreateButton(sub.label, sub.run) end
    end
  end)
end

-- A waypoint button: the world map's pin, lit on hover, darker and a pixel
-- lower while pressed
local function WaypointButton(parent, size)
  local b = CobySuite_Recollect.UI.CreateIconButton(parent, { atlas = PIN_ATLAS, highlightAtlas = PIN_HIGHLIGHT, pushedShade = 0.65,
    size = size })
  local pushed = b:GetPushedTexture()
  if pushed then
    pushed:ClearAllPoints()
    pushed:SetPoint("TOPLEFT", 1, -1)
    pushed:SetPoint("BOTTOMRIGHT", 1, -1)
  end
  return b
end

-- "Durotar (41.2, 18.4)"
local function PlaceText(place)
  return ("%s (%.1f, %.1f)"):format(place.zone or ("map " .. tostring(place.mapID)), place.x * 100, place.y * 100)
end

local function WaypointTooltip(owner, place)
  if not place then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText("Set a waypoint", 1, 1, 1)
  local gray = U.Colors.LABEL_GRAY
  GameTooltip:AddLine(PlaceText(place), gray[1], gray[2], gray[3], true)
  GameTooltip:Show()
end

-- Whether Ctrl-click can preview the row's thing (DressUpLink: gear that
-- can be worn, a mount, housing decor)
local function Previewable(row)
  if row.what == "mount" or row.what == "decor" then return true end
  if not row.itemID then return false end
  local ok, dressable = pcall(seams.Dressable, row.itemID)
  return ok and dressable == true
end

-- What a row's clicks do, one line each, for its tooltip
local function Hints(row, link)
  local hints = {}
  if link then
    hints[#hints + 1] = row.what == "npc" and "Click: open it in the Adventure Guide" or "Click: open its tooltip"
    hints[#hints + 1] = "Shift-click: link in chat"
  elseif row.what == "npc" or row.what == "object" then
    hints[#hints + 1] = "Shift-click: its name, place and map pin in chat"
  end
  if Previewable(row) then hints[#hints + 1] = "Ctrl-click: preview" end
  if Data().ItemOf(row) then hints[#hints + 1] = "Alt-click: its details here" end
  hints[#hints + 1] = "Right-click: more"
  return hints
end

-- The game's own tooltip for the thing, as it is, and what the clicks do
-- under it (Cobanyte, 2026-09-24); a row the game has no tooltip for (an
-- NPC, a spot, a zone, an endeavor task) says what it is and where
local function ThingTooltip(frame, row, anchor)
  local data = Data()
  local GameTooltip = seams.Tooltip()
  GameTooltip:SetOwner(frame, anchor)
  if not data.Tooltip(row, GameTooltip) then
    GameTooltip:SetText(data.DisplayName(row), 1, 1, 1)
    local gray = U.Colors.LABEL_GRAY
    if row.kindLabel or row.stateText then
      GameTooltip:AddLine((row.kindLabel or "") .. (row.stateText and (": " .. row.stateText) or ""), gray[1], gray[2], gray[3])
    end
    if row.kind == "endeavor" then GameTooltip:AddLine(data.Where(row), gray[1], gray[2], gray[3], true) end
    local place = data.Place(row)
    if place then GameTooltip:AddLine(PlaceText(place), gray[1], gray[2], gray[3], true) end
    -- an NPC, as Recollect's own data knows it (Cobanyte, 2026-09-28)
    local white = U.Colors.LIGHT_GRAY
    for _, text in ipairs(Detail.NpcFacts(row)) do GameTooltip:AddLine(text, white[1], white[2], white[3], true) end
  end
  local blue = U.Colors.INFO_BLUE
  for _, hint in ipairs(Hints(row, data.Link(row))) do GameTooltip:AddLine(hint, blue[1], blue[2], blue[3]) end
  GameTooltip:Show()
end

-- Hover (Cobanyte, 2026-09-24): the thing's own tooltip only over the thing
-- itself (its icon and name); over the Where or Sold by cell, who and where
-- in full; anywhere else, nothing
local function OnRowEnter(frame, row, column)
  local data = Data()
  local GameTooltip = seams.Tooltip()
  if column == "where" then
    local where = data.Where(row)
    if not where or where == "" then return GameTooltip:Hide() end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(where, 1, 1, 1, 1, true)
    local place = data.Place(row)
    if place then
      local gray = U.Colors.LABEL_GRAY
      GameTooltip:AddLine(PlaceText(place) .. ": the waypoint button sets a waypoint", gray[1], gray[2], gray[3], true)
    end
    return GameTooltip:Show()
  end
  if column == "cost" and row.count then
    -- every part of the trade, with how many you have (item 9)
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText("What it costs", 1, 1, 1)
    local gray = U.Colors.LABEL_GRAY
    for _, line in ipairs(Detail.CostLines(row)) do
      if line.note then
        GameTooltip:AddLine(line.text, gray[1], gray[2], gray[3], true)
      else
        local have = line.have and ("you have " .. line.have) or "how many you have can't be read"
        GameTooltip:AddLine(("%s  |cFF%s(%s)|r"):format(line.text, Hex(gray), have), 1, 1, 1)
      end
    end
    local owner = shown and shown.source and shown.source.owner
    if type(owner) == "table" and owner.isViewer == false then
      local blue = U.Colors.INFO_BLUE
      GameTooltip:AddLine(("How many you have is %s's, not %s's"):format(seams.ViewerName() or "this character",
        owner.name or "its owner"), blue[1], blue[2], blue[3], true)
    end
    return GameTooltip:Show()
  end
  if column ~= "name" then return GameTooltip:Hide() end
  ThingTooltip(frame, row, "ANCHOR_RIGHT")
end

-- NpcFacts(row): what Recollect's data knows about an NPC or a spot, in
-- words, for its hover: a boss and its dungeon or raid, what a vendor sells
-- (Vendors.ItemsOf), what a treasure holds; {} when nothing
function Detail.NpcFacts(row)
  local out = {}
  local Vendors = Recollect.Facts.Vendors
  if row.npcID then
    local okB, boss = pcall(Vendors.Boss, row.npcID)
    if okB and type(boss) == "table" and boss.instance then out[#out + 1] = ("A boss in %s"):format(boss.instance) end
    local okS, sells = pcall(Vendors.ItemsOf, row.npcID)
    if okS and type(sells) == "table" and #sells > 0 then
      out[#out + 1] = ("A vendor: Recollect knows %d %s sold here"):format(#sells, #sells == 1 and "item" or "items")
    end
  elseif row.objectID then
    local okO, object = pcall(Vendors.Object, row.objectID)
    local n = okO and type(object) == "table" and type(object.contents) == "table" and #object.contents or 0
    if n > 0 then out[#out + 1] = ("A treasure holding %d %s"):format(n, n == 1 and "item" or "items") end
  end
  if Data().Wowhead(row) then out[#out + 1] = "Right-click for a waypoint and its Wowhead link" end
  return out
end

-- ChatText(row): what Shift-click puts in chat (Cobanyte, 2026-09-28:
-- anything, from anywhere in the window): the thing's own game link; an NPC
-- or a spot, which the game can't link, as its name, zone and coordinates
-- and the game's own map pin link (seams.PinLink: never built by hand, since
-- the server drops a whole message whose link it doesn't accept, as a hand-
-- built pin was, 2026-09-28); nil when nothing
function Detail.ChatText(row)
  local data = Data()
  local link = data.ChatLink(row)
  if link then return link end
  if row.what == "quest" then
    -- no link the game will send: its name, in quotes (Cobanyte, 2026-09-28:
    -- a hand-built quest link arrived in guild chat as plain text)
    local name = data.Name(row)
    return type(name) == "string" and name ~= "" and ('"%s"'):format(data.PlainWords(name)) or nil
  end
  local name = data.PlainWords(data.DisplayName(row))
  local place = data.Place(row)
  if not place then return (row.what == "npc" or row.what == "object") and name or nil end
  local words = ("%s (%s %.1f, %.1f)"):format(name, data.PlainWords(place.zone or ("map " .. tostring(place.mapID))),
    place.x * 100, place.y * 100)
  local mapID, x, y = Recollect.UI.Waypoint.Placeable(place.mapID, place.x, place.y)
  if not mapID then return words end
  local ok, pin = pcall(seams.PinLink, mapID, x, y)
  if ok and type(pin) == "string" and pin ~= "" then return words .. " " .. pin end
  return words
end

local function OnRowClick(row, column, mouseButton, frame)
  local modified = seams.AnyModifier()
  if mouseButton == "LeftButton" and seams.ChatLinkClick() then
    local text = Detail.ChatText(row)
    if text then return PutInChat(text) end
  end
  -- an NPC or a spot the game has no link for: a click opens its menu
  if mouseButton == "LeftButton" and not modified and column == "name" and (row.what == "npc" or row.what == "object")
      and not Data().Link(row) then
    return Detail.ShowRowMenu(row, frame)
  end
  if mouseButton == "LeftButton" and seams.OnlyAlt() and Data().ItemOf(row) then return OpenRowItem(row) end
  if mouseButton == "RightButton" and not modified then return Detail.ShowRowMenu(row, frame) end
  if column == "map" and mouseButton == "LeftButton" and not modified then
    local place = Data().Place(row)
    if place then return SetWaypoint(place) end
  end
  local link = Data().Link(row)
  if link then return seams.ItemRef(link, mouseButton) end
  if row.itemID then Recollect.Utilities.Message("That item is still loading; try again in a moment.") end
end

-- A link in the Overview or the header (Links in the text): hover and
-- clicks are its row's, as over the Name cell. Alt-click opens its item here
-- and is no click of the game's (the pin key's click hook never sees it).
-- OnHyperlinkEnter gives the font string the link is in (Blizzard's
-- InlineHyperlinkFrame_OnEnter anchors to it); it is kept for the click,
-- whose extra arguments the generated docs don't list, so the menu opens at
-- the line
function Hyper.Enter(frame, link, _, region)
  Hyper.over = { link = link, region = type(region) == "table" and region or nil }
  local row = Hyper.Row(link)
  if row then ThingTooltip(frame, row, "ANCHOR_CURSOR") end
end

function Hyper.Leave()
  Hyper.over = nil
  seams.Tooltip():Hide()
end

function Hyper.Click(frame, link, _, mouseButton, region)
  local row = Hyper.Row(link)
  if not row then return end
  if mouseButton == "RightButton" then Hyper.lastRight = seams.Now() end
  local over = Hyper.over
  local at = type(region) == "table" and region or (over and over.link == link and over.region) or frame
  OnRowClick(row, "name", mouseButton, at)
end

-- A right-click over a link, in case the game doesn't send a text link's
-- OnHyperlinkClick for the right button (unconfirmed; the Overview's missing
-- menu of 2026-09-28 was its owner, a font string: Detail.MenuOwner): the
-- frame's own mouse-up opens the menu of the link under the cursor
-- (Hyper.over, set on hover), a frame later, so a right-click the game did
-- deliver to the link opens it once.
function Hyper.MouseUp(frame, mouseButton)
  if mouseButton ~= "RightButton" or not Hyper.over then return end
  local over, at = Hyper.over, seams.Now()
  seams.After(0, function()
    if Hyper.lastRight == at or Hyper.over ~= over then return end
    Hyper.Click(frame, over.link, nil, "RightButton", over.region)
  end)
end

-- A frame whose font strings' links are live: its hover and clicks
local function EnableLinks(frame)
  frame:SetHyperlinksEnabled(true)
  frame:SetScript("OnHyperlinkEnter", Hyper.Enter)
  frame:SetScript("OnHyperlinkLeave", Hyper.Leave)
  frame:SetScript("OnHyperlinkClick", Hyper.Click)
  frame:HookScript("OnMouseUp", Hyper.MouseUp)
end

-------------------------------------------------------------------------------
-- Build: every frame, at login (or when combat ends)
-------------------------------------------------------------------------------
local function OnMapClick(self) SetWaypoint(self.place) end

local function BuildHeader()
  -- the item's icon in a frame of its quality's color
  local icon = CreateFrame("Button", nil, window)
  icon:SetSize(HERO.ICON, HERO.ICON)
  icon:SetPoint("TOPLEFT", window, "TOPLEFT", PAD + 2, -TOP - 2)
  window.IconFrame = icon:CreateTexture(nil, "BACKGROUND")
  window.IconFrame:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
  window.IconFrame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
  icon.Texture = icon:CreateTexture(nil, "ARTWORK")
  icon.Texture:SetAllPoints()
  icon.Texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  window.Icon = icon.Texture
  CobySuite_Recollect.UI.AddItemTooltip(icon, function() return shown and shown.source and shown.source.itemID end, "ANCHOR_RIGHT")
  icon:SetScript("OnClick", function()
    local itemID = shown and shown.source and shown.source.itemID
    if not itemID then return end
    local link = Data().Link({ itemID = itemID, what = "item" })
    if link then seams.ItemRef(link, "LeftButton") end
  end)
  -- the name large, and one quiet line of what the item is under it
  window.Name = window:CreateFontString(nil, "OVERLAY", U.Fonts.TITLE)
  window.Name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
  window.Name:SetPoint("RIGHT", window, "RIGHT", -PAD - 70, 0)
  window.Name:SetJustifyH("LEFT")
  window.Name:SetWordWrap(false)
  window.Kind = window:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
  window.Kind:SetPoint("TOPLEFT", window.Name, "BOTTOMLEFT", 0, -4)
  window.Kind:SetPoint("RIGHT", window, "RIGHT", -PAD - 70, 0)
  window.Kind:SetJustifyH("LEFT")
  window.Kind:SetWordWrap(false)
  local gray = U.Colors.LABEL_GRAY
  window.Kind:SetTextColor(gray[1], gray[2], gray[3])
  window.Verdict = window.Kind   -- (PaintFlag ends both lines left of the buttons)
  window.Back = CobySuite_Recollect.UI.CreateButton(window, { text = "<", size = { 28, 22 }, tooltip = "Back to the item before",
    point = { "TOPRIGHT", window, "TOPRIGHT", -PAD - 32, -TOP }, onClick = function() Detail.Back() end })
  window.Forward = CobySuite_Recollect.UI.CreateButton(window, { text = ">", size = { 28, 22 }, tooltip = "Forward again",
    point = { "LEFT", window.Back, "RIGHT", 4, 0 }, onClick = function() Detail.Forward() end })
  window.Flag = CobySuite_Recollect.UI.CreateButton(window, { text = "Curator Flag", size = { FLAG_WIDTH, 22 },
    point = { "RIGHT", window.Back, "LEFT", -6, 0 },
    onClick = function(self)
      if self.join then
        -- the curator program: its settings page says what is recorded
        local Config = Recollect.Config
        if Config and Config.OpenSettingsAt then Config.OpenSettingsAt("curator") end
        return
      end
      local provider = CuratorProvider()
      if self.itemID and provider and provider.OpenFlag then provider.OpenFlag(self.itemID) end
    end })
  CobySuite_Recollect.UI.AddDynamicTooltip(window.Flag, function(tip, self)
    tip:SetText(self:GetText() or "", 1, 1, 1)
    if self.tip then
      tip:AddLine(self.tip, gray[1], gray[2], gray[3], true)
    end
  end)
  window.Flag:Hide()
  -- the answer band (PaintBand): full width under the header, on every tab
  local band = CreateFrame("Frame", nil, window)
  band:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -TOP - HERO.H)
  band:SetPoint("RIGHT", window, "RIGHT", -PAD, 0)
  band:SetHeight(HERO.BAND_MIN)
  band.Tint = band:CreateTexture(nil, "BACKGROUND")
  band.Tint:SetAllPoints()
  band.Bar = band:CreateTexture(nil, "BORDER")
  band.Bar:SetPoint("TOPLEFT")
  band.Bar:SetPoint("BOTTOMLEFT")
  band.Bar:SetWidth(3)
  band.Icon = band:CreateTexture(nil, "ARTWORK")
  band.Icon:SetSize(HERO.BAND_ICON, HERO.BAND_ICON)
  band.Icon:SetPoint("TOPLEFT", band, "TOPLEFT", 12, -HERO.BAND_PAD + 1)
  band.Text = band:CreateFontString(nil, "OVERLAY", U.Fonts.BODY)
  band.Text:SetPoint("TOPLEFT", band.Icon, "TOPRIGHT", 8, -1)
  band.Text:SetPoint("RIGHT", band, "RIGHT", -12, 0)
  band.Text:SetJustifyH("LEFT")
  band.Text:SetWordWrap(true)
  band.Text:SetMaxLines(HERO.BAND_LINES)
  -- the whole why, the verdict, the Tip and the owner's rule on hover
  band:EnableMouse(true)
  band:SetScript("OnEnter", function(self)
    local k = self.keep
    if not k then return end
    local light = U.Colors.LIGHT_GRAY
    local tip = seams.Tooltip()
    tip:SetOwner(self, "ANCHOR_BOTTOM")
    tip:SetText(k.word, (k.color or light)[1], (k.color or light)[2], (k.color or light)[3])
    tip:AddLine(k.why, light[1], light[2], light[3], true)
    local reason = shown and shown.reason
    if type(reason) == "string" and reason ~= "" and reason ~= k.why then
      tip:AddLine(("%s: %s"):format(tostring(shown.label or "Verdict"), reason), light[1], light[2], light[3], true)
    end
    if type(k.detail) == "string" and k.detail ~= "" and k.detail ~= k.why then
      tip:AddLine(k.detail, light[1], light[2], light[3], true)
    end
    local blue = U.Colors.INFO_BLUE
    tip:AddLine("Recollect only suggests; it's always your call.", blue[1], blue[2], blue[3], true)
    tip:Show()
  end)
  band:SetScript("OnLeave", function() seams.Tooltip():Hide() end)
  EnableLinks(band)   -- the why's names
  window.Band = band
  window.Reason = band.Text   -- the Overview repeats the reason when the band had to cut it
  -- where the toolbar and the tables start: below the band, however tall it wrapped
  window.HeaderEnd = CreateFrame("Frame", nil, window)
  window.HeaderEnd:SetSize(1, 1)
  window.HeaderEnd:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, -HEADER_GAP)
  EnableLinks(window)
end

local function BuildToolbar()
  -- the loading bar along the bottom edge, under the Overview and the tables,
  -- clear of the resize grip
  local bar = CreateFrame("StatusBar", nil, window)
  bar:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", PAD, 2)
  bar:SetPoint("RIGHT", window, "RIGHT", -PAD - 18, 0)
  bar:SetHeight(11)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  local blue = U.Colors.INFO_BLUE
  bar:SetStatusBarColor(blue[1], blue[2], blue[3], 0.8)
  bar.Bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.Bg:SetAllPoints()
  bar.Bg:SetColorTexture(0, 0, 0, 0.5)
  bar.Text = bar:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
  bar.Text:SetPoint("CENTER")
  bar:Hide()
  window.Bar = bar
  local search = CobySuite_Recollect.UI.CreateSearchBox(window, { width = 200, point = { "TOPLEFT", window.HeaderEnd, "TOPLEFT", 6, -2 },
    onSearch = function(text)
      searches[activeTab] = text and text:lower() or ""
      ApplyView(activeTab)
    end })
  window.Search = search
  window.Filters = {}
  for tab, kinds in pairs(KIND_DEFS) do
    local defs = {}
    for _, def in ipairs(STATUS_DEFS) do defs[#defs + 1] = def end
    for _, kind in ipairs(kinds) do defs[#defs + 1] = { key = "k:" .. kind, label = KIND_WORDS[kind] or kind } end
    local filter = CobySuite_Recollect.UI.CreateFilterButton(window, {
      defs = defs, point = { "LEFT", search, "RIGHT", 8, 0 },
      isChecked = function(key) return filters[tab][key] == true end,
      setChecked = function(key, on)
        filters[tab][key] = on or nil
        ApplyView(tab)
      end,
      onClear = function()
        wipe(filters[tab])
        ApplyView(tab)
      end,
      -- above the window's own layer (DIALOG), where its table rows would cover it
      menu = { name = "RecollectDetailFilter" .. tab, parent = window, strata = "FULLSCREEN_DIALOG" },
      tooltipIdle = "Show only what you still need, what you have, or one kind",
    })
    filter:Hide()
    window.Filters[tab] = filter
  end
  window.Count = window:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
  window.Count:SetPoint("RIGHT", window, "RIGHT", -PAD, 0)
  window.Count:SetPoint("TOP", search, "TOP", 0, -4)
  local gray = U.Colors.LABEL_GRAY
  window.Count:SetTextColor(gray[1], gray[2], gray[3])
  -- a line about the tab's counts: whose they are (PI-07)
  window.TabNote = window:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
  window.TabNote:SetPoint("LEFT", search, "RIGHT", 40, 0)
  window.TabNote:SetPoint("RIGHT", window.Count, "LEFT", -12, 0)
  window.TabNote:SetJustifyH("LEFT")
  window.TabNote:SetWordWrap(false)
  local blue = U.Colors.INFO_BLUE
  window.TabNote:SetTextColor(blue[1], blue[2], blue[3])
end

-- What a tab's counts are: the logged-in character's, never the pinned copy's
-- owner's when that is another character (PI-07, B1)
function Detail.TabNote(tabKey, model)
  local owner = model and model.source and model.source.owner
  if tabKey ~= "takes" or type(owner) ~= "table" or owner.isViewer ~= false then return "" end
  return ("Counted for %s, not %s: %s's own copies are under Others, not counted"):format(seams.ViewerName() or "this character",
    owner.name or "its owner", owner.name or "its owner")
end

-- A container's button (Fold): the plus or minus, the words, a hover shade; its
-- click opens or closes the container, or shows the next slice
Fold.BUTTONS = 16
function Fold.MakeButton(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(200, Fold.HEIGHT)
  b.Arrow = b:CreateTexture(nil, "ARTWORK")
  b.Arrow:SetSize(Fold.ICON, Fold.ICON)
  b.Arrow:SetPoint("LEFT", b, "LEFT", 0, 0)
  b.Arrow:SetAtlas(Fold.COLLAPSED)
  -- brightens under the mouse, as the guide's does
  b.ArrowGlow = b:CreateTexture(nil, "HIGHLIGHT")
  b.ArrowGlow:SetAllPoints(b.Arrow)
  b.ArrowGlow:SetBlendMode("ADD")
  b.ArrowGlow:SetAlpha(0.3)
  b.ArrowGlow:SetAtlas(Fold.COLLAPSED)
  b.Label = b:CreateFontString(nil, "OVERLAY", U.Fonts.BODY)
  b.Label:SetPoint("LEFT", b, "LEFT", Fold.ICON + 6, 0)
  b.Label:SetJustifyH("LEFT")
  b.Label:SetWordWrap(false)
  CobySuite_Recollect.UI.AddHoverHighlight(b)
  b:SetScript("OnClick", function(self) Fold.Click(self.action, self.key) end)
  CobySuite_Recollect.UI.AddDynamicTooltip(b, function(tip, self)
    local open = self.action == "toggle" and Fold.expanded[self.key]
    tip:SetText(self.action == "more" and "Show the next ones here" or (open and "Hide them" or "List them here"), 1, 1, 1)
    local gray = U.Colors.LABEL_GRAY
    tip:AddLine("The tab lists them all, with a search and filters", gray[1], gray[2], gray[3], true)
  end)
  b:Hide()
  return b
end

-- The achievement button (Cobanyte, 2026-09-28: one click, no prompt): an
-- insecure action button whose macro "/click AchievementMicroButton" clicks
-- the micro menu's own button on the secure path, so the game loads and
-- opens its achievement window itself (the repo's taint notes, pitfall 5; a click
-- that runs Recollect's code, a right-click menu's included, would open it
-- tainted); then Recollect selects the row's achievement
-- (AchievementPrompt.AfterSecureClick). With the window already shown the
-- macro is switched off for that click (the micro button toggles, so it
-- would close it) and only the selection runs.
local function AchievementButton(parent, size)
  local b = CreateFrame("Button", nil, parent, "InsecureActionButtonTemplate")
  b:SetSize(size, size)
  b.Icon = b:CreateTexture(nil, "ARTWORK")
  b.Icon:SetAllPoints()
  b.Icon:SetTexture("Interface\\Icons\\Achievement_General")
  b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:RegisterForClicks("LeftButtonUp")
  b:SetAttribute("useOnKeyDown", false)
  b:SetAttribute("type", "macro")
  b:SetAttribute("macrotext", Recollect.UI.AchievementPrompt.MACRO)
  b:SetAttribute("shift-type*", "")
  b:SetAttribute("ctrl-type*", "")
  b:SetAttribute("alt-type*", "")
  b:SetScript("PreClick", function(self)
    self.wasShown = Recollect.UI.AchievementPrompt.seams.Shown()
    self:SetAttribute("type", self.wasShown and "" or "macro")
  end)
  b:SetScript("PostClick", function(self)
    local row = parent.data
    if row then pcall(Recollect.UI.AchievementPrompt.AfterSecureClick, row.achievementID, self.wasShown) end
    self:SetAttribute("type", "macro")
  end)
  return b
end
Detail.AchievementButton = AchievementButton

local function AchievementButtonTooltip(owner)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText("Open in the achievement window", 1, 1, 1)
  local gray = U.Colors.LABEL_GRAY
  GameTooltip:AddLine("The game opens its own achievement window at this achievement.", gray[1], gray[2], gray[3], true)
  GameTooltip:Show()
end

local function BuildBody()
  local utilities = U
  MAP.button.onClick = function(row)
    local place = Data().Place(row)
    if place then SetWaypoint(place) end
  end
  MAP.button.onEnter = function(b, row) WaypointTooltip(b, Data().Place(row)) end
  MAP.button.onAltEnter = function(b) AchievementButtonTooltip(b) end
  -- a cell for every column of the widest tab (What it takes has 9)
  local maxCells = 0
  for _, columns in pairs(COLUMNS) do maxCells = math.max(maxCells, #columns) end
  local t = Recollect.UI.DataTable.Create(window, { name = "RecollectDetailTable", pool = POOL, rowHeight = ROW_HEIGHT,
    maxCells = maxCells, utilities = utilities, persistence = { savedVariable = "RECOLLECT_WINDOW_STATE", path = "detailColumns" },
    onRowClick = OnRowClick, onRowEnter = OnRowEnter, onRowLeave = function() GameTooltip:Hide() end,
    rowButton = function(parent) return WaypointButton(parent, MAP_HEIGHT) end,
    rowAltButton = function(parent) return AchievementButton(parent, MAP_HEIGHT - 2) end,
    onSort = function(tabKey) ApplyView(tabKey) end })
  t.frame:SetPoint("TOPLEFT", window.HeaderEnd, "TOPLEFT", 0, -30)
  t.frame:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, 14)
  for tabKey, columns in pairs(COLUMNS) do
    -- by status where the tab has one, else by name (No longer available)
    local hasStatus = false
    for _, col in ipairs(columns) do if col.key == "status" then hasStatus = true end end
    t:AddView(tabKey, columns, { sortKey = hasStatus and "status" or "name", ascending = true, minStretch = 90 })
  end
  t.frame:Hide()
  window.Table = t
  local overview = CreateFrame("Frame", nil, window)
  overview:SetPoint("TOPLEFT", window.HeaderEnd, "TOPLEFT", 0, 0)
  overview:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, 14)
  local scroll = CreateFrame("ScrollFrame", nil, overview, "UIPanelScrollFrameTemplate")
  scroll.scrollBarHideable = true
  scroll:SetPoint("TOPLEFT", overview, "TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", overview, "BOTTOMRIGHT", -20, 0)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(1, 1)
  scroll:SetScrollChild(child)
  -- the Overview's names are links; a drag there still moves the window
  child:EnableMouse(true)
  EnableLinks(child)
  child:RegisterForDrag("LeftButton")
  child:SetScript("OnDragStart", function()
    local start = window:GetScript("OnDragStart")
    if start then start(window) end
  end)
  child:SetScript("OnDragStop", function()
    local stop = window:GetScript("OnDragStop")
    if stop then stop(window) end
  end)
  overview.Scroll, overview.Child = scroll, child
  window.Overview = overview
  for i = 1, MAP_BUTTONS do
    local b = WaypointButton(child, LINE_MAP)
    b:SetScript("OnClick", OnMapClick)
    b:SetScript("OnEnter", function(self) WaypointTooltip(self, self.place) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    maps[i] = b
  end
  for i = 1, Fold.BUTTONS do folds[i] = Fold.MakeButton(child) end
  for i = 1, TILE_HOVERS do
    local f = CreateFrame("Frame", nil, child)
    f:EnableMouse(true)
    f:SetScript("OnEnter", TileTooltip)
    f:SetScript("OnLeave", function() seams.Tooltip():Hide() end)
    f:Hide()
    tileHovers[i] = f
  end
  for i = 1, Sections.HEADERS do Sections.headers[i] = Sections.MakeHeader(child) end
end

local function BuildTabs()
  window.Tabs = {}
  for i, tab in ipairs(Data().TABS) do
    local b = CreateFrame("Button", WINDOW_NAME .. "Tab" .. i, window, "PanelTabButtonTemplate")
    b:SetText(tab.label)
    b:SetID(i)
    b:SetScript("OnClick", function() Detail.SetTab(tab.key) end)
    PanelTemplates_TabResize(b, 0)
    window.Tabs[i] = b
  end
  window.numTabs = #window.Tabs
  PanelTemplates_SetTab(window, 1)
end

local function BuildCopy()
  local box = CreateFrame("Frame", nil, window, "TooltipBackdropTemplate")
  box:SetFrameStrata("DIALOG")
  box:SetFrameLevel(window:GetFrameLevel() + 30)
  box:SetSize(420, 70)
  box:SetPoint("CENTER", window, "CENTER", 0, 40)
  local title = box:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
  title:SetText("Copy: press Ctrl+C to copy it")
  box.Title = title
  local gold = U.Colors.STATUS_GOLD
  title:SetTextColor(gold[1], gold[2], gold[3])
  box.Field = CobySuite_Recollect.UI.CreateCopyField(box, { height = U.EditBoxHeight.INLINE,
    point = { "TOPLEFT", box, "TOPLEFT", 18, -30 }, tooltip = "Select the link so Ctrl+C copies it" })
  box.Field:SetPoint("RIGHT", box, "RIGHT", -12, 0)
  box.Field:HookScript("OnEditFocusLost", function() box:Hide() end)
  -- the copy happens on the key press itself; the box goes once it's done
  box.Field:HookScript("OnKeyDown", function(_, key)
    if key == "C" and IsControlKeyDown() then
      C_Timer.After(0.1, function()
        box:Hide()
        Recollect.Utilities.Message("Copied.")
      end)
    end
  end)
  box:Hide()
  window.Copy = box
end

local function Build()
  window = CobySuite_Recollect.UI.CreateWindow({
    name = WINDOW_NAME,
    title = "Recollect: Item Details",
    icon = Recollect.ICON,
    width = WIDTH, height = HEIGHT,
    resizable = { minWidth = 620, minHeight = 380, maxWidth = 1400, maxHeight = 240 + POOL * ROW_HEIGHT },
    escapeCloses = true,
    persist = {
      svTable = function() return RECOLLECT_WINDOW_STATE end,
      key = "detail",
      defaults = { point = "CENTER", relPoint = "CENTER", x = 260, y = 0 },
    },
  })
  BuildHeader()
  BuildToolbar()
  BuildBody()
  BuildTabs()
  BuildCopy()
  window:SetScript("OnSizeChanged", function()
    if activeTab == "overview" then PaintOverview() end
  end)
  window:SetScript("OnHide", function()
    CancelJobs()
    job = nil   -- its rows (thousands for Mark of Honor) go with it; opening builds them again
    for _, t in pairs(window.Table.views) do t.rows = {} end
  end)
  window:Hide()
end

-------------------------------------------------------------------------------
-- Opening, history, refreshing
-------------------------------------------------------------------------------
-- Open(model, how): pin a panel model (UI.Tooltip.Model, or a reference
-- model); how is "back" or "forward" when walking the history
function Detail.Open(model, how)
  if not window or type(model) ~= "table" then return false end
  if shown and shown ~= model and how == nil then
    back[#back + 1] = shown
    wipe(forward)
  end
  Fold.ForItem(model)
  shown = model
  nameRepaints = 0
  for tab in pairs(filters) do wipe(filters[tab]) end
  wipe(searches)
  for _, filter in pairs(window.Filters) do filter:Refresh() end
  if not window:IsShown() then
    window:RestoreState()
    window:Show()
  end
  PaintHeader()
  StartJob()
  Detail.SetTab("overview")
  return true
end

-- OpenItem(itemID): that item's details in reference mode (a click on a row)
function Detail.OpenItem(itemID)
  local model = Recollect.UI.Tooltip.ReferenceModel({ id = itemID }, "detail")
  if model then Detail.Open(model) end
end

function Detail.Back()
  if #back == 0 then return end
  forward[#forward + 1] = shown
  Detail.Open(table.remove(back), "back")
end

function Detail.Forward()
  if #forward == 0 then return end
  back[#back + 1] = shown
  Detail.Open(table.remove(forward), "forward")
end

-- A list row's details (UI.ListWindow's row click)
function Detail.OpenRow(entry)
  if type(entry) ~= "table" then return false end
  local ok, model = pcall(Recollect.UI.Tooltip.RowModel, entry, { id = entry.itemID, hyperlink = entry.link })
  if not ok or not model then return false end
  return Detail.Open(model)
end

-- The pinned copy's verdict read again (B3): the header is never older than
-- the tables under it
function Detail.Refresh()
  if not shown then return end
  local ok, model = pcall(Recollect.UI.Tooltip.Rebuild, shown, { keepLines = true })
  if ok and model then
    if model.detailSeason == nil then model.detailSeason = shown.detailSeason end   -- read once per item
    shown = model
  elseif not ok then
    Recollect.Debug.Warn("UI", "Detail view refresh failed: %s", tostring(model))
  end
end

-- Data arriving (names, quest states, a collection learned): the verdict is
-- read again at most every VERDICT_EVERY seconds, every row's state in
-- slices, and the rows on screen repainted
local lastVerdict, trailing = 0, false
local function RefreshShown()
  if not shown or seams.Hidden(window) then return end
  local now = seams.Now()
  if now - lastVerdict >= VERDICT_EVERY then
    lastVerdict = now
    Detail.Refresh()
    PaintHeader()
  elseif not trailing then
    -- the last change of a burst still reaches the verdict (PI-12)
    trailing = true
    seams.After(VERDICT_EVERY - (now - lastVerdict), function()
      trailing = false
      RefreshShown()
    end)
  end
  if job and job.finished then
    Data().Refresh(job, function()
      if activeTab == "overview" then PaintOverview() else ApplyView(activeTab) end
    end)
  end
end
local refresh = U.Coalesce(0.5, RefreshShown)

local listener = {}
function listener:ReceiveEvent()
  refresh:Call()
end

local function OnClick()
  if target then Detail.Open(target) end
end

-- The pin key's click on an item anywhere (a post-hook on the game's
-- HandleModifiedItemClick): link, and itemLocation for a bag, bank or
-- equipped slot
local function OnItemClick(link, itemLocation)
  local chord = ClickChord(Detail.Key())
  if not chord or seams.MouseButton() ~= chord.button then return end
  local shift, ctrl, alt = seams.Modifiers()
  if (shift or false) ~= chord.shift or (ctrl or false) ~= chord.ctrl or (alt or false) ~= chord.alt then return end
  if seams.GameClick() then return end
  local model = Recollect.UI.Tooltip.ClickModel(link, itemLocation)
  if model then Detail.Open(model) end
end

if type(HandleModifiedItemClick) == "function" then
  hooksecurefunc("HandleModifiedItemClick", function(link, itemLocation)
    local ok, err = pcall(OnItemClick, link, itemLocation)
    if not ok then Recollect.Debug.Warn("UI", "Item click failed: %s", tostring(err)) end
  end)
end

button = CreateFrame("Button", BUTTON_NAME, UIParent)
button:Hide()
button:SetScript("OnClick", OnClick)
button:RegisterEvent("PLAYER_REGEN_ENABLED")
button:SetScript("OnEvent", OnCombatEnded)

EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_LOGIN", function()
  local function Ready()
    Build()
    Recollect.EventBus:Register(listener, { Recollect.Events.InventoryChanged })
    -- a flag saved, sent or delivered: the header's Curator Flag button says so
    local flagListener = {}
    function flagListener:ReceiveEvent()
      if window and window:IsShown() and shown then PaintFlag() end
    end
    Recollect.EventBus:Register(flagListener, { Recollect.Events.CuratorNotesChanged })
    -- An item name arriving: the table repaints at once; the Overview, whose
    -- lines are built whole, once a burst of names has settled
    local paintOverview = U.Coalesce(0.2, function()
      if window and window:IsShown() and activeTab == "overview" then PaintOverview() end
    end)
    Data().onItemLoaded = function()
      if not (window and window:IsShown()) then return end
      if activeTab == "overview" then paintOverview:Call() else window.Table:Paint() end
    end
    -- A creature's name not read yet: one repaint a moment later asks again,
    -- at most NAME_REPAINTS times for one shown item (a name that never
    -- comes must not repaint the window forever)
    local repaint = U.Coalesce(2.5, function()
      if not (window and window:IsShown()) then return end
      if activeTab == "overview" then PaintOverview() else window.Table:Paint() end
    end)
    Data().onNameMissed = function()
      if repaint:IsPending() or nameRepaints >= NAME_REPAINTS then return end
      nameRepaints = nameRepaints + 1
      repaint:Call()
    end
  end
  if InCombatLockdown() then
    EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_REGEN_ENABLED", Ready)
  else
    Ready()
  end
end)

Detail._test = {
  FOR = FOR,
  seams = seams,
  Click = OnClick,
  CombatEnded = OnCombatEnded,
  State = function() return { target = target, bound = bound, boundKey = boundKey, clearAfterCombat = clearAfterCombat } end,
  SetState = function(saved)
    saved = type(saved) == "table" and saved or {}
    target, bound, boundKey = saved.target, saved.bound == true, saved.boundKey
    clearAfterCombat = saved.clearAfterCombat == true
  end,
  Shown = function() return shown end,
  SetShown = function(model) shown = model end,
  Columns = COLUMNS,
  KindDefs = KIND_DEFS,
  SourceOrder = SOURCE_ORDER,
  RowLine = function(row, withPlace) return RowLine(row, withPlace) end,
  Filters = filters,
  Searches = searches,
  History = function() return back, forward end,
  Build = function() Build() end,
  Window = function() return window end,
  ActiveTab = function() return activeTab end,
  Job = function() return job end,
  RowEnter = OnRowEnter,
  RefreshShown = RefreshShown,
  Throttle = function() return lastVerdict, trailing end,
  SetThrottle = function(last, pending) lastVerdict, trailing = last or 0, pending == true end,
  RowClick = OnRowClick,
  ItemClick = OnItemClick,
  Hyper = Hyper,
  Gone = Gone,
  Fold = Fold,
  Sections = Sections,
  PaintOverview = function() PaintOverview() end,
}
