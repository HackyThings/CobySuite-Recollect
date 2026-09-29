-------------------------------------------------------------------------------
-- The curator's two writing windows (curator spec D35, Cobanyte 2026-09-27):
--   Curator.FlagDialog.Open(itemID, reason)   the details window's Curator
--                                     Flag (reason: one chosen for a flag
--                                     with no entries yet, "missing" for
--                                     Request info)
--   Curator.FeedbackDialog.Open()     /rec feedback
-- Each is its own resizable window on the suite's shell (never
-- StaticPopupDialogs), its size and place kept in RECOLLECT_CURATOR_DB.windows,
-- built at load out of combat, with a chat line when asked for in combat
-- before it exists. DIALOG strata, raised over the details window when it
-- opens: Blizzard's dropdown menus open at FULLSCREEN_DIALOG, so a window
-- there would cover its own reason menu (seen in game, 2026-09-27).
--
-- The flag window: the item, what was already sent about it and where each
-- entry stands, a reason, then the curator's own words in a box that fills
-- the window, tagged Optional (gray) or Required (red, "Something else"),
-- then Save, Remove (an entry not sent yet) and Cancel. Once something was
-- sent, what is saved goes to the author as more information. The feedback
-- window is the same without the reason; its words are always required. What is kept and when it goes is
-- Curator.Notes'; these windows only read and write through it.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Notes = Curator.Notes
local U = CobySuite_Recollect.Utilities

local WIDTH, PAD = 460, 14
local BULLET = "\226\128\162 "

local Shared = {}
Shared.seams = {
  Date = function(at) return date("%b %d", at) end,
  ItemName = function(itemID) return C_Item.GetItemNameByID(itemID) end,
  ItemIcon = function(itemID) return C_Item.GetItemIconByID(itemID) end,
}

local function Seam(name, ...)
  local ok, value = pcall(Shared.seams[name], ...)
  if not ok or Host.IsSecret(value) then return nil end
  return value
end

-- Where an entry stands, in words
function Shared.StateText(entry)
  if entry.state == "delivered" then
    local when = entry.at and Seam("Date", entry.at)
    return when and ("delivered " .. when) or "delivered"
  elseif entry.state == "sent" then
    return "sent, waiting for the author to save it"
  end
  return "not sent yet"
end

