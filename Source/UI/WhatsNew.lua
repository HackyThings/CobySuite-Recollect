-------------------------------------------------------------------------------
-- UI.WhatsNew: Recollect's changelog window and what its login shows
-- (Cobanyte, 2026-09-27), on the shared CobySuite.UI.CreateWhatsNewWindow:
-- one collapsible section per version of Data/Changelog.lua, /rec changelog
-- any time. At login RECOLLECT_WINDOW_STATE.lastVersion says what the player
-- last ran: none (a fresh install) opens the feature guide, an older version
-- this window with every version since then open, else nothing; either
-- waits for combat to end. Core.lua's PLAYER_LOGIN calls OnLogin, which
-- builds the window out of combat.
-------------------------------------------------------------------------------
local UI = Recollect.UI
local U = CobySuite_Recollect.Utilities
local Shared = CobySuite_Recollect.UI.WhatsNew

local WhatsNew = {}
UI.WhatsNew = WhatsNew

-- The shared helpers under the names the suites use
WhatsNew.CompareVersions = U.CompareVersions
WhatsNew.SectionKey = Shared.SectionKey
WhatsNew.Line = Shared.Line
WhatsNew.Decide = Shared.Decide
function WhatsNew.Sections(log)
  return Shared.Sections(log, Recollect.ICON)
end

local changelog = CobySuite_Recollect.UI.CreateWhatsNewWindow({
  name = "RecollectChangelogWindow",
  title = "Recollect: What's New",
  icon = Recollect.ICON,
  intro = "What changed in each version of Recollect, newest first. Click a version to open or close it.",
  footer = "Open this window any time with " .. U.WrapColor(U.Colors.HELP_COMMAND, "/rec changelog"),
  entries = Recollect.Data.Changelog,
  version = Recollect.VERSION,
  state = function() return RECOLLECT_WINDOW_STATE end,
  onFirstRun = function() if UI.Guide then UI.Guide.Show() end end,
  combatMessage = function(text) Recollect.Utilities.Message(text) end,
  onShow = function(what) Recollect.Debug.Log("UI", "Login shows the %s", what) end,
})

-- The window's instance, for the suites (its opts and built window)
WhatsNew._test = { instance = changelog }

function WhatsNew.Build() return changelog:Build() end
function WhatsNew.Toggle() changelog:Toggle() end
function WhatsNew.ShowVersions(keys) changelog:ShowVersions(keys) end
function WhatsNew.OnLogin() changelog:OnLogin() end
