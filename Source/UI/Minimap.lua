-------------------------------------------------------------------------------
-- Minimap button, LibDataBroker launcher and addon compartment entry, all from
-- the shared launcher (CobySuite.UI.CreateLauncher). A click opens the
-- Recollect Audit (the same as /rec), a right-click the settings; the hover
-- names the audit panel's key. The TOC's compartment globals in Core.lua call
-- the launcher; Core.lua's PLAYER_LOGIN calls Initialize.
-------------------------------------------------------------------------------
local UI = Recollect.UI
local Config = Recollect.Config

local Minimap_Module = {}
UI.Minimap = Minimap_Module

local function TooltipOpts()
  local hint = Recollect.PanelKeyHint()
  return {
    brandColor = Recollect.BRAND_COLOR,
    title      = "Recollect",
    body       = hint and { hint } or nil,
    keys = {
      { key = "Left-click",  desc = "Open the Recollect Audit" },
      { key = "Right-click", desc = "Open settings" },
    },
  }
end

local launcher = CobySuite_Recollect.UI.CreateLauncher({
  name         = "Recollect",
  label        = "Recollect",
  icon         = Recollect.ICON,
  buttonName   = "RecollectMinimapButton",
  tooltip      = TooltipOpts,
  onLeftClick  = function() if UI.ToggleList then UI.ToggleList() end end,
  onRightClick = function() if Config.ToggleSettings then Config.ToggleSettings() end end,
  persist      = {
    svTable      = function() return RECOLLECT_WINDOW_STATE end,
    key          = "minimapAngle",
    defaultAngle = 200,
  },
  isShown      = function() return Config.Get(Config.Options.SHOW_MINIMAP) ~= false end,
  buttonTooltipAnchor      = "ANCHOR_LEFT",
  compartmentTooltipAnchor = "ANCHOR_LEFT",
})
Minimap_Module.Launcher = launcher

function Minimap_Module.Initialize()
  launcher:Initialize()
  Recollect.Debug.Log("INIT", "Minimap button initialized (angle: %d)", launcher:GetAngle())
end

-- Show or hide the button when the setting changes. A nil key (Defaults, a
-- restored snapshot) means any option may have changed.
local listener = { ReceiveEvent = function(_, _, key)
  if key == nil or key == Config.Options.SHOW_MINIMAP then
    launcher:RefreshShown()
  end
end }
Recollect.EventBus:Register(listener, { Recollect.Events.ConfigChanged })
