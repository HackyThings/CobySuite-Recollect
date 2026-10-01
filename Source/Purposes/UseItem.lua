-------------------------------------------------------------------------------
-- Purpose: a Miscellaneous item (class 15) with a Use effect
--
-- Many current items do their job from the bags: a teleport beacon, a
-- summoning stone, a flare. Nothing in the data names such a use, and the
-- panel never restates the Use line (Cobanyte, 2026-09-24: such an item
-- reads Useful when it can be used), so the check says only what it read:
--   a current-expansion item whose tooltip has a Use line
--   and that this character can use (CanUseItem)          Useful
--   the same from an older expansion                      informs only
--   the game says older, AllTheThings' added patch says
--   current (Facts.Item.Age "disagree")                   informs only,
--                                                         naming both
--   a spell still loading, one that failed to load, or a
--   spell read that failed                                Unknown (rule 14),
--                                                         so no other check's
--                                                         Outdated slips through
-- Only the subclasses no other check reads: Junk (0), Holiday (3) and Other
-- (4). Crafting reagents, companion pets and mounts go to their own checks
-- (Reagent, Pet, Mount); no check reads mount equipment (6) yet.
-- Toys and other collections are left to their checks (Registry.CollectionItem).
--
-- UseEffect (shared with Consumable, and for the panel): what an older
-- item's Use does, as facts read from the game, never its Use line copied:
--   Gains(ctx)     the currencies using it gives, with how many: the data's
--                  count (Relations "$<currency>x<n>", any language), else,
--                  on English clients, a number the Use line puts beside the
--                  currency's live name after a verb of gaining ("generate
--                  48 Cataloged Research", "increase your Dragon Isles
--                  Herbalism Knowledge by 1", "Grants 500 reputation with the
--                  Dream Wardens"); a currency only named ("Costs 100", "Turn
--                  5 ... into", "the maximum amount of ... by 100") is no gain
--   Where(text)    where the Use works, from the Use line's own words ("Only
--                  usable in Draenor", "Can only be used on the Broken
--                  Isles", "Only works during the Day of the Dead"; English
--                  clients): a place or event that starts with a capital
--   Describe(ctx)  both, worded for a reason, with a headline when it gives
--                  something ("Using it gives 48 Cataloged Research")
-- Whether a place or event is still in the game is read nowhere, so neither
-- ever makes an item Outdated.
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber

local UseEffect = {}
Recollect.Purposes.UseEffect = UseEffect

-- "from Shadowlands (added in patch 9.1.0)", or "from Dragonflight" when the
-- game's own expansion stands
function UseEffect.From(expansion, source, patch)
  local text = "from " .. R.ExpansionName(expansion)
  local patchText = source == "added" and Recollect.Facts.Item.PatchText(patch)
  if patchText then text = ("%s (added in patch %s)"):format(text, patchText) end
  return text
end

-- For Facts.Item.Age's "disagree": "the game tags it as from Dragonflight,
-- but it was added in patch 12.0.7 (Midnight)"
function UseEffect.Disagree(facts, expansion, patch)
  return ("the game tags it as from %s, but it was added in patch %s (%s)"):format(R.ExpansionName(facts.expansionID),
    tostring(Recollect.Facts.Item.PatchText(patch)), R.ExpansionName(expansion))
end

