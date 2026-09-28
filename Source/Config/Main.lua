local Config = Recollect.Config

---------------------------------------------------------------------------
-- Shared config base via CobySuite.Config.New; the settings window is
-- Config/Window.lua (/rec settings).
---------------------------------------------------------------------------
local base = CobySuite_Recollect.Config.New({
  savedVariable = "RECOLLECT_CONFIG",
  options = {
    SHOW_BANK    = "show_bank",      -- list this character's bank snapshot
    SHOW_WARBAND = "show_warband",   -- list the warband bank snapshot
    SHOW_TOOLTIP = "show_tooltip",   -- the Recollect hint and panel on item tooltips
    TOOLTIP_KEY  = "tooltip_key",    -- "alt" | "shift" | "ctrl": hold it for the panel; "always"
    WAYPOINT_ENABLED = "waypoint_enabled",  -- the panel's waypoint key is on
    WAYPOINT_KEY     = "waypoint_key",      -- "ALT-W": sets a waypoint to the vendor the panel names
    PIN_ENABLED      = "pin_enabled",       -- the panel's pin key is on
    PIN_KEY          = "pin_key",           -- "ALT-D": pins the panel's full details in a window
    LIST_OTHERS      = "list_other_characters",  -- the list shows other characters' stored items, a tab each (on by default)
    SHOW_MINIMAP     = "show_minimap_button",    -- the minimap button (UI/Minimap.lua)
    WAYPOINT_PROVIDER = "waypoint_provider",     -- "auto" (TomTom when loaded, else the game's pin) | "game" (UI/Waypoint.lua)
  },
  defaults = {
    ["show_bank"]    = true,
    ["show_warband"] = true,
    ["show_tooltip"] = true,
    ["tooltip_key"]  = "alt",
    ["waypoint_enabled"] = true,
    ["waypoint_key"]     = "ALT-W",
    ["pin_enabled"]      = true,
    ["pin_key"]          = "ALT-D",
    ["list_other_characters"] = true,
    ["show_minimap_button"]   = true,
    ["waypoint_provider"]     = "auto",
  },
  validate = {
    ["show_bank"]    = { type = "boolean" },
    ["show_warband"] = { type = "boolean" },
    ["show_tooltip"] = { type = "boolean" },
    ["tooltip_key"]  = { type = "string", values = { "alt", "shift", "ctrl", "always" } },
    ["waypoint_enabled"] = { type = "boolean" },
    ["waypoint_key"]     = { type = "string" },
    ["pin_enabled"]      = { type = "boolean" },
    ["pin_key"]          = { type = "string" },
    ["list_other_characters"] = { type = "boolean" },
    ["show_minimap_button"]   = { type = "boolean" },
    ["waypoint_provider"]     = { type = "string", values = { "auto", "game" } },
  },
  debug = Recollect.Debug,
  onSet = function(name, old, value)
    Recollect.EventBus:Fire(Recollect.Events.ConfigChanged, name, value, old)
  end,
  onReset = function()
    Recollect.EventBus:Fire(Recollect.Events.ConfigChanged)
  end,
})

Config.Options       = base.Options
Config.Defaults      = base.Defaults
Config.IsValidOption = base.IsValidOption
Config.CheckValue    = base.CheckValue
Config.Get           = base.Get
Config.Set           = base.Set
Config.Reset         = base.Reset

---------------------------------------------------------------------------
-- InitializeData: wraps base with addon-specific SavedVariable init
---------------------------------------------------------------------------
function Config.InitializeData()
  base.InitializeData()
  -- Anything but a table here is a damaged file: start that table over
  if type(RECOLLECT_WINDOW_STATE) ~= "table" then
    RECOLLECT_WINDOW_STATE = {}
  end
  -- Once: "Include your other characters" became on by default
  -- (Cobanyte, 2026-09-28), and a saved "off" from the beta, when it
  -- defaulted off, is turned on this one time; a later "off" stays
  local done = type(RECOLLECT_WINDOW_STATE.migrations) == "table" and RECOLLECT_WINDOW_STATE.migrations or {}
  RECOLLECT_WINDOW_STATE.migrations = done
  if not done.listOthersOn then
    done.listOthersOn = true
    if type(RECOLLECT_CONFIG) == "table" and RECOLLECT_CONFIG.list_other_characters == false then
      RECOLLECT_CONFIG.list_other_characters = true
    end
  end
end
