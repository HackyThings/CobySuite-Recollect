-------------------------------------------------------------------------------
-- Curator transfer window (curator spec, walkthrough 4, D4)
--
-- Shows the collection being sent (parts sent of all, size, paused in
-- lockdown) with Cancel, or the author's request with Allow and Decline
-- when "Ask me before each collection" is on. The request opens the window
-- when the curator is resting and out of combat; otherwise a chat line
-- carries a [Review request] link that opens it, and so does the dashboard's
-- Review button; /rec curator opens it while something is running only when
-- the dashboard can't open (in combat before it was built). Closing it never
-- cancels. Built at login, out of combat, like every window.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Sharing = Curator.Sharing
local U = CobySuite_Recollect.Utilities

local TransferWindow = {}
Curator.TransferWindow = TransferWindow

local WIDTH, HEIGHT, PAD = 380, 150, 14
local window

local function SetShownButtons(asking)
  window.Allow:SetShown(asking)
  window.Decline:SetShown(asking)
  window.Cancel:SetShown(not asking and Sharing.Status() ~= nil)
end

-- The text for what is running now
function TransferWindow.Text()
  local asked = Sharing.Prompt()
  if asked then
    return "Recollect's author asks to collect your curator findings now. Allow sends them in the background; "
      .. "you can cancel at any time.", true
  end
  local status = Sharing.Status()
  if not status then return "No curator collection is running.", false end
  local text = ("Sending your curator findings: %d of %d parts (%d KB)."):format(math.min(status.sent, status.total),
    status.total, math.max(1, math.ceil(status.bytes / 1024)))
  if status.waitingK then text = "All parts sent; waiting for the author's client to confirm." end
  if status.paused then text = text .. " Paused while the game blocks addon messages here." end
  return text, false
end

function TransferWindow.Refresh()
  if not window or not window:IsShown() then return end
  local text, asking = TransferWindow.Text()
  window.Body:SetText(text)
  SetShownButtons(asking)
end

local function Build()
  if window or InCombatLockdown() then return end
  window = CobySuite_Recollect.UI.CreateWindow({
    name = "RecollectCuratorTransferWindow", title = "Recollect curator collection", icon = Curator.Host.Icon(),
    width = WIDTH, height = HEIGHT, escapeCloses = true, point = { "CENTER", UIParent, "CENTER", 0, 160 },
  })
  window.Body = window:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  window.Body:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -34)
  window.Body:SetWidth(WIDTH - 2 * PAD)
  window.Body:SetJustifyH("LEFT")
  window.Body:SetWordWrap(true)
  local function Button(text, point, onClick)
    return CobySuite_Recollect.UI.CreateButton(window, { text = text, size = { 100, U.ButtonSize.MEDIUM.height }, point = point, onClick = onClick })
  end
  window.Allow = Button("Allow", { "BOTTOMLEFT", window, "BOTTOMLEFT", PAD, 14 }, function() Sharing.AnswerPrompt(true) end)
  window.Decline = Button("Decline", { "LEFT", window.Allow, "RIGHT", 8, 0 }, function() Sharing.AnswerPrompt(false) end)
  window.Cancel = Button("Cancel", { "BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, 14 }, function() Sharing.Cancel() end)
  window:HookScript("OnShow", TransferWindow.Refresh)
  window:Hide()
end

function TransferWindow.Open()
  Build()
  if not window then
    Host.Print((TransferWindow.Text()))
    return
  end
  window:Show()
  TransferWindow.Refresh()
end

-- The request arrived (D4): a window when resting and out of combat, else a
-- chat line with the [Review request] link
Sharing.OnPrompt = function()
  local okRest, resting = pcall(IsResting)
  if okRest and resting and not InCombatLockdown() and window then
    TransferWindow.Open()
  else
    Host.Print("Recollect's author asks to collect your curator findings. "
      .. U.WrapColor(U.Colors.LINK_BLUE, "|H" .. Sharing.LINK .. "|h[Review request]|h"))
  end
end
Sharing.OnPromptLink = function() TransferWindow.Open() end
Sharing.OnChanged = function() TransferWindow.Refresh() end

Host.OnLoaded(function() C_Timer.After(0, Build) end)
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", Build)
