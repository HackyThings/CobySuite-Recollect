-------------------------------------------------------------------------------
-- UI.Guide: the feature guide (CobySuite.UI.CreateGuideWindow). /rec guide
-- and the list window's "?" button open it, and so does the first login of
-- a fresh install (UI/WhatsNew.lua). Built at load, so opening it in combat
-- creates nothing. Keep the text in step with the README.
--
-- The sections follow a new player's first session (Cobanyte, 2026-09-27):
-- the first thing to try, what the panel showed, what its verdict means,
-- then the list, one item's details, waypoints, settings, the optional
-- curator mode, and last the list of every addon (AddonsGuideSection). Each body is short bullets that scan at a glance:
-- keys and commands in gold, the panel's block names in blue, verdicts in
-- their own colors, and a gray line for a caveat.
-------------------------------------------------------------------------------
local Guide = {}
Recollect.UI.Guide = Guide

local V = Recollect.Purposes.Registry.Verdict
local LABELS = Recollect.Purposes.Registry.VerdictLabel
local ICONS = "Interface\\Icons\\"

-- The shared guide's text helpers: keys and commands in gold, the panel's
-- block names in blue, a caveat in gray, a small icon inside a line, and
-- bulleted lines
local T = CobySuite_Recollect.UI.GuideText
local Key, Block, Note, Icon, Bullets = T.Key, T.Block, T.Note, T.Icon, T.Bullets
-- A verdict's name in its list color, then what it means
local function Verdict(key, meaning)
  return T.Term(Recollect.UI.VerdictColors and Recollect.UI.VerdictColors[key], LABELS[key], meaning)
end

