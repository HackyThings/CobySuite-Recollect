-------------------------------------------------------------------------------
-- Show Achievement (Cobanyte, 2026-09-28): the game's achievement window,
-- opened at an achievement from the item details window's row menu, with
-- nothing of Blizzard's achievement UI loaded or toggled by Recollect's code.
--
-- Blizzard's ShowAchievementFrameForAchievement (Blizzard_AchievementUI's
-- Bootstrap.lua) loads Blizzard_AchievementUI when it isn't loaded, and
-- toggles the window (AchievementFrame_ToggleAchievementFrame) when it isn't
-- shown. Run from addon code, the load defines every global of the
-- achievement UI with Recollect's taint, and the toggle writes the global
-- AchievementFrameTab_OnClick (both seen in the Taint suite's first in-game
-- run, 2026-09-28). With the window already shown it only selects the
-- achievement. So:
-- - the window is shown: the achievement is selected at once
-- - otherwise: a small window of ours asks for one click. Its Open button is
--   an insecure action button whose macro "/click AchievementMicroButton"
--   clicks the micro menu's own button on the secure path (its OnClick is
--   ToggleAchievementFrame, Blizzard_MicroMenu's MainMenuBarMicroButtons.lua),
--   so the game loads and opens its window itself; once the window shows,
--   Recollect selects the achievement and the small window closes. The
--   micro button toggles, so the prompt never stays up while the window is
--   shown. A menu entry can't make that secure click itself, which is why
--   the extra click is asked for (the repo's taint notes, pitfall 5).
--
-- One achievement waits at a time: a second Show Achievement replaces it.
-- The window is built on its first use out of combat; in combat Show
-- Achievement says it waits, and the window shows when combat ends. When the
-- micro button can't open the window (turned off by the game, or not usable
-- yet on this character), a chat line says so instead. Client calls go
-- through Prompt.seams.
-------------------------------------------------------------------------------
local U = CobySuite_Recollect.Utilities

local Prompt = {}
Recollect.UI.AchievementPrompt = Prompt

Prompt.MACRO = "/click AchievementMicroButton"
Prompt.RETRY = 0.5   -- seconds before the click's result is looked at again

Prompt.seams = {
  Shown = function() return AchievementFrame ~= nil and AchievementFrame:IsShown() == true end,
  -- only ever called with the window shown: it selects, nothing else
  Select = function(achievementID) ShowAchievementFrameForAchievement(achievementID) end,
  InCombat = function() return InCombatLockdown() end,
  -- The micro button's own gates (AchievementMicroButtonMixin:OnClick and
  -- UpdateMicroButton: Kiosk, no achievement yet and not in a guild,
  -- CanShowAchievementUI all leave it disabled) and the game rule
  -- ToggleAchievementFrame checks
  Clickable = function()
    local micro = AchievementMicroButton
    if not micro or not micro:IsEnabled() then return false end
    if DISALLOW_FRAME_TOGGLING then return false end
    local ok, off = pcall(function() return C_GameRules.IsGameRuleActive(Enum.GameRule.AchievementsPanelDisabled) end)
    return not (ok and off)
  end,
  Name = function(achievementID)
    local _, name = GetAchievementInfo(achievementID)
    return name
  end,
  After = function(seconds, fn) C_Timer.After(seconds, fn) end,
  Message = function(text) Recollect.Utilities.Message(text) end,
}

local WIDTH, HEIGHT, PAD = 400, 150, 16

local dialog
local pending = nil     -- the achievement waiting for the window to open
local waiting = false   -- asked in combat: show the window once it ends

local function Body(achievementID)
  local ok, name = pcall(Prompt.seams.Name, achievementID)
  local what = (ok and type(name) == "string" and name ~= "") and U.WrapColor(U.Colors.STATUS_GOLD, name) or "the achievement"
  return "Blizzard's achievement window is closed. Open it with the button below, so the game opens it "
    .. "itself; Recollect then shows " .. what .. " in it.\n\n"
    .. "(When an addon opens that window itself, the game counts what happens in it afterwards as the "
    .. "addon's, which can get actions blocked.)"
end

-- The window is up: select the waiting achievement and close ours
local function Finish()
  local id = pending
  pending = nil
  if dialog then dialog:Hide() end
  if id then pcall(Prompt.seams.Select, id) end
end

-- After the Open click: the window should be up by now (the load and the
-- toggle run inside the click); looked at once more a moment later
local function Check(triesLeft)
  if not pending then return end
  if Prompt.seams.Shown() then return Finish() end
  if triesLeft > 0 then
    Prompt.seams.After(Prompt.RETRY, function() Check(triesLeft - 1) end)
    return
  end
  Prompt.seams.Message("The achievement window didn't open. Open it once with the achievements key or the micro menu, then use Show Achievement again.")
end

