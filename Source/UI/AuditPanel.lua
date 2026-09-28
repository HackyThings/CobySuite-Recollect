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
--   [icon] Recollect                                  Bank tab 2
--   | Outdated                                        the verdict, large, its color
--   | Appearance collected; item level 250 is         the reason
--   |   below what you wear there (325)
--   (an Unknown leads with what the item is for instead:
--   | Combine 30 into Shattered Fragments of Val'anyr  large, white
--   | You have 4 of the 30 it takes, all in your bank  the reason
--   | Still needed? Can't tell yet                     small, gray)
--   Tip: Every use Recollect read is done (...).      the Tip, when there is one
--     It's most likely safe to sell or delete, but    (UI.Tooltip.Tip), its label gold
--     that's your call.
--   ------------------------------------------------
--   USED FOR                                          what it is used for, each with
--   Objective of "Light Repurposed" (you're on it)    its live state (UI.UsedFor);
--     Rewards Val'anyr                                text light gray, the "(state)"
--   Buys at Chef Dinaire (Hallowfall)                 and bullet in the state's color;
--   o Darkroot Grippers for 5                         what it buys under its seller
--   ------------------------------------------------
--   COMES FROM                                        where it comes from: quest
--   Reward from "Pink Elekks On Parade" (done)        rewards, what it's made from
--   ------------------------------------------------
--   GUIDE NOTES                                       what a guide says, when a note
--   o Charges the five Runestones of ...              ships (Data/Notes.lua): the note,
--     How many: 3 per charge                          how many, where, where from, a
--     Achievement "Runestone Rush" (2 of 5 done)      named achievement's or quest's
--     Per method.gg; not confirmed in game yet        state, and whose words they are
--   ------------------------------------------------
--   ABOUT                                             its kind and expansion (the
--   Armor: Plate, from The War Within                 tooltip names no expansion)
--   ------------------------------------------------
--   CHECKS                                            only when several ran
--   o Gear                                            each check in its verdict's color,
--     Appearance collected; ...                       its reason under it
--   Alt+W: waypoint to the vendor in Silvermoon City  when a vendor is known and
--                                                     the key is bound ("Alt+W after
--                                                     combat: ..." while combat blocks it)
--   Alt+D: pin the full details                       the pinned view's key (UI.DetailWindow)
-- For an item not held in that slot (reference mode) the verdict block says
-- how many you have instead. An Unknown's verdict block ends with its one
-- recovery step (G-04: "Open your bank once so Recollect can read it again").
-- A long headline is cut by characters, never inside a UTF-8 character (G-08).
-- Names a line uses that the game links (line.links, UI.UsedFor) are colored
-- as their links are (an item by its quality); the panel can't be clicked,
-- so they are only colored here (Panel.Linked). The verdict's and the
-- checks' reasons color the same names where they use them (model.links).
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
local GROUP_INDENT = 10          -- a line under a "Buys at" heading sits in from the rest (BA-14)
local GAP = U.Spacing.GROUP_GAP
local LINE_GAP = 3
local SIDE_GAP = 2
local RECHECK = 0.1              -- seconds between side and still-the-same-item checks
local SEGMENT_GAP = 2            -- between the parts of one reason
local HEADING_GAP = 3             -- above a "Buys at" heading after other lines
local HEADLINE_LARGE = 90        -- characters an Unknown's headline may have in the title font
local HEADLINE_MAX = 180         -- and at all

local frame
local fonts, fontsUsed = {}, 0
local textures, texturesUsed = {}, 0
local owner, ownerGuid, sinceCheck = nil, nil, 0

local seams = {
  PrimaryData = function(tooltip) return tooltip:GetPrimaryTooltipData() end,
  ShoppingTooltips = function() return { ShoppingTooltip1, ShoppingTooltip2 } end,
}

-------------------------------------------------------------------------------
-- Pools: font strings and plain textures, reused on every paint
-------------------------------------------------------------------------------
local function Font(template, color)
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
  tex:SetColorTexture(color[1], color[2], color[3], alpha or 1)
  tex:ClearAllPoints()
  tex:Show()
  return tex
end

local function ResetPools()
  for i = 1, fontsUsed do fonts[i]:Hide() end
  for i = 1, texturesUsed do textures[i]:Hide() end
  fontsUsed, texturesUsed = 0, 0
end

-- A wrapped text block at (x, y) of the given width; returns its height
local function Block(template, color, text, x, y, width)
  local fs = Font(template, color)
  fs:SetWidth(width)
  fs:SetText(text)
  fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
  return fs:GetStringHeight()
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

-- A reason as its parts, one block each, the names links holds colored;
-- returns the height used
local function ReasonBlocks(template, color, text, x, y, width, links)
  local top = y
  for i, part in ipairs(Panel.Segments(text)) do
    if i > 1 then y = y - SEGMENT_GAP end
    y = y - Block(template, color, Panel.Linked(part, links), x, y, width)
  end
  return top - y
end

local function Divider(y)
  local line = Texture(U.Colors.DIVIDER_GRAY, U.Colors.DIVIDER_GRAY[4])
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
  line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, y)
end

-------------------------------------------------------------------------------
-- Painting a model (UI.Tooltip.Model): header, verdict block, checks, footer
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

-- The verdict block: the verdict and its reason; for an Unknown, what the
-- item is for, the reason, then the verdict in small print. A long headline
-- (a whole Use line) drops to the body font rather than filling the panel.
local function PaintVerdict(model, y, contentWidth)
  local top = y
  local textX = PAD + ACCENT + ACCENT_GAP
  local textWidth = contentWidth - ACCENT - ACCENT_GAP
  if model.headline then
    local headline = U.Truncate(model.headline, HEADLINE_MAX)
    local font = U.Utf8Length(headline) <= HEADLINE_LARGE and U.Fonts.TITLE or U.Fonts.BODY
    y = y - Block(font, U.Colors.HIGHLIGHT_WHITE, headline, textX, y, textWidth) - LINE_GAP
  else
    y = y - Block(U.Fonts.TITLE, model.color, model.label, textX, y, textWidth) - LINE_GAP
  end
  y = y - ReasonBlocks(U.Fonts.BODY, U.Colors.LIGHT_GRAY, model.reason, textX, y, textWidth, model.links)
  if model.verdictNote then
    y = y - LINE_GAP - Block(U.Fonts.DATA, U.Colors.LABEL_GRAY, model.verdictNote, textX, y - LINE_GAP, textWidth)
  end
  if model.recovery then
    y = y - LINE_GAP - Block(U.Fonts.DATA, U.Colors.INFO_BLUE, model.recovery, textX, y - LINE_GAP, textWidth)
  end
  local bar = Texture(model.color)
  bar:SetWidth(ACCENT)
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, top)
  bar:SetHeight(top - y)
  return y
end

local function PaintChecks(model, y, contentWidth)
  y = y - GAP
  Divider(y)
  y = y - GAP
  y = y - Block(U.Fonts.SMALL, U.Colors.STATUS_GOLD, "CHECKS", PAD, y, contentWidth) - LINE_GAP
  for _, check in ipairs(model.purposes) do
    local dot = Texture(check.color)
    dot:SetSize(BULLET, BULLET)
    dot:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 2, y - 4)
    y = y - Block(U.Fonts.SMALL, check.color, check.label, PAD + BULLET_INDENT, y, contentWidth - BULLET_INDENT) - 1
    y = y - ReasonBlocks(U.Fonts.DATA, U.Colors.LABEL_GRAY, check.reason, PAD + BULLET_INDENT, y, contentWidth - BULLET_INDENT,
      model.links)
    y = y - LINE_GAP - 2
  end
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

