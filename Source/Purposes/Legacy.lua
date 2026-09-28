-------------------------------------------------------------------------------
-- Purpose: an item of an older expansion's system (legendary memories, Heart
-- of Azeroth essences, Corruption), saying what the system was and whether
-- it still does anything
--
-- Legacy.System(itemID, facts, tip) names the system from the item's Use
-- text, read on English clients only (Registry.EnglishClient): the tooltip's
-- Use line when tip is given, else the item's spell description
-- (C_Item.GetItemSpell's 2nd return, C_Spell.GetSpellDescription, which is
-- empty until the spell's data loads; both in Blizzard's generated docs,
-- 12.1.0). It returns { key, name, what, expansion, still (true, false, or
-- nil when not known), stillWords, power (a memory's power name), learn (the
-- item teaches something the tooltip marks "Already known") } or nil: no
-- system, another language, or the text not loaded yet.
--
-- still comes from pages the site rules allow, cited in stillWords:
--   memory      Shadowlands legendary powers still work, but only in
--               Shadowlands content (Blizzard Watch, 2022-10-19, "What's
--               happening to tier sets bonuses and Legendaries in the
--               Dragonflight pre-patch?")
--   essence     where the Heart of Azeroth still works is not settled by a
--               page read (nil)
--   corruption  the Corruption system went away in patch 9.0 (Blizzard
--               Watch, 2020-10-12), but the cloak's Use line also names
--               Sanity Drain, and whether it serves Horrific Visions now isn't
--               known (nil)
--
-- No C_LegendaryCrafting call maps an item to its power (RuneforgePower has
-- no item field; GetRuneforgePowerInfo takes a power ID, 12.1.0 docs), so
-- whether a memory is known comes from its tooltip's "Already known"
-- (ITEM_SPELL_KNOWN) alone, like a glyph's (rule 6: done only for a copy no
-- other character can use). Whether a restored memory's tooltip shows that
-- line is unmeasured until the Lab's legacy probe runs.
--
--   no system named                               nothing
--   teaches something, "Already known", a copy    Purpose done
--   only this character can use
--   "Already known" on a copy another character   Unknown
--   could use
--   the system no longer does anything (still     Outdated, naming the system
--   false)                                        and why
--   otherwise                                     Unknown, led by what the
--                                                 system was, with whether it
--                                                 still does anything
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try
local IsPositiveID = Recollect.Utilities.IsPositiveID

local Legacy = {}
Recollect.Purposes.Legacy = Legacy

local seams = {
  ItemSpell = function(itemID)
    local _, spellID = C_Item.GetItemSpell(itemID)
    return spellID
  end,
  SpellDescription = function(spellID) return C_Spell.GetSpellDescription(spellID) end,
}

-- Each system: its Use text's opening words (English, colors stripped), the
-- expansion it belongs to, what it was, and whether it still does anything
local SYSTEMS = {
  {
    key = "memory", opening = "Restore the following memory to the Runecarver", expansion = 8, learn = true,
    name = "Runecarving memory",
    what = "a Shadowlands legendary memory: restoring it lets the Runecarver in Torghast put its power on Shadowlands legendary gear",
    still = true,
    stillWords = "Shadowlands legendary powers still work, but only in Shadowlands content (Blizzard Watch, 2022-10-19)",
  },
  {
    key = "essence", opening = "Infuse your Heart of Azeroth with", expansion = 7, learn = true,
    name = "Heart of Azeroth essence",
    what = "a Battle for Azeroth essence: it adds a power to the Heart of Azeroth necklace",
    still = nil,
    stillWords = "where the Heart of Azeroth still works isn't checked",
  },
  {
    key = "corruption", opening = "Empower Ashjra'kamas", expansion = 7, learn = false,
    name = "Ashjra'kamas upgrade",
    what = "a Battle for Azeroth upgrade for the cloak Ashjra'kamas, Shroud of Resolve, against Sanity Drain and Corruption",
    still = nil,
    stillWords = "Corruption was removed in patch 9.0 (Blizzard Watch, 2020-10-12); whether it still serves Horrific Visions isn't checked",
  },
}