local function Build()
  if dialog or Prompt.seams.InCombat() then return end
  dialog = CobySuite_Recollect.UI.CreateWindow({
    name = "RecollectAchievementPrompt", title = "Show Achievement", icon = Recollect.ICON,
    width = WIDTH, height = HEIGHT, strata = "DIALOG", escapeCloses = true,
    point = { "CENTER", UIParent, "CENTER", 0, 120 },
  })
  dialog.Body = dialog:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  dialog.Body:SetPoint("TOPLEFT", dialog, "TOPLEFT", PAD, -34)
  dialog.Body:SetWidth(WIDTH - 2 * PAD)
  dialog.Body:SetJustifyH("LEFT")
  dialog.Body:SetWordWrap(true)
  -- the shared button's look on an insecure action button: its click runs
  -- the macro on the secure path, once, on release, never with a modifier
  -- (the pattern of the old channel's leave prompt, verified in game 2026-09-28)
  dialog.Open = CobySuite_Recollect.UI.CreateButton(dialog, { text = "Open achievements", size = { 150, U.ButtonSize.MEDIUM.height },
    point = { "BOTTOMLEFT", dialog, "BOTTOMLEFT", PAD, 14 }, template = "UIPanelButtonTemplate, InsecureActionButtonTemplate" })
  CobySuite_Recollect.UI.ConfigureSecureClicker(dialog.Open, { type = "macro", macrotext = Prompt.MACRO, blockModified = true })
  dialog.Open:HookScript("PostClick", function()
    if Prompt.seams.InCombat() then
      Prompt.seams.Message("The achievement window can't be opened from here in combat; click Open achievements again once combat ends.")
      return
    end
    Prompt.seams.After(0, function() Check(1) end)
  end)
  dialog.Cancel = CobySuite_Recollect.UI.CreateButton(dialog, { text = "Cancel", size = { 110, U.ButtonSize.MEDIUM.height },
    point = { "BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -PAD, 14 },
    onClick = function() dialog:Hide() end })
  -- the achievements key or the micro menu used while ours is up: select
  -- as soon as the window shows
  dialog:HookScript("OnUpdate", function()
    if pending and Prompt.seams.Shown() then Finish() end
  end)
  -- closed (Cancel, the X, Escape, or done): nothing waits any more
  dialog:HookScript("OnHide", function()
    pending = nil
    waiting = false
  end)
  dialog:Hide()
end

-- Shows the window for the waiting achievement, or says why it can't
local function Ask()
  if not pending then return nil end
  if not Prompt.seams.Clickable() then
    pending = nil
    Prompt.seams.Message("The achievement window can't be opened right now: the game has it turned off here.")
    return "unavailable"
  end
  Build()
  if not dialog then return nil end
  dialog.Body:SetText(Body(pending))
  dialog:Show()
  return "prompt"
end

-- Show(achievementID): what Show Achievement does. Returns "selected" (the
-- window was shown and the achievement is selected in it), "prompt" (our
-- window asks for the click), "waiting" (in combat; it asks once combat
-- ends), "unavailable" (the game can't open the window here) or nil (no
-- achievement)
function Prompt.Show(achievementID)
  if not Recollect.Utilities.IsPositiveID(achievementID) then return nil end
  if Prompt.seams.Shown() then
    pending = achievementID
    Finish()
    return "selected"
  end
  pending = achievementID
  if Prompt.seams.InCombat() then
    waiting = true
    Prompt.seams.Message("The achievement window can be opened once combat ends; Recollect will ask then.")
    return "waiting"
  end
  return Ask()
end

-- AfterSecureClick(achievementID, wasShown): the details window's
-- achievement button was clicked (UI/DetailWindow.lua, AchievementButton):
-- its own macro opened the window on the secure path unless it was shown
-- already; the achievement is selected once the window is up
function Prompt.AfterSecureClick(achievementID, wasShown)
  if not Recollect.Utilities.IsPositiveID(achievementID) then return nil end
  pending = achievementID
  if wasShown then Finish() return "selected" end
  Prompt.seams.After(0, function() Check(1) end)
  return "opening"
end

function Prompt.Pending() return pending end

function Prompt.IsShown()
  return dialog ~= nil and dialog:IsShown()
end

-- Combat ended: the window asked for in combat shows now
local function OnCombatEnded()
  if not waiting then return end
  waiting = false
  Ask()
end

-- Tests: the window (its button's macro), the build, the click's check, the
-- end of combat, and a reset that leaves nothing waiting
Prompt._test = {
  Window = function() return dialog end,
  Build = Build,
  Check = Check,
  CombatEnded = OnCombatEnded,
  Waiting = function() return waiting end,
  Reset = function()
    if dialog then dialog:Hide() end
    pending, waiting = nil, false
  end,
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function()
  pcall(OnCombatEnded)
end)
