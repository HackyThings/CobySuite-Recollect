-------------------------------------------------------------------------------
-- UI.SecretPanel: the details window's Secret tab (Tasks #407 and #411)
--
-- A secret is a checklist a player works through, so its tab is a panel of
-- its own, not a table (Cobanyte, 2026-10-14: "It doesn't have to be forced
-- into a table"). It paints UI.SecretModel's model, as Task #430 redesigned
-- it (Cobanyte, 2026-10-14: "buttons are everywhere.. it's chaotic looking
-- still"; keep the two panels, everything else up for consideration):
--   * one compact header in place of the details window's own on this tab:
--     the secret's name (a menu of the item's secrets when it is in
--     several), the item history, Refresh (its read time on hover) and More
--     (Expand or Collapse all steps, Clear my marks, the curator's action);
--     under it the item the tab was opened for with its answer, and the
--     progress counted honestly ("0/41 tracked done; 16 untracked")
--   * on the left a quiet explorer: Search and the All / To do / This item
--     filters (not for a secret of three steps or fewer), then Summary &
--     rewards, the stages (a click shows the stage's page; the chevron
--     folds it) and the steps (a mark, the code, this item's icon, a short
--     title; selected in gold), Suggested next fixed at the bottom
--   * on the right one page, its text at most 680 wide: a step (breadcrumb,
--     title, state with the "Done for my checklist" box, the item's role,
--     Before you start, You need as a table, Do this, its sub-steps,
--     Locations with one pin and Set waypoint per destination and the places
--     its words only name apart, Notes and troubleshooting), a stage's page
--     or the Summary; one Previous and Next in the reader's footer
--   * each link in its kind's game color, as the details window paints it
--     (Task #450), each name linked the first time a section uses it;
--     titles, the list and breadcrumbs plain
-- Built once at login with the window; rows, lines, pins and stages are
-- pooled, more made only out of combat. Painted on open, on a resize, and on
-- a refresh only when what it shows changed (the tab reads its steps again
-- every few seconds while it shows, UI.DetailWindow's SecretPoll;
-- SecretModel.Signature); folds, scrolls and the selection are kept per
-- owner and secret, so a refresh never moves the player.
--
-- Also the look every other surface gives a secret (Cobanyte, 2026-10-14:
-- "maybe make it rainbow color when we say 'secret'"; the Secret tab itself
-- no longer uses it, Task #430): LINK_COLOR for a link that opens the Secret
-- tab, a color no other Recollect or CobySuite text uses, and Styled, which
-- paints the word "secret" in a static rainbow (color codes per letter,
-- nothing per frame). Only painted text is styled; a line's own text, which
-- Copy and chat use, stays plain.
-------------------------------------------------------------------------------
local U = CobySuite_Recollect.Utilities

local Panel = {}
Recollect.UI.SecretPanel = Panel

-- A pink no other color of the suite uses (the quality colors, the verdict
-- colors, the link yellows and blues, the journal's blue): a secret's link
Panel.LINK_COLOR = { 1, 0.5, 0.84 }
-- The rainbow's hues, blended across the word's letters: fully saturated, each
-- bright enough to read on the dark backdrop (the first pastel set was barely
-- visible at the small size of a line, Task #410)
Panel.RAINBOW = { { 1, 0.15, 0.15 }, { 1, 0.55, 0 }, { 1, 0.92, 0.1 }, { 0.15, 1, 0.3 }, { 0.2, 0.7, 1 },
  { 0.78, 0.3, 1 } }
Panel.TIP = "Open the Secret tab"

local Hex = U.ColorToHex

-- Rainbow(word): the word in capitals, each letter in a color blended along
-- RAINBOW (painted text only: Copy and chat keep the line's own words)
function Panel.Rainbow(word)
  word = tostring(word):upper()
  local n, hues = #word, Panel.RAINBOW
  if n == 0 then return word end
  local out = {}
  for i = 1, n do
    local at = n == 1 and 1 or 1 + (i - 1) / (n - 1) * (#hues - 1)
    local lo = math.floor(at)
    local hi = math.min(lo + 1, #hues)
    local t = at - lo
    local a, b = hues[lo], hues[hi]
    local color = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
    out[i] = ("|cFF%s%s|r"):format(Hex(color), word:sub(i, i))
  end
  return table.concat(out)
end

-- PlainLink(name): the secret's link as plain text, "[SECRET: Phoenix Wishwing]"
-- (Cobanyte, 2026-10-14): what Copy and chat read, and the text a line holds
-- where the painted link goes
function Panel.PlainLink(name)
  return ("[SECRET: %s]"):format(tostring(name))
end

-- PaintedLink(name, linkData): the same span painted: brackets, colon and name
-- in LINK_COLOR, "SECRET" in its rainbow capitals, and with linkData one
-- hyperlink around the whole span (the hit area is all of it), none without
-- (the audit panel never clicks). Color codes only; the plain text is PlainLink's.
function Panel.PaintedLink(name, linkData)
  local pink = "|cFF" .. Hex(Panel.LINK_COLOR)
  local rainbow = Panel.Rainbow("SECRET")
  if linkData then
    return ("%s|H%s|h[|r%s%s: %s]|h|r"):format(pink, linkData, rainbow, pink, tostring(name))
  end
  return ("%s[|r%s%s: %s]|r"):format(pink, rainbow, pink, tostring(name))
end

-- StyleChunk(part): a stretch of text outside any color or link: each
-- "[SECRET: name]" painted as PaintedLink paints it (no hyperlink: the
-- audit panel never clicks), every other word "secret" or "secrets" in the
-- rainbow
local function StyleChunk(part)
  local out, at = {}, 1
  while true do
    local first, last, name = part:find("%[SECRET: ([^%]]+)%]", at)
    if not first then break end
    out[#out + 1] = (part:sub(at, first - 1):gsub("%f[%a]([Ss]ecrets?)%f[%A]", Panel.Rainbow))
    out[#out + 1] = Panel.PaintedLink(name)
    at = last + 1
  end
  out[#out + 1] = (part:sub(at):gsub("%f[%a]([Ss]ecrets?)%f[%A]", Panel.Rainbow))
  return table.concat(out)
end

-- Styled(text): painted text with every "[SECRET: name]" painted as a link
-- (without its hyperlink) and every word "secret" or "secrets" (either case
-- of its first letter) in the rainbow capitals, except inside a color, a link
-- or a texture the text already holds (their codes are kept whole)
function Panel.Styled(text)
  text = tostring(text)
  if not text:lower():find("secret", 1, true) then return text end
  local out, n = {}, #text
  local i, from, depth, link = 1, 1, 0, 0
  local function Flush(upto)
    if from > upto then return end
    local part = text:sub(from, upto)
    if depth == 0 and link == 0 then part = StyleChunk(part) end
    out[#out + 1] = part
  end
  while i <= n do
    if text:byte(i) == 124 and i < n then   -- "|"
      Flush(i - 1)   -- the text before the code, styled by the state before it
      local code = text:sub(i + 1, i + 1)
      local stop = i + 1
      if code == "c" then
        stop, depth = i + 9, depth + 1
      elseif code == "r" then
        depth = math.max(0, depth - 1)
      elseif code == "H" then
        local close = text:find("|h", i + 2, true)
        stop, link = close and close + 1 or n, link + 1
      elseif code == "h" then
        link = math.max(0, link - 1)
      elseif code == "A" or code == "T" or code == "K" then
        local close = text:find("|" .. code:lower(), i + 2, true)
        stop = close and close + 1 or n
      end
      out[#out + 1] = text:sub(i, stop)
      i = stop + 1
      from = i
    else
      i = i + 1
    end
  end
  Flush(n)
  return table.concat(out)
end

-------------------------------------------------------------------------------
-- The secrets an item is in, and the model (UI.SecretModel)
-------------------------------------------------------------------------------
-- Secrets(itemID): the secrets the item belongs to, in the data's order,
-- each { sid, role ("use", or "teaches" for the item that teaches its
-- reward), rewardState ("have", "missing", "unread" or nil when it has none), name, gone }; one no longer in the game is
-- kept, marked gone and listed after the others (Task #463, the Manager's decision 2026-10-15: shown, never a live use)
function Panel.Secrets(itemID)
  local S = Recollect.Facts.Secrets
  local list, gone, bySid = {}, {}, {}
  if not S or S.Status() ~= "ok" or not Recollect.Utilities.IsPositiveID(itemID) then return list end
  for _, entry in ipairs(S.Of("item", itemID)) do
    local use = S.USE_ROLES[entry.role]
    if use or entry.role == "teaches" then
      local secret = S.Get(entry.sid)
      if secret then
        local kept = bySid[entry.sid]
        if not kept then
          local things, all = S.Rewards(secret)
          local first = things[1]
          kept = { sid = entry.sid, role = use and "use" or "teaches", rewardState = all,
            name = S.Name(secret) or (first and Recollect.Facts.Buys.Name(first)) or nil, gone = S.Gone(secret) or nil }
          bySid[entry.sid] = kept
          local into = kept.gone and gone or list
          into[#into + 1] = kept
        elseif use then
          kept.role = "use"
        end
      end
    end
  end
  for _, kept in ipairs(gone) do list[#list + 1] = kept end
  return list
end

-- Model(itemID, owner, sid): the tab's model for the item, on sid's secret
-- when it is one of its own, else its first (UI.SecretModel.Build); nil when
-- the item is in no secret
function Panel.Model(itemID, owner, sid)
  local list = Panel.Secrets(itemID)
  if #list == 0 then return nil end
  local pick = list[1]
  for _, entry in ipairs(list) do
    if entry.sid == sid then pick = entry end
  end
  local read = Recollect.UI.DetailData.SecretStepsOf(pick.sid, owner, itemID)
  return Recollect.UI.SecretModel.Build(itemID, owner, pick, list, read)
end

-------------------------------------------------------------------------------
-- The painter (Task #430, from the UI designer's spec of 2026-10-14: one
-- compact header, a quiet step explorer, one readable page, no red buttons,
-- one pager, honest waypoints). Every size below is in UI units
-------------------------------------------------------------------------------
local L = { INSET = 4, HEAD_GAP = 6, SPLIT_GAP = 12, EXP_MIN = 208, EXP_MAX = 320, EXP_SHARE = 0.28, EXP_PAD = 8,
  PAGE = 20, PAGE_NARROW = 16, READ_NARROW = 560, TEXT_MAX = 680, FOOTER = 40, SUGGEST_H = 40, ICON_BTN = 24,
  PIN_H = 28, PIN = 16, ROW_MIN = 22, ROW_TWO = 32, INDENT = 12, DISCLOSE = 18, MARK = 14, CODE = 20, ITEM_ICON = 12,
  NEXT_W = 20, NEXT_H = 16, STAGE_H = 38, SUMMARY_H = 24, SEARCH_H = 22, SEG_H = 22, SCROLLBAR = 20, NARROW = 836, BUTTON_H = 24,
  SECTION_GAP = 12, LINE_GAP = 3, NUM_W = 56, TREE_ROWS = 80, TREE_STAGES = 16, PAGE_LINES = 48, HEADS = 10,
  PAGE_PINS = 8, STEPS = 40, REQS = 16 }
Panel.LAYOUT = L
Panel.SPLIT = L   -- (the reader's padding, Task #417's name)

-- The game's own glyphs (in the 12.1.0 UI source; Task #430's atlas contract)
local ATLAS = { back = "common-icon-backarrow", forward = "common-icon-forwardarrow", warn = "transmog-icon-warning-small",
  pin = "Waypoint-MapPin-Untracked", refresh = "Interface\\Buttons\\UI-RefreshButton" }
Panel.ATLAS = ATLAS

local FONTS = { body = U.Fonts.BODY, data = U.Fonts.DATA }

local function Model() return Recollect.UI.SecretModel end

local function Font(parent, font, color, wrap)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  fs:SetWordWrap(wrap ~= false)
  fs:SetTextColor(color[1], color[2], color[3])
  return fs
end

-- A size the client gives, or fallback when it gives none
local function Size(value, fallback)
  return type(value) == "number" and value or fallback
end

local function SetColor(fs, color)
  color = color or U.Colors.LIGHT_GRAY
  fs:SetTextColor(color[1], color[2], color[3])
end

-- One text at x, y, w wide: shown, its height
local function Place(fs, text, x, y, w, color)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", fs:GetParent(), "TOPLEFT", x, y)
  fs:SetWidth(math.max(20, w))
  fs:SetText(text)
  if color then SetColor(fs, color) end
  fs:Show()
  return math.ceil(Size(fs:GetStringHeight(), 12))
end

local function Tint(tex, color, alpha)
  tex:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
end

-- Shown(region, on): shown or hidden
local function Shown(region, on)
  if on then region:Show() else region:Hide() end
end

-- The tooltip lines a control shows: a title, then gray lines
local function Tip(owner, title, lines, anchor)
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  GameTooltip:SetText(title, 1, 1, 1)
  local gray = U.Colors.LABEL_GRAY
  for _, line in ipairs(lines or {}) do
    if type(line) == "table" then
      GameTooltip:AddLine(line.text, line.color[1], line.color[2], line.color[3], true)
    elseif line ~= "" then
      GameTooltip:AddLine(line, gray[1], gray[2], gray[3], true)
    end
  end
  GameTooltip:Show()
end

-------------------------------------------------------------------------------
-- Controls: flat text actions, icon buttons, a disclosure chevron, the checkbox
-------------------------------------------------------------------------------
local Kit = {}
Panel.Kit = Kit

-- Text(parent, words, onClick, color, font): a flat text action (Previous,
-- Next, More, a disclosure, a link), sized to its words; :SetLabel(words),
-- :SetActive(on)
function Kit.Text(parent, words, onClick, color, font)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(L.BUTTON_H)
  b.color = color or U.Colors.LINK_BLUE
  b.Text = Font(b, font or U.Fonts.BODY, b.color, false)
  b.Text:SetPoint("LEFT", b, "LEFT", 2, 0)
  local hover = b:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  Tint(hover, U.Colors.HOVER_HIGHLIGHT)
  b.enabled = true
  function b:SetLabel(text)
    self.Text:SetText(text)
    self:SetWidth(math.ceil(Size(self.Text:GetStringWidth(), 8 * #tostring(text))) + 6)
  end
  function b:SetActive(on)
    self.enabled = on and true or false
    self:SetEnabled(self.enabled)
    SetColor(self.Text, self.enabled and self.color or U.Colors.DISABLED_GRAY)
  end
  b:SetLabel(words or "")
  if onClick then b:SetScript("OnClick", function(self) if self.enabled then onClick(self) end end) end
  b:Hide()
  return b
end

-- Icon(parent, glyph, w, h, onClick): a quiet square button of the shared
-- kit with a glyph centered in it (an atlas, or a file for "Interface\\..."),
-- dimmed while it can't be used
function Kit.Icon(parent, glyph, w, h, onClick)
  local make = CobySuite_Recollect.UI.CreateIconButton
  local b = make and make(parent, { size = L.ICON_BTN, highlight = U.Colors.HOVER_HIGHLIGHT }) or CreateFrame("Button", nil, parent)
  b:SetSize(L.ICON_BTN, L.ICON_BTN)
  b.Glyph = b:CreateTexture(nil, "ARTWORK")
  b.Glyph:SetSize(w, h)
  b.Glyph:SetPoint("CENTER", b, "CENTER", 0, 0)
  if glyph:find("\\", 1, true) then b.Glyph:SetTexture(glyph) else b.Glyph:SetAtlas(glyph) end
  b.enabled = true
  function b:SetActive(on)
    self.enabled = on and true or false
    self:SetEnabled(self.enabled)
    self:SetAlpha(self.enabled and 1 or 0.35)
  end
  if onClick then b:SetScript("OnClick", function(self) if self.enabled then onClick(self) end end) end
  b:Hide()
  return b
end

-- Disclosure(parent, onClick): the explorer's chevron, its own hit area (a
-- row or a stage selects; this folds): right when closed, down when open
function Kit.Disclosure(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(L.DISCLOSE, L.DISCLOSE)
  b.Arrow = b:CreateTexture(nil, "ARTWORK")
  b.Arrow:SetSize(7, 11)
  b.Arrow:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.Arrow:SetAtlas(ATLAS.forward)
  local gray = U.Colors.LIGHT_GRAY
  b.Arrow:SetVertexColor(gray[1], gray[2], gray[3])
  local hover = b:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  Tint(hover, U.Colors.HOVER_HIGHLIGHT)
  b.open, b.label = false, false
  function b:SetOpen(open)
    self.open = open and true or false
    self.Arrow:SetRotation(self.open and -math.pi / 2 or 0)
  end
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self)
    Tip(self, self.open and "Hide its steps" or "Show its steps", { "Only the list changes; the page you're reading stays." })
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  return b
end

-- Check(parent, words, onClick): the shared checkbox with its label
function Kit.Check(parent, words, onClick)
  local cb
  if CobySuite_Recollect.UI.CreateCheckbox then
    cb = CobySuite_Recollect.UI.CreateCheckbox(parent, { size = L.BUTTON_H, label = words, labelFont = U.Fonts.BODY })
  else
    cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(L.BUTTON_H, L.BUTTON_H)
    cb.text = Font(cb, U.Fonts.BODY, U.Colors.LIGHT_GRAY, false)
    cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.text:SetText(words)
  end
  cb:SetScript("OnClick", onClick)
  cb:Hide()
  return cb
end

-- A square outline around a mark: the player's own check, told apart from the game's
function Kit.Box(parent, size)
  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(size, size)
  local blue = U.Colors.INFO_BLUE
  for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
    { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
    local t = box:CreateTexture(nil, "OVERLAY")
    t:SetPoint(edge[1], box, edge[1], 0, 0)
    t:SetPoint(edge[2], box, edge[2], 0, 0)
    if edge[3] then t:SetHeight(1) else t:SetWidth(1) end
    t:SetColorTexture(blue[1], blue[2], blue[3], 0.9)
  end
  box:Hide()
  return box
end

-- NextMarker(parent): the Suggested next sign (Task #432, "bigger, more apparent"):
-- a big gold arrow, the game's own forward arrow, on a faint gold chip so it reads
-- on a selected row too; the parent's hover says what it is
function Kit.NextMarker(parent)
  local m = CreateFrame("Frame", nil, parent)
  m:SetSize(L.NEXT_W, L.NEXT_W)
  local gold = U.Colors.STATUS_GOLD
  m.Chip = m:CreateTexture(nil, "ARTWORK", nil, 1)
  m.Chip:SetAllPoints()
  Tint(m.Chip, gold, 0.28)
  m.Arrow = m:CreateTexture(nil, "ARTWORK", nil, 2)
  m.Arrow:SetSize(math.floor(L.NEXT_H * 0.64 + 0.5), L.NEXT_H)
  m.Arrow:SetAtlas(ATLAS.forward)
  m.Arrow:SetVertexColor(gold[1], gold[2], gold[3])
  m.Arrow:SetPoint("CENTER", m, "CENTER", 1, 0)
  m:EnableMouse(false)
  m:Hide()
  return m
end

-- The selected row's look (the settings sidebar's): a gold stripe on the
-- left and a faint gold wash; the hover the shared wash
function Kit.Selectable(frame)
  frame.Sel = frame:CreateTexture(nil, "BORDER")
  frame.Sel:SetAllPoints()
  Tint(frame.Sel, U.Colors.STATUS_GOLD, 0.10)
  frame.Stripe = frame:CreateTexture(nil, "ARTWORK")
  frame.Stripe:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  frame.Stripe:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  frame.Stripe:SetWidth(3)
  Tint(frame.Stripe, U.Colors.STATUS_GOLD, 0.9)
  -- a folded branch holding the selected step: a small gold mark at its right
  frame.Holds = frame:CreateTexture(nil, "ARTWORK")
  frame.Holds:SetSize(5, 5)
  frame.Holds:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
  Tint(frame.Holds, U.Colors.STATUS_GOLD, 0.9)
  frame.Sel:Hide()
  frame.Stripe:Hide()
  frame.Holds:Hide()
end

local function Selected(frame, on, holds)
  Shown(frame.Sel, on)
  Shown(frame.Stripe, on)
  Shown(frame.Holds, holds and not on)
end

-------------------------------------------------------------------------------
-- Words as painted
-------------------------------------------------------------------------------
-- A line's text as painted (opts.hyper, the details window's Hyper.Text, so
-- hover and clicks are its rows'): each link in the color the model gives
-- it, its kind's game color (Data.LinkColor: an item by its quality, a quest
-- or an achievement yellow, a spell blue, an NPC or a place Recollect's own;
-- Cobanyte, 2026-10-15, Task #450, in place of Task #430's one LINK_BLUE),
-- LINK_BLUE when it has none, and with seen (a section's), a name linked only the first time the section
-- uses it; a line in pieces painted piece by piece, an icon before its
-- piece. The words stay the line's own (text, seg.text)
local function Painted(f, line, seen)
  local hyper = f.opts.hyper
  local function Text(text, links)
    if not (links and #links > 0 and hyper) then return text end
    local kept = {}
    for _, link in ipairs(links) do
      if type(link.text) == "string" and link.text ~= "" and not (seen and seen[link.text]) then
        kept[#kept + 1] = { text = link.text, row = link.row, kind = link.kind, id = link.id,
          color = link.color or U.Colors.LINK_BLUE }
      end
    end
    if #kept == 0 then return text end
    if seen then
      for _, link in ipairs(kept) do
        if text:find(link.text, 1, true) then seen[link.text] = true end
      end
    end
    return hyper(text, kept, seen ~= nil) or text
  end
  if not line.segs then return Text(tostring(line.text or ""), line.links) end
  local out = {}
  for _, seg in ipairs(line.segs) do
    local text = tostring(seg.text or "")
    if seg.links then
      text = Text(text, seg.links)
    elseif seg.color then
      text = ("|cFF%s%s|r"):format(Hex(seg.color), text)
    end
    if seg.icon then text = Recollect.UI.Icons.Markup(seg.icon, 12) .. text end
    out[#out + 1] = text
  end
  return table.concat(out)
end
Panel.Painted = Painted

-- Painted text's words alone, for a suite: color codes, links' data and icons taken out
function Panel.PlainText(text)
  text = tostring(text or "")
  text = text:gsub("|A.-|a ?", ""):gsub("|T.-|t", ""):gsub("|H.-|h", ""):gsub("|h", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return text
end

-- Repaint(f, read): the model read again (a mark changed), else painted again (a fold)
function Panel.Repaint(f, read)
  if read and f.itemID then return Panel.Show(f, f.itemID, f.owner, f.sid, f.onPick, true) end
  if f.model then Panel.Paint(f, f.model, true) end
end

-------------------------------------------------------------------------------
-- Pins: one action per destination, the pin and "Set waypoint" (Task #430)
-------------------------------------------------------------------------------
-- A pin's click: one place sets its waypoint; several open a menu of them
function Panel.PinClick(f, pin)
  local places = pin.places
  if type(places) ~= "table" or #places == 0 then return end
  if #places == 1 then
    if f.opts.onWaypoint then f.opts.onWaypoint(places[1]) end
  elseif f.opts.placesMenu then
    f.opts.placesMenu(pin, pin.title, places)
  end
end

function Panel.PinTip(f, pin)
  local places = pin.places
  if type(places) ~= "table" or #places == 0 then return end
  if #places == 1 and f.opts.waypointTip then return f.opts.waypointTip(pin, places[1]) end
  Tip(pin, "Choose a location", { tostring(pin.title or ""), ("Click for its %d places"):format(#places) })
end

local function MakePin(f, parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(L.PIN_H)
  b.places, b.title = false, false
  local function Click() Panel.PinClick(f, b) end
  local function Enter() Panel.PinTip(f, b) end
  local function Leave() GameTooltip:Hide() end
  b.Pin = f.opts.pin and f.opts.pin(b, L.PIN) or nil
  if b.Pin then
    b.Pin:ClearAllPoints()
    b.Pin:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.Pin:SetScript("OnClick", Click)
    b.Pin:SetScript("OnEnter", Enter)
    b.Pin:SetScript("OnLeave", Leave)
  else
    b.Pin = b:CreateTexture(nil, "ARTWORK")
    b.Pin:SetSize(L.PIN, L.PIN)
    b.Pin:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.Pin:SetAtlas(ATLAS.pin)
  end
  b.Label = Font(b, U.Fonts.BODY, U.Colors.LINK_BLUE, false)
  b.Label:SetPoint("LEFT", b, "LEFT", L.PIN + 4, 0)
  local hover = b:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  Tint(hover, U.Colors.HOVER_HIGHLIGHT)
  b:SetScript("OnClick", Click)
  b:SetScript("OnEnter", Enter)
  b:SetScript("OnLeave", Leave)
  b:Hide()
  return b
end

-- The client calls the painter makes, for the suites
Panel.seams = { InCombat = function() return InCombatLockdown() end }

-- The pooled piece i of a list, made when missing (out of combat only)
local function Pooled(list, i, make)
  if not list[i] and not Panel.seams.InCombat() then list[i] = make() end
  return list[i]
end

-- The panel's width now, read at every paint (Task #411: a row is never laid
-- out wider than what shows); before the first layout a full window's
local function Width(f)
  local w = Size(f:GetWidth(), 0)
  if w < 300 then w = 900 end
  return math.floor(w)
end
Panel.Width = Width

-- The explorer's width for the panel's: a share of it, held between its least and most
local function ExplorerWidth(width)
  local content = width - 2 * L.INSET
  local w = math.floor(content * L.EXP_SHARE / 4 + 0.5) * 4
  return math.max(L.EXP_MIN, math.min(L.EXP_MAX, w))
end
Panel.ExplorerWidth = ExplorerWidth

-------------------------------------------------------------------------------
-- The header (Task #430): the secret's name (a menu of the item's secrets
-- when it is in several), the item history, Refresh and More on its right;
-- under it the item it was opened for with its answer, and the progress
-- (a line of its own below 836 wide)
-------------------------------------------------------------------------------
-- The header's More: the explorer's folds, the player's marks (asked
-- first), and the curator's action for the item
function Panel.MoreMenu(f, anchor)
  local model = f.model
  if not (model and f.opts.menu) then return end
  local entries = {
    { label = "Expand all steps", run = function() Model().SetAll(f.model, true) Panel.Repaint(f) end },
    { label = "Collapse all steps", run = function() Model().SetAll(f.model, false) Panel.Repaint(f) end },
  }
  if (model.markedCount or 0) > 0 and model.owner and model.owner.isViewer then
    entries[#entries + 1] = { label = "Clear my marks on this secret", run = function() Panel.AskClearMarks(f) end }
  end
  local curator = f.opts.curator and f.opts.curator() or nil
  if curator and curator.text then entries[#entries + 1] = { label = curator.text, run = curator.run } end
  f.opts.menu(anchor, nil, entries)
end

-- Clear my marks: the shared confirmation first (a bulk removal), naming
-- whose checklist and which secret; without the dialog (offline) at once.
-- The owner and secret are the ones shown when it asks: its confirm clears
-- those, and the panel showing another owner or secret hides it (Paint;
-- review UI-01: the dialog isn't modal and outlived a change of secret)
function Panel.AskClearMarks(f)
  local model = f.model
  if not model then return end
  local ownerKey, sid = model.ownerKey, model.sid
  local function Clear()
    Model().ClearMarks(ownerKey, sid)
    if f.model then Panel.Repaint(f, true) end
  end
  local dialog = f.ClearDialog
  if not dialog then return Clear() end
  dialog.clear, dialog.target = Clear, tostring(ownerKey) .. "\29" .. tostring(sid)
  dialog:SetBody(("Take off the %d mark%s you made on this character's checklist for %s? The game's own progress doesn't change.")
    :format(model.markedCount or 0, (model.markedCount or 0) == 1 and "" or "s", tostring(model.name)))
  dialog:Show()
end

-- The item's secrets, when it is in several: a pick shows that one
function Panel.SecretsMenu(f, anchor)
  local model = f.model
  if not (model and f.opts.menu and #(model.secrets or {}) > 1) then return end
  local entries = {}
  for i, entry in ipairs(model.secrets) do
    local state = entry.rewardState == "have" and "collected" or entry.rewardState == "missing" and "not collected" or nil
    if entry.gone then state = "no longer in the game" end
    local role = entry.role == "teaches" and "its reward" or "uses this item"
    local sid = entry.sid
    entries[#entries + 1] = { label = ("%s (%s%s)"):format(entry.name or ("Secret " .. i), role, state and ("; " .. state) or ""),
      run = function() if f.onPick then f.onPick(sid) end end }
  end
  f.opts.menu(anchor, "Secrets this item is in", entries)
end

-- PaintRefresh(f): Refresh's warning while the latest read failed (the
-- time on its hover stays the last good read's)
function Panel.PaintRefresh(f)
  local _, failed = nil, false
  if f.opts.readState then _, failed = f.opts.readState() end
  Shown(f.RefreshWarn, failed and f.opts.refresh ~= nil)
end

local function RefreshTip(f, owner)
  local at, failed = nil, false
  if f.opts.readState then at, failed = f.opts.readState() end
  local lines = { "The game sends no word when a hidden step is done, so this tab reads every step again every few seconds." }
  lines[#lines + 1] = at and ("Updated " .. date("%H:%M:%S", at)) or "Not read yet"
  if failed then lines[#lines + 1] = { text = "The last read failed; what shows is from the last good one.", color = U.Colors.CAUTION_ORANGE } end
  Tip(owner, "Read every step again now", lines)
end

local function MakeHead(f)
  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT", f, "TOPLEFT", L.INSET, 0)
  head:SetPoint("TOPRIGHT", f, "TOPRIGHT", -L.INSET, 0)
  head:SetHeight(72)
  head:EnableMouse(true)
  f.Head = head
  -- the secret's name; a menu of the item's secrets behind it when it is in several
  local title = CreateFrame("Button", nil, head)
  title:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
  f.TitleButton = title
  f.Title = Font(title, U.Fonts.TITLE, U.Colors.HIGHLIGHT_WHITE)
  f.Title:SetMaxLines(2)
  f.TitleChevron = title:CreateTexture(nil, "ARTWORK")
  f.TitleChevron:SetSize(7, 11)
  f.TitleChevron:SetAtlas(ATLAS.forward)
  f.TitleChevron:SetRotation(-math.pi / 2)
  title:SetScript("OnClick", function(self) Panel.SecretsMenu(f, self) end)
  title:SetScript("OnEnter", function(self)
    if f.model and #(f.model.secrets or {}) > 1 then Tip(self, "This item is in several secrets", { "Click to show another." }) end
  end)
  title:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- the utilities, quiet, on the right
  f.More = Kit.Text(head, "More", function(self) Panel.MoreMenu(f, self) end, U.Colors.LINK_BLUE)
  f.More:SetScript("OnEnter", function(self) Tip(self, "More", { "Expand or collapse every step in the list, and clear your own marks." }) end)
  f.More:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.Refresh = Kit.Icon(head, ATLAS.refresh, 16, 16, function() if f.opts.refresh then f.opts.refresh() end end)
  f.Refresh:SetScript("OnEnter", function(self) RefreshTip(f, self) end)
  f.Refresh:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.RefreshWarn = head:CreateTexture(nil, "OVERLAY")
  f.RefreshWarn:SetSize(12, 12)
  f.RefreshWarn:SetAtlas(ATLAS.warn)
  f.RefreshWarn:SetPoint("BOTTOMRIGHT", f.Refresh, "BOTTOMRIGHT", 2, -2)
  f.RefreshWarn:Hide()
  f.Forward = Kit.Icon(head, ATLAS.forward, 8, 13, function() if f.opts.forward then f.opts.forward() end end)
  f.Back = Kit.Icon(head, ATLAS.back, 8, 13, function() if f.opts.back then f.opts.back() end end)
  for _, pair in ipairs({ { f.Back, "Previous item" }, { f.Forward, "Next item" } }) do
    pair[1]:SetScript("OnEnter", function(self) Tip(self, pair[2], { "The item you looked at before or after this one." }) end)
    pair[1]:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  -- the item it was opened for: its icon and name (hover: the item's own
  -- tooltip), then its answer (hover: the whole explanation)
  local item = CreateFrame("Frame", nil, head)
  item:EnableMouse(true)
  f.ContextItem = item
  f.ContextIcon = item:CreateTexture(nil, "ARTWORK")
  f.ContextIcon:SetSize(14, 14)
  f.ContextIcon:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0)
  f.ContextIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.ContextName = Font(item, U.Fonts.BODY, U.Colors.LIGHT_GRAY, false)
  f.ContextName:SetPoint("TOPLEFT", item, "TOPLEFT", 18, 0)
  item:SetScript("OnEnter", function(self)
    local itemID = f.context and f.context.itemID
    if not itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    local ok = pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
    if ok then GameTooltip:Show() else GameTooltip:Hide() end
  end)
  item:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local answer = CreateFrame("Frame", nil, head)
  answer:EnableMouse(true)
  f.ContextAnswerHit = answer
  f.ContextAnswer = Font(answer, U.Fonts.BODY, U.Colors.LABEL_GRAY, false)
  f.ContextAnswer:SetPoint("TOPLEFT", answer, "TOPLEFT", 0, 0)
  answer:SetScript("OnEnter", function(self)
    local tip = f.context and f.context.answerTip
    if not tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    if tip(GameTooltip) then GameTooltip:Show() else GameTooltip:Hide() end
  end)
  answer:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- the progress, honestly counted (its hover says what counts)
  f.ProgressHit = CreateFrame("Frame", nil, head)
  f.ProgressHit:EnableMouse(true)
  f.Progress = Font(f.ProgressHit, U.Fonts.DATA, U.Colors.LABEL_GRAY, false)
  f.Progress:SetPoint("TOPLEFT", f.ProgressHit, "TOPLEFT", 0, 0)
  f.ProgressHit:SetScript("OnEnter", function(self)
    Tip(self, "Progress", { "Only steps the game itself reports count as tracked: a hidden flag, a quest turned in, or what a "
      .. "step gives held in your bags, bank or warband bank. Sub-steps count too, so the steps aren't equal parts of the secret.",
      "A step the game can't track (a talk, a walk, an emote) is untracked. You can mark one done for your own checklist; "
        .. "your marks never count as the game's progress." })
  end)
  f.ProgressHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.Divider = head:CreateTexture(nil, "ARTWORK")
  f.Divider:SetHeight(1)
  Tint(f.Divider, U.Colors.DIVIDER_GRAY)
end

-- The item the tab was opened for, as the details window gives it
-- (opts.context: { icon, name, color, itemID, answer, answerColor,
-- answerTip }), else its name alone
local function Context(f, model)
  local ctx = f.opts.context and f.opts.context() or nil
  if type(ctx) ~= "table" then
    local itemID = model.itemID
    local name = itemID and Recollect.Facts.Item.Name(itemID) or nil
    ctx = { itemID = itemID, name = name or "this item" }
    local ok, icon = pcall(Model().seams.ItemIcon, itemID)
    ctx.icon = ok and icon or nil
  end
  return ctx
end

local function PaintHead(f, model, width)
  local head = f.Head
  local inner = width - 2 * L.INSET
  -- the right side of the first row: More, Refresh, then the item history
  local right = 0
  f.More:SetLabel("More")
  f.More:ClearAllPoints()
  f.More:SetPoint("TOPRIGHT", head, "TOPRIGHT", 0, 0)
  f.More:SetActive(f.opts.menu ~= nil)
  f.More:Show()
  right = right + Size(f.More:GetWidth(), 40) + 8
  local anchor = f.More
  if f.opts.refresh then
    f.Refresh:ClearAllPoints()
    f.Refresh:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
    f.Refresh:SetActive(true)
    f.Refresh:Show()
    anchor, right = f.Refresh, right + L.ICON_BTN + 8
  else
    f.Refresh:Hide()
  end
  Panel.PaintRefresh(f)
  local history = f.opts.history and f.opts.history() or nil
  if history then
    f.Forward:ClearAllPoints()
    f.Forward:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
    f.Back:ClearAllPoints()
    f.Back:SetPoint("RIGHT", f.Forward, "LEFT", -2, 0)
    f.Back:SetActive(history.canBack)
    f.Forward:SetActive(history.canForward)
    f.Back:Show()
    f.Forward:Show()
    right = right + 2 * L.ICON_BTN + 10
  else
    f.Back:Hide()
    f.Forward:Hide()
  end
  -- the secret's name, wrapped short of the utilities
  local several = #(model.secrets or {}) > 1
  local tw = math.max(80, inner - right - (several and 16 or 0))
  local th = Place(f.Title, model.name or "A secret", 0, 0, tw, U.Colors.HIGHLIGHT_WHITE)
  local used = math.min(tw, math.ceil(Size(f.Title:GetStringWidth(), tw)))
  f.TitleChevron:ClearAllPoints()
  f.TitleChevron:SetPoint("TOPLEFT", f.TitleButton, "TOPLEFT", used + 6, -4)
  Shown(f.TitleChevron, several)
  f.TitleButton:SetSize(used + (several and 16 or 4), math.max(th, 18))
  local y = -math.max(th, L.ICON_BTN) - 6
  -- the second row: the item and its answer on the left, the progress on the right
  local ctx = Context(f, model)
  f.context = ctx
  if ctx.icon then f.ContextIcon:SetTexture(ctx.icon) end
  Shown(f.ContextIcon, ctx.icon ~= nil)
  local name = tostring(ctx.name or "this item")
  if ctx.color then name = ("|cFF%s%s|r"):format(Hex(ctx.color), name) end
  f.ContextName:SetText(("|cFF%sOpened for:|r %s"):format(Hex(U.Colors.LABEL_GRAY), name))
  local nameW = math.ceil(Size(f.ContextName:GetStringWidth(), 160))
  f.ContextItem:ClearAllPoints()
  f.ContextItem:SetPoint("TOPLEFT", head, "TOPLEFT", 0, y)
  f.ContextItem:SetSize(nameW + 18, 16)
  f.ContextItem:Show()
  local progress = model.notFor or model.progressShort or model.progress or ""
  f.Progress:SetText(progress)
  SetColor(f.Progress, model.notFor and U.Colors.CAUTION_ORANGE or model.complete and U.Colors.SAGE_GREEN or U.Colors.LABEL_GRAY)
  local pw = math.ceil(Size(f.Progress:GetStringWidth(), 200))
  local narrow = width < L.NARROW
  local answerW = math.max(40, inner - nameW - 18 - 8 - (narrow and 0 or pw + 16))
  f.ContextAnswer:SetWidth(answerW)
  f.ContextAnswer:SetText(ctx.answer or "")
  if ctx.answerColor then SetColor(f.ContextAnswer, ctx.answerColor) else SetColor(f.ContextAnswer, U.Colors.LABEL_GRAY) end
  f.ContextAnswerHit:ClearAllPoints()
  f.ContextAnswerHit:SetPoint("TOPLEFT", head, "TOPLEFT", nameW + 18 + 8, y)
  f.ContextAnswerHit:SetSize(answerW, 16)
  Shown(f.ContextAnswerHit, (ctx.answer or "") ~= "")
  local rowH = math.max(16, math.ceil(Size(f.ContextName:GetStringHeight(), 14)))
  f.ProgressHit:ClearAllPoints()
  if narrow then
    y = y - rowH - 4
    f.ProgressHit:SetPoint("TOPLEFT", head, "TOPLEFT", 0, y)
  else
    f.ProgressHit:SetPoint("TOPRIGHT", head, "TOPRIGHT", 0, y)
  end
  f.ProgressHit:SetSize(pw + 4, 14)
  f.ProgressHit:Show()
  y = y - rowH - 6
  f.Divider:ClearAllPoints()
  f.Divider:SetPoint("TOPLEFT", head, "TOPLEFT", 0, y)
  f.Divider:SetPoint("TOPRIGHT", head, "TOPRIGHT", 0, y)
  f.Divider:Show()
  head:SetHeight(-y + 1)
  head:Show()
end

-------------------------------------------------------------------------------
-- Selection
-------------------------------------------------------------------------------
-- ShowInTree(f, selection): the explorer scrolled so the selection's row shows
function Panel.ShowInTree(f, selection)
  local row = f.treeRowFor and f.treeRowFor[selection]
  if not (row and row:IsShown()) then return end
  local top = -Size(select(5, row:GetPoint(1)), 0)
  local view = Size(f.TreeScroll:GetHeight(), 0)
  local now = Size(f.TreeScroll:GetVerticalScroll(), 0)
  local h = Size(row:GetHeight(), L.ROW_MIN)
  if top >= now and top + h <= now + view then return end
  local range = Size(f.TreeScroll:GetVerticalScrollRange(), 0)
  f.TreeScroll:SetVerticalScroll(math.max(0, math.min(top - math.floor(view / 3), range)))
end

-- Select(f, selection): a step's label, "stage:<key>" or "summary" shown in
-- the reader and kept for this owner, secret and item; the explorer opens
-- what holds a step and scrolls to it. False when the model has no such page
function Panel.Select(f, selection)
  local model = f.model
  if not (model and Model().Split(model) and Model().Valid(model, selection)) then return false end
  Model().Select(model, selection)
  if model.byLabel[selection] then Model().Reveal(model, selection) end
  Panel.Paint(f, model, true)
  Panel.ShowInTree(f, selection)
  return true
end

-- RevealStep(f, label): a step link's click, Suggested next and the item's
-- own step: that step selected and shown in the list
function Panel.RevealStep(f, label)
  if f.model and label then return Panel.Select(f, label) end
  return false
end

-- SetFilter(f, filter): the explorer's filter ("all", "todo", "mine"), kept
-- per owner and secret; the page being read stays
function Panel.SetFilter(f, filter)
  local model = f.model
  if not model then return end
  Model().SetFilter(model, filter)
  f.treeOffset = 0
  Panel.Paint(f, model, true)
  f.treeOffset = false
end

-- SetSearch(f, text): the explorer's search, for this panel only
function Panel.SetSearch(f, text)
  f.search = tostring(text or "")
  if f.model then
    f.treeOffset = 0
    Panel.Paint(f, f.model, true)
    f.treeOffset = false
  end
end

-- SearchEnter(f): Enter in the search opens the first matching step
function Panel.SearchEnter(f)
  local model = f.model
  if not model then return end
  for _, item in ipairs(Model().Tree(model, Model().Filter(model), f.search)) do
    if item.row and not item.context then return Panel.Select(f, item.row.label) end
  end
end

-- RevealInList(f): the filter and the search cleared, the page's step shown in the list
function Panel.RevealInList(f)
  local model = f.model
  if not model then return end
  Model().SetFilter(model, "all")
  f.search = ""
  if f.Search and f.Search.SetText then f.Search:SetText("") end
  return Panel.Select(f, f.selection)
end

-------------------------------------------------------------------------------
-- The explorer: Search and the filters fixed at the top, then Summary &
-- rewards, the stages and the steps, Suggested next fixed at the bottom
-------------------------------------------------------------------------------
local function RowTip(f, row)
  local data = f.model and f.model.byLabel and f.model.byLabel[row.label]
  if not data then return end
  local lines = {}
  if row.Title:IsTruncated() then lines[#lines + 1] = row.fullTitle end
  if data.own and data.entry then
    lines[#lines + 1] = { text = "This item: " .. tostring(data.entry.roleWords or "in this step"), color = U.Colors.INFO_BLUE }
  end
  if data.marked then lines[#lines + 1] = { text = "Marked by you, for your own checklist", color = U.Colors.INFO_BLUE }
  elseif data.untracked then lines[#lines + 1] = "Not tracked by the game" end
  if data.suggested then lines[#lines + 1] = { text = tostring(data.suggested), color = U.Colors.STATUS_GOLD } end
  Tip(row, "Step " .. tostring(row.label), lines)
end

local function MakeTreeRow(f)
  local row = CreateFrame("Button", nil, f.Tree)
  Kit.Selectable(row)
  local hover = row:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  Tint(hover, U.Colors.HOVER_HIGHLIGHT)
  row.Mark = row:CreateTexture(nil, "ARTWORK")
  row.Mark:SetSize(L.MARK, L.MARK)
  row.Box = Kit.Box(row, L.MARK + 4)
  row.Label = Font(row, U.Fonts.DATA, U.Colors.LABEL_GRAY, false)
  row.Item = row:CreateTexture(nil, "ARTWORK")
  row.Item:SetSize(L.ITEM_ICON, L.ITEM_ICON)
  row.Item:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.Title = Font(row, U.Fonts.BODY, U.Colors.LIGHT_GRAY)
  row.Title:SetMaxLines(2)
  row.Next = Kit.NextMarker(row)
  row.Next:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  -- a step's sub-steps open and close here (the unfiltered list only)
  row.Fold = Kit.Disclosure(row, function(self)
    local model = f.model
    if not (model and self.label) then return end
    Model().SetFold(model.ownerKey, model.sid, "p", self.label, not self.open)
    Panel.Repaint(f)
  end)
  row.label, row.selection, row.fullTitle = false, false, false
  row:SetScript("OnClick", function(self) if self.selection then Panel.Select(f, self.selection) end end)
  row:SetScript("OnEnter", function(self) RowTip(f, self) end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:Hide()
  return row
end

local function MakeTreeStage(f)
  local h = CobySuite_Recollect.UI.CreateCollapsibleHeader(f.Tree, { height = L.STAGE_H, iconSize = 1, pad = 8,
    titleFont = U.Fonts.BODY, titleY = 0, summaryGap = 2 })
  -- the stage's name and counts, no product icon and no plus or minus: the chevron on the left folds it
  h.Icon:Hide()
  h.Arrow:Hide()
  h.ArrowGlow:Hide()
  h.Title:ClearAllPoints()
  h.Title:SetPoint("TOPLEFT", h, "TOPLEFT", L.DISCLOSE + 2, -5)
  h.Title:SetPoint("RIGHT", h, "RIGHT", -16, 0)
  h.Summary:ClearAllPoints()
  h.Summary:SetPoint("TOPLEFT", h.Title, "BOTTOMLEFT", 0, -2)
  h.Summary:SetPoint("RIGHT", h, "RIGHT", -16, 0)
  Kit.Selectable(h)
  h.Chevron = Kit.Disclosure(h, function(self)
    local model = f.model
    if not (model and h.key) then return end
    Model().SetFold(model.ownerKey, model.sid, "s", h.key, not h.open)
    Panel.Repaint(f)
  end)
  h.Chevron:SetPoint("LEFT", h, "LEFT", 1, 0)
  h.Chevron:Show()
  -- a click on the stage itself shows its page
  h:SetScript("OnClick", function(self)
    if self.key then Panel.Select(f, "stage:" .. self.key) end
  end)
  -- a name or counts cut at a narrow explorer read whole on hover (the spec's
  -- explorer titles; Task #430's first in-game run cut both at 620 wide)
  h:SetScript("OnEnter", function(self)
    if not (self.Title:IsTruncated() or self.Summary:IsTruncated()) then return end
    Tip(self, tostring(self.Title:GetText() or ""), { tostring(self.Summary:GetText() or "") })
  end)
  h:SetScript("OnLeave", function() GameTooltip:Hide() end)
  h:Hide()
  return h
end

local function MakeSummaryRow(f)
  local row = CreateFrame("Button", nil, f.Tree)
  row:SetHeight(L.SUMMARY_H)
  Kit.Selectable(row)
  local hover = row:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  Tint(hover, U.Colors.HOVER_HIGHLIGHT)
  row.Title = Font(row, U.Fonts.BODY, U.Colors.LIGHT_GRAY, false)
  row.Title:SetPoint("LEFT", row, "LEFT", L.DISCLOSE + 2, 0)
  row.Title:SetText("Summary & rewards")
  row:SetScript("OnClick", function() Panel.Select(f, Model().SUMMARY) end)
  row:Hide()
  return row
end

-- CodeWidth(f, model): the code column's width, the widest step code of the
-- secret as the code font paints it (measured once per model), so the title
-- starts right after the code
local codeMeasure = setmetatable({}, { __mode = "k" })
local function CodeWidth(f, model)
  if rawget(model, "codeW") then return model.codeW end
  local fs = codeMeasure[f]
  if not fs then
    fs = Font(f.Tree, U.Fonts.DATA, U.Colors.LABEL_GRAY, false)
    fs:Hide()
    codeMeasure[f] = fs
  end
  local widest = 0
  for label in pairs(model.byLabel or {}) do
    fs:SetText(tostring(label))
    widest = math.max(widest, Size(fs:GetStringWidth(), 7 * #tostring(label)))
  end
  model.codeW = math.max(L.CODE, math.ceil(widest) + 2)
  return model.codeW
end

-- A step's row, one line at about 22 px (two only when the title needs it):
-- the fold slot (kept on a leaf, so titles line up), its mark, its code, this
-- item's icon when the secret has any step of it, then the title right after;
-- selection, this item and the suggestion each marked apart. Returns its height
local function PaintTreeRow(f, row, item, y, width, selection, holds)
  local data = item.row
  local model = f.model
  row.label, row.selection = data.label, data.label
  row.fullTitle = Panel.PlainText(data.short or data.title or data.text or "")
  local codeW = CodeWidth(f, model)
  local hasIcon = f.itemIcon and #(model.itemSteps or {}) > 0
  local foldX = 1 + (item.depth or 0) * L.INDENT
  local markX = foldX + L.DISCLOSE
  local labelX = markX + L.MARK + 3
  local iconX = labelX + codeW + 3
  local x = hasIcon and iconX + L.ITEM_ICON + 4 or iconX
  local color = (data.done or item.context) and U.Colors.LABEL_GRAY or selection == data.label and U.Colors.HIGHLIGHT_WHITE
    or U.Colors.LIGHT_GRAY
  local reserve = data.suggested and L.NEXT_W + 10 or 8
  local h = Place(row.Title, row.fullTitle, x, -4, width - x - reserve, color)
  local height = h > 16 and L.ROW_TWO or L.ROW_MIN
  row.Title:ClearAllPoints()
  row.Title:SetPoint("LEFT", row, "LEFT", x, 0)
  if item.childrenOpen ~= nil and data.children then
    row.Fold:SetOpen(item.childrenOpen)
    row.Fold.label = data.label
    row.Fold:ClearAllPoints()
    row.Fold:SetPoint("LEFT", row, "LEFT", foldX, 0)
    row.Fold:Show()
  else
    row.Fold:Hide()
  end
  row.Mark:ClearAllPoints()
  row.Mark:SetPoint("LEFT", row, "LEFT", markX, 0)
  Shown(row.Mark, Recollect.UI.Icons.Paint(row.Mark, data.mark) and true or false)
  row.Box:ClearAllPoints()
  row.Box:SetPoint("CENTER", row.Mark, "CENTER", 0, 0)
  Shown(row.Box, data.marked)
  row.Label:ClearAllPoints()
  row.Label:SetPoint("LEFT", row, "LEFT", labelX, 0)
  row.Label:SetWidth(codeW)
  row.Label:SetText(data.label)
  row.Item:ClearAllPoints()
  row.Item:SetPoint("LEFT", row, "LEFT", iconX, 0)
  if data.own and f.itemIcon then row.Item:SetTexture(f.itemIcon) end
  Shown(row.Item, data.own and hasIcon and true or false)
  Shown(row.Next, data.suggested)
  row.Holds:ClearAllPoints()
  row.Holds:SetPoint("RIGHT", row, "RIGHT", data.suggested and -(L.NEXT_W + 10) or -8, 0)
  Selected(row, selection == data.label, holds)
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", f.Tree, "TOPLEFT", 0, y)
  row:SetSize(width, height)
  row:Show()
  return height
end

local function PaintTreeStage(f, h, item, y, width, selection, holds)
  local stage = item.stage
  h:ClearAllPoints()
  h:SetPoint("TOPLEFT", f.Tree, "TOPLEFT", 0, y)
  h:SetWidth(width)
  h.Title:SetText(stage.title)
  h.Summary:SetText(stage.short or "")
  h.key, h.open = stage.key, item.open and true or false
  h.Chevron:SetOpen(h.open)
  h.Chevron:SetShown(not f.narrowed)
  Selected(h, selection == "stage:" .. stage.key, holds)
  h:Show()
  return L.STAGE_H
end

-- The filters: one segmented group, the one in use lit gold
local function PaintChips(f, filter, x, y, w)
  local each = math.floor((w - 2 * 2) / 3)
  for i, chip in ipairs(f.Chips) do
    local on = chip.filter == filter
    chip:ClearAllPoints()
    chip:SetPoint("TOPLEFT", f.Explorer, "TOPLEFT", x + (i - 1) * (each + 2), y)
    chip:SetSize(each, L.SEG_H)
    Shown(chip.On, on)
    SetColor(chip.Text, on and U.Colors.STATUS_GOLD or U.Colors.LIGHT_GRAY)
    local words = Model().FILTER_WORDS[chip.filter]
    if chip.filter == "mine" then words = ("%s (%d)"):format(words, #(f.model and f.model.itemSteps or {})) end
    chip.Text:SetText(words)
    chip:Show()
  end
end

local function MakeChip(f, parent, filter)
  local chip = CreateFrame("Button", nil, parent)
  chip:SetSize(60, L.SEG_H)
  chip.filter = filter
  local bg = chip:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  Tint(bg, U.Colors.CONTENT_BG)
  chip.On = chip:CreateTexture(nil, "BORDER")
  chip.On:SetAllPoints()
  Tint(chip.On, U.Colors.STATUS_GOLD, 0.18)
  local hover = chip:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  Tint(hover, U.Colors.HOVER_HIGHLIGHT)
  chip.Text = Font(chip, U.Fonts.DATA, U.Colors.LIGHT_GRAY, false)
  chip.Text:SetPoint("CENTER", chip, "CENTER", 0, 0)
  chip.Text:SetJustifyH("CENTER")
  chip.Text:SetText(Model().FILTER_WORDS[filter])
  chip:SetScript("OnClick", function(self) Panel.SetFilter(f, self.filter) end)
  return chip
end

-- Suggested next, fixed under the list: its code and short title; a click shows it
local function PaintSuggest(f, model, ew)
  local s = model.suggestion
  local b = f.Suggest
  local row = s and model.byLabel and model.byLabel[s.step]
  if not row then
    b.label = false
    b:Hide()
    return 0
  end
  b.label, b.check, b.head = s.step, s.check, s.label
  b:SetWidth(ew)
  b.Head:SetText(s.label)
  b.Text:SetWidth(ew - 2 * L.EXP_PAD - L.NEXT_W - 10)
  b.title = Panel.PlainText(row.short or row.title or "")
  b.Text:SetText(("|cFF%s%s|r  %s"):format(Hex(U.Colors.LABEL_GRAY), s.step, b.title))
  b:Show()
  return L.SUGGEST_H
end

local function MakeSuggest(f, parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(L.SUGGEST_H)
  b:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  Tint(bg, U.Colors.ALT_ROW_BG)
  local line = b:CreateTexture(nil, "ARTWORK")
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  line:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
  Tint(line, U.Colors.DIVIDER_GRAY)
  local hover = b:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  Tint(hover, U.Colors.HOVER_HIGHLIGHT)
  b.Head = Font(b, U.Fonts.DATA, U.Colors.STATUS_GOLD, false)
  b.Head:SetPoint("TOPLEFT", b, "TOPLEFT", L.EXP_PAD, -5)
  b.Text = Font(b, U.Fonts.BODY, U.Colors.LIGHT_GRAY, false)
  b.Text:SetPoint("TOPLEFT", b.Head, "BOTTOMLEFT", 0, -2)
  b.Arrow = Kit.NextMarker(b)
  b.Arrow:SetPoint("RIGHT", b, "RIGHT", -8, 0)
  b.Arrow:Show()
  b.label, b.check, b.title = false, false, false
  b:SetScript("OnClick", function(self) if self.label then Panel.RevealStep(f, self.label) end end)
  b:SetScript("OnEnter", function(self)
    local lines = { "Click to show this step." }
    if self.title and self.Text:IsTruncated() then table.insert(lines, 1, self.title) end
    if self.check then lines[#lines + 1] = { text = self.check, color = U.Colors.CAUTION_ORANGE } end
    Tip(self, tostring(self.head or "Suggested next") .. ": step " .. tostring(self.label), lines)
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  return b
end

local function PaintTree(f, model, selection, ew)
  local width = ew - L.SCROLLBAR
  local filter = Model().Filter(model)
  f.narrowed = Model().Filtered(filter, f.search)
  -- the search and the filters, except for a secret of a few steps
  local top = L.EXP_PAD
  if not model.small then
    if f.Search then
      f.Search:ClearAllPoints()
      f.Search:SetPoint("TOPLEFT", f.Explorer, "TOPLEFT", L.EXP_PAD + 4, -top)
      f.Search:SetWidth(ew - 2 * L.EXP_PAD - 4)
      f.Search:Show()
    end
    top = top + L.SEARCH_H + 6
    PaintChips(f, filter, L.EXP_PAD, -top, ew - 2 * L.EXP_PAD)
    top = top + L.SEG_H + 4
  else
    if f.Search then f.Search:Hide() end
    for _, chip in ipairs(f.Chips) do chip:Hide() end
    f.narrowed = false
    filter = "all"
  end
  local foot = PaintSuggest(f, model, ew)
  f.TreeScroll:ClearAllPoints()
  f.TreeScroll:SetPoint("TOPLEFT", f.Explorer, "TOPLEFT", 0, -top)
  f.TreeScroll:SetPoint("BOTTOMRIGHT", f.Explorer, "BOTTOMRIGHT", -L.SCROLLBAR, foot + 2)
  f.Tree:SetWidth(width)
  f.treeRowFor = {}
  -- where the selection lives, for a folded branch's gold mark
  local selRow = model.byLabel and model.byLabel[selection]
  local selStage = selRow and Model().StageOf(model, selRow.index)
  local y = 0
  f.SummaryRow:ClearAllPoints()
  f.SummaryRow:SetPoint("TOPLEFT", f.Tree, "TOPLEFT", 0, y)
  f.SummaryRow:SetWidth(width)
  Selected(f.SummaryRow, selection == Model().SUMMARY)
  SetColor(f.SummaryRow.Title, selection == Model().SUMMARY and U.Colors.HIGHLIGHT_WHITE or U.Colors.LIGHT_GRAY)
  f.SummaryRow:Show()
  f.treeRowFor[Model().SUMMARY] = f.SummaryRow
  y = y - L.SUMMARY_H
  local rows, stages = 0, 0
  local tree = Model().Tree(model, filter, f.search)
  for _, item in ipairs(tree) do
    if item.stage then
      stages = stages + 1
      local h = Pooled(f.TreeStages, stages, function() return MakeTreeStage(f) end)
      if h then
        if stages > 1 or rows > 0 then y = y - 3 end
        y = y - PaintTreeStage(f, h, item, y, width, selection, not item.open and selStage == item.stage)
        f.treeRowFor["stage:" .. item.stage.key] = h
      else
        f.incomplete = true
      end
    else
      rows = rows + 1
      local row = Pooled(f.TreeRows, rows, function() return MakeTreeRow(f) end)
      if row then
        local holds = item.row.children and item.childrenOpen == false and selRow and selRow.parent == item.row.label
        y = y - PaintTreeRow(f, row, item, y, width, selection, holds)
        f.treeRowFor[item.row.label] = row
      else
        f.incomplete = true
      end
    end
  end
  for i = rows + 1, #f.TreeRows do f.TreeRows[i]:Hide() end
  for i = stages + 1, #f.TreeStages do f.TreeStages[i]:Hide() end
  -- an empty list says why, and To do's offers the whole list back
  f.ShowAll:Hide()
  if #tree == 0 then
    local todo = filter == "todo" and not Model().Filtered("all", f.search)
    y = y - Place(f.TreeEmpty, todo and "Nothing left on this checklist" or "No matching steps", L.EXP_PAD, y - 6,
      width - 2 * L.EXP_PAD, U.Colors.LABEL_GRAY) - 10
    if todo then
      f.ShowAll:ClearAllPoints()
      f.ShowAll:SetPoint("TOPLEFT", f.Tree, "TOPLEFT", L.EXP_PAD - 2, y)
      f.ShowAll:Show()
      y = y - L.BUTTON_H - 4
    end
  elseif f.incomplete then
    y = y - Place(f.TreeEmpty, "More steps show once combat ends.", L.EXP_PAD, y - 6, width - 2 * L.EXP_PAD,
      U.Colors.LABEL_GRAY) - 10
  else
    f.TreeEmpty:Hide()
  end
  f.Tree:SetHeight(-y + 6)
  f.TreeScroll:UpdateScrollChildRect()
  local range = Size(f.TreeScroll:GetVerticalScrollRange(), 0)
  local offset = f.treeOffset or Model().Scroll(model.ownerKey, model.sid)
  f.TreeScroll:SetVerticalScroll(math.max(0, math.min(offset or 0, range)))
end

-------------------------------------------------------------------------------
-- The reader: one page, measured, its text at most 680 wide; the pager
-- fixed in its footer for a step's page
-------------------------------------------------------------------------------
local Page = {}

function Page.Line(f, n)
  return Pooled(f.PageLines, n, function() return Font(f.Page, U.Fonts.BODY, U.Colors.LIGHT_GRAY) end)
end

-- Page.Text(f, p, line, x, w, font, seen): a model line on the page at p.y; p.y moves under it
function Page.Text(f, p, line, x, w, font, seen)
  p.n = p.n + 1
  local fs = Page.Line(f, p.n)
  if not fs then
    f.incomplete = true
    return 0
  end
  fs:SetFontObject(font or FONTS[line.font] or U.Fonts.BODY)
  local h = Place(fs, Painted(f, line, seen), x, p.y, w, line.color or U.Colors.LIGHT_GRAY)
  p.y = p.y - h - L.LINE_GAP
  return h
end

-- Page.Heading(f, p, text, sub): a section's heading (or a smaller one under it)
function Page.Heading(f, p, text, sub)
  p.heads = p.heads + 1
  local fs = Pooled(f.PageHeads, p.heads, function() return Font(f.Page, U.Fonts.HEADING, U.Colors.HIGHLIGHT_WHITE, false) end)
  if not fs then return end
  p.y = p.y - (sub and 4 or L.SECTION_GAP)
  fs:SetFontObject(sub and U.Fonts.DATA or U.Fonts.HEADING)
  local h = Place(fs, text, p.x, p.y, p.w, sub and U.Colors.LABEL_GRAY or U.Colors.HIGHLIGHT_WHITE)
  p.y = p.y - h - 4
end

-- The page's top: the breadcrumb (stage and step, plain) and the title, plain and large
function Page.Top(f, p, crumb, title, color)
  p.y = p.y - Place(f.Kicker, crumb, p.x, p.y, p.w, U.Colors.LABEL_GRAY) - 3
  p.y = p.y - Place(f.ReadTitle, title, p.x, p.y, p.w, color or U.Colors.HIGHLIGHT_WHITE) - 6
end

-- A row of the requirements table, or of an any-N step's choices
local function MakeReq(f)
  local r = CreateFrame("Frame", nil, f.Page)
  r:EnableMouse(true)
  if f.opts.links then f.opts.links(r) end
  r.Mark = r:CreateTexture(nil, "ARTWORK")
  r.Mark:SetSize(12, 12)
  r.Name = Font(r, U.Fonts.BODY, U.Colors.LIGHT_GRAY)
  r.Need = Font(r, U.Fonts.BODY, U.Colors.LIGHT_GRAY, false)
  r.Owned = Font(r, U.Fonts.BODY, U.Colors.LIGHT_GRAY, false)
  r.Missing = Font(r, U.Fonts.BODY, U.Colors.LIGHT_GRAY, false)
  r.Detail = Font(r, U.Fonts.DATA, U.Colors.LABEL_GRAY)
  for _, fs in ipairs({ r.Need, r.Owned, r.Missing }) do fs:SetJustifyH("RIGHT") end
  r:Hide()
  return r
end

-- Page.Req(f, p, cells): one table row at p.y: { name (painted), need,
-- owned, missing, missingColor, mark, header }; narrow, the counts go under the
-- name. An any-N choice's row has one state in place of the counts ({ name,
-- state, stateColor, mark }): at its own measured width on the right, or
-- alone under the name when narrow (Task #430: "Not o..." in a count's
-- column, "Owned Not owned" under the name)
function Page.Req(f, p, cells)
  p.reqs = p.reqs + 1
  local r = Pooled(f.ReqRows, p.reqs, function() return MakeReq(f) end)
  if not r then
    f.incomplete = true
    return
  end
  local narrow = p.narrow
  local x = cells.mark and 18 or 0
  Shown(r.Mark, cells.mark and Recollect.UI.Icons.Paint(r.Mark, cells.mark) and true or false)
  r.Mark:ClearAllPoints()
  r.Mark:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -1)
  local stateW = 0
  if cells.state and not narrow then
    r.Owned:SetFontObject(U.Fonts.BODY)
    r.Owned:SetWidth(p.w)
    r.Owned:SetText(cells.state)
    stateW = math.ceil(Size(r.Owned:GetStringWidth(), L.NUM_W)) + 4
  end
  local nameW = narrow and (p.w - x) or cells.state and (p.w - x - stateW - 12) or (p.w - x - 3 * L.NUM_W)
  r.Name:SetFontObject(cells.header and U.Fonts.DATA or U.Fonts.BODY)
  local h = Place(r.Name, cells.name or "", x, 0, nameW, cells.header and U.Colors.LABEL_GRAY or U.Colors.LIGHT_GRAY)
  local cols = { { r.Need, cells.need }, { r.Owned, cells.owned }, { r.Missing, cells.missing, cells.missingColor } }
  if cells.state then
    r.Need:Hide()
    r.Missing:Hide()
    if narrow then
      r.Owned:Hide()
      h = h + 2 + Place(r.Detail, cells.state, x, -h - 2, nameW, cells.stateColor or U.Colors.LABEL_GRAY)
    else
      r.Detail:Hide()
      r.Owned:ClearAllPoints()
      r.Owned:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
      r.Owned:SetWidth(stateW)
      SetColor(r.Owned, cells.stateColor or U.Colors.LIGHT_GRAY)
      r.Owned:Show()
    end
  elseif narrow then
    for _, c in ipairs(cols) do c[1]:Hide() end
    local parts = {}
    for i, label in ipairs({ "Need", "Owned", "Missing" }) do
      if cols[i][2] and cols[i][2] ~= "" then parts[#parts + 1] = label .. " " .. cols[i][2] end
    end
    if #parts > 0 and not cells.header then
      h = h + 2 + Place(r.Detail, table.concat(parts, "; "), x, -h - 2, nameW, U.Colors.LABEL_GRAY)
    else
      r.Detail:Hide()
    end
  else
    r.Detail:Hide()
    for i, c in ipairs(cols) do
      local fs = c[1]
      fs:SetFontObject(cells.header and U.Fonts.DATA or U.Fonts.BODY)
      fs:ClearAllPoints()
      fs:SetPoint("TOPRIGHT", r, "TOPRIGHT", -(3 - i) * L.NUM_W, 0)
      fs:SetWidth(L.NUM_W - 6)
      fs:SetText(c[2] or "")
      SetColor(fs, cells.header and U.Colors.LABEL_GRAY or c[3] or U.Colors.LIGHT_GRAY)
      fs:Show()
    end
  end
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", f.Page, "TOPLEFT", p.x, p.y)
  r:SetSize(p.w, h)
  r:Show()
  p.y = p.y - h - 6
end

-- You need: the items in rows (Item, Need, Owned, Missing), what owned
-- counts, then an any-N step's choices, each with whether you own it
function Page.Needs(f, p, model, row)
  local needs, any = row.needs or {}, row.any
  if #needs == 0 and not any then return end
  Page.Heading(f, p, "You need")
  local viewer = model.owner and model.owner.isViewer
  local seen = {}
  if #needs > 0 then
    Page.Req(f, p, { header = true, name = "Item", need = "Need", owned = "Owned", missing = "Missing" })
    for _, need in ipairs(needs) do
      local name = Painted(f, { text = need.name, links = need.link and { need.link } or nil }, seen)
      if need.tool and not need.unsure then name = name .. ("|cFF%s (you keep it)|r"):format(Hex(U.Colors.LABEL_GRAY)) end
      local owned, missing, color = "Unknown", "", nil
      if row.done then
        owned = ""
      elseif need.owned then
        owned, missing = tostring(need.owned), tostring(need.missing)
        color = need.missing > 0 and U.Colors.CAUTION_ORANGE or U.Colors.SAGE_GREEN
      end
      Page.Req(f, p, { name = name, need = tostring(need.need), owned = owned, missing = missing, missingColor = color })
    end
    local note = row.done and "Counts aren't shown for a step that's done."
      or viewer and "Owned includes bags, bank and warband bank. Owning them doesn't mean every other need is met."
      or "Counts aren't read on another character's copy."
    Page.Text(f, p, { text = note, color = U.Colors.LABEL_GRAY, font = "data" }, p.x, p.w)
  end
  if any then
    if #needs > 0 then p.y = p.y - 6 end
    Page.Text(f, p, { text = any.count == 1 and "Bring any one of these." or ("Bring %d different ones of these."):format(any.count) },
      p.x, p.w)
    Page.Text(f, p, { text = any.readable and ("You own %d of the listed choices. The list here may not be complete."):format(any.held)
      or "The list here may not be complete.", color = U.Colors.LABEL_GRAY, font = "data" }, p.x, p.w)
    for _, choice in ipairs(any.items) do
      local mark, owned, color = "wait", "Unknown", U.Colors.LABEL_GRAY
      if choice.owned ~= nil then
        mark = choice.owned > 0 and "done" or "pending"
        owned = choice.owned > 0 and ("Owned " .. choice.owned) or "Not owned"
        color = choice.owned > 0 and U.Colors.SAGE_GREEN or U.Colors.LIGHT_GRAY
      end
      Page.Req(f, p, { mark = viewer and mark or nil, name = Painted(f, { text = choice.name, links = choice.link and { choice.link }
        or nil }, seen), state = owned, stateColor = color })
    end
  end
end

-- A step's state: its mark and words, then, on a step the game can't track
-- on the player's own copy, the checklist box ("Marked by you" when ticked)
function Page.State(f, p, model, row, lines)
  if #lines == 0 then return end
  f.StateMark:ClearAllPoints()
  f.StateMark:SetPoint("TOPLEFT", f.Page, "TOPLEFT", p.x, p.y)
  local mark = row.marked and "untracked" or row.mark
  Shown(f.StateMark, Recollect.UI.Icons.Paint(f.StateMark, mark) and true or false)
  local sx = p.x + L.MARK + 6
  for _, line in ipairs(lines) do Page.Text(f, p, line, sx, p.w - (sx - p.x), U.Fonts.BODY) end
  if row.checklist and model.owner and model.owner.isViewer then
    local cb = f.ReadOwn
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", f.Page, "TOPLEFT", p.x - 3, p.y + 2)
    cb.label, cb.marked = row.label, row.marked and true or false
    cb:SetChecked(cb.marked)
    cb:Show()
    f.MarkedNote:ClearAllPoints()
    local labelW = math.ceil(Size(cb.text and cb.text:GetStringWidth(), 150))
    f.MarkedNote:SetPoint("TOPLEFT", f.Page, "TOPLEFT", p.x - 3 + L.BUTTON_H + 4 + labelW + 12, p.y - 5)
    f.MarkedNote:SetText("Marked by you")
    Shown(f.MarkedNote, cb.marked)
    p.y = p.y - L.BUTTON_H - 4
  end
end

-- One place: its name and coordinates, then its one action, the pin and Set
-- waypoint (Choose location for several), beside it when there is room
function Page.Place(f, p, line, seen)
  local start = p.y
  local w = p.w
  p.n = p.n + 1
  local fs = Page.Line(f, p.n)
  if not fs then
    f.incomplete = true
    return
  end
  fs:SetFontObject(U.Fonts.BODY)
  local h = Place(fs, Painted(f, line, seen), p.x, p.y, w - 150, U.Colors.LIGHT_GRAY)
  if not line.pin then
    p.y = p.y - h - L.LINE_GAP
    return
  end
  p.pins = p.pins + 1
  local pin = Pooled(f.PagePins, p.pins, function() return MakePin(f, f.Page) end)
  if not pin then
    f.incomplete = true
    p.y = p.y - h - L.LINE_GAP
    return
  end
  pin.places, pin.title = line.pin.places, line.pin.title
  pin.Label:SetText(#line.pin.places > 1 and "Choose location" or "Set waypoint")
  pin:SetWidth(L.PIN + 4 + math.ceil(Size(pin.Label:GetStringWidth(), 100)) + 4)
  local textW = math.min(math.ceil(Size(fs:GetStringWidth(), w - 150)), w - 150)
  pin:ClearAllPoints()
  pin:SetPoint("TOPLEFT", f.Page, "TOPLEFT", p.x + textW + 12, start + math.floor((L.PIN_H - math.min(h, 16)) / 2))
  pin:Show()
  p.y = start - math.max(h, L.PIN_H - 6) - L.LINE_GAP
end

-- Locations: where the step is done, then, apart, the places its words only
-- name, under Other places mentioned even when the step has no place of its
-- own (Task #430: step 12I's only place, Griftah, a supplier its words name,
-- read as the step's destination right under Locations)
function Page.Places(f, p, lines)
  if #lines == 0 then return end
  local action, mentioned = {}, {}
  for _, line in ipairs(lines) do
    if line.role == "mentioned" then mentioned[#mentioned + 1] = line else action[#action + 1] = line end
  end
  Page.Heading(f, p, "Locations")
  local seen = {}
  for _, line in ipairs(action) do Page.Place(f, p, line, seen) end
  if #mentioned > 0 then
    Page.Heading(f, p, "Other places mentioned", true)
    for _, line in ipairs(mentioned) do Page.Place(f, p, line, seen) end
  end
end

-- A step's row on a stage's or a parent's page: its mark, code and short title, a click away
local function MakeStepButton(f)
  local b = CreateFrame("Button", nil, f.Page)
  local hover = b:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  Tint(hover, U.Colors.HOVER_HIGHLIGHT)
  b.Mark = b:CreateTexture(nil, "ARTWORK")
  b.Mark:SetSize(L.MARK, L.MARK)
  b.Mark:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -6)
  b.Text = Font(b, U.Fonts.BODY, U.Colors.LIGHT_GRAY)
  b.Text:SetPoint("TOPLEFT", b, "TOPLEFT", 4 + L.MARK + 8, -6)
  b.label = false
  b:SetScript("OnClick", function(self) if self.label then Panel.Select(f, self.label) end end)
  b:Hide()
  return b
end

function Page.Steps(f, p, rows, indent)
  for _, row in ipairs(rows) do
    p.steps = p.steps + 1
    local b = Pooled(f.StepButtons, p.steps, function() return MakeStepButton(f) end)
    if not b then
      f.incomplete = true
      return
    end
    local x = p.x + (indent and (row.depth or 0) * L.INDENT or 0)
    b.label = row.label
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f.Page, "TOPLEFT", x, p.y)
    b:SetWidth(p.w - (x - p.x))
    Shown(b.Mark, Recollect.UI.Icons.Paint(b.Mark, row.mark) and true or false)
    b.Text:SetWidth(p.w - (x - p.x) - L.MARK - 16)
    SetColor(b.Text, row.done and U.Colors.LABEL_GRAY or U.Colors.LIGHT_GRAY)
    local more = row.children and ("|cFF%s  (%d sub-steps)|r"):format(Hex(U.Colors.LABEL_GRAY), #row.children) or ""
    b.Text:SetText(("|cFF%s%s|r   %s%s"):format(Hex(U.Colors.LABEL_GRAY), row.label, Panel.PlainText(row.short or row.title or ""), more))
    local h = math.max(L.ROW_MIN - 4, math.ceil(Size(b.Text:GetStringHeight(), 12)) + 12)
    b:SetHeight(h)
    b:Show()
    p.y = p.y - h - 1
  end
end

-- A step's page: breadcrumb, title, state (and the checklist box), this
-- item's role, Before you start, You need, Do this, its sub-steps,
-- Locations, Notes and troubleshooting; empty sections left out
function Page.Step(f, p, model, row)
  local stage = Model().StageOf(model, row.index)
  local crumb = {}
  if stage then crumb[#crumb + 1] = stage.title end
  crumb[#crumb + 1] = "Step " .. row.label
  if row.parent then crumb[#crumb] = ("Step %s, part of step %s"):format(row.label, row.parent) end
  Page.Top(f, p, table.concat(crumb, "  /  "), Panel.PlainText(row.short or row.title or ""),
    row.done and U.Colors.LABEL_GRAY or U.Colors.HIGHLIGHT_WHITE)
  -- outside the filter: said, with the way back to it in the list
  if f.narrowed and not Model().Matches(row, Model().Filter(model), f.search) then
    p.y = p.y - Place(f.Outside, "Outside the current filter", p.x, p.y, p.w, U.Colors.CAUTION_ORANGE) - 2
    f.RevealLink:ClearAllPoints()
    f.RevealLink:SetPoint("TOPLEFT", f.Page, "TOPLEFT", p.x - 2, p.y)
    f.RevealLink:Show()
    p.y = p.y - L.BUTTON_H - 6
  end
  local sections = Model().Sections(row)
  local state, relevance = {}, {}
  for _, line in ipairs(sections.state) do
    if line.relevance then relevance[#relevance + 1] = line elseif not line.suggest then state[#state + 1] = line end
  end
  Page.State(f, p, model, row, state)
  for _, line in ipairs(relevance) do Page.Text(f, p, line, p.x, p.w, U.Fonts.BODY) end
  if #sections.before > 0 then
    Page.Heading(f, p, "Before you start")
    local seen = {}
    for _, line in ipairs(sections.before) do Page.Text(f, p, line, p.x, p.w, U.Fonts.BODY, seen) end
  end
  Page.Needs(f, p, model, row)
  -- Do this: the step's whole words (the title line too when the title shortened it), as written
  local doThis = {}
  local first = sections.title[1]
  if first and Panel.PlainText(first.text or "") ~= Panel.PlainText(row.short or "") then doThis[1] = first end
  for _, line in ipairs(sections.action) do doThis[#doThis + 1] = line end
  if #doThis > 0 then
    Page.Heading(f, p, "Do this")
    local seen = {}
    for _, line in ipairs(doThis) do
      Page.Text(f, p, { text = line.text, links = line.links, segs = line.segs, color = U.Colors.LIGHT_GRAY }, p.x, p.w,
        U.Fonts.BODY, seen)
    end
  end
  if row.children then
    Page.Heading(f, p, "Sub-steps")
    local list = {}
    for _, label in ipairs(row.children) do list[#list + 1] = model.byLabel[label] end
    Page.Steps(f, p, list)
  end
  Page.Places(f, p, sections.where)
  local more = sections.more[1]
  if more then
    p.y = p.y - L.SECTION_GAP + 4
    local open = Model().FoldOpen(model.ownerKey, model.sid, "m", row.label, false)
    local b = f.ReadMore
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f.Page, "TOPLEFT", p.x - 4, p.y)
    b.Arrow:SetRotation(open and -math.pi / 2 or 0)
    b.label, b.open = row.label, open and true or false
    b:Show()
    p.y = p.y - L.BUTTON_H - 4
    if open then Page.Text(f, p, { text = more.more, links = more.links, color = U.Colors.LIGHT_GRAY }, p.x + 4, p.w - 4, U.Fonts.BODY, {}) end
  end
end

-- A stage's page: its name, its steps' range and counts, First unfinished,
-- then each of its top-level steps with its mark and how many sub-steps
function Page.Stage(f, p, model, stage)
  local first, last = model.rows[stage.first], model.rows[stage.last]
  Page.Top(f, p, ("Stage, steps %s to %s"):format(first and first.label or "?", last and last.label or "?"), stage.title)
  Page.Text(f, p, { text = stage.summary ~= "" and stage.summary or "Nothing here the game tracks", color = U.Colors.LABEL_GRAY,
    font = "data" }, p.x, p.w)
  if stage.firstOpen then
    f.FirstOpen:ClearAllPoints()
    f.FirstOpen:SetPoint("TOPLEFT", f.Page, "TOPLEFT", p.x - 2, p.y - 2)
    f.FirstOpen.label = stage.firstOpen
    f.FirstOpen:SetLabel(("First unfinished: step %s"):format(stage.firstOpen))
    f.FirstOpen:Show()
    p.y = p.y - L.BUTTON_H - 6
  end
  local list = {}
  for i = stage.first, stage.last do
    if model.rows[i].depth == 0 then list[#list + 1] = model.rows[i] end
  end
  Page.Heading(f, p, "Steps")
  Page.Steps(f, p, list)
end

-- The marks' meanings, for the Summary page
local LEGEND = { { "done", "Done, as the game reads it" }, { "pending", "Not done yet" }, { "progress", "Partly done" },
  { "ready", "Everything it takes is in your bags, bank or warband bank" }, { "untracked", "Not tracked by the game" },
  { "marked", "Marked by you, for your own checklist" }, { "wait", "Still being read" }, { "warn", "Can't be read right now" } }
Panel.LEGEND = LEGEND

-- The Summary page: completion with honest counts, every reward with its
-- state, whether it can be done again, who it is for, any-order steps, the marks' legend
function Page.Summary(f, p, model)
  Page.Top(f, p, model.name or "A secret", "Summary & rewards")
  local c = model.counts or {}
  Page.Text(f, p, { text = model.complete and "Secret complete" or (model.progress or ""), color = model.complete
    and U.Colors.SAGE_GREEN or U.Colors.LIGHT_GRAY }, p.x, p.w, U.Fonts.BODY)
  local counts = {}
  if (c.tracked or 0) > 0 then counts[#counts + 1] = ("Tracked by the game: %d of %d done"):format(c.done or 0, c.tracked) end
  if (c.untracked or 0) > 0 then
    counts[#counts + 1] = ("Not tracked by the game: %d%s"):format(c.untracked, (c.marked or 0) > 0
      and ("; you marked %d of them for your own checklist"):format(c.marked) or "")
  end
  if (c.unread or 0) > 0 then counts[#counts + 1] = ("Can't be read right now: %d"):format(c.unread) end
  for _, words in ipairs(counts) do Page.Text(f, p, { text = words, color = U.Colors.LABEL_GRAY, font = "data" }, p.x, p.w) end
  if #(model.rewardRows or {}) > 0 then
    Page.Heading(f, p, #model.rewardRows > 1 and "Rewards" or "Reward")
    for _, reward in ipairs(model.rewardRows) do
      Page.Text(f, p, { segs = { { icon = reward.mark, text = reward.name, links = reward.link and { reward.link } or nil },
        { text = (" (%s, "):format(reward.kind) }, { text = reward.state, color = reward.color }, { text = ")" } },
        color = U.Colors.LIGHT_GRAY }, p.x, p.w, U.Fonts.BODY)
    end
  end
  local about = {}
  if model.again then about[#about + 1] = "Repeatable: " .. model.again:gsub("^%u", string.lower) end
  for _, note in ipairs(model.notes or {}) do about[#about + 1] = note end
  if #about > 0 then
    Page.Heading(f, p, "Good to know")
    for _, words in ipairs(about) do Page.Text(f, p, { text = words, color = U.Colors.LIGHT_GRAY }, p.x, p.w, U.Fonts.BODY) end
  end
  Page.Heading(f, p, "What the marks mean")
  for _, entry in ipairs(LEGEND) do
    Page.Text(f, p, { segs = { { icon = entry[1], text = entry[2] } }, color = U.Colors.LABEL_GRAY, font = "data" }, p.x, p.w)
  end
end

local function HideReader(f)
  for _, list in ipairs({ f.PageLines, f.PageHeads, f.PagePins, f.StepButtons, f.ReqRows }) do
    for _, piece in ipairs(list) do piece:Hide() end
  end
  for _, piece in ipairs({ f.ReadOwn, f.MarkedNote, f.ReadMore, f.StateMark, f.Kicker, f.ReadTitle, f.Outside, f.RevealLink,
    f.FirstOpen }) do
    piece:Hide()
  end
end

-- The footer's one pager: the step before and after in the list's order
-- (the matching steps while it's narrowed), where this page is, never
-- wrapping; none for a stage's page or the Summary
local function PaintPager(f, model, selection)
  local filter = Model().Filter(model)
  local pager = Model().Pager(model, selection, filter, f.search)
  if not pager then
    f.Footer:Hide()
    return false
  end
  local prev = Model().Neighbor(model, selection, -1, filter, f.search)
  local nextLabel = Model().Neighbor(model, selection, 1, filter, f.search)
  f.Prev.label, f.Next.label = prev or false, nextLabel or false
  f.Prev:SetActive(prev ~= nil)
  f.Next:SetActive(nextLabel ~= nil)
  local words
  if pager.index then
    words = ("%s %d of %d"):format(pager.kind == "match" and "Match" or "Page", pager.index, pager.total)
  else
    words = ("Outside the current filter; %d match%s"):format(pager.total, pager.total == 1 and "" or "es")
  end
  f.PagerText:SetText(words)
  f.Prev:Show()
  f.Next:Show()
  f.Footer:Show()
  return true
end

local function PaintReader(f, model, selection, rw)
  HideReader(f)
  local pager = PaintPager(f, model, selection)
  f.ReadScroll:ClearAllPoints()
  f.ReadScroll:SetPoint("TOPLEFT", f.Read, "TOPLEFT", 0, 0)
  f.ReadScroll:SetPoint("BOTTOMRIGHT", f.Read, "BOTTOMRIGHT", -L.SCROLLBAR, pager and L.FOOTER or 0)
  -- whole pixels: a fraction of the window's width left a line's right edge a hair past the page (Task #430)
  local width = math.max(160, math.floor(rw - L.SCROLLBAR))
  f.Page:SetWidth(width)
  local pad = rw < L.READ_NARROW and L.PAGE_NARROW or L.PAGE
  local p = { x = pad, y = -pad + 8, w = math.min(L.TEXT_MAX, width - 2 * pad), n = 0, heads = 0, pins = 0, steps = 0, reqs = 0 }
  p.narrow = p.w < L.READ_NARROW - 2 * L.PAGE
  local key = type(selection) == "string" and selection:match("^stage:(.+)$")
  local stage = key and Model().StageByKey(model, key)
  local row = not key and model.byLabel[selection]
  if selection == Model().SUMMARY then
    Page.Summary(f, p, model)
  elseif stage then
    Page.Stage(f, p, model, stage)
  elseif row then
    Page.Step(f, p, model, row)
  end
  f.Page:SetHeight(-p.y + pad)
  f.ReadScroll:UpdateScrollChildRect()
  -- the same page painted again keeps where the player read to; another starts at its top
  local offset = f.pageFor == selection and Size(f.ReadScroll:GetVerticalScroll(), 0) or 0
  f.pageFor = selection
  local range = Size(f.ReadScroll:GetVerticalScrollRange(), 0)
  f.ReadScroll:SetVerticalScroll(math.max(0, math.min(offset, range)))
end

-- PaintSplit(f, model, width): the explorer and the reader under the header;
-- a first look at this secret for this item selects its own step and opens
-- only that step's path (every other branch starts folded)
local function PaintSplit(f, model, width)
  local selection, restored = Model().Selected(model)
  if not restored then
    Model().Select(model, selection)
    if model.byLabel[selection] then Model().Reveal(model, selection) end
  end
  f.selection = selection
  local ok, icon = pcall(Model().seams.ItemIcon, model.itemID)
  f.itemIcon = ok and icon or false
  local ew = ExplorerWidth(width)
  f.Explorer:SetWidth(ew)
  f.Split:ClearAllPoints()
  f.Split:SetPoint("TOPLEFT", f.Head, "BOTTOMLEFT", 0, -L.HEAD_GAP)
  f.Split:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -L.INSET, 0)
  f.Split:Show()
  PaintTree(f, model, selection, ew)
  PaintReader(f, model, selection, width - 2 * L.INSET - ew - L.SPLIT_GAP)
  if not restored then Panel.ShowInTree(f, selection) end
end

-- MakeSplit(f): the explorer and the reader, built once with the panel
local function MakeSplit(f)
  local split = CreateFrame("Frame", nil, f)
  f.Split = split
  local explorer = CreateFrame("Frame", nil, split)
  explorer:SetPoint("TOPLEFT", split, "TOPLEFT", 0, 0)
  explorer:SetPoint("BOTTOMLEFT", split, "BOTTOMLEFT", 0, 0)
  explorer:SetWidth(L.EXP_MAX)
  local bg = explorer:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  Tint(bg, U.Colors.SIDEBAR_BG)
  f.Explorer = explorer
  f.Search = false
  if CobySuite_Recollect.UI.CreateSearchBox then
    f.Search = CobySuite_Recollect.UI.CreateSearchBox(explorer, { width = L.EXP_MAX - 2 * L.EXP_PAD, placeholder = "Search steps",
      point = { "TOPLEFT", explorer, "TOPLEFT", L.EXP_PAD + 4, -L.EXP_PAD }, maxLetters = 40,
      onSearch = function(text) Panel.SetSearch(f, text) end,
      onEnter = function(box)
        if box.FlushSearch then box:FlushSearch() end
        Panel.SearchEnter(f)
      end })
  end
  f.Chips = {}
  for _, filter in ipairs(Model().FILTERS) do f.Chips[#f.Chips + 1] = MakeChip(f, explorer, filter) end
  local scroll = CreateFrame("ScrollFrame", nil, explorer, "UIPanelScrollFrameTemplate")
  scroll.scrollBarHideable = true
  local tree = CreateFrame("Frame", nil, scroll)
  tree:SetSize(L.EXP_MAX - L.SCROLLBAR, 1)
  scroll:SetScrollChild(tree)
  scroll:HookScript("OnVerticalScroll", function(_, offset)
    local model = f.model
    if model and not f.painting then Model().SetScroll(model.ownerKey, model.sid, offset) end
  end)
  f.TreeScroll, f.Tree = scroll, tree
  f.TreeEmpty = Font(tree, U.Fonts.BODY, U.Colors.LABEL_GRAY)
  f.ShowAll = Kit.Text(tree, "Show all steps", function() Panel.SetFilter(f, "all") end)
  f.SummaryRow = MakeSummaryRow(f)
  f.TreeRows, f.TreeStages = {}, {}
  for i = 1, L.TREE_ROWS do f.TreeRows[i] = MakeTreeRow(f) end
  for i = 1, L.TREE_STAGES do f.TreeStages[i] = MakeTreeStage(f) end
  f.Suggest = MakeSuggest(f, explorer)
  -- one line centered in the gap between them
  local line = split:CreateTexture(nil, "ARTWORK")
  line:SetWidth(1)
  line:SetPoint("TOPLEFT", explorer, "TOPRIGHT", L.SPLIT_GAP / 2, 0)
  line:SetPoint("BOTTOMLEFT", explorer, "BOTTOMRIGHT", L.SPLIT_GAP / 2, 0)
  Tint(line, U.Colors.DIVIDER_GRAY)
  -- the reader: the page scrolling, the pager fixed under it
  local read = CreateFrame("Frame", nil, split)
  read:SetPoint("TOPLEFT", explorer, "TOPRIGHT", L.SPLIT_GAP, 0)
  read:SetPoint("BOTTOMRIGHT", split, "BOTTOMRIGHT", 0, 0)
  f.Read = read
  local rs = CreateFrame("ScrollFrame", nil, read, "UIPanelScrollFrameTemplate")
  rs.scrollBarHideable = true
  local page = CreateFrame("Frame", nil, rs)
  page:SetSize(400, 1)
  page:EnableMouse(true)
  if f.opts.links then f.opts.links(page) end
  rs:SetScrollChild(page)
  f.ReadScroll, f.Page = rs, page
  f.Kicker = Font(page, U.Fonts.DATA, U.Colors.LABEL_GRAY)
  f.ReadTitle = Font(page, U.Fonts.TITLE, U.Colors.HIGHLIGHT_WHITE)
  f.StateMark = page:CreateTexture(nil, "ARTWORK")
  f.StateMark:SetSize(L.MARK, L.MARK)
  f.Outside = Font(page, U.Fonts.BODY, U.Colors.CAUTION_ORANGE)
  f.RevealLink = Kit.Text(page, "Reveal in list", function() Panel.RevealInList(f) end)
  f.FirstOpen = Kit.Text(page, "First unfinished", function(self) if self.label then Panel.Select(f, self.label) end end)
  f.FirstOpen.label = false
  f.FirstOpen:SetScript("OnEnter", function(self)
    Tip(self, "The stage's first step not done yet", { "Its steps needed first may still be ahead of it." })
  end)
  f.FirstOpen:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.PageLines, f.PageHeads, f.PagePins, f.StepButtons, f.ReqRows = {}, {}, {}, {}, {}
  for i = 1, L.PAGE_LINES do f.PageLines[i] = Font(page, U.Fonts.BODY, U.Colors.LIGHT_GRAY) end
  for i = 1, L.HEADS do f.PageHeads[i] = Font(page, U.Fonts.HEADING, U.Colors.HIGHLIGHT_WHITE, false) end
  for i = 1, L.PAGE_PINS do f.PagePins[i] = MakePin(f, page) end
  for i = 1, L.STEPS do f.StepButtons[i] = MakeStepButton(f) end
  for i = 1, L.REQS do f.ReqRows[i] = MakeReq(f) end
  -- the player's own checklist: the shared checkbox, a click marks or unmarks at once
  f.ReadOwn = Kit.Check(page, "Done for my checklist", function(self)
    local model = f.model
    if not (model and self.label) then return end
    Model().SetMarked(model.ownerKey, model.sid, self.label, not self.marked)
    Panel.Repaint(f, true)
  end)
  f.ReadOwn.label, f.ReadOwn.marked = false, false
  f.ReadOwn:HookScript("OnEnter", function(self)
    Tip(self, "Done for my checklist", { "The game doesn't track this step. Your mark is only for this character's checklist: it "
      .. "never counts as the game's progress, never meets another step's need and never changes what Recollect says about an item." })
  end)
  f.ReadOwn:HookScript("OnLeave", function() GameTooltip:Hide() end)
  f.MarkedNote = Font(page, U.Fonts.DATA, U.Colors.INFO_BLUE, false)
  -- Notes and troubleshooting: the step's folded words, a disclosure of their own
  local more = Kit.Text(page, "Notes and troubleshooting", function(self)
    local model = f.model
    if not (model and self.label) then return end
    Model().SetFold(model.ownerKey, model.sid, "m", self.label, not self.open)
    Panel.Repaint(f)
  end)
  more.Text:ClearAllPoints()
  more.Text:SetPoint("LEFT", more, "LEFT", 18, 0)
  more.Arrow = more:CreateTexture(nil, "ARTWORK")
  more.Arrow:SetSize(7, 11)
  more.Arrow:SetPoint("LEFT", more, "LEFT", 4, 0)
  more.Arrow:SetAtlas(ATLAS.forward)
  more.Label = more.Text
  more:SetWidth(more:GetWidth() and (Size(more:GetWidth(), 180) + 18) or 200)
  more.open, more.label = false, false
  f.ReadMore = more
  local footer = CreateFrame("Frame", nil, read)
  footer:SetHeight(L.FOOTER)
  footer:SetPoint("BOTTOMLEFT", read, "BOTTOMLEFT", 0, 0)
  footer:SetPoint("BOTTOMRIGHT", read, "BOTTOMRIGHT", 0, 0)
  local top = footer:CreateTexture(nil, "ARTWORK")
  top:SetHeight(1)
  top:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
  Tint(top, U.Colors.DIVIDER_GRAY)
  f.Footer = footer
  local function Walk(self) if self.label then Panel.Select(f, self.label) end end
  f.Prev = Kit.Text(footer, "Previous", Walk)
  f.Prev:SetPoint("LEFT", footer, "LEFT", L.PAGE - 2, 0)
  f.Next = Kit.Text(footer, "Next", Walk)
  f.Next:SetPoint("RIGHT", footer, "RIGHT", -L.PAGE - L.SCROLLBAR + 2, 0)
  f.PagerText = Font(footer, U.Fonts.DATA, U.Colors.LABEL_GRAY, false)
  f.PagerText:SetPoint("CENTER", footer, "CENTER", 0, 0)
  f.PagerText:SetJustifyH("CENTER")
  for _, b in ipairs({ f.Prev, f.Next }) do
    b.label = false
    b:SetScript("OnEnter", function(self)
      local row = self.label and f.model and f.model.byLabel and f.model.byLabel[self.label]
      if not row then return end
      Tip(self, "Step " .. self.label, { Panel.PlainText(row.short or row.title or "") }, "ANCHOR_TOP")
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  footer:Hide()
  f.selection, f.search, f.pageFor, f.treeOffset, f.treeRowFor, f.narrowed, f.itemIcon = false, "", false, false, {}, false, false
  split:Hide()
end

-------------------------------------------------------------------------------
-- Create, Paint, Show
-------------------------------------------------------------------------------
-- Create(parent, opts): the panel, hidden. opts.pin(parent, size) makes a
-- waypoint button, opts.onWaypoint(place) sets one, opts.waypointTip(button,
-- place) shows its tooltip, opts.placesMenu(anchor, title, places) a menu of
-- several places, opts.menu(anchor, title, entries) a menu, opts.links(frame)
-- makes a frame's links live, opts.hyper(text, links, once) paints names as
-- links, opts.resetLinks() forgets the links painted before; the header's
-- (Task #430): opts.history() { canBack, canForward } with opts.back() and
-- opts.forward(), opts.refresh() and opts.readState() (the last good read's
-- time, whether the latest failed), opts.context() (the item it was opened
-- for and its answer) and opts.curator() ({ text, run }: the curator's
-- action, in More)
function Panel.Create(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  f.opts = opts or {}
  -- what the panel shows, none yet (false, never nil: a frame's missing field reads as its methods')
  f.model, f.signature, f.width, f.painting, f.itemID, f.sid = false, false, false, false, false, false
  f.incomplete, f.onPick, f.context = false, false, false
  MakeHead(f)
  if f.opts.links then f.opts.links(f.Head) end
  MakeSplit(f)
  f.Empty = Font(f, U.Fonts.BODY, U.Colors.LABEL_GRAY)
  -- Clear my marks asks first, in the shared dialog (built here, never in combat)
  f.ClearDialog = false
  if CobySuite_Recollect.UI.CreateDialogPopup and CobySuite_Recollect.UI.CreateWindow and not Panel.seams.InCombat() then
    local ok, dialog = pcall(CobySuite_Recollect.UI.CreateDialogPopup, { name = "RecollectSecretClearMarks", parent = UIParent, hidden = true,
      title = "Clear my marks", icon = Recollect.ICON, confirmText = "Clear marks", danger = true, fixedPlace = true,
      body = "Take off your marks?", onConfirm = function(popup) if popup.clear then popup.clear() end end })
    f.ClearDialog = ok and dialog or false
  end
  -- a new size, or shown again: painted again only when its width changed
  f:SetScript("OnSizeChanged", function() if f.model then Panel.Paint(f, f.model) end end)
  f:SetScript("OnShow", function() if f.model then Panel.Paint(f, f.model) end end)
  f:Hide()
  return f
end

-- What the panel shows beside the model: the item history, the read state
-- and the item's answer, so a change there paints too
local function PanelState(f)
  local parts = {}
  local history = f.opts.history and f.opts.history() or nil
  if history then parts[#parts + 1] = tostring(history.canBack) .. tostring(history.canForward) end
  local ctx = f.opts.context and f.opts.context() or nil
  if type(ctx) == "table" then parts[#parts + 1] = tostring(ctx.name) .. tostring(ctx.answer) end
  return table.concat(parts, "|")
end

local function PaintEmpty(f, words, width)
  f.Split:Hide()
  f.selection = false
  local y = f.Head:IsShown() and -(Size(f.Head:GetHeight(), 72) + L.HEAD_GAP) or -L.HEAD_GAP
  Place(f.Empty, words, L.INSET + 8, y, width - 2 * L.INSET - 16, U.Colors.LABEL_GRAY)
end

-- Clear my marks' confirmation, when it asks about another owner's or
-- secret's marks than the panel now shows, is hidden (review UI-01)
local function HideStaleClear(f, model)
  local dialog = f.ClearDialog
  if not (dialog and dialog.target and dialog:IsShown()) then return end
  if model and tostring(model.ownerKey) .. "\29" .. tostring(model.sid) == dialog.target then return end
  dialog.clear, dialog.target = nil, nil
  dialog:Hide()
end

-- Paint(f, model, force): the header, then the explorer and the reader;
-- skipped when nothing it shows changed (force after a fold or a click).
-- Each scroll stays where it was, or where it was left on this secret
function Panel.Paint(f, model, force)
  model = model or false   -- kept as false, never nil (a frame's missing field reads as its methods')
  HideStaleClear(f, model)
  local width = Width(f)
  local signature = (model and Model().Signature(model) or "none") .. "\29" .. PanelState(f)
  if not force and f.model == model and f.signature == signature and f.width == width then return end
  if f.model ~= model and f.signature == signature and f.width == width and not force then
    f.model = model
    return
  end
  f.model, f.signature, f.width = model, signature, width
  f.painting, f.incomplete = true, false
  if f.opts.resetLinks then f.opts.resetLinks() end
  if not model then
    f.Head:Hide()
    PaintEmpty(f, "This item isn't part of a Warcraft secret Recollect knows.", width)
    f.painting = false
    return
  end
  f.Empty:Hide()
  PaintHead(f, model, width)
  if not Model().Split(model) then
    PaintEmpty(f, model.failed and "Its steps can't be read right now. They are read again in a few seconds." or
      "This secret has no steps Recollect can show.", width)
  else
    PaintSplit(f, model, width)
  end
  if f.incomplete then f.signature = false end
  f.painting = false
end

-- Show(f, itemID, owner, sid, onPick, force): the tab for the item, on sid's
-- secret when it is one of its own; onPick(sid) is the secrets menu's pick
function Panel.Show(f, itemID, owner, sid, onPick, force)
  f.onPick, f.itemID, f.owner, f.sid = onPick or false, itemID, owner, sid or false
  local model = Panel.Model(itemID, owner, sid)
  Panel.Paint(f, model, force)
  return model
end
