-------------------------------------------------------------------------------
-- Purpose: an item tagged with a season ("Midnight Season 1", "The War
-- Within Season 3", "Battle for Azeroth Season 4"; Facts.Tooltip reads it);
-- contract rules 17 and 41
--
--   an older expansion's season (its EXPANSION_NAME<n>
--   below GetServerExpansionLevel)                      Outdated, naming it
--   the current expansion's season, the current one     no claim
--   a past season of the current expansion (its number
--   below the season the game shows now), for gear power:
--     gear, a crafting reagent, or an item whose Use
--     line speaks of item level or upgrades             Outdated, naming both
--                                                       seasons
--     unless it still makes gear whose appearance you
--     haven't collected (a recipe it is a reagent of,
--     or what it combines into)                         Useful for transmog
--                                                       only; Unknown when a
--                                                       look can't be read
--   a past season, anything else                        Unknown: whether it
--                                                       still serves isn't
--                                                       checked
--   which season is current can't be read, or the
--   game's two season numbers disagree                  Unknown
-- The current season is what the game's own UI shows: C_MythicPlus.
-- GetCurrentUIDisplaySeason (Blizzard_ChallengesUI titles the Mythic+ tab
-- "<expansion> Season <n>" with it) and C_PvP.GetUIDisplaySeason with
-- C_SeasonInfo.GetCurrentDisplaySeasonExpansion (PVPUtil.GetCurrentSeasonText
-- formats EXPANSION_SEASON_NAME, "%s Season %d", with them; when it answers
-- nothing, the server's expansion, as the Mythic+ title does). A season number
-- of 0 or nil is no season; when both are read they must agree on which
-- side of the tag they fall. ATT's patch the item was removed in
-- (Relations.RemovedIn), when the client is at or past it, is added as a fact.
-- Toys, mounts, pets, ensembles and weapon illusions are left to their own
-- checks (rule 24). A result for a season of this expansion that isn't the
-- current one carries supersedes: the checks that call an item current by
-- its expansion alone (Consumable, Use effect, Reagent), and Combine, whose
-- counts never weigh the season, then only inform (Verdicts.Settle), so "a
-- current-expansion consumable" never outranks the season. The word "Season"
-- is English, so this check runs on
-- English clients only.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber

local Season = {}
Recollect.Purposes.Season = Season

-- The season reads are among the calls the checks make (Purposes.client:
-- GetSeasonExpansion, GetMythicPlusSeason, GetPvPSeason, GetClientVersion,
-- GetItemEquipLoc)
local client = Recollect.Purposes.client

-- The checks whose Useful or Use now rests on the item being of the current
-- expansion, and Combine, whose counts never weigh the season; a season
-- result that isn't "current" makes them only inform
Season.SUPERSEDES = { consumable = true, useItem = true, reagent = true, combine = true }

-- Products checked for an appearance still to collect (a spark is a reagent
-- of about a hundred recipes), and item loads asked for per evaluation
-- (BA-11: never a burst of loads in one frame)
local MAX_PRODUCTS = 120
local MAX_LOADS = 8

-- The current season: { expansion, low, high } (low and high are the two
-- season numbers read, equal when they agree or only one answered), or nil.
-- The season's expansion is C_SeasonInfo's; when that answers nothing, the
-- server's expansion, as Blizzard_ChallengesUI titles the Mythic+ tab with
-- EXPANSION_NAME<GetExpansionLevel()> and the Mythic+ season alone
function Season.Current()
  local okX, expansion = Try(client.GetSeasonExpansion)
  if not okX or not IsFiniteNumber(expansion) then
    local okS, server = Try(client.GetServerExpansionLevel)
    if not okS or not IsFiniteNumber(server) then return nil end
    expansion = server
  end
  local low, high
  for _, read in ipairs({ client.GetMythicPlusSeason, client.GetPvPSeason }) do
    local ok, number = Try(read)
    if ok and IsFiniteNumber(number) and number > 0 then
      low = low and math.min(low, number) or number
      high = high and math.max(high, number) or number
    end
  end
  if not low then return nil end
  return { expansion = expansion, low = low, high = high }
end

-- The item's season tag and where it stands:
-- { state, name, number, current } with state "older" (an older
-- expansion's season), "current", "past", "later" (a number above the
-- season shown now), "disagree" (between the two numbers read) or "unread"
-- (the current season can't be read); nil for no tag, an expansion name not
-- recognized ("Warlords", "Trial of Style") or a client not in English.
-- Kept on ctx for the other checks (Consumable asks).
local function Read(ctx)
  local tip = ctx.Tooltip()
  if not tip or type(tip.seasonExpansion) ~= "string" then return nil end
  if not R.EnglishClient() then return nil end
  local okE, server = Try(client.GetServerExpansionLevel)
  if not okE or not IsFiniteNumber(server) then return nil end
  for expansionID = 0, server do
    local okName, name = Try(client.GetExpansionName, expansionID)
    if okName and name == tip.seasonExpansion then
      local tag = { name = name, number = tip.seasonNumber or 0 }
      if expansionID < server then
        tag.state = "older"
        return tag
      end
      local current = Season.Current()
      if not current or current.expansion ~= expansionID then
        tag.state = "unread"
      elseif tag.number < current.low then
        tag.state, tag.current = "past", current.high
      elseif tag.number > current.high then
        tag.state, tag.current = "later", current.high
      elseif current.low == current.high then
        tag.state, tag.current = "current", current.high
      else
        tag.state, tag.current = "disagree", current.high
      end
      return tag
    end
  end
  return nil
end

function Season.Of(ctx)
  if ctx.seasonTag == nil then ctx.seasonTag = Read(ctx) or false end
  return ctx.seasonTag or nil
end

-- "12.1.0" for 120100
function Season.PatchText(patch)
  return ("%d.%d.%d"):format(math.floor(patch / 10000), math.floor(patch / 100) % 100, patch % 100)
end

-- The client's version as a patch number (12.1.0 is 120100), or nil
local function ClientPatch()
  local ok, version = Try(client.GetClientVersion)
  if not ok or type(version) ~= "string" then return nil end
  local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)")
  if not major then return nil end
  return tonumber(major) * 10000 + tonumber(minor) * 100 + tonumber(patch)
end

-- The patch every way to obtain the item was removed in (AllTheThings, the
-- shipped data), when this client is at or past it; else nil
function Season.RemovedIn(itemID)
  local Relations = Recollect.Facts.Relations
  if type(Relations.RemovedIn) ~= "function" then return nil end   -- data without the table
  local ok, patch = Try(Relations.RemovedIn, itemID)
  if not ok or not IsFiniteNumber(patch) or patch <= 0 then return nil end
  local now = ClientPatch()
  if not now or now < patch then return nil end
  return patch
end

-- "; it can no longer be obtained (removed in patch 12.1.0)", or ""
function Season.RemovedWords(itemID)
  local patch = Season.RemovedIn(itemID)
  if not patch then return "" end
  return ("; it can no longer be obtained (removed in patch %s)"):format(Season.PatchText(patch))
end

-- What gear power the item is: "gear", "reagent", "upgrade" (its Use line
-- speaks of item level or upgrades), or nil
local function GearPower(ctx)
  local facts = ctx.facts
  if facts.classID == R.CLASS_WEAPON or facts.classID == R.CLASS_ARMOR then return "gear" end
  if facts.isCraftingReagent then return "reagent" end
  local tip = ctx.Tooltip()
  local use = tip and type(tip.useText) == "string" and tip.useText:lower()
  if use and (use:find("item level", 1, true) or use:find("upgrade", 1, true)) then return "upgrade" end
  return nil
end

local POWER_WORDS = { gear = "Gear from %s", reagent = "A crafting reagent from %s", upgrade = "An item-level upgrade from %s" }

-- Whether anything the item makes (a recipe it is a reagent of, what it
-- combines into) is gear whose appearance you haven't collected:
-- { found = product } for the first such one; else { checked, unread,
-- loading, uncollectable, more } (gear products whose look was read as
-- collected, whose look or tooltip couldn't be read or disagreed, whose
-- look is unread while its item data loads (asked for here, so a later
-- evaluation reads it), whose look this character can't collect, and
-- products past MAX_PRODUCTS), or nil while the appearance collection isn't
-- loaded
local function CraftedLook(itemID)
  if not Recollect.Facts.Ready.Transmog() then return nil end
  local Relations, Gear = Recollect.Facts.Relations, Recollect.Purposes.Gear
  local seen, looked, count, loads = {}, { checked = 0, unread = 0, loading = 0, uncollectable = 0, more = 0 }, 0, 0
  for _, relation in ipairs(Relations.For(itemID)) do
    local product
    if relation.kind == "reagentOf" then
      local recipe = Relations.Recipe(relation.id)
      product = recipe and recipe.product
    elseif relation.kind == "makes" then
      product = relation.id
    end
    if Recollect.Utilities.IsPositiveID(product) and not seen[product] then
      seen[product] = true
      count = count + 1
      if count > MAX_PRODUCTS then
        looked.more = looked.more + 1
      else
        local okLoc, equipLoc = Try(client.GetItemEquipLoc, product)
        if not okLoc or equipLoc == nil then
          -- nil: the client has no record of the product yet, so whether it
          -- is gear isn't known (review CORE-02); "" is a product that isn't
          looked.unread = looked.unread + 1
        elseif type(equipLoc) == "string" and Gear.SLOTS[equipLoc] then
          local look = Gear.Appearance(client, { facts = { equipLoc = equipLoc }, stack = { itemID = product } })
          if look == "missing" then
            -- the product's own tooltip must agree (rule 5)
            local tip = Recollect.Facts.Tooltip.FromItemID(product)
            if tip and tip.appearanceMissing == true then return { found = product } end
            looked.unread = looked.unread + 1
          elseif look == "uncollectable" then
            looked.uncollectable = looked.uncollectable + 1
          elseif look == nil then
            -- an item not cached yet may answer nothing: ask for it (Facts.Item
            -- fires InventoryChanged when it arrives), a few per evaluation
            if loads < MAX_LOADS then
              loads = loads + 1
              local _, why = Recollect.Facts.Item.Get(product)
              if why == "item data loading" then looked.loading = looked.loading + 1 else looked.unread = looked.unread + 1 end
            else
              looked.loading = looked.loading + 1
            end
          elseif look ~= "none" then   -- a ring or trinket has no look to collect
            looked.checked = looked.checked + 1
          end
        end
      end
    end
  end
  return looked
end

-- CraftedLook's answer, kept per item while every state it read is
-- (Facts.Buys.Stamp: until data changes or its memo's seconds pass, rule 9):
-- a spark row is read once, not at every redraw
local looks, looksStamp = {}, nil
local function KeptLook(itemID)
  local stamp = Recollect.Facts.Buys.Stamp()
  if stamp ~= looksStamp then looks, looksStamp = {}, stamp end
  local kept = looks[itemID]
  if kept == nil then
    kept = CraftedLook(itemID) or false
    looks[itemID] = kept
  end
  return kept or nil
end

-- The answer for a past season of the current expansion
local function PastSeason(ctx, tag)
  local label = ("%s Season %d"):format(tag.name, tag.number)
  local now = ("%s Season %d"):format(tag.name, tag.current)
  local removed = Season.RemovedWords(ctx.stack.itemID)
  local power = GearPower(ctx)
  if not power then
    -- The Use line tells an item-level upgrade; while it loads, say so (rule 14)
    local first = ("From %s, a past season (%s is current)"):format(label, now)
    if ctx.facts.spellLoading then return R.Unknown(first .. "; its Use line is still loading" .. removed, nil, "loading") end
    if ctx.facts.spellFailed then return R.Unknown(first .. "; its Use line can't be loaded" .. removed, nil, "unreadable") end
    return R.Unknown(first .. "; whether it still serves this season isn't checked" .. removed)
  end
  local facts = (POWER_WORDS[power]):format(label) .. (", a past season (%s is current)"):format(now) .. removed
  if power == "gear" then return R.Result(V.OUTDATED, facts) end   -- the Gear check answers for its look
  local looked = KeptLook(ctx.stack.itemID)
  if not looked then
    return R.Unknown(facts .. "; whether what it makes has an appearance you haven't collected can't be read yet", nil, "loading")
  end
  if looked.found then
    local name = Recollect.Facts.Item.Name(looked.found) or ("item " .. looked.found)
    return R.Result(V.USEFUL, ("Useful for transmog only: it makes %s, whose appearance you haven't collected; for gear, it is %s")
      :format(name, facts:sub(1, 1):lower() .. facts:sub(2)))
  end
  if looked.unread > 0 or looked.loading > 0 or looked.uncollectable > 0 or looked.more > 0 then
    local parts = {}
    if looked.unread > 0 then parts[#parts + 1] = ("%d can't be read"):format(looked.unread) end
    if looked.loading > 0 then parts[#parts + 1] = ("%d still loading"):format(looked.loading) end
    if looked.uncollectable > 0 then
      parts[#parts + 1] = ("%d %s this character can't collect"):format(looked.uncollectable,
        looked.uncollectable == 1 and "has a look" or "have looks")
    end
    if looked.more > 0 then
      parts[#parts + 1] = ("%d more %s checked"):format(looked.more, looked.more == 1 and "isn't" or "aren't")
    end
    local category = (looked.unread > 0 and "unreadable") or (looked.loading > 0 and "loading") or nil
    return R.Unknown(("%s; whether the gear it makes has an appearance you haven't collected isn't settled: %s"):format(facts,
      table.concat(parts, ", ")), nil, category)
  end
  if looked.checked > 0 then
    return R.Result(V.OUTDATED, ("%s; you have every appearance of the gear it makes (%d)"):format(facts, looked.checked))
  end
  return R.Result(V.OUTDATED, facts)
end

R.Register({
  key = "season",
  accountWide = true,   -- the same answer for any character's copy
  label = "Season",
  order = 69,
  Evaluate = function(ctx)
    local tag = Season.Of(ctx)
    if not tag then return nil end
    if tag.state == "current" then return nil end
    -- its collection check answers (rule 24), an older expansion's tag included
    if R.CollectionItem(ctx) == true then return nil end
    if tag.state == "older" then
      return R.Result(V.OUTDATED, ("From %s Season %d, a season of an older expansion"):format(tag.name, tag.number))
    end
    local result
    if tag.state == "past" then
      result = PastSeason(ctx, tag)
    elseif tag.state == "unread" then
      result = R.Unknown(("From %s Season %d; which season is current can't be read"):format(tag.name, tag.number))
    else
      result = R.Unknown(("From %s Season %d; the game's season numbers (Mythic+ and PvP) disagree on whether that season is current")
        :format(tag.name, tag.number), nil, "disagree")
      if tag.state == "later" then
        result.reason = ("From %s Season %d, but the game shows %s Season %d as current"):format(tag.name, tag.number,
          tag.name, tag.current)
        result.category = nil
      end
    end
    result.supersedes = Season.SUPERSEDES
    return result
  end,
})

-------------------------------------------------------------------------------
-- The season numbers may not be there when the first verdicts are read (a 0
-- or nil at login is unmeasured; the Lab's season probe records it). When
-- the game sends Mythic+ or PvP season data, and 5 and 30 seconds after
-- entering the world, a change in what Season.Current reads redraws the
-- verdicts (InventoryChanged); an unchanged read redraws nothing
-------------------------------------------------------------------------------
local notify = CobySuite_Recollect.Utilities.Coalesce(0.5, function()
  Recollect.EventBus:Fire(Recollect.Events.InventoryChanged, "season")
end)
local seams = {
  Notify = function() notify:Call() end,
  After = function(seconds, fn) C_Timer.After(seconds, fn) end,
}

-- What Season.Current reads, as one string ("none" when nothing is read)
function Season.Signature()
  local current = Season.Current()
  if not current then return "none" end
  return ("%s:%s:%s"):format(tostring(current.expansion), tostring(current.low), tostring(current.high))
end

local lastSignature = nil
local function OnSeasonData()
  local signature = Season.Signature()
  if signature == lastSignature then return end
  lastSignature = signature
  seams.Notify()
end

local SEASON_EVENTS = { "CHALLENGE_MODE_MAPS_UPDATE", "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", "PVP_RATED_STATS_UPDATE" }
local RECHECK_SECONDS = { 5, 30 }
local frame = CreateFrame("Frame")
local enteredOnce = false
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
for _, event in ipairs(SEASON_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_ENTERING_WORLD" then
    if enteredOnce then return end
    enteredOnce = true
    lastSignature = Season.Signature()   -- what the first verdicts read
    for _, seconds in ipairs(RECHECK_SECONDS) do seams.After(seconds, OnSeasonData) end
    return
  end
  OnSeasonData()
end)

Season._test = {
  seams = seams,
  OnSeasonData = OnSeasonData,
  -- Sets the last read aside (nil: none yet) and returns the function that puts it back
  Isolate = function(signature)
    local saved = lastSignature
    lastSignature = signature
    return function() lastSignature = saved end
  end,
}
