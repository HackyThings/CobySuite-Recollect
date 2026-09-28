-------------------------------------------------------------------------------
-- Purpose: a known use from Data.Uses (secrets, exchanges, collection parts)
--
-- The link from item to use is shipped data; whether the use is finished is
-- read live from its target:
--   mount        C_MountJournal.GetMountInfoByID, 11th return isCollected
--   toy          PlayerHasToy
--   pet          C_PetJournal.GetNumCollectedInfo(species) above 0
--   achievement  GetAchievementInfo, 4th return completed
--   quest        IsQuestFlaggedCompleted, or ...OnAccount for account = true
-- Target done: Purpose done ("you already have the reward"). Not done:
-- Needed, with how many of the item the use needs and how many the player
-- holds across the bags, bank and warband bank. A target that cannot be read
-- yet is Unknown. Entries without a confirmed line are skipped. When an item
-- has several uses, any one still needed makes it Needed.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber
local Ready = Recollect.Facts.Ready

local KnownUse = {}
Recollect.Purposes.KnownUse = KnownUse

local function Boolean(ok, value)
  if ok and type(value) == "boolean" then return value end
  return nil
end

local READERS = {}

function READERS.mount(client, id)
  if not Ready.Mounts() then return nil end
  local ok, _, _, _, _, _, _, _, _, _, _, isCollected = Try(client.GetMountInfoByID, id)
  return Boolean(ok, isCollected)
end

function READERS.toy(client, id)
  if not Ready.Toys() then return nil end
  return Boolean(Try(client.PlayerHasToy, id))
end

function READERS.pet(client, id)
  if not Ready.Pets() then return nil end
  local ok, collected = Try(client.GetNumCollectedInfo, id)
  if not ok or not IsFiniteNumber(collected) then return nil end
  return collected > 0
end

function READERS.achievement(client, id)
  local ok, _, _, _, completed = Try(client.GetAchievementInfo, id)
  return Boolean(ok, completed)
end

function READERS.quest(client, id, target)
  if not Ready.Quests() then return nil end
  local fn = target.account and client.IsQuestFlaggedCompletedOnAccount or client.IsQuestFlaggedCompleted
  return Boolean(Try(fn, id))
end

-- TargetDone(target): true, false, or nil when it cannot be read
function KnownUse.TargetDone(target)
  if type(target) ~= "table" then return nil end
  local client = Recollect.Purposes.client
  for kind, reader in pairs(READERS) do
    local id = target[kind]
    if id ~= nil then return reader(client, id, target) end
  end
  return nil
end

-- The confirmed entries that use itemID
function KnownUse.EntriesFor(itemID)
  local list = {}
  for _, entry in ipairs(Recollect.Data.Uses or {}) do
    if type(entry) == "table" and type(entry.parts) == "table" and entry.parts[itemID]
      and type(entry.confirmed) == "string" and entry.confirmed ~= "" then
      list[#list + 1] = entry
    end
  end
  return list
end

-- How each kind of use reads: what the item is part of, and what it is
-- still needed for. %s is the entry's name.
local KIND_WORDS = {
  secret = { part = "Part of the secret %s", needed = "Needed for the secret %s" },
  cache = { part = "One of the keys to %s", needed = "Needed to open %s" },
  exchange = { part = "One of the items that buy %s", needed = "Needed to buy %s" },
  collection = { part = "Part of the collection %s", needed = "Needed for the collection %s" },
}
local DEFAULT_WORDS = { part = "Part of %s", needed = "Needed for %s" }

local function Words(entry, which)
  local words = KIND_WORDS[entry.kind] or DEFAULT_WORDS
  return words[which]:format(entry.name or entry.key or "a known use")
end

local function Held(itemID)
  local ok, n = Try(Recollect.Purposes.client.GetItemCount, itemID, true, false, true, true)
  return ok and IsFiniteNumber(n) and n or nil
end

-- One entry's result for itemID
local function EntryResult(entry, itemID)
  local done = KnownUse.TargetDone(entry.target)
  if done == nil then return R.Unknown(Words(entry, "part") .. "; its progress can't be read yet") end
  if done then
    return R.Result(V.DONE, Words(entry, "part") .. "; you already have "
      .. (entry.reward or "its reward") .. ", so this copy is left over")
  end
  local need = tonumber(entry.parts[itemID]) or 1
  local held = Held(itemID)
  local counts = (" (needs %d)"):format(need)
  if held and held > need then
    counts = (" (needs %d, you have %d: %d more than it needs)"):format(need, held, held - need)
  elseif held then
    counts = (" (needs %d, you have %d)"):format(need, held)
  end
  return R.Result(V.NEEDED, Words(entry, "needed") .. counts)
end

R.Register({
  key = "knownUse",
  accountWide = true,   -- the same answer for any character's copy
  label = "Known use",
  order = 5,
  Evaluate = function(ctx)
    local entries = KnownUse.EntriesFor(ctx.stack.itemID)
    if #entries == 0 then return nil end
    local results = {}
    for _, entry in ipairs(entries) do results[#results + 1] = EntryResult(entry, ctx.stack.itemID) end
    -- Any use still needed wins, then any unreadable one, else every use is done
    for _, verdict in ipairs({ V.NEEDED, V.UNKNOWN }) do
      for _, result in ipairs(results) do
        if result.verdict == verdict then return result end
      end
    end
    local reasons = {}
    for _, result in ipairs(results) do reasons[#reasons + 1] = result.reason end
    return R.Result(V.DONE, table.concat(reasons, "; "))
  end,
})
