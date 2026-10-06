-------------------------------------------------------------------------------
-- Curator.Dashboard: what the curator dashboard shows, as plain data (the
-- window, UI/Dashboard.lua, only paints it; Cobanyte 2026-09-28: "/rec
-- curator as the root command ... just informative", then "put yourself in
-- the use-case of being a curator ... not too hard to scan")
--
--   Overview()        the Overview tab (DashboardOverview.lua): a status
--                     banner with three numbers, what needs the curator's
--                     attention (only when something does), what waits to be
--                     sent, the collections, then the connection, its
--                     details and what gets recorded, shut
--   FindingRows()     the Findings tab: one row per finding and stamp, live
--                     and from older databases' frozen blocks, and one per
--                     note (flags, feedback, errors)
--   Filter(rows, filters, search), Sort(rows, key, ascending)
--   FINDING_COLUMNS   the table's columns; their text reads names live
--   HistoryRows(), HISTORY_COLUMNS, HistoryState(entry), HistoryEmpty()
--                     the History tab
--   Waiting()         findings, stamps and notes not sent yet (the title's and Findings tab's count)
--   Ago(at), Short(at) how long ago, in words and in a table cell
-- Everything is read from the curator's modules and the store in use (a
-- suite's sandbox too). Names come from the game in the player's language,
-- through Dashboard.seams; the findings themselves hold IDs only. An NPC's
-- name costs a tooltip read, so rows are built with the ones already read,
-- and the table reads the rest only for the rows on screen (LoadName asks
-- the server for an item it hasn't sent yet, from the paint alone).
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Decode = Curator.Decode
local U = CobySuite_Recollect.Utilities

local Dashboard = {}
Curator.Dashboard = Dashboard

Dashboard.seams = {
  ItemName = function(id) return C_Item.GetItemNameByID(id) end,
  ItemIcon = function(id) return C_Item.GetItemIconByID(id) end,
  LoadItem = function(id) return C_Item.RequestLoadItemDataByID(id) end,
  QuestName = function(id) return C_QuestLog.GetTitleForQuestID(id) end,
  SpellName = function(id) return C_Spell.GetSpellName(id) end,
  CurrencyName = function(id)
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    return info and info.name
  end,
  SkillName = function(id)
    local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(id)
    return info and info.professionName
  end,
  MapName = function(id) return Host.ZoneName(id) end,
  NpcName = function(id) return Host.NpcName(id) end,
  Faction = function() return UnitFactionGroup("player") end,
  InCombat = function() return InCombatLockdown() end,
  Date = function(format, at) return date(format, at) end,
  Now = function() return GetServerTime() end,
}

local function Seam(name, ...)
  local fn = Dashboard.seams[name]
  if not fn then return nil end
  local ok, value = pcall(fn, ...)
  if not ok or Host.IsSecret(value) then return nil end
  return value
end
Dashboard.Seam = Seam

-- Icons: textures Blizzard's own UI names (checked against the 12.1 UI
-- source, 2026-09-28), and "atlas:<name>" for an atlas, which the window
-- sets with SetAtlas (the ready check's marks, ReadyCheck.lua)
local ICONS = "Interface\\Icons\\"
Dashboard.ICONS = {
  ok = "atlas:UI-LFG-ReadyMark", wait = "atlas:UI-LFG-PendingMark", problem = "atlas:UI-LFG-DeclineMark",
  new = ICONS .. "INV_Misc_Note_02", different = ICONS .. "INV_Misc_QuestionMark",
  notseen = ICONS .. "inv_misc_spyglass_03", confirmed = "atlas:UI-LFG-ReadyMark", noinfo = ICONS .. "inv_misc_scrollunrolled01",
  flag = ICONS .. "UI_GreenFlag", feedback = ICONS .. "UI_Chat", error = "atlas:UI-LFG-DeclineMark",
  older = ICONS .. "INV_Scroll_04", waiting = ICONS .. "Inv_misc_bag_08",
  collections = ICONS .. "INV_Misc_PocketWatch_01", delivered = "atlas:UI-LFG-ReadyMark",
  connection = ICONS .. "UI_Chat",
  attention = "atlas:UI-LFG-DeclineMark", recorded = ICONS .. "INV_Scroll_04", details = ICONS .. "INV_MISC_WRENCH_01",
  vendor = ICONS .. "inv_misc_coin_01", loot = ICONS .. "INV_Misc_Bone_Skull_02",
  quest = ICONS .. "Achievement_Quests_Completed_06", crafting = ICONS .. "inv_gizmo_03", place = ICONS .. "inv_misc_map02",
  use = ICONS .. "INV_Misc_Key_05", market = ICONS .. "TradingPostCurrency", other = ICONS .. "INV_Misc_QuestionMark",
  -- the Connection and Connection details tiles
  character = ICONS .. "Achievement_Character_Human_Male", author = ICONS .. "INV_Misc_Book_09",
  members = ICONS .. "INV_Misc_GroupNeedMore", messages = ICONS .. "INV_Letter_15", pace = ICONS .. "Spell_Holy_BorrowedTime",
  addon = ICONS .. "INV_Gizmo_02", database = ICONS .. "INV_Misc_Book_11", never = "atlas:UI-LFG-DeclineMark",
}

-------------------------------------------------------------------------------
-- Names (read live; a miss shows "Item 1234")
-------------------------------------------------------------------------------
local npcNames = {}   -- NPC names read this session (the tooltip read is the costly one)
local asked = {}      -- items asked of the server this session (LoadName)

local NAME_SEAMS = { item = "ItemName", quest = "QuestName", spell = "SpellName", currency = "CurrencyName",
  map = "MapName", skill = "SkillName" }

-- Name(kind, id): the game's name for an ID, or nil
function Dashboard.Name(kind, id)
  if type(id) ~= "number" then return nil end
  if kind == "npc" then
    if npcNames[id] then return npcNames[id] end
    local name = Seam("NpcName", id)
    if type(name) == "string" and name ~= "" then npcNames[id] = name return name end
    return nil
  end
  local seam = NAME_SEAMS[kind]
  local name = seam and Seam(seam, id)
  return type(name) == "string" and name ~= "" and name or nil
end

-- CheapName(kind, id): the same, but an NPC only when already read
function Dashboard.CheapName(kind, id)
  if kind == "npc" then return npcNames[id] end
  return Dashboard.Name(kind, id)
end

-- LoadName(row): asks the server once a session for the item a row on
-- screen is about when its name isn't loaded yet (an item seen once, often
-- one with no information); the next repaint shows the name. Only the
-- table's paint calls it, never a sort or a search.
function Dashboard.LoadName(row)
  local ref = row and (row.source == "note" and row.item and { kind = "item", id = row.item } or (row.decoded and row.decoded.subject))
  if not (ref and ref.kind == "item" and type(ref.id) == "number") or asked[ref.id] then return false end
  if Dashboard.Name("item", ref.id) then return false end
  asked[ref.id] = true
  Seam("LoadItem", ref.id)
  return true
end

local function Now()
  return tonumber(Seam("Now")) or 0
end

-- The dates the tables show: "Sep 23, 14:05"
function Dashboard.When(at)
  if type(at) ~= "number" or at <= 0 then return "" end
  return Seam("Date", "%b %d, %H:%M", at) or ""
end

-- Ago(at): "just now", "5 minutes ago", "3 hours ago", "2 days ago", "Sep 23"
function Dashboard.Ago(at)
  if type(at) ~= "number" or at <= 0 then return "" end
  local seconds = math.max(0, Now() - at)
  if seconds < 60 then return "just now" end
  if seconds < 3600 then
    local n = math.floor(seconds / 60)
    return n == 1 and "a minute ago" or ("%d minutes ago"):format(n)
  end
  if seconds < 86400 then
    local n = math.floor(seconds / 3600)
    return n == 1 and "an hour ago" or ("%d hours ago"):format(n)
  end
  if seconds < 7 * 86400 then
    local n = math.floor(seconds / 86400)
    return n == 1 and "yesterday" or ("%d days ago"):format(n)
  end
  return Seam("Date", "%b %d", at) or ""
end

-- Short(at): the same for a narrow cell: "now", "5m", "3h", "2d", "Sep 23"
function Dashboard.Short(at)
  if type(at) ~= "number" or at <= 0 then return "" end
  local seconds = math.max(0, Now() - at)
  if seconds < 60 then return "now" end
  if seconds < 3600 then return ("%dm"):format(math.floor(seconds / 60)) end
  if seconds < 86400 then return ("%dh"):format(math.floor(seconds / 3600)) end
  if seconds < 7 * 86400 then return ("%dd"):format(math.floor(seconds / 86400)) end
  return Seam("Date", "%b %d", at) or ""
end

local function Plural(n, one, many)
  return ("%d %s"):format(n, n == 1 and one or (many or (one .. "s")))
end
Dashboard.Plural = Plural

-- "3.4 KB", "1 MB", "812 bytes"
function Dashboard.Size(bytes)
  bytes = tonumber(bytes) or 0
  if bytes < 1024 then return Plural(math.floor(bytes), "byte") end
  if bytes >= 1024 * 1024 then
    local mb = bytes / (1024 * 1024)
    return mb == math.floor(mb) and ("%d MB"):format(mb) or ("%.1f MB"):format(mb)
  end
  if bytes >= 10 * 1024 then return ("%d KB"):format(math.floor(bytes / 1024 + 0.5)) end
  return ("%.1f KB"):format(bytes / 1024)
end

local function Count(tbl)
  return U.TableCount(type(tbl) == "table" and tbl or {})
end

-------------------------------------------------------------------------------
-- What is waiting
-------------------------------------------------------------------------------
-- Waiting(): { findings (records), stamps, notes (not sent yet), older
-- (frozen blocks' findings and stamps not acknowledged), total }
function Dashboard.Waiting()
  local db = Curator.Store.DB()
  local pending = Curator.Store.Pending()
  local out = { findings = Count(pending.recs), stamps = Count(pending.confirms), notes = Curator.Notes.Counts().pending,
    older = 0 }
  for _, block in ipairs(db.frozen) do
    -- a block the author turned down isn't sent again, so it doesn't wait
    if not block.awaiting and not block.rejected then out.older = out.older + Count(block.records) + Count(block.confirms) end
  end
  out.total = out.findings + out.stamps + out.notes + out.older
  return out
end

-------------------------------------------------------------------------------
-- The Findings tab
-------------------------------------------------------------------------------
-- The kinds: the table's first column, the filter and the Overview's tiles
-- share these words and colors
Dashboard.KINDS = {
  { key = "new", label = "New", tooltip = "Something the game showed that Recollect's database doesn't have" },
  { key = "different", label = "Different", tooltip = "The game showed another value than the database has" },
  { key = "notseen", label = "Not seen", tooltip = "The database lists it, but the game didn't show it here" },
  { key = "noinfo", label = "No info", tooltip = "An item Recollect's database knows nothing about" },
  { key = "confirmed", label = "Confirmed", tooltip = "The game showed what the database says: a confirmation" },
  { key = "note", label = "Your notes", tooltip = "Flags, feedback and errors" },
}
local KIND_LABEL = {}
for _, kind in ipairs(Dashboard.KINDS) do KIND_LABEL[kind.key] = kind.label end
local RECORD_KIND = { addition = "new", conflict = "different", notseen = "notseen" }
local KIND_COLOR = { new = U.Colors.SUCCESS_GREEN, different = U.Colors.CAUTION_ORANGE, notseen = U.Colors.SLATE_GRAY,
  noinfo = U.Colors.SAND_TAN, confirmed = U.Colors.SAGE_GREEN, note = U.Colors.INFO_BLUE }
Dashboard.KIND_COLOR = KIND_COLOR

Dashboard.STATES = {
  { key = "pending", label = "Waiting", tooltip = "Not sent yet: goes with the author's next collection" },
  { key = "sending", label = "Sending", tooltip = "In the collection being sent now" },
  { key = "sent", label = "Sent", tooltip = "The author has it and hasn't said it's saved yet" },
  { key = "delivered", label = "Saved", tooltip = "A note the author saved (kept here until the next database)" },
  { key = "rejected", label = "Not sent (turned down)", tooltip = "The author turned this down; it isn't sent again unless it changes" },
}
local STATE_LABEL = {}
for _, state in ipairs(Dashboard.STATES) do STATE_LABEL[state.key] = state.label end
local STATE_COLOR = { pending = U.Colors.STATUS_GOLD, sending = U.Colors.INFO_BLUE, sent = U.Colors.LIGHT_GRAY,
  delivered = U.Colors.SAGE_GREEN, rejected = U.Colors.LABEL_GRAY }

local NOTE_KIND = { flag = "Flag", feedback = "Feedback", error = "Error" }

-- The context map a record or stamp was seen on most
local function MapOf(ctx, contexts)
  local best, bestN
  for index, n in pairs(type(ctx) == "table" and ctx or {}) do
    if not bestN or n > bestN then best, bestN = index, n end
  end
  local block = best and type(contexts) == "table" and contexts[best]
  return type(block) == "table" and tonumber(block.map) or nil
end

local function Seen(ctx)
  local n = 0
  for _, count in pairs(type(ctx) == "table" and ctx or {}) do n = n + (tonumber(count) or 0) end
  return n
end

-- The words a row can be found by: its type, IDs and the names read cheaply
local function SearchText(row)
  local parts = { row.typeLabel or "", KIND_LABEL[row.kind] or "", row.older or "", row.noteText or "" }
  local d = row.decoded
  for _, ref in ipairs({ d and d.subject, d and d.source, d and d.other }) do
    if ref then
      parts[#parts + 1] = tostring(ref.id)
      parts[#parts + 1] = Dashboard.CheapName(ref.kind, ref.id) or ""
    end
  end
  if row.map then parts[#parts + 1] = Dashboard.CheapName("map", row.map) or "" end
  if row.source == "note" then
    parts[#parts + 1] = row.item and tostring(row.item) or ""
    parts[#parts + 1] = (row.item and Dashboard.CheapName("item", row.item)) or ""
  end
  return table.concat(parts, " "):lower()
end

local function RecordRow(id, record, contexts, state, older)
  local decoded = Decode.Fact(record.fact)
  local kind = decoded.type == "no-info" and "noinfo" or RECORD_KIND[record.kind] or "new"
  local row = { key = id, source = "record", kind = kind, decoded = decoded,
    typeLabel = decoded.label, group = decoded.group, value = record.value, shipped = record.shipped, fact = record.fact,
    count = Seen(record.ctx), first = record.first, last = record.last, build = record.build,
    map = MapOf(record.ctx, contexts), state = state, older = older }
  row.search = SearchText(row)
  return row
end

local function StampRow(key, stamp, contexts, state, older)
  local decoded = Decode.Stamp(stamp.source)
  local matched = 0
  for _ in tostring(stamp.matched or ""):gmatch("%d+") do matched = matched + 1 end
  local row = { key = key, source = "stamp", kind = "confirmed", decoded = decoded, typeLabel = decoded.label,
    group = decoded.group, matched = matched, total = tonumber(stamp.total) or 0, count = Seen(stamp.ctx),
    first = stamp.first, last = stamp.last, build = stamp.build, map = MapOf(stamp.ctx, contexts), state = state,
    older = older, fact = stamp.source }
  row.search = SearchText(row)
  return row
end

local function NoteState(entry)
  if entry.state == "sent" then return "sent" end
  if entry.state == "delivered" then return "delivered" end
  return "pending"
end

local function NoteRow(key, kind, entry, itemID, current)
  local reason = kind == "flag" and (Curator.Notes.REASON_LABELS[entry.reason] or "Flag") or NOTE_KIND[kind]
  local row = { key = key, source = "note", kind = "note", noteKind = kind, item = itemID, typeLabel = reason,
    group = "note", noteText = entry.text, count = tonumber(entry.count) or 1, last = entry.at, first = entry.at,
    state = NoteState(entry), older = entry.data, build = entry.build }
  -- an entry written under the database in use is not "older"
  if row.older == current then row.older = nil end
  row.search = SearchText(row)
  return row
end

local function Holds(key)
  local sharing = Curator.Sharing
  return sharing and sharing.Holds and sharing.Holds(key) == true
end

local function LiveRows(out, db)
  for id, record in pairs(db.records) do
    local state = Holds(id) and "sending" or (record.rejected == record.rev and "rejected")
      or (db.delivered[id] == record.rev and "sent") or "pending"
    out[#out + 1] = RecordRow(id, record, db.contexts, state, nil)
  end
  for key, stamp in pairs(db.confirms) do
    local state = Holds(key) and "sending" or (stamp.rejected == stamp.rev and "rejected")
      or (db.delivered[key] == stamp.rev and "sent") or "pending"
    out[#out + 1] = StampRow(key, stamp, db.contexts, state, nil)
  end
end

local function FrozenRows(out, db)
  local sharing = Curator.Sharing
  for _, block in ipairs(db.frozen) do
    local state = (sharing and sharing.HoldsBlock and sharing.HoldsBlock(block)) and "sending"
      or (block.rejected and "rejected") or (block.awaiting and "sent") or "pending"
    local older = tostring(block.dataVersion or "?")
    for id, record in pairs(type(block.records) == "table" and block.records or {}) do
      if type(record) == "table" then out[#out + 1] = RecordRow(id, record, block.contexts, state, older) end
    end
    for key, stamp in pairs(type(block.confirms) == "table" and block.confirms or {}) do
      if type(stamp) == "table" then out[#out + 1] = StampRow(key, stamp, block.contexts, state, older) end
    end
  end
end

local function NoteRows(out)
  local notes = Curator.Notes.DB()
  local current = tostring(Host.Versions().data)
  for itemID, flag in pairs(notes.flags) do
    for _, entry in ipairs(flag.entries or {}) do
      out[#out + 1] = NoteRow(("f:%d:%d"):format(itemID, entry.n or 0), "flag", entry, itemID, current)
    end
  end
  for _, entry in ipairs(notes.feedback) do out[#out + 1] = NoteRow("fb:" .. tostring(entry.n), "feedback", entry, nil, current) end
  for _, entry in ipairs(notes.errors) do out[#out + 1] = NoteRow("e:" .. tostring(entry.n), "error", entry, nil, current) end
end

-- FindingRows(): every finding, stamp and note in the store in use
function Dashboard.FindingRows()
  local db = Curator.Store.DB()
  local out = {}
  LiveRows(out, db)
  FrozenRows(out, db)
  NoteRows(out)
  return out
end

-- Filters: { kind = { [key] = true }, group = {...}, state = {...}, older =
-- true }; within a set any checked key matches, the sets combine; search is
-- plain text, any case
function Dashboard.Filter(rows, filters, search)
  filters = filters or {}
  local needle = type(search) == "string" and search:lower():match("^%s*(.-)%s*$") or ""
  local out = {}
  for _, row in ipairs(rows) do
    local keep = true
    for _, field in ipairs({ "kind", "group", "state" }) do
      local set = filters[field]
      if keep and type(set) == "table" and next(set) and not set[row[field]] then keep = false end
    end
    if keep and filters.older and not row.older then keep = false end
    if keep and needle ~= "" then
      -- built again: a name the game has loaded since counts
      row.search = SearchText(row)
      if not row.search:find(needle, 1, true) then keep = false end
    end
    if keep then out[#out + 1] = row end
  end
  return out
end

-- The subject's name and icon as the What column shows them
local function Subject(row)
  if row.source == "note" then
    if row.item then return Decode.Name(Dashboard.Name, "item", row.item) end
    return NOTE_KIND[row.noteKind] or "Note"
  end
  local ref = row.decoded and row.decoded.subject
  if not ref then return row.typeLabel or "?" end
  return Decode.Name(Dashboard.Name, ref.kind, ref.id)
end
Dashboard.Subject = Subject

function Dashboard.Icon(row)
  local ref = row.source == "note" and row.item and { kind = "item", id = row.item } or (row.decoded and row.decoded.subject)
  if ref and ref.kind == "item" then
    local icon = Seam("ItemIcon", ref.id)
    if icon then return icon end
  end
  if row.source == "note" then return Dashboard.ICONS[row.noteKind] or Dashboard.ICONS.feedback end
  return Dashboard.ICONS[row.group] or Dashboard.ICONS.other
end

-- Where it was seen: the source the fact names, else the zone
local function Where(row)
  local ref = row.decoded and row.decoded.source
  if ref then return Decode.Name(Dashboard.Name, ref.kind, ref.id) end
  if row.map then return Decode.Name(Dashboard.Name, "map", row.map) end
  return ""
end
Dashboard.Where = Where

-- What the curator saw, and what the database says
local function SawText(row)
  if row.source == "note" then return (tostring(row.noteText or ""):gsub("\n", " ")) end
  if row.source == "stamp" then
    if (row.total or 0) > 0 then return ("%d of %d match"):format(row.matched or 0, row.total) end
    local n = row.matched or 0
    return n == 1 and "1 entry matches" or ("%d entries match"):format(n)
  end
  return Decode.Value(row.decoded, row.value, Dashboard.Name)
end
Dashboard.SawText = SawText

local function ShippedText(row)
  if row.source == "note" then return "" end
  if row.source == "stamp" then return "Matches" end
  if row.kind == "notseen" then return "Listed" end
  local text = Decode.Shipped(row.decoded, row.shipped, Dashboard.Name)
  if text == "" and row.kind == "new" then return "Not in it" end
  return text
end
Dashboard.ShippedText = ShippedText

-- The Kind cell: a short word, a note by its own kind
local function KindText(row)
  if row.source == "note" then return NOTE_KIND[row.noteKind] or "Note" end
  return KIND_LABEL[row.kind] or ""
end
Dashboard.KindText = KindText

-- The State cell: one word; an older database's finding says so
local function StateText(row)
  local text = STATE_LABEL[row.state] or row.state or ""
  if row.older then text = text .. " (older)" end
  return text
end
Dashboard.StateText = StateText

-- The State in full, for the hover
local function StateWords(row)
  local state = Dashboard.STATES[1]
  for _, s in ipairs(Dashboard.STATES) do if s.key == row.state then state = s end end
  local text = ("%s: %s"):format(state.label, state.tooltip:sub(1, 1):lower() .. state.tooltip:sub(2))
  if row.older then text = text .. (" (recorded under the older database %s, sent whole with a collection of its own)"):format(row.older) end
  return text
end

-- The Findings table's columns (text and sort read the row; color is RGB).
-- Sized for the window at 940 pixels wide (a size a curator may have kept):
-- the fixed columns and What's minimum fit its table, and What takes the rest
-- (TableHeader's fitToWidth; the hover has every cell in full).
Dashboard.FINDING_COLUMNS = {
  { key = "kind", label = "Kind", width = 82, text = KindText, color = function(row) return KIND_COLOR[row.kind] end,
    tooltip = "New, Different, Not seen, No info, Confirmed, or your own note" },
  { key = "what", label = "What", width = 160, stretch = true, icon = Dashboard.Icon, text = Subject,
    load = Dashboard.LoadName, tooltip = "The item, NPC, quest or recipe it's about; names come from your game" },
  { key = "type", label = "Type", width = 100, text = function(row) return row.typeLabel or "" end,
    tooltip = "What kind of fact it is" },
  { key = "where", label = "Where", width = 114, text = Where, tooltip = "The vendor, creature, quest or zone it was seen at" },
  { key = "saw", label = "You saw", width = 130, text = SawText, tooltip = "What the game showed you" },
  { key = "shipped", label = "Database says", width = 108, text = ShippedText,
    tooltip = "What Recollect's database says about it" },
  { key = "count", label = "Seen", width = 40, justify = "RIGHT", text = function(row) return tostring(row.count or 0) end,
    sortValue = function(row) return row.count or 0 end, tooltip = "How many times you saw it" },
  { key = "last", label = "Last", width = 60, justify = "RIGHT", text = function(row) return Dashboard.Short(row.last) end,
    sortValue = function(row) return row.last or 0 end, tooltip = "When you last saw it" },
  { key = "state", label = "State", width = 96, text = StateText,
    color = function(row) return STATE_COLOR[row.state] end,
    tooltip = "Waiting: goes with the next collection. Sent: the author has it, not saved yet. Saved: a note the author kept. (older): from an older database" },
}
Dashboard.FINDINGS_MIN_STRETCH = 160

local function SortValue(col, row)
  local fn = col.sortValue or col.text
  local ok, value = pcall(fn, row)
  if not ok or value == nil then return "" end
  if type(value) == "string" then return value:lower() end
  return value
end

-- Sort(rows, key, ascending, columns, tie): by that column, then by the tie
-- column (What for the Findings, else the first), then by key, so the order
-- never shuffles
function Dashboard.Sort(rows, key, ascending, columns, tie)
  columns = columns or Dashboard.FINDING_COLUMNS
  local col, second = columns[1], columns[1]
  for _, c in ipairs(columns) do
    if c.key == key then col = c end
    if c.key == (tie or (columns == Dashboard.FINDING_COLUMNS and "what")) then second = c end
  end
  local keys = {}
  for _, row in ipairs(rows) do keys[row] = { SortValue(col, row), tostring(SortValue(second, row)), tostring(row.key or "") } end
  table.sort(rows, function(a, b)
    local ka, kb = keys[a], keys[b]
    local va, vb = ka[1], kb[1]
    if type(va) ~= type(vb) then va, vb = tostring(va), tostring(vb) end
    if va ~= vb then
      if ascending then return va < vb end
      return va > vb
    end
    if ka[2] ~= kb[2] then return ka[2] < kb[2] end
    return ka[3] < kb[3]
  end)
  return rows
end

-- The row's hover: everything about it, in lines of { left, right }
function Dashboard.FindingTooltip(row)
  local lines = {}
  local function Add(left, right) if right and right ~= "" then lines[#lines + 1] = { left, right } end end
  Add("Kind", KindText(row))
  Add("Type", row.typeLabel)
  Add("Where", Where(row))
  Add("You saw", SawText(row))
  Add("Database says", ShippedText(row))
  Add("Seen", row.count and tostring(row.count) or nil)
  Add("First seen", Dashboard.When(row.first))
  Add("Last seen", Dashboard.When(row.last))
  Add("Game build", row.build and tostring(row.build) or nil)
  if row.older then Add("Recorded under database", row.older) end
  return { title = Subject(row), note = StateWords(row), lines = lines }
end

-------------------------------------------------------------------------------
-- The History tab
-------------------------------------------------------------------------------
local REFUSED = { busy = "another collection was running", nodata = "your database files failed their check",
  empty = "nothing was waiting", declined = "you declined", pack = "it couldn't be packed",
  toolarge = "it was too large to send", large = "what's left needs a bigger collection, which the author starts by hand" }

-- HistoryState(entry): its state in words, and its color
function Dashboard.HistoryState(entry)
  local state, C = entry.state, U.Colors
  if state == "asked" then
    return entry.prompt and "Waiting for your answer" or "Starting", C.STATUS_GOLD
  elseif state == "sending" then
    local status = Curator.Sharing.Status()
    if status and status.request == entry.request then
      if status.waitingK then return "Sent, waiting for the author's client", C.INFO_BLUE end
      return ("Sending, %d of %d parts"):format(math.min(status.sent, status.total), status.total), C.STATUS_GOLD
    end
    return "Sending", C.STATUS_GOLD
  elseif state == "acknowledged" then
    return "Sent; waiting for the author to save it", C.INFO_BLUE
  elseif state == "saved" then
    return "Saved by the author", C.SAGE_GREEN
  elseif state == "kept" then
    return "Kept by the author for a closer look; removed here", C.LIGHT_GRAY
  elseif state == "rejected" then
    return "Turned down by the author; not sent again unless it changes", C.CAUTION_ORANGE
  elseif state == "lost" then
    return "Lost on the author's side; sent again later", C.CAUTION_ORANGE
  elseif state == "cancelled" then
    return entry.why == "author" and "Cancelled by the author" or "Cancelled by you", C.CAUTION_ORANGE
  elseif state == "refused" then
    local why = REFUSED[entry.why] or tostring(entry.why or "")
    return "Not sent: " .. why, (entry.why == "declined" or entry.why == "empty") and C.LABEL_GRAY or C.CAUTION_ORANGE
  elseif state == "replaced" then
    return "Replaced by a newer request; sent again later", C.LABEL_GRAY
  elseif state == "interrupted" then
    return "Stopped by a reload or logout; sent again later", C.CAUTION_ORANGE
  elseif state == "expired" then
    if entry.why == "prompt" then return "Not answered in time", C.LABEL_GRAY end
    return "No word from the author in 30 days; sent again", C.CAUTION_ORANGE
  end
  return tostring(state or "?"), C.LIGHT_GRAY
end

local function Contents(entry)
  return type(entry.contents) == "table" and entry.contents or {}
end

-- HistoryRows(): one row per entry, newest first
function Dashboard.HistoryRows()
  local out = {}
  for _, entry in ipairs(Curator.History.Entries()) do
    local c = Contents(entry)
    out[#out + 1] = { key = entry.request, entry = entry, at = entry.started or entry.asked or 0,
      by = entry.by, findings = c.findings or 0, stamps = c.stamps or 0, notes = c.notes or 0, bytes = c.bytes or 0 }
  end
  return out
end

local function Numbered(n) return (n and n > 0) and tostring(n) or "" end

Dashboard.HISTORY_COLUMNS = {
  { key = "at", label = "When", width = 110, text = function(row) return Dashboard.When(row.at) end,
    sortValue = function(row) return row.at or 0 end, tooltip = "When the author asked" },
  { key = "by", label = "Collected by", width = 170, text = function(row)
      local by = tostring(row.by or "?")
      if Curator.Protocol.IsTest(row.entry.mode) then by = by .. " (test)" end
      return by
    end, tooltip = "The author's character that asked for it" },
  { key = "state", label = "How it went", width = 240, stretch = true, text = function(row) return (Dashboard.HistoryState(row.entry)) end,
    color = function(row) return select(2, Dashboard.HistoryState(row.entry)) end, tooltip = "How it went" },
  { key = "findings", label = "Findings", width = 70, justify = "RIGHT", text = function(row) return Numbered(row.findings) end,
    sortValue = function(row) return row.findings end, tooltip = "Findings it held: new, different, not seen and no info" },
  { key = "stamps", label = "Confirmed", width = 75, justify = "RIGHT", text = function(row) return Numbered(row.stamps) end,
    sortValue = function(row) return row.stamps end, tooltip = "Confirmations it held" },
  { key = "notes", label = "Notes", width = 55, justify = "RIGHT", text = function(row) return Numbered(row.notes) end,
    sortValue = function(row) return row.notes end, tooltip = "Flags, feedback and errors it held" },
  { key = "bytes", label = "Size", width = 70, justify = "RIGHT", text = function(row)
      return row.bytes > 0 and Dashboard.Size(row.bytes) or ""
    end, sortValue = function(row) return row.bytes end, tooltip = "How much was sent, packed" },
}

local KIND_WORDS = { addition = "new", conflict = "different", notseen = "not seen" }
local NOTE_WORDS = { flag = "flag", feedback = "feedback", error = "error" }

-- "3 new, 1 different", in a fixed order
local function Kinds(map, words, order)
  local parts = {}
  for _, key in ipairs(order) do
    if (map[key] or 0) > 0 then parts[#parts + 1] = ("%d %s"):format(map[key], words[key]) end
  end
  return table.concat(parts, ", ")
end

-- The hover of a History row: what it held and when each step came
function Dashboard.HistoryTooltip(row)
  local entry, c = row.entry, Contents(row.entry)
  local lines = {}
  local function Add(left, right) if right and right ~= "" then lines[#lines + 1] = { left, right } end end
  Add("State", (Dashboard.HistoryState(entry)))
  Add("Findings", Kinds(c.kinds or {}, KIND_WORDS, { "addition", "conflict", "notseen" }))
  local types = {}
  for typeKey, n in pairs(c.types or {}) do
    types[#types + 1] = { label = (Decode.TYPES[typeKey] or Decode.TYPES.unknown).label, n = n }
  end
  table.sort(types, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.label < b.label end)
  for i, t in ipairs(types) do
    if i > 6 then
      local more = #types - 6
      Add("", more == 1 and "and 1 more kind" or ("and %d more kinds"):format(more))
      break
    end
    Add("  " .. t.label, tostring(t.n))
  end
  Add("Confirmations", Numbered(c.stamps))
  Add("Notes", Kinds(c.noteKinds or {}, NOTE_WORDS, { "flag", "feedback", "error" }))
  if c.frozen then Add("From an older database", tostring(c.data or "?")) end
  Add("Size", (c.bytes or 0) > 0 and ("%s in %s"):format(Dashboard.Size(c.bytes), Plural(c.parts or 0, "part")) or nil)
  Add("Asked", Dashboard.When(entry.asked))
  Add("Started", Dashboard.When(entry.started))
  Add("Author has it", Dashboard.When(entry.ack))
  Add("Saved", Dashboard.When(entry.saved))
  Add("Ended", Dashboard.When(entry.ended))
  if entry.localOnly then Add("", "Collected on this client (you are the author)") end
  return { title = "Collection by " .. tostring(entry.by or "?"), lines = lines }
end

-- The line the History tab shows above its table (with entries)
function Dashboard.HistoryIntro()
  local n = #Curator.History.Entries()
  local began = Dashboard.When(Curator.History.Since())
  return ("%s, newest first, since %s. Hover a row for what it held."):format(Plural(n, "collection"), began)
end

-- HistoryEmpty(): the History tab with no entry: { title, lines }, or nil
-- when there are entries
function Dashboard.HistoryEmpty()
  if #Curator.History.Entries() > 0 then return nil end
  local ask = Curator.Config.Get("curator_ask") == true
  local began = Dashboard.When(Curator.History.Since())
  return { title = "No collections yet", lines = {
    "Each time the author collects your findings, it shows here: when, what it held and how it went.",
    ask and "Recollect asks you before each one." or "Collections run in the background, with a chat line when one starts and ends.",
    began ~= "" and ("Kept since %s."):format(began) or nil,
  } }
end

-- Tests: SwapAsked(set) puts a set in place of the items asked of the
-- server this session and returns the one it replaced
Dashboard._test = {}
function Dashboard._test.SwapAsked(set)
  local old = asked
  asked = set or {}
  return old
end
