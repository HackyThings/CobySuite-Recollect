-------------------------------------------------------------------------------
-- UI.UsedFor: the audit panel's USED FOR and COMES FROM lines, one per thing
-- the item is linked to, each with its live state
--
--   USED FOR
--   Objective of "Light Repurposed" (you're on it)
--   Counts toward "Glory of the Ulduar Raider" (4 of 30)
--   Used in 17 of your recipes (8 Blacksmithing, 9 Leatherworking)
--   Opens a treasure in Zul'Aman (48.5, 25.8) (not looted)
--     Holds Arathi Lantern
--   Used at Hogger (Elwynn Forest)
--   Makes Shattered Fragments of Val'anyr from 30 (you have none yet)
--   Currency: Radiant Spark Dust (you have 12 Radiant Spark Dust)
--     Spent at a vendor in Silvermoon City (55.7, 65.9)
--   Buys at Fizz Alechux (Razorwind Shores) or Kay Stouthammer (...)   a heading
--   Decor: Brewfest Keg for 125 Brewfest Prize Token (not owned)
--   Mount: Spectral Steed for 165 Brewfest Prize Token (not owned)
--   Buys at Chef Dinaire (Hallowfall)
--   Darkroot Grippers for 5 Brewfest Prize Token and other costs
--     Leads to Phoenix Wishwing, a pet you don't have, through "Tale of
--     the Phoenix" (not done)
--   COMES FROM
--   Reward from "Pink Elekks On Parade" (not done)
--   Reward from the achievement "Treasures of Voidstorm" (3 of 5 done)
--   Sold by Innkeeper Farley (Elwynn Forest)
--   Sold by Sergeant Vornin (Silvermoon City) (Requires the achievements
--     "Void Response Team" (3 of 5 done) and "Ritual Site Disruptor" (earned))
--   Drops from Hogger
--   Found at a spot in Naigtal (22.9, 61.3)
--   Drops from enemies in Zul'Aman
--   Crafted by Blacksmithing: Spellbreaker's Blade
--   Listed in the Renown 12 rewards for Council of Dornogal (you're at 7)
--   Sometimes offered on the Black Market Auction House
--   Offered at the Trading Post (March 2025)
--   Drops from Sylvanas Windrunner in Sanctum of Domination, per the Encounter Journal
--
-- Lines(itemID, stack, owner, opts) returns the uses { { text, color,
-- detail, tier, header, note, place } }, the first position found for the waypoint
-- key ({ mapID, x, y, zone, what }; a key's object, an NPC it is used at or
-- a currency's vendor first, then a vendor that takes the item, then one it
-- buys from, then a source such as a seller, a creature or a spot), the sources in the same form, and extra = { pending (quests of the uses still
-- being checked), pendingSources (quests it comes from still being
-- checked, noted under COMES FROM, never under USED FOR), buys (every
-- purchase summed up in one line, BuySummary: "Buys 4 decor and 2 pets you
-- don't have, at 4 vendors (70 things in all)", which the audit panel shows
-- in place of the "Buys at" groups; nil when nothing is bought) }.
-- The uses hold at most MAX_LINES lines besides headings, the sources
-- MAX_SOURCES, then "and N more" (a note marked more, as is "N more still
-- being checked"); a purchase's line is marked buy, and the closing line for
-- uses no longer in the game gone (and every when no use is left). The
-- audit panel shows only a few of these (UI.AuditPanel.Compact); the details
-- window builds its own rows (UI.DetailData). opts.tip (the
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
-- too says "and other costs". An achievement AllTheThings says the item
-- counts toward reads like the game's own criteria; a criterion it only
-- links the item to reads "Linked to". A key says what it opens
-- (Facts.Vendors.Object): where, what it holds, and whether its loot quest
-- is done; an NPC it is used at is named.
--
-- Routes (SRC-01, Relations.Applies): one no longer in the game is left out
-- (the details window lists it under "No longer available", UI.DetailData); one for another faction, class or race
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
--     the detail whether it still does anything (its stillWords).
--   * What using it gives (items 7, 8): a currency whose count the data
--     lacks reads "Using it gives 48 Cataloged Research (you have 0 ...)"
--     from the Use line (English clients, Purposes.UseEffect.GainCount).
--     Where a Use works is left to the checks' reasons: the Use line says it
--     beside the panel.
--   * Costs (item 9): a purchase names this item and every other cost the
--     data lists ("for 50 Mark of Honor, 4 Apexis Crystal and 25 gold",
--     UsedFor.TradeWords); a trade
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
-- that it is a guide note ("Guide note; not confirmed in game yet"). A note
-- is never a USED FOR line and never changes a verdict.
-------------------------------------------------------------------------------
local UsedFor = {}
Recollect.UI.UsedFor = UsedFor

local U = CobySuite_Recollect.Utilities
local Try = Recollect.Utilities.Try
local MAX_LINES = 8
local MAX_SOURCES = 4
local MAX_SELLERS = 2   -- vendors named in one "Buys at" heading
local DETAIL_CHARS = 160
local TIER_OPEN, TIER_INFO, TIER_CLOSED = 1, 2, 3   -- still to get or do; no such state; done or out of reach
-- A quest state's tier, by QuestState's rank: on it, repeatable or not done
-- are open, done (a recurring quest done for now too) is closed, loading or
-- unknown says nothing
local QUEST_TIER = { [5] = TIER_OPEN, [3] = TIER_OPEN, [2] = TIER_OPEN, [4] = TIER_CLOSED, [0] = TIER_CLOSED }
local QUEST_KIND = { objective = true, questItem = true, starts = true, reward = true, choice = true, duringQuest = true }
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
  -- A friendship faction's rank ("Best Friend"): FriendshipReputationInfo, whose
  -- friendshipFactionID is 0 for a faction that isn't one (GossipInfoDocumentation)
  FriendshipData = function(factionID) return C_GossipInfo.GetFriendshipReputation(factionID) end,
  QuestTitle = function(questID) return C_QuestLog.GetTitleForQuestID(questID) end,
  SpellName = function(spellID) return C_Spell.GetSpellName(spellID) end,
  -- A mount's name and summon spell by its mount ID (GetMountInfoByID's first two returns)
  MountInfo = function(mountID) return C_MountJournal.GetMountInfoByID(mountID) end,
  -- An instance difficulty's name ("Mythic Keystone"): GetDifficultyInfo's first return
  DifficultyName = function(difficultyID) return (GetDifficultyInfo(difficultyID)) end,
  -- An item's quality (nil until its data is cached) and a quality's color
  ItemQuality = function(itemID) return C_Item.GetItemQualityByID(itemID) end,
  QualityColor = function(quality) return C_Item.GetItemQualityColor(quality) end,
  -- An item's equip slot, class and subclass with no item load (GetItemInfoInstant's 4th, 6th and 7th)
  ItemKind = function(itemID)
    local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    return equipLoc, classID, subclassID
  end,
  -- An armor subclass's name ("Plate"): GetItemSubClassInfo's first return
  ArmorTypeName = function(subclassID) return (C_Item.GetItemSubClassInfo(4, subclassID)) end,
  -- A follower mission's name, and whether this character has the garrison type it runs from: neither call is in
  -- Blizzard's generated docs (12.1.5); Blizzard's own UI makes them (FloatingGarrisonFollowerTooltip.lua's
  -- FloatingGarrisonMission_Show for a mission link, EventImplementation.lua for HasGarrison), unmeasured here
  MissionName = function(missionID) return C_Garrison.GetMissionName(missionID) end,
  HasGarrison = function(garrisonType) return C_Garrison.HasGarrison(garrisonType) end,
  -- An expansion's name by the game's expansion ID ("Legion" for 6)
  ExpansionName = function(expansion) return _G["EXPANSION_NAME" .. expansion] end,
}

local function Colors() return Recollect.UI.VerdictColors end
local function Verdict() return Recollect.Purposes.Registry.Verdict end
local function Relations() return Recollect.Facts.Relations end
-- A count as the player reads it, with the game's thousands separators
-- ("1,000"; Task #438), everywhere a line prints how many
local function N(n) return Recollect.Utilities.Count(n) end

-------------------------------------------------------------------------------
-- Names as game links: what a line names, heard while it is worded
-------------------------------------------------------------------------------
local LINK_YELLOW = U.Colors.LINK_YELLOW    -- a quest's or an achievement's link
local LINK_BLUE = U.Colors.LINK_BLUE        -- a spell's link (a mount, a recipe, an illusion)
-- a mount, a recipe or an illusion with no item behind it keeps its spell link's blue
local LINK_KINDS = { quest = LINK_YELLOW, achievement = LINK_YELLOW, spell = LINK_BLUE, mount = LINK_BLUE,
  recipe = LINK_BLUE, illusion = LINK_BLUE }

local function QualityColor(quality)
  if type(quality) ~= "number" then return nil end
  local ok, r, g, b = Try(seams.QualityColor, quality)
  if not ok or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
  return { r, g, b }
end

-- ItemBehind(kind, id): the item a named thing stands for, whose quality
-- colors its name as the game's link does, or nil. The one resolver for
-- every kind a line or a row names (the details window's rows use it too),
-- so a new kind can't be left white again (Task #434): an item, a toy, an
-- heirloom or decor is its own item; an ensemble, a pet species, a weapon
-- illusion or a recipe spell the item the data's T table gives
-- (Relations.ThingItem); a mount (its mount ID) the item that teaches its
-- summon spell (Relations.MountItem); anything else (an achievement, a
-- quest, a currency, a plain spell) none
local ITEM_KINDS = { item = true, toy = true, heirloom = true, decor = true }
local THING_LETTER = { ensemble = "e", pet = "p", illusion = "l", recipe = "r" }

function UsedFor.ItemBehind(kind, id)
  if not Recollect.Utilities.IsPositiveID(id) then return nil end
  if ITEM_KINDS[kind] then return id end
  local letter = THING_LETTER[kind]
  if letter then return Relations().ThingItem(letter, id) end
  if kind == "mount" then
    local ok, _, spellID = Try(seams.MountInfo, id)
    return ok and Recollect.Utilities.IsPositiveID(spellID) and Relations().MountItem(spellID) or nil
  end
  return nil
end

-- The quality color of the item behind a typed thing, or nil (no item, or
-- one not loaded yet: asked for, rationed, and the name stays uncolored
-- until it is; never a guess). Task #434: an ensemble and a mount read white
local function ThingItemColor(kind, id)
  local itemID = kind ~= "item" and UsedFor.ItemBehind(kind, id)
  if not itemID then return nil, false end
  local ok, quality = Try(seams.ItemQuality, itemID)
  if not ok or type(quality) ~= "number" then
    Recollect.Facts.Item.Name(itemID)
    return nil, true
  end
  return QualityColor(quality), true
end

-- The color the game gives a name's link, or nil when it can't be told
local function LinkColor(kind, id, quality)
  local thingColor, hasItem = ThingItemColor(kind, id)
  if hasItem then return thingColor end
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

-- color, when given, is the link's (an NPC's or a zone's: links of
-- Recollect's own, which the game gives no color; Task #411)
local function Named(kind, id, text, quality, color)
  if naming and type(text) == "string" and text ~= "" then
    color = color or LinkColor(kind, id, quality)
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

-- A quest's state: title, rank (5 on it, 3 repeatable, 2 not done, 4 done,
-- 1 unread, 0 needs a profession the character doesn't have: out of reach,
-- the grayed cross, never "not done"; a merged line keeps the highest), words,
-- color, quest; nil while it loads. stateless (another character's copy, or
-- another faction's route) reads the title alone.
-- The skill line of the player profession a quest needs, or nil (Task #338):
-- the profession its tag names (QuestTagInfo.tradeskillLineID), else, on an
-- English client, the profession named in the title of the weekly services
-- quests ("Tailoring Services Requested"), the name read live
local function QuestProfession(quest)
  local Recipes = Recollect.Facts.Recipes
  if quest.tradeskillLineID then
    local line = Recipes.ParentProfession(quest.tradeskillLineID)
    if line then return line end
  end
  if quest.title and Recollect.Purposes.Registry.EnglishClient() then
    local name = quest.title:match("^(.+) Services Requested$")
    if name then return Recipes.ProfessionByName(name) end
  end
  return nil
end

-- The name of the profession a quest needs when the logged-in character is
-- read not to have it (never while its professions aren't known yet: the
-- readiness gate of Recipes.OwnsSkillLine), else nil
local function QuestNeeds(quest)
  local Recipes = Recollect.Facts.Recipes
  local line = QuestProfession(quest)
  if not line or Recipes.OwnsSkillLine(line) ~= false then return nil end
  return Recipes.SkillLineName(line)
end

local function QuestState(questID, budget, stateless)
  local quest, why = Recollect.Facts.QuestInfo.Get(questID, budget)
  local V, colors = Verdict(), Colors()
  -- the server answered with nothing for it: never "still checking"
  if not quest and why == "unavailable" then
    return "quest " .. questID, 1, "can't be read", U.Colors.LABEL_GRAY, nil
  end
  if not quest then return nil end
  if quest.title then Named("quest", questID, quest.title) end
  local title = quest.title and ("\"" .. quest.title .. "\"") or ("quest " .. questID)
  if stateless then return title, 1, nil, U.Colors.LIGHT_GRAY, quest end
  if quest.onQuest then return title, 5, "you're on it", colors[V.NEEDED], quest end
  local done = Recollect.Facts.QuestInfo.Done(quest)
  local needs = done ~= true and QuestNeeds(quest) or nil
  if needs then return title, 0, "you don't have " .. needs, U.Colors.LABEL_GRAY, quest end
  if quest.repeatable then return title, 3, "repeatable", colors[V.USEFUL], quest end
  local recurs = done and Recurs(questID)
  -- a recurring quest done this time is done (the check and the done color,
  -- Task #334; the game's own flag clears at the weekly or daily reset, so the
  -- next read after it says not done); the words keep that it comes back
  if recurs then return title, 4, recurs .. ", done for now", colors[V.DONE], quest end
  if done then return title, 4, "done", colors[V.DONE], quest end
  if done == false then return title, 2, "not done", colors[V.USEFUL], quest end
  return title, 1, "can't be read", U.Colors.LABEL_GRAY, quest
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
-- renown level, a completed quest, achievements earned. ShownMet says
-- whether the owner meets one (true, false, or nil: another character's row,
-- or a read that fails; achievements an account-wide one on any row);
-- ShownWords words it ("Engineering only", "Requires Revered with Cenarion
-- Expedition", "Requires Renown 6 with Silvermoon Court (you're at 4)",
-- 'After quest "The Call"', 'After quest "The Call" (done)', 'Requires the
-- achievement "Void Response Team" (3 of 5 done)', several joined: 'Requires
-- the achievements "X" (earned) and "Y" (not earned)'), with names and
-- states read live (Facts.Achievements.Progress and ProgressWords)
local Renown  -- the owner's renown with a major faction, defined with the renown lines below

-- Whether one achievement counts as earned for the owner: true, false, or
-- nil when it can't be told (a read that fails; another character's copy of
-- one not known to be account-wide, rule 46; one earned on another character
-- that isn't account-wide)
local function AchievementMet(progress, owner)
  if not progress then return nil end
  local viewer = owner and owner.isViewer
  if not viewer and progress.accountWide ~= true then return nil end
  if not progress.earned then return false end
  if progress.accountWide == true or progress.byMe then return true end
  return nil
end

local function ShownMet(tag, owner)
  local ids = tag.ids or {}
  if tag.kind == "achievement" then
    local all = true
    for _, achievementID in ipairs(ids) do
      local met = AchievementMet(Recollect.Facts.Achievements.Progress(achievementID), owner)
      if met == nil then return nil end
      if not met then all = false end
    end
    return all
  end
  if not (owner and owner.isViewer) then return nil end
  local client = Recollect.Purposes.client
  if tag.kind == "profession" then
    return Recollect.Facts.Recipes.OwnsSkillLine(ids[1])
  elseif tag.kind == "standing" then
    local ok, data = Try(seams.FactionData, ids[1])
    if not ok or type(data) ~= "table" or type(data.reaction) ~= "number" then return nil end
    return data.reaction >= (ids[2] or 0)
  elseif tag.kind == "renown" then
    local state = Renown(ids[1], ids[2], true)
    if state == "reached" then return true end
    if state == "short" then return false end
    return nil
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

-- '"Void Response Team" (3 of 5 done)': one achievement a route requires,
-- its name heard as a link's, with its progress when it can be told for the
-- owner (another character's copy only for an account-wide one, rule 46)
local function RequiredAchievement(achievementID, owner)
  local progress = Recollect.Facts.Achievements.Progress(achievementID)
  if not progress then return ("%d"):format(achievementID or 0) end
  local name = ('"%s"'):format(Named("achievement", achievementID, progress.name))
  if not (owner and owner.isViewer) and progress.accountWide ~= true then return name end
  return ("%s (%s)"):format(name, (Recollect.Facts.Achievements.ProgressWords(progress)))
end

-- "A", "A and B", "A, B and C"
local function Joined(list)
  if #list <= 1 then return list[1] or "" end
  return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

local function ShownWords(tag, owner, met, missed)
  local ids = tag.ids or {}
  local words
  if tag.kind == "profession" then
    local name = SeamName(seams.SkillLineName, ids[1])
    -- the logged-in character is read not to have it: say so (Task #334);
    -- another character's copy, or a read that fails, keeps the plain words
    if missed and name then
      words = ("You don't have %s"):format(name)
    else
      words = name and ("%s only"):format(name) or "For one profession only"
    end
  elseif tag.kind == "standing" then
    local label = SeamName(seams.StandingLabel, ids[2] or 0)
    words = label and ("Requires %s with %s"):format(label, FactionName(ids[1])) or "Requires a reputation standing"
  elseif tag.kind == "renown" then
    local state, name, now = Renown(ids[1], ids[2], owner and owner.isViewer)
    words = ("Requires Renown %d with %s"):format(ids[2] or 0, name)
    if state == "short" then words = ("%s (you're at %d)"):format(words, now) end
  elseif tag.kind == "achievement" then
    local names = {}
    for i, achievementID in ipairs(ids) do names[i] = RequiredAchievement(achievementID, owner) end
    words = ("Requires the achievement%s %s"):format(#names > 1 and "s" or "", Joined(names))
  else
    local title = SeamName(seams.QuestTitle, ids[1])
    if title then Named("quest", ids[1], title) end
    words = title and ('After quest "%s"'):format(title) or ("After quest %d"):format(ids[1] or 0)
    if met then words = words .. " (done)" end
  end
  -- a name keeps its capitals after another tag; only the leading word lowers
  local after = words:match("^(For one profession only)$") and "for one profession only"
    or words:gsub("^Requires ", "requires "):gsub("^After ", "after "):gsub("^You don't have ", "you don't have ")
  return words, after
end

-- Tags(relation, applies, owner): the tags a route's line or row carries
-- (D19; display only, D34), each { kind, words, after, ids }, from
-- Relations.Conditions with class and race names read here. applies is
-- Relations.Applies' answer for the owner (or a quest's QuestApplies
-- answer, which another code of the quest may have decided) and chooses
-- which tags say why: "unavailable" "No longer available"; nil or
-- "unknown", a condition the owner's record can't answer (a stored alt with
-- no race recorded), is worded as not recorded, as the checks word it
-- (PI-14), never as a mismatch; "other" names each condition missed
-- (faction, class, race), else "not for this character". Display-only
-- conditions (a profession, a standing, renown, a completed quest,
-- achievements; D34) follow, whatever applies says short of unavailable: a
-- profession, standing or renown only while the owner doesn't meet it; a
-- quest or the route's achievements always, with their state ("(done)",
-- "(3 of 5 done)", "(earned)"), since they say what buying takes. One the
-- owner isn't read to meet is marked shown = true (the line dims); one met
-- is kept undimmed. An event route adds "During a holiday or event" for
-- every character, including one it serves. Empty when there is nothing to
-- say.
-- The instance difficulties a route drops on (M, data format 11), worded
-- for every character like an event ("On Mythic Keystone or Mythic
-- difficulty", the names read live with GetDifficultyInfo; "On some
-- difficulties only" when a name can't be read). Returns words, after
function UsedFor.DifficultyWords(ids)
  local names = {}
  for _, difficultyID in ipairs(ids or {}) do
    local ok, name = Try(seams.DifficultyName, difficultyID)
    if not ok or type(name) ~= "string" or name == "" then names = nil break end
    names[#names + 1] = name
  end
  if not names or #names == 0 then return "On some difficulties only", "on some difficulties only" end
  local words = ("on %s difficulty"):format(table.concat(names, " or "))
  return (words:gsub("^o", "O")), words
end

local OTHER_WORDS = "not for this character"
local SHOWN_CONDITIONS = { profession = true, standing = true, renown = true, quest = true, achievement = true }
-- worded even when met, with their state: they say what buying takes
local ALWAYS_SHOWN = { quest = true, achievement = true }
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
      if SHOWN_CONDITIONS[tag.kind] then
        local state = ShownMet(tag, owner)
        local met = state == true
        if not met or ALWAYS_SHOWN[tag.kind] then
          tag.words, tag.after = ShownWords(tag, owner, met, tag.kind == "profession" and state == false)
          tag.shown = not met or nil
          out[#out + 1] = tag
        end
      end
    end
  end
  if applies ~= "unavailable" then
    for _, tag in ipairs(conditions) do
      if tag.kind == "difficulty" then
        tag.words, tag.after = UsedFor.DifficultyWords(tag.ids)
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

-- What makes two seller routes one seller (Task #338): the creature's name,
-- the price and the tags the line carries. One vendor listed under several
-- creature IDs (the data keeps each ID's route) is one line, the one with a
-- place kept over one without. nil when the creature's name isn't read, or
-- the relation isn't a seller's
local function SellerKey(relation, line)
  if relation.kind ~= "soldBy" then return nil end
  local ok, name = Try(Recollect.Facts.Vendors.NpcName, relation.id)
  if not ok or type(name) ~= "string" or name == "" then return nil end
  return table.concat({ name, UsedFor.PriceWords(relation), TagText(line.tags) or "" }, "\30")
end
UsedFor.SellerKey = SellerKey

-- Adds line to list unless a seller line of the same key is there: a line
-- with a place replaces one without
local function AddSeller(list, byKey, key, line)
  local kept = key and byKey[key]
  if not kept then
    list[#list + 1] = line
    if key then byKey[key] = line end
  elseif not kept.place and line.place then
    for k in pairs(kept) do kept[k] = nil end
    for k, v in pairs(line) do kept[k] = v end
  end
end

-- A line with its route's tags: a route that doesn't serve the owner reads
-- them in a closing parenthetical, gray and with the finished lines; an
-- event route that serves it keeps its state last, so the panel still colors
-- the state (AuditPanel.LineText colors only the closing parenthetical). A
-- display-only condition the owner misses (D34) is worded the same way and
-- dims the line (dimmed = true), which stays where it was: no verdict reads it
-- Tags(relation, applies, owner), with the names their words use (a
-- required achievement's, a quest's): handed to the line being built, else
-- returned for the line itself
local function NamedTags(relation, applies, owner)
  local outer = naming
  naming = {}
  local ok, tags = pcall(Tags, relation, applies, owner)
  local names = naming
  naming = outer
  if not ok then error(tags, 0) end
  if outer then
    for _, name in ipairs(names) do outer[#outer + 1] = name end
    names = {}
  end
  return tags, names
end

local function Tagged(line, relation, applies, owner)
  if applies == true and not (relation.flags and relation.flags.event) and not relation.shows then return line end
  local tags, names = NamedTags(relation, applies, owner)
  local words = TagText(tags)
  if not words then return line end
  line.tags = tags
  if #names > 0 then
    line.links = line.links or {}
    for _, name in ipairs(names) do line.links[#line.links + 1] = name end
  end
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

-------------------------------------------------------------------------------
-- What it buys, summed up in one line for the audit panel (BuySummary):
-- every thing Entries counts is tallied, not only the ones it keeps
-------------------------------------------------------------------------------
local MAX_VENDOR_LIST = 12   -- a route's vendor list the data build may have cut (rule 25): no count from it
local MAX_TEXT_SELLERS = 2   -- sellers Facts.Vendors.FromSourceText names at most
local MAX_NAMED_VENDORS = 8  -- vendors named to tell a data vendor from one a source text names

local function Sellers()
  return { texts = {}, textCount = 0, npcs = {}, npcCount = 0, lists = {}, none = 0, capped = false }
end

local function Tally()
  return { total = 0, missing = {}, missingCount = 0, collectibles = 0, owned = 0, unread = 0, plain = 0, leads = 0,
    open = Sellers(), all = Sellers(), leadSellers = Sellers() }
end

-- One thing's sellers into a set: the source text's (texts), else the
-- data's vendor list (a relation's seller string read once), else none
local function AddSellers(set, texts, relation)
  if texts and #texts > 0 then
    -- Vendors.FromSourceText names two sellers at most: a text that named two may have named more
    if #texts >= MAX_TEXT_SELLERS then set.capped = true end
    for _, text in ipairs(texts) do
      if not set.texts[text] then
        set.texts[text] = true
        set.textCount = set.textCount + 1
      end
    end
    return
  end
  local vendors = relation and relation.vendors
  if not vendors or #vendors == 0 then
    set.none = set.none + 1
    return
  end
  local key = relation.seller or vendors
  if set.lists[key] then return end
  set.lists[key] = true
  if #vendors >= MAX_VENDOR_LIST then set.capped = true end
  for _, npc in ipairs(vendors) do
    if not set.npcs[npc] then
      set.npcs[npc] = true
      set.npcCount = set.npcCount + 1
    end
  end
end

-- One thing counted: its state, whether it serves this character, and its sellers
local function Count(tally, what, state, collectible, restricted, texts, relation, leads)
  tally.total = tally.total + 1
  AddSellers(tally.all, texts, relation)
  if collectible then
    tally.collectibles = tally.collectibles + 1
    if state == "have" then
      tally.owned = tally.owned + 1
    elseif state == "missing" and not restricted then
      tally.missing[what] = (tally.missing[what] or 0) + 1
      tally.missingCount = tally.missingCount + 1
      AddSellers(tally.open, texts, relation)
    elseif state == nil or state == "unread" then
      tally.unread = tally.unread + 1
    end
  else
    tally.plain = tally.plain + 1
    if leads and not restricted then
      tally.leads = tally.leads + 1
      AddSellers(tally.leadSellers, texts, relation)
    end
  end
end

-- Entries(itemID, decor, buys, buyApplies, owner, max, budget, tally): the
-- entries that can show, in order, and how many there are in all (Mark of
-- Honor's purchases, about 8,700, make a few dozen entries, not thousands);
-- tally, when given, counts every thing (BuySummary)
local function Entries(itemID, decorRelations, buyRelations, buyApplies, owner, max, budget, tally)
  local entries, seen, taken, total, followed = {}, {}, {}, 0, 0
  local function Add(entry, texts)
    seen[entry.key] = true
    total = total + 1
    if tally then Count(tally, entry.what, entry.state, true, false, texts, nil, false) end
    if Room(taken, entry.group, entry.tier, max) then entries[#entries + 1] = entry end
  end
  local Vendors = Recollect.Facts.Vendors
  for _, relation in ipairs(decorRelations) do
    local owned, info = Recollect.Purposes.Registry.DecorOwned(relation.id)
    local state = owned ~= nil and (owned > 0 and "have" or "missing") or nil
    local texts = Vendors.FromSourceText(info and info.sourceText, "item", itemID)
    local seller = #texts > 0 and table.concat(texts, " or ") or nil
    Add({ what = "decor", id = relation.id, count = relation.count or 1, ofItem = itemID, state = state,
      key = "decor:" .. relation.id, sellerText = seller, group = seller and ("text:" .. seller) or nil, tier = EntryTier(state) },
      texts)
  end
  local index = Recollect.Facts.Journals.Get()
  for _, target in ipairs((index and index[itemID]) or {}) do
    local state, name = Recollect.Purposes.Registry.CollectibleState(target, owner.faction, owner.isViewer)
    local texts = Vendors.FromSourceText(Recollect.Facts.Journals.SourceText(target.kind, target.id), "item", itemID)
    local seller = #texts > 0 and table.concat(texts, " or ") or nil
    Add({ what = target.kind, id = target.id, name = name or (target.kind .. " " .. target.id), count = target.count or 1, ofItem = itemID,
      state = state, key = target.kind .. ":" .. target.id, sellerText = seller, group = seller and ("text:" .. seller) or nil,
      tier = EntryTier(state) }, texts)
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
      if tally then
        Count(tally, thing.what, thing.state, thing.collectible, restricted, nil, relation,
          chain ~= nil and chain.best.state == "open")
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

-- The kinds a summary names, in this order when their counts tie
local KIND_WORDS = { mount = { "mount", "mounts" }, pet = { "pet", "pets" }, toy = { "toy", "toys" },
  decor = { "decor", "decor" }, ensemble = { "ensemble", "ensembles" },
  illusion = { "weapon illusion", "weapon illusions" }, heirloom = { "heirloom", "heirlooms" },
  recipe = { "recipe", "recipes" } }
local KIND_ORDER = { "mount", "pet", "toy", "decor", "ensemble", "illusion", "heirloom", "recipe" }
local MAX_KINDS = 3

local function Counted(n, one, many) return ("%d %s"):format(n, n == 1 and one or many) end

-- "4 decor and 2 pets": the kinds with the most first, three at most, the
-- rest as other collectibles
local function KindWords(missing)
  local kinds, rest = {}, 0
  for i, what in ipairs(KIND_ORDER) do
    if missing[what] then kinds[#kinds + 1] = { what = what, n = missing[what], order = i } end
  end
  for what, n in pairs(missing) do
    if not KIND_WORDS[what] then rest = rest + n end
  end
  table.sort(kinds, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.order < b.order
  end)
  local parts = {}
  for i, kind in ipairs(kinds) do
    if i <= MAX_KINDS then
      parts[#parts + 1] = Counted(kind.n, KIND_WORDS[kind.what][1], KIND_WORDS[kind.what][2])
    else
      rest = rest + kind.n
    end
  end
  if rest > 0 then
    parts[#parts + 1] = #parts > 0 and Counted(rest, "other collectible", "other collectibles")
      or Counted(rest, "collectible", "collectibles")
  end
  return Joined(parts)
end

-- A vendor's name without its place ("Fizz Alechux (Razorwind Shores)" is "Fizz Alechux")
local function VendorName(words)
  return type(words) == "string" and (words:match("^(.-) %(") or words) or nil
end

-- Where a set of things is sold, as words after the things (" at 4 vendors",
-- " at Fizz Alechux (Razorwind Shores)"), or nil when the count can't be
-- stated: a thing with no vendor named, a vendor list the data may have cut,
-- or a vendor a source text names and one the data names by ID that can't
-- be told apart (the same vendor may be named both ways, so the count is
-- of names, and only when every one can be read)
local function SellerWords(set)
  if set.none > 0 or set.capped then return nil end
  local count = set.textCount + set.npcCount
  if count == 0 then return nil end
  local Vendors = Recollect.Facts.Vendors
  if set.textCount > 0 and set.npcCount > 0 then
    if set.npcCount > MAX_NAMED_VENDORS then return nil end
    local names, first = {}, nil
    count = 0
    local function Name(name, words)
      if not names[name] then
        names[name] = true
        count = count + 1
        first = first or words
      end
    end
    for text in pairs(set.texts) do Name(VendorName(text), text) end
    for npc in pairs(set.npcs) do
      local name = Vendors.NpcName(npc)
      if type(name) ~= "string" or name == "" then return nil end
      Name(name, Vendors.Describe(npc))
    end
    if count == 1 and first then return " at " .. first end
    return (" at %d vendors"):format(count)
  end
  if count == 1 then
    -- one value only: next's second (the set's true) would arrive as Describe's noun
    local words = next(set.texts) or Vendors.Describe((next(set.npcs)))
    return words and (" at " .. words) or " at 1 vendor"
  end
  return (" at %d vendors"):format(count)
end

-- BuySummary(tally): what the item buys as one line for the audit panel,
-- from every thing Entries counted, never only the ones shown. Only what
-- the reads verify: "you don't have" counts only collectibles read as
-- missing that serve this character; plain items only through a chain that
-- was followed and leads to one (rule 39); "every collectible among them"
-- only when each one read as owned (rule 31); "can't be read" for one that
-- didn't read. nil when it buys nothing.
local function BuySummary(tally)
  if not tally or tally.total == 0 then return nil end
  local V, colors = Verdict(), Colors()
  local inAll = function(shown)
    return tally.total > shown and (" (%d things in all)"):format(tally.total) or ""
  end
  if tally.missingCount > 0 then
    local at = SellerWords(tally.open)
    return { text = ("Buys %s you don't have%s%s"):format(KindWords(tally.missing), at and ("," .. at) or "",
      inAll(tally.missingCount)), color = colors[V.USEFUL], tier = TIER_OPEN, summary = true }
  end
  if tally.leads > 0 then
    local at = SellerWords(tally.leadSellers)
    return { text = ("Buys %s that %s to things you don't have%s%s"):format(Counted(tally.leads, "item", "items"),
      tally.leads == 1 and "leads" or "lead", at and ("," .. at) or "", inAll(tally.leads)),
      color = colors[V.USEFUL], tier = TIER_OPEN, summary = true }
  end
  local text = ("Buys %s%s"):format(Counted(tally.total, "thing", "things"), SellerWords(tally.all) or "")
  if tally.collectibles > 0 and tally.owned == tally.collectibles then
    -- plain items have no owned state, so they may still be wanted
    local only = tally.plain == 0
    return { text = text .. " (you have every collectible among them)", color = only and colors[V.DONE] or U.Colors.LIGHT_GRAY,
      tier = only and TIER_CLOSED or TIER_INFO, summary = true }
  end
  if tally.unread > 0 then
    text = text .. (" (%d can't be read)"):format(tally.unread)
  end
  return { text = text, color = U.Colors.LIGHT_GRAY, tier = TIER_INFO, summary = true }
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

-- A priced trade's price after its seller (the data's V code): " for 25
-- gold", ", 5 for 1 gold 50 silver" for a stack; a price in a currency
-- (data format 8, 2026-09-29) " for 350 Honor", ", 5 for 350 Honor and 10
-- gold", worded by Facts.Chains.PriceWords, which never words a price partly
-- unknown as whole; with the stack unknown no "N for". "" for a seller with none
function UsedFor.PriceWords(relation)
  if type(relation) ~= "table" then return "" end
  local words
  if relation.price ~= nil then
    local price = relation.price
    if not CobySuite_Recollect.Utilities.IsFiniteNumber(price) or price < 0 then return "" end
    words = UsedFor.GoldWords(price)
  else
    words = Recollect.Facts.Chains.PriceWords(relation.costs)
  end
  if not words then return "" end
  local count = relation.count or 1
  if count > 1 then return (", %s for %s"):format(N(count), words) end
  return " for " .. words
end
function UsedFor.TradeWords(relation, itemID) return Recollect.Facts.Chains.TradeWords(relation, itemID) end

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
  local cost = UsedFor.TradeWords(entry.relation or { count = entry.count }, entry.ofItem)
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
  questItem = "Used in ", starts = "Starts ", duringQuest = "Comes from doing " }
-- Quest lines that also say what the quest rewards
local WITH_REWARDS = { objective = true, questItem = true, starts = true }
local MAX_HELD = 2   -- items an opened object's line names

-- An achievement's line: the game's criterion ("4 of 30") or AllTheThings'
-- requirement ("needs 250")
local function AchievementLine(a, id, needs, stateless)
  local V, colors = Verdict(), Colors()
  if not a then return { text = ("Counts toward achievement %d"):format(id), color = U.Colors.LABEL_GRAY } end
  Named("achievement", id, a.name)
  -- another character's copy (stateless): a part done and how many are the
  -- logged-in character's unless the achievement is account-wide; earned is
  -- the account's (Task #315 ACH-01)
  if stateless and not a.earned and Recollect.Facts.Achievements.AccountWide(id) ~= true then
    return { text = ("Counts toward \"%s\""):format(a.name), color = U.Colors.LIGHT_GRAY, tier = TIER_INFO }
  end
  local state, color, tier
  if a.earned then
    state, color, tier = "earned", colors[V.DONE], TIER_CLOSED
  elseif a.criterionDone then
    state, color, tier = "that part done", colors[V.DONE], TIER_CLOSED
  elseif type(a.required) == "number" and a.required > 1 and type(a.quantity) == "number" then
    state, color, tier = ("%s of %s"):format(N(a.quantity), N(a.required)), colors[V.NEEDED], TIER_OPEN
  elseif needs and needs > 1 then
    state, color, tier = ("needs %s; not earned"):format(N(needs)), colors[V.NEEDED], TIER_OPEN
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
      detail = "Which part it's linked to can't be read" }
  end
  local open = parts.found - parts.done
  local detail
  if state == "open" then
    detail = many and ("Linked to %d of its parts; %d not done yet"):format(parts.found, open)
      or "Linked to a part not done yet"
  else
    detail = many and ("Linked to %d of its parts, all done"):format(parts.found)
      or "Linked to a part that's done"
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

-- OpenersOf(objectID): the keys that open an object, { { itemID, count } },
-- in item order: every item whose live j code names the object or a
-- container its spawn is filed under (Vendors.ObjectAliases). The data has
-- no index from an object to its keys, so the item codes are searched once
-- per object (a plain find over each bucket, then each candidate's own
-- parsed codes confirm it), kept for the session while the data stays the
-- same table (Task #437: the Hexed Vilefeather Eagle's spot opens with
-- 1000 Vile Essence, and its line didn't say so)
local openers = { data = nil, byObject = {} }

local function ScanOpeners(objectID, found, seen)
  local version = Recollect.Facts.DataVersion
  if version and not version.Ok() then return end
  local data = Recollect.Data and Recollect.Data.Relations
  local needle = "j" .. objectID
  for _, bucket in pairs(type(data) == "table" and type(data.B) == "table" and data.B or {}) do
    if type(bucket) == "string" and bucket:find(needle, 1, true) then
      for item, codes in bucket:gmatch("\30(%d+)\31([^\30]*)") do
        item = tonumber(item)
        if not seen[item] and codes:find(needle, 1, true) then
          for _, relation in ipairs(Relations().Of(item, "opens")) do
            if relation.id == objectID and not (relation.flags and relation.flags.unavailable) then
              seen[item] = true
              found[#found + 1] = { itemID = item, count = relation.count or 1 }
              break
            end
          end
        end
      end
    end
  end
end

function UsedFor.OpenersOf(objectID)
  if not Recollect.Utilities.IsPositiveID(objectID) then return {} end
  local data = Recollect.Data and Recollect.Data.Relations
  local B = type(data) == "table" and data.B or nil
  if openers.data ~= B then openers.data, openers.byObject = B, {} end
  local list = openers.byObject[objectID]
  if list then return list end
  list = {}
  local seen = {}
  local ok = pcall(function()
    ScanOpeners(objectID, list, seen)
    for _, alias in ipairs(Recollect.Facts.Vendors.ObjectAliases(objectID)) do ScanOpeners(alias, list, seen) end
  end)
  if not ok then return {} end   -- not kept: asked again next time
  table.sort(list, function(a, b) return a.itemID < b.itemID end)
  openers.byObject[objectID] = list
  return list
end

-- TokensOf(pieceID): the class tokens that can give a piece, { { itemID,
-- classes } } in item order (classes: the set of class IDs the token's route
-- names, or nil), the reverse of the tokens' C codes (Task #440: the piece
-- named nothing of its token; the data has no code for it, so the item codes
-- are searched once per piece, as OpenersOf does for a key, and kept for the
-- session while the data stays the same table)
local tokens = { data = nil, byPiece = {} }

function UsedFor.TokensOf(pieceID)
  if not Recollect.Utilities.IsPositiveID(pieceID) then return {} end
  local data = Recollect.Data and Recollect.Data.Relations
  local B = type(data) == "table" and data.B or nil
  if tokens.data ~= B then tokens.data, tokens.byPiece = B, {} end
  local list = tokens.byPiece[pieceID]
  if list then return list end
  list = {}
  local version = Recollect.Facts.DataVersion
  if version and not version.Ok() then return list end
  local needle = "C" .. pieceID
  local ok = pcall(function()
    for _, bucket in pairs(type(B) == "table" and B or {}) do
      if type(bucket) == "string" and bucket:find(needle, 1, true) then
        for item, codes in bucket:gmatch("\30(%d+)\31([^\30]*)") do
          item = tonumber(item)
          if codes:find(needle, 1, true) then
            for _, relation in ipairs(Relations().Of(item, "givesByClass")) do
              if relation.id == pieceID and not (relation.flags and relation.flags.unavailable) then
                list[#list + 1] = { itemID = item, classes = relation.flags and relation.flags.classes or nil }
                break
              end
            end
          end
        end
      end
    end
  end)
  if not ok then return {} end   -- not kept: asked again next time
  table.sort(list, function(a, b) return a.itemID < b.itemID end)
  tokens.byPiece[pieceID] = list
  return list
end

-- TokenSourceLines(pieceID): the piece's COMES FROM lines for the tokens that
-- give it ("From the class token Dauntless Plate Token (for Paladin and
-- Warrior)"), each token's name heard as an item link in its quality's color;
-- at most MAX_TOKENS, then one line counting the rest
local MAX_TOKENS = 3
function UsedFor.TokenSourceLines(pieceID)
  local out = {}
  local list = UsedFor.TokensOf(pieceID)
  for i = 1, math.min(#list, MAX_TOKENS) do
    local token = list[i]
    local text = "From the class token " .. ItemName(token.itemID)
    local names = {}
    for classID in pairs(token.classes or {}) do names[#names + 1] = classID end
    table.sort(names)
    if #names > 0 and #names <= 4 then
      for k, classID in ipairs(names) do
        local ok, name = Try(seams.ClassName, classID)
        if not ok or type(name) ~= "string" or name == "" then names = {} break end
        names[k] = name
      end
      if #names > 0 then
        text = ("%s (for %s)"):format(text, #names == 1 and names[1]
          or ("%s and %s"):format(table.concat(names, ", ", 1, #names - 1), names[#names]))
      end
    end
    out[#out + 1] = { text = text, color = U.Colors.LIGHT_GRAY, tier = TIER_INFO }
  end
  if #list > MAX_TOKENS then
    out[#out + 1] = { text = ("From %d more class tokens"):format(#list - MAX_TOKENS), color = U.Colors.LIGHT_GRAY,
      tier = TIER_INFO }
  end
  return out
end

-- OpenedWords(objectID): ", opened with 1000 Vile Essence" (several: "X or
-- Y", "X, Y or Z", past three "or one of N more items"), each key's name
-- heard as an item link in its quality's color; "" when nothing opens it.
-- complete is false while a key's name hasn't loaded
local MAX_OPENERS = 3
function UsedFor.OpenedWords(objectID)
  local list = UsedFor.OpenersOf(objectID)
  if #list == 0 then return "", true end
  local names, complete = {}, true
  for i = 1, math.min(#list, MAX_OPENERS) do
    local key = list[i]
    local name = Recollect.Facts.Item.Name(key.itemID)
    if type(name) ~= "string" or name == "" then complete = false end
    name = ItemName(key.itemID)
    names[i] = key.count > 1 and ("%s %s"):format(Recollect.Utilities.Count(key.count), name) or name
  end
  local more = #list - #names
  local words
  if more > 0 then
    words = ("%s or one of %d more items"):format(table.concat(names, ", "), more)
  elseif #names == 1 then
    words = names[1]
  else
    words = ("%s or %s"):format(table.concat(names, ", ", 1, #names - 1), names[#names])
  end
  return ", opened with " .. words, complete
end

-- Where a chain leads and the way back (Tasks #438 and #439), one table:
-- this file is near Lua 5.1's 200 locals
local Lead = { MAX = 2, RANK = { open = 1, unread = 2, done = 3, other = 4, plain = 5 },
  TIERS = { open = TIER_OPEN, unread = TIER_INFO, plain = TIER_INFO, done = TIER_CLOSED, other = TIER_CLOSED } }

-- What a key opens: "Opens a treasure in Zone (x, y) (not looted)", holding
-- what; "Used at a spot in Zone (x, y)" for an object that holds nothing.
-- One that takes several (": takes 1000") says how many you have.
local function OpensLine(relation, places, stateless, itemID)
  local object = Recollect.Facts.Vendors.Object(relation.id)
  if not object then return nil end
  local V, colors = Verdict(), Colors()
  local treasure = #object.contents > 0
  local where, place
  if object.mapID then
    local zone = Recollect.Facts.Vendors.ZoneName(object.mapID) or ("map " .. object.mapID)
    where = ("%s (%.1f, %.1f)"):format(zone, object.x * 100, object.y * 100)
    place = { mapID = object.mapID, x = object.x, y = object.y, zone = zone, what = treasure and "the treasure" or "the spot",
      role = treasure and "opens" or "spot", itemID = itemID }
    places[#places + 1] = place
  end
  local text
  if treasure then
    text = where and ("Opens a treasure in %s"):format(where) or "Opens a treasure"
  else
    text = where and ("Used at a spot in %s"):format(where) or "Used at a spot"
  end
  local takes = (relation.count or 1) > 1 and relation.count or nil
  if takes then text = ("%s: takes %s"):format(text, Recollect.Utilities.Count(takes)) end
  local color, tier = U.Colors.LIGHT_GRAY, nil
  if object.questID and not stateless and Recollect.Facts.Ready.Quests() then
    local ok, done = Try(Recollect.Purposes.client.IsQuestFlaggedCompleted, object.questID)
    if ok and done == true then
      text, color, tier = text .. (treasure and " (looted)" or " (done)"), colors[V.DONE], TIER_CLOSED
    elseif ok and done == false then
      text, color, tier = text .. (treasure and " (not looted)" or " (not done)"), colors[V.USEFUL], TIER_OPEN
    end
  end
  local detail = treasure and Lead.Holds(object.contents) or nil
  local have = takes and not stateless and itemID and Owned(itemID) or nil
  if have then
    detail = ("You have %s of the %s it takes.%s"):format(Recollect.Utilities.Count(have), Recollect.Utilities.Count(takes),
      detail and (" " .. detail) or "")
  end
  return { text = text, color = color, tier = tier, detail = detail, place = place }
end

-- CombineLeads(itemID, owner, places): where combining the item leads (the
-- "leads" check's chains, Task #438: the Diver's Key Fragment makes the
-- Diver's Key, which opens a treasure holding the Ancient Amani Mask), as
-- lines: one "Leads to <end>" per end still to get, unread, had or for
-- someone else (Lead.MAX of them; plain ends only when nothing else is
-- there), each in its state's color with the end's name a link, then a line
-- per treasure on the way with its place (added to places, for the waypoint)
-- and whether it is looted. {} when combining it leads nowhere the data names.
-- relations: the item's own (Relations.For's list, which the caller holds):
-- only an item with a confirmed combine among them is followed
-- (one table: this file is near Lua 5.1's 200 locals)
function Lead.CombineEnd(entry) return entry.via[1] ~= nil and entry.via[1].kind == "makes" end
-- a key's own chain too: what the treasure it opens holds, with its state (Task #439: every node of a chain says
-- what it leads to)
function Lead.Keep(entry) return entry.via[1] ~= nil and (entry.via[1].kind == "makes" or entry.via[1].kind == "opens") end

-- The names a treasure holds, each once (the Sunken Diver's Chest holds the
-- Ancient Amani Mask and a plain copy of one name): "Holds X" or "Holds X, Y
-- and 2 more", or nil when it holds nothing named
function Lead.Holds(contents)
  local names, seen, total = {}, {}, 0
  for _, itemID in ipairs(contents or {}) do
    local name = ItemName(itemID)
    if not seen[name] then
      seen[name] = true
      total = total + 1
      if #names < MAX_HELD then names[#names + 1] = name end
    end
  end
  if #names == 0 then return nil end
  local more = total - #names
  return "Holds " .. table.concat(names, ", ") .. (more > 0 and (" and %d more"):format(more) or "")
end

-------------------------------------------------------------------------------
-- The way back (Task #439; Cobanyte, 2026-10-15, on the Ancient Amani Mask's
-- HOW TO GET MORE, which ended at "opened with Diver's Key"): under a source
-- that needs another item first (a spot a key opens: Task #437's OpenersOf; a
-- combine's parts: f codes), each item on the way as a line with how you get
-- it, at most Lead.STEPS deep, KEYS items a step, never one twice:
--   "Diver's Key: combine 3 Diver's Key Fragment (you have 1)"
--   "Diver's Key Fragment: drops from Glittering Grouper Brinetail (The Coiled Isle)"
-- Information only: no check reads it.
-------------------------------------------------------------------------------
Lead.STEPS, Lead.KEYS = 3, 2

-- How an item is got, in words, and the items that way needs first: a
-- combine of its parts (with how many you have), else UsedFor.SourceWords'
-- first source, else a spot it is found at (and the keys that open it)
function Lead.How(itemID, owner, stateless)
  local R = Relations()
  local parts, ids = {}, {}
  for _, relation in ipairs(R.Of(itemID, "madeFrom")) do
    local ok, applies = pcall(R.Applies, relation, owner)
    if Recollect.Utilities.IsPositiveID(relation.id) and (not ok or applies ~= "unavailable") then
      local have = not stateless and Owned(relation.id) or nil
      parts[#parts + 1] = ("%s %s%s"):format(N(relation.count or 1), ItemName(relation.id),
        have and (" (you have %s)"):format(N(have)) or "")
      ids[#ids + 1] = relation.id
    end
  end
  if #parts > 0 then return "combine " .. Joined(parts), ids end
  local from = UsedFor.SourceWords(itemID, owner)
  if from then return from, {} end
  -- a quest that gives it (Task #446: Living Rot and the Mortar and Pestle,
  -- both rewards of the quest that uses what they make, read "no way to get
  -- it is recorded yet"), its title from the game when it has it
  for _, kind in ipairs({ "reward", "choice", "duringQuest" }) do
    for _, relation in ipairs(R.Of(itemID, kind)) do
      local ok, applies = pcall(R.Applies, relation, owner)
      if Recollect.Utilities.IsPositiveID(relation.id) and (not ok or applies ~= "unavailable") then
        local title = SeamName(seams.QuestTitle, relation.id)
        local quest = title and ('"%s"'):format(Named("quest", relation.id, title)) or ("quest " .. relation.id)
        return (kind == "duringQuest" and "comes from doing " or "a reward of ") .. quest, {}
      end
    end
  end
  for _, relation in ipairs(R.Of(itemID, "foundIn")) do
    local ok, applies = pcall(R.Applies, relation, owner)
    local object = (not ok or applies ~= "unavailable") and Recollect.Facts.Vendors.Object(relation.id)
    if object then
      local keys = {}
      for _, key in ipairs(UsedFor.OpenersOf(relation.id)) do keys[#keys + 1] = key.itemID end
      local zone = object.mapID and (Recollect.Facts.Vendors.ZoneName(object.mapID) or ("map " .. object.mapID))
      local words = zone and ("found at a spot in %s (%.1f, %.1f)"):format(zone, object.x * 100, object.y * 100)
        or "found at a spot in the world"
      return words .. UsedFor.OpenedWords(relation.id), keys
    end
  end
  return nil, {}
end

function Lead.Step(itemID, owner, stateless)
  local how = Lead.How(itemID, owner, stateless)
  return { text = ("%s: %s"):format(ItemName(itemID), how or "no way to get it is recorded yet"), color = U.Colors.LIGHT_GRAY }
end

-- The lines of the way back from the items a source needs first (starts)
function Lead.PathLines(starts, owner, stateless)
  local lines, seen = {}, {}
  local function Walk(ids, depth)
    if depth > Lead.STEPS then return end
    local taken = 0
    for _, itemID in ipairs(ids) do
      if taken >= Lead.KEYS then break end
      if Recollect.Utilities.IsPositiveID(itemID) and not seen[itemID] then
        seen[itemID] = true
        taken = taken + 1
        lines[#lines + 1] = Build(Lead.Step, itemID, owner, stateless)
        local _, nexts = Lead.How(itemID, owner, stateless)
        Walk(nexts or {}, depth + 1)
      end
    end
  end
  Walk(starts, 1)
  return lines
end

-- SourcePath(relation, owner, stateless): the way back under a source
-- relation, as lines (each { text, color, links }); {} for a source that
-- needs nothing first. A spot starts from the keys that open it, a combine
-- from its part
function UsedFor.SourcePath(relation, owner, stateless)
  owner = owner or Recollect.Verdicts.Rows.Owner()
  local starts = {}
  if relation.kind == "foundIn" then
    for _, key in ipairs(UsedFor.OpenersOf(relation.id)) do starts[#starts + 1] = key.itemID end
  elseif relation.kind == "madeFrom" then
    starts[1] = relation.id
  end
  if #starts == 0 then return {} end
  local ok, lines = pcall(Lead.PathLines, starts, owner, stateless == true)
  return ok and lines or {}
end

-- The way back in one detail line ("Diver's Key: combine 3 ...; Diver's Key
-- Fragment: drops from ..."), or nil
function Lead.PathDetail(relation, owner, stateless)
  local texts = {}
  for _, line in ipairs(UsedFor.SourcePath(relation, owner, stateless)) do texts[#texts + 1] = line.text end
  return #texts > 0 and table.concat(texts, "; ") or nil
end

function Lead.Color(state)
  local colors, V = Colors(), Verdict()
  if state == "open" then return colors[V.USEFUL] end
  if state == "done" or state == "other" then return colors[V.DONE] end
  return U.Colors.LIGHT_GRAY
end

function Lead.Line(read, owner)
  local Chains = Recollect.Facts.Chains
  return { text = "Leads to " .. Chains.Words(read.entry, owner, read.thing, read.quests), color = Lead.Color(read.state),
    tier = Lead.TIERS[read.state], leadState = read.state, leadEnd = true,
    collectible = read.thing and read.thing.collectible or false }
end

function Lead.Treasure(step, owner, places)
  local Chains = Recollect.Facts.Chains
  local object = Recollect.Facts.Vendors.Object(step.objectID)
  if not object then return nil end
  local looted = Chains.LootState(step.objectID, owner)
  local text = ("%s opens %s"):format(ItemName(step.of), Chains.TreasureWords(step.objectID, looted))
  local takes = step.relation and (step.relation.count or 1) > 1 and step.relation.count or nil
  if takes then text = ("%s: takes %s"):format(text, Recollect.Utilities.Count(takes)) end
  local place
  if object.mapID then
    place = { mapID = object.mapID, x = object.x, y = object.y, what = "the treasure", role = "opens", itemID = step.of,
      zone = Recollect.Facts.Vendors.ZoneName(object.mapID) or ("map " .. object.mapID) }
    places[#places + 1] = place
  end
  local detail = Lead.Holds(object.contents)
  local state = looted == "done" and "done" or looted == "open" and "open" or "unread"
  return { text = text, color = Lead.Color(state), tier = Lead.TIERS[state], detail = detail, place = place, leadState = state }
end

function Lead.Combines(relations)
  for _, relation in ipairs(relations or {}) do
    if (relation.kind == "makes" or relation.kind == "partOf") and not relation.unresolved
      and Recollect.Utilities.IsPositiveID(relation.id) then return true end
  end
  return false
end

-- Whether the item's own relations hold a key (an opens relation)
function Lead.Opens(relations)
  for _, relation in ipairs(relations or {}) do
    if relation.kind == "opens" and Recollect.Utilities.IsPositiveID(relation.id) then return true end
  end
  return false
end

-- CombinesIn(relations): whether an item's own relations hold a confirmed combine
function UsedFor.CombinesIn(relations) return Lead.Combines(relations) end

function UsedFor.CombineLeads(itemID, owner, places, relations)
  if not Lead.Combines(relations) and not Lead.Opens(relations) then return {} end
  owner = owner or Recollect.Verdicts.Rows.Owner()
  places = places or {}
  local Chains = Recollect.Facts.Chains
  local ok, summary = pcall(Chains.Summary, itemID, owner, Recollect.Facts.QuestInfo.FrameBudget(), nil, Lead.Keep)
  if not ok or type(summary) ~= "table" then return {} end
  -- by state, a collectible before a plain item of the same state (a looted
  -- treasure's plain copy of the toy never stands for the toy), then in order
  local reads, collectible = {}, false
  for i, read in ipairs(summary.reads) do
    reads[i] = read
    read.order = i
    if read.thing and read.thing.collectible then collectible = true end
  end
  table.sort(reads, function(a, b)
    if Lead.RANK[a.state] ~= Lead.RANK[b.state] then return Lead.RANK[a.state] < Lead.RANK[b.state] end
    local ca, cb = a.thing and a.thing.collectible or false, b.thing and b.thing.collectible or false
    if ca ~= cb then return ca end
    return a.order < b.order
  end)
  local lines, shown, treasures = {}, {}, {}
  for _, read in ipairs(reads) do
    if #shown >= Lead.MAX then break end
    local plain = read.state == "plain" or not (read.thing and read.thing.collectible)
    if not plain or (#shown == 0 and not collectible) then
      shown[#shown + 1] = read
      lines[#lines + 1] = Build(Lead.Line, read, owner)
    end
  end
  for _, read in ipairs(shown) do
    for _, step in ipairs(read.entry.via) do
      -- (a treasure the item itself opens is its own opens line)
      if step.kind == "opens" and step.of ~= itemID and not treasures[step.objectID] then
        treasures[step.objectID] = true
        local line = Build(Lead.Treasure, step, owner, places)
        if line then lines[#lines + 1] = line end
      end
    end
  end
  return lines
end

local ProductCustomizes   -- what a combine's product customizes, defined with CustomizesLine below

local function MakesLine(relation, stateless, owner)
  local colors, V = Colors(), Verdict()
  if relation.unresolved then
    return { text = ("Combines %s of these; what they make is unconfirmed"):format(N(relation.count or 1)), color = colors[V.USE] }
  end
  local made = not stateless and Owned(relation.id) or nil
  local have = made and (made > 0 and ("you have %s"):format(N(made)) or "you have none yet")
  local text = ("Makes %s from %s"):format(ItemName(relation.id), N(relation.count or 1))
  return { text = have and ("%s (%s)"):format(text, have) or text, color = colors[V.USE],
    detail = ProductCustomizes(relation.id, stateless, owner) }
end

-- "Using it gives Glyph of the Matriarch's Wings (collected)": what using the
-- item gives (data format 14's I code, from its Use text), with the product's
-- own state when it is a collectible the game counts (Facts.Buys.Product, for
-- the row's owner), else how many you have; information only, never a need
local GIVES_WORDS = { recipe = { have = "known", missing = "not known" },
  achievement = { have = "earned", missing = "not earned" } }
local function GivesLine(relation, stateless, owner)
  local name = ItemName(relation.id)
  local text = (relation.count or 1) > 1 and ("Using it gives %s %s"):format(N(relation.count), name) or ("Using it gives " .. name)
  if stateless then return { text = text, color = U.Colors.LIGHT_GRAY, tier = TIER_INFO } end
  local colors, V = Colors(), Verdict()
  local ok, thing = pcall(Recollect.Facts.Buys.Product, relation.id, owner)
  if ok and type(thing) == "table" and (thing.state == "have" or thing.state == "missing") then
    local words = GIVES_WORDS[thing.what] and GIVES_WORDS[thing.what][thing.state]
      or (thing.state == "have" and "collected" or "not collected")
    return { text = ("%s (%s)"):format(text, words), color = thing.state == "have" and colors[V.DONE] or colors[V.USEFUL],
      tier = thing.state == "have" and TIER_CLOSED or TIER_OPEN }
  end
  local held = (not owner or owner.isViewer ~= false) and Owned(relation.id) or nil
  local have = held and (held > 0 and ("you have %s"):format(N(held)) or "you have none")
  return { text = have and ("%s (%s)"):format(text, have) or text, color = U.Colors.LIGHT_GRAY, tier = TIER_INFO }
end

-- Data format 15 (Task #395): uses from the game's own Use text, information
-- only. A mount customization (B, the mount's summon spell): the mount by
-- name with whether you have it, and the option's own state when the item's
-- tooltip was read (its "Already known" line); "Customizes Cliffside
-- Wylderdrake (unlocked)", "(not unlocked yet; you have the mount)"
local function CustomizesLine(relation, stateless, owner, tip)
  local ok, read = pcall(Recollect.Facts.Buys.Resolve, { kind = "buys", thing = "m", id = relation.id }, owner)
  local thing = ok and type(read) == "table" and read or nil
  local name = thing and thing.name
  if type(name) ~= "string" or name == "" then name = "a mount" else name = Named("mount", thing.id, name) end
  local text = "Customizes " .. name
  if stateless then return { text = text, color = U.Colors.LIGHT_GRAY, tier = TIER_INFO } end
  local colors, V = Colors(), Verdict()
  if tip and tip.known == true then return { text = text .. " (unlocked)", color = colors[V.DONE], tier = TIER_CLOSED } end
  local mount = thing and (thing.state == "have" and "you have the mount" or thing.state == "missing" and "you don't have the mount")
  local option = tip and tip.known == false and "not unlocked yet" or nil
  local words = option and mount and (option .. "; " .. mount) or option or mount
  if not words then return { text = text, color = U.Colors.LIGHT_GRAY, tier = TIER_INFO } end
  local open = option and thing and thing.state == "have"
  return { text = ("%s (%s)"):format(text, words), color = open and colors[V.USEFUL] or U.Colors.LIGHT_GRAY,
    tier = open and TIER_OPEN or TIER_INFO }
end

-- A combine whose product is a mount customization's item (the G-99
-- Breakneck's turbos, Task #403: the parts make Steamboil, whose own B code
-- names the mount): "Steamboil customizes G-99 Breakneck (not unlocked yet;
-- you have the mount)", the product's own B line read with the product's
-- tooltip ("Already known"), as the detail of the part's line; nil when the
-- product customizes nothing this character can use
ProductCustomizes = function(productID, stateless, owner)
  if not Recollect.Utilities.IsPositiveID(productID) then return nil end
  local R = Relations()
  local ok, list = pcall(R.Of, productID, "customizes")
  local relation = ok and type(list) == "table" and list[1] or nil
  if not relation or R.Applies(relation, owner) ~= true then return nil end
  local tip = not stateless and Recollect.Facts.Tooltip.FromItemID(productID) or nil
  -- the product is rarely held, and a tooltip by ID for an item not cached
  -- yet still parses, with no "Already known": read it only once it carries
  -- the Use line, which the product's whole tooltip always has (rule 14)
  if tip and not tip.useText then tip = nil end
  local line = CustomizesLine(relation, stateless, owner, tip)
  if not line then return nil end
  local more = #list - 1
  return ItemName(productID) .. " c" .. line.text:sub(2)
    .. (more > 0 and (more == 1 and " and 1 more mount" or (" and %d more mounts"):format(more)) or "")
end

-- The owner's standing with a faction, read live: "Renown 12" for a major
-- faction, a friendship's rank ("Best Friend"), else the standing's name
-- ("Revered"); nil when none can be read. Only the logged-in character's
local function StandingWords(factionID, owner)
  if owner and owner.isViewer == false then return nil end
  local IsSecret = Recollect.Utilities.IsSecret
  local okMajor, major = Try(seams.MajorFactionData, factionID)
  if okMajor and type(major) == "table" and CobySuite_Recollect.Utilities.IsFiniteNumber(major.renownLevel) and not IsSecret(major.renownLevel) then
    return ("Renown %d"):format(major.renownLevel)
  end
  local okFriend, friend = Try(seams.FriendshipData, factionID)
  if okFriend and type(friend) == "table" and Recollect.Utilities.IsPositiveID(friend.friendshipFactionID)
    and type(friend.reaction) == "string" and friend.reaction ~= "" and not IsSecret(friend.reaction) then
    return friend.reaction
  end
  local ok, data = Try(seams.FactionData, factionID)
  if not ok or type(data) ~= "table" or type(data.reaction) ~= "number" or IsSecret(data.reaction) then return nil end
  local okLabel, label = Try(seams.StandingLabel, data.reaction)
  return okLabel and type(label) == "string" and label ~= "" and label or nil
end
UsedFor.StandingWords = StandingWords

-- "Gives 250 reputation with Valarjar (you're Revered)"; with no one amount
-- (W<faction>x0), "Raises your reputation with Valarjar"
local function ReputationWords(relation)
  local name = FactionName(relation.id)
  if (relation.count or 0) > 0 then
    return ("Gives %s reputation with %s"):format(Recollect.Utilities.Count(relation.count), name)
  end
  return "Raises your reputation with " .. name
end
UsedFor.ReputationWords = ReputationWords

local function ReputationLine(relation, stateless, owner)
  local text = ReputationWords(relation)
  local standing = not stateless and StandingWords(relation.id, owner) or nil
  return { text = standing and ("%s (you're %s)"):format(text, standing) or text, color = U.Colors.LIGHT_GRAY,
    tier = TIER_INFO }
end

-- "A lure: Blackwater Whiptail bites more often (you have 3)"
local function LureLine(relation, stateless, owner)
  local text = ("A lure: %s bites more often"):format(ItemName(relation.id))
  local held = not stateless and (not owner or owner.isViewer ~= false) and Owned(relation.id) or nil
  local have = held and (held > 0 and ("you have %s"):format(N(held)) or "you have none")
  return { text = have and ("%s (%s)"):format(text, have) or text, color = U.Colors.LIGHT_GRAY, tier = TIER_INFO }
end

-- Data format 16 (Task #396): what a class token gives (its C codes), one
-- of them by the class or specialization of whoever uses it. The armor type
-- each class wears, by class ID (1 Warrior to 13 Evoker; 1 Cloth, 2 Leather,
-- 3 Mail, 4 Plate, as Enum.ItemArmorSubclass numbers them in the 12.1.5
-- generated docs): our own table, for the wording only, since no game call
-- maps a class to its armor type (IsItemPreferredArmorType needs a held
-- item's location). A piece's own armor type is read from the item.
local CLASS_ARMOR = { [1] = 4, [2] = 4, [3] = 3, [4] = 2, [5] = 1, [6] = 4, [7] = 3, [8] = 1, [9] = 1, [10] = 2,
  [11] = 2, [12] = 2, [13] = 3 }
local ARMOR_WORDS = { "Cloth", "Leather", "Mail", "Plate" }   -- when the game's name can't be read
local ARMOR_CLASS = 4   -- Enum.ItemClass.Armor
local MAX_PIECES = 3    -- pieces a line names

-- A piece's armor type (1 to 4), false for one that has none (a ring, a
-- trinket, a cloak every class wears), nil when it can't be read
local function ArmorType(itemID)
  local ok, equipLoc, classID, subclassID = Try(seams.ItemKind, itemID)
  if not ok or type(classID) ~= "number" then return nil end
  if classID == ARMOR_CLASS and equipLoc ~= "INVTYPE_CLOAK" and type(subclassID) == "number" and ARMOR_WORDS[subclassID] then
    return subclassID
  end
  return false
end

local function ArmorName(armor)
  local ok, name = Try(seams.ArmorTypeName, armor)
  if ok and type(name) == "string" and name ~= "" then return name end
  return ARMOR_WORDS[armor]
end

local function Listed(words)
  if #words < 2 then return words[1] or "" end
  return table.concat(words, ", ", 1, #words - 1) .. " and " .. words[#words]
end

-- "Death Knight, Paladin and Warrior": the classes that wear an armor type,
-- by name; nil when a name can't be read
local function Wearers(armor)
  local names = {}
  for classID = 1, #CLASS_ARMOR do
    if CLASS_ARMOR[classID] == armor then
      local ok, name = Try(seams.ClassName, classID)
      if not ok or type(name) ~= "string" or name == "" then return nil end
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return Listed(names)
end

-- A token's pieces read for an owner: { armor = { [id] = type or false },
-- types (the armor types in the order first met), unread, mine (the pieces of
-- the owner's armor type), ownArmor (nil when the owner's class isn't known),
-- split (every piece has an armor type and they differ), single (the one
-- armor type every piece has) }
local function TokenPieces(ids, owner)
  local out = { armor = {}, types = {}, unread = false, mine = {} }
  out.ownArmor = owner and CLASS_ARMOR[owner.classID] or nil
  local seen, every = {}, true
  for _, id in ipairs(ids) do
    local armor = ArmorType(id)
    if armor == nil then out.unread = true end
    if not armor then every = false end
    out.armor[id] = armor or false
    if armor and not seen[armor] then
      seen[armor] = true
      out.types[#out.types + 1] = armor
    end
    if armor and armor == out.ownArmor then out.mine[#out.mine + 1] = id end
  end
  out.split = every and #out.types >= 2
  out.single = every and #out.types == 1 and out.types[1] or nil
  return out
end
UsedFor.TokenPieces = TokenPieces

-- "your armor type", or another character's ("Tanklite's armor type")
local function Whose(owner)
  if not owner or owner.isViewer ~= false then return "your" end
  return type(owner.name) == "string" and owner.name ~= "" and (owner.name .. "'s") or "this character's"
end

local function PieceNames(ids)
  local names = {}
  for i = 1, math.min(#ids, MAX_PIECES) do names[i] = ItemName(ids[i]) end
  local more = #ids - #names
  if more > 0 then names[#names + 1] = ("%d more"):format(more) end
  return Listed(names)
end

-- One line for every piece a token gives (information only): "Gives the
-- piece for your armor type: Dauntless Plate Helm (Plate)", with every armor
-- type and who wears it in the line's detail; "Gives one of 16 Mail pieces,
-- chosen by class and specialization (your armor type)"; "Gives one of 3
-- items, chosen by class or specialization: A, B and C"; one piece alone
-- "Using it gives X"
local function TokenLine(ids, owner)
  local line = { color = U.Colors.LIGHT_GRAY, tier = TIER_INFO }
  if #ids == 1 then
    line.text = "Using it gives " .. ItemName(ids[1])
    return line
  end
  local pieces = TokenPieces(ids, owner)
  if pieces.split then
    local types = {}
    for _, armor in ipairs(pieces.types) do
      local who = Wearers(armor)
      types[#types + 1] = who and (ArmorName(armor) .. " for " .. who) or ArmorName(armor)
    end
    line.detail = "One for each armor type: " .. table.concat(types, "; ")
    if #pieces.mine == 1 then
      line.text = ("Gives the piece for %s armor type: %s (%s)"):format(Whose(owner), ItemName(pieces.mine[1]),
        ArmorName(pieces.ownArmor))
    elseif #pieces.mine > 1 then
      line.text = ("Gives one of %d %s pieces for %s armor type, by specialization: %s"):format(#pieces.mine,
        ArmorName(pieces.ownArmor), Whose(owner), PieceNames(pieces.mine))
    else
      local names = {}
      for _, armor in ipairs(pieces.types) do names[#names + 1] = ArmorName(armor) end
      local own = pieces.ownArmor and ("; none is %s, %s armor type"):format(ArmorName(pieces.ownArmor), Whose(owner)) or ""
      line.text = ("Gives one piece by armor type (%s)%s"):format(table.concat(names, ", "), own)
    end
    return line
  end
  if pieces.single then
    local armor = pieces.single
    local state
    if pieces.ownArmor == armor then
      state = Whose(owner) .. " armor type"
    else
      local who = Wearers(armor)
      state = who and ("worn by " .. who) or nil
    end
    line.text = ("Gives one of %d %s pieces, chosen by class and specialization%s"):format(#ids, ArmorName(armor),
      state and (" (" .. state .. ")") or "")
    return line
  end
  line.text = ("Gives one of %d items, chosen by class or specialization: %s"):format(#ids, PieceNames(ids))
  return line
end

-- A token's piece as the pinned view's state: its armor type and who wears
-- it ("Plate, worn by Death Knight, Paladin and Warrior"), "Plate, your
-- armor type" for the owner's; nil for a piece with no armor type, false
-- when it can't be read. The second value is true for the owner's piece.
function UsedFor.PieceWords(itemID, owner)
  local armor = ArmorType(itemID)
  if armor == nil then return false end
  if not armor then return nil end
  local own = owner and CLASS_ARMOR[owner.classID]
  if own == armor then return ("%s, %s armor type"):format(ArmorName(armor), Whose(owner)), true end
  local who = Wearers(armor)
  return who and ("%s, worn by %s"):format(ArmorName(armor), who) or ArmorName(armor), false
end

-- "Combines with the Reinforced Amani Haft and Toughened Amani Leather Wrap
-- into Amani Warrior's Spear (you have 1 of the 3 parts)": one of several
-- different parts (Purposes.Parts says the same in its reason)
local function PartOfLine(relation, stateless, itemID, owner)
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
  local text = ("Combines %swith %s into %s"):format(own and own.count > 1 and (own.count .. " of these ") or "",
    Parts.Join(others), ItemName(relation.id))
  local held, readable = 0, not stateless
  for _, part in ipairs(readable and relation.parts or {}) do
    local have = Owned(part.itemID)
    if have == nil then readable = false break end
    if have >= part.count then held = held + 1 end
  end
  if readable then text = ("%s (you have %d of the %d parts)"):format(text, held, #relation.parts) end
  local open = readable and held < #relation.parts
  return { text = text, color = Colors()[Verdict().USE], tier = open and TIER_OPEN or nil,
    detail = ProductCustomizes(relation.id, stateless, owner) }
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
    held = (" (you have %s %s%s)"):format(N(quantity), info.name, capped and ", the most you can hold" or "")
  end
  Named("currency", relation.id, info.name, info.quality)
  local gain = not (relation.count and relation.count > 0) and UseGain(tip, info.name) or nil
  if relation.count and relation.count > 0 then
    text = ("Worth %s %s%s"):format(N(relation.count), info.name, held)
  elseif gain then
    text = ("Using it gives %s %s%s"):format(N(gain), info.name, held)
  else
    text = ("Currency: %s%s"):format(info.name, held)
  end
  local line = { text = text, color = colors[V.USEFUL] }
  local plain = type(info.description) == "string" and U.StripColors(info.description):gsub("|n", " ") or ""
  local desc = plain ~= "" and Cut(plain) or nil
  local vendor = Recollect.Facts.Vendors.ForCurrency(relation.id)[1]
  if vendor then
    vendor.role, vendor.currencyID = "spend", relation.id
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

-- LacksWords(skillLine, stateless): "you don't have Tailoring" when the
-- logged-in character (not another's copy, stateless) is read not to have
-- the player profession a recipe belongs to (Task #334); nil for a profession
-- it has, one that can't be read, and a skill line of another system
local function LacksWords(skillLine, stateless)
  local Recipes = Recollect.Facts.Recipes
  if stateless or not Recipes.IsProfession(skillLine) or Recipes.OwnsSkillLine(skillLine) ~= false then return nil end
  local name = SkillName(Recipes.ProfessionOf(skillLine))
  return name and ("you don't have " .. name) or nil
end

local function CraftedLine(relation, stateless)
  local recipe = Relations().Recipe(relation.id)
  local profession = recipe and recipe.skillLine and recipe.skillLine > 0 and SkillName(recipe.skillLine) or nil
  local ok, name = Try(seams.SpellName, relation.id)
  name = ok and type(name) == "string" and name ~= "" and Named("spell", relation.id, name) or ("recipe " .. relation.id)
  local text = profession and ("Crafted by %s: %s"):format(profession, name) or ("Crafted with the recipe " .. name)
  if not stateless then
    local known = Recollect.Facts.Buys.RecipeKnown(relation.id)
    local lacks = known ~= true and recipe and LacksWords(recipe.skillLine, stateless) or nil
    if known == true then
      text = text .. " (you know it)"
    elseif lacks then
      text = ("%s (%s)"):format(text, lacks)
    end
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
      local recipe = Relations().Recipe(relation.id)
      local lacks = recipe and LacksWords(recipe.skillLine, stateless) or nil
      text, color, tier = ("%s (%s)"):format(text, lacks or "you don't know it"), Colors()[Verdict().USEFUL], TIER_OPEN
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
function Renown(factionID, level, readState)
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

-- RenownWords(level, name): "Listed in the Renown 12 rewards for Council of
-- Dornogal" (Task #341). The game's reward type is a display type only, with
-- no quantity, one-time or purchase field, so the words promise no grant, no
-- amount and no unlock; the item is only named among that level's rewards
function UsedFor.RenownWords(level, name)
  return ("Listed in the Renown %d rewards for %s"):format(level or 0, name)
end

-- "Listed in the Renown 12 rewards for Council of Dornogal (you're at 7)"
local function RenownLine(relation, stateless)
  local level = relation.level or 0
  local state, name, now = Renown(relation.id, level, not stateless)
  local text = UsedFor.RenownWords(level, name)
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

-- "Drops from Sylvanas Windrunner in Sanctum of Domination, per the
-- Encounter Journal", the boss's name a journal link when the journal gives
-- one; nil when the journal can't name the encounter
local function JournalLine(relation)
  local encounter = Recollect.Facts.Vendors.Encounter(relation.id)
  if not encounter then return nil end
  local boss = encounter.link and Named("encounter", relation.id, encounter.name) or encounter.name
  local text = encounter.instance and ("Drops from %s in %s, per the Encounter Journal"):format(boss, encounter.instance)
    or ("Drops from %s, per the Encounter Journal"):format(boss)
  return { text = text, color = U.Colors.LIGHT_GRAY }
end

-- Sources of data format 11: a profession's gathering or extracting spell
-- ("Comes from Disenchant", its name read live; no line while it can't be
-- read), a creature skinned (its place like a drop's), and a seasonal drop
local SEASON_DROP_TEXT = "A seasonal drop: it comes from many of the season's activities, dungeon and raid bosses "
  .. "among them, not from one boss"
-- Data format 22 (Task #447): a G on a creature (G<spell>@<npc>, placed like
-- a drop) or a zone's enemies (G<spell>#<map>): Pick Pocket says pickpocketed,
-- a profession on a creature names the profession ("Gathered from X with
-- Herbalism"); a G made by a spell (G<spell>.1) says so ("Made by the spell
-- Get Shavings", "Made by a spell" when the name can't be read). Spell 0 (a
-- profession's spell not known) is never read for a name
local function GatheredWords(relation)
  local profession = relation.shows and relation.shows.professions and relation.shows.professions[1]
  local name
  if relation.id > 0 then
    local ok, read = Try(seams.SpellName, relation.id)
    name = ok and type(read) == "string" and read ~= "" and read or nil
  end
  local pick = relation.id == Relations().PICK_POCKET
  if relation.npc or relation.mapID then
    local where
    if relation.mapID then
      where = "enemies in " .. (Recollect.Facts.Vendors.ZoneName(relation.mapID) or ("map " .. relation.mapID))
    end
    if pick then return "Pickpocketed from %s", where end
    local skill = profession and SkillName(profession)
    if skill then return "Gathered from %s with " .. skill, where end
    if name then return "Comes from " .. name .. " on %s", where end
    return nil
  end
  if pick then return "Pickpocketed from enemies" end
  if relation.made then return name and ("Made by the spell " .. name) or "Made by a spell" end
  return name and ("Comes from " .. name) or nil
end

local function GatheredLine(relation, _, places, itemID)
  local words, where = GatheredWords(relation)
  if not words then return nil end
  if not relation.npc then
    return { text = where and words:format(where) or words, color = U.Colors.LIGHT_GRAY }
  end
  local who, npc = Recollect.Facts.Vendors.Describe(relation.npc, "a creature")
  if not who then return nil end
  if npc then
    npc.what, npc.role, npc.itemID = "the creature", "gatheredBy", itemID
    places[#places + 1] = npc
  end
  return { text = words:format(who), color = U.Colors.LIGHT_GRAY, place = npc }
end

local function SkinnedLine(relation, _, places, itemID)
  local who, npc = Recollect.Facts.Vendors.Describe(relation.id, "a creature")
  if not who then return nil end
  if npc then
    npc.what, npc.role, npc.itemID = "the creature", "skinnedFrom", itemID
    places[#places + 1] = npc
  end
  return { text = "Skinned from " .. who, color = U.Colors.LIGHT_GRAY, place = npc }
end

-- Data format 12: a Delve's completion reward (the words only; no number is read)
local DELVE_REWARD_TEXT = "Completing a Delve gives it"

-- Data format 13: the in-game shop, a promotion, a Trading Card Game loot card and a Recruit-A-Friend reward
local STORE_PROMOTION_TEXT = {
  [1] = "From the in-game shop",
  [2] = "From a promotion",
  [3] = "From a Trading Card Game loot card",
  [4] = "A Recruit-A-Friend reward",
}
local STORE_PROMOTION_SUMMARY = {
  [1] = "comes from the in-game shop",
  [2] = "comes from a promotion",
  [3] = "comes from a Trading Card Game loot card",
  [4] = "is a Recruit-A-Friend reward",
}

local function StorePromotionLine(relation)
  local text = STORE_PROMOTION_TEXT[relation.id]
  if not text then return nil end
  return { text = text, color = U.Colors.LIGHT_GRAY }
end

local NEW_SOURCES = {
  journalDrop = JournalLine,
  renownReward = RenownLine,
  blackMarket = function() return { text = BLACK_MARKET_TEXT, color = U.Colors.LIGHT_GRAY } end,
  tradingPost = function(relation) return { text = TradingPostText(relation.id), color = U.Colors.LIGHT_GRAY } end,
  gatheredBy = GatheredLine,
  skinnedFrom = SkinnedLine,
  seasonDrop = function() return { text = SEASON_DROP_TEXT, color = U.Colors.LIGHT_GRAY } end,
  delveReward = function() return { text = DELVE_REWARD_TEXT, color = U.Colors.LIGHT_GRAY } end,
  storePromotion = StorePromotionLine,
}
UsedFor.SEASON_DROP_TEXT = SEASON_DROP_TEXT

-- Data format 17 (Task #397), sources. "Bought with 3 Mark of Honor":
-- what buys it, every cost of the trade in rule 50's words (the buying item
-- first, never a price partly unknown as whole), then the vendor ("at Zektar
-- (Hallowfall)", a waypoint to it) or the place the trade is ("in Timeless
-- Isle"); PvP season gear has neither
local function BoughtWithLine(relation, places, itemID)
  local text = "Bought with " .. UsedFor.TradeWords(relation, relation.id)
  local vendors, place = relation.vendors or {}, nil
  if vendors[1] then
    local who, vendor = Recollect.Facts.Vendors.Describe(vendors[1])
    if who then
      text = text .. " at " .. who
      local others = #vendors - 1
      if others > 0 then text = text .. (others == 1 and " or 1 other vendor" or (" or %d other vendors"):format(others)) end
    end
    if vendor then
      vendor.role, vendor.itemID = "soldBy", itemID
      places[#places + 1] = vendor
      place = vendor
    end
  elseif relation.mapID then
    text = text .. " in " .. (Recollect.Facts.Vendors.ZoneName(relation.mapID) or ("map " .. relation.mapID))
  end
  return { text = text, color = U.Colors.LIGHT_GRAY, place = place }
end

-- "Given to new Death Knight characters" (data format 18's Z): the classes
-- and races its route flags name, at most two of each, when the route serves
-- the owner; "Given to new characters" otherwise, where the route's own tag
-- says who it is for ("(Death Knight only)")
function UsedFor.NewCharacterWords(relation, owner)
  local flags = type(relation) == "table" and relation.flags
  local served = type(flags) == "table" and Relations().Applies(relation, owner) == true
  if not served then return "Given to new characters" end
  local function Names(set, seam)
    local ids, names = {}, {}
    for id in pairs(set or {}) do ids[#ids + 1] = id end
    if #ids == 0 or #ids > 2 then return nil end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local ok, name = Try(seam, id)
      if not ok or type(name) ~= "string" or name == "" then return nil end
      names[#names + 1] = name
    end
    return table.concat(names, " and ")
  end
  local words = {}
  words[#words + 1] = Names(flags.races, seams.RaceName)
  words[#words + 1] = Names(flags.classes, seams.ClassName)
  if #words == 0 then return "Given to new characters" end
  return ("Given to new %s characters"):format(table.concat(words, " "))
end

-- "Solved through Archaeology with 34 Dwarf Archaeology Fragments (you have
-- 120)": an artifact of the race whose fragments the code names, the
-- fragments' name read live (the game's race calls take a race's index in
-- the Archaeology window, not an ID the data can carry)
local function ArchaeologyLine(relation, stateless)
  local info = Currency(relation.id)
  if not info then return { text = "Solved through Archaeology", color = U.Colors.LIGHT_GRAY } end
  Named("currency", relation.id, info.name, info.quality)
  local count = relation.count and relation.count > 0 and (Recollect.Utilities.Count(relation.count) .. " ") or ""
  local text = ("Solved through Archaeology with %s%s"):format(count, info.name)
  local quantity = not stateless and CobySuite_Recollect.Utilities.IsFiniteNumber(info.quantity) and info.quantity or nil
  if quantity then text = ("%s (you have %s)"):format(text, N(quantity)) end
  return { text = text, color = U.Colors.LIGHT_GRAY }
end

-- Data format 19 (Task #401): a reward for completing an event no zone
-- holds, worded by what names the event, each with its live state:
-- 'A reward for completing "Fyrakk Assault" (weekly, done for now)', the
-- quest's own line (nil and true second while it loads); 'A reward for
-- completing an event the achievement "X" counts (3 of 5 done)', the progress
-- left out on another character's copy of one not known to be account-wide
-- (Task #315 ACH-01); 'A reward for completing an event that gives Voidlight
-- Marl (you have 40)', the count only on the logged-in character's copy
local EVENT_LEAD = "A reward for completing "
local function EventRewardLine(relation, budget, stateless, owner)
  if relation.event == "quest" then
    local line = QuestLine(EVENT_LEAD, relation.id, false, budget, stateless, owner)
    return line, line == nil
  end
  if relation.event == "achievement" then
    local A = Recollect.Facts.Achievements
    local progress = A.Progress(relation.id)
    if not progress then
      return { text = EVENT_LEAD .. ("an event achievement %d counts"):format(relation.id), color = U.Colors.LABEL_GRAY }
    end
    Named("achievement", relation.id, progress.name)
    local text = ("%san event the achievement \"%s\" counts"):format(EVENT_LEAD, progress.name)
    if stateless and not progress.earned and progress.accountWide ~= true then
      return { text = text, color = U.Colors.LIGHT_GRAY, tier = TIER_INFO }
    end
    local words, open = A.ProgressWords(progress)
    local colors, V = Colors(), Verdict()
    return { text = ("%s (%s)"):format(text, words),
      color = open and colors[V.USEFUL] or (open == false and colors[V.DONE]) or U.Colors.LIGHT_GRAY,
      tier = open and TIER_OPEN or (open == false and TIER_CLOSED) or nil }
  end
  local info = Currency(relation.id)
  if not info then return { text = EVENT_LEAD .. "an event", color = U.Colors.LIGHT_GRAY } end
  Named("currency", relation.id, info.name, info.quality)
  local text = ("%san event that gives %s"):format(EVENT_LEAD, info.name)
  local quantity = not stateless and CobySuite_Recollect.Utilities.IsFiniteNumber(info.quantity) and info.quantity or nil
  if quantity then text = ("%s (you have %s)"):format(text, N(quantity)) end
  return { text = text, color = U.Colors.LIGHT_GRAY }
end

-- Data format 20 (Task #403): a reward of a follower mission, by the game's
-- Enum.GarrisonFollowerType (the M code's system): what the system is
-- called, the garrison type HasGarrison asks for it, and its expansion (the
-- type's own patch, 6.0 to 9.0, less one: rule 45's way)
local MISSION_SYSTEMS = {
  [1] = { one = "garrison mission", many = "garrison missions", garrison = 2, expansion = 5 },
  [2] = { one = "shipyard mission", many = "shipyard missions", garrison = 2, expansion = 5 },
  [4] = { one = "class hall mission", many = "class hall missions", garrison = 3, expansion = 6 },
  [22] = { garrison = 9, expansion = 7 },   -- named by its expansion ("Battle for Azeroth mission")
  [123] = { one = "covenant adventure", many = "covenant adventures", garrison = 111, expansion = 8 },
}

local function ExpansionName(expansion)
  local ok, name = Try(seams.ExpansionName, expansion)
  return ok and type(name) == "string" and name ~= "" and name or nil
end

-- What a mission of the system is called, one and many ("mission" for a
-- system this Recollect doesn't know)
local function MissionNouns(system)
  local known = MISSION_SYSTEMS[system]
  if known and known.one then return known.one, known.many end
  local expansion = known and ExpansionName(known.expansion)
  if expansion then return expansion .. " mission", expansion .. " missions" end
  return "mission", "missions"
end

-- 'A reward from the class hall mission "X" (costs 100 Order Resources, you
-- have 1240; open to this character)': the mission's name read live ("a
-- class hall mission" when it can't be, "class hall missions" for mission
-- 0, which one not known), its cost and the count held, and whether the
-- logged-in character has the system (C_Garrison.HasGarrison); the details
-- window's detail says the system is an older expansion's. Information only:
-- whether the mission is still offered isn't read (Purposes.Legacy's garrison
-- and follower systems keep still = nil for the same reason)
-- The mission as a phrase: 'the class hall mission "X"', "a class hall
-- mission" when its name can't be read, "class hall missions" for mission 0
local function MissionPhrase(relation)
  local one, many = MissionNouns(relation.system)
  if relation.id == 0 then return many end
  local ok, name = Try(seams.MissionName, relation.id)
  if ok and type(name) == "string" and name ~= "" then return ("the %s \"%s\""):format(one, name) end
  return "a " .. one
end

-- What the mission costs, with how many you hold, and whether this
-- character has the system: the words in order, and HasGarrison's answer
-- (true, false, or nil when not read)
local function MissionStates(relation, stateless)
  local parts = {}
  for _, cost in ipairs(relation.costs or {}) do
    local info = Currency(cost.id)
    if info then
      Named("currency", cost.id, info.name, info.quality)
      local words = cost.count > 0 and ("costs %s %s"):format(Recollect.Utilities.Count(cost.count), info.name)
        or ("paid with " .. info.name)
      local quantity = not stateless and CobySuite_Recollect.Utilities.IsFiniteNumber(info.quantity) and info.quantity or nil
      parts[#parts + 1] = quantity and ("%s, you have %s"):format(words, N(quantity)) or words
    end
  end
  local known = MISSION_SYSTEMS[relation.system]
  local has
  if not stateless and known then
    local ok, answer = Try(seams.HasGarrison, known.garrison)
    if ok and (answer == true or answer == false) then has = answer end
    if has == true then parts[#parts + 1] = "open to this character" end
    if has == false then parts[#parts + 1] = "not unlocked on this character" end
  end
  return parts, has
end

local function MissionLine(relation, stateless)
  local text = "A reward from " .. MissionPhrase(relation)
  local parts = MissionStates(relation, stateless)
  if #parts > 0 then text = ("%s (%s)"):format(text, table.concat(parts, "; ")) end
  local known = MISSION_SYSTEMS[relation.system]
  local expansion = known and ExpansionName(known.expansion)
  return { text = text, color = U.Colors.LIGHT_GRAY, tier = TIER_INFO,
    detail = expansion and ("A system of %s, an older expansion"):format(expansion) or nil }
end

-- The pinned view's Mission row: its name ('Class hall mission "X"') and
-- state ("Costs 100 Order Resources, you have 1240; open to this
-- character"), and HasGarrison's answer for its filter
function UsedFor.MissionRow(relation, owner)
  local name = MissionPhrase(relation):gsub("^the ", ""):gsub("^a ", ""):gsub("^%l", string.upper)
  local parts, has = MissionStates(relation, not (owner and owner.isViewer))
  local state = #parts > 0 and (table.concat(parts, "; "):gsub("^%l", string.upper)) or nil
  return name, state, has
end
UsedFor.MISSION_SYSTEMS = MISSION_SYSTEMS

-- Data format 21 (Task #405): an ensemble piece's look comes with its
-- ensemble. Buying or using the ensemble collects the piece's appearance,
-- never the item, so the piece isn't "sold by" the ensemble's vendor. The
-- ensemble is read as a purchase's e thing (Facts.Buys: the set collected or
-- not, its name), one shared reference per set so the reads are kept (rule 9)
local ensembleRefs = {}
local function EnsembleOf(setID, owner)
  local ref = ensembleRefs[setID]
  if not ref then
    ref = { kind = "buys", thing = "e", id = setID }
    ensembleRefs[setID] = ref
  end
  local ok, thing = pcall(Recollect.Facts.Buys.Resolve, ref, owner)
  return ok and type(thing) == "table" and thing or nil
end

local SET_WORDS = { have = "you have the ensemble", missing = "you don't have the ensemble" }
local LOOK_WORDS = { have = "you have this look", missing = "this look isn't collected",
  unavailable = "this character can't collect this look" }

-- The ensemble's name (the set's, else its item's) and the words of its state
-- and of this piece's look, for the line and the pinned row: the look is the
-- piece's own appearance as Facts.Buys.Product reads it, its tooltip agreeing
-- (rule 5); only the set's state on another character's copy. Returns name,
-- the words in order, the set's state and the look's
function UsedFor.EnsembleLook(relation, itemID, owner)
  local stateless = not (owner and owner.isViewer)
  local set = EnsembleOf(relation.id, owner)
  local item = Relations().ThingItem("e", relation.id)
  local name = set and set.name
  if not name and item then
    -- the ensemble's item is named "Ensemble: <set>"; the line says "the ensemble" already
    name = Recollect.Facts.Item.Name(item)
    if type(name) == "string" then name = name:gsub("^Ensemble: ", "") end
  end
  local words, setState, lookState = {}, set and set.state, nil
  if SET_WORDS[setState] then words[#words + 1] = SET_WORDS[setState] end
  if not stateless and Recollect.Utilities.IsPositiveID(itemID) then
    local ok, look = pcall(Recollect.Facts.Buys.Product, itemID, owner)
    if ok and type(look) == "table" and look.what == "appearance" then
      lookState = look.state
      local lookWords = LOOK_WORDS[lookState]
      if lookState == "have" and look.otherItem then lookWords = "you have this look from another item" end
      if lookWords then words[#words + 1] = lookWords end
    end
  end
  return name, words, setState, lookState, item
end

-- "Its look comes with the ensemble Vestments of the Eternal Blossom (you
-- don't have the ensemble; this look isn't collected)": information only,
-- never a need; the line ranks with what is still to get only while both
-- the ensemble and the look are missing
local function EnsembleLookLine(relation, itemID, owner)
  local name, words, setState, lookState, item = UsedFor.EnsembleLook(relation, itemID, owner)
  local text = "Its look comes with "
    .. (name and ("the ensemble " .. (item and Named("item", item, name) or name)) or "an ensemble")
  if #words > 0 then text = ("%s (%s)"):format(text, table.concat(words, "; ")) end
  local colors, V = Colors(), Verdict()
  if lookState == "have" or setState == "have" then
    return { text = text, color = colors[V.DONE], tier = TIER_CLOSED }
  end
  if setState == "missing" and lookState == "missing" then
    return { text = text, color = colors[V.USEFUL], tier = TIER_OPEN }
  end
  return { text = text, color = U.Colors.LIGHT_GRAY, tier = TIER_INFO }
end

local function Line(relation, places, budget, stateless, itemID, owner, tip)
  local kind = relation.kind
  if NEW_SOURCES[kind] then return NEW_SOURCES[kind](relation, stateless, places, itemID) end
  if QUEST_LEADS[kind] then
    local line = QuestLine(QUEST_LEADS[kind], relation.id, WITH_REWARDS[kind], budget, stateless, owner)
    -- a reward at the end of a quest chain says how the chain starts (Task #106)
    if line and (kind == "reward" or kind == "choice") and not line.detail then
      local ok, words = pcall(UsedFor.ChainSummary, relation.id, owner)
      if ok and words then line.detail = words end
    end
    return line, line == nil
  end
  if kind == "achievementReward" then return AchievementRewardLine(relation) end
  if kind == "opens" then return OpensLine(relation, places, stateless, itemID) end
  if kind == "usedAt" then
    local who, npc = Recollect.Facts.Vendors.Describe(relation.id, "an NPC")
    if not who then return nil end
    if npc then
      npc.what, npc.role, npc.itemID = "the NPC", "usedAt", itemID
      places[#places + 1] = npc
    end
    local takes = (relation.count or 1) > 1 and (": takes %s"):format(Recollect.Utilities.Count(relation.count)) or ""
    return { text = "Used at " .. who .. takes, color = U.Colors.LIGHT_GRAY, place = npc }
  end
  if kind == "soldBy" then
    local seller, vendor = Recollect.Facts.Vendors.Describe(relation.id)
    if not seller then return nil end
    if vendor then
      vendor.role, vendor.itemID = "soldBy", itemID
      places[#places + 1] = vendor
    end
    return { text = "Sold by " .. seller .. UsedFor.PriceWords(relation), color = U.Colors.LIGHT_GRAY, place = vendor }
  end
  if kind == "dropsFrom" then
    -- "Name (Zone)", or "a creature in Zone (x, y)" until its name is read
    local who, npc = Recollect.Facts.Vendors.Describe(relation.id, "a creature")
    if not who then return nil end
    if npc then
      npc.what, npc.role, npc.itemID = "the creature", "dropsFrom", itemID
      places[#places + 1] = npc
    end
    return { text = "Drops from " .. who, color = U.Colors.LIGHT_GRAY, place = npc }
  end
  if kind == "zoneDrop" then
    if relation.id == 0 then return { text = "World drop: any enemy can drop it", color = U.Colors.LIGHT_GRAY } end
    local zone = Recollect.Facts.Vendors.ZoneName(relation.id)
    return zone and { text = "Drops from enemies in " .. zone, color = U.Colors.LIGHT_GRAY } or nil
  end
  -- Data format 10's curator findings: a fishing zone (no spot), a container
  -- it comes out of, and what opening this container can give
  if kind == "fishedIn" then
    local zone = Recollect.Facts.Vendors.ZoneName(relation.id)
    return zone and { text = "Fished in " .. zone, color = U.Colors.LIGHT_GRAY } or nil
  end
  if kind == "openedFrom" then return { text = "From opening " .. ItemName(relation.id), color = U.Colors.LIGHT_GRAY } end
  if kind == "holds" then return { text = "Opening it can give " .. ItemName(relation.id), color = U.Colors.LIGHT_GRAY } end
  -- data format 14: what using it gives, and what using another item gives it
  if kind == "gives" then return GivesLine(relation, stateless, owner) end
  if kind == "givenBy" then return { text = "From using " .. ItemName(relation.id), color = U.Colors.LIGHT_GRAY } end
  -- data format 15: a mount customization, reputation, a fishing lure
  if kind == "customizes" then return CustomizesLine(relation, stateless, owner, tip) end
  if kind == "reputation" then return ReputationLine(relation, stateless, owner) end
  if kind == "lure" then return LureLine(relation, stateless, owner) end
  -- data format 16: a class token's piece on a route that doesn't serve this
  -- character (the ones that do are one line, TokenLine)
  if kind == "givesByClass" then return { text = "Can give " .. ItemName(relation.id), color = U.Colors.LIGHT_GRAY } end
  -- data format 17: what buys it, a zone's activities, Archaeology
  if kind == "boughtWith" then return BoughtWithLine(relation, places, itemID) end
  if kind == "zoneReward" then
    local zone = Recollect.Facts.Vendors.ZoneName(relation.id) or ("map " .. relation.id)
    return { text = "A reward from activities in " .. zone, color = U.Colors.LIGHT_GRAY }
  end
  if kind == "archaeology" then return ArchaeologyLine(relation, stateless) end
  -- data format 19: an event no zone holds
  if kind == "eventReward" then return EventRewardLine(relation, budget, stateless, owner) end
  -- data format 20: a follower mission's reward
  if kind == "missionReward" then return MissionLine(relation, stateless, owner) end
  -- data format 21: an ensemble piece's look
  if kind == "ensembleLook" then
    return EnsembleLookLine(relation, itemID, stateless and { isViewer = false, faction = owner and owner.faction } or owner)
  end
  -- data format 18: given to new characters
  if kind == "newCharacter" then return { text = UsedFor.NewCharacterWords(relation, owner), color = U.Colors.LIGHT_GRAY } end
  if kind == "craftedBy" then return CraftedLine(relation, stateless) end
  if kind == "foundIn" then
    local object = Recollect.Facts.Vendors.Object(relation.id)
    local zone = object and object.mapID and Recollect.Facts.Vendors.ZoneName(object.mapID)
    -- a chest, a node or a spot on the ground: the data doesn't say which;
    -- what opens it, when an item's j code names it (Task #437)
    local opened = UsedFor.OpenedWords(relation.id)
    -- looted or not, from its loot quest (Task #439), on the logged-in character's copy
    local looted = not stateless and object and Recollect.Facts.Chains.LootState(relation.id, owner or { isViewer = true })
    local state = (looted == "done" and " (looted)") or (looted == "open" and " (not looted yet)") or ""
    -- the way back: what opens it and how you get that (Task #439)
    local detail = Lead.PathDetail(relation, owner, stateless)
    if not zone then return { text = "Found at a spot in the world" .. opened .. state, color = U.Colors.LIGHT_GRAY, detail = detail } end
    local place = { mapID = object.mapID, x = object.x, y = object.y, zone = zone, what = "the spot", role = "found",
      itemID = itemID }
    places[#places + 1] = place
    return { text = ("Found at a spot in %s (%.1f, %.1f)%s%s"):format(zone, object.x * 100, object.y * 100, opened, state),
      color = U.Colors.LIGHT_GRAY, place = place, detail = detail }
  end
  if kind == "criterion" then
    return AchievementLine(Recollect.Facts.Achievements.Get(relation.id, relation.criteria), relation.id, nil, stateless)
  end
  if kind == "linked" then return LinkedLine(relation) end
  -- The count after the other item's name is of that item, never of this one
  if kind == "makes" then return MakesLine(relation, stateless, owner) end
  if kind == "partOf" then return PartOfLine(relation, stateless, itemID, owner) end
  if kind == "madeFrom" then
    local have = not stateless and Owned(relation.id) or nil
    local text = ("Made from %s %s"):format(N(relation.count or 1), ItemName(relation.id))
    return { text = have and ("%s (you have %s of those)"):format(text, N(have)) or text, color = U.Colors.LIGHT_GRAY,
      detail = Lead.PathDetail(relation, owner, stateless) }
  end
  if kind == "recipeFor" then return { text = "Teaches how to make " .. ItemName(relation.id), color = U.Colors.LIGHT_GRAY } end
  if kind == "teaches" then return TeachesLine(relation, stateless) end
  if kind == "taughtBy" then return { text = "Its recipe is taught by " .. ItemName(relation.id), color = U.Colors.LIGHT_GRAY } end
  if kind == "currency" then return CurrencyLine(relation, places, stateless, tip) end
  return nil
end

-------------------------------------------------------------------------------
-- An older expansion's system (item 5, Purposes.Legacy.System: a Runecarving
-- memory, a Heart of Azeroth essence, an Ashjra'kamas upgrade): what the
-- system was, and in the detail whether it still does anything (the
-- system's stillWords). English clients only (the system is named from the Use
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
    lines[#lines + 1] = { text = ("%s's %s scan%s recorded %d %s using this"):format(r.name, r.profession,
      r.scannedAt and (" (" .. date("%b %d", r.scannedAt) .. ")") or "", r.count, r.count == 1 and "recipe" or "recipes"),
      color = U.Colors.LIGHT_GRAY, tier = TIER_INFO, recorded = true }
  end
  return lines
end

local SkillLineName = SkillName

-- The recipes the Lab read that take it (g codes): one line per profession,
-- closing "(you don't have Tailoring)" on the logged-in character's copy of
-- a profession it is read not to have (Task #334)
local function ReagentLines(relations, stateless)
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
    -- reagentTotal: every profession's count together, which a headline
    -- names instead of one profession's (item 11)
    local text = ("Reagent in %d %s%s"):format(#list, profession and (profession .. " ") or "",
      #list == 1 and "recipe" or "recipes")
    local lacks = LacksWords(skill, stateless)
    if lacks then text = ("%s (%s)"):format(text, lacks) end
    lines[#lines + 1] = { text = text, color = U.Colors.LIGHT_GRAY, reagentTotal = #relations }
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

-- A note line: no use of its own
local function Note(text)
  return { text = text, color = U.Colors.LABEL_GRAY, note = true }
end

-- A note that stands for lines not shown ("and 3 more", "2 more still being
-- checked"): more = true, so the audit panel can say "for everything" instead
local function More(text)
  local line = Note(text)
  line.more = true
  return line
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
            vendor.role, vendor.itemID = "payment", entry.ofItem
            places[#places + 1] = vendor
          end
        end
        local line = Build(BuyLine, entry, entry.group ~= nil)
        line.buy = true   -- what it buys: the audit panel sums these up in one line
        out[#out + 1] = line
        shown = shown + 1
      end
      if shown >= max then break end
    end
  end
  local more = #lines + (total or #entries) - shown
  if more > 0 then out[#out + 1] = More(("and %d more"):format(more)) end
  if pending > 0 then out[#out + 1] = More(("%d more still being checked"):format(pending)) end
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
  return { text = lead .. words, color = Colors()[Verdict().OUTDATED], note = true, gone = true, every = every or nil }
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
  if not Season or type(Season.RemovedText) ~= "function" then return nil end
  local ok, text = pcall(Season.RemovedText, itemID)
  if not ok or not text then return nil end
  return { text = text, color = Colors()[Verdict().OUTDATED], tier = TIER_CLOSED }
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
  if not ok or (type(entries) == "table" and #entries > 0) then return true end
  -- a secret still in the game (or one that can't be read while the
  -- manifest names the item) is a live use too
  local okSecret, inSecret = Recollect.Facts.SecretUse(itemID)
  if not okSecret or inSecret == true then return true end
  -- so is a collectible the item teaches (a toy, a mount, a pet, an
  -- ensemble), read live by its own check; one that can't be read counts
  -- too, so "every use is gone" is never said of it (Task #445, audit R12:
  -- the Whistle of the Mottled Red Raptor teaches a mount, its quest use gone)
  return UsedFor.TeachesCollectible(itemID) ~= false
end

-- TeachesCollectible(itemID, ctx): Registry.CollectionItem for an item: true
-- (a toy, mount, pet or ensemble it teaches; an illusion too when ctx has the
-- tooltip), false, or "unreadable"; ctx is a check's own when it has one
function UsedFor.TeachesCollectible(itemID, ctx)
  if not Recollect.Utilities.IsPositiveID(itemID) then return false end
  ctx = ctx or { stack = { itemID = itemID }, Tooltip = function() return nil end }
  local ok, answer = pcall(Recollect.Purposes.Registry.CollectionItem, ctx)
  if not ok then return "unreadable" end
  return answer
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
  local stateless = not owner.isViewer
  local R = Relations()
  local budget = Recollect.Facts.QuestInfo.FrameBudget()
  local questApplies = R.QuestApplies(itemID, owner)
  local lines, sources, decor, buys, buyApplies, reagents, unavailable, linked = {}, {}, {}, {}, {}, {}, {}, {}
  local pieces = {}   -- what a class token gives, one line for all (data format 16)
  -- places for the waypoint: what a key opens or an NPC it is used at and a
  -- currency's vendor (in the relations' order), then one that takes it, one
  -- it buys from, and last a source (a seller, a creature or a spot)
  local places, takingPlaces, sourcePlaces = {}, {}, {}
  local sellerLines = {}   -- [SellerKey] = the seller line kept (one vendor listed under several creature IDs)
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
    elseif kind == "givesByClass" and applies == true then
      pieces[#pieces + 1] = relation.id
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
        AddSeller(isSource and sources or lines, sellerLines, SellerKey(relation, line), line)
      end
    end
  end
  Append(lines, LinkedLines(linked, stateless, itemID))
  -- where combining it leads (Task #438)
  Append(lines, UsedFor.CombineLeads(itemID, owner, places, relations))
  if #pieces > 0 then lines[#lines + 1] = Build(TokenLine, pieces, owner) end
  local legacy = (opts.tip or opts.facts) and LegacyLine(itemID, opts.facts, opts.tip, stateless) or nil
  if legacy then lines[#lines + 1] = legacy end
  if owner.isViewer then
    local recipes = RecipeLine(itemID)
    if recipes then lines[#lines + 1] = recipes end
    Append(lines, EndeavorLines(itemID))   -- the neighborhood's endeavor is the logged-in character's
  end
  Append(lines, RecordedLines(itemID))
  -- the secrets the item is used in (Facts.Secrets), each with its step's state
  for _, line in ipairs(UsedFor.SecretUseLines(itemID, owner)) do
    lines[#lines + 1] = line
    if line.place and not stateless then places[#places + 1] = line.place end
  end
  Append(lines, ReagentLines(reagents, stateless))
  -- Vendors recorded in game that take the item itself, or sell it
  local Vendors = Recollect.Facts.Vendors
  local taking, selling = Vendors.ForCostItem(itemID)[1], Vendors.Selling(itemID)[1]
  if taking then
    taking.role, taking.itemID = "payment", itemID
    takingPlaces[#takingPlaces + 1] = taking
    lines[#lines + 1] = { text = VendorText("Taken as payment by", taking), color = U.Colors.LIGHT_GRAY, place = taking }
  end
  if selling then
    selling.role, selling.itemID = "soldBy", itemID
    sourcePlaces[#sourcePlaces + 1] = selling
    sources[#sources + 1] = { text = VendorText("Sold by", selling), color = U.Colors.LIGHT_GRAY, place = selling }
  end
  local buyPlaces = {}
  local max = MAX_LINES
  -- every purchase tallied for the panel's one-line summary
  local tally = Tally()
  local entries, total = Entries(itemID, decor, buys, buyApplies, owner, max, budget, tally)
  local uses = Assemble(Merge(lines), entries, max, pending, buyPlaces, total)
  local gone = GoneLine(unavailable, not AnyUse(uses) and pending == 0
    and not UsedFor.LiveUse(itemID, relations, owner, questApplies))
  if gone then uses[#uses + 1] = gone end
  Append(places, takingPlaces)
  Append(places, buyPlaces)
  Append(places, sourcePlaces)
  -- the secrets whose reward the item teaches
  Append(sources, UsedFor.SecretSourceLines(itemID, owner))
  Append(sources, UsedFor.TokenSourceLines(itemID))
  -- Where it comes from keeps the relations' order, then "and N more"
  local merged, comesFrom = Merge(sources), {}
  local maxSources = MAX_SOURCES
  for i = 1, math.min(#merged, maxSources) do comesFrom[i] = merged[i] end
  if #merged > maxSources then comesFrom[#comesFrom + 1] = More(("and %d more"):format(#merged - maxSources)) end
  if pendingSources > 0 then comesFrom[#comesFrom + 1] = More(("%d more still being checked"):format(pendingSources)) end
  local removed = RemovedLine(itemID)
  if removed then
    table.insert(comesFrom, 1, removed)
  else
    local goneSources = GoneSources(unavailable)
    if goneSources > 0 then
      comesFrom[#comesFrom + 1] = Note(("%d %s no longer available"):format(goneSources,
        goneSources == 1 and "way to get it is" or "ways to get it are"))
    end
  end
  local extra = { pending = pending, pendingSources = pendingSources, buys = BuySummary(tally) }
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
-- color, links } or nil, label ("Guide note; not confirmed in game
-- yet"), confirmed, note, color }, in Data/Notes.lua's order
function UsedFor.NoteLines(itemID, owner)
  owner = owner or Recollect.Verdicts.Rows.Owner()
  local out = {}
  local budget = Recollect.Facts.QuestInfo.FrameBudget()
  for _, note in ipairs(Recollect.Facts.Notes.For(itemID)) do
    local details = {}
    if note.howMany then details[#details + 1] = "How many: " .. note.howMany end
    if note.where then details[#details + 1] = "Where: " .. note.where end
    if note.from then details[#details + 1] = "Comes from: " .. note.from end
    local label = note.confirmed and ("Guide note; confirmed in game: %s"):format(note.confirmed)
      or "Guide note; not confirmed in game yet"
    out[#out + 1] = { text = note.text, details = details, state = Build(NoteState, note, owner, budget), label = label,
      confirmed = note.confirmed, note = note, color = U.Colors.LABEL_GRAY }
  end
  return out
end

-------------------------------------------------------------------------------
-- Quest chains (Task #106, 2026-10-01; Cobanyte: "how is this mount
-- obtained? ... nothing mentions i need to run the stonevault for it"): the
-- quests that lead to a quest reward, from the data's E table
-- (Facts.Chains.QuestPath), each with what starts it or what it takes and
-- where those come from, in our own words, names as links
-------------------------------------------------------------------------------
-- Where an item comes from, in a few words ("drops from Void Speaker Eirich
-- (The Stonevault)"), from its first live source of the kinds a player looks
-- for first; nil when the data names none
function UsedFor.SourceWords(itemID, owner)
  local R, Vendors = Recollect.Facts.Relations, Recollect.Facts.Vendors
  local function Live(kind)
    local out = {}
    for _, relation in ipairs(R.Of(itemID, kind) or {}) do
      local ok, applies = pcall(R.Applies, relation, owner)
      if not ok or applies ~= "unavailable" then out[#out + 1] = relation end
    end
    return out
  end
  -- a seasonal drop first: the season's activities give it, never one boss
  if #Live("seasonDrop") > 0 then return "a seasonal drop" end
  for _, relation in ipairs(Live("dropsFrom")) do
    local who = Vendors.Describe(relation.id, "a creature")
    if who then return "drops from " .. who end
  end
  for _, relation in ipairs(Live("journalDrop")) do
    local ok, e = pcall(Vendors.Encounter, relation.id)
    if ok and e and e.name then return e.instance and ("drops from %s in %s"):format(e.name, e.instance) or ("drops from " .. e.name) end
  end
  for _, relation in ipairs(Live("soldBy")) do
    local who = Vendors.Describe(relation.id)
    if who then return "sold by " .. who end
  end
  for _, relation in ipairs(Live("zoneDrop")) do
    if relation.id == 0 then return "a world drop" end
    local zone = Vendors.ZoneName(relation.id)
    if zone then return "drops from enemies in " .. zone end
  end
  for _, relation in ipairs(Live("skinnedFrom")) do
    local who = Vendors.Describe(relation.id, "a creature")
    if who then return "skinned from " .. who end
  end
  for _, relation in ipairs(Live("gatheredBy")) do
    local words, where = GatheredWords(relation)
    if words and relation.npc then where = Vendors.Describe(relation.npc, "a creature") end
    if words and (where or not words:find("%s", 1, true)) then
      words = where and words:format(where) or words
      return words:sub(1, 1):lower() .. words:sub(2)
    end
  end
  if #Live("delveReward") > 0 then return "comes from completing a Delve" end
  for _, relation in ipairs(Live("storePromotion")) do
    if STORE_PROMOTION_SUMMARY[relation.id] then return STORE_PROMOTION_SUMMARY[relation.id] end
  end
  return nil
end

-- An item and where it comes from: "Malfunctioning Mechsuit, which drops
-- from Void Speaker Eirich (The Stonevault)"
local function ItemWithSource(itemID, owner, count)
  local name = ItemName(itemID)
  if count and count > 1 then name = ("%d %s"):format(count, name) end
  local from = UsedFor.SourceWords(itemID, owner)
  return from and ("%s, which %s"):format(name, from) or name
end

-- One step's words: its title and state, then what starts it or what it takes
local function StepLine(index, step, owner, budget, last)
  local title, rank, state, color = QuestState(step.questID, budget, not owner or owner.isViewer == false)
  local head =("%d. %s"):format(index, title and (state and ("%s (%s)"):format(title, state) or title) or "A quest still loading")
  local parts, chain = {}, step.chain
  if index == 1 and chain and chain.any and #chain.before > 0 then
    parts[#parts + 1] = ("after any of %d earlier quests"):format(#chain.before)
  end
  for _, itemID in ipairs(chain and chain.starters or {}) do
    parts[#parts + 1] = "starts from " .. ItemWithSource(itemID, owner)
  end
  for _, cost in ipairs(chain and chain.costs or {}) do
    parts[#parts + 1] = "takes " .. ItemWithSource(cost.itemID, owner, cost.count)
  end
  if last and #parts == 0 then parts[1] = "rewards it" end
  -- a quest done carries the check, one not done (or on, or repeatable) the
  -- cross; one that can't be read or is still loading none (Task #334)
  local tier = title and QUEST_TIER[rank] or nil
  local icon = (rank == 4 and "done") or (rank == 0 and "na") or (tier == TIER_OPEN and "no") or nil
  return { text = #parts > 0 and ("%s: %s"):format(head, table.concat(parts, "; ")) or head,
    color = color or U.Colors.LIGHT_GRAY, icon = icon }
end

-- ChainLines(questID, owner): the lines under a quest reward that say how to
-- reach that quest: "A chain of 5 quests from Speaker Jurlax (The Ringing
-- Deeps):", then each quest, first to last; nil when the quest is no chain
-- (no earlier quest, nothing that starts it, nothing it takes)
function UsedFor.ChainLines(questID, owner)
  owner = owner or Recollect.Verdicts.Rows.Owner()
  local path, earlier = Recollect.Facts.Chains.QuestPath(questID)
  local only = path[1]
  if #path == 0 or (#path == 1 and not (only.chain and (#only.chain.starters > 0 or #only.chain.costs > 0))) then
    return nil
  end
  local budget = Recollect.Facts.QuestInfo.FrameBudget()
  local giver = Recollect.Facts.Relations.QuestGiver(path[1].questID)
  local who = giver and giver.npcID and Recollect.Facts.Vendors.Describe(giver.npcID, "an NPC")
  local count = #path + (earlier or 0)
  local head = count == 1 and "To get this quest" or ("A chain of %d quests"):format(count)
  local lines = { { text = (who and ("%s from %s"):format(head, who) or head) .. ":", color = U.Colors.LABEL_GRAY } }
  if earlier and earlier > 0 then
    lines[#lines + 1] = { text = ("(%d earlier %s before these)"):format(earlier, earlier == 1 and "quest" or "quests"), color = U.Colors.LABEL_GRAY }
  end
  for i, step in ipairs(path) do
    lines[#lines + 1] = Build(StepLine, i + (earlier or 0), step, owner, budget, i == #path)
  end
  return lines
end

-- ChainSummary(questID, owner): the chain in one sentence, for the audit
-- panel's reward line: "The last of 5 quests; the first starts from
-- Malfunctioning Mechsuit, which drops from Void Speaker Eirich (The
-- Stonevault)"; nil when the quest is no chain
function UsedFor.ChainSummary(questID, owner)
  local path, earlier = Recollect.Facts.Chains.QuestPath(questID)
  local count = #path + (earlier or 0)
  if count < 2 then return nil end
  local first = path[1].chain
  local start = first and first.starters[1]
  local words = ("The last of %d quests"):format(count)
  if start and (earlier or 0) == 0 then
    words = ("%s; the first starts from %s"):format(words, ItemWithSource(start, owner or Recollect.Verdicts.Rows.Owner()))
  end
  return words
end

-------------------------------------------------------------------------------
-- Secrets (Facts.Secrets; the secrets design of Task #391, sections 2.6, 5
-- and 7): each step in our own words, every name read live,
-- with its state; the USED FOR line of an item a secret uses, the COMES
-- FROM line of an item that teaches a secret's reward, and the Secret tab's
-- steps (UI.DetailData), all from SecretSteps so they never disagree
-------------------------------------------------------------------------------
-- A step's state, as the Secret tab, the panel and WHAT IT'S FOR word it
-- (Task #407, from the secrets UI review): a step merely not started is
-- pending, never an error; some of what it gets held is in progress; a
-- read that failed is unavailable, one still coming is loading. mark is the
-- UI.Icons kind beside it, one on every step so the column is never ragged
-- (Task #411): a check, an empty circle (blue in progress, green with its
-- materials held), the waiting mark, the warning, and a gray dash for a step
-- the game reports nothing about, or one only its own character can be asked
local SECRET_STATES = {
  done = { word = "Done", tier = TIER_CLOSED, filter = "have", mark = "done" },
  ready = { word = "Materials ready", tier = TIER_OPEN, filter = "missing", mark = "ready" },
  progress = { word = "In progress", tier = TIER_OPEN, filter = "missing", mark = "progress" },
  todo = { word = "Pending", tier = TIER_OPEN, filter = "missing", mark = "pending" },
  unread = { word = "Loading progress", tier = TIER_INFO, filter = "none", mark = "wait" },
  unreadable = { word = "Progress unavailable", tier = TIER_INFO, filter = "none", mark = "warn" },
  character = { word = "Check on %s", tier = TIER_INFO, filter = "none", mark = "untracked" },
  untracked = { word = "Not tracked by the game", tier = TIER_INFO, filter = "none", mark = "untracked" },
}
local FREQ_WORDS = { w = { done = "Done this week", todo = "Pending this week" },
  d = { done = "Done today", todo = "Pending today" } }

local function SecretStateColor(state)
  local V, colors = Verdict(), Colors()
  if state == "done" then return colors[V.DONE] end
  if state == "ready" then return colors[V.USE] end
  if state == "progress" then return colors[V.USEFUL] end
  if state == "todo" or state == "untracked" then return U.Colors.LIGHT_GRAY end
  return U.Colors.LABEL_GRAY
end

-- "20 Inert Phoenix Ash" (an item reference with its count)
local function CountedItem(ref)
  local name = ItemName(ref.id)
  if (ref.count or 1) > 1 then return ("%d %s"):format(ref.count, name) end
  return name
end

local function JoinWords(list)
  if #list <= 1 then return list[1] or "" end
  return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

local function ItemList(refs)
  local words = {}
  for i, ref in ipairs(refs) do words[i] = CountedItem(ref) end
  return JoinWords(words)
end

-- An NPC's name as a link of Recollect's own (rule 36): INFO_BLUE, a boss
-- the journal knows in the journal's color (as DetailData.LinkColor colors one)
local function NpcNamed(npcID, name)
  local Vendors = Recollect.Facts.Vendors
  local boss = Vendors.Boss(npcID)
  return Named("npc", npcID, name, nil, boss and boss.link and Vendors.JOURNAL_COLOR or U.Colors.INFO_BLUE)
end

local function NpcWords(npcID)
  return NpcNamed(npcID, Recollect.Facts.Vendors.NpcName(npcID)) or "an NPC"
end

-- A step's place: its own, else its NPC's or its object's, as a waypoint place
local function StepPlace(step, itemID)
  local Vendors = Recollect.Facts.Vendors
  local mapID, x, y = nil, nil, nil
  if step.at then
    mapID, x, y = step.at.mapID, step.at.x, step.at.y
  elseif step.npc then
    local p = Vendors.Position(step.npc)
    if p then mapID, x, y = p.mapID, p.x, p.y end
  elseif step.object then
    local o = Vendors.Object(step.object)
    if o and o.mapID then mapID, x, y = o.mapID, o.x, o.y end
  end
  if not mapID then return nil end
  return { mapID = mapID, x = x, y = y, zone = Vendors.ZoneName(mapID), what = "the step", role = "found", itemID = itemID }
end
UsedFor.SecretStepPlace = StepPlace

-- Where a looted item comes from: up to two creatures, else a zone (its name
-- a zone link; Task #411)
local function LootWords(itemID)
  local R = Relations()
  local names, event = {}, false
  for _, relation in ipairs(R.Of(itemID, "dropsFrom") or {}) do
    if relation.flags and relation.flags.event then event = true end
    local name = Recollect.Facts.Vendors.NpcName(relation.id)
    if name and #names < 2 then names[#names + 1] = NpcNamed(relation.id, name) end
  end
  local text
  if #names > 0 then
    text = " from " .. JoinWords(names)
  else
    local zone = (R.Of(itemID, "zoneDrop") or {})[1]
    local zoneName = zone and Recollect.Facts.Vendors.ZoneName(zone.id)
    if zoneName then text = " from enemies in " .. Named("zone", zone.id, zoneName, nil, U.Colors.INFO_BLUE) end
  end
  return (text or "") .. (event and ", during a holiday or event" or "")
end

-- SecretStepText(secret, step, itemID): what the step asks, in our words;
-- the names it uses are heard as links (Build), its zone's among them
function UsedFor.SecretStepText(secret, step, itemID)
  local Secrets = Recollect.Facts.Secrets
  if step.say then return Secrets.Text(step.say) or ("Step " .. step.label) end
  local place = StepPlace(step, itemID)
  local zone = place and place.zone
  if zone then Named("zone", place.mapID, zone, nil, U.Colors.INFO_BLUE) end
  local act = step.action
  local text
  if act == "buy" then
    text = ("Buy %s from %s"):format(ItemList(step.products), step.npc and NpcWords(step.npc) or "a vendor")
    if zone then text = text .. " in " .. zone end
    if #step.takes > 0 then text = text .. " for " .. ItemList(step.takes) end
  elseif act == "trade" then
    text = ("Hand %s to %s for %s"):format(ItemList(step.takes), step.npc and NpcWords(step.npc) or "an NPC",
      CountedItem(step.makes))
  elseif act == "loot" then
    text = "Get " .. CountedItem(step.makes) .. LootWords(step.makes.id)
  elseif act == "gather" then
    text = ("Collect %s from a spot%s"):format(CountedItem(step.makes), zone and (" in " .. zone) or "")
  elseif act == "click" then
    text = zone and ("Click the spot in %s (%.1f, %.1f)"):format(zone, place.x * 100, place.y * 100) or "Click the spot"
    if #step.products > 0 then text = text .. " to get " .. ItemList(step.products) end
  elseif act == "use" then
    text = ("Use %s"):format(ItemList(#step.tools > 0 and step.tools or step.takes))
    if #step.products > 0 then text = text .. " to get " .. ItemList(step.products) end
    if zone then text = text .. " in " .. zone end
  elseif act == "talk" then
    text = "Talk to " .. NpcWords(step.npc) .. (zone and (" in " .. zone) or "")
  elseif act == "kill" then
    text = "Defeat " .. NpcWords(step.npc) .. (zone and (" in " .. zone) or "")
  elseif act == "quest" then
    local title = QuestState(step.quest, Recollect.Facts.QuestInfo.FrameBudget(), true)
    text = ("Turn in %s"):format(title or ("quest " .. step.quest))
    if step.npc then text = text .. " to " .. NpcWords(step.npc) end
    if zone then text = text .. " in " .. zone end
    if #step.takes > 0 then text = text .. ", with " .. ItemList(step.takes) end
  elseif act == "fish" then
    text = zone and ("Fish in %s"):format(zone) or "Fish"
  elseif act == "go" then
    text = zone and ("Go to %s (%.1f, %.1f)"):format(zone, place.x * 100, place.y * 100) or "Go to the spot"
  elseif act == "wait" then
    text = step.freq == "d" and "Come back after the daily reset" or "Come back after the weekly reset"
  else
    text = "Step " .. step.label
  end
  return text
end

-- One prerequisite or hint of a step (Task #411: every kind the data names,
-- not quests alone): its name, its state in words or nil, whether it is met
-- (true, false, or nil when that can't be read or isn't the viewer's to
-- read) and, for a hidden flag a step of the secret sets, that step's label
-- (the Secret tab words it as that step, with a jump link)
local function NeedWords(secret, ref, owner, budget)
  local kind, id = ref.kind, ref.id
  local viewer = owner.isViewer ~= false
  if kind == "quest" then
    local title, rank, state = QuestState(id, budget, not viewer)
    local met = nil
    if rank == 4 then met = true elseif rank == 2 or rank == 3 or rank == 5 then met = false end
    return title or ("quest " .. id), state, met
  elseif kind == "achievement" then
    local progress = Recollect.Facts.Achievements.Progress(id)
    if not progress then return ("the achievement %d"):format(id), "can't be read", nil end
    local name = ('the achievement "%s"'):format(Named("achievement", id, progress.name))
    if not viewer and progress.accountWide ~= true then return name, nil, nil end
    local words, open = Recollect.Facts.Achievements.ProgressWords(progress)
    local met = nil
    if open ~= nil then met = not open end
    return name, words, met
  elseif kind == "standing" then
    local okLabel, label = Try(seams.StandingLabel, ref.standing or 0)
    local words = ("%s with %s"):format(okLabel and type(label) == "string" and label ~= "" and label or "a standing",
      FactionName(id))
    if not viewer then return words, nil, nil end
    local ok, data = Try(seams.FactionData, id)
    local reaction = ok and type(data) == "table" and type(data.reaction) == "number"
      and not Recollect.Utilities.IsSecret(data.reaction) and data.reaction or nil
    if not reaction then return words, nil, nil end
    if reaction >= (ref.standing or 0) then return words, "reached", true end
    local now = StandingWords(id, owner)
    return words, now and ("you're " .. now) or nil, false
  elseif kind == "flag" then
    -- a flag one of the secret's own steps sets is that step
    for _, step in ipairs(secret and secret.steps or {}) do
      if step.flag == id then return nil, nil, nil, step.label end
    end
    local done = Recollect.Facts.Secrets.FlagDone(id, "u", owner)
    return "an earlier part of the secret", done == true and "done" or done == false and "not done" or nil, done
  elseif kind == "profession" then
    local name = SkillLineName(id) or "a profession"
    if not viewer then return name, nil, nil end
    local has = Recollect.Facts.Recipes.OwnsSkillLine(id)
    return name, has == true and "you have it" or has == false and "you don't have it" or nil, has
  elseif kind == "npc" then
    return NpcWords(id), nil, nil
  end
  return nil, nil, nil
end

-- What else a step names (Task #411: every kind): what it needs first that
-- isn't one of its steps (a quest, an achievement, a standing, a hidden flag,
-- a profession), each with its state, then its hints, labelled as hints and
-- never blocking. Each { text, color, need or hint, any (one of several is
-- enough: needsAny), step (a flag that is that step's, for the Secret tab to
-- word), met, links (the names heard while it was worded) }
local function StepExtras(step, owner, secret)
  local out = {}
  local budget = Recollect.Facts.QuestInfo.FrameBudget()
  local V, colors = Verdict(), Colors()
  local function Add(ref, hint)
    local line = Build(function()
      local name, state, met, label = NeedWords(secret, ref, owner, budget)
      if label then
        return { step = label, text = hint and ("Hint: if it doesn't work yet, do step %s first"):format(label)
          or ("After step " .. label) }
      end
      if not name then return nil end
      local text
      if hint then
        text = ref.kind == "quest" and ("Hint: if it isn't there yet, finish %s first"):format(name)
          or ("Hint: if it doesn't work yet, %s first"):format(ref.kind == "achievement" and ("earn " .. name)
          or ref.kind == "npc" and ("find " .. name) or ("get " .. name))
      else
        text = (ref.kind == "quest" or ref.kind == "flag") and ("After " .. name) or ("Requires " .. name)
      end
      -- the state last, in parentheses, as every line closes with it
      if state then text = ("%s (%s)"):format(text, state) end
      return { text = text, met = met }
    end)
    if not line then return end
    line.color = line.met == true and colors[V.DONE] or line.met == false and colors[V.USEFUL] or U.Colors.LABEL_GRAY
    line.need, line.hint, line.any = not hint, hint or nil, (not hint and step.needsAny) or nil
    out[#out + 1] = line
  end
  for _, ref in ipairs(step.needs) do
    if ref.kind ~= "step" then Add(ref, false) end
  end
  for _, ref in ipairs(step.hints) do Add(ref, true) end
  return out
end

-- The item's role in a step: "uses" (the step takes it, uses it as a tool,
-- or counts it among an "any N" step's choices), "gives" (the step gets it),
-- or nil; the words for the one-line summary ("ingredient for step 1"); and
-- the exact kind ("takes", "tool", "keeps" a tool it isn't known to use up
-- but does keep, "choice", "gives") for the Secret tab's role line
function UsedFor.SecretRole(step, itemID)
  if not itemID then return nil end
  for _, ref in ipairs(step.takes) do
    if ref.id == itemID then return "uses", ("ingredient for step %s"):format(step.label), "takes" end
  end
  for _, ref in ipairs(step.tools) do
    if ref.id == itemID then return "uses", ("used in step %s"):format(step.label), ref.unsure and "tool" or "keeps" end
  end
  for _, ref in ipairs(step.any and step.any.items or {}) do
    if ref.id == itemID then return "uses", ("one of the choices for step %s"):format(step.label), "choice" end
  end
  for _, ref in ipairs(step.products) do
    if ref.id == itemID then return "gives", ("you get it in step %s"):format(step.label), "gives" end
  end
  return nil
end
UsedFor.SECRET_ROLE_WORDS = { uses = "Uses this item", gives = "Gives this item" }
-- The Secret tab's role line by the exact kind, consumption said when known
-- (the merged design, Task #411)
UsedFor.SECRET_ROLE_KIND_WORDS = { takes = "Uses this item (used up)", keeps = "Uses this item (you keep it)",
  tool = "Uses this item (whether it's used up isn't known)", choice = "One of the choices", gives = "Gives this item" }

-- The step that names the item for the player (unfinished uses before a
-- finished acquisition): the first step that uses it and isn't done, else
-- the first that gets it and isn't done, else the first that uses it, else
-- the first that gets it; nil when no step names it
function UsedFor.SecretMine(steps)
  local picks = {}
  for _, s in ipairs(steps) do
    if s.role then
      local key = s.role .. (s.state == "done" and ":done" or "")
      picks[key] = picks[key] or s
    end
  end
  return picks.uses or picks.gives or picks["uses:done"] or picks["gives:done"]
end

-- What to do next: a step whose materials are all held first; else the
-- first step not done, in the curated order, with no sub-step left to do and
-- every step it needs done. A step whose state can't be read is never
-- suggested, and one the game doesn't track (a talk, a click) never holds
-- another back, since nothing would ever read it done. "Next step" only when the curated graph is complete, else
-- "Suggested next" (a missing edge is never read as no prerequisite)
function UsedFor.SecretSuggest(secret, steps)
  local byLabel, open = {}, {}
  for _, s in ipairs(steps) do byLabel[s.label] = s end
  for _, s in ipairs(steps) do
    local up = s.step.up and byLabel[s.step.up]
    if up and s.state ~= "done" and s.state ~= "untracked" then open[up.label] = true end
  end
  local label = secret.graph == "complete" and "Next step" or "Suggested next"
  for _, s in ipairs(steps) do
    if s.state == "ready" then return { label = label, entry = s } end
  end
  for _, s in ipairs(steps) do
    if (s.state == "todo" or s.state == "progress") and not open[s.label] then
      local blocked = false
      for _, ref in ipairs(s.step.needs) do
        local need = ref.kind == "step" and byLabel[ref.label]
        if need and need.state ~= "done" and need.state ~= "untracked" then blocked = true end
      end
      if not blocked then return { label = label, entry = s } end
    end
  end
  return nil
end

-- "Phoenix Wishwing, pet" and "not collected": the first reward still
-- missing (else the first), its kind, whether you have it and that state's
-- color; nil while no reward reads
function UsedFor.SecretRewardTitle(things)
  local pick
  for _, thing in ipairs(things or {}) do
    if thing.state == "missing" then pick = thing break end
  end
  pick = pick or (things and things[1])
  if not pick then return nil end
  local name = Recollect.Facts.Buys.Name(pick) or "Its reward"
  local kind = (Recollect.Facts.Secrets.KIND_WORDS[pick.what] or ""):gsub("^an? ", "")
  local V, colors = Verdict(), Colors()
  local state, color = nil, U.Colors.LABEL_GRAY
  if pick.state == "missing" then
    state, color = "not collected", colors[V.NEEDED]
  elseif pick.state == "have" then
    state, color = "collected", colors[V.DONE]
  end
  return kind ~= "" and ("%s, %s"):format(name, kind) or name, state, color
end

-- SecretSteps(secret, owner, itemID): the secret's steps for display, each
-- { step, label, depth, text, links (the names its words use, heard as they
-- were worded: UI.SecretModel makes them links), state (Facts.Secrets'
-- state, "progress" for a step whose items are partly held), stateText,
-- color, mark (UI.Icons), tier, filterState, have ("12 / 20"), held, need,
-- place, own and role (the item's: "uses" or "gives"), roleKind (SecretRole's
-- exact kind), roleText, roleWords, extras, reports (Facts.Secrets.Reports:
-- the game can say it's done) }, and a summary { done, total, tracked (the
-- steps the game reports), trackedDone, untracked, unread (steps whose state
-- can't be read), phrase, anyOrder, name (the secret's, else its first
-- reward's, nil while neither reads), mine (SecretMine's step), suggestion
-- (SecretSuggest), complete (the secret's own completion: true, false or
-- nil), things (its rewards) }
function UsedFor.SecretSteps(secret, owner, itemID)
  owner = owner or Recollect.Verdicts.Rows.Owner()
  local Secrets = Recollect.Facts.Secrets
  local states = Secrets.Steps(secret, owner)
  local out, done, unread, tracked, trackedDone = {}, 0, 0, 0, 0
  for _, step in ipairs(secret.steps) do
    local entry = states[step.label]
    local state = entry.state
    if state == "todo" and entry.held and entry.held > 0 and entry.need and entry.held < entry.need then state = "progress" end
    local key = (state == "unread" and entry.why == "unreadable") and "unreadable" or state
    local def = SECRET_STATES[key] or SECRET_STATES.unread
    local words = def.word
    if key == "character" then words = words:format(owner.name or "the character it's for") end
    local freq = FREQ_WORDS[step.freq]
    if freq and (state == "done" or state == "todo") then words = freq[state] end
    if entry.by then words = ("%s (step %s is done)"):format(words, entry.by) end
    if state == "done" then done = done + 1 end
    local reports = Secrets.Reports(step)
    if reports then
      tracked = tracked + 1
      if state == "done" then trackedDone = trackedDone + 1 end
    end
    if key == "unread" or key == "unreadable" or key == "character" then unread = unread + 1 end
    local role, roleWords, roleKind = UsedFor.SecretRole(step, itemID)
    local action = Build(function() return { text = UsedFor.SecretStepText(secret, step, itemID) } end)
    out[#out + 1] = { step = step, label = step.label, depth = step.up and 1 or 0, text = action.text, links = action.links,
      state = state, stateText = words,
      color = SecretStateColor(state), mark = def.mark, tier = freq and TIER_INFO or def.tier, filterState = def.filter,
      have = entry.held and entry.need and ("%d / %d"):format(entry.held, entry.need) or nil,
      held = entry.held, need = entry.need, reports = reports,
      place = StepPlace(step, itemID), own = role ~= nil, role = role, roleKind = roleKind,
      roleText = role and UsedFor.SECRET_ROLE_WORDS[role], roleWords = roleWords, extras = StepExtras(step, owner, secret) }
  end
  local things = Secrets.Rewards(secret, owner)
  local name = Secrets.Name(secret, owner) or (things[1] and Recollect.Facts.Buys.Name(things[1])) or nil
  local summary = { done = done, total = #secret.steps, unread = unread, tracked = tracked, trackedDone = trackedDone,
    untracked = #secret.steps - tracked,
    phrase = Recollect.Purposes.Secret.Phrase(secret, things, owner), anyOrder = Secrets.AnyOrder(secret),
    name = name, mine = itemID and UsedFor.SecretMine(out) or nil, things = things,
    complete = Secrets.Done(secret, owner) }
  if summary.complete ~= true then summary.suggestion = UsedFor.SecretSuggest(secret, out) end
  return out, summary
end

-- SecretProgressWords(done, tracked, total): "12 of 41 tracked steps done;
-- 16 the game can't track", or "3 of 8 steps done" when the game tracks every
-- step (Task #411: progress counts only what the game can report)
function UsedFor.SecretProgressWords(done, tracked, total)
  if tracked >= total then return ("%d of %d steps done"):format(done, total) end
  if tracked == 0 then return ("The game tracks none of its %d steps"):format(total) end
  return ("%d of %d tracked steps done; %d the game can't track"):format(done, tracked, total - tracked)
end

-- SecretUseText(summary): the one line that says the item is used in a
-- Warcraft secret, naming it and the item's role, with the step's state
-- ('Used in [SECRET: Phoenix Wishwing], ingredient for step 1 (pending)'): the panel's USED FOR line and the details window's WHAT IT'S
-- FOR line alike (Tasks #406 and #407); and the name, which a painter links
function UsedFor.SecretUseText(summary)
  local name = type(summary) == "table" and summary.name or nil
  local mine = type(summary) == "table" and summary.mine or nil
  local text = name and ("Used in %s"):format(Recollect.UI.SecretPanel.PlainLink(name)) or "Used in a Warcraft secret"
  if mine and mine.roleWords then text = ("%s, %s"):format(text, mine.roleWords) end
  if mine and mine.stateText then text = ("%s (%s)"):format(text, (tostring(mine.stateText):gsub("^%u", string.lower))) end
  return text, name
end

-- SecretUseLines(itemID, owner): one USED FOR line per secret the item is
-- used in (SecretUseText), marked by its step's state (line.icon, so a step
-- not started is never a red cross) and as a secret's (line.secret, the
-- secret's ID: painters give the word "secret" its look, UI.SecretPanel.Styled)
function UsedFor.SecretUseLines(itemID, owner)
  local Secrets = Recollect.Facts.Secrets
  local lines = {}
  if not Secrets or Secrets.Status() ~= "ok" then return lines end
  local seen = {}
  for _, entry in ipairs(Secrets.Uses(itemID)) do
    local secret = not seen[entry.sid] and Secrets.Get(entry.sid)
    seen[entry.sid] = true
    if secret and not secret.routeFlags:find("x", 1, true) then
      local line = Build(function()
        local _, summary = UsedFor.SecretSteps(secret, owner, itemID)
        local mine = summary.mine
        if not mine then return nil end
        return { text = (UsedFor.SecretUseText(summary)), color = mine.color, tier = mine.tier, place = mine.place,
          icon = mine.mark or false, secret = entry.sid, secretName = summary.name }
      end)
      if line then lines[#lines + 1] = line end
    end
  end
  return lines
end

-- SecretRewardText(secret, owner, done, tracked): what the item that teaches
-- a secret's reward is ('The reward of [SECRET: Phoenix Wishwing]: 3 of 8
-- steps done'), for the panel's COMES FROM and HOW TO GET MORE; done counts
-- the tracked steps done, tracked how many the game reports (every step when
-- not given), as the Secret tab counts them (SecretProgressWords)
function UsedFor.SecretRewardText(secret, owner, done, tracked)
  local name = Recollect.Facts.Secrets.Name(secret, owner)
  local what = name and ("The reward of %s"):format(Recollect.UI.SecretPanel.PlainLink(name)) or "The reward of a Warcraft secret"
  return ("%s: %s"):format(what, UsedFor.SecretProgressWords(done, tracked or #secret.steps, #secret.steps))
end

-- SecretSourceLines(itemID, owner): one COMES FROM line per secret whose
-- reward the item teaches (SecretRewardText)
function UsedFor.SecretSourceLines(itemID, owner)
  local Secrets = Recollect.Facts.Secrets
  local lines = {}
  if not Secrets or Secrets.Status() ~= "ok" then return lines end
  local seen = {}
  for _, entry in ipairs(Secrets.RewardOf(itemID)) do
    local secret = not seen[entry.sid] and Secrets.Get(entry.sid)
    seen[entry.sid] = true
    if secret then
      local states = Secrets.Steps(secret, owner or Recollect.Verdicts.Rows.Owner())
      local done, tracked = 0, 0
      for _, step in ipairs(secret.steps) do
        if Secrets.Reports(step) then
          tracked = tracked + 1
          if states[step.label].state == "done" then done = done + 1 end
        end
      end
      lines[#lines + 1] = { text = UsedFor.SecretRewardText(secret, owner, done, tracked), color = U.Colors.LIGHT_GRAY,
        tier = TIER_INFO, secret = entry.sid, secretName = Secrets.Name(secret, owner) }
    end
  end
  return lines
end

-- What the pinned view's tables share with these lines (UI.DetailData), so a
-- row and a line never disagree about a state or its words
UsedFor.parts = {
  QuestState = QuestState, Tags = Tags, TagText = TagText, AnyShown = AnyShown, NamedWords = NamedWords,
  STATE_WORDS = STATE_WORDS,
  WHAT_LABEL = WHAT_LABEL, Currency = Currency, GrantedFaction = GrantedFaction, FactionName = FactionName,
  SourceSellers = SourceSellers, Owned = Owned, SkillLineName = SkillLineName, QUEST_KIND = QUEST_KIND,
  CLASS_ARMOR = CLASS_ARMOR,
  MAX_FOLLOW = MAX_FOLLOW,
  Renown = Renown, MonthWords = MonthWords, TradingPostText = TradingPostText, BLACK_MARKET_TEXT = BLACK_MARKET_TEXT,
  STORE_PROMOTION_TEXT = STORE_PROMOTION_TEXT,
  TIER_OPEN = TIER_OPEN, TIER_INFO = TIER_INFO, TIER_CLOSED = TIER_CLOSED,
  SpellName = function(spellID)
    local ok, name = Try(seams.SpellName, spellID)
    return ok and type(name) == "string" and name ~= "" and name or nil
  end,
}

-- Tally, Count and BuySummary: the panel's purchase summary, for the suites
UsedFor._test = { seams = seams, Tally = Tally, Count = Count, BuySummary = BuySummary, SellerWords = SellerWords }
