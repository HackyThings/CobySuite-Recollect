-------------------------------------------------------------------------------
-- Curator opt-out dialog (curator spec, walkthrough 9, D16)
--
-- When curator mode is turned off, a dialog of its own (never
-- StaticPopupDialogs: adding to that Blizzard table taints unrelated secure
-- actions, such as using a bag item) says recording
-- stopped and how to leave the community (leaving is restricted, so the
-- addon never calls it), with a checkbox to delete the current findings.
-- "Stop curating" deletes them if ticked and tells the author (L); "Keep
-- curating" turns curator mode back on. In combat, where no window may be
-- built, the same words go to chat and the findings are kept. Deleting also
-- clears the collection history (Curator.History).
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local U = CobySuite_Recollect.Utilities

local OptOut = {}
Curator.OptOutDialog = OptOut

local WIDTH, HEIGHT, PAD = 420, 200, 16
local LEAVE_TEXT = "Recording has stopped. Please also leave the Recollect Curators community: open the "
  .. "Communities window, right-click the community and choose Leave."
local dialog

local function FindingsCount()
  local counts = Curator.Store.Counts()
  return counts.records + counts.stamps
end

-- Finish(delete): recording stays off; delete also removes every finding,
-- note and the collection history (the curator's own record of what was
-- sent); the author hears L either way
local function Finish(delete)
  if delete then
    Curator.Main.ClearFindings()
    if Curator.Notes then Curator.Notes.Clear() end   -- flags, feedback and errors are findings too
    if Curator.History then Curator.History.Clear() end
  end
  Curator.Sharing.SendLeaving()
  if dialog then dialog:Hide() end
  Host.Print(delete and "Recollect: curator mode is off and your findings were deleted."
    or "Recollect: curator mode is off. Your findings are kept, through database updates too, until you delete them or turn it back on and they are collected.")
end

local function Build()
  if dialog or InCombatLockdown() then return end
  -- the suite's window shell: Escape and its X close it (both keep the
  -- findings, as the X always did), the X works in combat, it can be moved
  dialog = CobySuite_Recollect.UI.CreateWindow({
    name = "RecollectCuratorOptOutDialog", title = "Stop being a curator?", icon = Host.Icon(),
    width = WIDTH, height = HEIGHT, strata = "DIALOG", escapeCloses = true,
    point = { "CENTER", UIParent, "CENTER", 0, 120 },
  })
  dialog.Body = dialog:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  dialog.Body:SetPoint("TOPLEFT", dialog, "TOPLEFT", PAD, -34)
  dialog.Body:SetWidth(WIDTH - 2 * PAD)
  dialog.Body:SetJustifyH("LEFT")
  dialog.Body:SetWordWrap(true)
  dialog.Body:SetText(LEAVE_TEXT)
  dialog.Delete = CobySuite_Recollect.UI.CreateCheckbox(dialog, { size = 24, label = "Also delete my current findings",
    point = { "TOPLEFT", dialog.Body, "BOTTOMLEFT", -4, -12 } })
  dialog.Stop = CobySuite_Recollect.UI.CreateButton(dialog, { text = "Stop curating", size = { 130, U.ButtonSize.MEDIUM.height },
    point = { "BOTTOMLEFT", dialog, "BOTTOMLEFT", PAD, 14 },
    onClick = function() Finish(dialog.Delete:GetChecked() == true) end })
  dialog.Keep = CobySuite_Recollect.UI.CreateButton(dialog, { text = "Keep curating", size = { 130, U.ButtonSize.MEDIUM.height },
    point = { "BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -PAD, 14 },
    onClick = function()
      dialog:Hide()
      Curator.Config.Set("curator_enabled", true)
    end })
  dialog:Hide()
end

-- Show(): after curator mode was turned off
function OptOut.Show()
  Build()
  if not dialog then
    Host.Print("Recollect: curator mode is off. " .. LEAVE_TEXT)
    Curator.Sharing.SendLeaving()
    return
  end
  local label = dialog.Delete.text
  if label and label.SetText then label:SetText(("Also delete my current findings (%d)"):format(FindingsCount())) end
  dialog.Delete:SetChecked(false)
  dialog:Show()
end

OptOut.Finish = Finish

Host.OnLoaded(function() C_Timer.After(0, Build) end)
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", Build)
