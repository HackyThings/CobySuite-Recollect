Recollect = {
  Debug = {},
  Config = {},
  Utilities = {},
  Inventory = {},
  Facts = {},
  Purposes = {},
  Verdicts = {},
  UI = {},
  Data = {},
}

Recollect.BRAND_COLOR = "9ACD32"
-- The addon's icon: the TOC's IconTexture, the minimap button and window titles
Recollect.ICON = "Interface\\Icons\\achievement_faction_goldenlotus"

-------------------------------------------------------------------------------
-- EventBus event constants
-------------------------------------------------------------------------------
Recollect.Events = {
  ConfigChanged = "recollect_config_changed",
  -- Anything a verdict reads may have changed: a bag, a bank snapshot, item
  -- data that finished loading, or a data source that became ready
  InventoryChanged = "recollect_inventory_changed",
  -- A bank or warband bank snapshot was stored: (kind, bagIDs)
  SnapshotCaptured = "recollect_snapshot_captured",
  -- Curator mode's notes changed (a flag saved, sent or delivered): the
  -- details window repaints its Curator Flag button
  CuratorNotesChanged = "recollect_curator_notes_changed",
}

-------------------------------------------------------------------------------
-- Addon metadata
-------------------------------------------------------------------------------
local ADDON_NAME = "Recollect"
local VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "0.0.1"
Recollect.VERSION = VERSION

-------------------------------------------------------------------------------
-- The audit panel's key as the settings have it, for help text: "Alt",
-- "Shift" or "Ctrl"; "always" when the panel shows without one; nil when the
-- item tooltip hint and panel are off. Read when the text is shown, so it
-- follows the settings; an unknown key counts as Alt, as UI/Tooltip.lua's
-- Key() does.
-------------------------------------------------------------------------------
local PANEL_KEY_NAMES = { alt = "Alt", shift = "Shift", ctrl = "Ctrl" }

function Recollect.PanelKeyName()
  local Config = Recollect.Config
  if not Config.Get then return "Alt" end
  if Config.Get(Config.Options.SHOW_TOOLTIP) == false then return nil end
  local key = Config.Get(Config.Options.TOOLTIP_KEY)
  if key == "always" then return "always" end
  return PANEL_KEY_NAMES[key] or "Alt"
end

-- The launcher tooltip's line about the panel (UI/Minimap.lua): nil while
-- the panel is off
function Recollect.PanelKeyHint()
  local key = Recollect.PanelKeyName()
  if key == "always" then return "Point at any item for its audit" end
  if key then return ("Hold %s over any item for its audit"):format(key) end
  return nil
end

