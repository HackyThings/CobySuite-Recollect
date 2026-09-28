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
    Host.Print(("Recollect's hidden curator channel is joined (/%d)."):format(index))
  elseif why == "member" then
    Host.Print("This character isn't in the Recollect Curators community: /rec curator join")
  elseif why == "slot" then
    Host.Print("Every chat channel slot is in use: leave one channel, then type /rec curator channel again.")
  else
    Host.Print("Joining Recollect's hidden curator channel; it takes a moment.")
  end
  return index
end

local function CountsText(tbl)
  local keys, parts = {}, {}
  for k in pairs(tbl or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. " " .. tostring(tbl[k]) end
  return #parts > 0 and table.concat(parts, ", ") or "none"
end

local function Ago(at)
  if type(at) ~= "number" then return "never" end
  local seconds = math.max(0, GetServerTime() - at)
  if seconds < 60 then return seconds .. " seconds ago" end
  if seconds < 3600 then return math.floor(seconds / 60) .. " minutes ago" end
  return math.floor(seconds / 3600) .. " hours ago"
end

-- Diagnose(): the lines /rec curator diag prints, for a curator whose client
-- doesn't answer the author (Cobanyte, 2026-09-28): what this client sees of
-- curator mode, the community, its channel, its members' roles, the curator
-- messages it got, and why the last one from the author went unanswered
function Provider.Diagnose()
  local main, T, M, S = Curator.Main, Curator.Transport, Curator.Membership, Curator.Sharing
  local versions = Host.Versions()
  local out = { ("Recollect curator check: addon %s, database %s%s"):format(tostring(versions.addon), tostring(versions.data),
    versions.ok and "" or " (the data files failed their check)") }
  out[#out + 1] = ("Curator mode: %s; answering as %s; curator ID %s"):format(main.IsEnabled() and "on" or "off",
    S and S.State() or "?", tostring(main.CuratorID()))
  local community = T.Community()
  out[#out + 1] = community and ("Community: found (club %s); hidden channel %s; whispers to the author go to %s"):format(
    tostring(community.clubId), T.ChannelIndex() and ("/" .. T.ChannelIndex()) or "not joined (type /rec curator channel)",
    T.RouteOf(Curator.Protocol.AUTHOR) or "nobody yet (until the author's first message)")
    or "Community: this character isn't in the Recollect Curators community"
  local authors, members = {}, 0
  for _, entry in ipairs(M.Roster()) do
    members = members + 1
    if entry.role == M.ROLE.OWNER or entry.role == M.ROLE.LEADER then
      authors[#authors + 1] = ("%s (%s, %s)"):format(entry.name, M.ROLE_NAMES[entry.role], entry.nameFrom or "?")
    end
  end
  out[#out + 1] = ("Members read %s: %d named%s; who may collect: %s"):format(Ago(M.ReadAt()), members,
    (M.unnamed or 0) > 0 and (", " .. M.unnamed .. " with no readable name") or "",
    #authors > 0 and table.concat(authors, ", ") or "nobody (so every collection request is ignored)")
  out[#out + 1] = "This character: " .. tostring(T.Self())
  local counts = T.Counts()
  out[#out + 1] = ("Curator messages this session: got %s; with the prefix by chat type %s; sent %s"):format(
    CountsText(counts.got), CountsText(counts.raw), CountsText(counts.sent))
  if S and S.lastHello then
    out[#out + 1] = ("Last presence check answered: from %s, %s"):format(S.lastHello.sender, Ago(S.lastHello.at))
  end
  local dropped = S and S.lastDropped
  out[#out + 1] = dropped and ("Last message not answered: %s from %s, %s: %s"):format(dropped.kind, tostring(dropped.sender),
    Ago(dropped.at), dropped.why) or "Last message not answered: none"
  if Curator.Ping then
    for _, line in ipairs(Curator.Ping.Lines()) do out[#out + 1] = line end
  end
  return out
end

-- /rec curator: the transfer window while a collection runs or waits for an
-- answer, else the status line; join, channel, cancel, diag, and console
-- (development)
function Provider.Slash(rest)
  local word = rest and rest:match("^%s*(%S+)") or ""
  word = word:lower()
  local Sharing = Curator.Sharing
  if word == "join" then
    Provider.PrintJoinLink()
  elseif word == "channel" then
    Provider.AddChannel()
  elseif word == "ping" and Curator.Ping then
    Curator.Ping.Start()
  elseif word == "pong" and Curator.Ping then
    if not Curator.Ping.Listen("asked with /rec curator pong") then Host.Print("Recollect: already listening for curator tests.") end
    Host.Print("Recollect: answering curator tests (the answers are automatic; this only joins the test channel).")
  elseif word == "diag" then
    for _, line in ipairs(Provider.Diagnose()) do
      Host.Print(line)
      Host.Log("Curator diag: %s", line)
    end
    Host.Print("The same lines are in the debug log: /rec debug, then Copy All.")
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