-- A titled list of UI.UsedFor lines (USED FOR, COMES FROM): a heading
-- ("Buys at ...") flush left with no bullet, every other line bulleted in
-- its color; a line under a heading (line.grouped) indented further, so the
-- line after a group can't read as one of its lines
local function PaintLines(title, lines, y, contentWidth)
  y = y - GAP
  Divider(y)
  y = y - GAP
  y = y - Block(U.Fonts.SMALL, U.Colors.STATUS_GOLD, title, PAD, y, contentWidth) - LINE_GAP
  for i, line in ipairs(lines) do
    if line.header then
      if i > 1 then y = y - HEADING_GAP end
      y = y - Block(U.Fonts.SMALL, U.Colors.HIGHLIGHT_WHITE, line.text, PAD, y, contentWidth)
    else
      local inset = line.grouped and GROUP_INDENT or 0
      local dot = Texture(line.color or U.Colors.LIGHT_GRAY)
      dot:SetSize(BULLET, BULLET)
      dot:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 2 + inset, y - 4)
      local x, w = PAD + BULLET_INDENT + inset, contentWidth - BULLET_INDENT - inset
      y = y - Block(U.Fonts.SMALL, U.Colors.LIGHT_GRAY, Panel.LineText(line), x, y, w) - 1
      if line.detail then
        y = y - Block(U.Fonts.DATA, U.Colors.LABEL_GRAY, Panel.Linked(line.detail, line.links), x, y, w)
      end
    end
    y = y - LINE_GAP - 2
  end
  return y
