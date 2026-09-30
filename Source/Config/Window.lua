-------------------------------------------------------------------------------
-- Recollect Settings Window
--
-- The suite's standard settings window (CobySuite.UI.CreateSettingsWindow):
-- a sidebar with Tooltips, Recollect Audit and Curator, staged edits that
-- Apply writes through Config.Set, Cancel, and Defaults, and a Guide button
-- beside Defaults. It grows from its corner and keeps its size. Built at
-- load, so opening it never creates frames in combat; a ConfigChanged
-- event repaints an open window.
-------------------------------------------------------------------------------
local Config = Recollect.Config
local Opt = Config.Options
local U = CobySuite_Recollect.Utilities
local UI = CobySuite_Recollect.UI

local WINDOW_W = 600
local WINDOW_H = 460
local SUB_OPTION_INDENT = 24   -- a radio group under the line that introduces it
local KEY_INDENT = 28          -- a key's row under its checkbox, level with the checkbox's label

-- Where a waypoint goes (UI/Waypoint.lua)
local WAYPOINT_CHOICES = {
  { value = "auto", label = "TomTom when it's installed, else the game's map pin" },
  { value = "game", label = "Always the game's map pin" },
}

local KEY_CHOICES = {
  { value = "alt",    label = "Hold Alt" },
  { value = "shift",  label = "Hold Shift (it also shows the game's item comparison)" },
  { value = "ctrl",   label = "Hold Ctrl" },
  { value = "always", label = "Always show it" },
}

-- The Curator category (curator spec, "The separation boundary"): Recollect
-- owns the category and declares every row now; the rows read the curator
-- provider when they show, and bind to the curator's own config, which the
-- category's config function names only once curator mode has registered.
-- Without a provider the category says curator mode isn't in this build.
local function CuratorProvider()
  return Recollect.CuratorProvider and Recollect.CuratorProvider() or nil
end

local function HasCurator()
  return CuratorProvider() ~= nil
end

local function CuratorText(index)
  local provider = CuratorProvider()
  local text = provider and provider.SETTINGS_TEXT and provider.SETTINGS_TEXT[index]
  return text or ""
end

-- Whether curator mode can run in this game region (the provider says;
-- true for a provider from before it could tell)
local function CuratorAvailable()
  local provider = CuratorProvider()
  if not provider then return false end
  if type(provider.IsAvailable) ~= "function" then return true end
  local ok, available = pcall(provider.IsAvailable)
  return ok and available == true
end

local function BuildCurator(panel)
  panel:Section("Curator mode")
  panel:Description("Curator mode isn't part of this build.", {
    visibleWhen = function() return not HasCurator() end,
  })
  -- outside the author's game region the section still explains curator
  -- mode, says why it's unavailable and grays its controls (Cobanyte,
  -- 2026-09-30)
  panel:Description("", {
    visibleWhen = function() return HasCurator() and not CuratorAvailable() end,
    refresh = function(row)
      local provider = CuratorProvider()
      local gold = U.Colors.STATUS_GOLD
      row.Text:SetTextColor(gold[1], gold[2], gold[3])
      row.Text:SetText(provider and provider.REGION_TEXT or "")
    end,
  })
  panel:Checkbox{
    key = "curator_enabled", label = "Help build Recollect's database (curator mode)",
    tooltip = "Off by default. While on, Recollect records where the game disagrees with its database, for its author to collect.",
    visibleWhen = HasCurator, enabledWhen = CuratorAvailable,
  }
  -- The opt-in paragraphs in white: they are what a player agrees to, not a
  -- side note in the descriptions' dim gray (Cobanyte, 2026-09-26)
  for index = 1, 5 do
    panel:Description("", {
      visibleWhen = HasCurator,
      refresh = function(row)
        local white = U.Colors.HIGHLIGHT_WHITE
        row.Text:SetTextColor(white[1], white[2], white[3])
        row.Text:SetText(CuratorText(index))
      end,
    })
  end
  panel:Checkbox{
    key = "curator_ask", label = "Ask me before each collection",
    tooltip = "Off by default: collections run in the background with a chat message when one starts and ends.",
    visibleWhen = function(get) return HasCurator() and get("curator_enabled") == true end,
    enabledWhen = CuratorAvailable,
  }
  panel:Description("", {
    visibleWhen = HasCurator,
    refresh = function(row)
      local provider = CuratorProvider()
      row.Text:SetText(provider and provider.Status and provider.Status() or "")
    end,
  })
  panel:Button{
    text = "Join the curator community", width = 200,
    tooltip = "Prints the community's invite link in chat; click it there to open Blizzard's join window.",
    visibleWhen = function(get)
      local provider = CuratorProvider()
      return provider ~= nil and CuratorAvailable() and get("curator_enabled") == true and provider.IsMember
        and provider.IsMember() == false
    end,
    onClick = function()
      local provider = CuratorProvider()
      if provider and provider.PrintJoinLink then provider.PrintJoinLink() end
    end,
  }