-------------------------------------------------------------------------------
-- Curator provider (curator spec, "The separation boundary", D33): curator
-- mode registers one table of plain functions at load, and Recollect names
-- the curator only through it, in these places: the settings window's
-- Curator category, the guide's curator section, /rec curator and /rec
-- feedback, and the details window's Curator Flag button. Without a
-- provider (the curator's files removed) each does the plain thing.
-------------------------------------------------------------------------------
local curatorProvider

function Recollect.RegisterCuratorProvider(provider)
  curatorProvider = provider
end

function Recollect.CuratorProvider()
  return curatorProvider
end

-------------------------------------------------------------------------------
-- Addon Compartment entry (named in the TOC): the shared launcher in
-- UI/Minimap.lua handles it like the minimap button (a click opens the
-- Recollect Audit, a right-click the settings)
-------------------------------------------------------------------------------
function Recollect_OnAddonCompartmentClick(_, button)
  if Recollect.UI.Minimap then Recollect.UI.Minimap.Launcher:OnCompartmentClick(button) end
end

function Recollect_OnAddonCompartmentEnter(_, menuItem)
  if Recollect.UI.Minimap then Recollect.UI.Minimap.Launcher:OnCompartmentEnter(menuItem) end
end

function Recollect_OnAddonCompartmentLeave()
  if Recollect.UI.Minimap then Recollect.UI.Minimap.Launcher:OnCompartmentLeave() end
end

-------------------------------------------------------------------------------
-- Slash commands
--
-- Registered through CobySuite.Slash, which generates help and version. A
-- bare /rec opens the Recollect Audit. "test" and "lab" exist only while
-- the Tests folder is loaded: release builds strip it, and available() hides both.
-- "curator" is handed to the curator provider.
-------------------------------------------------------------------------------
local function ToggleList()
  if Recollect.UI.ToggleList then Recollect.UI.ToggleList() end
end

CobySuite_Recollect.Slash.Register({
  key = "RECOLLECT",
  slashes = { "/recollect", "/rec" },
  title = "Recollect",
  version = VERSION,
  message = function(text) Recollect.Utilities.Message(text) end,
  commands = {
    { name = "show", help = "Open or close the Recollect Audit", run = ToggleList },
    {
      name = "settings", aliases = { "config", "options" }, help = "Open the settings window",
      run = function()
        if Recollect.Config.ToggleSettings then Recollect.Config.ToggleSettings() end
      end,
    },
    {
      name = "guide", aliases = { "tutorial" }, help = "Open or close the feature guide",
      run = function()
        if Recollect.UI.Guide then Recollect.UI.Guide.Toggle() end
      end,
    },
    {
      name = "changelog", aliases = { "change", "whatsnew", "news" }, help = "Open or close the changelog: what changed in each version",
      run = function()
        if Recollect.UI.WhatsNew then Recollect.UI.WhatsNew.Toggle() end
      end,
    },
    {
      name = "debug", help = "Open or close the debug log window",
      run = function()
        if Recollect.DebugWindow then Recollect.DebugWindow:Toggle() end
      end,
    },
    {
      name = "curator", usage = "curator [join|cancel]",
      help = "Curator mode: help build Recollect's database (status or the running collection; join prints the invite link; cancel stops a collection)",
      run = function(rest)
        local provider = curatorProvider
        if provider and provider.Slash then
          provider.Slash(rest)
        else
          Recollect.Utilities.Message("Curator mode isn't part of this build.")
        end
      end,
    },
    {
      name = "feedback", aliases = { "bug" },
      help = "Write feedback for Recollect's author; it's sent with your next curator collection",
      run = function()
        local provider = curatorProvider
        if provider and provider.OpenFeedback then
          provider.OpenFeedback()
        else
          Recollect.Utilities.Message("Feedback travels with curator mode, which isn't part of this build.")
        end
      end,
    },
    {
      name = "test", usage = "test [suite]",
      help = "Open the in-game test window, optionally running one suite",
      available = function() return Recollect.Tests ~= nil end,
      run = function(rest)
        local tests = Recollect.Tests
        if not tests then return end
        tests.Window:Show()
        local suite = rest and rest:match("^%s*(%S+)")
        if suite then tests.RunSuite(suite) end
      end,
    },
    {
      name = "lab", help = "Open the development Lab: what the game answers in each state, as one report",
      available = function() return Recollect.Tests ~= nil and Recollect.Tests.Lab ~= nil end,
      run = function()
        local tests = Recollect.Tests
        if tests and tests.Lab then tests.Lab.Open() end
      end,
    },
  },
  onEmpty = ToggleList,
})

-------------------------------------------------------------------------------
-- Startup sequence
-------------------------------------------------------------------------------
EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
  if Recollect.Config.InitializeData then Recollect.Config.InitializeData() end
  if Recollect.Inventory.Snapshots and Recollect.Inventory.Snapshots.InitializeData then
    Recollect.Inventory.Snapshots.InitializeData()
  end
  Recollect.Debug.Log("INIT", "Recollect v%s loaded", VERSION)
end)

EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_LOGIN", function()
  if Recollect.UI.Minimap then Recollect.UI.Minimap.Initialize() end
  -- A fresh install opens the guide; an update, the changelog
  if Recollect.UI.WhatsNew then Recollect.UI.WhatsNew.OnLogin() end
  Recollect.Debug.Log("INIT", "PLAYER_LOGIN complete")
end)
