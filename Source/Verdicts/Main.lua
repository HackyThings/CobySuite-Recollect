-------------------------------------------------------------------------------
-- Verdicts: every purpose check on one item, combined into one verdict
--
-- The accuracy contract, as code:
--   * No facts (item data not loaded) means Unknown before any check runs.
--   * No check that applies means Unknown ("no purpose check covers this
--     item yet").
--   * Needed beats Use now, which beats Useful, which beats Unknown, which
--     beats Junk, then Outdated, then Lower level, then Purpose done: an
--     Unknown in any purpose blocks Junk, Outdated, Lower level and Purpose
--     done.
--   * Junk, Outdated, Lower level and Purpose done also need no sign of a use
--     this build does not check yet: a crafting reagent or a quest item with
--     no check covering it. Those make it Unknown, naming what was found and
--     what is not checked.
--   * A check that errors counts as Unknown for its purpose.
--   * A slot whose quest info couldn't be read (stack.questUnread) may be a
--     quest item: that blocks them too (BA-02).
--   * A result may carry supersedes = { [key] = true } (Season, for a season
--     of this expansion that isn't the current one): those checks' Useful,
--     Use now, and Unknowns that state a use's progress (with a headline:
--     "You have 3 of the 5 it takes") then only inform (Settle), since they
--     rest on the item being of the current expansion.
--   * Every use the data knows being gone (the "removed" check) is Outdated
--     only when nothing else answered: an item with a Use effect, or whose
--     spell can't be read, and no other check deciding, is Unknown (Settle).
-- An Unknown result carries the deciding check's category (G-04,
-- Registry.CATEGORY), so the panel can name the one step that changes it.
-- No verdict is cached: collections, quests and recipes change without a
-- bag event, so each redraw evaluates again; what a check keeps (Buys,
-- Season, Reagent, through Facts.Buys.Stamp) lasts only until data changes
-- or a few seconds pass (contract rule 9).
-------------------------------------------------------------------------------
local Verdicts = Recollect.Verdicts
local R = Recollect.Purposes.Registry
local V = R.Verdict

-- Sort order for the list: what to act on first
Verdicts.RANK = { [V.NEEDED] = 1, [V.USE] = 2, [V.USEFUL] = 3, [V.UNKNOWN] = 4, [V.JUNK] = 5, [V.OUTDATED] = 6, [V.LOWER] = 7,
  [V.DONE] = 8 }

