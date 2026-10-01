-------------------------------------------------------------------------------
-- Curator.Provider: what Recollect's hooks ask the curator for (curator
-- spec, "The separation boundary"): the settings category's config, text
-- and join button, the guide section's body, /rec curator and /rec
-- feedback, the details window's Curator Flag button (D35), and the
-- dashboard's doorway for Recollect's Taint suite (OpenDashboard,
-- CloseDashboard, DashboardTabs).
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

-- IsEnabled(): whether curator mode is on (the details window offers the
-- curator program in the Curator Flag's place when it isn't)
function Provider.IsEnabled()
  return Curator.Main.IsEnabled() == true
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
  "Recollect notes where the game shows something its database gets wrong or is missing: a vendor price, a drop, a quest reward, where an NPC stands, and any item it knows nothing about, including ones in your bags and banks. It records game IDs and map positions, with your character's class, race, level, faction, professions, zone, War Mode, Chromie Time, the instance difficulty and, where it matters, quest progress and how a vendor regards you (a reputation discount changes its prices); never names, chat, gold, currencies, how many of anything you have, or anything else you carry.",
  "You can also flag an item from its details window, or send feedback with /rec feedback: those carry the words you type. Recollect's own errors are kept too, whether or not the game shows them. Only the author reads them.",
  "Recollect's author collects your findings in the background through the \"Recollect Curators\" community to improve the database. You'll see a chat message when a collection starts and ends; /rec curator shows what's waiting, what was sent, and a running collection you can cancel.",
  "Findings are sent only from characters in the community, whose members can see your character's name and zone. Your characters share one random curator ID made by Recollect (not your Blizzard account). Only Recollect's author sees it, so he can tell your characters belong to the same player.",
  "Your findings stay under 1 MB and are deleted once the author has saved them. Turning this off stops recording and offers to delete them.",
}

-- IsAvailable(): whether curator mode can run in this game region (Main.Available)
function Provider.IsAvailable()
  return Curator.Main.Available() == true
end

-- The words a player outside the author's region reads, in the settings and the guide
Provider.REGION_TEXT = "Curator mode isn't available in your game region. It works only in the Americas and Oceania "
  .. "region, where Recollect's author plays, because curators and the author have to reach each other in game to "
  .. "hand findings over. Everything else in Recollect works as usual."

