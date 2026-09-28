-------------------------------------------------------------------------------
-- Facts.Notes: the guide notes Data/Notes.lua ships, by item (contract
-- rule 43: information, never a verdict)
--
-- For(itemID) returns the notes about an item, in the file's order:
--   { { text, howMany, where, from, source, sources, confirmed,
--       confirmInGame, achievement, quest } }
-- (an empty list when there is none). source names the pages the note was
-- read on for the panel ("method.gg", "method.gg and forums.blizzard.com":
-- the first two sites of sources, "www." and a forum's region left off);
-- confirmed is false until the entry's in-game check says otherwise, and
-- then that check's words. A note never changes a verdict: nothing in the
-- purpose checks reads this module.
-- An entry without items, text or an http(s) source is left out. The index
-- is built on the first call and again only when Data.Notes is replaced
-- (a test that scripts it).
-------------------------------------------------------------------------------
local Notes = {}
Recollect.Facts.Notes = Notes

local IsPositiveID = Recollect.Utilities.IsPositiveID

local NONE = {}
local MAX_SITES = 2   -- sites named in a note's source

local index, indexedFrom = nil, nil

-- "method.gg" for "https://www.method.gg/guides/...", "forums.blizzard.com"
-- for "https://us.forums.blizzard.com/..."; nil for anything not http(s)
function Notes.Site(url)
  if type(url) ~= "string" then return nil end
  local host = url:match("^https?://([^/%?#]+)")
  if not host or host == "" then return nil end
  host = host:lower():gsub("^www%.", "")
  host = host:gsub("^%a%a%.forums%.", "forums.")
  return host
end

-- The panel's name for a note's sources, or nil when none is a page
local function SourceLabel(sources)
  local sites, seen = {}, {}
  for _, url in ipairs(sources) do
    local site = Notes.Site(url)
    if site and not seen[site] then
      seen[site] = true
      if #sites < MAX_SITES then sites[#sites + 1] = site end
    end
  end
  if #sites == 0 then return nil end
  return table.concat(sites, " and ")
end

-- One entry as the note For returns, or nil when it isn't usable
local function Read(entry)
  if type(entry) ~= "table" or type(entry.text) ~= "string" or entry.text == "" then return nil end
  if type(entry.items) ~= "table" or type(entry.sources) ~= "table" then return nil end
  local source = SourceLabel(entry.sources)
  if not source then return nil end
  local function Optional(value) return type(value) == "string" and value ~= "" and value or nil end
  return {
    text = entry.text, howMany = Optional(entry.howMany), where = Optional(entry.where), from = Optional(entry.from),
    source = source, sources = entry.sources,
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