-- The Use line as plain words: no color codes, textures ("Gain 25
-- |T...|t Garrison Resources") or line breaks
local function Plain(text)
  if type(text) ~= "string" then return nil end
  local plain = Recollect.Facts.Tooltip.StripColors(text)
  plain = plain:gsub("|T.-|t", ""):gsub("|n", " "):gsub("%s+", " ")
  return plain
end

-------------------------------------------------------------------------------
-- Where it works
-------------------------------------------------------------------------------
-- The lead words, lowercase, and the preposition kept for the wording. "works
-- on" is left out: its object is a target ("Only works on heirlooms", "on
-- Beasts, Humanoids and Critters"), not a place; so is a bare "usable on"
-- ("Usable on most rare creatures in Undermine")
local WHERE = {}
for _, lead in ipairs({ "only usable", "usable only", "can only be used", "may only be used", "only works", "only functions",
  "must be", "usable" }) do
  for _, prep in ipairs({ "in", "within", "inside", "at", "on", "during" }) do
    local target = prep == "on" and (lead == "only works" or lead == "only functions" or lead == "must be" or lead == "usable")
    if not target then WHERE[#WHERE + 1] = { text = lead .. " " .. prep .. " ", prep = prep } end
  end
end
local MAX_PLACE = 80

-- The place, cut where its clause ends: a full stop, a semicolon or a
-- parenthesis, ", <lowercase>" (", located in"; ", and flags the user") but
-- not ", and <Capital>" (a list of zones), " to <lowercase>" ("to activate")
local function Clause(rest)
  local place = rest:match("^[^%.;%(|]*")
  local cut = #place + 1
  local from = 1
  while true do
    local i, _, word, nextChar = place:find(", (%a+) ?(.?)", from)
    if not i then break end
    local list = (word == "and" or word == "or") and nextChar:find("^%u") ~= nil
    if not word:find("^%u") and not list then
      cut = math.min(cut, i)
      break
    end
    from = i + 1
  end
  local to = place:find(" to %l")
  if to then cut = math.min(cut, to) end
  place = place:sub(1, cut - 1):gsub("%s+$", "")
  return place
end

-- Where(text): the preposition ("in", "on", "during", ...) and the place or
-- event a Use line says it works in, or nil (English clients only). A lead
-- inside a longer word ("unusable in") or after "not" ("not usable in
-- Arenas") says where it doesn't work, and is passed over
function UseEffect.Where(text)
  local plain = Plain(text)
  if not plain or not R.EnglishClient() then return nil end
  local low = plain:lower()
  for _, lead in ipairs(WHERE) do
    local from = 1
    while true do
      local i, j = low:find(lead.text, from, true)
      if not i then break end
      local before = low:sub(1, i - 1)
      if not before:find("%a$") and not before:find("not $") and not before:find("never $") then
        local rest = plain:sub(j + 1)
        -- "on the Broken Isles", "in the Shadowlands": the word after "the" leads
        local body = rest:match("^[Tt]he (.*)$") or rest
        if body:find("^%u") or body:find("^%d") then
          local place = Clause(rest)
          if place ~= "" and #place <= MAX_PLACE then return lead.prep, place end
        end
      end
      from = j + 1
    end
  end
  return nil
end

-------------------------------------------------------------------------------
-- What using it gives
-------------------------------------------------------------------------------
local GAIN_VERBS = { gain = true, gains = true, generate = true, generates = true, generating = true, grant = true,
  grants = true, award = true, awards = true, earn = true, earns = true, receive = true, receives = true }

local function Number(text)
  return tonumber((text:gsub(",", "")))
end

-- The count a Use line gives of a currency named name, or nil: one count
-- only (two different numbers give none). English words.
function UseEffect.GainCount(text, name)
  local plain = Plain(text)
  if not plain or type(name) ~= "string" or name == "" then return nil end
  local low, lowName = plain:lower(), name:lower()
  local count, from = nil, 1
  while true do
    local i, j = low:find(lowName, from, true)
    if not i then break end
    local before, after = low:sub(1, i - 1), low:sub(j + 1)
    local found
    -- The whole name only ("Honor", never inside "Honorbound")
    if before:find("[%w']$") or after:find("^[%w]") then before, after = "", "" end
    -- "<gain verb> N <name>"; "<gain verb> (you) N reputation with (the) <name>"
    local verb, n = before:match("(%a+) (%d[%d,]*) $")
    if n and GAIN_VERBS[verb] then found = n end
    if not found then
      verb, n = before:match("(%a+) (%d[%d,]*) reputation with $")
      if not verb then verb, n = before:match("(%a+) (%d[%d,]*) reputation with the $") end
      if n and (GAIN_VERBS[verb] or verb == "you") then found = n end
    end
    -- "increase(s) your <name> by N"; "reputation with (the) <name> by N"
    if not found then
      local by = after:match("^ by (%d[%d,]*)")
      if by and (before:find("increases? your $") or before:find("reputation with $") or before:find("reputation with the $")) then
        found = by
      end
    end
    if found then
      local value = Number(found)
      if count and value ~= count then return nil end
      count = value
    end
    from = j + 1
  end
  return count
end

-- Gains(ctx): { { name, count, quantity, max, reputation } },
-- only currencies whose count is known; an empty list when none is
function UseEffect.Gains(ctx)
  local out = {}
  local ok, relations = pcall(Recollect.Facts.Relations.Of, ctx.stack.itemID, "currency")
  if not ok or type(relations) ~= "table" then return out end
  local client = Recollect.Purposes.client
  local tip, english = nil, nil
  for _, relation in ipairs(relations) do
    if Recollect.Facts.Relations.Applies(relation) ~= "unavailable" then
      local okInfo, info = Try(client.GetCurrencyInfo, relation.id)
      if okInfo and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
        local count = relation.count and relation.count > 0 and relation.count or nil
        if not count then
          if english == nil then english = R.EnglishClient() end
          if english then
            tip = tip or ctx.Tooltip() or false
            count = tip and UseEffect.GainCount(tip.useText, info.name) or nil
          end
        end
        if count then
          local okFaction, factionID = Try(client.GetFactionGrantedByCurrency, relation.id)
          out[#out + 1] = { name = info.name, count = count,
            quantity = IsFiniteNumber(info.quantity) and info.quantity or nil,
            max = IsFiniteNumber(info.maxQuantity) and info.maxQuantity > 0 and info.maxQuantity or nil,
            reputation = okFaction and Recollect.Utilities.IsPositiveID(factionID) or false }
        end
      end
    end
  end
  return out
end

-- "48 Cataloged Research", "500 reputation with Dream Wardens"
local function GainWords(gain)
  if gain.reputation then return ("%d reputation with %s"):format(gain.count, gain.name) end
  return ("%d %s"):format(gain.count, gain.name)
end

-- " (you have 0)", " (you have 300, the most you can hold)"; reputation holds nothing
local function HeldWords(gain)
  if gain.reputation or not gain.quantity then return "" end
  if gain.max and gain.quantity >= gain.max then
    return (" (you have %d, the most you can hold)"):format(gain.quantity)
  end
  return (" (you have %d)"):format(gain.quantity)
end

local MAX_GAINS = 3

-- Describe(ctx): { text, headline } or nil when nothing is known. text is for
-- a reason, after its first clause ("; using it gives 48 Cataloged Research
-- (you have 0); it works only in Korthia"); headline is set when it gives
-- something
function UseEffect.Describe(ctx)
  local gains = UseEffect.Gains(ctx)
  local tip = ctx.Tooltip()
  local prep, place = nil, nil
  if tip and type(tip.useText) == "string" then prep, place = UseEffect.Where(tip.useText) end
  if #gains == 0 and not place then return nil end
  local parts, heads = {}, {}
  for i, gain in ipairs(gains) do
    if i > MAX_GAINS then break end
    parts[#parts + 1] = GainWords(gain) .. HeldWords(gain)
    heads[#heads + 1] = GainWords(gain)
  end
  local text, headline = "", nil
  if #parts > 0 then
    text = "; using it gives " .. table.concat(parts, " and ")
    headline = "Using it gives " .. table.concat(heads, " and ")
  end
  if place then text = ("%s; it works only %s %s"):format(text, prep, place) end
  return { text = text, headline = headline }
end

-- An informing result: reason, what the Use does (Describe's result, or
-- nil), then tail; led by what it gives
function UseEffect.Info(reason, described, tail)
  local result = R.Info(reason .. (described and described.text or "") .. (tail or ""))
  if described and described.headline then result.headline = described.headline end
  return result
end

-- Enum.ItemMiscellaneousSubclass (12.1): Junk 0, Holiday 3, Other 4
local Sub = Enum and Enum.ItemMiscellaneousSubclass or {}
local SUBCLASSES = { [Sub.Junk or 0] = true, [Sub.Holiday or 3] = true, [Sub.Other or 4] = true }

R.Register({
  key = "useItem",
  label = "Use effect",
  order = 68,
  Evaluate = function(ctx)
    local facts = ctx.facts
    if facts.classID ~= R.CLASS_MISC or not SUBCLASSES[facts.subclassID] then return nil end
    if facts.hasSpell == false then return nil end   -- nothing to use
    local collection = R.CollectionItem(ctx)
    if collection == true then return nil end
    if collection == "unreadable" then
      return R.Unknown("Whether it's a toy, mount or pet can't be read", nil, "unreadable")
    end
    if facts.hasSpell == nil then return R.Unknown("Whether it has a Use effect can't be read", nil, "unreadable") end
    if facts.spellLoading then return R.Unknown("Its Use line is still loading", nil, "loading") end
    if facts.spellFailed then return R.Unknown("Its Use line can't be loaded", nil, "unreadable") end
    local client = Recollect.Purposes.client
    local okE, current = Try(client.GetServerExpansionLevel)
    local age, expansion, source, patch = nil, nil, nil, nil
    if okE then age, expansion, source, patch = Recollect.Facts.Item.Age(facts, ctx.stack.itemID, current) end
    if not age then
      return R.Unknown("An item with a Use effect; its expansion can't be read")
    end
    if age == "older" then
      return UseEffect.Info(("An item with a Use effect, %s, an older expansion"):format(UseEffect.From(expansion, source, patch)),
        UseEffect.Describe(ctx))
    end
    if age == "disagree" then
      return UseEffect.Info("An item with a Use effect; " .. UseEffect.Disagree(facts, expansion, patch)
        .. ", so whether it's of the current expansion can't be told", UseEffect.Describe(ctx))
    end
    local tip = ctx.Tooltip()
    if not tip then return R.Unknown("A current-expansion item with a Use effect; its tooltip can't be read", nil, "unreadable") end
    if not tip.useText then return R.Unknown("It has a spell, but the tooltip read shows no Use line") end
    local okUse, canUse = Try(client.CanUseItem, ctx.stack.itemID)
    if okUse and canUse == true then return R.Result(V.USEFUL, "A current-expansion item you can use") end
    return R.Unknown("A current-expansion item with a Use effect, but this character can't use it yet")
  end,
})
