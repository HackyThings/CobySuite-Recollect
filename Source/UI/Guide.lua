-------------------------------------------------------------------------------
-- UI.Guide: the feature guide (CobySuite.UI.CreateGuideWindow). /rec guide
-- and the list window's "?" button open it, and so does the first login of
-- a fresh install (UI/WhatsNew.lua). Built at load, so opening it in combat
-- creates nothing. Keep the text in step with the README.
--
-- The sections follow a new player's first session (Cobanyte, 2026-09-27):
-- the first thing to try, what the panel showed, what its verdict means,
-- then the list, one item's details, waypoints, settings, and last the
-- optional curator mode. Each body is short bullets that scan at a glance:
-- keys and commands in gold, the panel's block names in blue, verdicts in
-- their own colors, and a gray line for a caveat.
-------------------------------------------------------------------------------
local Guide = {}
Recollect.UI.Guide = Guide

local U = CobySuite_Recollect.Utilities
local V = Recollect.Purposes.Registry.Verdict
local LABELS = Recollect.Purposes.Registry.VerdictLabel
local ICONS = "Interface\\Icons\\"
local BULLET = "\226\128\162 "

-- A key or command, in the slash help's gold
local function Key(text) return U.WrapColor(U.Colors.HELP_COMMAND, text) end
-- One of the panel's block names, in the help's section blue
local function Block(text) return U.WrapColor(U.Colors.HELP_SECTION, text) end
-- A caveat, in gray
local function Note(text) return U.WrapColor(U.Colors.LABEL_GRAY, text) end
-- A small icon inside a line, cropped like the section icons
local function Icon(path) return "|T" .. path .. ":16:16:0:0:64:64:5:59:5:59|t" end
-- Bulleted lines, one paragraph
local function Bullets(lines)
  local out = {}
  for i, line in ipairs(lines) do out[i] = BULLET .. line end
  return table.concat(out, "\n")
end
-- A verdict's name in its list color, then what it means
local function Verdict(key, meaning)
  local color = Recollect.UI.VerdictColors and Recollect.UI.VerdictColors[key] or U.Colors.HIGHLIGHT_WHITE
  return U.WrapColor(color, LABELS[key]) .. ": " .. meaning
end

-- The keys as the player set them now, read each time the guide shows
-- (review 2026-09-30: the guide named the defaults whatever was chosen);
-- the default's words when a key is off or can't be read
local function KeyWords(get, default)
  local ok, key = pcall(get)
  if not ok or type(key) ~= "string" or key == "" then return default end
  local okT, text = pcall(CobySuite_Recollect.Utilities.FormatKeyText, key)
  return okT and type(text) == "string" and text ~= "" and text or default
end
-- the panel's key ("Alt"), and whether the panel always shows
local function PanelKey()
  local ok, key = pcall(Recollect.PanelKeyName)
  key = ok and key or nil
  return (key and key ~= "always") and key or "Alt", key == "always"
end
local function PinKey()
  return KeyWords(function() return Recollect.UI.DetailWindow.Key() end, "Alt+D")
end
local function WaypointKey()
  return KeyWords(function() return Recollect.UI.Waypoint.Key() end, "Alt+W")
end
-- How to pin with the details key: a key is pressed, a click chord used on the item
local function PinAction()
  local key = PinKey()
  if key:find("Click", 1, true) then return Key(key) .. " the item" end
  return "press " .. Key(key)
end
Guide.KeyWords = { Panel = PanelKey, Pin = PinKey, Waypoint = WaypointKey }

local SPYGLASS = ICONS .. "INV_Misc_Spyglass_02"
local LIST = ICONS .. "INV_Misc_Note_02"
local DETAILS = ICONS .. "INV_Misc_Note_01"

