-------------------------------------------------------------------------------
-- Leaving the old hidden channel (Cobanyte, 2026-09-28)
--
-- TODO(Cobanyte): remove this file, its TOC line and Const.CHANNEL_NAME once
-- no curator runs a version from before 2026-09-28 (0.0.1c and older).
--
-- Recollect up to 0.0.1c put every curator's character in a hidden chat
-- channel, Curator.Const.CHANNEL_NAME ("RecollectCurators"), which took one
-- of their chat channel slots. Curator traffic goes by whisper now
-- (Transport.lua), so a character still in that channel is asked, in a
-- window of its own, to leave it. The game blocks leaving a channel from
-- addon code (LeaveChannelByName was forbidden for Recollect, 0.0.1c curator
-- error reports), so the Leave button is an insecure action button whose
-- click runs the macro "/leave RecollectCurators" on the secure path. The
-- macro names that one channel by its full name, never a number, so no
-- other channel can be left; the window shows only while this character is
-- in a channel of exactly that name.
--
-- Verified in game 2026-09-28: Leave channel left RecollectCurators and no
-- other channel moved.
--
-- Looked at 20 seconds after entering the world, out of combat (in combat it
-- waits for combat to end); Not now closes it until the next login. It asks
-- whether or not curator mode is on: the channel is Recollect's either way.
-- Client calls go through Leave.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local U = CobySuite_Recollect.Utilities

local Leave = {}
Curator.LeaveOldChannel = Leave

Leave.AFTER = 20   -- seconds after entering the world before looking
Leave.MACRO = "/leave " .. Curator.Const.CHANNEL_NAME

Leave.seams = {
  ChannelIndex = function(name) return GetChannelName(name) end,
  InCombat = function() return InCombatLockdown() end,
  After = function(delay, fn) C_Timer.After(delay, fn) end,
}

local WIDTH, HEIGHT, PAD = 420, 146, 16

local dialog
local waiting = false   -- asked in combat: look again once it ends
local looked = false    -- looked this session

-- InChannel(): the index of the old channel when this character is in it
-- (a channel of exactly that name), else nil
function Leave.InChannel()
  local ok, index, name = pcall(Leave.seams.ChannelIndex, Curator.Const.CHANNEL_NAME)
  if not ok or Host.IsSecret(index) or Host.IsSecret(name) then return nil end
  if type(index) ~= "number" or index <= 0 then return nil end
  if type(name) == "string" and name:lower() ~= Curator.Const.CHANNEL_NAME:lower() then return nil end
  return index
end

Leave.BODY = "Earlier versions of Recollect put this character in a hidden chat channel, RecollectCurators, "
  .. "which takes one of your chat channel slots. Curator mode no longer needs it.\n\n"
  .. "Leave that channel now? Only RecollectCurators is left; your other channels stay as they are."

local function Build()
  if dialog or Leave.seams.InCombat() then return end
  dialog = CobySuite_Recollect.UI.CreateWindow({
    name = "RecollectCuratorLeaveChannel", title = "Leave Recollect's old chat channel?", icon = Host.Icon(),
    width = WIDTH, height = HEIGHT, strata = "DIALOG", escapeCloses = true,
    point = { "CENTER", UIParent, "CENTER", 0, 120 },
  })
  dialog.Body = dialog:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  dialog.Body:SetPoint("TOPLEFT", dialog, "TOPLEFT", PAD, -34)
  dialog.Body:SetWidth(WIDTH - 2 * PAD)
  dialog.Body:SetJustifyH("LEFT")
  dialog.Body:SetWordWrap(true)
  dialog.Body:SetText(Leave.BODY)
  -- the shared button's look on an insecure action button: its click runs
  -- the macro on the secure path, once, on release, never with a modifier
  dialog.Leave = CobySuite_Recollect.UI.CreateButton(dialog, { text = "Leave channel", size = { 140, U.ButtonSize.MEDIUM.height },
    point = { "BOTTOMLEFT", dialog, "BOTTOMLEFT", PAD, 14 }, template = "UIPanelButtonTemplate, InsecureActionButtonTemplate" })
  dialog.Leave:RegisterForClicks("LeftButtonUp")
  dialog.Leave:SetAttribute("useOnKeyDown", false)
  dialog.Leave:SetAttribute("type", "macro")
  dialog.Leave:SetAttribute("macrotext", Leave.MACRO)
  dialog.Leave:SetAttribute("shift-type*", "")
  dialog.Leave:SetAttribute("ctrl-type*", "")
  dialog.Leave:SetAttribute("alt-type*", "")
  dialog.Leave:HookScript("PostClick", function()
    Host.Log("Curator old channel: Leave pressed (%s)", Leave.MACRO)
    Leave.seams.After(1, function()
      if dialog then dialog:Hide() end
      if Leave.InChannel() then
        Host.Print("Recollect: still in the RecollectCurators channel; type /leave RecollectCurators to leave it.")
      else
        Host.Print("Recollect: left the RecollectCurators channel.")
      end
    end)
  end)
  dialog.Later = CobySuite_Recollect.UI.CreateButton(dialog, { text = "Not now", size = { 130, U.ButtonSize.MEDIUM.height },
    point = { "BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -PAD, 14 },
    onClick = function() dialog:Hide() end })
  dialog:Hide()
end

-- Look(): shows the window when this character is in the old channel;
-- returns whether it showed (or will once combat ends)
function Leave.Look()
  if not Leave.InChannel() then return false end
  if Leave.seams.InCombat() then
    waiting = true
    return true
  end
  Build()
  if not dialog then return false end
  dialog:Show()
  Host.Log("Curator old channel: this character is in %s; asked to leave it", Curator.Const.CHANNEL_NAME)
  return true
end

-- Tests: the window, to read its button's macro
Leave._test = { Window = function() return dialog end, Build = Build }

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" then
    if waiting then
      waiting = false
      pcall(Leave.Look)
    end
    return
  end
  if looked then return end
  looked = true
  Leave.seams.After(Leave.AFTER, function() pcall(Leave.Look) end)
end)
