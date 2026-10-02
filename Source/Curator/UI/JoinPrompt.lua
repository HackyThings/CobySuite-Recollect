-------------------------------------------------------------------------------
-- Curator join prompt (Cobanyte, 2026-09-28; replaces D27's chat line)
--
-- A curator on a character that isn't in the Recollect Curators community
-- (an alt, usually) is asked once, in a window of its own (never
-- StaticPopupDialogs: adding to that Blizzard table taints unrelated secure
-- actions), whether to add this character. Join prints the invite link in
-- chat (the only join route, Provider.PrintJoinLink); No thanks, the X or
-- Escape keeps this character out, and it is never asked again. Findings
-- recorded here are kept either way: the store is the account's, so a
-- collection from any character in the community sends them.
--
-- The answer is kept per character GUID in RECOLLECT_CURATOR_DB.joinAsked
-- ("join" or "no"). Offered by Sharing's login notice, 10 seconds after
-- entering the world, and shown only when curator mode is on, the club list
-- reads, and a second look CONFIRM seconds later still finds this character
-- outside the community (the list can arrive late); in combat it waits for
-- combat to end. Client calls go through JoinPrompt.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host

local Join = {}
Curator.JoinPrompt = Join

Join.CONFIRM = 5   -- seconds between the two looks that call a character outside the community

Join.seams = {
  Clubs = function() return C_Club.GetSubscribedClubs() end,
  InCombat = function() return InCombatLockdown() end,
  After = function(delay, fn) C_Timer.After(delay, fn) end,
  Name = function() return UnitName("player") end,
}

Join.DECLINED = "This character won't be asked again. Findings you record here are still collected "
  .. "through your characters in the Recollect Curators community; /rec curator join adds this one later."

local dialog
local shownFor = nil     -- the GUID the open window asks for
local waiting = nil      -- a GUID to ask for once combat ends

local function Asked()
  local db = Curator.Main.DB()
  db.joinAsked = type(db.joinAsked) == "table" and db.joinAsked or {}
  return db.joinAsked
end

-- ShouldAsk(guid): curator mode on, not asked on this character before, the
-- club list readable, and this character in no community of that name
function Join.ShouldAsk(guid)
  if type(guid) ~= "string" or not Curator.Main.IsEnabled() then return false end
  if Asked()[guid] then return false end
  local ok, clubs = pcall(Join.seams.Clubs)
  if not ok or type(clubs) ~= "table" or (issecrettable and issecrettable(clubs)) then return false end
  Curator.Transport.Forget()
  return not Curator.Transport.IsMember()
end

-- Answer(guid, join): keeps the answer for this character; join prints the
-- invite link, anything else says it won't ask again
function Join.Answer(guid, join)
  if type(guid) == "string" then Asked()[guid] = join and "join" or "no" end
  shownFor = nil
  if dialog and dialog:IsShown() then dialog:Hide() end
  Host.Log("Curator join prompt: %s", join and "join (invite link printed)" or "declined; not asked again on this character")
  if join then
    Curator.Provider.PrintJoinLink()
  else
    Host.Print(Join.DECLINED)
  end
end

local function Build()
  if dialog or Join.seams.InCombat() then return end
  -- the suite's prompt with plain buttons: Escape and its X close it, which
  -- declines
  dialog = CobySuite_Recollect.UI.CreateClickPrompt({
    name = "RecollectCuratorJoinPrompt", title = "Add this character to Recollect Curators?", icon = Host.Icon(),
    width = 420,
    buttons = {
      { key = "Join", text = "Join", onClick = function() Join.Answer(shownFor, true) end },
      { key = "No", text = "No thanks", side = "right", onClick = function() Join.Answer(shownFor, false) end },
    },
    onHide = function()
      if shownFor then Join.Answer(shownFor, false) end   -- the X or Escape
    end,
  })
end

-- The body: the character's name when it reads
function Join.BodyText()
  local ok, name = pcall(Join.seams.Name)
  local who = (ok and type(name) == "string" and not Host.IsSecret(name)) and name or "This character"
  return ("You're a Recollect curator, but %s isn't in the Recollect Curators community. Add this character "
    .. "too?\n\nFindings you record here are kept either way, and your characters in the community send them. "
    .. "Join prints the community's invite link in chat."):format(who)
end

local function Show(guid)
  Build()
  if not dialog then
    waiting = guid
    return false
  end
  shownFor = guid
  -- sized to the text, which a long character name makes taller
  dialog:Ask(Join.BodyText())
  Host.Log("Curator join prompt shown: this character isn't in the community")
  return true
end

-- Offer(guid): asks this character once, after a second look; in combat, once
-- combat ends. Returns whether it will look again (false: nothing to ask)
function Join.Offer(guid)
  if not Join.ShouldAsk(guid) then return false end
  Join.seams.After(Join.CONFIRM, function()
    if not Join.ShouldAsk(guid) then return end
    if Join.seams.InCombat() then waiting = guid else Show(guid) end
  end)
  return true
end

function Join.IsShown()
  return dialog ~= nil and dialog:IsShown()
end

-- Combat ended: build the window if it isn't yet, and ask what waited
function Join.CombatEnded()
  Build()
  local guid = waiting
  waiting = nil
  if guid and Join.ShouldAsk(guid) then Show(guid) end
end

-- Tests: Close() closes the window as its X or Escape does; Window() is it;
-- Show(guid) asks for that character key now; Dismiss() closes it with no
-- answer recorded (a look at the window that must change nothing)
Join._test = {
  Close = function() if dialog then dialog:Hide() end end,
  Window = function() return dialog end,
  Show = function(guid) return Show(guid) end,
  Dismiss = function()
    shownFor = nil
    if dialog and dialog:IsShown() then dialog:Hide() end
  end,
}

Host.OnLoaded(function() C_Timer.After(0, Build) end)
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function() Join.CombatEnded() end)