end

-- The Tip under the verdict block: "Tip:" in gold, then its words
function Panel.TipText(tip)
  local label = Recollect.UI.Tooltip and Recollect.UI.Tooltip.TIP_LABEL or "Tip"
  return ("|cFF%s%s:|r %s"):format(U.Colors.TEXT_GOLD, label, tip)
end

local function PaintTip(model, y, contentWidth)
  y = y - GAP
  return y - Block(U.Fonts.DATA, U.Colors.LIGHT_GRAY, Panel.TipText(model.tip), PAD, y, contentWidth)
end

-- GUIDE NOTES (UI.UsedFor.NoteLines): each note bulleted gray, its details
-- and a named achievement's or quest's state under it, then whose words
-- they are
local function PaintNotes(notes, y, contentWidth)
  y = y - GAP
  Divider(y)
  y = y - GAP
  y = y - Block(U.Fonts.SMALL, U.Colors.STATUS_GOLD, "GUIDE NOTES", PAD, y, contentWidth) - LINE_GAP
  local x, w = PAD + BULLET_INDENT, contentWidth - BULLET_INDENT
  for i, note in ipairs(notes) do
    if i > 1 then y = y - HEADING_GAP end
    local dot = Texture(note.color or U.Colors.LABEL_GRAY)
    dot:SetSize(BULLET, BULLET)
    dot:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 2, y - 4)
    y = y - Block(U.Fonts.SMALL, U.Colors.LIGHT_GRAY, note.text, x, y, w) - 1
    for _, detail in ipairs(note.details or {}) do
      y = y - Block(U.Fonts.DATA, U.Colors.LABEL_GRAY, detail, x, y, w)
    end
    if note.state then
      y = y - Block(U.Fonts.DATA, U.Colors.LABEL_GRAY, Panel.LineText(note.state), x, y, w)
    end
    y = y - SEGMENT_GAP - Block(U.Fonts.DATA, U.Colors.INFO_BLUE, note.label, x, y - SEGMENT_GAP, w)
    y = y - LINE_GAP
  end
  return y
end

local function PaintAbout(model, y, contentWidth)
  y = y - GAP
  Divider(y)
  y = y - GAP
  y = y - Block(U.Fonts.SMALL, U.Colors.STATUS_GOLD, "ABOUT", PAD, y, contentWidth) - LINE_GAP
  for i, line in ipairs(model.about) do
    if i > 1 then y = y - SEGMENT_GAP end
    y = y - Block(U.Fonts.DATA, i == 1 and U.Colors.LIGHT_GRAY or U.Colors.LABEL_GRAY, line, PAD, y, contentWidth)
  end
  return y
end

-- keyLive and afterCombat: what UI.Waypoint.Arm answered for model.waypoint;
-- pinLive and pinAfterCombat: what UI.DetailWindow.Arm answered
local function Paint(model, keyLive, afterCombat, pinLive, pinAfterCombat)
  ResetPools()
  local contentWidth = WIDTH - 2 * PAD
  local y = PaintHeader(model, -PAD)
  y = PaintVerdict(model, y, contentWidth)
  if model.tip then y = PaintTip(model, y, contentWidth) end
  if model.usedFor and #model.usedFor > 0 then y = PaintLines("USED FOR", model.usedFor, y, contentWidth) end
  if model.comesFrom and #model.comesFrom > 0 then y = PaintLines("COMES FROM", model.comesFrom, y, contentWidth) end
  if model.notes and #model.notes > 0 then y = PaintNotes(model.notes, y, contentWidth) end
  if model.about and #model.about > 0 then y = PaintAbout(model, y, contentWidth) end
  if #model.purposes > 0 then y = PaintChecks(model, y, contentWidth) end
  -- The key is named only while it is bound, or as bound once combat ends
  local Waypoint = Recollect.UI.Waypoint
  local hint = model.waypoint and Waypoint and (keyLive or afterCombat) and Waypoint.HintText(model.waypoint, not keyLive)
  if hint then
    y = y - GAP
    y = y - Block(U.Fonts.DATA, U.Colors.INFO_BLUE, hint, PAD, y, contentWidth)
  end
  local Detail = Recollect.UI.DetailWindow
  local pin = Detail and ((pinLive or pinAfterCombat) and Detail.HintText(not pinLive) or Detail.ClashText())
  if pin then
    y = y - (hint and LINE_GAP or GAP)
    y = y - Block(U.Fonts.DATA, U.Colors.INFO_BLUE, pin, PAD, y, contentWidth)
  end
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

Panel._test = { seams = seams, Frame = function() return frame end }
