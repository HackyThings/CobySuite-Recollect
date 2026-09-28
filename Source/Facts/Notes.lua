-------------------------------------------------------------------------------
-- Facts.Notes: the guide notes Data/Notes.lua ships, by item (contract
-- rule 43: information, never a verdict)
--
-- For(itemID) returns the notes about an item, in the file's order:
--   { { text, howMany, where, from, confirmed, confirmInGame, achievement,
--       quest } }
-- (an empty list when there is none). No website is named: the pages a
-- note was researched on stay in the repo's research notes (Cobanyte,
-- 2026-09-28). confirmed is false until the entry's in-game check says otherwise, and
-- then that check's words. A note never changes a verdict: nothing in the
-- purpose checks reads this module.
-- An entry without items or text is left out. The index
-- is built on the first call and again only when Data.Notes is replaced
-- (a test that scripts it).
-------------------------------------------------------------------------------
local Notes = {}
Recollect.Facts.Notes = Notes

local IsPositiveID = Recollect.Utilities.IsPositiveID

local NONE = {}

local index, indexedFrom = nil, nil

-- One entry as the note For returns, or nil when it isn't usable
local function Read(entry)
  if type(entry) ~= "table" or type(entry.text) ~= "string" or entry.text == "" then return nil end
  if type(entry.items) ~= "table" then return nil end
  local function Optional(value) return type(value) == "string" and value ~= "" and value or nil end
  return {
    text = entry.text, howMany = Optional(entry.howMany), where = Optional(entry.where), from = Optional(entry.from),
    confirmed = type(entry.confirmed) == "string" and entry.confirmed ~= "" and entry.confirmed or false,
    confirmInGame = Optional(entry.confirmInGame),
    achievement = IsPositiveID(entry.achievement) and entry.achievement or nil,
    quest = IsPositiveID(entry.quest) and entry.quest or nil,
  }
end

local function Index()
  local data = Recollect.Data and Recollect.Data.Notes
  if index and indexedFrom == data then return index end
  index, indexedFrom = {}, data
  for _, entry in ipairs(type(data) == "table" and data or NONE) do
    local note = Read(entry)
    if note then
      for _, itemID in ipairs(entry.items) do
        if IsPositiveID(itemID) then
          local list = index[itemID]
          if not list then
            list = {}
            index[itemID] = list
          end
          list[#list + 1] = note
        end
      end
    end
  end
  return index
end

-- For(itemID): the notes about the item (see the header), never nil
function Notes.For(itemID)
  if not IsPositiveID(itemID) then return NONE end
  return Index()[itemID] or NONE
end
