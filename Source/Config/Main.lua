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
    WAYPOINT_KEY     = "waypoint_key",      -- "ALT-W": sets a waypoint to the place the panel names
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
Config.CheckValue    = base.CheckValue
Config.Get           = base.Get
Config.Set           = base.Set

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

---------------------------------------------------------------------------
-- The settings window's words (Config/Window.lua), kept here so the suites
-- can read them: the audit panel's example, how current a bank's stored
-- tabs are, a key clash, and curator mode's state and pending change
---------------------------------------------------------------------------
local U = CobySuite_Recollect.Utilities
local Opt = Config.Options
local KEY_WORDS = { alt = "Alt", shift = "Shift", ctrl = "Ctrl" }

-- ExampleState(on, key): what the example shows for the staged choices:
-- its caption, the tooltip's hint line (nil: none) and whether the panel
-- shows. The hint is the one the tooltip prints (UI/Tooltip.lua)
function Config.ExampleState(on, key)
  if not on then
    return "Example: Recollect is off on tooltips, so there's no hint line and no panel", nil, false
  end
  local word = KEY_WORDS[key]
  if not word then return "Example: the panel shows every time you point at an item", nil, true end
  return ("Example with %s held"):format(word), Recollect.UI.Tooltip.HintText(key), true
end

-- How long ago a time was, in a few words
function Config.Ago(at, now)
  local seconds = math.max(0, (now or time()) - at)
  if seconds < 3600 then return "less than an hour ago" end
  if seconds < 86400 then
    local hours = math.floor(seconds / 3600)
    return hours == 1 and "an hour ago" or ("%d hours ago"):format(hours)
  end
  local days = math.floor(seconds / 86400)
  return days == 1 and "yesterday" or ("%d days ago"):format(days)
end

-- FreshnessLine(fresh, place, now): a bank tile's line from
-- Snapshots.Freshness ("your bank", "the warband bank")
function Config.FreshnessLine(fresh, place, now)
  local state = type(fresh) == "table" and fresh.state or nil
  if state == "open" then return "Read live while the bank is open" end
  if state == "never" then return ("Not read yet: open %s once"):format(place) end
  if state == "missing" then return ("Some tabs not read yet: open %s"):format(place) end
  if state == "changed" then return ("May have changed since: open %s again"):format(place) end
  if state == "read" and type(fresh.oldest) == "number" then return "Read " .. Config.Ago(fresh.oldest, now) end
  return "Can't tell when it was read"
end

-- KeysClash(get): the staged key both the pin and the waypoint key would
-- use, or nil. The waypoint key keeps it then (DetailWindow's Detail.Key)
function Config.KeysClash(get)
  if get(Opt.PIN_ENABLED) == false or get(Opt.WAYPOINT_ENABLED) == false then return nil end
  local pin, waypoint = get(Opt.PIN_KEY), get(Opt.WAYPOINT_KEY)
  if type(pin) ~= "string" or pin == "" or pin ~= waypoint then return nil end
  return pin
end

-- CuratorState(available, enabled, member): the card's line and dot for
-- curator mode as it is now (saved, never staged: a ticked box isn't on
-- until Apply). member: true, false or nil (unreadable)
function Config.CuratorState(available, enabled, member)
  if not available then return "Not available in your game region", U.Colors.STATUS_GOLD end
  if not enabled then return "Off: nothing is recorded or sent", U.Colors.DISABLED_GRAY end
  if member == true then return "On: this character sends its findings", U.Colors.SUCCESS_GREEN end
  if member == false then return "On; this character isn't in the community yet", U.Colors.STATUS_GOLD end
  return "On; the community list can't be read now", U.Colors.STATUS_GOLD
end

-- PendingCurator(staged, saved): the line under the opt-in while a change
-- waits for Apply, or nil. Nothing is recorded or deleted before Apply
function Config.PendingCurator(staged, saved)
  if staged == nil or (staged == true) == (saved == true) then return nil end
  if staged == true then return "Turns on when you press Apply." end
  return "Turns off when you press Apply. Recording stops then, and Recollect asks whether to delete your findings."
end
