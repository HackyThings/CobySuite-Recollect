-------------------------------------------------------------------------------
-- Curator opt-out dialog (curator spec, walkthrough 9, D16)
--
-- When curator mode is turned off, a dialog of its own (never
-- StaticPopupDialogs: adding to that Blizzard table taints unrelated secure
-- actions, such as using a bag item) says recording
-- stopped and how to leave the community (leaving is restricted, so the
-- addon never calls it), with a checkbox to delete the current findings.
-- It opens once Apply has turned recording off, so it says so and its buttons
-- are "Done" (deletes them if ticked and tells the author, L) and "Turn it
-- back on" (Task #232: "Stop curating" and "Keep curating" read as if nothing
-- had happened yet). In combat, where no window may be
-- built, the same words go to chat and the findings are kept. Deleting also
-- clears the collection history (Curator.History).
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host

local OptOut = {}
Curator.OptOutDialog = OptOut

-- the room the delete checkbox takes under the text: its gap and its size
local CHECK_ROOM = 12 + 24
local LEAVE_TEXT = "Recording has stopped. Please also leave the Recollect Curators community: open the "
  .. "Communities window, right-click the community and choose Leave."
local dialog

-- Every finding the checkbox deletes: Main.ClearFindings clears the blocks
-- kept from older databases too, so they count here (with only those left,
-- it read "(0)" while the dashboard showed 334 waiting)
local function FindingsCount()
  local counts = Curator.Store.Counts()
  local n = counts.records + counts.stamps
  for _, block in ipairs(Curator.Store.DB().frozen or {}) do
    for _ in pairs(block.records or {}) do n = n + 1 end
    for _ in pairs(block.confirms or {}) do n = n + 1 end
  end
  return n
end
OptOut._test = { FindingsCount = FindingsCount }

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
  Host.Print(delete and "Curator mode is off and your findings were deleted."
    or "Curator mode is off. Your findings are kept, through database updates too, until you delete them or turn it back on and they are collected.")
end

local function Build()
  if dialog or InCombatLockdown() then return end
  -- the suite's prompt with plain buttons: Escape and its X close it (both
  -- keep the findings, as the X always did), the X works in combat, it can
  -- be moved
  dialog = CobySuite_Recollect.UI.CreateClickPrompt({
    name = "RecollectCuratorOptOutDialog", title = "Curator mode is off", icon = Host.Icon(),
    width = 420, extraHeight = CHECK_ROOM,
    buttons = {
      { key = "Stop", text = "Done", onClick = function() Finish(dialog.Delete:GetChecked() == true) end },
      { key = "Keep", text = "Turn it back on", side = "right", onClick = function()
        dialog:Hide()
        Curator.Config.Set("curator_enabled", true)
      end },
    },
  })
  dialog.Delete = CobySuite_Recollect.UI.CreateCheckbox(dialog, { size = 24, label = "Also delete my current findings",
    point = { "TOPLEFT", dialog.Body, "BOTTOMLEFT", -4, -12 } })
end

-- Show(): after curator mode was turned off
function OptOut.Show()
  Build()
  if not dialog then
    Host.Print("Curator mode is off. " .. LEAVE_TEXT)
    Curator.Sharing.SendLeaving()
    return
  end
  local label = dialog.Delete.text
  if label and label.SetText then label:SetText(("Also delete my findings (%d), notes and collection history"):format(FindingsCount())) end
  dialog.Delete:SetChecked(false)
  -- sized to the text, with the checkbox under it
  dialog:Ask(LEAVE_TEXT)
end

OptOut.Finish = Finish

Host.OnLoaded(function() C_Timer.After(0, Build) end)
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", Build)