end

local window = UI.CreateSettingsWindow({
  name    = "RecollectOptionsWindow",
  title   = U.WrapColor(Recollect.BRAND_COLOR, "Recollect") .. " Settings",
  icon    = Recollect.ICON,
  config  = Config,
  width   = WINDOW_W,
  height  = WINDOW_H,
  persist = {
    svTable = function() return RECOLLECT_WINDOW_STATE end,
    key = "options",
  },
  watch   = { bus = Recollect.EventBus, event = Recollect.Events.ConfigChanged },
  message = function(text) Recollect.Utilities.Message(text) end,
  footerButtons = {
    {
      text = "Guide", width = 80,
      tooltip = "Open the feature guide: what Recollect shows and where to find it.",
      onClick = function()
        if Recollect.UI.Guide then Recollect.UI.Guide.Toggle() end
      end,
    },
  },
  categories = {
    -- Two groups: when the panel shows, then the keys it offers while it
    -- shows. Each key's row sits under its checkbox, level with its label.
    {
      key = "tooltip", label = "Tooltips",
      build = function(panel)
        panel:Section("Item tooltips")
        panel:Checkbox{
          key = Opt.SHOW_TOOLTIP, label = "Show Recollect on item tooltips",
          tooltip = "A line on the tooltip of any item in your bags, bank or warband bank says how to open the audit panel beside it.",
        }
        panel:Description("The audit panel beside the tooltip says what the item is for and whether you still need it. Show it:")
        panel:Radio{
          key = Opt.TOOLTIP_KEY, options = KEY_CHOICES, indent = SUB_OPTION_INDENT,
          tooltip = "When the audit panel appears beside an item's tooltip: while you hold this key, or every time.",
          enabledWhen = function(get) return get(Opt.SHOW_TOOLTIP) ~= false end,
        }
        panel:Section("Keys while the audit panel shows")
        panel:Checkbox{
          key = Opt.WAYPOINT_ENABLED, label = "Waypoint key: set a waypoint to the place the panel names",
          tooltip = "While the audit panel names a place Recollect knows (a vendor, a treasure or an NPC), this key puts a waypoint on your map to it. Not bound in combat.",
          enabledWhen = function(get) return get(Opt.SHOW_TOOLTIP) ~= false end,
        }
        panel:Keybind{
          key = Opt.WAYPOINT_KEY, label = "Key", indent = KEY_INDENT,
          tooltip = "Click, then press the key with its modifiers (Alt+W by default). Clear goes back to Alt+W.",
          enabledWhen = function(get) return get(Opt.SHOW_TOOLTIP) ~= false and get(Opt.WAYPOINT_ENABLED) ~= false end,
        }
        panel:Checkbox{
          key = Opt.PIN_ENABLED, label = "Pin key: pin the item's full details in a window",
          tooltip = "While the audit panel shows, this key opens a window with everything about the item: every use with no limit, what finishing a use takes, routes no longer available, and every check. Clicking a row of the Recollect Audit opens it too. Not bound in combat.",
          enabledWhen = function(get) return get(Opt.SHOW_TOOLTIP) ~= false end,
        }
        panel:Keybind{
          key = Opt.PIN_KEY, label = "Key", mouse = true, indent = KEY_INDENT,
          tooltip = "Click, then press the key with its modifiers (Alt+D by default), or hold Alt, Ctrl or Shift and click this button. A click works on any item: in your bags or bank, a chat link, loot, a vendor, even in combat. Shift+Left, Ctrl+Left and Shift+Right stay the game's own (link, preview, expand). Clear goes back to Alt+D.",
          enabledWhen = function(get) return get(Opt.SHOW_TOOLTIP) ~= false and get(Opt.PIN_ENABLED) ~= false end,
        }
        panel:Section("Waypoints")
        panel:Radio{
          key = Opt.WAYPOINT_PROVIDER, options = WAYPOINT_CHOICES,
          tooltip = "Where the waypoint key, the item details window's map buttons and its right-click menu put a waypoint. TomTom's arrow points the way; the game's map pin shows on the map and the compass.",
        }
      end,
    },
    {
      key = "list", label = "Recollect Audit",
      build = function(panel)
        panel:Section("What the list shows")
        panel:Description("The Recollect Audit (/rec, or a click on the minimap button) always lists the items in your bags.")
        panel:Checkbox{
          key = Opt.SHOW_BANK, label = "Include your bank",
          tooltip = "List this character's bank tabs, as they were when you last had the bank open.",
        }
        panel:Checkbox{
          key = Opt.SHOW_WARBAND, label = "Include the warband bank",
          tooltip = "List the warband bank tabs, as they were when last opened.",
        }
        panel:Checkbox{
          key = Opt.LIST_OTHERS, label = "Include your other characters",
          tooltip = "List what your other characters carried and stored when they last logged in, with a tab for each along the bottom of the Recollect Audit. Only checks that hold for the whole account run on them; everything else is checked on that character.",
        }
        panel:Section("Minimap button")
        panel:Checkbox{
          key = Opt.SHOW_MINIMAP, label = "Show the minimap button",
          tooltip = "A button on the minimap edge: click it to open the Recollect Audit, right-click for these settings, drag it to move it. The addon compartment menu has the same entry either way.",
        }
      end,
    },
    {
      key = "curator", label = "Curator",
      config = function()
        local provider = CuratorProvider()
        return provider and provider.Config and provider.Config() or nil
      end,
      build = BuildCurator,
    },
  },
})

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
function Config.ToggleSettings()
  window:Toggle()