-- The keys as the player set them now, read each time the guide shows
-- (review 2026-09-30: the guide named the defaults whatever was chosen);
-- nil when a key is off, cleared or the same as another (Task #232: the
-- guide named the default for a key that did nothing); the default's words
-- when it can't be read. The shared guide lays every body out once at load,
-- before the saved settings exist: the defaults then, with no read (each one
-- logged a CONFIG warning at every login, Task #232)
local function SettingsLoaded() return type(RECOLLECT_CONFIG) == "table" end
local function KeyWords(get, default)
  if not SettingsLoaded() then return default end
  local ok, key = pcall(get)
  if not ok then return default end
  if type(key) ~= "string" or key == "" then return nil end
  local okT, text = pcall(CobySuite_Recollect.Utilities.FormatKeyText, key)
  return okT and type(text) == "string" and text ~= "" and text or default
end
-- the panel's key ("Alt"), or nil when the panel is off; and whether the
-- panel always shows
local function PanelKey()
  if not SettingsLoaded() then return "Alt", false end
  local ok, key = pcall(Recollect.PanelKeyName)
  if not ok then return "Alt", false end
  if key == nil then return nil, false end
  return key ~= "always" and key or "Alt", key == "always"
end
local TURN_ON_PANEL = "turn on the audit panel in /rec settings, Audit panel"
local TURN_ON_PIN = "turn on the details key in /rec settings, Keys and waypoints"
local function PinKey()
  return KeyWords(function() return Recollect.UI.DetailWindow.Key() end, "Alt+D")
end
local function WaypointKey()
  return KeyWords(function() return Recollect.UI.Waypoint.Key() end, "Alt+W")
end
-- How to pin with the details key: a key is pressed, a click chord used on
-- the item; nil when the key is off
local function PinAction()
  local key = PinKey()
  if not key then return nil end
  if key:find("click", 1, true) then return Key(key) .. " the item" end
  return "press " .. Key(key)
end

-- Just for fun and Your call, the details window's answers (not verdicts):
-- the name in the band's color, then what it means, as the band's hover
-- says it (DetailWindow.OPTIONAL's meanings, put together; Task #339)
local function Answer(text, neutral)
  local name, meaning = (text or ""):match("^([^:]+): (.+)$")
  if not name then return Note(text or "") end
  local color = not neutral and Recollect.UI.VerdictColors and Recollect.UI.VerdictColors[V.DONE] or nil
  return "In the details window, " .. T.Term(color, name, meaning)
end
local JUST_FOR_FUN = "Just for fun: nothing Recollect checks still needs it. It's a drink for roleplay or a "
  .. "novelty, such as a treat that changes a pet's size, a firework or a disguise, so keep it only if you'd like to."
local function ForFun() return Answer(JUST_FOR_FUN) end
local YOUR_CALL = "Your call: nothing Recollect checks needs it, and whether you still want what it does is up "
  .. "to you: something for pet battles, a token that only buys things you can still buy, an item only holiday or event "
  .. "NPCs take, an item for a secret whose reward you have and can earn again, or an item from an older expansion."
local function YourCall() return Answer(YOUR_CALL, true) end
Guide.YOUR_CALL = YOUR_CALL

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
        Key("1.") .. " " .. Icon(SPYGLASS) .. (not panel and (" First, " .. TURN_ON_PANEL .. "\n")
          or always and " Point at any item in your bags\n"
          or (" Hold " .. Key(panel) .. " over any item in your bags\n"))
          .. Note("The audit panel opens beside its tooltip."),
        Key("2.") .. " " .. Icon(LIST) .. " Type " .. Key("/rec") .. ", or click the " .. Icon(Recollect.ICON) .. " minimap button\n"
          .. Note("The Recollect Audit lists everything you hold."),
        Key("3.") .. " " .. Icon(DETAILS) .. (not pin and " Click a row of the Recollect Audit\n"
          or pin:find("click", 1, true) and (" " .. Key(pin) .. " any item\n")
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
        Block("Used for") .. ": its most important uses, and where you stand",
        Block("Comes from") .. ": where to get more",
        Block("Guide notes") .. ": a short note Recollect researched, for a few items no data explains",
        PinAction() and ("A short summary: " .. PinAction() .. " for everything, in the item's details")
          or ("A short summary; for everything, " .. TURN_ON_PIN .. ", or click the item's row in the Recollect Audit"),
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
      -- the band's Just for fun and Your call answers, as its hover words them
      -- (DetailWindow.OPTIONAL), named as the details window's answers, in
      -- their color (Task #232, Task #339)
      ForFun(),
      YourCall(),
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
        (not PanelKey() and "Click a row for its details"
          or ((select(2, PanelKey()) and "Point at a row for its panel" or ("Hold " .. Key((PanelKey())) .. " over a row for its panel"))
          .. "; click a row for its details")),
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
        "Overview: a summary of what it is and what it's for, how to get more, what you have",
        "Hover the Still needed? answer for why: every check Recollect ran and what it found",
        "Tabs: what it buys, quests, crafting, where it comes from, and more",
        "An item used in one of the game's secrets gets a Secret tab: the steps on the left, the chosen step's page "
          .. "on the right, and your own checkmarks for steps the game can't track",
        "Every table sorts, searches and filters",
        "Names are links: hover for the tooltip, click like a chat link",
        Key("Alt-click") .. " an item to open it here; Back and Forward return",
        "Right-click a row for a menu: link it in chat, preview it, set a waypoint, or copy its name or Wowhead link",
        "The " .. Icon(ICONS .. "INV_Misc_Map_01") .. " Map button sets a waypoint",
        "An achievement's button shows it in the game's achievement window. From the row menu's Show Achievement, "
          .. "with that window closed, one more click on " .. Key("Open Achievements") .. " lets the game open it "
          .. "itself, since an addon opening it can get your actions blocked",
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
        WaypointKey() and ("When the panel names a vendor, a treasure or an NPC, press " .. Key(WaypointKey()))
          or "When the panel names a vendor, a treasure or an NPC, a waypoint key takes you there: set one in /rec settings, Keys and waypoints",
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
      Note("Changes wait until you click Apply; Undo Edits drops them."),
    },
    try = {
      { "/rec settings", "Open the settings" },
      { "/rec guide", "Open this guide" },
      { "/rec changelog", "What changed in each version" },
      { "/rec reset windows", "Put every window back to its default place and size" },
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
      { "/rec curator pause", "Stop recording for this session; /rec curator resume or a reload starts it again" },
    },
  },
}
-- The last section in every addon's guide: the list of every addon by Cobanyte
Guide.SECTIONS[#Guide.SECTIONS + 1] = CobySuite_Recollect.UI.AddonsGuideSection(Recollect.AddonsList)

local window = CobySuite_Recollect.UI.CreateGuideWindow({
  name = "RecollectGuideWindow",
  title = CobySuite_Recollect.Utilities.WrapColor(Recollect.BRAND_COLOR, "Recollect") .. " Guide",
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
