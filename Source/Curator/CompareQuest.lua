-------------------------------------------------------------------------------
-- Curator.Compare, continued: what a quest window shows (curator plan,
-- phase 4c), against the shipped data through Host only
--
-- Facts (the store's fact names; values are text):
--   q:<quest>:w:<item> / :k:<item>   a reward / a choice reward not shipped
--                                    (value: how many)
--   q:<quest>:i:<item>               shipped as the other kind (value "w"
--                                    or "k", shipped the other)
--   q:<quest>:o:<item>               an item the turn-in asks for (value:
--                                    how many; shipped: objective or
--                                    questItem)
--   s:<item>                         the quest an item starts
--   G:<quest>                        who gives the quest (never a conflict:
--                                    a quest may have several givers)
--   T:<quest>                        who takes the turn-in (not shipped yet)
--   Q:<quest>                        a daily or weekly the game states
-- Every reward, choice and turn-in item is also handed to the
-- items-with-no-information recorder as seen at "q:<quest>"
-- (Compare.SawItem, the fact ni:<item>).
-- Rewards are filtered by class (U14), so a quest window is never complete
-- and gives no "not seen": additions, conflicts and stamps only.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Compare = Curator.Compare

local function Record(kind, fact, value, shipped, ctx)
  return Curator.Store.Record(kind, fact, value, shipped, ctx)
end

local KINDS = { { letter = "w", relation = "reward", other = "k", otherRelation = "choice", field = "rewards" },
  { letter = "k", relation = "choice", other = "w", otherRelation = "reward", field = "choices" } }

-- QuestRewards(visit, ctx): visit = { questID, rewards = { [itemID] = n },
-- choices = { [itemID] = n } }; returns how many matched
function Compare.QuestRewards(visit, ctx)
  local quest, matched = visit.questID, {}
  for _, kind in ipairs(KINDS) do
    for itemID, count in pairs(visit[kind.field] or {}) do
      Compare.SawItem(itemID, "q:" .. quest, ctx)
      if Compare.Shipped(itemID, kind.relation)[quest] then
        matched[#matched + 1] = itemID
      elseif Compare.Shipped(itemID, kind.otherRelation)[quest] then
        Record("conflict", "q:" .. quest .. ":i:" .. itemID, kind.letter, kind.other, ctx)
      else
        Record("addition", "q:" .. quest .. ":" .. kind.letter .. ":" .. itemID, tostring(count), nil, ctx)
      end
    end
  end
  Curator.Store.Confirm("q:" .. quest, matched, 0, ctx)
  return #matched
end

-- QuestRequired(questID, required, ctx): required = { [itemID] = n }, what
-- the turn-in asks for
function Compare.QuestRequired(questID, required, ctx)
  local matched = {}
  for itemID, count in pairs(required) do
    Compare.SawItem(itemID, "q:" .. questID, ctx)
    local shipped = Compare.Shipped(itemID, "objective")[questID] or Compare.Shipped(itemID, "questItem")[questID]
    local fact = "q:" .. questID .. ":o:" .. itemID
    if not shipped then
      Record("addition", fact, tostring(count), nil, ctx)
    elseif shipped ~= true and shipped ~= count then
      Record("conflict", fact, tostring(count), tostring(shipped), ctx)
    else
      matched[#matched + 1] = itemID
    end
  end
  if #matched > 0 then Curator.Store.Confirm("o:" .. questID, matched, 0, ctx) end
  return #matched
end

-- QuestStarter(itemID, questID, ctx): the quest an item offered
function Compare.QuestStarter(itemID, questID, ctx)
  if Compare.Shipped(itemID, "starts")[questID] then
    Curator.Store.Confirm("s:" .. itemID, { questID }, 1, ctx)
    return "confirmed"
  end
  Record("addition", "s:" .. itemID, tostring(questID), nil, ctx)
  return "addition"
end

-- QuestGiver(questID, npc, ctx)
function Compare.QuestGiver(questID, npc, ctx)
  local shipped = Host.QuestGiver(questID)
  if shipped == npc then
    Curator.Store.Confirm("G:" .. questID, { 1 }, 1, ctx)
    return "confirmed"
  end
  Record("addition", "G:" .. questID, tostring(npc), shipped and tostring(shipped) or nil, ctx)
  return "addition"
end

-- QuestTurnIn(questID, npc, ctx): no turn-in NPC ships yet
function Compare.QuestTurnIn(questID, npc, ctx)
  Record("addition", "T:" .. questID, tostring(npc), nil, ctx)
end

-- QuestFrequency(questID, letter ("d" or "w"), ctx)
function Compare.QuestFrequency(questID, letter, ctx)
  local flags = Host.QuestFrequency(questID) or ""
  if flags:find(letter, 1, true) then
    Curator.Store.Confirm("Q:" .. questID, { 1 }, 1, ctx)
    return "confirmed"
  end
  Record("addition", "Q:" .. questID, letter, flags ~= "" and flags or nil, ctx)
  return "addition"
end
