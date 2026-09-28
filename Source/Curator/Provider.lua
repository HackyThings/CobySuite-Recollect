-------------------------------------------------------------------------------
-- Curator.Provider: what Recollect's hooks ask the curator for (curator
-- spec, "The separation boundary"): the settings category's config, text
-- and join button, the guide section's body, /rec curator and /rec
-- feedback, and the details window's Curator Flag button (D35).
-- Registered with Recollect through Host at load. Recollect reads these
-- functions only when its windows, guide or slash commands run, and only
-- plain values cross.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host

local Provider = {}
Curator.Provider = Provider

Provider.HOST_VERSION = Host.HOST_VERSION

-- The config the settings category binds its rows to
function Provider.Config()
  return Curator.Config
end

-------------------------------------------------------------------------------
-- Community membership (per character, D27)
-------------------------------------------------------------------------------
-- true when this character is in the curator community, false when not,
-- nil when the community list can't be read (clubs not loaded, lockdown)
function Provider.IsMember()
  if not (C_Club and C_Club.GetSubscribedClubs) then return nil end
  local ok, clubs = pcall(C_Club.GetSubscribedClubs)
  if not ok or type(clubs) ~= "table" or (issecrettable and issecrettable(clubs)) then return nil end
  local const = Curator.Const
  for _, club in ipairs(clubs) do
    if const.CLUB_ID and tostring(club.clubId) == tostring(const.CLUB_ID) then return true end
    if not const.CLUB_ID and not Host.IsSecret(club.name) and club.name == const.CLUB_NAME then return true end
  end
  return false
end

-- Prints the community's invite link in chat; a click on it opens Blizzard's
-- own join window, the only join route (curator spec, walkthrough 1)
function Provider.PrintJoinLink()
  local const = Curator.Const
  if not const.TICKET_ID then
    Host.Print("The curator community's invite link isn't set in this build yet.")
    return
  end
  local link = GetClubTicketLink(const.TICKET_ID, const.CLUB_NAME, Enum.ClubType.Character)
  Host.Print("Click to open the join window: " .. link)
end

-------------------------------------------------------------------------------
-- Text for the settings category and the guide
-------------------------------------------------------------------------------
Provider.SETTINGS_TEXT = {
  "Recollect notes where the game shows something its database gets wrong or is missing: a vendor price, a drop, a quest reward, where an NPC stands. It records game IDs and your character's class, race, level, faction, professions and, where it matters, quest progress; never names, chat, gold or your inventory.",
  "You can also flag an item from its details window, or send feedback with /rec feedback: those carry the words you type. Recollect errors your game shows are kept too. Only the author reads them.",
  "Recollect's author collects your findings in the background through the \"Recollect Curators\" community to improve the database. You'll see a chat message when a collection starts and ends; /rec curator shows or cancels it.",
  "Findings are sent only from characters in the community, whose members can see your character's name and zone. Your characters share one random curator ID made by Recollect (not your Blizzard account), so other members can tell they belong to the same player.",
  "Your findings stay under 1 MB and are deleted once collected. Turning this off stops recording and offers to delete them.",
}

-- One status line for the settings category
function Provider.Status()
  local main = Curator.Main
  if not main then return "" end
  local member = Provider.IsMember()
  local memberText = member == true and "this character is in the curator community"
    or member == false and "this character is not in the curator community yet"
    or "the community list can't be read right now"
  local versions = Host.Versions()
  return ("Curator mode is %s; %s. Database %s."):format(main.IsEnabled() and "on" or "off", memberText,
    tostring(versions.data))
end

-- The guide's curator section: the settings text in short bullets (the
-- settings page keeps the full wording, which the player reads before
-- turning it on)
function Provider.GuideBody()
  local bullet = "\226\128\162 "
  return {
    "Optional, and off until you turn it on in /rec settings, Curator.",
    table.concat({
      bullet .. "While you play, it notes where the game differs from Recollect's database: a vendor price, a drop, a quest reward",
      bullet .. "It records game IDs and your character's class, race, level, faction and professions; never names, chat, gold or your inventory",
      bullet .. "Flag an item from its details window (Curator Flag), or send feedback with /rec feedback; Recollect's errors go along too, and only the author reads them",
      bullet .. "The author collects the findings through the \"Recollect Curators\" community, whose members can see each other's names and zones",
      bullet .. "Turning it off stops recording and offers to delete your findings",
    }, "\n"),
    "The settings page has the full details.",
  }
end

-------------------------------------------------------------------------------
-- Notes: the details window's Curator Flag and /rec feedback (D35)
-------------------------------------------------------------------------------
-- FlagState(itemID): nil unless curator mode is on; else { flagged, state
-- (the last entry's: "pending", "sent" or "delivered"), entries, atLimit }
function Provider.FlagState(itemID)
  itemID = tonumber(itemID)
  if not (itemID and Curator.Main.IsEnabled() and Curator.Notes) then return nil end
  local flag = Curator.Notes.Flag(itemID)
  local last = flag.entries[#flag.entries]
  return { flagged = last ~= nil, state = last and last.state or nil, entries = #flag.entries, atLimit = flag.atLimit }
end

-- OpenFlag(itemID): the flag window for an item; false when it can't open
function Provider.OpenFlag(itemID)
  if not (Curator.Main.IsEnabled() and Curator.FlagDialog) then return false end
  return Curator.FlagDialog.Open(itemID)
end

-- OpenFeedback(): the feedback window, or a line saying how to turn curator mode on
function Provider.OpenFeedback()
  if not Curator.Main.IsEnabled() then
    Host.Print("Recollect: feedback is sent through curator mode. Turn it on in /rec settings, Curator, then type /rec feedback again.")
    return false
  end
  return Curator.FeedbackDialog and Curator.FeedbackDialog.Open() or false
end

-------------------------------------------------------------------------------
-- /rec curator
-------------------------------------------------------------------------------
-- /rec curator channel: puts the community's channel back in the list
function Provider.AddChannel()
  local index, why = Curator.Transport.AddChannel()
  if index then
    Host.Print(("The Recollect Curators channel is in your chat channels (/%d)."):format(index))
  elseif why == "member" then
    Host.Print("This character isn't in the Recollect Curators community: /rec curator join")
  elseif why == "slot" then
    Host.Print("Every chat channel slot is in use: leave one channel, then type /rec curator channel again.")
  else
    Host.Print("The Recollect Curators channel couldn't be added; try again in a moment.")
  end
  return index
end

-- /rec curator: the transfer window while a collection runs or waits for an
-- answer, else the status line; join, channel, cancel, and console
-- (development)
function Provider.Slash(rest)
  local word = rest and rest:match("^%s*(%S+)") or ""
  word = word:lower()
  local Sharing = Curator.Sharing
  if word == "join" then
    Provider.PrintJoinLink()
  elseif word == "channel" then
    Provider.AddChannel()
  elseif word == "cancel" then
    if not (Sharing and Sharing.Cancel()) then Host.Print("No curator collection is running.") end
  elseif word == "console" and Curator.Console and Curator.Console.Open then
    Curator.Console.Open()
  elseif Sharing and (Sharing.Status() or Sharing.Prompt()) and Curator.TransferWindow then
    Curator.TransferWindow.Open()
  else
    Host.Print(Provider.Status())
  end
end

Host.RegisterProvider(Provider)