Guide.SECTIONS = {
  {
    key = "start",
    title = "Start here",
    icon = Recollect.ICON,
    summary = "New to Recollect? Try these three things first",
    body = function()
      local panel, always = PanelKey()
      local pin = PinKey()
      return {
        "Recollect tells you what each item you hold is for, and whether you still need it.",
        -- A step and its caption; the caption starts at the margin (no space
        -- indent, which can't line up with an icon in a proportional font)
        Key("1.") .. " " .. Icon(SPYGLASS) .. (always and " Point at any item in your bags\n"
          or (" Hold " .. Key(panel) .. " over any item in your bags\n"))
          .. Note("The audit panel opens beside its tooltip."),
        Key("2.") .. " " .. Icon(LIST) .. " Type " .. Key("/rec") .. ", or click the " .. Icon(Recollect.ICON) .. " minimap button\n"
          .. Note("The Recollect Audit lists everything you hold."),
        Key("3.") .. " " .. Icon(DETAILS) .. (pin:find("Click", 1, true) and (" " .. Key(pin) .. " any item\n")
          or (" Press " .. Key(pin) .. " while the panel shows\n"))
          .. Note("Everything about that one item, in its own window."),
        Note("Open your bank once, so Recollect can remember what's in it."),
      }
    end,
  },
  {
    key = "panel",
    title = "Reading the audit panel",
    icon = SPYGLASS,
    summary = "What you see beside the tooltip",
    body = function() return {
      Bullets({
        "The verdict, in color, and the reason for it",
        Block("USED FOR") .. ": its most important uses, and where you stand",
        Block("COMES FROM") .. ": where to get more",
        Block("GUIDE NOTES") .. ": a short note Recollect researched, for a few items no data explains",
        "A short summary: " .. PinAction() .. " for everything, in the item's details",
      }),
      Bullets({
        "Works on any item: bags, bank, chat links, vendors, loot, the auction house",
        "An item you don't hold gets the facts, but no verdict",
        "Gray lines are for another faction, class or race",
      }),
      Note("Prefer Shift or Ctrl, or the panel always on? Change it in /rec settings."),
    } end,
  },
  {
    key = "verdicts",
    title = "What the verdicts mean",
    icon = ICONS .. "INV_Misc_Bag_08",
    summary = "One colored word for every item",
    body = {
      table.concat({
        Verdict(V.NEEDED, "something unfinished still uses it"),
        Verdict(V.USE, "learn it, open it, or start its quest"),
        Verdict(V.USEFUL, "it still has a use, like something it buys you lack"),
        Verdict(V.UNKNOWN, "not confirmed yet; the panel says what would settle it"),
        Verdict(V.OUTDATED, "replaced, such as last season's gear, or an older expansion's potions and weapon oils"),
        Verdict(V.LOWER, "gear below what you wear"),
        Verdict(V.JUNK, "a gray item the game marks as junk"),
        Verdict(V.DONE, "every use Recollect checks is finished"),
      }, "\n"),
      Note("Recollect never decides for you: the details window's Still needed? answer is a suggestion with its reason, and a Tip may say an item is most likely safe to let go. Your call."),
    },
  },
  {
    key = "list",
    title = "The Recollect Audit",
    icon = LIST,
    summary = "Everything you hold, in one list",
    body = function() return {
      Bullets({
        "Open it: " .. Key("/rec") .. ", or the minimap button",
        "The top line counts your stacks by verdict",
        "Sort: click a column title",
        "Resize: drag a column divider, or double-click it to fit",
        "Search: the box at the top",
        "Filter: the funnel, by verdict, where it is, its uses, or why Can't tell",
        "Tabs along the bottom once another character is stored: My Items, All Characters, one per character",
        (select(2, PanelKey()) and "Point at a row for its panel" or ("Hold " .. Key((PanelKey())) .. " over a row for its panel"))
          .. "; click a row for its details",
      }),
      Note("With the bank closed, your bank and warband bank show as of your last visit; other characters as of their last login. "
        .. "Their items get only the checks that hold for the whole account. Turn them off in /rec settings."),
    } end,
    try = {
      { "/rec", "Open or close the Recollect Audit" },
    },
  },
  {
    key = "details",
    title = "Item details",
    icon = DETAILS,
    summary = "Pin it from the panel, or click a row in the list",
    body = {
      Bullets({
        "Overview: what it is, what it's for, how to get more, what you have",
        "Tabs: what it buys, quests, crafting, where it comes from, and more",
        "Every table sorts, searches and filters",
        "Names are links: hover for the tooltip, click like a chat link",
        Key("Alt-click") .. " an item to open it here; Back and Forward return",
        "Right-click a row for a menu: link it in chat, preview it, set a waypoint, or copy its name or Wowhead link",
        "The " .. Icon(ICONS .. "INV_Misc_Map_01") .. " Map button sets a waypoint",
      }),
      Note("The details key can be a click instead, such as Alt-click on any item: set it in /rec settings."),
    },
  },
  {
    key = "waypoint",
    title = "Waypoints",
    icon = ICONS .. "INV_Misc_Map_01",
    summary = "One key to go where the panel points",
    body = function() return {
      Bullets({
        "When the panel names a vendor, a treasure or an NPC, press " .. Key(WaypointKey()),
        "A waypoint appears on your map, or on TomTom's arrow when TomTom is installed",
      }),
      Note("Not during combat. Change the key in /rec settings."),
    } end,
  },
  {
    key = "settings",
    title = "Settings and commands",
    icon = ICONS .. "INV_Misc_Gear_01",
    summary = "Keys, what the list includes, and every command",
    body = {
      Bullets({
        "Keys: the panel key, the waypoint key, the details key",
        "The list: your bank, the warband bank, other characters",
        "The minimap button: show or hide it",
        "Waypoints: TomTom's arrow or the game's map pin",
      }),
      Note("Changes wait until you click Apply."),
    },
    try = {
      { "/rec settings", "Open the settings" },
      { "/rec guide", "Open this guide" },
      { "/rec changelog", "What changed in each version" },
      { "/rec help", "List every command" },
    },
  },
  {
    key = "curator",
    title = "Curator mode",
    icon = ICONS .. "INV_Misc_Book_09",
    summary = "Optional: help improve Recollect's database",
    body = function()
      local provider = Recollect.CuratorProvider and Recollect.CuratorProvider()
      if provider and provider.GuideBody then return provider.GuideBody() end
      return { "Curator mode isn't part of this build." }
    end,
    try = {
      { "/rec settings", "Turn it on or off (Curator)" },
      { "/rec curator", "The curator dashboard: what's waiting, what was sent" },
    },
  },
}

local window = CobySuite_Recollect.UI.CreateGuideWindow({
  name = "RecollectGuideWindow",
  title = "Recollect Guide",
  icon = Recollect.ICON,
  intro = "New here? Start with the first section. Click any heading to open or close it.",
  footer = "Open this guide any time with " .. Key("/rec guide"),
  sections = Guide.SECTIONS,
  persist = {
    svTable = function() return RECOLLECT_WINDOW_STATE end,
    key = "guideWindow",
  },
})

-- The window, for the suites
Guide._test = { window = window }

function Guide.Toggle()
  window:Toggle()
end

-- Shows the guide at its first section (the first login of a fresh
-- install, UI/WhatsNew.lua)
function Guide.Show()
  window:OpenSection(Guide.SECTIONS[1].key)
end
