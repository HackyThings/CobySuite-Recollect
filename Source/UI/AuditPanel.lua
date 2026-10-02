-------------------------------------------------------------------------------
-- UI.AuditPanel: an item's audit, in its own panel beside the item tooltip
--
-- An addon-owned frame with the tooltip look (Blizzard's
-- TooltipBackdropTemplate), built at load and anchored beside GameTooltip:
-- on the side with room, and past a comparison tooltip (ShoppingTooltip1/2)
-- on that side. GameTooltip itself is never changed. It hides itself when
-- the tooltip hides or stops showing the item it was opened for; UI.Tooltip
-- decides when it shows (the configured key held, or always).
--
-- A short summary, never a long list (Cobanyte, 2026-09-28: "This should be
-- just a simple summary of the item, the item details panel is where they
-- go to explore more"). Panel.Compact picks what shows from the model,
-- which the details window reads whole and which stays as UI.Tooltip built
-- it:
--
--   [icon] Recollect                                  Bank tab 2
--   | Useful                                          the verdict, large, its color
--   | Buys 4 decor you don't own: ...                 the reason, one fact a line:
--   |                                                 REASON_PARTS facts, REASON_LINES lines
--   (an Unknown leads with what the item is for instead:
--   | Combine 30 into Shattered Fragments of Val'anyr  large, white, HEADLINE_LINES
--   | You have 4 of the 30 it takes, all in your bank  the reason
--   | Still needed? Can't tell yet                     small, gray)
--   Tip: Every use Recollect read is done (...).      the Tip, whole: its closing words
--     It's most likely safe to sell or delete, but    are the owner's (UI.Tooltip.Tip)
--     that's your call.
--   ------------------------------------------------
--   USED FOR                                          at most MAX_USES lines, still to
--   Objective of "Light Repurposed" (you're on it)    get or do first (UI.UsedFor's
--   Buys 4 decor and 2 pets you don't have, at 4      order); every purchase is one
--     vendors (70 things in all)                      line (model.buySummary), never a
--                                                     "Buys at" group; no details
--   ------------------------------------------------
--   COMES FROM                                        at most MAX_SOURCES lines
--   Reward from "Pink Elekks On Parade" (done)
--   ------------------------------------------------
--   GUIDE NOTES                                       a guide note, when there is room:
--   o Charges the five Runestones of ...              its words and whose they are
--     Guide note; not confirmed in game yet
--   Alt+W: waypoint to the vendor in Silvermoon City  when a vendor is known and
--                                                     the key is bound ("Alt+W after
--                                                     combat: ..." while combat blocks it)
--   Alt+D for everything: pin the full details        the pinned view's key (UI.DetailWindow);
--                                                     "for everything" when anything was
--                                                     left out here
-- The lines of USED FOR, COMES FROM and the guide note are MAX_ENTRIES in
-- all, each wrapped to LINE_LINES lines at most (room for its closing
-- "(state)"), so no item can make the panel tall. Left out here, and shown
-- in the details window's Overview: CHECKS (the deciding check's words are
-- the reason), ABOUT (the kind and expansion: the details window's
-- explanation says it, and shows ABOUT only when it names an added patch), a line's detail, "and N
-- more", the "Also no longer in the game" line (the "Every use ... is gone"
-- line stays: with no use left it is what the item was for, rule 42; only
-- a reason that says it already, the removed check's Outdated, drops it), a
-- guide note's details and state. What is left out is never said to be
-- none: the pin key's line then says "for everything".
-- For an item not held in that slot (reference mode) the verdict block says
-- how many you have instead. An Unknown's verdict block ends with its one
-- recovery step (G-04: "Open your bank once so Recollect can read it again").
-- A long headline is cut by characters, never inside a UTF-8 character (G-08).
-- Names a line uses that the game links (line.links, UI.UsedFor) are colored
-- as their links are (an item by its quality); the panel can't be clicked,
-- so they are only colored here (Panel.Linked). The verdict's reason colors
-- the same names where it uses them (model.links).
-------------------------------------------------------------------------------
local Panel = {}
Recollect.UI.AuditPanel = Panel

local U = CobySuite_Recollect.Utilities

local WIDTH = 300
local PAD = 10
local ICON = 18
local ACCENT = 3                 -- the verdict's color bar beside the verdict and reason
local ACCENT_GAP = 7
local BULLET = 6
local BULLET_INDENT = 14
local GAP = U.Spacing.GROUP_GAP
local LINE_GAP = 3
local SIDE_GAP = 2
local RECHECK = 0.1              -- seconds between side and still-the-same-item checks
local SEGMENT_GAP = 2            -- between the parts of one reason
local HEADLINE_LARGE = 90        -- characters an Unknown's headline may have in the title font
local HEADLINE_MAX = 180         -- and at all

-- The summary's limits (Panel.Compact): what shows, and how far each wraps
local MAX_USES = 3               -- USED FOR lines
local MAX_SOURCES = 2            -- COMES FROM lines
local MAX_ENTRIES = 5            -- USED FOR, COMES FROM and a guide note together
local REASON_PARTS = 3           -- the reason's facts, one a line
local REASON_LINES = 4           -- lines the reason may wrap to in all
local HEADLINE_LINES = 2
local LINE_LINES = 2             -- one USED FOR or COMES FROM line: its "(state)" closes it
local NOTE_LINES = 2             -- a guide note's words, and whose words they are
local RECOVERY_LINES = 2
local HINT_LINES = 2

local frame
local fonts, fontsUsed = {}, 0
local textures, texturesUsed = {}, 0
local owner, ownerGuid, sinceCheck = nil, nil, 0
local cut = false                -- a block of this paint was cut short by its line limit
local painted = { height = 0, trimmed = false }   -- the last paint, for the suites

local seams = {
  PrimaryData = function(tooltip) return tooltip:GetPrimaryTooltipData() end,
  ShoppingTooltips = function() return { ShoppingTooltip1, ShoppingTooltip2 } end,
}

-------------------------------------------------------------------------------
-- Pools: font strings and plain textures, reused on every paint
-------------------------------------------------------------------------------
-- maxLines: how many lines the text may wrap to (the rest cut with "..."),
-- nil for no limit; set on every use, since the string is reused
local function Font(template, color, maxLines)
  fontsUsed = fontsUsed + 1
  local fs = fonts[fontsUsed]
  if not fs then
    fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fonts[fontsUsed] = fs
  end
  fs:SetFontObject(template)
  fs:SetTextColor(color[1], color[2], color[3])
  fs:SetMaxLines(maxLines or 0)
  fs:ClearAllPoints()
  fs:Show()
  return fs
end

local function Texture(color, alpha)
  texturesUsed = texturesUsed + 1
  local tex = textures[texturesUsed]
  if not tex then
    tex = frame:CreateTexture(nil, "ARTWORK")
    textures[texturesUsed] = tex
  end
  tex:SetDesaturated(false)   -- a pooled texture may have been a grayed state icon
  tex:SetVertexColor(1, 1, 1, 1)
  tex:SetColorTexture(color[1], color[2], color[3], alpha or 1)
  tex:ClearAllPoints()
  tex:Show()
  return tex
end

-- A line's state icon (UI.Icons) from the same pool, or nil when it has none
local STATE_ICON = 12
local function StateIcon(kind)
  if not kind or not Recollect.UI.Icons.ATLAS[kind] then return nil end
  local tex = Texture(U.Colors.LIGHT_GRAY)
  Recollect.UI.Icons.Paint(tex, kind)
  tex:SetSize(STATE_ICON, STATE_ICON)
  return tex
end

local function ResetPools()
  for i = 1, fontsUsed do fonts[i]:Hide() end
  for i = 1, texturesUsed do textures[i]:Hide() end
  fontsUsed, texturesUsed = 0, 0
end

-- A wrapped text block at (x, y) of the given width, at most maxLines lines
-- (nil: no limit); returns its height and the font string. A block its
-- limit cut short marks the paint as leaving something out.
local function Block(template, color, text, x, y, width, maxLines)
  local fs = Font(template, color, maxLines)
  fs:SetWidth(width)
  fs:SetText(text)
  fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
  if maxLines then
    local ok, truncated = pcall(fs.IsTruncated, fs)
    if ok and truncated == true then cut = true end
  end
  return fs:GetStringHeight(), fs
end

-- How many lines a block wrapped to (1 when the client can't say)
local function LinesOf(fs)
  local ok, n = pcall(fs.GetNumLines, fs)
  return ok and type(n) == "number" and n > 0 and n or 1
end

-- A reason's parts: reasons join their facts with "; ", and one fact per
-- line reads faster than one long sentence
function Panel.Segments(text)
  local parts = {}
  for part in (tostring(text) .. "; "):gmatch("(.-); ") do
    if part:find("%S") then parts[#parts + 1] = (part:gsub("^%l", string.upper)) end
  end
  return parts
end

local function Divider(y)
  local line = Texture(U.Colors.DIVIDER_GRAY, U.Colors.DIVIDER_GRAY[4])
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
  line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, y)
end

-------------------------------------------------------------------------------
-- What the panel shows: a summary of the model (UI.Tooltip.Model)
-------------------------------------------------------------------------------
-- Whether the reason already says what a closing "Every use Recollect knows
-- is gone from the game: ..." line says (the removed check's Outdated,
-- rule 42, opens with the same words); only such a line is ever skipped
local function SaidByReason(line, reason)
  if not line.every or type(line.text) ~= "string" or type(reason) ~= "string" then return false end
  local lead = line.text:match("^(.-):")
  return lead ~= nil and reason:find(lead, 1, true) ~= nil
end

-- The USED FOR lines to choose from, in the model's order: every purchase
-- as the one summary line (model.buySummary), where the first purchase
-- stood (UI.UsedFor orders by tier, still to get first); true second when
-- something the panel never shows was passed over
local function UseCandidates(model)
  local candidates, summary, placed, passed = {}, model.buySummary, false, false
  for _, line in ipairs(type(model.usedFor) == "table" and model.usedFor or {}) do
    if line.header or line.buy then
      if summary then
        if not placed then
          candidates[#candidates + 1] = summary
          placed = true
        end
      elseif line.header then
        passed = true   -- a seller's heading: its lines stand alone here
      else
        candidates[#candidates + 1] = line
      end
    elseif line.more or (line.gone and not line.every) then
      passed = true
    elseif not (model.headline and line.text == model.headline) and not SaidByReason(line, model.reason) then
      candidates[#candidates + 1] = line   -- a line the headline or the reason says already is not said twice
    end
  end
  -- purchases past the lines the model kept: the summary still stands for them
  if summary and not placed then candidates[#candidates + 1] = summary end
  return candidates, passed
end

-- Up to max of lines into list; true when any was left out or has a detail
local function Take(list, lines, max)
  local left = false
  for i, line in ipairs(lines) do
    if i > max then return true end
    list[i] = line
    if line.detail then left = true end
  end
  return left
end

-- Compact(model): { reason = { parts }, uses = { lines }, sources = { lines },
-- note = a guide note or nil, trimmed } where trimmed says something the
-- model holds is left out here (the pin key's line then says "for
-- everything"). ABOUT is not counted: the details window's explanation says it.
function Panel.Compact(model)
  local out = { reason = {}, uses = {}, sources = {}, note = nil, trimmed = false }
  local parts = Panel.Segments(model.reason)
  for i = 1, math.min(#parts, REASON_PARTS) do out.reason[i] = parts[i] end
  if #parts > REASON_PARTS then out.trimmed = true end
  -- CHECKS: the deciding check's words are the reason; every check is in the details
  if type(model.purposes) == "table" and #model.purposes > 1 then out.trimmed = true end

  local candidates, passed = UseCandidates(model)
  if passed then out.trimmed = true end
  if Take(out.uses, candidates, MAX_USES) then out.trimmed = true end

  -- COMES FROM: its lines in order; a note ("2 ways to get it are no longer
  -- in the game") only when there is nothing else to say
  local regular, notes = {}, {}
  for _, line in ipairs(type(model.comesFrom) == "table" and model.comesFrom or {}) do
    if line.more then
      out.trimmed = true
    elseif line.note then
      notes[#notes + 1] = line
    else
      regular[#regular + 1] = line
    end
  end
  if #regular > 0 and #notes > 0 then out.trimmed = true end
  local room = MAX_ENTRIES - #out.uses
  if Take(out.sources, #regular > 0 and regular or notes, math.min(MAX_SOURCES, room)) then out.trimmed = true end
  room = room - #out.sources

  -- GUIDE NOTES: the first note's words with whose words they are (rule 43)
  local guide = type(model.notes) == "table" and model.notes or {}
  if #guide > 0 then
    if room > 0 then
      out.note = guide[1]
      if #guide > 1 or (type(out.note.details) == "table" and #out.note.details > 0) or out.note.state then
        out.trimmed = true
      end
    else
      out.trimmed = true
    end
  end
  return out
end

-------------------------------------------------------------------------------
-- Painting a model (UI.Tooltip.Model): header, verdict block, summary, keys
-------------------------------------------------------------------------------
local function PaintHeader(model, y)
  frame.Icon:SetTexture(model.icon or 134400)   -- the question-mark icon when there is none
  frame.Icon:ClearAllPoints()
  frame.Icon:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
  local title = Font(U.Fonts.SMALL, U.Colors.HIGHLIGHT_WHITE)
  title:SetWidth(0)
  title:SetText(U.WrapColor(Recollect.BRAND_COLOR, "Recollect"))
  title:SetPoint("LEFT", frame.Icon, "RIGHT", 6, 0)
  if model.where then
    local where = Font(U.Fonts.DATA, U.Colors.LABEL_GRAY)
    where:SetWidth(0)
    where:SetText(model.where)
    where:SetPoint("RIGHT", frame, "TOPRIGHT", -PAD, y - ICON / 2)
  end
  return y - ICON - GAP
end

-- The reason's facts, one a block, REASON_LINES lines in all, the names
-- links holds colored and the done words in the done color with their check
-- (UI.Icons.MarkDone, as the details window's band); returns the height used
local function ReasonBlocks(parts, x, y, width, links, done)
  local top, left = y, REASON_LINES
  for i, part in ipairs(parts) do
    if left <= 0 then
      cut = true
      break
    end
    if i > 1 then y = y - SEGMENT_GAP end
    local text = Recollect.UI.Icons.MarkDone(Panel.Linked(part, links), done, true)
    local height, fs = Block(U.Fonts.BODY, U.Colors.LIGHT_GRAY, text, x, y, width,
      math.min(LINE_LINES, left))
    y = y - height
    left = left - LinesOf(fs)
  end
  return top - y
end

-- The verdict block: the verdict and its reason; for an Unknown, what the
-- item is for, the reason, then the verdict in small print. A long headline
-- (a whole Use line) drops to the body font rather than filling the panel.
local function PaintVerdict(model, compact, y, contentWidth)
  local top = y
  local textX = PAD + ACCENT + ACCENT_GAP
  local textWidth = contentWidth - ACCENT - ACCENT_GAP
  if model.headline then
    local headline = U.Truncate(model.headline, HEADLINE_MAX)
    local font = U.Utf8Length(headline) <= HEADLINE_LARGE and U.Fonts.TITLE or U.Fonts.BODY
    y = y - Block(font, U.Colors.HIGHLIGHT_WHITE, headline, textX, y, textWidth, HEADLINE_LINES) - LINE_GAP
  else
    y = y - Block(U.Fonts.TITLE, model.color, model.label, textX, y, textWidth, HEADLINE_LINES) - LINE_GAP
  end
  y = y - ReasonBlocks(compact.reason, textX, y, textWidth, model.links, model.done)
  if model.verdictNote then
    y = y - LINE_GAP - Block(U.Fonts.DATA, U.Colors.LABEL_GRAY, model.verdictNote, textX, y - LINE_GAP, textWidth, 1)
  end
  if model.recovery then
    y = y - LINE_GAP - Block(U.Fonts.DATA, U.Colors.INFO_BLUE, model.recovery, textX, y - LINE_GAP, textWidth,
      RECOVERY_LINES)
  end
  local bar = Texture(model.color)
  bar:SetWidth(ACCENT)
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, top)
  bar:SetHeight(top - y)
  return y
end

local Hex = U.ColorToHex

-- Linked(text, links): text with each name links holds ({ text, color })
-- in its color, as the game colors its link; longer names first, and a name
-- inside one already colored, or inside a longer word, is left alone (as the
-- details window's links are)
function Panel.Linked(text, links)
  if type(text) ~= "string" or type(links) ~= "table" or #links == 0 then return text end
  local function Word(b) return b ~= nil and (b >= 128 or string.char(b):find("%w") ~= nil) end
  local order = {}
  for _, link in ipairs(links) do
    if type(link.text) == "string" and link.text ~= "" and type(link.color) == "table" then order[#order + 1] = link end
  end
  table.sort(order, function(a, b) return #a.text > #b.text end)
  local spans = {}
  for _, link in ipairs(order) do
    local from = 1
    while true do
      local first, last = text:find(link.text, from, true)
      if not first then break end
      local free = not Word(text:byte(first - 1)) and not Word(text:byte(last + 1))
      for _, span in ipairs(spans) do
        if first <= span[2] and last >= span[1] then
          free = false
          break
        end
      end
      if free then spans[#spans + 1] = { first, last, link.color } end
      from = last + 1
    end
  end
  if #spans == 0 then return text end
  table.sort(spans, function(a, b) return a[1] < b[1] end)
  local out, at = {}, 1
  for _, span in ipairs(spans) do
    out[#out + 1] = text:sub(at, span[1] - 1)
    out[#out + 1] = ("|cFF%s%s|r"):format(Hex(span[3]), text:sub(span[1], span[2]))
    at = span[2] + 1
  end
  out[#out + 1] = text:sub(at)
  return table.concat(out)
end

-- A line's text for the panel: light gray, with only its closing "(state)"
-- in the line's color, so long lines stay easy to read, and the names it
-- uses in their links' colors
function Panel.LineText(line)
  local text = tostring(line.text)
  local head, state = text:match("^(.-)(%b())$")
  local color = line.color
  if not head or type(color) ~= "table" then return Panel.Linked(text, line.links) end
  return ("%s|cFF%s%s|r"):format(Panel.Linked(head, line.links), Hex(color), state)
end

-- A titled list of the summary's lines (USED FOR, COMES FROM), each
-- bulleted in its color and wrapped to LINE_LINES lines at most
local function PaintLines(title, lines, y, contentWidth)
  y = y - GAP
  Divider(y)
  y = y - GAP
  y = y - Block(U.Fonts.SMALL, U.Colors.STATUS_GOLD, title, PAD, y, contentWidth) - LINE_GAP
  local x, w = PAD + BULLET_INDENT, contentWidth - BULLET_INDENT
  for _, line in ipairs(lines) do
    -- a line that states a check or a cross shows its icon in the bullet's place (UI.Icons)
    local icon = StateIcon(Recollect.UI.Icons.FromLine(line))
    if icon then
      icon:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD - 1, y + 1)
    else
      local dot = Texture(line.color or U.Colors.LIGHT_GRAY)
      dot:SetSize(BULLET, BULLET)
      dot:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 2, y - 4)
    end
    y = y - Block(U.Fonts.SMALL, U.Colors.LIGHT_GRAY, Panel.LineText(line), x, y, w, LINE_LINES) - LINE_GAP - 1
  end
  return y
end

-- The Tip under the verdict block: "Tip:" in gold, then its words
function Panel.TipText(tip)
  local label = Recollect.UI.Tooltip and Recollect.UI.Tooltip.TIP_LABEL or "Tip"
  return ("|cFF%s%s:|r %s"):format(U.Colors.TEXT_GOLD, label, tip)
end

-- Painted whole: its closing words are the owner's rule (contract rule 1)
local function PaintTip(model, y, contentWidth)
  y = y - GAP
  return y - Block(U.Fonts.DATA, U.Colors.LIGHT_GRAY, Panel.TipText(model.tip), PAD, y, contentWidth)
end

-- GUIDE NOTES (UI.UsedFor.NoteLines): the note bulleted gray, then whose
-- words they are, never the one without the other (rule 43)
local function PaintNote(note, y, contentWidth)
  y = y - GAP
  Divider(y)
  y = y - GAP
  y = y - Block(U.Fonts.SMALL, U.Colors.STATUS_GOLD, "GUIDE NOTES", PAD, y, contentWidth) - LINE_GAP
  local x, w = PAD + BULLET_INDENT, contentWidth - BULLET_INDENT
  local dot = Texture(note.color or U.Colors.LABEL_GRAY)
  dot:SetSize(BULLET, BULLET)
  dot:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 2, y - 4)
  y = y - Block(U.Fonts.SMALL, U.Colors.LIGHT_GRAY, tostring(note.text), x, y, w, NOTE_LINES) - 1
  y = y - SEGMENT_GAP - Block(U.Fonts.DATA, U.Colors.INFO_BLUE, tostring(note.label), x, y - SEGMENT_GAP, w, NOTE_LINES)
  return y - LINE_GAP
end

-- The pin key's line (UI.DetailWindow): "Alt+D: pin the full details", or,
-- with anything left out here, "Alt+D for everything: pin the full
-- details"; a pin key that is the waypoint key too says so, and with the
-- pin key off, a panel that left something out says where it is.
-- pinLive and pinAfterCombat: what UI.DetailWindow.Arm answered.
function Panel.PinText(model, pinLive, pinAfterCombat, trimmed)
  local Detail = Recollect.UI.DetailWindow
  if not Detail then return nil end
  if pinLive or pinAfterCombat then
    local key = trimmed and Detail.Key()
    if not key then return Detail.HintText(not pinLive) end
    return ("%s%s for everything: pin the full details"):format(Recollect.UI.Waypoint.KeyText(key),
      pinLive and "" or " after combat")
  end
  local clash = Detail.ClashText()
  if clash then return clash end
  if trimmed and type(model) == "table" and model.source then
    return "More in the item's full details: turn on the details key (/rec settings > Keys and waypoints)"
  end
  return nil
end

-- keyLive and afterCombat: what UI.Waypoint.Arm answered for model.waypoint;
-- pinLive and pinAfterCombat: what UI.DetailWindow.Arm answered
local function Paint(model, keyLive, afterCombat, pinLive, pinAfterCombat)
  ResetPools()
  cut = false
  local contentWidth = WIDTH - 2 * PAD
  local compact = Panel.Compact(model)
  local y = PaintHeader(model, -PAD)
  y = PaintVerdict(model, compact, y, contentWidth)
  if model.tip then y = PaintTip(model, y, contentWidth) end
  if #compact.uses > 0 then y = PaintLines("USED FOR", compact.uses, y, contentWidth) end
  if #compact.sources > 0 then y = PaintLines("COMES FROM", compact.sources, y, contentWidth) end
  if compact.note then y = PaintNote(compact.note, y, contentWidth) end
  -- The key is named only while it is bound, or as bound once combat ends
  local Waypoint = Recollect.UI.Waypoint
  local hint = model.waypoint and Waypoint and (keyLive or afterCombat) and Waypoint.HintText(model.waypoint, not keyLive)
  if hint then
    y = y - GAP
    y = y - Block(U.Fonts.DATA, U.Colors.INFO_BLUE, hint, PAD, y, contentWidth, HINT_LINES)
  end
  local trimmed = compact.trimmed or cut
  local pin = Panel.PinText(model, pinLive, pinAfterCombat, trimmed)
  if pin then
    y = y - (hint and LINE_GAP or GAP)
    y = y - Block(U.Fonts.DATA, U.Colors.INFO_BLUE, pin, PAD, y, contentWidth, HINT_LINES)
  end
  painted.height, painted.trimmed = PAD - y, trimmed
  frame:SetHeight(PAD - y)
end

-------------------------------------------------------------------------------
-- Placement beside the tooltip
-------------------------------------------------------------------------------
-- The outermost frame on one side: the tooltip, or a comparison tooltip shown there
local function Outermost(tooltip, side)
  local anchor = tooltip
  for _, shop in ipairs(seams.ShoppingTooltips()) do
    if shop and shop:IsShown() and shop:GetLeft() and anchor:GetLeft() then
      if side == "right" and shop:GetLeft() >= anchor:GetLeft() and shop:GetRight() > anchor:GetRight() then anchor = shop end
      if side == "left" and shop:GetRight() <= anchor:GetRight() and shop:GetLeft() < anchor:GetLeft() then anchor = shop end
    end
  end
  return anchor
end

local function Place(tooltip)
  local scale = tooltip:GetEffectiveScale() / UIParent:GetEffectiveScale()
  frame:SetScale(scale)
  frame:ClearAllPoints()
  local right = Outermost(tooltip, "right")
  local roomRight = UIParent:GetRight() - (right:GetRight() or 0) * right:GetEffectiveScale() / UIParent:GetEffectiveScale()
  if roomRight >= WIDTH * scale + SIDE_GAP then
    frame:SetPoint("TOPLEFT", right, "TOPRIGHT", SIDE_GAP, 0)
  else
    frame:SetPoint("TOPRIGHT", Outermost(tooltip, "left"), "TOPLEFT", -SIDE_GAP, 0)
  end
end

-- The identity of the item a tooltip's data shows: its GUID (an item you
-- hold), else its link, else "item:<id>"; nil for anything else
function Panel.Identity(data)
  if type(data) ~= "table" then return nil end
  local guid, link, id = data.guid, data.hyperlink, data.id
  local IsSecret = Recollect.Utilities.IsSecret
  if type(guid) == "string" and not IsSecret(guid) then return guid end
  if type(link) == "string" and not IsSecret(link) then return link end
  if type(id) == "number" and not IsSecret(id) then return "item:" .. id end
  return nil
end

-- Still the item the panel opened for?
local function StillShowing()
  if not owner or not owner:IsShown() then return false end
  local ok, data = pcall(seams.PrimaryData, owner)
  local identity = ok and Panel.Identity(data)
  return identity ~= nil and identity == ownerGuid
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------
-- Show(tooltip, model): paint the model and place it beside tooltip. The
-- waypoint key is armed first, so the hint says whether it works now
function Panel.Show(tooltip, model)
  owner, ownerGuid = tooltip, model.guid
  local keyLive, afterCombat, pinLive, pinAfterCombat = false, false, false, false
  if Recollect.UI.Waypoint then keyLive, afterCombat = Recollect.UI.Waypoint.Arm(model.waypoint) end
  if Recollect.UI.DetailWindow then pinLive, pinAfterCombat = Recollect.UI.DetailWindow.Arm(model) end
  local ok, err = pcall(Paint, model, keyLive, afterCombat, pinLive, pinAfterCombat)
  if not ok then
    Panel.Hide()   -- no key left bound for a panel that never showed
    error(err, 0)
  end
  Place(tooltip)
  sinceCheck = 0
  frame:Show()
end

function Panel.Hide()
  owner, ownerGuid = nil, nil
  frame:Hide()
  if Recollect.UI.Waypoint then Recollect.UI.Waypoint.Disarm() end
  if Recollect.UI.DetailWindow then Recollect.UI.DetailWindow.Disarm() end
end

function Panel.IsShown()
  return frame:IsShown()
end

-- Built at load, outside combat
frame = CreateFrame("Frame", "RecollectPanel", UIParent, "TooltipBackdropTemplate")
frame:SetFrameStrata("TOOLTIP")
frame:SetWidth(WIDTH)
frame:SetClampedToScreen(true)
frame.Icon = frame:CreateTexture(nil, "ARTWORK")
frame.Icon:SetSize(ICON, ICON)
frame:Hide()
frame:SetScript("OnUpdate", function(self, elapsed)
  sinceCheck = sinceCheck + elapsed
  if sinceCheck < RECHECK then return end
  sinceCheck = 0
  if not StillShowing() then
    Panel.Hide()
    return
  end
  Place(owner)   -- the tooltip may have grown or moved since
end)

Panel._test = { seams = seams, Frame = function() return frame end, Painted = function() return painted end,
  LIMITS = { MAX_USES = MAX_USES, MAX_SOURCES = MAX_SOURCES, MAX_ENTRIES = MAX_ENTRIES, REASON_PARTS = REASON_PARTS } }
