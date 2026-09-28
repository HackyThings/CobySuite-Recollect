-------------------------------------------------------------------------------
-- Curator recorder: what a quest item is used on (curator spec, "v1
-- recorders"; research note I section 6)
--
-- UNIT_SPELLCAST_SENT names the cast (its castGUID, spell, and the target's
-- name). The target's identity is read then from UnitGUID("target"), else
-- the soft-interact target, and counts only when that unit's name is the
-- cast's target name (compared, never stored): a quest item cast on
-- yourself or on the ground while something else is targeted names no
-- target, so nothing is recorded. When the cast succeeds (the bag
-- observer's cast listeners, by castGUID and the same spell) and its spell
-- is the Use spell of exactly one quest item (item class 12) in the bags,
-- the item was used on that NPC or object: Compare.UsedAt, in a later
-- frame. A secret or missing value records nothing.
--
-- Only while curator mode may record, and never while a test run scripts
-- the client. Client reads go through QuestItemUse.seams.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Bags = Curator.Recorders.Bags

local QuestItemUse = {}
Curator.Recorders.QuestItemUse = QuestItemUse

local QUEST_CLASS = 12   -- Enum.ItemClass.Questitem
local KEEP = 10          -- seconds a sent cast waits for its result

QuestItemUse.seams = {
  UnitGUID = function(unit) return UnitGUID(unit) end,
  UnitName = function(unit) return UnitName(unit) end,
  ItemClass = function(itemID) return select(6, C_Item.GetItemInfoInstant(itemID)) end,
}

local sent = {}   -- [castGUID] = { kind, id, spell, at }

local function Read(name, ...)
  local ok, value = pcall(QuestItemUse.seams[name], ...)
  if not ok or Host.IsSecret(value) then return nil end
  return value
end

local function Readable(text)
  return type(text) == "string" and not Host.IsSecret(text) and text ~= ""
end

-- The cast's target: "npc" or "obj", and its ID, when a unit whose name is
-- the cast's target name is targeted (or soft-interacted); else nil
function QuestItemUse.Target(targetName)
  if not Readable(targetName) then return nil end
  for _, unit in ipairs({ "target", "softinteract" }) do
    local guid = Read("UnitGUID", unit)
    if type(guid) == "string" and Read("UnitName", unit) == targetName then
      local kind, _, _, _, _, id = strsplit("-", guid)
      id = tonumber(id)
      if not id then return nil end
      if kind == "Creature" or kind == "Vehicle" then return "npc", id end
      if kind == "GameObject" then return "obj", id end
      return nil
    end
  end
  return nil
end

-- UNIT_SPELLCAST_SENT (unit, targetName, castGUID, spellID)
function QuestItemUse.OnSent(unit, targetName, castGUID, spellID)
  if unit ~= "player" or not Curator.Main.MayRecord() or not Readable(castGUID) or not Bags.PositiveID(spellID) then return end
  local now = Bags.seams.Clock()
  for guid, entry in pairs(sent) do
    if now - entry.at > KEEP then sent[guid] = nil end
  end
  local kind, id = QuestItemUse.Target(targetName)
  if kind then sent[castGUID] = { kind = kind, id = id, spell = spellID, at = now } end
end

-- A cast succeeded (spellID, castGUID)
function QuestItemUse.OnCast(spellID, castGUID)
  if not Readable(castGUID) then return end
  local target = sent[castGUID]
  if not target then return end
  sent[castGUID] = nil
  if target.spell ~= spellID then return end
  local found
  for _, itemID in ipairs(Bags.ItemsForSpell(spellID)) do
    if Read("ItemClass", itemID) == QUEST_CLASS then
      if found then return end   -- two quest items share the spell: no answer
      found = itemID
    end
  end
  if found then
    Curator.Main.Defer(function() Curator.Compare.UsedAt(found, target.kind, target.id, Curator.Context.Current()) end)
  end
end

function QuestItemUse.Reset()
  wipe(sent)
end

Bags.ListenCasts(function(spellID, castGUID) QuestItemUse.OnCast(spellID, castGUID) end)

local frame = CreateFrame("Frame")
pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SENT", "player")
frame:SetScript("OnEvent", function(_, _, ...)
  if Curator.Main.IsScripted() then return end
  local ok, err = pcall(QuestItemUse.OnSent, ...)
  if not ok then Host.Log("Quest item recorder failed: %s", tostring(err)) end
end)
