-------------------------------------------------------------------------------
-- Recollect Settings Window
--
-- The suite's standard settings window (CobySuite.UI.CreateSettingsWindow):
-- a sidebar with Audit panel, Recollect Audit, Keys and waypoints and
-- Curator, staged edits that Apply writes through Config.Set, Cancel, and
-- Defaults, and a Guide button beside Defaults. It grows from its corner and
-- keeps its size. Built at load, so opening it never creates frames in
-- combat; a ConfigChanged event repaints an open window.
--
-- The contents follow the settings redesign (Task #51, 2026-10-01): each
-- page leads with one thing to look at (the audit
-- panel's example, the list's sources with how current they are, the
-- curator card), staged choices show in the example before Apply, and live
-- state (a bank last read, TomTom, curator mode) is read when the page
-- paints, never staged.
-------------------------------------------------------------------------------
local Config = Recollect.Config
local Opt = Config.Options
local U = CobySuite_Recollect.Utilities
local UI = CobySuite_Recollect.UI

local KEY_INDENT = 28          -- a key's row under its checkbox, level with the checkbox's label

local ICONS = "Interface\\Icons\\"
local KIND_BANK = Recollect.Inventory.Locations.KIND_BANK
local KIND_WARBAND = Recollect.Inventory.Locations.KIND_WARBAND

-------------------------------------------------------------------------------
-- Audit panel: the example and the key tiles
-------------------------------------------------------------------------------
-- The key tiles (tooltip_key): a keycap for each key; Always as its word
local KEY_TILES = {
  { value = "alt", face = "Alt", title = "Hold Alt", description = "The panel shows while you hold it",
    tooltip = "The audit panel shows beside an item's tooltip while you hold Alt." },
  { value = "shift", face = "Shift", title = "Hold Shift", description = "Also opens the game's item comparison",
    tooltip = "The audit panel shows while you hold Shift. Shift also shows the game's own item comparison, so both open together." },
  { value = "ctrl", face = "Ctrl", title = "Hold Ctrl", description = "The panel shows while you hold it",
    tooltip = "The audit panel shows beside an item's tooltip while you hold Ctrl." },
  { value = "always", icon = Recollect.ICON, title = "Always", description = "Every item, no key and no hint line",
    tooltip = "The audit panel shows whenever you point at an item. The tooltip gets no hint line." },
}

-- The example's sample item and answer: illustrative only, never a real
-- evaluation (a real verdict pass at every repaint would cost too much)
local EXAMPLE_ITEM = "Old Explorer's Map"
local EXAMPLE_ANSWER = "A quest you're on uses it"

local function Box(parent, color)
  local t = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
  t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
  return t
end

-- The example's frames, made once in the Preview's frame: a small item
-- tooltip with its hint line, and a small audit panel beside it (the
-- caption is the kit's own, live)
local function BuildExample(frame)
  local gray, white = U.Colors.LABEL_GRAY, U.Colors.HIGHLIGHT_WHITE
  frame.Tip = Box(frame, U.Colors.TOAST_BG)
  frame.Tip:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
  frame.Tip:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -3, 8)
  frame.Icon = frame:CreateTexture(nil, "ARTWORK")
  frame.Icon:SetSize(20, 20)
  frame.Icon:SetPoint("TOPLEFT", frame.Tip, "TOPLEFT", 6, -6)
  frame.Icon:SetTexture(ICONS .. "INV_Misc_Map_01")
  frame.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  frame.Name = frame:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
  frame.Name:SetPoint("LEFT", frame.Icon, "RIGHT", 6, 0)
  frame.Name:SetPoint("RIGHT", frame.Tip, "RIGHT", -6, 0)
  frame.Name:SetJustifyH("LEFT")
  frame.Name:SetWordWrap(false)
  frame.Name:SetTextColor(white[1], white[2], white[3])
  frame.Name:SetText(EXAMPLE_ITEM)
  frame.Hint = frame:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
  frame.Hint:SetPoint("TOPLEFT", frame.Icon, "BOTTOMLEFT", 0, -6)
  frame.Hint:SetPoint("RIGHT", frame.Tip, "RIGHT", -6, 0)
  frame.Hint:SetJustifyH("LEFT")
  frame.Hint:SetWordWrap(false)
  frame.Hint:SetTextColor(gray[1], gray[2], gray[3])
  frame.Panel = Box(frame, U.Colors.WINDOW_BG)
  frame.Panel:SetPoint("TOPLEFT", frame, "TOP", 3, -8)
  frame.Panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
  frame.Verdict = frame:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  frame.Verdict:SetPoint("TOPLEFT", frame.Panel, "TOPLEFT", 8, -8)
  frame.Answer = frame:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
  frame.Answer:SetPoint("TOPLEFT", frame.Verdict, "BOTTOMLEFT", 0, -4)
  frame.Answer:SetPoint("RIGHT", frame.Panel, "RIGHT", -8, 0)
  frame.Answer:SetJustifyH("LEFT")
  frame.Answer:SetWordWrap(true)
  frame.Answer:SetText(EXAMPLE_ANSWER)
  frame.Off = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.Off:SetPoint("CENTER", frame.Panel, "CENTER")
  frame.Off:SetText("No panel")
end

local function ExampleNow(window)
  return Config.ExampleState(window:Get(Opt.SHOW_TOOLTIP) ~= false, window:Get(Opt.TOOLTIP_KEY))
end

-- Paints the example's frames for the staged choices
local function PaintExample(frame, window)
  local _, hint, panel = ExampleNow(window)
  frame.Hint:SetText(hint or "")
  frame.Hint:SetShown(hint ~= nil)
  local V = Recollect.Purposes.Registry.Verdict
  local color = Recollect.UI.VerdictColors and Recollect.UI.VerdictColors[V.NEEDED] or U.Colors.SUCCESS_GREEN
  frame.Verdict:SetText(Recollect.Purposes.Registry.VerdictLabel[V.NEEDED] or "Needed")
  frame.Verdict:SetTextColor(color[1], color[2], color[3])
  frame.Verdict:SetShown(panel)
  frame.Answer:SetShown(panel)
  frame.Off:SetShown(not panel)
end

local function BuildAuditPanel(panel)
  panel:Checkbox{
    key = Opt.SHOW_TOOLTIP, label = "Show Recollect on item tooltips",
    description = "Adds a hint line and the audit panel to any item's tooltip. The details and waypoint keys need this on; a mouse click assigned to details keeps working.",
  }
  panel:Preview{
    height = 62, build = BuildExample, refresh = PaintExample,
    caption = function(window) return (ExampleNow(window)) end,
    dimWhen = function(get) return get(Opt.SHOW_TOOLTIP) == false end,
  }
  panel:Section("Show the panel when you", { icon = ICONS .. "INV_Misc_Key_05" })
  panel:Tiles{
    key = Opt.TOOLTIP_KEY, columns = 2, options = KEY_TILES,
    enabledWhen = function(get) return get(Opt.SHOW_TOOLTIP) ~= false end,
  }
end

-------------------------------------------------------------------------------
-- Recollect Audit: the sources and how current they are
-------------------------------------------------------------------------------
local function Freshness(kind, place)
  local ok, fresh = pcall(Recollect.Inventory.Snapshots.Freshness, kind)
  return Config.FreshnessLine(ok and fresh or nil, place)
end

local function OtherCharacters()
  local ok, list = pcall(Recollect.Inventory.Snapshots.OtherCharacters)
  return ok and type(list) == "table" and list or {}
end

local function OthersLine()
  local n = #OtherCharacters()
  if n == 0 then return "None saved yet: log in on another character once" end
  return n == 1 and "1 character saved" or ("%d characters saved"):format(n)
end

local function OthersTip()
  local names = {}
  for _, entry in ipairs(OtherCharacters()) do names[#names + 1] = tostring(entry.char.name or "a character") end
  local tip = "A tab for each of your other characters in the Recollect Audit, as they were when you last played them. Only checks that hold for the whole account run on their items."
  if #names > 0 then tip = tip .. "\n\nSaved: " .. table.concat(names, ", ") end
  return tip
end

local function BuildAuditList(panel)
  panel:Section("Include in the audit list", { icon = ICONS .. "INV_Misc_Bag_08",
    subtitle = "What the Recollect Audit (/rec, or the minimap button) lists" })
  panel:ToggleTiles{
    columns = 2,
    options = {
      { title = "Your bags", locked = true, icon = ICONS .. "INV_Misc_Bag_08", description = "Read live, every time",
        tooltip = "Your bags are always included, read live every time." },
      { key = Opt.SHOW_BANK, title = "Your bank", icon = ICONS .. "INV_Box_02",
        description = function() return Freshness(KIND_BANK, "your bank") end,
        tooltip = "This character's bank tabs, as they were when last read. Open your bank to bring them up to date." },
      { key = Opt.SHOW_WARBAND, title = "Warband bank", icon = ICONS .. "INV_Box_04",
        description = function() return Freshness(KIND_WARBAND, "the warband bank") end,
        tooltip = "The warband bank tabs, as they were when last read by any of your characters." },
      { key = Opt.LIST_OTHERS, title = "Other characters", icon = ICONS .. "Achievement_Character_Human_Male",
        description = OthersLine, tooltip = OthersTip },
    },
    description = "Other characters also adds their copies to an item's details window, under What you have.",
  }
  panel:Section("Minimap", { icon = ICONS .. "inv_misc_map02" })
  panel:Checkbox{
    key = Opt.SHOW_MINIMAP, label = "Show the minimap button",
    description = "Click it to open the Recollect Audit, right-click for these settings, drag it to move it. The addon compartment menu keeps Recollect either way.",
  }
end

-------------------------------------------------------------------------------
-- Keys and waypoints
-------------------------------------------------------------------------------
local function TooltipOn(get) return get(Opt.SHOW_TOOLTIP) ~= false end

local function TomTomLine()
  local ok, loaded = pcall(Recollect.UI.Waypoint.TomTomLoaded)
  return (ok and loaded) and "TomTom available" or "TomTom unavailable; using the game's map pin"
end

local function BuildKeys(panel)
  panel:Note{
    text = "The audit panel is off, so these keys do nothing. A mouse click assigned to details still works.",
    color = U.Colors.STATUS_GOLD,
    visibleWhen = function(get) return not TooltipOn(get) end,
  }
  panel:Section("Item details", { icon = ICONS .. "INV_Misc_Book_09" })
  panel:Checkbox{
    key = Opt.PIN_ENABLED, label = "Open an item's details with a key",
    description = "Opens everything Recollect knows about the item in its own window. The key isn't bound in combat. Clicking a row of the Recollect Audit opens it too.",
    enabledWhen = TooltipOn,
  }
  panel:Keybind{
    key = Opt.PIN_KEY, label = "Key", mouse = true, indent = KEY_INDENT,
    tooltip = "Click, then press the key with its modifiers (Alt+D by default), or hold Alt, Ctrl or Shift and click this button. Clear goes back to Alt+D.",
    description = "You can also assign a modified mouse click, which works on any item, even in combat. Shift+click, Ctrl+click and Shift+right-click stay the game's own.",
    enabledWhen = function(get) return TooltipOn(get) and get(Opt.PIN_ENABLED) ~= false end,
  }
  panel:Section("Waypoint", { icon = ICONS .. "UI_GreenFlag" })
  panel:Checkbox{
    key = Opt.WAYPOINT_ENABLED, label = "Set a waypoint with a key",
    description = "Puts a waypoint on the place the audit panel names: a vendor, a treasure or an NPC. Not in combat.",
    enabledWhen = TooltipOn,
  }
  panel:Keybind{
    key = Opt.WAYPOINT_KEY, label = "Key", indent = KEY_INDENT,
    tooltip = "Click, then press the key with its modifiers (Alt+W by default). Clear goes back to Alt+W.",
    enabledWhen = function(get) return TooltipOn(get) and get(Opt.WAYPOINT_ENABLED) ~= false end,
  }
  panel:Note{
    text = function(window)
      local key = Config.KeysClash(function(k) return window:Get(k) end)
      return key and ("Both keys are %s, so only the waypoint key works. Choose another key for one of them.")
        :format(U.FormatKeyText(key)) or ""
    end,
    color = U.Colors.WARNING_RED,
    visibleWhen = function(get) return Config.KeysClash(get) ~= nil end,
  }
  panel:Section("Waypoints go to", { icon = ICONS .. "INV_Misc_Map_01" })
  panel:Tiles{
    key = Opt.WAYPOINT_PROVIDER, columns = 2,
    options = {
      { value = "auto", title = "TomTom first", icon = ICONS .. "INV_Misc_Spyglass_02", description = TomTomLine,
        tooltip = "TomTom's arrow points the way when it's available; otherwise the game's map pin." },
      { value = "game", title = "Map pin only", icon = ICONS .. "inv_misc_map02", description = "On the map and the compass",
        tooltip = "Always the game's own map pin, even when TomTom is available." },
    },
    description = "Used by the waypoint key, and by the map buttons and right-click menu of the item details window.",
  }
end

-------------------------------------------------------------------------------
-- Curator (curator spec, "The separation boundary"): Recollect owns the
-- category and declares every row now; the rows read the curator provider
-- when they show, and bind to the curator's own config, which the
-- category's config function names only once curator mode has registered.
-- Without a provider the category says curator mode isn't in this build.
-------------------------------------------------------------------------------
local function CuratorProvider()
  return Recollect.CuratorProvider and Recollect.CuratorProvider() or nil
end

local function HasCurator()
  return CuratorProvider() ~= nil
end

-- What a player agrees to before opting in: the provider's four blocks
-- (Provider.CONSENT_BLOCKS; Cobanyte approved their words 2026-10-01)
local function ConsentBlocks()
  local provider = CuratorProvider()
  return provider and type(provider.CONSENT_BLOCKS) == "table" and provider.CONSENT_BLOCKS or {}
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

-- What the provider says now, never a staged choice
local function Ask(name)
  local provider = CuratorProvider()
  local fn = provider and provider[name]
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn)
  if ok then return value end
end

local function State()
  return Config.CuratorState(CuratorAvailable(), Ask("IsEnabled") == true, Ask("IsMember"))
end

local function BuildCurator(panel)
  panel:Note{ text = "Curator mode isn't part of this build.", visibleWhen = function() return not HasCurator() end }
  panel:BeginCard{
    title = "Curator mode", icon = Recollect.ICON,
    description = function() return (State()) end,
    dot = function() local _, dot = State() return dot end,
    visibleWhen = HasCurator,
  }
  -- outside the author's game region the page still explains curator mode,
  -- says why it's unavailable and grays its controls (Cobanyte, 2026-09-30)
  panel:Note{
    text = function()
      local provider = CuratorProvider()
      return provider and provider.REGION_TEXT or ""
    end,
    color = U.Colors.STATUS_GOLD,
    visibleWhen = function() return HasCurator() and not CuratorAvailable() end,
  }
  panel:Button{
    text = "Join the curator community", width = 210,
    description = "Prints the community's invite link in chat; click it there to open the game's join window.",
    visibleWhen = function()
      return HasCurator() and CuratorAvailable() and Ask("IsEnabled") == true and Ask("IsMember") == false
    end,
    onClick = function()
      local provider = CuratorProvider()
      if provider and provider.PrintJoinLink then provider.PrintJoinLink() end
    end,
  }
  panel:Button{
    text = "Open curator dashboard", width = 210,
    description = "Opens it now. It changes nothing here and applies nothing.",
    visibleWhen = function()
      local provider = CuratorProvider()
      return provider ~= nil and CuratorAvailable() and type(provider.OpenDashboard) == "function"
    end,
    onClick = function()
      local provider = CuratorProvider()
      if provider and provider.OpenDashboard then pcall(provider.OpenDashboard) end
    end,
  }
  panel:EndCard()
  panel:Checkbox{
    key = "curator_enabled", label = "Help build Recollect's database",
    description = "Optional, and off until you turn it on. Read what it records below first.",
    visibleWhen = HasCurator, enabledWhen = CuratorAvailable,
  }
  panel:Note{
    text = function(window) return Config.PendingCurator(window:Get("curator_enabled"), Ask("IsEnabled")) or "" end,
    color = U.Colors.INFO_BLUE,
    visibleWhen = function(get)
      return HasCurator() and Config.PendingCurator(get("curator_enabled"), Ask("IsEnabled")) ~= nil
    end,
  }
  panel:Checkbox{
    key = "curator_ask", label = "Ask me before each collection",
    description = "Otherwise collections run in the background, with a chat message when one starts and ends.",
    visibleWhen = function(get) return HasCurator() and get("curator_enabled") == true end,
    enabledWhen = CuratorAvailable,
  }
  panel:Section("What curator mode does", { icon = ICONS .. "INV_Misc_Spyglass_02", visibleWhen = HasCurator })
  -- What a player agrees to, in white, not a side note in the descriptions'
  -- gray (Cobanyte, 2026-09-26): four full-width blocks, read live because
  -- the provider registers after this window is built
  panel:Bullets{ items = ConsentBlocks, maxItems = 4, visibleWhen = HasCurator }
end

local window = UI.CreateSettingsWindow({
  name    = "RecollectOptionsWindow",
  title   = U.WrapColor(Recollect.BRAND_COLOR, "Recollect") .. " Settings",
  icon    = Recollect.ICON,
  config  = Config,
  size    = "compact",   -- 640 x 460, the smallest size that fits every page; a smaller saved size grows to it
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
    { key = "tooltip", label = "Audit panel", build = BuildAuditPanel },
    { key = "list", label = "Recollect Audit", build = BuildAuditList },
    { key = "keys", label = "Keys and waypoints", build = BuildKeys },
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
local PAGE_SETTINGS = "The settings live in the addon's own settings window."

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
