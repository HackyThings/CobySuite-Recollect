-------------------------------------------------------------------------------
-- Curator.Errors: the Recollect errors a curator's client showed, kept as
-- notes for the author's next pull (Cobanyte, 2026-09-27: "any errors they
-- encountered we should send upon pull"; Curator.Notes.RecordError)
--
-- Only while curator mode is on, and never while a test run scripts the
-- client. Nothing here takes over the game's error handler (BugSack and
-- friends own that, and replacing it would taint): Blizzard's own error
-- frame receives every Lua error through AddLuaErrorHandler, shown or not
-- (Blizzard_ScriptErrorsFrame, always loaded; checked in the 12.1 source),
-- and a read-only hooksecurefunc on its DisplayMessageInternal sees each
-- one after it. With BugGrabber installed Blizzard's handler never runs, so
-- BugGrabber's public BugGrabber_BugGrabbed callback is used when it exists
-- (its shape, bug.message and bug.stack, is unverified here: each read is
-- guarded). The game's ADDON_ACTION_BLOCKED and ADDON_ACTION_FORBIDDEN
-- events that name Recollect are kept too.
--
-- An error is Recollect's when its message or stack names Recollect's
-- folder (the release build's private library lives inside it). Only the
-- message and the stack are kept, never the locals; a secret message is
-- skipped. Client reads go through Errors.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host

local Errors = {}
Curator.Errors = Errors

Errors.ADDON = "Recollect"

Errors.seams = {
  -- whether a test run scripts the client (the recorders' rule)
  Scripted = function() return Curator.Main.IsScripted() end,
}

-- Whether text names Recollect's folder ("Interface/AddOns/Recollect/...",
-- either slash, any case of "AddOns")
function Errors.IsOurs(text)
  if type(text) ~= "string" or Host.IsSecret(text) then return false end
  return text:find("[Aa][Dd][Dd][Oo][Nn][Ss][/\\]Recollect[/\\]") ~= nil
end

-- Keeping an error must never cause one that comes back here: an error
-- raised while one is being kept is dropped, never kept in turn
local busy = false

local function Keep(message, stack)
  if busy then return false end
  busy = true
  local ok, entry = pcall(Curator.Notes.RecordError, message, stack)
  busy = false
  return ok and entry ~= nil
end

-- Take(message, stack): keeps a Recollect error as a note; true when kept
function Errors.Take(message, stack)
  if busy or not Curator.Main.IsEnabled() then return false end
  local ok, scripted = pcall(Errors.seams.Scripted)
  if ok and scripted then return false end
  if Host.IsSecret(message) or Host.IsSecret(stack) then return false end
  if not (Errors.IsOurs(message) or Errors.IsOurs(stack)) then return false end
  return Keep(message, stack)
end

-- A blocked or forbidden action the game blamed on Recollect
function Errors.OnBlocked(event, addon, func)
  if busy or Host.IsSecret(addon) or addon ~= Errors.ADDON or not Curator.Main.IsEnabled() then return false end
  local ok, scripted = pcall(Errors.seams.Scripted)
  if ok and scripted then return false end
  local what = Host.IsSecret(func) and "?" or tostring(func or "?")
  return Keep(("%s: Recollect called the protected function %s"):format(event, what), "")
end

-- Blizzard's error frame, after it took an error. Its message types are
-- file-local there, so a warning (LUA_WARNING) is told apart by what it
-- lacks: every Lua error arrives with its stack, a warning with none.
local function OnDisplayed(_, message, _, stack)
  if type(stack) ~= "string" then return end
  pcall(Errors.Take, message, stack)
end
Errors.OnDisplayed = OnDisplayed

if ScriptErrorsFrame and ScriptErrorsFrame.DisplayMessageInternal then
  hooksecurefunc(ScriptErrorsFrame, "DisplayMessageInternal", OnDisplayed)
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_LOGIN" }) do
  pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    -- BugGrabber, when installed, has registered its handler by now
    local grabber = rawget(_G, "BugGrabber")
    if type(grabber) == "table" and type(grabber.RegisterCallback) == "function" then
      pcall(grabber.RegisterCallback, Errors, "BugGrabber_BugGrabbed", function(_, bug)
        if type(bug) == "table" then pcall(Errors.Take, bug.message, bug.stack) end
      end)
    end
    return
  end
  pcall(Errors.OnBlocked, event, ...)
end)
