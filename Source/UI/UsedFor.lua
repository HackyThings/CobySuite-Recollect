-------------------------------------------------------------------------------
-- UI.UsedFor: the audit panel's USED FOR and COMES FROM lines, one per thing
-- the item is linked to, each with its live state
--
--   USED FOR
--   Objective of "Light Repurposed" (you're on it)
--   Counts toward "Glory of the Ulduar Raider" (4 of 30)
--   Used in 17 of your recipes (8 Blacksmithing, 9 Leatherworking)
--   Opens a treasure in Zul'Aman (48.5, 25.8) (not looted)
--     Holds Arathi Lantern and 2 more
--   Used at Hogger (Elwynn Forest)
--   Makes Shattered Fragments of Val'anyr from 30 (you have none yet)
--   Currency: Radiant Spark Dust (you have 12 Radiant Spark Dust)
--     Spent at a vendor in Silvermoon City (55.7, 65.9)
--   Buys at Fizz Alechux (Razorwind Shores) or Kay Stouthammer (...)   a heading
--   Decor: Brewfest Keg for 125 (not owned)
--   Mount: Spectral Steed for 165 (not owned)
--   Buys at Chef Dinaire (Hallowfall)
--   Darkroot Grippers for 5 plus other costs
--     Leads to Phoenix Wishwing, a pet you don't have, through "Tale of
--     the Phoenix" (not done)
--   COMES FROM
--   Reward from "Pink Elekks On Parade" (not done)
--   Reward from the achievement "Treasures of Voidstorm" (3 of 5 done)
--   Sold by Innkeeper Farley (Elwynn Forest)
--   Drops from Hogger
--   Found at a spot in Naigtal (22.9, 61.3)
--   Drops from enemies in Zul'Aman
--   Crafted by Blacksmithing: Spellbreaker's Blade
--   Renown 12 with Council of Dornogal (you're at 7)
--   Sometimes offered on the Black Market Auction House
--   Offered at the Trading Post (March 2025)
--   Drops from Sylvanas Windrunner in Sanctum of Domination, per the Encounter Journal
--
-- Lines(itemID, stack, owner, opts) returns the uses { { text, color,
-- detail, tier, header, note, place } }, the first position found for the waypoint
-- key ({ mapID, x, y, zone, what }; a key's object or an NPC it is used at
-- first, then a vendor that takes the item, then one it buys from, then one
-- that sells it), the sources in the same form, and extra = { unavailable
-- (lines of routes no longer in the game), pending (quests of the uses still
-- being checked), pendingSources (quests it comes from still being
-- checked, noted under COMES FROM, never under USED FOR) }. The uses hold at
-- most MAX_LINES lines besides headings, the sources MAX_SOURCES, then "and
-- N more"; opts.full (the pinned view, UI.DetailWindow) raises both to
-- FULL_LINES and lists the routes no longer available. opts.tip (the
-- tooltip's facts, Facts.Tooltip.Parse) and opts.facts (Facts.Item.Get)
-- let the lines read the Use line: what using it gives, and an older
-- system's line.
--
-- Order (BA-14): every line has a tier, what is still to get or do (a quest
-- not done or on it, an achievement not earned, a collectible or decor not
-- owned), then lines with no state of that kind, then what is done or out of
-- reach; the lines are sorted by tier across every group, stable, so "and N
-- more" hides the finished ones (Cobanyte, 2026-09-24). What an item buys is
-- grouped under a heading per seller ("Buys at ..."): consecutive lines of
-- one seller share it, and a seller whose lines fall in two tiers gets the
-- heading again. Only the lines shown are worded: names and sellers are read
-- for them alone (BA-11), so an item that buys thousands of things costs a
-- sort, not thousands of item loads.
--
-- What it buys comes from Facts.Journals (mounts and pets), Facts.Relations
-- "buysDecor" (the housing catalog) and "buys" (AllTheThings and the Lab's
-- vendor recorder, read live through Facts.Buys; a thing the journals or
-- catalog list is not repeated). Sellers come from the collection's own
-- source text (Facts.Vendors.FromSourceText) or are named by the data, the
-- name read live (Facts.Vendors.Describe). A purchase that takes other costs
-- too says "plus other costs". An achievement AllTheThings says the item
-- counts toward reads like the game's own criteria; a criterion it only
-- links the item to reads "Linked to". A key says what it opens
-- (Facts.Vendors.Object): where, what it holds, and whether its loot quest
-- is done; an NPC it is used at is named.
--
-- Routes (SRC-01, Relations.Applies): one no longer in the game is left out
-- (extra.unavailable holds it for the pinned view's "No longer available",
-- tagged "no longer obtainable"); one for another faction, class or race
-- says so ("(Horde only)", "(Blood Elf only)") with no state, gray, and sits
-- with the finished lines. An event route adds "During a holiday or event"
-- for every character, before a line's closing state. These tags come from
-- Relations.Conditions and are display only (D19, D34): the checks never
-- read them, so no verdict moves.
--
-- A quest line's detail says what the quest rewards (Facts.Chains, from the
-- shipped W table, each reward with its state: "Rewards Phoenix Wishwing, a
-- pet you don't have"), else what the game's quest data lists. A plain item
-- it buys is followed through its own relations (Facts.Chains, contract
-- rule 39) for the first MAX_FOLLOW such purchases: the detail says what it
-- leads to, and a chain still open ranks with what is still to get.
--
-- Quests (BA-13/14): each quest line reads its quest's state; a quest not
-- loaded yet is asked of the server a batch at a time (QuestInfo.FrameBudget,
-- shared by everything that reads quests in a frame), those in the log
-- first, and "N more still being checked" stands for the rest until their
-- answers bring a new build. A quest that any of the item's codes names as
-- no longer in the game, or for another faction, class or race, is that on
-- all of them (Relations.QuestApplies). An account quest is done when the
-- account has done it (QuestInfo.Done).
--
-- Owner (BA-05): owner is Verdicts.Rows.Owner(). For another character's
-- copy, what only the logged-in character can be asked (quest states, loot,
-- counts of what you hold, known recipes) is left out: those lines read
-- without a state, and "your recipes" gives way to the recipes that
-- character's scans recorded.
--
-- A currency the game turns straight into reputation carries its faction's
-- name and is never held (C_CurrencyInfo.GetFactionGrantedByCurrency), so
-- it reads as the reputation it grants, with no count or vendor; when that
-- read fails there is no line. Quests of the same title (one per faction)
-- are one line, with the state of whichever you're on or have done. Names,
-- titles and states are read live; a name not loaded yet reads "item 123"
-- (its load fires InventoryChanged, and the panel reads again).
--
-- Names as game links (item 3): every line carries links = { { kind, id,
-- text, color } }, the names it uses that the game links (an item by its
-- quality's color, a quest or achievement yellow, a spell, mount or recipe
-- blue, a currency by its quality), heard as each line is worded
-- (Facts.Chains.SetNamer for what a chain names). The text stays plain;
-- UI.AuditPanel colors the names when it paints (the panel follows the
-- tooltip and can't be clicked), and the details window can make them links.
--
-- Round two (2026-09-25):
--   * Linked (item 4): every link of one achievement is one line with its
--     progress ("Linked to "Advanced Husbandry" (3 of 72 done)"), the detail
--     saying how many of the linked parts are still to do; never a need.
--   * An older system (item 5, Purposes.Legacy.System): what it was, and in
--     the detail whether it still does anything, with its page.
--   * What using it gives (items 7, 8): a currency whose count the data
--     lacks reads "Using it gives 48 Cataloged Research (you have 0 ...)"
--     from the Use line (English clients, Purposes.UseEffect.GainCount).
--     Where a Use works is left to the checks' reasons: the Use line says it
--     beside the panel.
--   * Costs (item 9): a purchase names every other cost the data lists ("for
--     50 plus 4 Apexis Crystal and 25 gold", UsedFor.CostWords); a trade
--     with no vendor named but its place is headed "Buys in <zone>".
--   * A reagent's per-profession line carries the total (reagentTotal), so
--     the panel's headline names every recipe (UI.Tooltip).
--
-- Sources of data format 4 (journalDrop, renownReward, blackMarket,
-- tradingPost): the boss and its dungeon or raid from the Encounter Journal
-- (Facts.Vendors.Encounter, the boss's name a journal link); a renown
-- reward's faction and, on the logged-in character's copy only, whether its
-- renown has reached the level (C_MajorFactions.GetMajorFactionData, read
-- live, "can't be read" when it fails); the Trading Post's month when the
-- data gives one. Like every source, none moves a verdict.
--
-- More lines (items 4, 5, 7): a task of the running neighborhood endeavor
-- that names the item (Facts.Endeavors.UsesOf, the logged-in character's
-- only), in the state's color; under the uses, what the routes no longer in
-- the game were ("Every use Recollect knows is gone from the game: it
-- bought 55 things"), which the verdict's removed check also says; and first
-- under COMES FROM, the patch every way to get the item was removed in
-- (Purposes.Season.RemovedIn, AllTheThings' patch once this client is at or
-- past it), else how many ways to get it are no longer in the game.
--
-- NoteLines(itemID, owner) words the guide notes (Facts.Notes, Data/Notes.lua)
-- for the panel's GUIDE NOTES and the details window: the note, how many,
-- where, where it comes from, an achievement's or quest's live state, and
-- whose words they are ("Per method.gg; not confirmed in game yet"). A note
-- is never a USED FOR line and never changes a verdict.
-------------------------------------------------------------------------------
local UsedFor = {}
Recollect.UI.UsedFor = UsedFor

local U = CobySuite_Recollect.Utilities
local Try = Recollect.Utilities.Try
local MAX_LINES = 8
local MAX_SOURCES = 4
local FULL_LINES = 300   -- the pinned view's limit: an item can buy thousands of things
local MAX_SELLERS = 2   -- vendors named in one "Buys at" heading
local DETAIL_CHARS = 160
local TIER_OPEN, TIER_INFO, TIER_CLOSED = 1, 2, 3   -- still to get or do; no such state; done or out of reach
-- A quest state's tier, by QuestState's rank: on it, repeatable or not done
-- are open, done is closed, loading or unknown says nothing
local QUEST_TIER = { [5] = TIER_OPEN, [3] = TIER_OPEN, [2] = TIER_OPEN, [4] = TIER_CLOSED }
local QUEST_KIND = { objective = true, questItem = true, starts = true, reward = true, choice = true }
local MAX_FOLLOW = 20   -- plain purchases followed to what they lead to (Facts.Chains), as Purposes.Buys does

local seams = {
  -- The faction a currency is turned into reputation with, or nil
  GrantedFaction = function(currencyID) return C_CurrencyInfo.GetFactionGrantedByCurrency(currencyID) end,
  FactionData = function(factionID) return C_Reputation.GetFactionDataByID(factionID) end,
  -- A major faction's name and renown (MajorFactionData: name, renownLevel), or nil
  MajorFactionData = function(factionID) return C_MajorFactions.GetMajorFactionData(factionID) end,
  ClassName = function(classID)
    local info = C_CreatureInfo.GetClassInfo(classID)
    return info and info.className
  end,
  -- A race's name ("Blood Elf"): the RaceInfo struct is nilable
  RaceName = function(raceID)
    local info = C_CreatureInfo.GetRaceInfo(raceID)
    return info and info.raceName
  end,
  SkillLineName = function(skillLineID) return C_TradeSkillUI.GetTradeSkillDisplayName(skillLineID) end,
  -- A reputation standing's name ("Revered", 1 Hated to 8 Exalted), as Blizzard's reputation UI words it
  StandingLabel = function(standing) return _G["FACTION_STANDING_LABEL" .. standing] end,
  QuestTitle = function(questID) return C_QuestLog.GetTitleForQuestID(questID) end,
  SpellName = function(spellID) return C_Spell.GetSpellName(spellID) end,
  -- An item's quality (nil until its data is cached) and a quality's color
  ItemQuality = function(itemID) return C_Item.GetItemQualityByID(itemID) end,
  QualityColor = function(quality) return C_Item.GetItemQualityColor(quality) end,
}

local function Colors() return Recollect.UI.VerdictColors end
local function Verdict() return Recollect.Purposes.Registry.Verdict end
local function Relations() return Recollect.Facts.Relations end

-------------------------------------------------------------------------------
-- Names as game links: what a line names, heard while it is worded
-------------------------------------------------------------------------------
local LINK_YELLOW = U.Colors.LINK_YELLOW    -- a quest's or an achievement's link
local LINK_BLUE = U.Colors.LINK_BLUE        -- a spell's link (a mount, a recipe, an illusion)
local LINK_KINDS = { quest = LINK_YELLOW, achievement = LINK_YELLOW, spell = LINK_BLUE, mount = LINK_BLUE,
  recipe = LINK_BLUE, illusion = LINK_BLUE }

local function QualityColor(quality)
  if type(quality) ~= "number" then return nil end
  local ok, r, g, b = Try(seams.QualityColor, quality)
  if not ok or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
  return { r, g, b }
end

-- The color the game gives a name's link, or nil when it can't be told
local function LinkColor(kind, id, quality)
  if LINK_KINDS[kind] then return LINK_KINDS[kind] end
  if kind == "item" then
    if quality == nil and Recollect.Utilities.IsPositiveID(id) then
      local ok, q = Try(seams.ItemQuality, id)
      quality = ok and q or nil
    end
    return QualityColor(quality)
  end
  if kind == "currency" then return QualityColor(quality) end
  -- a journal encounter: only named once its link is read (JournalLine)
  if kind == "encounter" then return Recollect.Facts.Vendors.JOURNAL_COLOR end
  return nil
end

local naming = nil   -- the names the line being worded uses, or nil

local function Named(kind, id, text, quality)
  if naming and type(text) == "string" and text ~= "" then
    local color = LinkColor(kind, id, quality)
    if color then naming[#naming + 1] = { kind = kind, id = id, text = text, color = color } end
  end
  return text
end

-- Build(fn, ...): fn's line with the names it used as line.links (a line
-- worded inside another gives its names to that one too)
local function Build(fn, ...)
  local outer = naming
  naming = {}
  local Chains = Recollect.Facts.Chains
  local outerNamer = Chains.SetNamer(Named)
  local ok, line, second = pcall(fn, ...)
  local names = naming
  naming = outer
  Chains.SetNamer(outerNamer)
  if not ok then error(line, 0) end
  if outer then
    for _, name in ipairs(names) do outer[#outer + 1] = name end
  end
  if type(line) == "table" and #names > 0 then line.links = names end
  return line, second
end

local function ItemName(itemID)
  return Named("item", itemID, Recollect.Facts.Item.Name(itemID)) or ("item " .. itemID)
end

-- How many the player holds (bags, bank, warband), or nil when unreadable (BA-07)
local function Owned(itemID)
  local ok, count = Try(Recollect.Purposes.client.GetItemCount, itemID, true, false, true, true)
  return ok and CobySuite_Recollect.Utilities.IsFiniteNumber(count) and count or nil
end

local function Append(into, list)
  for _, line in ipairs(list) do into[#into + 1] = line end
end

local function Cut(text)
  if not text then return nil end
  return U.Truncate(text, DETAIL_CHARS)
end

-------------------------------------------------------------------------------
-- Quests
-------------------------------------------------------------------------------
local FREQUENCY = { { "y", "yearly" }, { "m", "monthly" }, { "w", "weekly" }, { "d", "daily" }, { "q", "world quest" },
  { "r", "repeatable" } }

local function Recurs(questID)
  local flags = Relations().Frequency(questID)
  if not flags then return nil end
  for _, entry in ipairs(FREQUENCY) do
    if flags:find(entry[1], 1, true) then return entry[2] end
  end
  return nil
end

-- A quest's state: title, rank (a merged line keeps the highest), words,
-- color, quest; nil while it loads. stateless (another character's copy, or
-- another faction's route) reads the title alone.
local function QuestState(questID, budget, stateless)
  local quest = Recollect.Facts.QuestInfo.Get(questID, budget)
  if not quest then return nil end
  local V, colors = Verdict(), Colors()
  if quest.title then Named("quest", questID, quest.title) end
  local title = quest.title and ("\"" .. quest.title .. "\"") or ("quest " .. questID)
  if stateless then return title, 1, nil, U.Colors.LIGHT_GRAY, quest end
  if quest.onQuest then return title, 5, "you're on it", colors[V.NEEDED], quest end
  if quest.repeatable then return title, 3, "repeatable", colors[V.USEFUL], quest end
  local done = Recollect.Facts.QuestInfo.Done(quest)
  local recurs = done and Recurs(questID)
  if recurs then return title, 3, recurs .. ", done for now", colors[V.USEFUL], quest end
  if done then return title, 4, "done", colors[V.DONE], quest end
  if done == false then return title, 2, "not done", colors[V.USEFUL], quest end
  return title, 1, "state unknown", U.Colors.LABEL_GRAY, quest
end

-- What a quest rewards: the shipped table's things with their states
-- (Facts.Chains), else the game's own quest data by name
local function RewardText(quest, questID, owner)
  local words = questID and Recollect.Facts.Chains.RewardWords(questID, owner)
  if words then return (words:gsub("^%l", string.upper)) end
  local reward = quest and (quest.rewards[1] or quest.choices[1])
  if not reward then return nil end
  local more = #quest.rewards + #quest.choices - 1
  return "Rewards " .. ItemName(reward.itemID) .. (more > 0 and (" and %d more"):format(more) or "")
end

-- A quest line, or nil while its quest loads; lines with the same mergeKey
-- become one (Merge)
local function QuestLine(lead, questID, withRewards, budget, stateless, owner)
  local title, rank, state, color, quest = QuestState(questID, budget, stateless)
  if not title then return nil end
  return { text = state and ("%s%s (%s)"):format(lead, title, state) or (lead .. title), color = color, rank = rank,
    tier = QUEST_TIER[rank], mergeKey = quest and quest.title and (lead .. quest.title) or nil,
    detail = withRewards and RewardText(quest, questID, owner) or nil }
end

-------------------------------------------------------------------------------
-- Vendors and currencies
-------------------------------------------------------------------------------
local function VendorText(verb, vendor)
  local zone = Recollect.Facts.Vendors.ZoneName(vendor.mapID) or ("map " .. vendor.mapID)
  vendor.zone = zone
  return ("%s a vendor in %s (%.1f, %.1f)"):format(verb, zone, vendor.x * 100, vendor.y * 100)
end

-- "A or B", the sellers a collection's source text names beside the cost, or nil
local function SourceSellers(sourceText, itemID)
  local sellers = Recollect.Facts.Vendors.FromSourceText(sourceText, "item", itemID)
  if #sellers == 0 then return nil end
  return table.concat(sellers, " or ")
end

local function Currency(currencyID)
  local ok, info = Try(Recollect.Purposes.client.GetCurrencyInfo, currencyID)
  if not ok or type(info) ~= "table" or type(info.name) ~= "string" then return nil end
  return info
end

-- The faction a currency grants reputation with, false for a currency that
-- is held, nil when unreadable
local function GrantedFaction(currencyID)
  local ok, factionID = Try(seams.GrantedFaction, currencyID)
  if not ok then return nil end
  return Recollect.Utilities.IsPositiveID(factionID) and factionID or false
end

local function FactionName(factionID)
  local ok, data = Try(seams.FactionData, factionID)
  if ok and type(data) == "table" and type(data.name) == "string" and data.name ~= "" then return data.name end
  return ("faction %d"):format(factionID)
end

-- A class or race tag's words: one or two names ("Mage only", "Blood Elf
-- and Orc only"), else "for some classes only" / "for some races only"
-- (more than two, or a name that can't be read)
local function NamedWords(tag)
  local seam = tag.kind == "class" and seams.ClassName or seams.RaceName
  local ids, names = tag.ids or {}, {}
  for _, id in ipairs(ids) do
    local ok, name = Try(seam, id)
    if ok and type(name) == "string" and name ~= "" then names[#names + 1] = name end
  end
  if #names > 0 and #names == #ids and #names <= 2 then
    table.sort(names)
    return table.concat(names, " and ") .. " only"
  end
  return tag.kind == "class" and "for some classes only" or "for some races only"
end

-- Display-only conditions (D34): a profession, a reputation standing, a
-- completed quest. ShownMet says whether the viewer meets one (true, false,
-- or nil: another character's row, or a read that fails); ShownWords words
-- it ("Engineering only", "Requires Revered with Cenarion Expedition",
-- 'After quest "The Call"'), with names read live
local function ProfessionLines(client)
  local ok, a, b, c, d, e = Try(client.GetProfessions)
  if not ok then return nil end
  local lines = {}
  for _, index in pairs({ a, b, c, d, e }) do
    local okInfo, _, _, _, _, _, _, line = Try(client.GetProfessionInfo, index)
    if not okInfo then return nil end
    if line then lines[line] = true end
  end
  return lines
end

local function ShownMet(tag, owner)
  if not (owner and owner.isViewer) then return nil end
  local client = Recollect.Purposes.client
  local ids = tag.ids or {}
  if tag.kind == "profession" then
    local lines = ProfessionLines(client)
    return lines and lines[ids[1]] == true or nil
  elseif tag.kind == "standing" then
    local ok, data = Try(seams.FactionData, ids[1])
    if not ok or type(data) ~= "table" or type(data.reaction) ~= "number" then return nil end
    return data.reaction >= (ids[2] or 0)
  elseif tag.kind == "quest" then
    local ok, done = Try(client.IsQuestFlaggedCompleted, ids[1])
    if not ok or type(done) ~= "boolean" then return nil end
    return done
  end
  return nil
end

local function SeamName(seam, id)
  local ok, name = Try(seam, id)
  return ok and type(name) == "string" and name ~= "" and name or nil
end

local function ShownWords(tag)
  local ids = tag.ids or {}
  local words
  if tag.kind == "profession" then
    local name = SeamName(seams.SkillLineName, ids[1])
    words = name and ("%s only"):format(name) or "For one profession only"
  elseif tag.kind == "standing" then
    local label = SeamName(seams.StandingLabel, ids[2] or 0)
    words = label and ("Requires %s with %s"):format(label, FactionName(ids[1])) or "Requires a reputation standing"
  else
    local title = SeamName(seams.QuestTitle, ids[1])
    words = title and ('After quest "%s"'):format(title) or ("After quest %d"):format(ids[1] or 0)
  end
  -- a name keeps its capitals after another tag; only the leading word lowers
  local after = words:match("^(For one profession only)$") and "for one profession only"
    or words:gsub("^Requires ", "requires "):gsub("^After ", "after ")
  return words, after
end

-- Tags(relation, applies, owner): the tags a route's line or row carries
-- (D19; display only, D34), each { kind, words, after, ids }, from
-- Relations.Conditions with class and race names read here. applies is
-- Relations.Applies' answer for the owner (or a quest's QuestApplies
-- answer, which another code of the quest may have decided) and chooses
-- which tags say why: "unavailable" "No longer obtainable"; nil or
-- "unknown", a condition the owner's record can't answer (a stored alt with
-- no race recorded), is worded as not recorded, as the checks word it
-- (PI-14), never as a mismatch; "other" names each condition missed
-- (faction, class, race), else "not for this character". Display-only
-- conditions (a profession, a standing, a completed quest; D34) follow, each
-- unless the viewer meets it, marked shown = true, whatever applies says
-- short of unavailable. An event route adds "During a holiday or event" for
-- every character, including one it serves. Empty when there is nothing to
-- say.
local OTHER_WORDS = "not for this character"
local function Tags(relation, applies, owner)
  local R = Relations()
  local conditions = R.Conditions(relation, owner)
  local out, event = {}, nil
  for _, tag in ipairs(conditions) do
    if tag.kind == "event" then event = tag end
  end
  if applies == "unavailable" then
    out[1] = R.ConditionTag("unavailable")
  elseif applies == nil or applies == "unknown" then
    out[1] = R.ConditionTag("unknown")
  elseif applies ~= true then
    for _, tag in ipairs(conditions) do
      if tag.kind == "faction" then
        out[#out + 1] = tag
      elseif tag.kind == "class" or tag.kind == "race" then
        tag.words = NamedWords(tag)
        tag.after = tag.words
        out[#out + 1] = tag
      end
    end
    if #out == 0 then out[1] = { kind = "other", words = OTHER_WORDS, after = OTHER_WORDS } end
  end
  if applies ~= "unavailable" then
    for _, tag in ipairs(conditions) do
      if (tag.kind == "profession" or tag.kind == "standing" or tag.kind == "quest") and ShownMet(tag, owner) ~= true then
        tag.words, tag.after = ShownWords(tag)
        tag.shown = true
        out[#out + 1] = tag
      end
    end
  end
  if event and applies ~= "unavailable" then out[#out + 1] = event end
  return out
end

-- Whether tags carry a display-only condition the owner misses (D34): the
-- line or row is dimmed, its state and every verdict unchanged
local function AnyShown(tags)
  for _, tag in ipairs(tags or {}) do
    if tag.shown then return true end
  end
  return false
end

-- The tags as one parenthetical's words ("Horde only, during a holiday or
-- event"), or nil for none; inline words every tag as it reads after
-- another, for a state inside a sentence ("during a holiday or event",
-- names keeping their capitals)
local function TagText(tags, inline)
  if not tags or #tags == 0 then return nil end
  local words = { inline and tags[1].after or tags[1].words }
  for i = 2, #tags do words[i] = tags[i].after end
  return table.concat(words, ", ")
end

-- "Horde only", "Mage only", "Blood Elf only", "During a holiday or event":
-- whom and when a route serves (Tags' words)
local function RestrictionText(relation, applies, owner)
  return TagText(Tags(relation, applies, owner)) or OTHER_WORDS
end

-- A line with its route's tags: a route that doesn't serve the owner reads
-- them in a closing parenthetical, gray and with the finished lines; an
-- event route that serves it keeps its state last, so the panel still colors
-- the state (AuditPanel.LineText colors only the closing parenthetical). A
-- display-only condition the owner misses (D34) is worded the same way and
-- dims the line (dimmed = true), which stays where it was: no verdict reads it
local function Tagged(line, relation, applies, owner)
  if applies == true and not (relation.flags and relation.flags.event) and not relation.shows then return line end
  local tags = Tags(relation, applies, owner)
  local words = TagText(tags)
  if not words then return line end
  line.tags = tags
  if applies ~= true then
    line.text = ("%s (%s)"):format(line.text, words)
    line.color, line.tier = U.Colors.LABEL_GRAY, TIER_CLOSED
    return line
  end
  local head, state = line.text:match("^(.-)%s*(%b())$")
  if head and line.color ~= U.Colors.LIGHT_GRAY and line.color ~= U.Colors.LABEL_GRAY then
    line.text = ("%s (%s) %s"):format(head, words, state)
  else
    line.text = ("%s (%s)"):format(line.text, words)
  end
  if AnyShown(tags) then line.color, line.dimmed = U.Colors.LABEL_GRAY, true end
  return line
end

-------------------------------------------------------------------------------
-- What an item buys: one entry per thing, { what, thing, count, state,
-- tier, group, sellerText, relation }, worded only when shown
-------------------------------------------------------------------------------
local STATE_WORDS = {
  toy = { have = "owned", missing = "not owned" },
  mount = { have = "owned", missing = "not owned", unavailable = "not for this character" },
  pet = { have = "collected", missing = "not collected" },
  decor = { have = "owned", missing = "not owned" },
  ensemble = { have = "collected", missing = "not collected" },
  heirloom = { have = "owned", missing = "not owned" },
  recipe = { have = "known", missing = "not known" },
  illusion = { have = "collected", missing = "not collected" },
}
local WHAT_LABEL = { toy = "Toy", mount = "Mount", pet = "Pet", decor = "Decor", ensemble = "Ensemble",
  heirloom = "Heirloom", recipe = "Recipe", illusion = "Illusion" }

local function EntryTier(state, restricted)
  if restricted then return TIER_CLOSED end
  if state == "missing" then return TIER_OPEN end
  if state == "have" or state == "unavailable" then return TIER_CLOSED end
  return TIER_INFO
end

-- Whether an entry of a seller group and tier can still show: Assemble shows
-- at most max lines, a group's entries of a tier in order, and a thing with
-- no seller as a group of its own in order, so past max of either, no entry
-- of it is shown (only counted in "and N more")
local NO_GROUP = {}
local function Room(taken, group, tier, max)
  local g = group or NO_GROUP
  local counts = taken[g]
  if not counts then
    counts = { 0, 0, 0 }
    taken[g] = counts
  end
  if counts[tier] >= max then return false end
  counts[tier] = counts[tier] + 1
  return true
end

-- Entries(itemID, decor, buys, buyApplies, owner, max): the entries that can
-- show, in order, and how many there are in all (Mark of Honor's
-- purchases, about 8,700, make a few dozen entries, not thousands)
local function Entries(itemID, decorRelations, buyRelations, buyApplies, owner, max, budget)
  local entries, seen, taken, total, followed = {}, {}, {}, 0, 0
  local function Add(entry)
    seen[entry.key] = true
    total = total + 1
    if Room(taken, entry.group, entry.tier, max) then entries[#entries + 1] = entry end
  end
  for _, relation in ipairs(decorRelations) do
    local owned, info = Recollect.Purposes.Registry.DecorOwned(relation.id)
    local state = owned ~= nil and (owned > 0 and "have" or "missing") or nil
    local seller = SourceSellers(info and info.sourceText, itemID)
    Add({ what = "decor", id = relation.id, count = relation.count or 1, state = state,
      key = "decor:" .. relation.id, sellerText = seller, group = seller and ("text:" .. seller) or nil, tier = EntryTier(state) })
  end
  local index = Recollect.Facts.Journals.Get()
  for _, target in ipairs((index and index[itemID]) or {}) do
    local state, name = Recollect.Purposes.Registry.CollectibleState(target, owner.faction, owner.isViewer)
    local seller = SourceSellers(Recollect.Facts.Journals.SourceText(target.kind, target.id), itemID)
    Add({ what = target.kind, id = target.id, name = name or (target.kind .. " " .. target.id), count = target.count or 1,
      state = state, key = target.kind .. ":" .. target.id, sellerText = seller, group = seller and ("text:" .. seller) or nil,
      tier = EntryTier(state) })
  end
  for i, relation in ipairs(buyRelations) do
    local thing = Recollect.Facts.Buys.Resolve(relation, owner)
    if thing and not seen[thing.key] then
      seen[thing.key] = true
      total = total + 1
      local restricted = buyApplies[i] ~= true
      -- a trade with no vendor named but its place (#map) groups by that place
      local group = relation.seller or (relation.vendors and #relation.vendors > 0 and ("@" .. table.concat(relation.vendors, ",")))
        or (relation.mapID and ("#" .. relation.mapID)) or nil
      local tier = EntryTier(thing.state, restricted)
      -- a plain item: what it leads to (contract rule 39), for the first few
      local chain
      if not thing.collectible and not restricted and followed < MAX_FOLLOW then
        followed = followed + 1
        chain = Recollect.Facts.Chains.Summary(thing.id, owner, budget, itemID)
        if chain and chain.best.state == "open" then tier = TIER_OPEN end
      end
      if Room(taken, group, tier, max) then
        entries[#entries + 1] = { what = thing.what, thing = thing, count = relation.count or 1, ofItem = itemID,
          state = not restricted and thing.state or nil, key = thing.key, relation = relation, restricted = restricted,
          applies = buyApplies[i], owner = owner, group = group, tier = tier, chain = chain }
      end
    end
  end
  return entries, total
end

-- The sellers the data names, worded ("A (Zone) or B (Zone)"), or nil
local function DataSellers(relation)
  local words = {}
  for _, npc in ipairs(relation.vendors or {}) do
    local seller = Recollect.Facts.Vendors.Describe(npc)
    if seller and #words < MAX_SELLERS then words[#words + 1] = seller end
    if #words >= MAX_SELLERS then break end
  end
  return #words > 0 and table.concat(words, " or ") or nil
end

-- A seller group's heading: "Buys at Zektar (Hallowfall)", or "Buys in
-- Blade's Edge Mountains" for a trade whose place the data gives with no
-- vendor named (item 9)
local function HeadingText(entry)
  local seller = entry.sellerText or (entry.relation and DataSellers(entry.relation))
  if seller then return "Buys at " .. seller end
  local mapID = entry.relation and entry.relation.mapID
  if mapID then return "Buys in " .. (Recollect.Facts.Vendors.ZoneName(mapID) or ("map " .. mapID)) end
  return "Buys at a vendor"
end

-- A price in words and what a purchase costs besides this item: the one
-- wording Facts.Chains gives the checks too (review F15); the names are
-- heard through the chains' namer while a line is built
UsedFor.GoldWords = function(copper) return Recollect.Facts.Chains.GoldWords(copper) end

-- A gold-only trade's price after its seller (the data's V code): " for 25
-- gold", ", 5 for 1 gold 50 silver" for a stack; "" for a seller with none
function UsedFor.PriceWords(relation)
  local price = relation and relation.price
  if not CobySuite_Recollect.Utilities.IsFiniteNumber(price) or price < 0 then return "" end
  local count = relation.count or 1
  if count > 1 then return (", %d for %s"):format(count, UsedFor.GoldWords(price)) end
  return " for " .. UsedFor.GoldWords(price)
end
function UsedFor.CostWords(relation, itemID) return Recollect.Facts.Chains.CostWords(relation, itemID) end

-- The first vendor of an entry's seller with a known place, for the waypoint
local function EntryVendor(entry)
  for _, npc in ipairs(entry.relation and entry.relation.vendors or {}) do
    local vendor = Recollect.Facts.Vendors.Position(npc)
    if vendor then
      vendor.zone = Recollect.Facts.Vendors.ZoneName(vendor.mapID) or ("map " .. vendor.mapID)
      return vendor
    end
  end
  return nil
end

-- One thing it buys as a line: under its seller's heading "Toy: X for 200
-- (not owned)", standing alone "Buys the toy X for 200 (not owned)"
local function BuyLine(entry, grouped)
  local V, colors = Verdict(), Colors()
  local label = WHAT_LABEL[entry.what]
  local name
  if entry.name then
    name = Named(entry.what, entry.id, entry.name)
  elseif entry.thing then
    name = Recollect.Facts.Chains.ThingNamed(entry.thing, Recollect.Facts.Buys.Name(entry.thing))
  end
  name = name or (entry.what == "item" and ("item " .. (entry.thing and entry.thing.id or "?")))
    or ("%s %s"):format(entry.what, entry.thing and entry.thing.id or (entry.id or "?"))
  if entry.what == "decor" and not entry.thing then name = ItemName(entry.id) end
  local cost = ("%d"):format(entry.count) .. (entry.relation and UsedFor.CostWords(entry.relation, entry.ofItem) or "")
  local text
  if grouped then
    text = ("%s%s for %s"):format(label and (label .. ": ") or "", name, cost)
  else
    text = label and ("Buys the %s %s for %s"):format(entry.what, name, cost) or ("Buys %s for %s"):format(name, cost)
  end
  local color = U.Colors.LIGHT_GRAY
  if entry.restricted then
    return Tagged({ text = text, color = U.Colors.LABEL_GRAY, tier = TIER_CLOSED, grouped = grouped }, entry.relation,
      entry.applies, entry.owner)
  end
  local words = entry.state and STATE_WORDS[entry.what] and STATE_WORDS[entry.what][entry.state]
  if not words and entry.state == "unassessed" then words = "known per character" end
  if words then text = ("%s (%s)"):format(text, words) end
  if entry.state == "missing" then
    color = colors[V.USEFUL]
  elseif entry.state == "have" or entry.state == "unavailable" then
    -- not for this character is out of reach: it goes with the owned ones
    color = colors[V.DONE]
  end
  local detail
  local best = entry.chain and entry.chain.best
  if best then
    detail = "Leads to " .. Recollect.Facts.Chains.Words(best.entry, nil, best.thing, best.quests)
    if best.state == "open" then color = colors[V.USEFUL] end
  end
  local line = { text = text, color = color, tier = entry.tier, grouped = grouped, detail = detail }
  return entry.relation and Tagged(line, entry.relation, true, entry.owner) or line
end

-------------------------------------------------------------------------------
-- One relation as a line; may add a waypoint to places. stateless leaves out
-- what only the logged-in character can be asked; nil when there is no
-- line, and true second when the line waits for its quest's data
-------------------------------------------------------------------------------
local QUEST_LEADS = { objective = "Objective of ", reward = "Reward from ", choice = "A choice reward from ",
  questItem = "Used in ", starts = "Starts " }
-- Quest lines that also say what the quest rewards
local WITH_REWARDS = { objective = true, questItem = true, starts = true }
local MAX_HELD = 2   -- items an opened object's line names

-- An achievement's line: the game's criterion ("4 of 30") or AllTheThings'
-- requirement ("needs 250")
local function AchievementLine(a, id, needs)
  local V, colors = Verdict(), Colors()
  if not a then return { text = ("Counts toward achievement %d"):format(id), color = U.Colors.LABEL_GRAY } end
  Named("achievement", id, a.name)
  local state, color, tier
  if a.earned then
    state, color, tier = "earned", colors[V.DONE], TIER_CLOSED
  elseif a.criterionDone then
    state, color, tier = "that part done", colors[V.DONE], TIER_CLOSED
  elseif type(a.required) == "number" and a.required > 1 and type(a.quantity) == "number" then
    state, color, tier = ("%d of %d"):format(a.quantity, a.required), colors[V.NEEDED], TIER_OPEN
  elseif needs and needs > 1 then
    state, color, tier = ("needs %d; not earned"):format(needs), colors[V.NEEDED], TIER_OPEN
  else
    state, color, tier = "not earned", colors[V.NEEDED], TIER_OPEN
  end
  return { text = ("Counts toward \"%s\" (%s)"):format(a.name, state), color = color, tier = tier }
end

-- "Reward from the achievement "Treasures of Voidstorm" (3 of 5 done)": an
-- achievement whose reward text names the item, with its progress
local function AchievementRewardLine(relation)
  local A = Recollect.Facts.Achievements
  local progress = A.Progress(relation.id)
  if not progress then return { text = ("Reward from achievement %d"):format(relation.id), color = U.Colors.LABEL_GRAY } end
  local words, open = A.ProgressWords(progress)
  local colors, V = Colors(), Verdict()
  Named("achievement", relation.id, progress.name)
  return { text = ("Reward from the achievement \"%s\" (%s)"):format(progress.name, words),
    color = open and colors[V.USEFUL] or (open == false and colors[V.DONE]) or U.Colors.LIGHT_GRAY,
    tier = open and TIER_OPEN or (open == false and TIER_CLOSED) or nil }
end

-- A criterion AllTheThings only links the item to: named, never a need
-- (CR-07: the item's role in it isn't established)
local function LinkedLine(relation)
  local a = Recollect.Facts.Achievements.Get(relation.id, relation.criteria)
  if not a then return nil end
  local text = ("Linked to \"%s\""):format(Named("achievement", relation.id, a.name))
  if a.earned then text = text .. " (earned)" end
  return { text = text, color = a.earned and Colors()[Verdict().DONE] or U.Colors.LIGHT_GRAY,
    tier = a.earned and TIER_CLOSED or TIER_INFO }
end

-- Every link of one achievement as one line (Black Claw of Sethe links to
-- 72 parts of Advanced Husbandry): "Linked to "X" (3 of 72 done)", the
-- achievement's progress, and in the detail how many of the parts
-- AllTheThings links it to are still to do. Never a need (CR-07); the
-- criteria are read once (Achievements.Parts). stateless (another
-- character's copy) keeps a progress only when the achievement is
-- account-wide, since otherwise it is the logged-in character's.
local function LinkedGroupLine(achievementID, criteria, stateless, itemID)
  local A = Recollect.Facts.Achievements
  local V, colors = Verdict(), Colors()
  local progress = A.Progress(achievementID)
  if not progress then
    return { text = ("Linked to achievement %d (can't be read)"):format(achievementID), color = U.Colors.LABEL_GRAY,
      tier = TIER_INFO, unread = true }
  end
  local title = ("Linked to \"%s\""):format(Named("achievement", achievementID, progress.name))
  if stateless and progress.accountWide ~= true then
    return { text = title, color = U.Colors.LIGHT_GRAY, tier = TIER_INFO, achievement = progress.name }
  end
  local words = A.ProgressWords(progress)
  local text = ("%s (%s)"):format(title, words)
  if progress.earned then
    return { text = text, color = colors[V.DONE], tier = TIER_CLOSED, achievement = progress.name, earned = true }
  end
  local parts = A.Parts(achievementID, criteria, itemID)
  local many = #criteria > 1
  -- A part that failed to read, or wasn't found, is never done (review F14)
  local state = A.PartsState(parts)
  if state == nil then
    return { text = text, color = U.Colors.LIGHT_GRAY, tier = TIER_INFO, achievement = progress.name,
      detail = "Which part AllTheThings links it to can't be read" }
  end
  local open = parts.found - parts.done
  local detail
  if state == "open" then
    detail = many and ("AllTheThings links it to %d of its parts; %d not done yet"):format(parts.found, open)
      or "AllTheThings links it to a part not done yet"
  else
    detail = many and ("AllTheThings links it to %d of its parts, all done"):format(parts.found)
      or "AllTheThings links it to a part that's done"
  end
  if state == "open" then
    return { text = text, color = colors[V.USEFUL], tier = TIER_OPEN, detail = detail, achievement = progress.name }
  end
  return { text = text, color = colors[V.DONE], tier = TIER_CLOSED, detail = detail, achievement = progress.name }
end

-- The linked relations that serve the owner, grouped by achievement in
-- their order, as lines. Achievements of one name (Advanced Husbandry is
-- 9539 and 9705, one per faction, sharing their criteria) are one line, as
-- quests of one title are: the earned one, else the first
local function LinkedLines(relations, stateless, itemID)
  local order, byAchievement, lines = {}, {}, {}
  for _, relation in ipairs(relations) do
    local list = byAchievement[relation.id]
    if not list then
      list = {}
      byAchievement[relation.id] = list
      order[#order + 1] = relation.id
    end
    list[#list + 1] = relation.criteria
  end
  local byName = {}
  for _, achievementID in ipairs(order) do
    local line = Build(LinkedGroupLine, achievementID, byAchievement[achievementID], stateless, itemID)
    local name = type(line) == "table" and line.achievement or nil
    local kept = name and byName[name]
    if not kept then
      lines[#lines + 1] = line
      if name then byName[name] = #lines end
    elseif line.earned and not lines[kept].earned then
      lines[kept] = line
    end
  end
  return lines
end

-- What a key opens: "Opens a treasure in Zone (x, y) (not looted)", holding
-- what; "Used at a spot in Zone (x, y)" for an object that holds nothing.
-- One that takes several ("with 1000") says how many you have.
local function OpensLine(relation, places, stateless, itemID)
  local object = Recollect.Facts.Vendors.Object(relation.id)
  if not object then return nil end
  local V, colors = Verdict(), Colors()
  local treasure = #object.contents > 0
  local where, place
  if object.mapID then
    local zone = Recollect.Facts.Vendors.ZoneName(object.mapID) or ("map " .. object.mapID)
    where = ("%s (%.1f, %.1f)"):format(zone, object.x * 100, object.y * 100)
    place = { mapID = object.mapID, x = object.x, y = object.y, zone = zone, what = treasure and "the treasure" or "the spot" }
    places[#places + 1] = place
  end
  local text
  if treasure then
    text = where and ("Opens a treasure in %s"):format(where) or "Opens a treasure"
  else
    text = where and ("Used at a spot in %s"):format(where) or "Used at a spot"
  end
  local takes = (relation.count or 1) > 1 and relation.count or nil
  if takes then text = ("%s with %d"):format(text, takes) end
  local color, tier = U.Colors.LIGHT_GRAY, nil
  if object.questID and not stateless and Recollect.Facts.Ready.Quests() then
    local ok, done = Try(Recollect.Purposes.client.IsQuestFlaggedCompleted, object.questID)
    if ok and done == true then
      text, color, tier = text .. (treasure and " (looted)" or " (done)"), colors[V.DONE], TIER_CLOSED
    elseif ok and done == false then
      text, color, tier = text .. (treasure and " (not looted)" or " (not done)"), colors[V.USEFUL], TIER_OPEN
    end
  end
  local detail
  if treasure then
    local names = {}
    for i = 1, math.min(#object.contents, MAX_HELD) do names[i] = ItemName(object.contents[i]) end
    local more = #object.contents - #names
    detail = "Holds " .. table.concat(names, ", ") .. (more > 0 and (" and %d more"):format(more) or "")
  end
  local have = takes and not stateless and itemID and Owned(itemID) or nil
  if have then
    detail = ("You have %d of the %d it takes.%s"):format(have, takes, detail and (" " .. detail) or "")
  end
  return { text = text, color = color, tier = tier, detail = detail, place = place }
end

local function MakesLine(relation, stateless)
  local colors, V = Colors(), Verdict()
  if relation.unresolved then
    return { text = ("Combines %d of these; what they make is unconfirmed"):format(relation.count or 1), color = colors[V.USE] }
  end
  local made = not stateless and Owned(relation.id) or nil
  local have = made and (made > 0 and ("you have %d"):format(made) or "you have none yet")
  local text = ("Makes %s from %d"):format(ItemName(relation.id), relation.count or 1)
  return { text = have and ("%s (%s)"):format(text, have) or text, color = colors[V.USE] }
end

-- "Combines with the Reinforced Amani Haft and Toughened Amani Leather Wrap
-- into Amani Warrior's Spear (you have 1 of the 3 parts)": one of several
-- different parts (Purposes.Parts says the same in its reason)
local function PartOfLine(relation, stateless, itemID)
  local Parts = Recollect.Purposes.Parts
  local others, own = {}, nil
  for _, part in ipairs(relation.parts) do
    if part.itemID == itemID then
      own = part
    else
      Named("item", part.itemID, Recollect.Facts.Item.Name(part.itemID))
      others[#others + 1] = Parts.PartWords(part)
    end
  end
  local text = ("Combines %swith %s into %s"):format(own and own.count > 1 and (own.count .. " of it ") or "",
    Parts.Join(others), ItemName(relation.id))
  local held, readable = 0, not stateless
  for _, part in ipairs(readable and relation.parts or {}) do
    local have = Owned(part.itemID)
    if have == nil then readable = false break end
    if have >= part.count then held = held + 1 end
  end
  if readable then text = ("%s (you have %d of the %d parts)"):format(text, held, #relation.parts) end
  local open = readable and held < #relation.parts
  return { text = text, color = Colors()[Verdict().USE], tier = open and TIER_OPEN or nil }
end

-- How many of a currency the Use line says using the item gives (English
-- clients: Purposes.UseEffect.GainCount, a number beside the currency's
-- name after a verb of gaining), or nil
local function UseGain(tip, name)
  local UseEffect = Recollect.Purposes.UseEffect
  if type(tip) ~= "table" or type(tip.useText) ~= "string" or not UseEffect then return nil end
  if not Recollect.Purposes.Registry.EnglishClient() then return nil end
  local ok, count = pcall(UseEffect.GainCount, tip.useText, name)
  return ok and type(count) == "number" and count > 0 and count or nil
end

local function CurrencyLine(relation, places, stateless, tip)
  local colors, V = Colors(), Verdict()
  local factionID = GrantedFaction(relation.id)
  if factionID == nil then return nil end
  if factionID then return { text = "Grants reputation with " .. FactionName(factionID), color = U.Colors.LIGHT_GRAY } end
  local info = Currency(relation.id)
  if not info then return nil end
  local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber
  local quantity = not stateless and IsFiniteNumber(info.quantity) and info.quantity or nil
  -- "Worth 35 Reservoir Anima (you have 1200 Reservoir Anima)" when the data
  -- says how many it gives; "Using it gives 48 Cataloged Research (you have
  -- 0 Cataloged Research)" when the Use line does (items 7, 8); the count
  -- names the currency, never the item; at the cap, it says so
  local text
  local held = ""
  if quantity then
    local capped = IsFiniteNumber(info.maxQuantity) and info.maxQuantity > 0 and quantity >= info.maxQuantity
    held = (" (you have %d %s%s)"):format(quantity, info.name, capped and ", the most you can hold" or "")
  end
  Named("currency", relation.id, info.name, info.quality)
  local gain = not (relation.count and relation.count > 0) and UseGain(tip, info.name) or nil
  if relation.count and relation.count > 0 then
    text = ("Worth %d %s%s"):format(relation.count, info.name, held)
  elseif gain then
    text = ("Using it gives %d %s%s"):format(gain, info.name, held)
  else
    text = ("Currency: %s%s"):format(info.name, held)
  end
  local line = { text = text, color = colors[V.USEFUL] }
  local plain = type(info.description) == "string" and U.StripColors(info.description):gsub("|n", " ") or ""
  local desc = plain ~= "" and Cut(plain) or nil
  local vendor = Recollect.Facts.Vendors.ForCurrency(relation.id)[1]
  if vendor then
    places[#places + 1] = vendor
    desc = (desc and (desc .. " ") or "") .. VendorText("Spent at", vendor) .. "."
  end
  line.detail = desc
  line.place = vendor
  return line
end

-- "Crafted by Blacksmithing: Spellbreaker's Blade (you know it)": a recipe
-- the Lab read makes this item
local function SkillName(skillLine)
  local ok, name = Try(seams.SkillLineName, skillLine)
  return ok and type(name) == "string" and name ~= "" and name or nil
end

local function CraftedLine(relation, stateless)
  local recipe = Relations().Recipe(relation.id)
  local profession = recipe and recipe.skillLine and recipe.skillLine > 0 and SkillName(recipe.skillLine) or nil
  local ok, name = Try(seams.SpellName, relation.id)
  name = ok and type(name) == "string" and name ~= "" and Named("spell", relation.id, name) or ("recipe " .. relation.id)
  local text = profession and ("Crafted by %s: %s"):format(profession, name) or ("Crafted with the recipe " .. name)
  if not stateless then
    local known = Recollect.Facts.Buys.RecipeKnown(relation.id)
    if known == true then text = text .. " (you know it)" end
  end
  return { text = text, color = U.Colors.LIGHT_GRAY }
end

local function TeachesLine(relation, stateless)
  local ok, name = Try(seams.SpellName, relation.id)
  name = ok and type(name) == "string" and name ~= "" and Named("spell", relation.id, name) or ("recipe " .. relation.id)
  local text, color, tier = "Teaches " .. name, U.Colors.LIGHT_GRAY, nil
  if not stateless then
    local known = Recollect.Facts.Buys.RecipeKnown(relation.id)
    if known == true then
      text, color, tier = text .. " (you know it)", Colors()[Verdict().DONE], TIER_CLOSED
    elseif known == false then
      text, color, tier = text .. " (you don't know it)", Colors()[Verdict().USEFUL], TIER_OPEN
    end
  end
  return { text = text, color = color, tier = tier }
end

-------------------------------------------------------------------------------
-- Sources of data format 4: the Encounter Journal's loot, a renown reward,
-- the Black Market Auction House and the Trading Post. Names are read live;
-- the renown only on the logged-in character's copy (stateless: another
-- character's, or a route that doesn't serve the owner), never assumed to
-- be account-wide
-------------------------------------------------------------------------------
local BLACK_MARKET_TEXT = "Sometimes offered on the Black Market Auction House"
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
  "November", "December" }

-- "March 2025" for 202503; nil for 0 (not known) or a month that isn't one
local function MonthWords(yyyymm)
  if not Recollect.Utilities.IsPositiveID(yyyymm) or yyyymm % 1 ~= 0 then return nil end
  local year, month = math.floor(yyyymm / 100), yyyymm % 100
  if year < 2000 or not MONTHS[month] then return nil end
  return ("%s %d"):format(MONTHS[month], year)
end

local function TradingPostText(yyyymm)
  local month = MonthWords(yyyymm)
  return month and ("Offered at the Trading Post (%s)"):format(month) or "Offered at the Trading Post"
end

-- Renown(factionID, level, readState): the owner's renown with a major
-- faction against a reward's level: "reached" or "short" with the renown
-- now, "unread" when it can't be read, nil when readState is false; then
-- the faction's name (read live) and its data (textureKit, for an icon)
local function Renown(factionID, level, readState)
  local IsSecret = Recollect.Utilities.IsSecret
  local ok, data = Try(seams.MajorFactionData, factionID)
  data = ok and type(data) == "table" and data or nil
  local name = data and data.name
  if IsSecret(name) or type(name) ~= "string" or name == "" then name = FactionName(factionID) end
  if not readState then return nil, name, nil, data end
  local now = data and data.renownLevel
  if IsSecret(now) or not CobySuite_Recollect.Utilities.IsFiniteNumber(now) or type(level) ~= "number" then
    return "unread", name, nil, data
  end
  return now >= level and "reached" or "short", name, now, data
end

-- "Renown 12 with Council of Dornogal (you're at 7)"
local function RenownLine(relation, stateless)
  local level = relation.level or 0
  local state, name, now = Renown(relation.id, level, not stateless)
  local text = ("Renown %d with %s"):format(level, name)
  local V, colors = Verdict(), Colors()
  if state == "reached" then return { text = text .. " (reached)", color = colors[V.DONE], tier = TIER_CLOSED } end
  if state == "short" then
    return { text = ("%s (you're at %d)"):format(text, now), color = colors[V.USEFUL], tier = TIER_OPEN }
  end
  if state == "unread" then
    return { text = text .. " (your renown can't be read)", color = U.Colors.LABEL_GRAY, tier = TIER_INFO }
  end
  return { text = text, color = U.Colors.LIGHT_GRAY }
end

-- "Drops from Sylvanas Windrunner in Sanctum of Domination (Encounter
-- Journal)", the boss's name a journal link when the journal gives one; nil
-- when the journal can't name the encounter
local function JournalLine(relation)
  local encounter = Recollect.Facts.Vendors.Encounter(relation.id)
  if not encounter then return nil end
  local boss = encounter.link and Named("encounter", relation.id, encounter.name) or encounter.name
  local text = encounter.instance and ("Drops from %s in %s, per the Encounter Journal"):format(boss, encounter.instance)
    or ("Drops from %s, per the Encounter Journal"):format(boss)
  return { text = text, color = U.Colors.LIGHT_GRAY }
end

local NEW_SOURCES = {
  journalDrop = JournalLine,
  renownReward = RenownLine,
  blackMarket = function() return { text = BLACK_MARKET_TEXT, color = U.Colors.LIGHT_GRAY } end,
  tradingPost = function(relation) return { text = TradingPostText(relation.id), color = U.Colors.LIGHT_GRAY } end,
}

local function Line(relation, places, budget, stateless, itemID, owner, tip)
  local kind = relation.kind
  if NEW_SOURCES[kind] then return NEW_SOURCES[kind](relation, stateless) end
  if QUEST_LEADS[kind] then
    local line = QuestLine(QUEST_LEADS[kind], relation.id, WITH_REWARDS[kind], budget, stateless, owner)
    return line, line == nil
  end
  if kind == "achievementReward" then return AchievementRewardLine(relation) end
  if kind == "opens" then return OpensLine(relation, places, stateless, itemID) end
  if kind == "usedAt" then
    local who, npc = Recollect.Facts.Vendors.Describe(relation.id, "an NPC")
    if not who then return nil end
    if npc then
      npc.what = "the NPC"
      places[#places + 1] = npc
    end
    local takes = (relation.count or 1) > 1 and (" with %d"):format(relation.count) or ""
    return { text = "Used at " .. who .. takes, color = U.Colors.LIGHT_GRAY, place = npc }
  end
  if kind == "soldBy" then
    local seller, vendor = Recollect.Facts.Vendors.Describe(relation.id)
    if not seller then return nil end
    if vendor then places[#places + 1] = vendor end
    return { text = "Sold by " .. seller .. UsedFor.PriceWords(relation), color = U.Colors.LIGHT_GRAY, place = vendor }
  end
  if kind == "dropsFrom" then
    -- "Name (Zone)", or "a creature in Zone (x, y)" until its name is read
    local who, npc = Recollect.Facts.Vendors.Describe(relation.id, "a creature")
    if not who then return nil end
    if npc then
      npc.what = "the creature"
      places[#places + 1] = npc
    end
    return { text = "Drops from " .. who, color = U.Colors.LIGHT_GRAY, place = npc }
  end
  if kind == "zoneDrop" then
    if relation.id == 0 then return { text = "World drop: any enemy can drop it", color = U.Colors.LIGHT_GRAY } end
    local zone = Recollect.Facts.Vendors.ZoneName(relation.id)
    return zone and { text = "Drops from enemies in " .. zone, color = U.Colors.LIGHT_GRAY } or nil
  end
  if kind == "craftedBy" then return CraftedLine(relation, stateless) end
  if kind == "foundIn" then
    local object = Recollect.Facts.Vendors.Object(relation.id)
    local zone = object and object.mapID and Recollect.Facts.Vendors.ZoneName(object.mapID)
    -- a chest, a node or a spot on the ground: the data doesn't say which
    if not zone then return { text = "Found at a spot in the world", color = U.Colors.LIGHT_GRAY } end
    local place = { mapID = object.mapID, x = object.x, y = object.y, zone = zone, what = "the spot" }
    places[#places + 1] = place
    return { text = ("Found at a spot in %s (%.1f, %.1f)"):format(zone, object.x * 100, object.y * 100),
      color = U.Colors.LIGHT_GRAY, place = place }
  end
  if kind == "criterion" then
    return AchievementLine(Recollect.Facts.Achievements.Get(relation.id, relation.criteria), relation.id)
  end
  if kind == "linked" then return LinkedLine(relation) end
  -- The count after the other item's name is of that item, never of this one
  if kind == "makes" then return MakesLine(relation, stateless) end
  if kind == "partOf" then return PartOfLine(relation, stateless, itemID) end
  if kind == "madeFrom" then
    local have = not stateless and Owned(relation.id) or nil
    local text = ("Made from %d %s"):format(relation.count or 1, ItemName(relation.id))
    return { text = have and ("%s (you have %d of those)"):format(text, have) or text, color = U.Colors.LIGHT_GRAY }
  end
  if kind == "recipeFor" then return { text = "Teaches how to make " .. ItemName(relation.id), color = U.Colors.LIGHT_GRAY } end
  if kind == "teaches" then return TeachesLine(relation, stateless) end
  if kind == "taughtBy" then return { text = "Crafted with " .. ItemName(relation.id), color = U.Colors.LIGHT_GRAY } end
  if kind == "currency" then return CurrencyLine(relation, places, stateless, tip) end
  return nil
end

-------------------------------------------------------------------------------
-- An older expansion's system (item 5, Purposes.Legacy.System: a Runecarving
-- memory, a Heart of Azeroth essence, an Ashjra'kamas upgrade): what the
-- system was, and in the detail whether it still does anything, with the
-- page that says so. English clients only (the system is named from the Use
-- text); nil when no system is named or the text hasn't loaded. "(you know
-- it)" only for a system the item teaches, on the logged-in character's
-- tooltip.
-------------------------------------------------------------------------------
local function Capital(text) return (text:gsub("^%l", string.upper)) end

local function LegacyLine(itemID, facts, tip, stateless)
  local Legacy = Recollect.Purposes.Legacy
  if not Legacy or type(Legacy.System) ~= "function" then return nil end
  local ok, system = pcall(Legacy.System, itemID, facts, tip)
  if not ok or type(system) ~= "table" or type(system.what) ~= "string" then return nil end
  local V, colors = Verdict(), Colors()
  local text = Capital(system.what)
  if system.power then text = ("%s (%s)"):format(text, system.power) end
  local color, tier = U.Colors.LIGHT_GRAY, TIER_INFO
  if system.learn and not stateless and type(tip) == "table" and tip.known then
    text, color, tier = text .. " (you know it)", colors[V.DONE], TIER_CLOSED
  elseif system.still == false then
    color, tier = colors[V.OUTDATED], TIER_CLOSED
  end
  local detail = type(system.stillWords) == "string" and (Capital(system.stillWords) .. ".") or nil
  return { text = text, color = color, tier = tier, detail = detail, legacy = true }
end

-------------------------------------------------------------------------------
-- Recipes: this character's index, what other characters' scans recorded
-- (F-02), and the recipes the Lab read (G-01)
-------------------------------------------------------------------------------
-- "Used in 17 of your recipes (8 Blacksmithing, 9 Leatherworking)" from the
-- recipe index (Facts.Recipes), or nil
local function RecipeLine(itemID)
  local ok, index = pcall(Recollect.Facts.Recipes.ForCharacter)
  local byName = ok and index and index.uses and index.uses[itemID]
  if not byName or not next(byName) then return nil end
  local names, total, parts = {}, 0, {}
  for name, n in pairs(byName) do
    names[#names + 1] = name
    total = total + n
  end
  table.sort(names)
  for _, name in ipairs(names) do parts[#parts + 1] = ("%d %s"):format(byName[name], name) end
  return { text = ("Used in %d of your %s (%s)"):format(total, total == 1 and "recipe" or "recipes", table.concat(parts, ", ")),
    color = Colors()[Verdict().USEFUL] }
end

-- "Tanklite's Leatherworking scan (Sep 24) recorded 9 recipes using this":
-- historical, never a claim about now (CR-09)
local function RecordedLines(itemID)
  local lines = {}
  local ok, list = pcall(Recollect.Facts.Recipes.RecordedByOthers, itemID)
  for _, r in ipairs(ok and list or {}) do
    lines[#lines + 1] = { text = ("%s's %s scan (%s) recorded %d %s using this"):format(r.name, r.profession,
      r.scannedAt and date("%b %d", r.scannedAt) or "?", r.count, r.count == 1 and "recipe" or "recipes"),
      color = U.Colors.LIGHT_GRAY, tier = TIER_INFO, recorded = true }
  end
  return lines
end

local SkillLineName = SkillName

-- The recipes the Lab read that take it (g codes): one line per profession,
-- or every recipe in full
local function ReagentLines(relations, full)
  local byProfession, order, lines = {}, {}, {}
  for _, relation in ipairs(relations) do
    local recipe = Relations().Recipe(relation.id)
    local skill = recipe and recipe.skillLine or 0
    if not byProfession[skill] then
      byProfession[skill] = {}
      order[#order + 1] = skill
    end
    local list = byProfession[skill]
    list[#list + 1] = { relation = relation, recipe = recipe }
  end
  table.sort(order)
  for _, skill in ipairs(order) do
    local list = byProfession[skill]
    local profession = skill > 0 and SkillLineName(skill) or nil
    if full then
      for _, r in ipairs(list) do
        local ok, name = Try(seams.SpellName, r.relation.id)
        local product = r.recipe and r.recipe.product and r.recipe.product > 0 and ItemName(r.recipe.product) or nil
        lines[#lines + 1] = { text = ("Reagent (%d) in %s%s"):format(r.relation.count or 1,
          ok and type(name) == "string" and name or ("recipe " .. r.relation.id), product and (", which makes " .. product) or ""),
          color = U.Colors.LIGHT_GRAY }
      end
    else
      -- reagentTotal: every profession's count together, which a headline
      -- names instead of one profession's (item 11)
      lines[#lines + 1] = { text = ("Reagent in %d %s%s"):format(#list, profession and (profession .. " ") or "",
        #list == 1 and "recipe" or "recipes"), color = U.Colors.LIGHT_GRAY, reagentTotal = #relations }
    end
  end
  return lines
end

-------------------------------------------------------------------------------
-- Assembly
-------------------------------------------------------------------------------
-- Quest lines of the same title as one, keeping the highest state
local function Merge(lines)
  local out, byKey = {}, {}
  for _, line in ipairs(lines) do
    local kept = line.mergeKey and byKey[line.mergeKey]
    if not kept then
      out[#out + 1] = line
      if line.mergeKey then byKey[line.mergeKey] = line end
    elseif (line.rank or 0) > (kept.rank or 0) then
      for k, v in pairs(line) do kept[k] = v end
    end
  end
  return out
end

-- A note line ("and 3 more", "2 more still being checked"): no use of its own
local function Note(text)
  return { text = text, color = U.Colors.LABEL_GRAY, note = true }
end

-- Every line ordered by tier, stable: in each tier the non-buy lines (a
-- quest you're on first), then what it buys, a seller's lines together in
-- the order its first line had. Only the first max lines are worded
-- (headings don't count), then the notes; places gets each shown buy
-- group's vendor for the waypoint. One pass over the entries, no sort: an
-- item can buy thousands of things (BA-11).
local function Assemble(lines, entries, max, pending, places, total)
  local lineTiers = { {}, {}, {} }
  for _, line in ipairs(lines) do
    local tier = lineTiers[line.tier or TIER_INFO]
    if line.rank == 5 then
      tier.on = (tier.on or 0) + 1
      table.insert(tier, tier.on, line)
    else
      tier[#tier + 1] = line
    end
  end
  local groups, byGroup = {}, {}   -- seller groups in the order they first appear
  for i, entry in ipairs(entries) do
    local g = entry.group or i       -- a thing with no seller named is its own group
    local slot = byGroup[g]
    if not slot then
      slot = { {}, {}, {} }
      byGroup[g] = slot
      groups[#groups + 1] = g
    end
    local list = slot[entry.tier or TIER_INFO]
    list[#list + 1] = entry
  end
  local out, shown, vendorAdded = {}, 0, {}
  for tier = TIER_OPEN, TIER_CLOSED do
    for _, line in ipairs(lineTiers[tier]) do
      if shown >= max then break end
      out[#out + 1] = line
      shown = shown + 1
    end
    for _, g in ipairs(groups) do
      local list = byGroup[g][tier]
      for i, entry in ipairs(list) do
        if shown >= max then break end
        if i == 1 and entry.group then
          local vendor = EntryVendor(entry)
          out[#out + 1] = { text = HeadingText(entry), header = true, color = U.Colors.LIGHT_GRAY, place = vendor }
          -- a route for another faction or class gives the waypoint no place
          if vendor and not entry.restricted and not vendorAdded[entry.group] then
            vendorAdded[entry.group] = true
            places[#places + 1] = vendor
          end
        end
        out[#out + 1] = Build(BuyLine, entry, entry.group ~= nil)
        shown = shown + 1
      end
      if shown >= max then break end
    end
  end
  local more = #lines + (total or #entries) - shown
  if more > 0 then out[#out + 1] = Note(("and %d more"):format(more)) end
  if pending > 0 then out[#out + 1] = Note(("%d more still being checked"):format(pending)) end
  return out
end

-- Quest relations read in-log first, so the request budget goes to them;
-- the states are kept by relation for the pass that words the lines
local QUEST_KINDS = QUEST_KIND

local function ReadQuestsFirst(relations, budget)
  local client = Recollect.Purposes.client
  for _, relation in ipairs(relations) do
    if QUEST_KINDS[relation.kind] then
      local ok, on = Try(client.IsOnQuest, relation.id)
      if ok and on == true then Recollect.Facts.QuestInfo.Get(relation.id, budget) end
    end
  end
end

-- How a route no longer in the game reads when its name can't be read now
local GONE_WORDS = { objective = "Objective of quest %d", questItem = "Used in quest %d", starts = "Starts quest %d",
  reward = "Reward from quest %d", choice = "A choice reward from quest %d", usedAt = "Used at a creature (NPC %d)",
  soldBy = "Sold by a vendor (NPC %d)", dropsFrom = "Drops from a creature (NPC %d)", opens = "Opens object %d",
  buysDecor = "Bought housing decor (item %d)", reagentOf = "A reagent of recipe %d", currency = "Named currency %d",
  linked = "Linked to achievement %d", foundIn = "Found in object %d", zoneDrop = "Drops in zone %d",
  craftedBy = "Crafted with recipe %d", partOf = "A part of item %d", achievementReward = "Reward from achievement %d",
  journalDrop = "Drops from a boss (encounter %d)", renownReward = "A renown reward of faction %d",
  blackMarket = BLACK_MARKET_TEXT, tradingPost = "Offered at the Trading Post" }

-- A route no longer in the game, worded for the pinned view
local function UnavailableLine(relation, budget)
  local text
  if relation.kind == "buys" and relation.thing == "a" then
    local a = Recollect.Facts.Achievements.Get(relation.id)
    text = ("Counted toward %s"):format(a and ("\"" .. a.name .. "\"") or ("achievement " .. relation.id))
  elseif relation.kind == "buys" then
    local thing = Recollect.Facts.Buys.Resolve(relation, { isViewer = false })
    local name = thing and (Recollect.Facts.Buys.Name(thing) or (thing.what .. " " .. thing.id)) or ("thing " .. relation.id)
    text = ("Bought %s for %d"):format(name, relation.count or 1)
  else
    local line = Build(Line, relation, {}, budget, true)
    text = line and line.text or (GONE_WORDS[relation.kind] or "%d"):format(relation.id or 0)
  end
  -- the x flag's tag, as the pinned view's rows word it (D19)
  local tag = Relations().ConditionTag("unavailable")
  return { text = ("%s (%s)"):format(text, tag.after), color = U.Colors.LABEL_GRAY, tier = TIER_CLOSED, tags = { tag } }
end

-- "Starts "Q" (not done)" for the quest the item starts, or nil while it loads
local function StarterLine(questID, budget, stateless, owner)
  local title, rank, state, color, quest = QuestState(questID, budget, stateless)
  if not title then return nil end
  return { text = state and ("Starts %s (%s)"):format(title, state) or ("Starts " .. title), color = color, rank = rank,
    tier = QUEST_TIER[rank], detail = RewardText(quest, questID, owner),
    mergeKey = quest and quest.title and ("Starts " .. quest.title) or nil }
end

-- The tasks of the running neighborhood endeavor that name the item
-- (Facts.Endeavors), one line each: open in the Useful color, done in the
-- done color, a state that can't be read gray. The endeavor's own words
-- name it: a task names the item, which doesn't say the item is spent.
local function EndeavorLines(itemID)
  local Endeavors = Recollect.Facts.Endeavors
  if not Endeavors or type(Endeavors.UsesOf) ~= "function" then return {} end
  local ok, uses = pcall(Endeavors.UsesOf, itemID)
  if not ok or type(uses) ~= "table" then return {} end
  local V, colors = Verdict(), Colors()
  local okGet, endeavor = pcall(Endeavors.Get)
  local progress = okGet and endeavor and Endeavors.ProgressWords(endeavor) or nil
  local out = {}
  for _, use in ipairs(uses) do
    local state, color, tier = use.progressText, U.Colors.LABEL_GRAY, TIER_INFO
    if use.done == false then
      color, tier = colors[V.USEFUL], TIER_OPEN
    elseif use.done == true then
      state, color, tier = "done", colors[V.DONE], TIER_CLOSED
    end
    if type(state) ~= "string" or state == "" then state = "state can't be read" end
    out[#out + 1] = { text = ("Named in the endeavor task \"%s\" (%s)"):format(tostring(use.taskName), state), color = color,
      tier = tier, detail = ("Neighborhood endeavor \"%s\"%s"):format(tostring(use.title), progress and (", at " .. progress) or "") }
  end
  return out
end

-- What the routes no longer in the game were, as one closing line: every
-- is true when no use of the item is left ("Every use Recollect knows is
-- gone from the game: it bought 55 things and was used in 1 quest"); nil
-- when none of them is a use
local GONE_PHRASES = {
  buys = { "bought %d thing", "bought %d things" },
  quests = { "was used in %d quest", "was used in %d quests" },
  opens = { "opened %d treasure", "opened %d treasures" },
  usedAt = { "was used at %d NPC", "was used at %d NPCs" },
  achievements = { "counted toward %d achievement", "counted toward %d achievements" },
  reagent = { "was a reagent in %d recipe", "was a reagent in %d recipes" },
  other = { "had %d other use", "had %d other uses" },
}
local GONE_ORDER = { "buys", "quests", "opens", "usedAt", "achievements", "reagent", "other" }
local GONE_GROUP = { objective = "quests", questItem = "quests", starts = "quests", opens = "opens", usedAt = "usedAt",
  criterion = "achievements", linked = "achievements", reagentOf = "reagent", buysDecor = "buys", buys = "buys" }

-- The group a removed use counts in, and the key that counts it once (nil: each counts)
local function GoneGroup(relation)
  local kind = relation.kind
  if kind == "buys" and relation.thing == "a" then return "achievements", nil end
  local group = GONE_GROUP[kind] or "other"
  if kind == "buys" then return group, "b" .. tostring(relation.thing) .. ":" .. tostring(relation.id) end
  if kind == "buysDecor" then return group, "d:" .. tostring(relation.id) end
  if group == "quests" then return group, "q:" .. tostring(relation.id) end
  return group, nil
end

local function GoneLine(unavailable, every)
  local SOURCE = Relations().SOURCE
  local counts, seen, any = {}, {}, false
  for _, relation in ipairs(unavailable) do
    if not SOURCE[relation.kind] then
      local group, key = GoneGroup(relation)
      if not key or not seen[key] then
        if key then seen[key] = true end
        counts[group] = (counts[group] or 0) + 1
        any = true
      end
    end
  end
  if not any then return nil end
  local parts = {}
  for _, group in ipairs(GONE_ORDER) do
    local n = counts[group]
    if n then parts[#parts + 1] = (n == 1 and GONE_PHRASES[group][1] or GONE_PHRASES[group][2]):format(n) end
  end
  local words = #parts > 1 and (table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]) or parts[1]
  local lead = every and "Every use Recollect knows is gone from the game: it " or "Also no longer in the game: it "
  return { text = lead .. words, color = Colors()[Verdict().OUTDATED], note = true, gone = true }
end

-- How many ways to get the item are no longer in the game
local function GoneSources(unavailable)
  local SOURCE, n = Relations().SOURCE, 0
  for _, relation in ipairs(unavailable) do
    if SOURCE[relation.kind] then n = n + 1 end
  end
  return n
end

-- "Can no longer be obtained (removed in patch 12.1.0)": the patch every
-- way to get it was removed in, once this client is at or past it; or nil
local function RemovedLine(itemID)
  local Season = Recollect.Purposes.Season
  if not Season or type(Season.RemovedIn) ~= "function" then return nil end
  local ok, patch = pcall(Season.RemovedIn, itemID)
  if not ok or not patch then return nil end
  return { text = ("Can no longer be obtained (removed in patch %s)"):format(Season.PatchText(patch)),
    color = Colors()[Verdict().OUTDATED], tier = TIER_CLOSED }
end

-- LiveUse(itemID, relations, owner, questApplies): whether any use the data
-- or a known use (Data.Uses) gives is still in the game, for this character
-- or another. "Every use is gone" is decided from these, never from the
-- lines drawn alone: a use whose line can't be built yet (an achievement
-- not read, a currency with no info) is still a use. questApplies is
-- Relations.QuestAppliesOf's answer for the relations.
function UsedFor.LiveUse(itemID, relations, owner, questApplies)
  local R = Relations()
  for _, relation in ipairs(relations or {}) do
    if not R.SOURCE[relation.kind] then
      local applies
      local forQuest = relation.id and questApplies and questApplies[relation.id]
      if forQuest and QUEST_KIND[relation.kind] then applies = forQuest else applies = R.Applies(relation, owner) end
      if applies ~= "unavailable" then return true end
    end
  end
  local KnownUse = Recollect.Purposes.KnownUse
  local ok, entries = pcall(KnownUse.EntriesFor, itemID)
  return not ok or (type(entries) == "table" and #entries > 0)
end

-- Whether any line among the uses says a use (not a heading or a note)
local function AnyUse(uses)
  for _, line in ipairs(uses) do
    if not line.note then return true end
  end
  return false
end

-- Lines(itemID, stack, owner, opts): uses, waypoint or nil, sources, extra
function UsedFor.Lines(itemID, stack, owner, opts)
  opts = opts or {}
  owner = owner or Recollect.Verdicts.Rows.Owner()
  local full = opts.full
  local stateless = not owner.isViewer
  local R = Relations()
  local budget = Recollect.Facts.QuestInfo.FrameBudget()
  local questApplies = R.QuestApplies(itemID, owner)
  local lines, sources, decor, buys, buyApplies, reagents, unavailable, linked = {}, {}, {}, {}, {}, {}, {}, {}
  -- places for the waypoint: what a key opens or an NPC it is used at and a
  -- currency's vendor (in the relations' order), then one that takes it, one
  -- it buys from, and last one that sells it
  local places, takingPlaces, sourcePlaces = {}, {}, {}
  local pending, pendingSources = 0, 0   -- quests still being read: uses, and where it comes from
  local relations = R.For(itemID)
  ReadQuestsFirst(relations, budget)
  local questID = stack and stack.quest and stack.quest.questID
  if Recollect.Utilities.IsPositiveID(questID) then
    local starter = Build(StarterLine, questID, budget, stateless, owner)
    if starter then lines[1] = starter else pending = pending + 1 end
  end
  for _, relation in ipairs(relations) do
    local kind = relation.kind
    local applies = R.Applies(relation, owner)
    -- a quest is what its least-serving code says (the dump's codes can lack ATT's conditions)
    local forQuest = relation.id and questApplies[relation.id]
    if forQuest and QUEST_KIND[kind] then
      if forQuest == "unknown" then applies = nil else applies = forQuest end
    end
    if applies == "unavailable" then
      unavailable[#unavailable + 1] = relation
    elseif kind == "buysDecor" then
      decor[#decor + 1] = relation
    elseif kind == "buys" and relation.thing == "a" then
      -- an achievement AllTheThings says it counts toward
      local line = Build(AchievementLine, Recollect.Facts.Achievements.Get(relation.id), relation.id, relation.count)
      if applies ~= true then
        local a = Recollect.Facts.Achievements.Get(relation.id)
        line = { text = a and ("Counts toward \"%s\""):format(a.name) or ("Counts toward achievement %d"):format(relation.id),
          links = line.links }
      end
      Tagged(line, relation, applies, owner)
      -- where it is spent, when the data gives the place but no vendor (item 9)
      if relation.mapID then
        line.detail = "Spent in " .. (Recollect.Facts.Vendors.ZoneName(relation.mapID) or ("map " .. relation.mapID))
      end
      lines[#lines + 1] = line
    elseif kind == "buys" then
      buys[#buys + 1] = relation
      buyApplies[#buys] = applies
    elseif kind == "reagentOf" then
      reagents[#reagents + 1] = relation
    elseif kind == "linked" and applies == true then
      linked[#linked + 1] = relation
    else
      local isSource = R.SOURCE[kind]
      local restricted = applies ~= true
      -- a route that doesn't serve this character gives the waypoint no place
      local into = restricted and {} or (isSource and sourcePlaces or places)
      local line, waiting = Build(Line, relation, into, budget, stateless or restricted, itemID, owner, opts.tip)
      if waiting then
        -- a reward still loading is where it comes from, never a use
        if isSource then pendingSources = pendingSources + 1 else pending = pending + 1 end
      elseif line then
        Tagged(line, relation, applies, owner)
        local into = isSource and sources or lines
        into[#into + 1] = line
      end
    end
  end
  Append(lines, LinkedLines(linked, stateless, itemID))
  local legacy = (opts.tip or opts.facts) and LegacyLine(itemID, opts.facts, opts.tip, stateless) or nil
  if legacy then lines[#lines + 1] = legacy end
  if owner.isViewer then
    local recipes = RecipeLine(itemID)
    if recipes then lines[#lines + 1] = recipes end
    Append(lines, EndeavorLines(itemID))   -- the neighborhood's endeavor is the logged-in character's
  end
  Append(lines, RecordedLines(itemID))
  Append(lines, ReagentLines(reagents, full))
  -- Vendors recorded in game that take the item itself, or sell it
  local Vendors = Recollect.Facts.Vendors
  local taking, selling = Vendors.ForCostItem(itemID)[1], Vendors.Selling(itemID)[1]
  if taking then
    takingPlaces[#takingPlaces + 1] = taking
    lines[#lines + 1] = { text = VendorText("Taken as payment by", taking), color = U.Colors.LIGHT_GRAY, place = taking }
  end
  if selling then
    sourcePlaces[#sourcePlaces + 1] = selling
    sources[#sources + 1] = { text = VendorText("Sold by", selling), color = U.Colors.LIGHT_GRAY, place = selling }
  end
  local buyPlaces = {}
  local max = full and FULL_LINES or MAX_LINES
  local entries, total = Entries(itemID, decor, buys, buyApplies, owner, max, budget)
  local uses = Assemble(Merge(lines), entries, max, pending, buyPlaces, total)
  local gone = GoneLine(unavailable, not AnyUse(uses) and pending == 0
    and not UsedFor.LiveUse(itemID, relations, owner, questApplies))
  if gone then uses[#uses + 1] = gone end
  Append(places, takingPlaces)
  Append(places, buyPlaces)
  Append(places, sourcePlaces)
  -- Where it comes from keeps the relations' order, then "and N more"
  local merged, comesFrom = Merge(sources), {}
  local maxSources = full and FULL_LINES or MAX_SOURCES
  for i = 1, math.min(#merged, maxSources) do comesFrom[i] = merged[i] end
  if #merged > maxSources then comesFrom[#comesFrom + 1] = Note(("and %d more"):format(#merged - maxSources)) end
  if pendingSources > 0 then comesFrom[#comesFrom + 1] = Note(("%d more still being checked"):format(pendingSources)) end
  local removed = RemovedLine(itemID)
  if removed then
    table.insert(comesFrom, 1, removed)
  else
    local goneSources = GoneSources(unavailable)
    if goneSources > 0 then
      comesFrom[#comesFrom + 1] = Note(("%d %s no longer in the game"):format(goneSources,
        goneSources == 1 and "way to get it is" or "ways to get it are"))
    end
  end
  local extra = { pending = pending, pendingSources = pendingSources, unavailable = {} }
  if full then
    local none = { left = 0 }
    for i = 1, math.min(#unavailable, FULL_LINES) do extra.unavailable[i] = Build(UnavailableLine, unavailable[i], none) end
    if #unavailable > FULL_LINES then extra.unavailable[#extra.unavailable + 1] = Note(("and %d more"):format(#unavailable - FULL_LINES)) end
  else
    extra.unavailableCount = #unavailable
  end
  return uses, places[1], comesFrom, extra
end

-------------------------------------------------------------------------------
-- Guide notes (Facts.Notes): informational, never a use line or a verdict
-------------------------------------------------------------------------------
-- The live state of what a note names: an achievement's progress, else a
-- quest's state ({ text, color }, "(state)" closing the text), or nil
local function NoteState(note, owner, budget)
  local V, colors = Verdict(), Colors()
  if note.achievement then
    local progress = Recollect.Facts.Achievements.Progress(note.achievement)
    if not progress then
      return { text = ("Achievement %d (can't be read)"):format(note.achievement), color = U.Colors.LABEL_GRAY }
    end
    local words, open = Recollect.Facts.Achievements.ProgressWords(progress)
    Named("achievement", note.achievement, progress.name)
    return { text = ("Achievement \"%s\" (%s)"):format(progress.name, words),
      color = open and colors[V.USEFUL] or (open == false and colors[V.DONE]) or U.Colors.LABEL_GRAY }
  end
  if note.quest then
    local title, _, state, color = QuestState(note.quest, budget, not owner.isViewer)
    if not title then return { text = ("Quest %d (still being checked)"):format(note.quest), color = U.Colors.LABEL_GRAY } end
    return { text = state and ("Quest %s (%s)"):format(title, state) or ("Quest " .. title), color = color }
  end
  return nil
end

-- NoteLines(itemID, owner): the item's guide notes as { text, details =
-- { "How many: ...", "Where: ...", "Comes from: ..." }, state = { text,
-- color, links } or nil, label ("Per method.gg; not confirmed in game
-- yet"), source, confirmed, note }, in Data/Notes.lua's order
function UsedFor.NoteLines(itemID, owner)
  owner = owner or Recollect.Verdicts.Rows.Owner()
  local out = {}
  local budget = Recollect.Facts.QuestInfo.FrameBudget()
  for _, note in ipairs(Recollect.Facts.Notes.For(itemID)) do
    local details = {}
    if note.howMany then details[#details + 1] = "How many: " .. note.howMany end
    if note.where then details[#details + 1] = "Where: " .. note.where end
    if note.from then details[#details + 1] = "Comes from: " .. note.from end
    local label = note.confirmed and ("Per %s; confirmed in game: %s"):format(note.source, note.confirmed)
      or ("Per %s; not confirmed in game yet"):format(note.source)
    out[#out + 1] = { text = note.text, details = details, state = Build(NoteState, note, owner, budget), label = label,
      source = note.source, confirmed = note.confirmed, note = note, color = U.Colors.LABEL_GRAY }
  end
  return out
end

-- What the pinned view's tables share with these lines (UI.DetailData), so a
-- row and a line never disagree about a state or its words
UsedFor.parts = {
  QuestState = QuestState, RestrictionText = RestrictionText, Tags = Tags, TagText = TagText, AnyShown = AnyShown,
  EntryTier = EntryTier,
  STATE_WORDS = STATE_WORDS,
  WHAT_LABEL = WHAT_LABEL, Currency = Currency, GrantedFaction = GrantedFaction, FactionName = FactionName,
  SourceSellers = SourceSellers, Owned = Owned, SkillLineName = SkillLineName, QUEST_KIND = QUEST_KIND,
  RewardText = RewardText, MAX_FOLLOW = MAX_FOLLOW,
  Renown = Renown, MonthWords = MonthWords, TradingPostText = TradingPostText, BLACK_MARKET_TEXT = BLACK_MARKET_TEXT,
  TIER_OPEN = TIER_OPEN, TIER_INFO = TIER_INFO, TIER_CLOSED = TIER_CLOSED,
  SpellName = function(spellID)
    local ok, name = Try(seams.SpellName, spellID)
    return ok and type(name) == "string" and name ~= "" and name or nil
  end,
}

UsedFor._test = { seams = seams }