-- One status line for the settings category
function Provider.Status()
  local main = Curator.Main
  if not main then return "" end
  if not main.Available() then return Provider.REGION_TEXT end
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
  if not Curator.Main.Available() then return { Provider.REGION_TEXT } end
  return {
    "Optional, and off until you turn it on in /rec settings, Curator.",
    table.concat({
      bullet .. "While you play, it notes where the game differs from Recollect's database (a vendor price, a drop, a quest reward) and items it knows nothing about, your bags and banks included",
      bullet .. "It records game IDs and positions, with your character's class, race, level, faction, professions, zone, War Mode, Chromie Time and instance difficulty; never names, chat, gold, currencies or how many of anything you have",
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
-- Whether the shipped data says nothing at all about an item (the items
-- with no information recorder's own rule, Host.Knows)
local function NoInfo(itemID)
  local recorder = Curator.Recorders and Curator.Recorders.NoInfo
  return recorder ~= nil and recorder.IsEmpty(itemID) == true
end

-- FlagState(itemID): nil unless curator mode is on; else { flagged, state
-- (the last entry's: "pending", "sent" or "delivered"), entries, atLimit,
-- noInfo (the shipped data says nothing about the item: the button reads
-- Request info) }
function Provider.FlagState(itemID)
  itemID = tonumber(itemID)
  if not (itemID and Curator.Main.IsEnabled() and Curator.Notes) then return nil end
  local flag = Curator.Notes.Flag(itemID)
  local last = flag.entries[#flag.entries]
  return { flagged = last ~= nil, state = last and last.state or nil, entries = #flag.entries, atLimit = flag.atLimit,
    noInfo = NoInfo(itemID) or nil }
end

-- OpenFlag(itemID): the flag window for an item; false when it can't open.
-- An item with no flag yet that the shipped data says nothing about opens
-- with the reason Missing info chosen (the curator may pick another).
function Provider.OpenFlag(itemID)
  if not (Curator.Main.IsEnabled() and Curator.FlagDialog) then return false end
  local id = tonumber(itemID)
  local reason = nil
  if id and Curator.Notes and #Curator.Notes.Flag(id).entries == 0 and NoInfo(id) then reason = "missing" end
  return Curator.FlagDialog.Open(itemID, reason)
end

-- OpenFeedback(): the feedback window, or a line saying how to turn curator mode on
function Provider.OpenFeedback()
  if not Curator.Main.Available() then
    Host.Print("Feedback is sent through curator mode. " .. Provider.REGION_TEXT)
    return false
  end
  if not Curator.Main.IsEnabled() then
    Host.Print("Feedback is sent through curator mode. Turn it on in /rec settings, Curator, then type /rec feedback again.")
    return false
  end
  return Curator.FeedbackDialog and Curator.FeedbackDialog.Open() or false
end

-------------------------------------------------------------------------------
-- The curator dashboard's doorway (Recollect's Taint suite opens it on each
-- tab through these; /rec curator toggles it)
-------------------------------------------------------------------------------
-- DashboardTabs(): the dashboard's tabs, in order
function Provider.DashboardTabs()
  local out = {}
  for i, tab in ipairs(Curator.DashboardWindow and Curator.DashboardWindow.TABS or {}) do out[i] = tab.key end
  return out
end

-- OpenDashboard(tab): shows the dashboard on that tab; false when it can't
-- open (in combat before it was built)
function Provider.OpenDashboard(tab)
  return Curator.DashboardWindow ~= nil and Curator.DashboardWindow.Open(tab) == true
end

function Provider.CloseDashboard()
  if Curator.DashboardWindow then Curator.DashboardWindow.Close() end
end

-------------------------------------------------------------------------------
-- /rec curator
-------------------------------------------------------------------------------

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
  local n, unit = seconds, "second"
  if seconds >= 3600 then
    n, unit = math.floor(seconds / 3600), "hour"
  elseif seconds >= 60 then
    n, unit = math.floor(seconds / 60), "minute"
  end
  return ("%d %s%s ago"):format(n, unit, n == 1 and "" or "s")
end

-- Diagnose(): the lines /rec curator diag prints, for a curator whose client
-- doesn't answer the author (Cobanyte, 2026-09-28): what this client sees of
-- curator mode, the community, where its whispers to the author go, the
-- members (how many are online, who may collect and whether they are), the
-- curator messages it got, and why the last one from the author went
-- unanswered
function Provider.Diagnose()
  local main, T, M, S = Curator.Main, Curator.Transport, Curator.Membership, Curator.Sharing
  local versions = Host.Versions()
  local out = { ("Recollect curator check: addon %s, database %s%s"):format(tostring(versions.addon), tostring(versions.data),
    versions.ok and "" or " (the data files failed their check)") }
  out[#out + 1] = ("Curator mode: %s; answering as %s; curator ID %s"):format(main.IsEnabled() and "on" or "off",
    S and S.State() or "?", tostring(main.CuratorID()))
  local community = T.Community()
  out[#out + 1] = community and ("Community: found (club %s); curator messages go by whisper; to the author: %s"):format(
    tostring(community.clubId), M.IsCollector(T.Self()) and "none needed (this is one of the author's characters)"
      or ("answers to the author's character that asks%s; anything else to every online collector character"):format(
        S and S.lastHello and (", last " .. tostring(S.lastHello.sender)) or ""))
    or "Community: this character isn't in the Recollect Curators community"
  local authors, members, online = {}, 0, 0
  for _, entry in ipairs(M.Roster()) do
    members = members + 1
    if entry.presence == "online" then online = online + 1 end
    -- who may collect: the author's own characters (Const.COLLECTORS) holding Owner or Leader
    if M.IsCollector(entry.name) then
      authors[#authors + 1] = ("%s (%s, %s), %s"):format(entry.name, M.ROLE_NAMES[entry.role], entry.nameFrom or "?",
        tostring(entry.presence or "?"))
    end
  end
  out[#out + 1] = ("Members read %s: %d named, %d online%s; who may collect: %s"):format(Ago(M.ReadAt()), members, online,
    (M.unnamed or 0) > 0 and (", " .. M.unnamed .. " with no readable name") or "",
    #authors > 0 and table.concat(authors, "; ") or "nobody (so every collection request is ignored)")
  out[#out + 1] = "This character: " .. tostring(T.Self())
  local counts = T.Counts()
  out[#out + 1] = ("Curator messages this session: got %s; with the prefix by chat type %s; sent %s"):format(
    CountsText(counts.got), CountsText(counts.raw), CountsText(counts.sent))
  if S and S.lastHello then
    out[#out + 1] = ("Last presence check answered: from %s, %s"):format(S.lastHello.sender, Ago(S.lastHello.at))
  end
  local dropped = S and S.lastDropped
  out[#out + 1] = dropped and ("Last message not answered: %s from %s, %s: %s"):format(
    Curator.Protocol.KIND_WORDS[dropped.kind] or tostring(dropped.kind), tostring(dropped.sender),
    Ago(dropped.at), dropped.why) or "Last message not answered: none"
  if Curator.Ping then
    for _, line in ipairs(Curator.Ping.Lines()) do out[#out + 1] = line end
  end
  return out
end

-- /rec curator: the curator dashboard (a toggle; its Overview shows a
-- running collection and a request waiting for an answer), or the status
-- line when the window can't open (in combat before it was built); status
-- prints that line, and join, ping or transport, pong, diag, cancel and
-- console (development) do what they always did. channel, which joined the
-- old hidden channel, only says there is none now (0.0.1c told curators to
-- type it).
function Provider.Slash(rest)
  if not Curator.Main.Available() then
    Host.Print(Provider.REGION_TEXT)
    return
  end
  local word = rest and rest:match("^%s*(%S+)") or ""
  word = word:lower()
  local Sharing = Curator.Sharing
  if word == "join" then
    Provider.PrintJoinLink()
  elseif word == "channel" then
    Host.Print("Curator messages go by whisper now, so there's no curator channel to join.")
  elseif (word == "ping" or word == "transport") and Curator.Ping then
    -- an optional "Name-Realm" after it: the player whose answers count
    Curator.Ping.Start(rest and rest:match("^%s*%S+%s+(%S+)"))
  elseif word == "pong" and Curator.Ping then
    -- a test session: this client answers other players' curator tests for Ping.LISTEN_FOR seconds
    local minutes = math.floor(Curator.Ping.LISTEN_FOR / 60)
    if Curator.Ping.Listen("asked with /rec curator pong") then
      Host.Print(("Answering other players' curator tests for the next %d minutes."):format(minutes))
    else
      Host.Print(("Already answering curator tests; that goes on for %d more minutes from now."):format(minutes))
    end
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
  elseif word == "status" then
    Host.Print(Provider.Status())
  elseif Curator.DashboardWindow and Curator.DashboardWindow.Toggle() then
    return
  elseif Sharing and (Sharing.Status() or Sharing.Prompt()) and Curator.TransferWindow then
    Curator.TransferWindow.Open()
  else
    Host.Print(Provider.Status())
  end
end

Host.RegisterProvider(Provider)
