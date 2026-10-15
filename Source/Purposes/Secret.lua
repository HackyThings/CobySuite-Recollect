-------------------------------------------------------------------------------
-- Purpose: an item used in one of the game's secrets (Facts.Secrets)
--
-- The verdict rule (the secrets design of Task #391, section 6), for an item
-- a secret's step takes, uses as a tool, makes, or lists among its
-- alternatives. Each use is judged on its own: every step that takes the
-- item or uses it as a tool, every "any N" step it is an alternative of,
-- and, for an item no step takes, the step that makes it (the overnight
-- review's finding 6); their answers combine by the precedence below. The
-- rewards a use serves are its own step's "fo" list, else every reward
-- (finding 5), and for each use:
--   * a weekly or daily step only informs (design 6.1 item 8; finding 7): a
--     soft Unknown that never holds another answer back
--   * every reward it serves collected: Can't tell, settled (category
--     finished: the band reads Probably done, and no Tip), or, for a secret
--     whose final can be done again, the optional use "repeat" (the band's
--     Your call, rule 51); never Purpose done, which would carry the Tip. A
--     rewardless secret's own completion predicate stands in for its rewards,
--     worded as the secret done: settled once, a repeatable one Can't tell
--     with no optional use, since no reward is promised
--   * a reward it serves can't be read yet: Can't tell, loading
--   * a reward it serves still missing, and the step not done: Needed, with
--     how many the step needs and how many you have; an alternative of an
--     "any N" step is Useful. Holding enough never ends the need: the
--     materials stay Needed until the step that takes them is done (review
--     finding 1 of the design)
--   * a reward missing and the step done: Can't tell, "step N of the secret
--     X is done", never settled (the copy may still be wanted; nothing
--     proves otherwise)
--   * a step whose completion can't be read: Can't tell, loading or
--     unreadable, before any input or alternative answer (finding 3);
--     another character's copy whose step only the logged-in character can be
--     asked about: Can't tell, category character
-- For each secret first: one no longer in the game (route flag x) is left
-- out; one for another faction, class or race is Can't tell naming it, and
-- one whose restriction the owner's record can't answer Can't tell,
-- category character, never Needed or Useful (rule 32, through
-- Relations.Applies; finding 4). An event route's tag never changes a
-- verdict (rule 32; the design review's finding 8).
-- The secrets data off with the item in Relations' manifest, or a record
-- that can't be read naming it: Can't tell, unreadable, so nothing reads
-- Outdated or done for it (finding 1).
-- A reward or the item teaching it is how to get it, never a use: those
-- items are not this check's (COMES FROM shows them).
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict

local Secret = {}
Recollect.Purposes.Secret = Secret

local function Facts() return Recollect.Facts.Secrets end

-- How often a recurring step comes back, in words
local RECURRING = { w = "week", d = "day" }

-- The secret in words: "a secret that gives Phoenix Wishwing (a pet you
-- don't have)", or "the secret Mind-Seeker, which gives ..." when its name
-- isn't its reward's; "a secret" while nothing can be named
function Secret.Phrase(secret, things, owner)
  local S = Facts()
  local name = S.Name(secret, owner)
  local reward = S.RewardWords(things)
  local first = things and things[1]
  local rewardName = first and Recollect.Facts.Buys.Name(first) or nil
  if reward and name and name ~= rewardName then return ("the secret %s, which gives %s"):format(name, reward) end
  if reward then return ("a secret that gives %s"):format(reward) end
  if name then return ("the secret %s"):format(name) end
  return "a secret"
end

-- The secret's link as a reason's words hold it: "[SECRET: Phoenix Wishwing]"
-- (UI.SecretPanel.PlainLink, which every painter turns into the one secret
-- link with its rainbow word; Task #411)
local function SecretWords(name)
  local Panel = Recollect.UI and Recollect.UI.SecretPanel
  if Panel and Panel.PlainLink then return Panel.PlainLink(name) end
  return ("[SECRET: %s]"):format(name)
end

-- The secret named for a reason, its reward's state beside it: "[SECRET:
-- Phoenix Wishwing] (a pet you don't have)", "[SECRET: Mind-Seeker], which
-- gives ...", "a secret that gives ..." or "a secret" (Task #407: a reason
-- names the secret and the step that needs the item; Task #411: as its link)
function Secret.Named(secret, things, owner)
  local S = Facts()
  local first = things and things[1]
  local name = S.Name(secret, owner) or (first and Recollect.Facts.Buys.Name(first)) or nil
  local reward = S.RewardWords(things)
  if reward and name and reward:sub(1, #name) == name then
    return SecretWords(name) .. reward:sub(#name + 1)
  end
  if reward and name then return ("%s, which gives %s"):format(SecretWords(name), reward) end
  if reward then return ("a secret that gives %s"):format(reward) end
  if name then return SecretWords(name) end
  return "a secret"
end

-- The secret alone as its link ("[SECRET: Phoenix Wishwing]"), for the band's short why, or nil
function Secret.ShortName(secret, things, owner)
  local first = things and things[1]
  local name = Facts().Name(secret, owner) or (first and Recollect.Facts.Buys.Name(first)) or nil
  return name and SecretWords(name) or nil
end

-- The item's uses in one secret, each { step, count, tool, unsure,
-- alternative }, and the step that names the item for the player (the one
-- that makes it, else the first that takes it, else the "any N" step)
local function UsesIn(secret, itemID)
  local consumers, producer, _, alternatives = Facts().Roles(secret, itemID)
  local uses = {}
  for _, c in ipairs(consumers) do
    uses[#uses + 1] = { step = c.step, count = c.count, tool = c.tool, unsure = c.unsure }
  end
  for _, step in ipairs(alternatives) do uses[#uses + 1] = { step = step, alternative = true } end
  if #uses == 0 and producer then
    local need = 1
    for _, ref in ipairs(producer.products) do
      if ref.id == itemID then need = ref.count end
    end
    uses[1] = { step = producer, count = need }
  end
  local shown = producer or (consumers[1] and consumers[1].step) or alternatives[1]
  return uses, shown
end

local function StepDone(step, phrase)
  return R.Unknown(("Step %s of %s is done; whether this copy is needed again isn't known"):format(step.label, phrase),
    ("Step %s of a secret is done"):format(step.label))
end

-- A use whose rewards are all collected
local function Collected(secret, used)
  if secret.freq == "repeat" then
    local result = R.Unknown(used .. "; it can be done again for another reward", "The secret's reward is collected")
    result.optional = "repeat"
    result.brief = "Its secret's reward is collected; it can be done again"
    return result
  end
  local result = R.Unknown(used .. "; this secret was its only use Recollect knows", "The secret's reward is collected")
  result.settled = true
  result.brief = "Its secret's reward is collected"
  return result
end

-- A use whose step isn't done (or that nothing the game reports shows done):
-- Useful for an alternative, else Needed with the counts, naming the step
-- that needs it ("Needed for step 1 of [SECRET: Phoenix Wishwing] (a pet
-- you don't have); you have 12 of 20"; the band: "Ingredient for step 1 of
-- [SECRET: Phoenix Wishwing]")
local function StillNeeded(secret, itemID, owner, use, things)
  local step = use.step
  local named, short = Secret.Named(secret, things, owner), Secret.ShortName(secret, things, owner)
  local of = short or "a secret"
  if use.alternative then
    return R.Result(V.USEFUL, ("One of the items for step %s of %s; any %d different ones count"):format(
      step.label, named, step.any.count), ("One of the choices for step %s of %s"):format(step.label, of))
  end
  local counts = ""
  if owner.isViewer ~= false then
    local held = Facts().Held(itemID)
    if held then counts = ("; you have %d of %d"):format(held, use.count or 1) end
  end
  local tool = ""
  if use.tool then tool = use.unsure and " (you use it)" or " (you use it; it isn't taken)" end
  local brief = use.tool and ("Used in step %s of %s"):format(step.label, of)
    or ("Ingredient for step %s of %s"):format(step.label, of)
  return R.Result(V.NEEDED, ("Needed for step %s of %s"):format(step.label, named) .. tool .. counts, brief)
end

-- One use's result, worded by the use's own step; states is Steps(secret, owner)
local function OneUse(secret, itemID, owner, use, states)
  local step = use.step
  local things, rewardState = Facts().Served(secret, step, owner)
  local phrase = Secret.Named(secret, things, owner)
  local recurring = RECURRING[step.freq]
  if recurring then
    local result = R.Info(("Used in step %s of %s, a step done every %s"):format(step.label, phrase, recurring))
    result.headline = ("Used in a secret's step done every %s"):format(recurring)
    return result
  end
  local used = ("Used in step %s of %s"):format(step.label, phrase)
  if rewardState == nil then
    -- no reward to read: the secret's own completion stands in, and promises
    -- no reward (settled once; a repeatable one still waits, never Your call)
    local done = Facts().Done(secret, owner)
    if done == true then
      if secret.freq == "repeat" then
        return R.Unknown(used .. "; the secret is done, and it can be done again", "The secret is done")
      end
      local result = R.Unknown(used .. "; the secret is done, and this was its only use Recollect knows", "The secret is done")
      result.settled = true
      result.brief = "Its secret is done"
      return result
    end
    if done == nil then return R.Unknown(used .. "; whether the secret is done can't be read yet", nil, "loading") end
  elseif rewardState == "unread" then
    return R.Unknown(("Used in step %s of a secret; whether you have its reward can't be read yet"):format(step.label),
      nil, "loading")
  elseif rewardState == "have" then
    return Collected(secret, used)
  end
  -- a reward still missing: the step decides, its completion read first
  local entry = states[step.label]
  local state = entry and entry.state
  if state == "done" then return StepDone(step, phrase) end
  if state == "unread" or state == nil then
    return R.Unknown(used .. "; whether that step is done can't be read yet", nil,
      (entry and entry.why == "unreadable") and "unreadable" or "loading")
  end
  if state == "character" then
    return R.Unknown(used .. "; whether that step is done can be read only on the character it's for", nil, "character")
  end
  return StillNeeded(secret, itemID, owner, use, things)
end

-- A secret that doesn't serve the owner: Can't tell naming why, or nil when
-- it does (rule 32)
local function NotForOwner(secret, applies, owner, shown)
  local phrase = Secret.Named(secret, (Facts().Rewards(secret, owner)), owner)
  local where = ("step %s of %s"):format(shown.label, phrase)
  if applies == nil then
    return R.Unknown(("Used in %s; whether it's for this character isn't recorded yet"):format(where), nil, "character")
  end
  local words = R.KindWords((R.Restrictions({ secret }, owner)))
  local headline = ("Used in a secret for another %s"):format(words)
  return R.Unknown(("Used in %s, for another %s"):format(where, words), headline)
end

-- The results of the item's uses in one secret, added to results; nothing
-- for a secret no longer in the game
local function SecretResults(secret, itemID, owner, results)
  local applies = Facts().Applies(secret, owner)
  if applies == "unavailable" then return end
  local uses, shown = UsesIn(secret, itemID)
  if not shown then return end
  if applies ~= true then
    results[#results + 1] = NotForOwner(secret, applies, owner, shown)
    return
  end
  local states = Facts().Steps(secret, owner)
  for _, use in ipairs(uses) do results[#results + 1] = OneUse(secret, itemID, owner, use, states) end
end

-- Needed wins, then Useful, then an Unknown still waiting (not settled, not
-- optional), then an optional use, then a settled one, then one that only
-- informs; within a rank, the first found
local function Rank(result)
  if result.verdict == V.NEEDED then return 1 end
  if result.verdict == V.USEFUL then return 2 end
  if result.soft then return 6 end
  if not result.settled and not result.optional then return 3 end
  if result.optional then return 4 end
  return 5
end

local function Best(results)
  local best, bestRank
  for _, result in ipairs(results) do
    local rank = Rank(result)
    if not best or rank < bestRank then best, bestRank = result, rank end
  end
  return best
end

-- Evaluate(itemID, owner): the check's result, or nil when the item is in no secret
function Secret.Evaluate(itemID, owner)
  local S = Facts()
  local status = S.Status()
  if status == "off" then
    if S.InManifest(itemID) then
      return R.Unknown("Used in a secret, whose steps can't be read: reinstall Recollect", nil, "unreadable")
    end
    return nil
  end
  if status ~= "ok" then return nil end
  local results, seen = {}, {}
  for _, broken in ipairs(S.Unreadable(itemID)) do
    results[#results + 1] = R.Unknown("Used in a secret whose steps can't be read: reinstall Recollect (" .. tostring(broken.why) .. ")", nil,
      "unreadable")
  end
  for _, entry in ipairs(S.Uses(itemID)) do
    if not seen[entry.sid] then
      seen[entry.sid] = true
      local secret = S.Get(entry.sid)
      if secret then SecretResults(secret, itemID, owner, results) end
    end
  end
  return Best(results)
end

-- Covered(itemID, owner): the rewards (as Facts.Buys reads them) this check
-- answers for on the item, so another check need not count them (Currency's
-- journal targets; review finding 2): those a use of a secret still in the
-- game, serving the owner, serves, a weekly or daily step's left out
function Secret.Covered(itemID, owner)
  local S = Facts()
  local covered = {}
  if S.Status() ~= "ok" then return covered end
  local seen = {}
  for _, entry in ipairs(S.Uses(itemID)) do
    local secret = not seen[entry.sid] and S.Get(entry.sid)
    seen[entry.sid] = true
    if secret and S.Applies(secret, owner) == true then
      for _, use in ipairs((UsesIn(secret, itemID))) do
        if not RECURRING[use.step.freq] then
          for _, thing in ipairs((S.Served(secret, use.step, owner))) do covered[#covered + 1] = thing end
        end
      end
    end
  end
  return covered
end

-- The owner a check's context stands for
function Secret.OwnerOf(ctx)
  return ctx.owner or { faction = ctx.playerFaction, isViewer = not ctx.otherCharacter, name = ctx.otherCharacter }
end

R.Register({
  key = "secret",
  -- runs on another character's copy too: what only the logged-in
  -- character can be asked reads category character (rule 30)
  accountWide = true,
  label = "Secret",
  order = 6,
  Evaluate = function(ctx)
    return Secret.Evaluate(ctx.stack.itemID, Secret.OwnerOf(ctx))
  end,
})