-- Uses the item shows signs of that no check in purposes answered for (the
-- Reagent and QuestItem checks normally do; this is the last guard)
function Verdicts.OtherUses(ctx, purposes)
  local answered = {}
  for _, p in ipairs(purposes or {}) do answered[p.key] = true end
  local list = {}
  if ctx.facts and ctx.facts.isCraftingReagent and not answered.reagent then list[#list + 1] = "reagent" end
  local quest = ctx.stack and ctx.stack.quest
  -- A quest starter the questStarter check answered for is covered: its
  -- quest is the slot's own (QuestItem stands down for it)
  local starter = answered.questStarter and quest and Recollect.Utilities.IsPositiveID(quest.questID)
  if ((quest and quest.isQuestItem) or (ctx.facts and ctx.facts.classID == R.CLASS_QUEST)) and not answered.questItem
    and not starter then
    list[#list + 1] = "quest item"
  end
  if ctx.stack and ctx.stack.questUnread then list[#list + 1] = "quest info (unreadable)" end
  return list
end

-- Whether every purpose is done or settled (a result's settled: every use
-- that check read is finished, and it is Can't tell only for what can't be
-- ruled out, such as a completed quest that may come back), with at least
-- one settled
local function Settled(purposes)
  local any = false
  for _, p in ipairs(purposes) do
    if p.settled then any = true elseif p.verdict ~= V.DONE then return false end
  end
  return any
end

-- Combine(purposes, otherUses): the verdict for a list of purpose results.
-- A Can't tell whose every purpose is done or settled carries settled = true
-- and the category "finished", so it is never listed as "no check covers it"
-- The signs of other uses no check covers (OtherUses), in words: the note
-- a Combine result carries, and the Tip's "Not checked" (UI.Tooltip)
Verdicts.UNCHECKED_WORDS = {
  reagent = "whether a recipe uses it",
  ["quest item"] = "whether a quest needs it",
  ["quest info (unreadable)"] = "its quest info, which can't be read",
}

function Verdicts.Combine(purposes, otherUses)
  if #purposes == 0 then
    return { verdict = V.UNKNOWN, reason = "No check covers this item yet", purposes = purposes, category = "unsupported" }
  end
  local settled = Settled(purposes) and (not otherUses or #otherUses == 0) or nil
  -- Soft Unknowns (Registry.Info) only inform: they decide only when every check is soft
  local decided = {}
  for _, p in ipairs(purposes) do
    if not p.soft then decided[#decided + 1] = p end
  end
  if #decided == 0 then
    return { verdict = V.UNKNOWN, reason = purposes[1].reason, purposes = purposes,
      category = settled and "finished" or "unsupported", settled = settled }
  end
  local first = {}
  for _, p in ipairs(decided) do
    if not first[p.verdict] then first[p.verdict] = p end
  end
  for _, verdict in ipairs({ V.NEEDED, V.USE, V.USEFUL, V.UNKNOWN }) do
    if first[verdict] then
      local p = first[verdict]
      local unknown = verdict == V.UNKNOWN
      return { verdict = verdict, reason = p.reason, purposes = purposes,
        category = unknown and (p.category or (settled and "finished")) or nil, recovery = unknown and p.recovery or nil,
        settled = unknown and settled or nil }
    end
  end
  -- Every purpose is junk, outdated, lower level or done: the first of those
  -- any is, reasons in that order
  local reasons = {}
  for _, verdict in ipairs({ V.JUNK, V.OUTDATED, V.LOWER, V.DONE }) do
    for _, p in ipairs(decided) do
      if p.verdict == verdict then reasons[#reasons + 1] = p.reason end
    end
  end
  local reason = table.concat(reasons, "; ")
  if otherUses and #otherUses > 0 then
    -- in words ("not checked yet: whether a recipe uses it"), the signs kept
    -- as they are in unchecked for the Tip
    local words = {}
    for i, sign in ipairs(otherUses) do words[i] = Verdicts.UNCHECKED_WORDS[sign] or sign end
    local list = #words > 1 and (table.concat(words, ", ", 1, #words - 1) .. " and " .. words[#words]) or words[1]
    local note = "not checked yet: " .. list
    local unreadable = otherUses[#otherUses] == "quest info (unreadable)"
    return { verdict = V.UNKNOWN, reason = reason .. "; " .. note, note = note, unchecked = otherUses, purposes = purposes,
      category = unreadable and "unreadable" or "unsupported" }
  end
  return { verdict = (first[V.JUNK] and V.JUNK) or (first[V.OUTDATED] and V.OUTDATED) or (first[V.LOWER] and V.LOWER) or V.DONE,
    reason = reason,
    purposes = purposes }
end

-- Evaluate(ctx): { verdict, reason, purposes = { { key, label, verdict, reason } } }
function Verdicts.Evaluate(ctx)
  if not ctx.facts then
    local why = ctx.factsReason or "Item data not loaded"
    return { verdict = V.UNKNOWN, reason = why, purposes = {}, category = why == "item data loading" and "loading" or "unreadable" }
  end
  local purposes = {}
  for _, check in ipairs(R.All()) do
    if not ctx.otherCharacter or check.accountWide then
      Verdicts.RunCheck(check, ctx, purposes)
    end
  end
  Verdicts.Settle(ctx, purposes)
  if ctx.otherCharacter and #purposes == 0 then
    return { verdict = V.UNKNOWN, reason = ("Checked only on %s"):format(ctx.otherCharacter), purposes = purposes,
      category = "character" }
  end
  return Verdicts.Combine(purposes, Verdicts.OtherUses(ctx, purposes))
end

-- Settle(ctx, purposes): what one check's result says about another's,
-- applied in place before the verdict is combined
--   supersedes   a result's supersedes names checks whose Useful, Use now or
--                Unknown with a headline (a use's progress, not a failed read,
--                and not one waiting on a read: readOwed, Reagent's unread
--                profession windows) only informs (soft, with supersededBy
--                naming the result); a result marked noSettle (Reagent's
--                missing collectible a recipe still makes) is never softened
--   removed      the "removed" check's Outdated (every use the data knows is
--                gone) turns Unknown when the item has a Use effect, or its
--                spell can't be read, and no other check decided: that effect
--                may still be a use, and nothing checked it
function Verdicts.Settle(ctx, purposes)
  local over
  for _, p in ipairs(purposes) do
    if type(p.supersedes) == "table" then
      over = over or {}
      for key in pairs(p.supersedes) do over[key] = p end
    end
  end
  local removed, decidedOther = nil, false
  for _, p in ipairs(purposes) do
    local by = over and over[p.key]
    if by and by ~= p and not p.noSettle and (p.verdict == V.USEFUL or p.verdict == V.USE
      or (p.verdict == V.UNKNOWN and p.headline ~= nil and not p.readOwed)) then
      p.soft = true
      p.supersededBy = by.key
    end
    if p.key == "removed" then
      removed = p
    elseif not p.soft then
      decidedOther = true
    end
  end
  if removed and removed.verdict == V.OUTDATED and not decidedOther and ctx.facts and ctx.facts.hasSpell ~= false then
    removed.verdict = V.UNKNOWN
    removed.reason = removed.reason .. (ctx.facts.hasSpell == nil and "; whether it has a Use effect can't be read"
      or "; it has a Use effect, which isn't checked")
    removed.category = ctx.facts.hasSpell == nil and "unreadable" or nil
  end
end

-- One check on ctx, its result added to purposes (an error counts as Unknown)
function Verdicts.RunCheck(check, ctx, purposes)
  local ok, result = pcall(check.Evaluate, ctx)
  if not ok then
    Recollect.Debug.Warn("PURPOSE", "%s check failed on item %s: %s", check.key, tostring(ctx.stack.itemID), tostring(result))
    result = R.Unknown(check.label .. "; the check failed", nil, "unreadable")
  end
  if result then
    result.key = check.key
    result.label = check.label
    purposes[#purposes + 1] = result
  end
end