-- The Use text without its trigger ("Use: "), color codes and texture tags
local function Plain(text)
  text = Recollect.Facts.Tooltip.StripColors(text):gsub("|T.-|t", "")
  local trigger = ITEM_SPELL_TRIGGER_ONUSE
  if type(trigger) == "string" and trigger ~= "" and text:sub(1, #trigger) == trigger then text = text:sub(#trigger + 1) end
  return (text:gsub("^%s+", ""))
end

-- The Use text to match: the tooltip's line, else the spell's description;
-- nil while it loads or can't be read
local function UseText(itemID, facts, tip)
  if tip and type(tip.useText) == "string" and tip.useText ~= "" then return Plain(tip.useText) end
  if facts and (facts.spellLoading or facts.hasSpell == false) then return nil end
  local ok, spellID = Try(seams.ItemSpell, itemID)
  if not ok or not IsPositiveID(spellID) then return nil end
  local okText, text = Try(seams.SpellDescription, spellID)
  if not okText or type(text) ~= "string" or text == "" then return nil end
  return Plain(text)
end

-- The power a memory restores: the first line after the colon ("Triune
-- Ward"); the spell's text goes on with the power's own description on the
-- next line (the Lab's panels probe, 2026-09-26), and a tooltip joins its
-- lines with " | "
local function PowerName(text)
  local rest = text:match(":%s*(.-)%s*$")
  if not rest then return nil end
  rest = rest:gsub("|n", "\n"):gsub("|", "\n")
  for segment in (rest .. "\n"):gmatch("(.-)\n") do
    segment = segment:gsub("^%s+", ""):gsub("%s+$", "")
    if segment ~= "" then return segment end
  end
  return nil
end

function Legacy.System(itemID, facts, tip)
  if not R.EnglishClient() then return nil end
  local text = UseText(itemID, facts, tip)
  if not text then return nil end
  for _, system in ipairs(SYSTEMS) do
    if text:sub(1, #system.opening) == system.opening then
      local out = {}
      for k, v in pairs(system) do out[k] = v end
      out.opening = nil
      if system.key == "memory" then out.power = PowerName(text) end
      return out
    end
  end
  return nil
end

-- "A Runecarving memory (Triune Ward)"
local function Title(system)
  local title = ("%s %s"):format(R.Article(system.name), system.name)
  if system.power then title = ("%s (%s)"):format(title, system.power) end
  return title
end

R.Register({
  key = "legacy",
  label = "Older system",
  order = 59,
  Evaluate = function(ctx)
    -- Every system item has a Use spell: nothing else is read for one without
    if ctx.facts.hasSpell == false then return nil end
    local tip = ctx.Tooltip()
    local system = Legacy.System(ctx.stack.itemID, ctx.facts, tip)
    if not system then return nil end
    local title = Title(system)
    local about = ("%s: %s; %s"):format(title, system.what, system.stillWords)
    if system.learn then
      if not tip then return R.Unknown(about .. "; its tooltip can't be read to tell whether you know it", title) end
      if tip.known then
        if R.CharacterOnlyCopy(ctx) then
          return R.Result(V.DONE, ("%s; this character already knows it (its tooltip says Already known)"):format(title))
        end
        return R.Unknown(("%s; this character already knows it, but this copy could serve another character"):format(title), title)
      end
    end
    if system.still == false then return R.Result(V.OUTDATED, about) end
    local known = ""
    if system.learn then known = "; its tooltip doesn't say Already known" end
    if tip and tip.redLines > 0 then known = known .. "; its tooltip shows a requirement this character doesn't meet here" end
    return R.Unknown(about .. known, title)
  end,
})

Legacy._test = { seams = seams, SYSTEMS = SYSTEMS }