end

function Config.OpenSettings()
  window:Open()
end

-- OpenSettingsAt(key): the window at one category ("curator" for the
-- curator dashboard's settings button)
function Config.OpenSettingsAt(key)
  window:Open()
  if key and window.panels and window.panels[key] then window:SelectCategory(key) end
end

-------------------------------------------------------------------------------
-- Options > AddOns entry (registered once this addon has finished loading).
-- Its text names the audit panel's key as the settings have it
-- (Recollect.PanelKeyName). The page is built once, so its text is set again
-- on every settings change.
-------------------------------------------------------------------------------
local PAGE_INTRO = "Shows what each item in your bags, bank and warband bank is for, and whether you still need it."
local PAGE_SETTINGS = "The key and the list's contents live in the addon's own settings window."

local function PageText()
  local key = Recollect.PanelKeyName()
  local how
  if key == "always" then
    how = "Point at an item to see its audit beside the tooltip."
  elseif key then
    how = ("Hold %s over an item to see its audit beside the tooltip."):format(key)
  else
    how = "The audit beside item tooltips is turned off."
  end
  return PAGE_INTRO .. "\n\n" .. how .. " " .. PAGE_SETTINGS
end

EventUtil.ContinueOnAddOnLoaded("Recollect", function()
  local text = PageText()
  local _, canvas = UI.RegisterSettingsCategory({
    name        = "Recollect",
    brandColor  = Recollect.BRAND_COLOR,
    version     = Recollect.VERSION,
    description = text,
    slash       = "/rec settings",
    onOpen      = Config.OpenSettings,
  })
  -- The page's body is the font string holding that text
  local body
  for _, region in ipairs({ canvas:GetRegions() }) do
    if region:IsObjectType("FontString") and region:GetText() == text then body = region end
  end
  if not body then return end
  local listener = {}
  function listener:ReceiveEvent() body:SetText(PageText()) end
  Recollect.EventBus:Register(listener, { Recollect.Events.ConfigChanged })
end)
