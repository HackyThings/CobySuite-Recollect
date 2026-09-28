local Utilities = Recollect.Utilities

---------------------------------------------------------------------------
-- Addon-specific: chat output (branded prefix)
---------------------------------------------------------------------------
Utilities.Message = CobySuite_Recollect.Chat.NewMessenger({
  prefix = "[Recollect]",
  color = Recollect.BRAND_COLOR,
})

---------------------------------------------------------------------------
-- IsSecret(value): a 12.x secret value, which addon code may not compare,
-- index with or store as a fact
---------------------------------------------------------------------------
function Utilities.IsSecret(value)
  return issecretvalue ~= nil and issecretvalue(value) and true or false
end

-- Looked up per call (not captured), so suites can script secret values
local function CheckResults(ok, ...)
  if not ok then return false, (...) end
  for i = 1, select("#", ...) do
    if Utilities.IsSecret((select(i, ...))) then return false, "secret value" end
  end
  return true, ...
end

---------------------------------------------------------------------------
-- Try(fn, ...): calls fn in pcall. Returns true and fn's results, or false
-- and why: the error, "missing function" when fn is not a function (an API
-- the client does not have), or "secret value" when any result is secret.
-- Every client read in Recollect goes through it, so a failed read is an
-- answer of its own (Unknown), never an error.
---------------------------------------------------------------------------
function Utilities.Try(fn, ...)
  if type(fn) ~= "function" then return false, "missing function" end
  return CheckResults(pcall(fn, ...))
end

---------------------------------------------------------------------------
-- IsPositiveID(value): a finite number above zero (item, quest and species
-- IDs; 0 and nil mean "none" in several APIs)
---------------------------------------------------------------------------
-- BucketRecord(tbl, key): the record for key in a bucketed string table, the
-- shipped data's form (tbl[key // 1024] is one string of "\30<key>\31<record>"
-- entries: thousands of records cost a few strings, not a string each), or nil
local BUCKET = 1024
function Utilities.BucketRecord(tbl, key)
  local bucket = tbl and tbl[math.floor(key / BUCKET)]
  if type(bucket) ~= "string" then return nil end
  local _, stop = bucket:find("\30" .. key .. "\31", 1, true)
  if not stop then return nil end
  local finish = bucket:find("\30", stop + 1, true)
  return bucket:sub(stop + 1, (finish or 0) - 1)
end

function Utilities.IsPositiveID(value)
  return CobySuite_Recollect.Utilities.IsFiniteNumber(value) and value > 0
end

---------------------------------------------------------------------------
-- Build(): the client build number as a string, "?" when unreadable
---------------------------------------------------------------------------
function Utilities.Build()
  local _, build = GetBuildInfo()
  return build and tostring(build) or "?"
end
