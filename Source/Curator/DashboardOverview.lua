-------------------------------------------------------------------------------
-- Curator.Dashboard.Overview(): the dashboard's Overview tab as plain data
-- (the window paints it, UI/Dashboard.lua)
--
-- Built for the questions a curator opens it with, in this order: is it
-- working, what have I found, did the author get it, is anything wrong that
-- I must fix (Cobanyte, 2026-09-28: "put yourself in the use-case of being
-- a curator ... not too hard to scan"). A list of sections, in order:
--   status     the banner: no header, one sentence in the state's color
--              (banner = true, icon, text, color) and three numbers as
--              tiles filling the width (fill = true): waiting, delivered
--              (saved by the author since the history began), the last
--              collection; a running collection's bar and Cancel, a request
--              waiting with Review
--   attention  only when something needs the curator: this character
--              outside the community (Join), the game holding addon
--              messages back, the store near its cap, the author not heard
--              from for STALE_DAYS while findings wait
--   waiting    a tile for each kind with something in it, the empty kinds
--              in one gray line, the store's size (a bar from BAR_FROM of
--              the cap), Show findings
--   collections the last few, newest first, and Show the history
--   connection (shut) this character, where messages to the author go,
--              who may collect and who is online, the send pace, the last
--              message not answered, the connection test (hidden on the
--              author's own character, disabled with its reason until the
--              author's character is known)
--   details    (shut) Provider.Diagnose's lines, the ones /rec curator diag
--              prints
--   recorded   (shut) what curator mode records and never records
-- Each section: { key, title, icon, summary, closed (shut until the player
-- opens it), tiles, fill, lines, bar, buttons, disabled, failed }
--   tiles    { { key, icon, value, label, color, dim, tip = { title, lines =
--            { { left, right } }, note } } }
--   lines    { { text, color, bullet, small } }
--   bar      { share (0 to 1), text, color }
--   buttons  keys of the window's own buttons shown under the section
--            (join, test, review, cancel, history, findings, settings);
--            disabled = { [key] = why } shows one greyed with its reason
-- An icon is a texture path or "atlas:<name>". A builder that fails leaves
-- a section saying so (failed = true) and logs the error, so the rest still
-- shows.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Dashboard = Curator.Dashboard
local U = CobySuite_Recollect.Utilities
local C = U.Colors
local ICONS = Dashboard.ICONS
local Plural = Dashboard.Plural

Dashboard.STALE_DAYS = 14    -- the author not heard from this long, with findings waiting: said plainly
Dashboard.BAR_FROM = 0.25    -- the size bar shows from this share of the cap
Dashboard.FULL_AT = 0.9      -- and near the cap it is also something to know
Dashboard.RECENT = 3         -- collections listed on the Overview

local function Tile(key, icon, value, label, tip, color, dim)
  return { key = key, icon = icon, value = tostring(value), label = label, tip = tip, color = color, dim = dim }
end

local function Tip(title, note, lines)
  return { title = title, note = note, lines = lines or {} }
end

local function Line(text, color, bullet, small)
  return { text = text, color = color, bullet = bullet, small = small }
end

-------------------------------------------------------------------------------
-- Where things stand
-------------------------------------------------------------------------------
-- Recording(): "on", "partly" (combat), "paused" or "off", and why
function Dashboard.Recording()
  local main = Curator.Main
  if not main.IsEnabled() then return "off", "Curator mode is off, so nothing is recorded." end
  if Host.Versions().ok ~= true then
    return "paused", "Recollect's database files failed their check, so nothing is recorded until they match (reinstall Recollect)."
  end
  if main.IsScripted() then return "paused", "A test run is going; recording waits for it to end." end
  if Dashboard.Seam("InCombat") then
    return "partly", "In combat: loot and quests still record; vendors, NPC positions and a few others wait for it to end."
  end
  return "on", "Recording while you play."
end

-- Standing(): what this character is to curator mode: "author" (Owner or
-- Leader: it collects), "curator" (a member), "outside" (not in the
-- community) or "unknown" (the community or its member list can't be read
-- yet, so nothing is said either way)
function Dashboard.Standing()
  local member = Curator.Provider.IsMember()
  if member == false then return "outside" end
  if member == nil then return "unknown" end
  local M = Curator.Membership
  if not M.ReadAt() then return "unknown" end
  if M.MayPull(Curator.Transport.Self()) then return "author" end
  return "curator"
end

-- AuthorName(): the author's character this client heard from, or nil
function Dashboard.AuthorName()
  return Curator.Transport.RouteOf(Curator.Protocol.AUTHOR)
end

-- The newest collection in the history and when it came, or nil
local function Latest()
  local latest = Curator.History.Entries()[1]
  if not latest then return nil end
  return latest, latest.started or latest.asked
end

-- The store's size against its cap: { share, bytes, cap, text }
function Dashboard.SizeInfo()
  local counts = Curator.Store.Counts()
  local bytes = (counts.bytes or 0) + Curator.Store.FrozenBytes()
  local cap = Curator.Const.CAP_BYTES
  local share = math.max(0, math.min(1, bytes / cap))
  return { share = share, bytes = bytes, cap = cap, text = ("%s of %s"):format(Dashboard.Size(bytes), Dashboard.Size(cap)) }
end

-------------------------------------------------------------------------------
-- The status banner
-------------------------------------------------------------------------------
local function Held(c)
  c = type(c) == "table" and c or {}
  return (tonumber(c.findings) or 0) + (tonumber(c.stamps) or 0) + (tonumber(c.notes) or 0)
end

local function Stats(ctx)
  local waiting = ctx.waiting
  local d = Curator.History.Delivered()
  local delivered = d.findings + d.stamps + d.notes
  local since = Dashboard.When(Curator.History.Since())
  local latest, at = Latest()
  local lastTile
  if latest then
    local state, color = Dashboard.HistoryState(latest)
    lastTile = Tile("last", ICONS.collections, Dashboard.Ago(at), "Last collection",
      Tip("Last collection", ("%s, by %s."):format(state, tostring(latest.by or "?")), {
        { "When", Dashboard.When(at) }, { "It held", Plural(Held(latest.contents), "finding") } }), color)
  else
    lastTile = Tile("last", ICONS.collections, "None yet", "Last collection", Tip("Last collection",
      "The author hasn't collected from you yet."), nil, true)
  end
  return {
    Tile("waiting", ICONS.waiting, waiting.total, "Waiting to be sent",
      Tip("Waiting to be sent", "Everything here goes with the author's next collection.", {
        { "Findings", tostring(waiting.findings) }, { "Confirmations", tostring(waiting.stamps) },
        { "Your notes", tostring(waiting.notes) }, { "From older databases", tostring(waiting.older) } }),
      waiting.total > 0 and C.STATUS_GOLD or nil, waiting.total == 0),
    Tile("delivered", ICONS.delivered, delivered, "Delivered",
      Tip("Delivered", ("Saved by the author since %s, in %s."):format(since ~= "" and since or "now",
        Plural(d.collections, "collection")), {
        { "Findings", tostring(d.findings) }, { "Confirmations", tostring(d.stamps) }, { "Your notes", tostring(d.notes) } }),
      delivered > 0 and C.SAGE_GREEN or nil, delivered == 0),
    lastTile,
  }
end

-- The banner's sentence while recording
local function RecordingText(ctx)
  local total = ctx.waiting.total
  if ctx.standing == "author" then
    if total == 0 then return "Recording. Nothing waits; this character is the author, so you collect your own findings." end
    return ("Recording. %s wait for you to collect them: this character is the author."):format(Plural(total, "finding"))
  end
  if total == 0 then return "Recording. Nothing waits to be sent yet." end
  return ("Recording. %s wait for the author's next collection."):format(Plural(total, "finding"))
end

local function StatusSection(ctx)
  local S = Curator.Sharing
  local recording, why = Dashboard.Recording()
  local prompt, status = S.Prompt(), S.Status()
  local section = { key = "status", title = "Status", banner = true, tiles = Stats(ctx), fill = true, lines = {} }
  local lines = section.lines
  if prompt then
    section.icon, section.color = ICONS.wait, C.STATUS_GOLD
    section.text = "The author asks to collect your findings now."
    section.buttons = { "review" }
  elseif status then
    section.icon, section.color = ICONS.wait, C.STATUS_GOLD
    section.text = status.waitingK and "Everything is sent; waiting for the author's client to confirm it arrived."
      or ("Sending your findings to the author: %d of %d parts (%s)."):format(math.min(status.sent, status.total),
        status.total, Dashboard.Size(status.bytes))
    section.bar = { share = status.total > 0 and math.min(1, status.sent / status.total) or 0,
      text = ("%d of %d parts"):format(math.min(status.sent, status.total), status.total), color = C.STATUS_GOLD }
    if status.paused then
      lines[#lines + 1] = Line("Paused while the game holds addon messages back; it goes on by itself.", C.CAUTION_ORANGE)
    end
    section.buttons = { "cancel" }
  elseif recording == "off" then
    section.icon, section.color = ICONS.problem, C.LABEL_GRAY
    section.text = "Curator mode is off: nothing is recorded."
    if ctx.waiting.total > 0 then
      lines[#lines + 1] = Line(("%s you recorded earlier stay here, unsent, until you turn it on again."):format(
        Plural(ctx.waiting.total, "finding")), C.LABEL_GRAY)
    end
    section.buttons = { "settings" }
  elseif recording == "paused" then
    section.icon, section.color = ICONS.problem, C.CAUTION_ORANGE
    section.text = "Paused. " .. why
  else
    section.icon = recording == "on" and ICONS.ok or ICONS.wait
    section.color = recording == "on" and C.SUCCESS_GREEN or C.STATUS_GOLD
    section.text = RecordingText(ctx)
    if recording == "partly" then lines[#lines + 1] = Line(why, C.STATUS_GOLD) end
  end
  if recording ~= "off" and ctx.standing ~= "author" and not prompt and not status then
    local ask = Curator.Config.Get("curator_ask") == true
    lines[#lines + 1] = Line(ask and "Recollect asks you before each collection."
      or "Collections run in the background; a chat line tells you when one starts and ends.", C.LABEL_GRAY, false, true)
  end
  return section
end

-------------------------------------------------------------------------------
-- Needs your attention (only when something does)
-------------------------------------------------------------------------------
local DAY = 86400

local function AttentionSection(ctx)
  if not Curator.Main.IsEnabled() then return nil end
  local lines, buttons = {}, {}
  if ctx.standing == "outside" then
    lines[#lines + 1] = Line("This character isn't in the Recollect Curators community, so the author can't collect from it."
      .. " What it records goes out from your characters that are in it.", C.CAUTION_ORANGE, true)
    buttons[#buttons + 1] = "join"
  end
  if Curator.Transport.Activity() == "lockdown" and not Curator.Sharing.Status() then
    lines[#lines + 1] = Line("The game is holding addon messages back right now (usually during an encounter or a Mythic+ run);"
      .. " the author can't reach you until that ends.", C.STATUS_GOLD, true)
  end
  local size = Dashboard.SizeInfo()
  if size.share >= Dashboard.FULL_AT then
    lines[#lines + 1] = Line(("Your findings use %s: the oldest make room for new ones until the author collects."):format(size.text),
      C.CAUTION_ORANGE, true)
  end
  if ctx.standing == "curator" and ctx.waiting.total > 0 then
    local _, at = Latest()
    local since = at or Curator.History.Since()
    local days = math.floor((ctx.now - (tonumber(since) or ctx.now)) / DAY)
    if days >= Dashboard.STALE_DAYS then
      lines[#lines + 1] = Line((at and "The author last collected %d days ago." or "The author hasn't collected in the %d days since the history began.")
        :format(days) .. " Your findings stay here until they do; there's nothing to do on your side.", C.STATUS_GOLD, true)
    end
  end
  if #lines == 0 then return nil end
  return { key = "attention", title = "Needs your attention", icon = ICONS.attention,
    summary = #lines == 1 and "One thing to know" or (Plural(#lines, "thing") .. " to know"), lines = lines,
    buttons = #buttons > 0 and buttons or nil }
end

-------------------------------------------------------------------------------
-- Waiting to be sent
-------------------------------------------------------------------------------
-- Pending and sent-but-unsaved records by kind: { [kind] = { pending, sent } };
-- an item with no information ("ni:", an addition) under noinfo alone, so
-- the tiles add up to what waits
local function ByKind(db)
  local out = { addition = { 0, 0 }, conflict = { 0, 0 }, notseen = { 0, 0 }, noinfo = { 0, 0 } }
  for id, record in pairs(db.records) do
    local noInfo = type(record.fact) == "string" and record.fact:find("^ni:") ~= nil
    local slot = out[noInfo and "noinfo" or record.kind]
    if slot then
      if db.delivered[id] == record.rev then slot[2] = slot[2] + 1 else slot[1] = slot[1] + 1 end
    end
  end
  local stamps = { 0, 0 }
  for key, stamp in pairs(db.confirms) do
    if db.delivered[key] == stamp.rev then stamps[2] = stamps[2] + 1 else stamps[1] = stamps[1] + 1 end
  end
  return out, stamps
end

-- Notes by kind: { [kind] = { pending, sent } }
local function NotesByKind()
  local notes = Curator.Notes.DB()
  local out = { flag = { 0, 0 }, feedback = { 0, 0 }, error = { 0, 0 } }
  local function Add(kind, entry)
    if entry.state == "pending" then out[kind][1] = out[kind][1] + 1
    elseif entry.state == "sent" then out[kind][2] = out[kind][2] + 1 end
  end
  for _, flag in pairs(notes.flags) do for _, entry in ipairs(flag.entries or {}) do Add("flag", entry) end end
  for _, entry in ipairs(notes.feedback) do Add("feedback", entry) end
  for _, entry in ipairs(notes.errors) do Add("error", entry) end
  return out
end

local function OlderLine(db)
  local versions, n = {}, 0
  for _, block in ipairs(db.frozen) do
    n = n + U.TableCount(type(block.records) == "table" and block.records or {})
      + U.TableCount(type(block.confirms) == "table" and block.confirms or {})
    versions[#versions + 1] = tostring(block.dataVersion or "?")
  end
  if #versions == 0 then return nil end
  local text = n == 1 and "1 finding from an older database (%s) is kept as it was; it goes whole, with a collection of its own."
    or (n .. " findings from older databases (%s) are kept as they were; each database's findings go whole, with a collection of their own.")
  return Line(text:format(table.concat(versions, ", ")), C.LABEL_GRAY, false, true)
end

local function WaitingSection(ctx)
  local db = Curator.Store.DB()
  local kinds, stamps = ByKind(db)
  local notes = NotesByKind()
  local older = { ctx.waiting.older, 0 }
  local defs = {
    { "new", ICONS.new, kinds.addition, "New", "Things the game showed that the database doesn't have." },
    { "different", ICONS.different, kinds.conflict, "Different", "Values the game showed that differ from the database." },
    { "notseen", ICONS.notseen, kinds.notseen, "Not seen", "Things the database lists that the game didn't show you there." },
    { "noinfo", ICONS.noinfo, kinds.noinfo, "No info", "Items Recollect's database knows nothing about." },
    { "confirmed", ICONS.confirmed, stamps, "Confirmed", "What the game showed that matches the database." },
    { "flags", ICONS.flag, notes.flag, "Flags", "Items you flagged from their details window." },
    { "feedback", ICONS.feedback, notes.feedback, "Feedback", "What you wrote with /rec feedback." },
    { "errors", ICONS.error, notes.error, "Errors", "Recollect errors your game showed; they go to the author too." },
    { "older", ICONS.older, older, "Older databases", "Findings made under an earlier database, kept as they were and sent whole." },
  }
  local tiles, none, sent = {}, {}, 0
  for _, def in ipairs(defs) do
    local pair = def[3]
    sent = sent + pair[2]
    if pair[1] > 0 then
      local lines = {}
      if pair[2] > 0 then lines[1] = { "Also sent, waiting for the author", tostring(pair[2]) } end
      tiles[#tiles + 1] = Tile(def[1], def[2], pair[1], def[4], Tip(def[4], def[5], lines), Dashboard.KIND_COLOR[def[1]])
    else
      none[#none + 1] = def[4]
    end
  end
  local lines = {}
  local size = Dashboard.SizeInfo()
  if #tiles == 0 then
    lines[#lines + 1] = Line(ctx.standing == "author" and "Nothing waits. What you record shows here until you collect it."
      or "Nothing waits. What you record shows here until the author collects it.", C.LABEL_GRAY)
  elseif #none > 0 then
    lines[#lines + 1] = Line("None yet: " .. table.concat(none, ", ") .. ".", C.LABEL_GRAY, false, true)
  end
  if sent > 0 then
    lines[#lines + 1] = Line(("%d more %s sent and %s for the author to save %s."):format(sent, sent == 1 and "was" or "were",
      sent == 1 and "waits" or "wait", sent == 1 and "it" or "them"), C.INFO_BLUE, false, true)
  end
  local olderLine = OlderLine(db)
  if olderLine then lines[#lines + 1] = olderLine end
  local bar
  if size.share >= Dashboard.BAR_FROM then
    bar = { share = size.share, text = size.text, color = size.share >= Dashboard.FULL_AT and C.CAUTION_ORANGE or C.INFO_BLUE }
  end
  local total = ctx.waiting.total
  return { key = "waiting", title = "Waiting to be sent", icon = ICONS.waiting,
    summary = (total > 0 and (Plural(total, "finding") .. " waiting") or "Nothing waiting") .. ", " .. size.text,
    size = size, tiles = tiles, bar = bar, lines = lines,
    buttons = (#tiles > 0 or sent > 0) and { "findings" } or nil }
end

-------------------------------------------------------------------------------
-- Collections
-------------------------------------------------------------------------------
local function CollectionsSection()
  local entries = Curator.History.Entries()
  local lines = {}
  for i = 1, math.min(#entries, Dashboard.RECENT) do
    local entry = entries[i]
    local state, color = Dashboard.HistoryState(entry)
    local held = Held(entry.contents)
    lines[#lines + 1] = Line(("%s: %s%s, by %s%s"):format(Dashboard.Ago(entry.started or entry.asked), state,
      held > 0 and (" (" .. Plural(held, "finding") .. ")") or "", tostring(entry.by or "?"), entry.mode == "t" and " (test)" or ""),
      color, true)
  end
  if #entries == 0 then
    lines[1] = Line("No collection yet. When the author collects, each one shows here and on the History tab.", C.LABEL_GRAY)
  elseif #entries > Dashboard.RECENT then
    lines[#lines + 1] = Line(("And %d earlier on the History tab."):format(#entries - Dashboard.RECENT), C.LABEL_GRAY, false, true)
  end
  return { key = "collections", title = "Collections", icon = ICONS.collections,
    summary = entries[1] and (Dashboard.HistoryState(entries[1])) or "None yet", lines = lines,
    buttons = #entries > 0 and { "history" } or nil }
end

-------------------------------------------------------------------------------
-- Connection (shut)
-------------------------------------------------------------------------------
local PACE = { idle = "ready", resting = "ready", moving = "slower while you move", combat = "slowest in combat",
  lockdown = "held back by the game until addon messages are allowed again" }

local function Sum(tbl)
  local n = 0
  for _, v in pairs(tbl or {}) do n = n + (tonumber(v) or 0) end
  return n
end

local function CharacterLine(ctx)
  local T, M = Curator.Transport, Curator.Membership
  local me = tostring(T.Self() or "?")
  local faction = Dashboard.Seam("Faction")
  faction = type(faction) == "string" and (faction .. ", ") or ""
  if ctx.standing == "outside" then return ("This character: %s, %snot in the Recollect Curators community."):format(me, faction) end
  if ctx.standing == "unknown" then return ("This character: %s, %sthe community's member list isn't read yet."):format(me, faction) end
  local role = M.RoleOf(T.Self())
  return ("This character: %s, %s%sin Recollect Curators."):format(me, faction, role and (M.ROLE_NAMES[role] .. " ") or "")
end

local function MembersLine()
  local M = Curator.Membership
  local members, online, authors = 0, 0, {}
  for _, entry in ipairs(M.Roster()) do
    members = members + 1
    if entry.presence == "online" then online = online + 1 end
    if entry.role == M.ROLE.OWNER or entry.role == M.ROLE.LEADER then
      authors[#authors + 1] = ("%s (%s)"):format(entry.name, entry.presence == "online" and "online" or "offline")
    end
  end
  if members == 0 then return nil end
  return ("%d of %d members online; who may collect: %s."):format(online, members,
    #authors > 0 and table.concat(authors, ", ") or "nobody")
end

local function ConnectionSection(ctx)
  local T, S = Curator.Transport, Curator.Sharing
  local author = Dashboard.AuthorName()
  local lines, buttons, disabled = { Line(CharacterLine(ctx), C.LIGHT_GRAY) }, nil, nil
  local summary
  if ctx.standing == "author" then
    summary = "You are the author"
    lines[#lines + 1] = Line("You collect: this character is the author, so your own findings never leave your game.", C.LIGHT_GRAY)
  elseif author then
    summary = "The author is reached by whisper"
    lines[#lines + 1] = Line(("Messages to the author are whispered to %s%s."):format(author,
      S.lastHello and (", last heard from " .. Dashboard.Ago(S.lastHello.at)) or ""), C.LIGHT_GRAY)
  else
    summary = "The author hasn't been in touch this session"
    lines[#lines + 1] = Line("The author hasn't been in touch this session. Until then, what goes to the author is whispered"
      .. " to every Owner and Leader who is online.", C.LIGHT_GRAY)
  end
  local members = MembersLine()
  if members then lines[#lines + 1] = Line(members, C.LIGHT_GRAY) end
  local counts = T.Counts()
  lines[#lines + 1] = Line(("Messages this session: %d received, %d sent; sending is %s."):format(Sum(counts.got),
    Sum(counts.sent), PACE[T.Activity()] or tostring(T.Activity())), C.LIGHT_GRAY)
  if S.lastDropped then
    local d = S.lastDropped
    lines[#lines + 1] = Line(("Last message not answered: %s from %s (%s): %s."):format(tostring(d.kind), tostring(d.sender),
      Dashboard.Ago(d.at), tostring(d.why)), C.CAUTION_ORANGE)
  end
  if ctx.standing == "author" then
    lines[#lines + 1] = Line("The connection test runs from a curator's game, naming your character: /rec curator ping Name-Realm.",
      C.LABEL_GRAY, false, true)
  elseif Curator.Ping then
    buttons = { "test" }
    if not author then
      disabled = { test = "It needs the author's character, which is known once the author's client has been in touch this session." }
      lines[#lines + 1] = Line("The connection test needs the author's character, known once the author's client has been in touch this session.",
        C.LABEL_GRAY, false, true)
    end
  end
  lines[#lines + 1] = Line(("Your characters share one random curator ID: %s."):format(tostring(Curator.Main.CuratorID())),
    C.LABEL_GRAY, false, true)
  return { key = "connection", title = "Connection", icon = ICONS.connection, summary = summary, closed = true,
    lines = lines, buttons = buttons, disabled = disabled }
end

local function DetailsSection()
  local lines = {}
  local ok, diag = pcall(Curator.Provider.Diagnose)
  for _, text in ipairs(ok and diag or { "The connection details can't be read right now." }) do
    lines[#lines + 1] = Line(text, C.LIGHT_GRAY, false, true)
  end
  lines[#lines + 1] = Line("/rec curator diag prints these lines in chat and the debug log, for a bug report.", C.LABEL_GRAY, false, true)
  return { key = "details", title = "Connection details", icon = ICONS.details, summary = "What /rec curator diag reports",
    closed = true, lines = lines }
end

-------------------------------------------------------------------------------
-- What gets recorded (shut)
-------------------------------------------------------------------------------
Dashboard.RECORDED = {
  "Where the game and Recollect's database differ: vendor goods and prices, drops, quest rewards and givers, recipes, combines, where NPCs stand, the Black Market and the Trading Post",
  "Items Recollect's database knows nothing about, wherever you see them, your bags and banks included: the item's ID and where you saw it",
  "Confirmations: what the game showed that matches the database, so the author knows it still holds",
  "Game IDs only, with your character's class, race, level, faction, professions, zone and, where it matters, quest progress",
  "Your notes: items you flag, feedback you write, and Recollect's own errors; only the author reads them",
}
Dashboard.NEVER = {
  "Names, chat, gold, currencies, how many of anything you have, anything else you carry, or who you play with",
  "Anything while curator mode is off",
}

local function RecordedSection()
  local lines = { Line("Recorded", C.HIGHLIGHT_WHITE) }
  for _, text in ipairs(Dashboard.RECORDED) do lines[#lines + 1] = Line(text, C.LIGHT_GRAY, true) end
  lines[#lines + 1] = Line("Never recorded", C.HIGHLIGHT_WHITE)
  for _, text in ipairs(Dashboard.NEVER) do lines[#lines + 1] = Line(text, C.LIGHT_GRAY, true) end
  lines[#lines + 1] = Line("Names on this page are read from your game, in its language; the findings hold IDs only.",
    C.LABEL_GRAY, false, true)
  return { key = "recorded", title = "What gets recorded", icon = ICONS.recorded, closed = true,
    summary = "Game IDs and your own notes; never names, chat, gold or counts", lines = lines, buttons = { "settings" } }
end

-------------------------------------------------------------------------------
-- Overview(): the sections, in order
-------------------------------------------------------------------------------
Dashboard.SECTIONS = {
  { key = "status", title = "Status", build = StatusSection },
  { key = "attention", title = "Needs your attention", build = AttentionSection },
  { key = "waiting", title = "Waiting to be sent", build = WaitingSection },
  { key = "collections", title = "Collections", build = CollectionsSection },
  { key = "connection", title = "Connection", build = ConnectionSection },
  { key = "details", title = "Connection details", build = DetailsSection },
  { key = "recorded", title = "What gets recorded", build = RecordedSection },
}

local function Failed(def, err)
  Host.Log("Curator dashboard section %s failed: %s", def.key, tostring(err))
  return { key = def.key, title = def.title, icon = ICONS.problem, summary = "Can't be shown right now", failed = true,
    lines = { Line("This part hit an error and was left out; /rec debug has the details for a bug report.", C.CAUTION_ORANGE) } }
end

-- The context every builder reads: { waiting, standing, now }
local function Context()
  local ctx = { now = tonumber(Dashboard.Seam("Now")) or 0 }
  local ok, waiting = pcall(Dashboard.Waiting)
  if not ok then
    Host.Log("Curator dashboard: what waits can't be counted: %s", tostring(waiting))
    waiting = { findings = 0, stamps = 0, notes = 0, older = 0, total = 0 }
  end
  ctx.waiting = waiting
  local okS, standing = pcall(Dashboard.Standing)
  ctx.standing = okS and standing or "unknown"
  if not okS then Host.Log("Curator dashboard: this character's standing can't be read: %s", tostring(standing)) end
  return ctx
end

function Dashboard.Overview()
  local ctx = Context()
  local out = {}
  for _, def in ipairs(Dashboard.SECTIONS) do
    local ok, section = pcall(def.build, ctx)
    if not ok then
      out[#out + 1] = Failed(def, section)
    elseif section then
      out[#out + 1] = section
    end
  end
  return out
end