-- The lines about what was already sent (newest last; at most `most`), and
-- whether anything was sent at all
function Shared.HistoryLines(entries, withReason, most)
  local sent = {}
  for _, entry in ipairs(entries or {}) do
    if entry.state ~= "pending" then sent[#sent + 1] = entry end
  end
  local lines = {}
  local from = math.max(1, #sent - (most or 3) + 1)
  if from > 1 then lines[#lines + 1] = ("%d earlier entries"):format(from - 1) end
  for i = from, #sent do
    local entry = sent[i]
    local what = withReason and (Notes.REASON_LABELS[entry.reason] or "?") or nil
    local words = entry.text and entry.text ~= "" and ('"%s"'):format(U.Truncate((entry.text:gsub("\n", " ")), 80, "..."))
    local head = what and words and (what .. ": " .. words) or what or words or ""
    lines[#lines + 1] = BULLET .. head .. U.WrapColor(U.Colors.LABEL_GRAY, " (" .. Shared.StateText(entry) .. ")")
  end
  return lines, #sent > 0
end

local function Label(parent, font, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or U.Fonts.BODY)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(true)
  if width then fs:SetWidth(width) end
  return fs
end

-- Enter starts a new line in a writing box (the shared input commits on
-- Enter, which suits a single line, not a paragraph); Escape still leaves it.
-- The box follows its frame's size: the window is resizable.
local function WritingBox(input)
  local eb = input.EditBox
  eb:SetScript("OnEnterPressed", function(self) self:Insert("\n") end)
  input:HookScript("OnSizeChanged", function(self, width)
    width = tonumber(width) or self:GetWidth() or 0
    if width > 18 then
      eb:SetWidth(width - 18)
      if eb.Instructions then eb.Instructions:SetWidth(width - 18) end
    end
  end)
end

-- The "Optional" / "Required" tag over a box's top-right corner
local function Tag(fs, required)
  local color = required and U.Colors.WARNING_RED or U.Colors.LABEL_GRAY
  fs:SetText(required and "Required" or "Optional")
  fs:SetTextColor(color[1], color[2], color[3])
end

local function Warn(fs, text)
  local red = U.Colors.WARNING_RED
  fs:SetTextColor(red[1], red[2], red[3])
  fs:SetText(text or "")
end

-- A label that spans the window's width, under `above`
local function Row(window, font, above, gap)
  local fs = Label(window, font)
  fs:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -(gap or 8))
  fs:SetPoint("RIGHT", window, "RIGHT", -PAD, 0)
  return fs
end

-- The window's saved sizes and places, in the curator's own saved data
local function WindowState()
  local db = Curator.Main.DB()
  if type(db.windows) ~= "table" then db.windows = {} end
  return db.windows
end

-- The shell and its buttons; the builder adds the rest
local function BuildWindow(name, title, height, onSave, onRemove)
  local window = CobySuite_Recollect.UI.CreateWindow({
    name = name, title = title, icon = Host.Icon(), width = WIDTH, height = height,
    strata = "DIALOG", escapeCloses = true,
    resizable = { minWidth = 380, minHeight = 300, maxWidth = 1000, maxHeight = 900 },
    persist = { svTable = WindowState, key = name, defaults = { point = "CENTER", relPoint = "CENTER", x = 0, y = 80 } },
  })
  local size = { 110, U.ButtonSize.MEDIUM.height }
  window.Cancel = CobySuite_Recollect.UI.CreateButton(window, { text = "Cancel", size = size,
    point = { "BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD - 10, 14 }, onClick = function() window:Hide() end })
  window.Save = CobySuite_Recollect.UI.CreateButton(window, { text = "Save", size = size,
    point = { "RIGHT", window.Cancel, "LEFT", -8, 0 }, onClick = onSave })
  window.Remove = CobySuite_Recollect.UI.CreateButton(window, { text = "Remove", size = size,
    tooltip = "Withdraw what you saved before it's sent",
    point = { "BOTTOMLEFT", window, "BOTTOMLEFT", PAD, 14 }, onClick = onRemove })
  window.Problem = Label(window, U.Fonts.SMALL)
  window.Problem:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", PAD, 44)
  window.Problem:SetPoint("RIGHT", window, "RIGHT", -PAD, 0)
  return window
end

-- The writing box: from under `above` to the bottom, over the problem line,
-- with its tag above its top-right corner
local function BuildBox(window, above, maxLetters, placeholder, onChange)
  window.Tag = Label(window, U.Fonts.SMALL)
  window.Tag:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD, 0)
  window.Tag:SetJustifyH("RIGHT")
  window.Input = CobySuite_Recollect.UI.CreateMultiLineInput(window, { width = WIDTH - 2 * PAD - 8, height = 100,
    maxLetters = maxLetters, keepNewlines = true, placeholder = placeholder, onChange = onChange })
  window.Input:ClearAllPoints()
  window.Input:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 4, -22)
  window.Input:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD - 4, 64)
  window.Tag:ClearAllPoints()
  window.Tag:SetPoint("BOTTOMRIGHT", window.Input, "TOPRIGHT", 4, 5)
  window.Words = Label(window, U.Fonts.BODY)
  window.Words:SetPoint("BOTTOMLEFT", window.Input, "TOPLEFT", -4, 5)
  WritingBox(window.Input)
end

-------------------------------------------------------------------------------
-- The flag window
-------------------------------------------------------------------------------
local FlagDialog = { Shared = Shared }
Curator.FlagDialog = FlagDialog

local flagWindow
local flagItem

-- Whether Save may run: a reason, and words for "Something else"
function FlagDialog.CanSave(reason, text)
  return Notes.CheckFlag(reason, text) ~= nil
end

-- Whether the words are required for a reason
function FlagDialog.WordsRequired(reason)
  return reason == "other"
end

local function FlagText()
  return flagWindow.Input:GetText() or ""
end

local function PaintFlag()
  local w = flagWindow
  if not w or not flagItem then return end
  local state = Notes.Flag(flagItem)
  local reason = w.Reason:GetValue()
  Tag(w.Tag, FlagDialog.WordsRequired(reason))
  w.Save:SetEnabled(FlagDialog.CanSave(reason, FlagText()) and not state.atLimit)
  w.Remove:SetShown(state.pending ~= nil)
end

local function FlagHistory(state)
  local lines, anySent = Shared.HistoryLines(state.entries, true, 3)
  if anySent then
    lines[#lines + 1] = "What you save now goes to the author as more information."
  end
  return lines, anySent
end

local function SaveFlag()
  local entry, why = Notes.SaveFlag(flagItem, flagWindow.Reason:GetValue(), FlagText())
  if not entry then
    Warn(flagWindow.Problem, why)
    return
  end
  flagWindow:Hide()
  Host.Print("Recollect: your flag is saved; it goes to the author with your next curator collection.")
end

local function RemoveFlag()
  Notes.RemovePendingFlag(flagItem)
  flagWindow:Hide()
end

local function BuildFlag()
  if flagWindow or InCombatLockdown() then return end
  local w = BuildWindow("RecollectCuratorFlagDialog", "Curator Flag", 400, SaveFlag, RemoveFlag)
  w.ItemIcon = w:CreateTexture(nil, "ARTWORK")
  w.ItemIcon:SetSize(24, 24)
  w.ItemIcon:SetPoint("TOPLEFT", w, "TOPLEFT", PAD, -34)
  w.ItemName = Label(w, U.Fonts.TITLE)
  w.ItemName:SetPoint("LEFT", w.ItemIcon, "RIGHT", 8, 0)
  w.ItemName:SetPoint("RIGHT", w, "RIGHT", -PAD, 0)
  w.ItemName:SetWordWrap(false)
  w.History = Row(w, U.Fonts.SMALL, w.ItemIcon, 10)
  w.History:SetMaxLines(6)
  local labels, values = {}, {}
  for i, reason in ipairs(Notes.REASONS) do labels[i], values[i] = reason.label, reason.key end
  w.Reason = CobySuite_Recollect.UI.CreateDropDown(w, { label = "What's wrong", width = 240, labels = labels, values = values,
    defaultText = "Choose a reason", onValueChanged = function() PaintFlag() end })
  w.Reason:SetPoint("TOPLEFT", w.History, "BOTTOMLEFT", 0, -10)
  BuildBox(w, w.Reason, Notes.LIMITS.FLAG_TEXT, "What's missing or wrong? Where did you see it?", function() PaintFlag() end)
  w.Words:SetText("In your own words")
  flagWindow = w
  w:Hide()
end

-- Open(itemID, reason): the flag window for an item, with its flag so far;
-- reason, when given, is chosen for a flag with no entries yet
function FlagDialog.Open(itemID, reason)
  itemID = tonumber(itemID)
  if not itemID then return false end
  BuildFlag()
  if not flagWindow then
    Host.Print("Recollect: the Curator Flag window opens when combat ends.")
    return false
  end
  flagItem = itemID
  local state = Notes.Flag(itemID)
  local last = state.entries[#state.entries]
  flagWindow.ItemIcon:SetTexture(Seam("ItemIcon", itemID) or 134400)
  flagWindow.ItemName:SetText(Seam("ItemName", itemID) or ("Item " .. itemID))
  local lines = FlagHistory(state)
  flagWindow.History:SetText(table.concat(lines, "\n"))
  flagWindow.History:SetShown(#lines > 0)
  flagWindow.Reason.value = nil
  flagWindow.Reason.DropDown:OverrideText("Choose a reason")
  if last then
    flagWindow.Reason:SetValue(last.reason)
  elseif reason and Notes.REASON_LABELS[reason] then
    flagWindow.Reason:SetValue(reason)
  end
  flagWindow.Input:SetCommittedValue(state.pending and state.pending.text or "")
  Warn(flagWindow.Problem, state.atLimit and (#state.entries > 0
    and "This flag holds as much as it can until the author collects it." or "You have as many flags waiting as Recollect keeps.") or "")
  PaintFlag()
  flagWindow:Show()
  flagWindow:Raise()
  return true
end

-------------------------------------------------------------------------------
-- The feedback window
-------------------------------------------------------------------------------
local FeedbackDialog = {}
Curator.FeedbackDialog = FeedbackDialog

local feedbackWindow

local function PaintFeedback()
  local w = feedbackWindow
  if not w then return end
  local state = Notes.Feedback()
  Tag(w.Tag, true)
  w.Save:SetEnabled(Notes.CleanText(w.Input:GetText() or "", Notes.LIMITS.FEEDBACK_TEXT) ~= "" and not state.atLimit)
  w.Remove:SetShown(state.pending ~= nil)
end

local function SaveFeedback()
  local entry, why = Notes.SaveFeedback(feedbackWindow.Input:GetText())
  if not entry then
    Warn(feedbackWindow.Problem, why)
    return
  end
  feedbackWindow:Hide()
  Host.Print("Recollect: thank you. Your feedback goes to the author with your next curator collection.")
end

local function RemoveFeedback()
  Notes.RemovePendingFeedback()
  feedbackWindow:Hide()
end

local function BuildFeedback()
  if feedbackWindow or InCombatLockdown() then return end
  local w = BuildWindow("RecollectCuratorFeedbackDialog", "Recollect Feedback", 380, SaveFeedback, RemoveFeedback)
  w.Intro = Label(w, U.Fonts.BODY)
  w.Intro:SetPoint("TOPLEFT", w, "TOPLEFT", PAD, -34)
  w.Intro:SetPoint("RIGHT", w, "RIGHT", -PAD, 0)
  w.Intro:SetText("Tell the author anything: a bug, an idea, something confusing. It's sent with your next curator collection, and only the author reads it.")
  w.History = Row(w, U.Fonts.SMALL, w.Intro, 8)
  w.History:SetMaxLines(4)
  BuildBox(w, w.History, Notes.LIMITS.FEEDBACK_TEXT, "Your feedback", function() PaintFeedback() end)
  w.Words:SetText("Your feedback")
  feedbackWindow = w
  w:Hide()
end

-- Open(): the feedback window, with the entry not sent yet to edit
function FeedbackDialog.Open()
  BuildFeedback()
  if not feedbackWindow then
    Host.Print("Recollect: the feedback window opens when combat ends.")
    return false
  end
  local state = Notes.Feedback()
  local lines = Shared.HistoryLines(state.entries, false, 2)
  feedbackWindow.History:SetText(table.concat(lines, "\n"))
  feedbackWindow.Input:SetCommittedValue(state.pending and state.pending.text or "")
  Warn(feedbackWindow.Problem, state.atLimit and "You have as much feedback waiting as Recollect keeps." or "")
  PaintFeedback()
  feedbackWindow:Show()
  feedbackWindow:Raise()
  feedbackWindow.Input:SetFocus()
  return true
end

local function BuildBoth()
  BuildFlag()
  BuildFeedback()
end

Host.OnLoaded(function() C_Timer.After(0, BuildBoth) end)
local retry = CreateFrame("Frame")
retry:RegisterEvent("PLAYER_REGEN_ENABLED")
retry:SetScript("OnEvent", BuildBoth)
