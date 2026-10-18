-------------------------------------------------------------------------------
-- Facts.Secrets: the game's secrets, their steps and what each step uses
--
-- Data/Secrets.lua (rebuilt by /recollect-data; the secrets design of Task
-- #391, sections 2 to 5) holds one
-- string record per secret, IDs only, and a table of our own words:
--   Recollect.Data.Secrets = { dataVersion, secretsFormat, records = { [sid] = record }, text = { [n] = words } }
-- A record is fields split by byte 31, each "key=value"; its "st" field holds
-- the steps, split by byte 29, each step's fields split by byte 28. Lists use
-- ",". References are typed as the data's codes are: i<item>[x<count>][?]
-- (? after a tool whose consumption is unknown), n npc, o object, q quest,
-- f hidden flag, a achievement, m mount spell, t toy item, p pet species,
-- e ensemble set, d decor item, r recipe spell, v artifact appearance (an
-- artifactAppearanceID; Task #463), w an item's own appearance (an item ID;
-- Task #465), s spell, k<faction>.<standing>,
-- P<skill line>, c currency and z zone (a map ID; both only where a step
-- names what its words mention, mn), and #<label> a step of the same secret.
-- A record that breaks the grammar reads as unreadable, never half-read; an
-- unknown key is ignored, so a later format can add keys.
--
-- Display keys (Task #411; secretsFormat stays 1, an older reader ignores
-- them): the secret's ph=<label>:<n>,... names its stages, each starting at
-- that top-level step and running to the next stage's first step, titled by
-- text[n]; a step's ti=<n> is a short title for its action (text[n]), its
-- bg=<n> background or troubleshooting words shown folded (text[n]), and its
-- mn=<ref>[:<n>],... the things its words name, each a link in the Secret tab
-- (display only: never a use, never indexed), matched by its live name, or
-- by text[n] when the words name it otherwise (an object has no live name).
--
-- The file keeps its own validity (design 2.1): Status() is "ok", "none" (no
-- secrets shipped and no membership manifest) or "off" (the base data off,
-- the file missing while Relations' manifest N names secret items, a stamp
-- that differs from the base files' or a format this Recollect doesn't read).
-- While "off", InManifest still says which items belong to a secret, so the
-- secret check can say Can't tell instead of letting Outdated through.
-- While "ok", a record that breaks the grammar keeps its items in doubt the
-- same way (Unreadable; the overnight review's finding 1): the items its text
-- names that the manifest lists, and every manifest item while any record
-- can't be read or when no readable record uses it.
--
-- Of(kind, id) is the reverse index: every typed reference of every secret,
-- with its secret, step and role (input, tool, product, alternative, reward,
-- teaches, prerequisite, place, meta; unreadable for an item a broken
-- record names). It is built on first use and dropped with the parsed
-- records when the data changes.
--
-- A secret's route flags (fl: x gone, f0/f1 one faction, c<ids> some
-- classes, R<ids> some races, h during an event) read as a relation's do
-- (secret.flags, the shape of Facts.Relations' flags), and Applies(secret,
-- owner) decides through Relations.Applies (rule 32): h never changes it.
--
-- Steps(secret, owner) gives each step's live state (design 5):
--   done       proven done: its hidden flag or quest is flagged, its product
--              is held (the logged-in character's copy), or a completed step
--              implies it (im); a weekly or daily step's done is this reset's
--   ready      read as not done (todo or untracked), and every item it takes
--              is held; the entry's own ready field says whether every item
--              it takes is held whatever its state, so an unread completion
--              stays unread (review finding 3)
--   todo       not done
--   unread     a read failed, or quest history hasn't loaded yet
--   character  only the logged-in character can be asked (another
--              character's copy: counts, quests and character flags)
--   untracked  nothing the game reports shows it done (talk, go, kill
--              steps with no flag)
-- Every read goes through Purposes.client and Utilities.Try behind
-- Facts.Ready's gates; a failed, secret or wrongly typed answer is unread.
-- Rewards read through Facts.Buys' typed readers (Rewards(secret, owner)),
-- but an artifact appearance (v), which this file reads itself: unlocked
-- from C_ArtifactUI.GetAppearanceInfoByID (the logged-in character's answer;
-- another character's copy can't be asked), never missing on a read that
-- fails or returns nothing (Task #463); and an item's own appearance (w),
-- read through Facts.Buys.Product with the item's tooltip agreeing (rule 5):
-- done only when that item's own source is collected (Task #465).
-------------------------------------------------------------------------------
local Secrets = {}
Recollect.Facts.Secrets = Secrets

local Try = Recollect.Utilities.Try
local IsPositiveID = Recollect.Utilities.IsPositiveID
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber

Secrets.SUPPORTED_FORMATS = { [1] = true }

local FIELD, STEP, STEP_FIELD = "\31", "\29", "\28"

-- The actions a step may take (design 2.6), each with what it must name
Secrets.ACTIONS = {
  buy = { "mk" }, trade = { "tk", "mk" }, loot = { "mk" }, gather = { "mk" }, click = { "ob" }, use = { "item" },
  talk = { "np" }, kill = { "np" }, quest = { "qu" }, fish = {}, emote = { "np", "sa" }, go = { "at" },
  wait = { "fq" }, say = { "sa" },
}

-- Reward letters, read through Facts.Buys (its typed readers)
local REWARD_LETTERS = { m = true, t = true, p = true, e = true, d = true, r = true, a = true, v = true, w = true }
-- The words for a reward's kind, as the reasons name it
Secrets.KIND_WORDS = { mount = "a mount", toy = "a toy", pet = "a pet", ensemble = "an ensemble", decor = "a decor item",
  recipe = "a recipe", achievement = "an achievement", heirloom = "an heirloom", illusion = "a weapon illusion",
  appearance = "an artifact appearance", look = "an item appearance" }

local seams = {
  Data = function() return Recollect.Data and Recollect.Data.Secrets end,
  Manifest = function()
    local relations = Recollect.Data and Recollect.Data.Relations
    return type(relations) == "table" and relations.N or nil
  end,
  BaseOk = function() return Recollect.Facts.DataVersion.Ok() end,
  BaseVersion = function() return Recollect.Facts.DataVersion.Get().dataVersion end,
  SpellName = function(spellID) return C_Spell.GetSpellName(spellID) end,
  -- setID, appearanceID, name, displayIndex, unlocked, ... (may return nothing)
  ArtifactAppearance = function(appearanceID) return C_ArtifactUI.GetAppearanceInfoByID(appearanceID) end,
}

-- The parsed records and the index, for one data table
local cache = { data = nil, records = {}, index = nil, manifest = nil, manifestSource = nil }
-- The artifact appearances read (v rewards), kept while Facts.Buys keeps its
-- own answers (AppearanceThing)
local appearances = { stamp = nil, byID = {} }

local function Reset()
  cache.data, cache.records, cache.index, cache.manifest, cache.manifestSource = nil, {}, nil, nil, nil
  appearances.stamp, appearances.byID = nil, {}
end

-- The data table now, dropping what was parsed from another one
local function Data()
  local data = seams.Data()
  if data ~= cache.data then
    Reset()
    cache.data = data
  end
  return data
end

-------------------------------------------------------------------------------
-- Validity
-------------------------------------------------------------------------------

-- The manifest as a set: the item IDs the base data says belong to a secret
local function Manifest()
  local source = seams.Manifest()
  if source ~= cache.manifestSource then
    cache.manifestSource, cache.manifest = source, nil
    if type(source) == "string" then
      local set = {}
      for id in source:gmatch("%d+") do set[tonumber(id)] = true end
      cache.manifest = set
    end
  end
  return cache.manifest
end

-- Status(): "ok", "none" or "off", and why for "off" ("base", "missing",
-- "mismatch", "format")
function Secrets.Status()
  local data = Data()
  if not seams.BaseOk() then return "off", "base" end
  if type(data) ~= "table" then
    if Manifest() then return "off", "missing" end
    return "none"
  end
  if data.dataVersion ~= seams.BaseVersion() then return "off", "mismatch" end
  if not Secrets.SUPPORTED_FORMATS[data.secretsFormat] then return "off", "format" end
  if type(data.records) ~= "table" then return "off", "format" end
  return "ok"
end

-- InManifest(itemID): whether the base data names the item as part of a secret
function Secrets.InManifest(itemID)
  local set = Manifest()
  return set ~= nil and set[itemID] == true
end

-------------------------------------------------------------------------------
-- Parsing
-------------------------------------------------------------------------------

-- One typed reference, or nil when it is malformed
local function Ref(text)
  if type(text) ~= "string" then return nil end
  local letter, body = text:sub(1, 1), text:sub(2)
  if letter == "#" then
    if body:match("^[%w]+$") then return { kind = "step", label = body } end
    return nil
  end
  if letter == "i" then
    local id, rest = body:match("^(%d+)(.*)$")
    id = tonumber(id)
    if not IsPositiveID(id) then return nil end
    local count, unsure = 1, false
    if rest ~= "" then
      local n, q = rest:match("^x(%d+)(%??)$")
      if n then
        count, unsure = tonumber(n), q == "?"
      elseif rest == "?" then
        unsure = true
      else
        return nil
      end
    end
    if not count or count < 1 then return nil end
    return { kind = "item", letter = "i", id = id, count = count, unsure = unsure }
  end
  if letter == "k" then
    local faction, standing = body:match("^(%d+)%.(%d+)$")
    if not faction then return nil end
    return { kind = "standing", letter = "k", id = tonumber(faction), standing = tonumber(standing) }
  end
  local KINDS = { n = "npc", o = "object", q = "quest", f = "flag", a = "achievement", m = "mount", t = "toy", p = "pet",
    e = "ensemble", d = "decor", r = "recipe", s = "spell", P = "profession", c = "currency", z = "zone",
    v = "appearance", w = "look" }
  local kind = KINDS[letter]
  local id = tonumber(body:match("^%d+$") or "")
  if not kind or not IsPositiveID(id) then return nil end
  return { kind = kind, letter = letter, id = id }
end

local function RefList(text, allowed)
  local list = {}
  if text == nil or text == "" then return list end
  for part in text:gmatch("[^,]+") do
    local ref = Ref(part)
    if not ref or (allowed and not allowed[ref.kind]) then return nil end
    list[#list + 1] = ref
  end
  return list
end

local function Fields(text, sep)
  local fields = {}
  for part in (text .. sep):gmatch("(.-)" .. sep) do
    if part ~= "" then
      local key, value = part:match("^(%w+)=(.*)$")
      if not key then return nil end
      fields[key] = value
    end
  end
  return fields
end

local ITEMS = { item = true }
local PLACES = { npc = true }
local NEEDS = { step = true, quest = true, flag = true, achievement = true, standing = true, profession = true }
local HINTS = { quest = true, flag = true, achievement = true, npc = true, profession = true, standing = true }
local REWARDS = { mount = true, toy = true, pet = true, ensemble = true, decor = true, recipe = true, achievement = true,
  appearance = true, look = true }
local STEP_FREQ = { once = true, w = true, d = true, unknown = true }
-- What a step's words may mention (mn): anything that has a name or a place,
-- never a hidden flag (it has neither)
local MENTIONS = { item = true, npc = true, object = true, quest = true, achievement = true, mount = true, toy = true,
  pet = true, ensemble = true, decor = true, recipe = true, spell = true, profession = true, standing = true,
  currency = true, zone = true, step = true }

-- A positive text number ("12"), or nil
local function TextNumber(text)
  local n = tonumber(type(text) == "string" and text:match("^%d+$") or "")
  return n and n > 0 and n or nil
end

-- The mentions of a step (mn=<ref>[:<n>],...), or nil when one is malformed
local function Mentions(text)
  local list = {}
  if text == nil then return list end
  if text == "" then return nil end
  for part in text:gmatch("[^,]+") do
    local body, n = part:match("^(.-):(%d+)$")
    local ref = Ref(body or part)
    if not ref or not MENTIONS[ref.kind] then return nil end
    if n then
      ref.words = TextNumber(n)
      if not ref.words then return nil end
    end
    list[#list + 1] = ref
  end
  return list
end

-- One step, or nil and why
local function ParseStep(text)
  local f = Fields(text, STEP_FIELD)
  if not f or not f.n or not f.n:match("^[%w]+$") then return nil, "step label" end
  local action = f.ac
  local needsOf = action and Secrets.ACTIONS[action]
  if not needsOf then return nil, "action" end
  local step = { label = f.n, up = f.up, action = action }
  local mk = RefList(f.mk, ITEMS)
  local tk = RefList(f.tk, ITEMS)
  local to = RefList(f.to, ITEMS)
  local fo = RefList(f.fo, REWARDS)
  local ne = RefList(f.ne and f.ne:gsub("^~", "") or nil, NEEDS)
  local im = RefList(f.im, { step = true })
  local hi = RefList(f.hi, HINTS)
  if not (mk and tk and to and fo and ne and im and hi) then return nil, "reference" end
  -- what it makes: usually one item (makes), sometimes several at once (a
  -- spot that gives two things: products)
  step.products, step.makes = mk, mk[1]
  step.takes, step.tools, step.serves, step.needs, step.implies, step.hints = tk, to, fo, ne, im, hi
  step.needsAny = f.ne ~= nil and f.ne:sub(1, 1) == "~"
  -- display only (Task #411): what its words mention, its title and its folded words
  step.mentions = Mentions(f.mn)
  if not step.mentions then return nil, "mentions" end
  for key, field in pairs({ title = "ti", more = "bg" }) do
    if f[field] then
      step[key] = TextNumber(f[field])
      if not step[key] then return nil, field end
    end
  end
  if f.an then
    local n, refs = f.an:match("^(%d+):(.+)$")
    local list = refs and RefList(refs, ITEMS)
    if not n or not list or #list == 0 then return nil, "alternatives" end
    step.any = { count = tonumber(n), items = list }
  end
  -- one ID each: bare ("88045") or typed ("n88045")
  for key, kind in pairs({ np = "npc", ob = "object", qu = "quest", fg = "flag" }) do
    if f[key] then
      local bare = tonumber(f[key]:match("^%d+$") or "")
      local ref = bare and { kind = kind, id = bare } or Ref(f[key])
      if not ref or ref.kind ~= kind or not IsPositiveID(ref.id) then return nil, key end
      step[kind] = ref.id
    end
  end
  step.scope = f.sc or "u"
  if step.scope ~= "c" and step.scope ~= "a" and step.scope ~= "u" then return nil, "scope" end
  if f.at then
    local map, x, y = f.at:match("^(%d+),(%d+),(%d+)$")
    if not map or tonumber(x) > 1000 or tonumber(y) > 1000 then return nil, "place" end
    step.at = { mapID = tonumber(map), x = tonumber(x) / 1000, y = tonumber(y) / 1000 }
  end
  step.freq = f.fq or "unknown"
  if not STEP_FREQ[step.freq] then return nil, "frequency" end
  if f.sa then
    step.say = tonumber(f.sa)
    if not IsPositiveID(step.say) then return nil, "text" end
  end
  -- what the action must name
  local present = { mk = step.makes, tk = #tk > 0, to = #to > 0, np = step.npc, ob = step.object, qu = step.quest,
    at = step.at, sa = step.say, fq = step.freq ~= "unknown", item = #to > 0 or #tk > 0 }
  for _, key in ipairs(needsOf) do
    if not present[key] then return nil, "action " .. action .. " needs " .. key end
  end
  return step
end

-- Whether the steps' needs form a cycle
local function Cyclic(steps, byLabel)
  local mark = {}
  local function Visit(step)
    if mark[step] == 1 then return true end
    if mark[step] == 2 then return false end
    mark[step] = 1
    for _, ref in ipairs(step.needs) do
      if ref.kind == "step" and Visit(byLabel[ref.label]) then return true end
    end
    mark[step] = 2
    return false
  end
  for _, step in ipairs(steps) do
    if Visit(step) then return true end
  end
  return false
end

local SECRET_FREQ = { once = true, ["repeat"] = true, unknown = true }

-- A secret's route flags as Facts.Relations reads a route's (its Flags,
-- local there): nil for none
local function RouteFlags(text)
  if not text or text == "" then return nil end
  local flags = {}
  if text:find("x", 1, true) then flags.unavailable = true end
  local faction = text:match("f(%d)")
  if faction then flags.faction = tonumber(faction) end
  for key, letter in pairs({ classes = "c", races = "R" }) do
    local ids = text:match(letter .. "([%d%.]+)")
    if ids then
      flags[key] = {}
      for id in ids:gmatch("%d+") do flags[key][tonumber(id)] = true end
    end
  end
  if text:find("h", 1, true) then flags.event = true end
  return flags
end

-- Parse(sid, record): the secret, or nil and why (exposed for the suites)
function Secrets.Parse(sid, record)
  if type(record) ~= "string" or record == "" then return nil, "empty" end
  local f = Fields(record, FIELD)
  if not f then return nil, "field" end
  local secret = { sid = sid, att = tonumber(f.att), added = tonumber(f.ad), routeFlags = f.fl or "",
    flags = RouteFlags(f.fl) }
  secret.name = Ref(f.nm)
  if not secret.name then return nil, "name" end
  secret.rewards = RefList(f.rw, REWARDS)
  secret.teaches = RefList(f.te, ITEMS)
  secret.meta = RefList(f.me, { achievement = true })
  if not (secret.rewards and secret.teaches and secret.meta) then return nil, "reference" end
  secret.done = f.dn
  if secret.done == "rewards" then
    if #secret.rewards == 0 then return nil, "no rewards to complete" end
  elseif secret.done == "steps" then
    -- every top-level step done
  else
    local ref = Ref(secret.done)
    if not ref or not (ref.kind == "flag" or ref.kind == "quest" or ref.kind == "achievement") then return nil, "done" end
    secret.done = ref
  end
  secret.freq = f.fq or "unknown"
  if not SECRET_FREQ[secret.freq] then return nil, "frequency" end
  secret.graph = f.gr == "complete" and "complete" or "partial"
  if not f.st or f.st == "" then return nil, "no steps" end
  local steps, byLabel = {}, {}
  for text in (f.st .. STEP):gmatch("(.-)" .. STEP) do
    if text ~= "" then
      local step, why = ParseStep(text)
      if not step then return nil, why end
      if byLabel[step.label] then return nil, "label twice" end
      step.index = #steps + 1
      steps[#steps + 1], byLabel[step.label] = step, step
    end
  end
  for _, step in ipairs(steps) do
    if step.up and not byLabel[step.up] then return nil, "parent" end
    for _, list in ipairs({ step.needs, step.implies, step.mentions }) do
      for _, ref in ipairs(list) do
        if ref.kind == "step" and not byLabel[ref.label] then return nil, "step reference" end
      end
    end
  end
  if Cyclic(steps, byLabel) then return nil, "cycle" end
  secret.steps, secret.byLabel = steps, byLabel
  -- the stages (ph, Task #411): each a top-level step's label and the number
  -- of its title, in step order; one that breaks this makes the secret unreadable
  if f.ph then
    local stages, last = {}, 0
    for part in (f.ph .. ","):gmatch("([^,]*),") do
      local label, n = part:match("^([%w]+):(%d+)$")
      local step = label and byLabel[label]
      n = TextNumber(n)
      if not step or step.up or not n or step.index <= last then return nil, "stages" end
      last = step.index
      stages[#stages + 1] = { label = label, text = n, index = step.index }
    end
    secret.stages = stages
  end
  -- each reward as the relation Facts.Buys reads, kept with the secret so
  -- Buys' memo keys on a table that lasts
  secret.rewardRelations = {}
  for i, ref in ipairs(secret.rewards) do
    secret.rewardRelations[i] = { thing = ref.letter, id = ref.id }
  end
  return secret
end

-- Get(sid): the secret, or nil and why ("off", "missing", or the parse's why)
function Secrets.Get(sid)
  if Secrets.Status() ~= "ok" then return nil, "off" end
  local kept = cache.records[sid]
  if kept == nil then
    local record = cache.data.records[sid]
    if record == nil then return nil, "missing" end
    local secret, why = Secrets.Parse(sid, record)
    kept = secret or { unreadable = why or "grammar" }
    cache.records[sid] = kept
  end
  if kept.unreadable then return nil, kept.unreadable end
  return kept
end

-- All(): every sid, ascending
function Secrets.All()
  if Secrets.Status() ~= "ok" then return {} end
  local list = {}
  for sid in pairs(cache.data.records) do
    if type(sid) == "number" then list[#list + 1] = sid end
  end
  table.sort(list)
  return list
end

-- Text(n): our own words for a step, or nil
function Secrets.Text(n)
  local data = Data()
  local text = type(data) == "table" and type(data.text) == "table" and data.text[n]
  return type(text) == "string" and text or nil
end

-------------------------------------------------------------------------------
-- The reverse index
-------------------------------------------------------------------------------

local function Add(index, ref, sid, label, role)
  if not ref or not ref.id then return end
  local kind = ref.kind
  -- a mount, toy, pet and the rest are rewards: one key for the index
  if REWARDS[kind] and role == "reward" then kind = "reward:" .. ref.letter end
  local byKind = index[kind]
  if not byKind then
    byKind = {}
    index[kind] = byKind
  end
  local list = byKind[ref.id]
  if not list then
    list = {}
    byKind[ref.id] = list
  end
  list[#list + 1] = { sid = sid, step = label, role = role }
end

-- A record that can't be read still names its items (review finding 1):
-- every typed item in its text (after "=", "," or ":") that the manifest
-- lists, indexed as unreadable. Its text may be empty or cut short, so what
-- it names is never taken as all it uses: while any record can't be read,
-- every manifest item is in doubt (index.broken; the verify round)
local function AddBroken(index, sid, why)
  index.broken = index.broken or why or "grammar"
  local record = cache.data.records[sid]
  if type(record) ~= "string" then return end
  local manifest, seen = Manifest(), {}
  for id in record:gmatch("[=,:]i(%d+)") do
    id = tonumber(id)
    if IsPositiveID(id) and not seen[id] and (not manifest or manifest[id]) then
      seen[id] = true
      Add(index, { kind = "item", id = id }, sid, nil, "unreadable")
    end
  end
end

local function BuildIndex()
  local index = {}
  for _, sid in ipairs(Secrets.All()) do
    local secret, why = Secrets.Get(sid)
    if not secret then AddBroken(index, sid, why) end
    if secret then
      for _, ref in ipairs(secret.rewards) do Add(index, ref, sid, nil, "reward") end
      for _, ref in ipairs(secret.teaches) do Add(index, ref, sid, nil, "teaches") end
      for _, ref in ipairs(secret.meta) do Add(index, ref, sid, nil, "meta") end
      for _, step in ipairs(secret.steps) do
        local label = step.label
        for _, ref in ipairs(step.products) do Add(index, ref, sid, label, "product") end
        for _, ref in ipairs(step.takes) do Add(index, ref, sid, label, "input") end
        for _, ref in ipairs(step.tools) do Add(index, ref, sid, label, "tool") end
        for _, ref in ipairs(step.any and step.any.items or {}) do Add(index, ref, sid, label, "alternative") end
        for _, ref in ipairs(step.needs) do Add(index, ref, sid, label, "prerequisite") end
        for _, ref in ipairs(step.hints) do Add(index, ref, sid, label, "prerequisite") end
        if step.npc then Add(index, { kind = "npc", id = step.npc }, sid, label, "place") end
        if step.object then Add(index, { kind = "object", id = step.object }, sid, label, "place") end
        if step.quest then Add(index, { kind = "quest", id = step.quest }, sid, label, "place") end
        if step.flag then Add(index, { kind = "flag", id = step.flag }, sid, label, "place") end
      end
    end
  end
  return index
end

local function Index()
  if not cache.index then cache.index = BuildIndex() end
  return cache.index
end

-- Of(kind, id): { { sid, step, role }, ... } (a new list), for kind "item",
-- "npc", "object", "quest", "flag", "achievement", or "reward:<letter>"
-- (a mount spell, toy, pet species and the rest)
function Secrets.Of(kind, id)
  if Secrets.Status() ~= "ok" then return {} end
  local byKind = Index()[kind]
  local list = byKind and byKind[id]
  local copy = {}
  for i, entry in ipairs(list or {}) do copy[i] = { sid = entry.sid, step = entry.step, role = entry.role } end
  return copy
end

-- The roles that make an item a use of a secret (USED FOR); a reward or the
-- item that teaches it is how to get it (COMES FROM), never a use of it
Secrets.USE_ROLES = { input = true, tool = true, product = true, alternative = true }

-- Uses(itemID): the memberships in which the item is used
function Secrets.Uses(itemID)
  local list = {}
  for _, entry in ipairs(Secrets.Of("item", itemID)) do
    if Secrets.USE_ROLES[entry.role] then list[#list + 1] = entry end
  end
  return list
end

-- RewardOf(itemID): the memberships in which the item teaches a reward
function Secrets.RewardOf(itemID)
  local list = {}
  for _, entry in ipairs(Secrets.Of("item", itemID)) do
    if entry.role == "teaches" then list[#list + 1] = entry end
  end
  return list
end

-- Unreadable(itemID): { { sid, why }, ... }, the records that can't be read
-- and may use the item (review finding 1): those whose text names it, else,
-- for a manifest item, one entry with no sid while any record can't be read
-- (its text may not name all it uses) or when no readable record uses it
-- (the manifest equals the use index the build checked, so only a record
-- this client can't read leaves it out). Empty unless Status() is "ok"
function Secrets.Unreadable(itemID)
  local list = {}
  for _, entry in ipairs(Secrets.Of("item", itemID)) do
    if entry.role == "unreadable" then
      local _, why = Secrets.Get(entry.sid)
      list[#list + 1] = { sid = entry.sid, why = why }
    end
  end
  if #list == 0 and Secrets.Status() == "ok" and Secrets.InManifest(itemID)
      and (Index().broken or #Secrets.Uses(itemID) == 0) then
    list[1] = { why = Index().broken or "no record read names it" }
  end
  return list
end

-- Applies(secret, owner): whether the secret serves the owner, as
-- Relations.Applies answers for a route: true; "unavailable" (gone, x);
-- "other" (another faction, class or race); nil when the owner's record
-- can't say. An event (h) never changes it (rule 32)
function Secrets.Applies(secret, owner)
  if not secret.flags then return true end
  return Recollect.Facts.Relations.Applies(secret, owner)
end

-- LiveUse(itemID): whether the item is used in a secret still in the game,
-- for any character (or whether that can't be told: the secrets off with the
-- item in the manifest, or a record naming it that can't be read), for
-- UsedFor.LiveUse and the removed check
function Secrets.LiveUse(itemID)
  local status = Secrets.Status()
  if status == "off" then return Secrets.InManifest(itemID) end
  if #Secrets.Unreadable(itemID) > 0 then return true end
  for _, entry in ipairs(Secrets.Uses(itemID)) do
    local secret = Secrets.Get(entry.sid)
    if not secret or not (secret.flags and secret.flags.unavailable) then return true end
  end
  return false
end

-- Gone(secret): whether the secret is no longer in the game (route flag x)
function Secrets.Gone(secret)
  return type(secret) == "table" and secret.flags ~= nil and secret.flags.unavailable == true
end

-- GoneUses(itemID): the secrets no longer in the game that the item is used
-- in, each once, in the data's order. Never a live use (LiveUse), but a
-- removed one: rule 42's removed check and USED FOR's closing line count it,
-- and the Secret tab and the No longer available tab show it (Task #463, the
-- Manager's decision 2026-10-15)
function Secrets.GoneUses(itemID)
  local list, seen = {}, {}
  for _, entry in ipairs(Secrets.Uses(itemID)) do
    if not seen[entry.sid] then
      seen[entry.sid] = true
      local secret = Secrets.Get(entry.sid)
      if secret and Secrets.Gone(secret) then list[#list + 1] = secret end
    end
  end
  return list
end

-- CoversTarget(kind, id): whether a secret gives this reward ("mount" by
-- mount spell, "pet" by species, ...), so another check need not count it
function Secrets.CoversTarget(letter, id)
  return #Secrets.Of("reward:" .. letter, id) > 0
end

-------------------------------------------------------------------------------
-- Live state
-------------------------------------------------------------------------------

local function Client() return Recollect.Purposes.client end
local function Ready() return Recollect.Facts.Ready end

local function Bool(ok, value)
  if ok and type(value) == "boolean" then return value end
  return nil
end

-- Held(itemID): bags, bank and warband bank, or nil when unreadable
function Secrets.Held(itemID)
  local ok, n = Try(Client().GetItemCount, itemID, true, false, true, true)
  if ok and IsFiniteNumber(n) then return n end
  return nil
end

-- FlagDone(questID, scope, owner): true, false, or nil and why ("loading",
-- "unreadable", "character"). scope "a" reads the account's completion, "c"
-- the character's, "u" asks IsAccountQuest; when that fails, an answer only
-- when both completions agree (QuestInfo.Done's rule, PI-09). Behind the
-- quest-history gate: before it opens, completion answers false (CORE-03)
function Secrets.FlagDone(questID, scope, owner)
  if not Ready().Quests() then return nil, "loading" end
  local client = Client()
  local viewer = not owner or owner.isViewer ~= false
  if scope == "u" then
    local isAccount = Bool(Try(client.IsAccountQuest, questID))
    if isAccount ~= nil then scope = isAccount and "a" or "c" end
  end
  if scope == "a" then
    local done = Bool(Try(client.IsQuestFlaggedCompletedOnAccount, questID))
    if done == nil then return nil, "unreadable" end
    return done
  end
  if not viewer then return nil, "character" end
  local done = Bool(Try(client.IsQuestFlaggedCompleted, questID))
  if scope == "c" then
    if done == nil then return nil, "unreadable" end
    return done
  end
  local account = Bool(Try(client.IsQuestFlaggedCompletedOnAccount, questID))
  if done ~= nil and done == account then return done end
  return nil, "unreadable"
end

-- An artifact appearance (v), as Facts.Buys gives a thing: unlocked "have",
-- locked "missing", else "unread" (a failed read, no answer, another
-- character's copy). Kept while Facts.Buys keeps its own answers (its Stamp)
local function AppearanceThing(id, owner)
  local thing = { key = "appearance:" .. id, what = "appearance", id = id, collectible = true }
  if owner and owner.isViewer == false then
    thing.state, thing.why = "unread", "character"
    return thing
  end
  local stamp = Recollect.Facts.Buys.Stamp()
  if appearances.stamp ~= stamp then appearances.stamp, appearances.byID = stamp, {} end
  local kept = appearances.byID[id]
  if kept then return kept end
  local ok, _, appearanceID, name, _, unlocked = Try(seams.ArtifactAppearance, id)
  if ok and appearanceID == id and type(unlocked) == "boolean" then
    thing.state = unlocked and "have" or "missing"
  else
    thing.state, thing.failed = "unread", true
  end
  if ok and type(name) == "string" and name ~= "" then thing.name = name end
  appearances.byID[id] = thing
  return thing
end

-- An item's own appearance (w, Task #465), as Facts.Buys.Product reads gear's
-- look (the item's tooltip agreeing, rule 5): "have" only when this item's
-- own source is collected; the look collected from another item is still
-- "missing" (otherItem), since the reward is this item's source; one this
-- character can't collect is "unread" (why "unavailable"), as is one still
-- loading, a read that fails, and another character's copy (the tooltip is
-- the logged-in character's). The name is read on every call, which also
-- asks the client for the item (Product loads nothing)
local function LookThing(id, owner)
  local thing = { key = "look:" .. id, what = "look", id = id, itemID = id, collectible = true, state = "unread" }
  local name = Recollect.Facts.Item.Name(id)
  if type(name) == "string" and name ~= "" then thing.name = name end
  if owner and owner.isViewer == false then
    thing.why = "character"
    return thing
  end
  local look, why = Recollect.Facts.Buys.Product(id, owner)
  if type(look) ~= "table" then
    thing.why = why == "loading" and "loading" or "none"
    return thing
  end
  if look.what ~= "appearance" then
    thing.why, thing.failed = "none", look.failed
    return thing
  end
  if look.state == "have" then
    thing.state, thing.otherItem = look.otherItem and "missing" or "have", look.otherItem
  elseif look.state == "missing" then
    thing.state = "missing"
  elseif look.state == "unavailable" then
    thing.why = "unavailable"
  else
    thing.failed = look.failed
  end
  return thing
end

-- One reward (or naming) relation, read: an artifact appearance and an
-- item's look here, every other letter through Facts.Buys
local function Resolve(relation, owner)
  if relation.thing == "v" then return AppearanceThing(relation.id, owner) end
  if relation.thing == "w" then return LookThing(relation.id, owner) end
  return Recollect.Facts.Buys.Resolve(relation, owner)
end

-- Rewards(secret, owner): each reward as Facts.Buys reads it ({ what, id,
-- state, name, ... }), and the whole: "have" (every one), "missing" (any),
-- or "unread"
function Secrets.Rewards(secret, owner)
  owner = owner or Recollect.Verdicts.Rows.Owner()
  local things, all = {}, "have"
  for i, relation in ipairs(secret.rewardRelations) do
    local thing = Resolve(relation, owner)
    things[i] = thing
    local state = thing and thing.state
    if state == "missing" then
      all = "missing"
    elseif state ~= "have" and all == "have" then
      all = "unread"
    end
  end
  if #things == 0 then all = nil end
  return things, all
end

-- Whether a quest step's quest comes back (the data's frequency, or the
-- step's own weekly or daily): its completion then proves no one turn-in of
-- several (Task #454: the nine offerings of one repeatable quest, sid 122)
local function QuestRecurs(step)
  if step.freq == "w" or step.freq == "d" then return true end
  local Relations = Recollect.Facts.Relations
  local ok, freq = pcall(Relations.Frequency, step.quest)
  return ok and freq ~= nil
end

-- One step's own state before implications: its hidden flag, else its quest
-- (a quest that comes back and makes something reads what it made instead),
-- else what it makes held
local function OwnState(step, owner)
  local viewer = not owner or owner.isViewer ~= false
  local flag = step.flag or (step.action == "quest" and step.quest) or nil
  if flag and not step.flag and step.makes and QuestRecurs(step) then flag = nil end
  if flag then
    local done, why = Secrets.FlagDone(flag, step.flag and step.scope or "u", owner)
    if done == nil then return why == "character" and "character" or "unread", why end
    return done and "done" or "todo"
  end
  if step.makes then
    if not viewer then return "character" end
    -- every product held at its count
    for _, ref in ipairs(step.products) do
      local held = Secrets.Held(ref.id)
      if held == nil then return "unread", "unreadable" end
      if held < ref.count then return "todo" end
    end
    return "done"
  end
  return "untracked"
end

-- Steps(secret, owner): { [label] = { state, why, by, held, need, ready } }
-- by: the label of the step whose completion implied this one
function Secrets.Steps(secret, owner)
  owner = owner or Recollect.Verdicts.Rows.Owner()
  local viewer = owner.isViewer ~= false
  local states = {}
  for _, step in ipairs(secret.steps) do
    local state, why = OwnState(step, owner)
    local entry = { state = state, why = why }
    if step.makes and viewer then entry.held, entry.need = Secrets.Held(step.makes.id), step.makes.count end
    states[step.label] = entry
  end
  -- a step done proves the steps it implies (im), repeatedly
  local changed = true
  while changed do
    changed = false
    for _, step in ipairs(secret.steps) do
      if states[step.label].state == "done" then
        for _, ref in ipairs(step.implies) do
          local other = states[ref.label]
          if other.state ~= "done" then
            other.state, other.by, changed = "done", step.label, true
          end
        end
      end
    end
  end
  -- ready: read as not done, with every item it takes held (the logged-in
  -- character's); a completion that can't be read stays so, with ready
  -- beside it (review finding 3)
  for _, step in ipairs(secret.steps) do
    local entry = states[step.label]
    if entry.state ~= "done" and viewer and #step.takes > 0 then
      local all = true
      for _, ref in ipairs(step.takes) do
        local held = Secrets.Held(ref.id)
        if not held or held < ref.count then all = false end
      end
      entry.ready = all
      if all and (entry.state == "todo" or entry.state == "untracked") then entry.state = "ready" end
    end
  end
  return states
end

-- Served(secret, step, owner): the rewards a step serves (its own "fo"
-- list, else every reward) as Rewards reads them, and their whole: "have",
-- "missing", "unread", or nil when it serves none of the secret's rewards
-- (a rewardless secret, or an "fo" naming none of them: never vacuously
-- collected)
function Secrets.Served(secret, step, owner)
  local things, all = Secrets.Rewards(secret, owner)
  if not (step and #step.serves > 0) then return things, all end
  local wanted, picked, state = {}, {}, "have"
  for _, ref in ipairs(step.serves) do wanted[ref.letter .. ref.id] = true end
  for i, ref in ipairs(secret.rewards) do
    if wanted[ref.letter .. ref.id] then
      local thing = things[i]
      picked[#picked + 1] = thing
      local s = thing and thing.state
      if s == "missing" then state = "missing" elseif s ~= "have" and state == "have" then state = "unread" end
    end
  end
  if #picked == 0 then state = nil end
  return picked, state
end

-- Done(secret, owner): whether the secret's own completion predicate holds:
-- true, false or nil
function Secrets.Done(secret, owner)
  owner = owner or Recollect.Verdicts.Rows.Owner()
  local done = secret.done
  if done == "rewards" then
    local _, all = Secrets.Rewards(secret, owner)
    if all == "have" then return true end
    if all == "missing" then return false end
    return nil
  end
  if done == "steps" then
    -- every final step (one no other step needs: design 2.3), so a step the
    -- game can't report or the other faction's quest before a final never
    -- holds completion back (Task #454: sid 6's five filters)
    local needed = {}
    for _, step in ipairs(secret.steps) do
      for _, ref in ipairs(step.needs) do
        if ref.kind == "step" then needed[ref.label] = true end
      end
    end
    local states = Secrets.Steps(secret, owner)
    for _, step in ipairs(secret.steps) do
      if not step.up and not needed[step.label] then
        local state = states[step.label].state
        if state ~= "done" then
          if state == "unread" or state == "character" or state == "untracked" then return nil end
          return false
        end
      end
    end
    return true
  end
  if done.kind == "achievement" then
    local a = Recollect.Facts.Achievements.Get(done.id)
    if not a then return nil end
    return a.earned == true
  end
  local value = Secrets.FlagDone(done.id, "u", owner)
  return value
end

-- AnyOrder(secret): the labels of the top-level steps that may be done in
-- any order (none needs another top-level step), only for a secret whose
-- curated graph is complete (design 2.4: a missing edge never reads as
-- independence; review finding 4), two or more of them; else nil
function Secrets.AnyOrder(secret)
  if not secret or secret.graph ~= "complete" then return nil end
  local free = {}
  for _, step in ipairs(secret.steps) do
    if not step.up then
      local needsStep = false
      for _, ref in ipairs(step.needs) do
        if ref.kind == "step" and not secret.byLabel[ref.label].up then needsStep = true end
      end
      if not needsStep then free[#free + 1] = step.label end
    end
  end
  return #free >= 2 and free or nil
end

-- StepOf(secret, label): the step
function Secrets.StepOf(secret, label)
  return secret and secret.byLabel[label]
end

-- Reports(step): whether the game itself can say the step is done (its
-- hidden flag, its quest turned in, or what it makes held, as OwnState reads
-- them); any other step is untracked, and the Secret tab counts progress over
-- these alone (Task #411: "0 of 57 steps done" counted steps that can never
-- read done)
function Secrets.Reports(step)
  return type(step) == "table" and (step.flag ~= nil or (step.action == "quest" and step.quest ~= nil) or step.makes ~= nil)
end

-- The steps that take the item or use it as a tool (its consumers), the
-- first one that makes it, the last "any N" step it is an alternative of, and
-- every such step (review finding 6: every membership is evaluated)
function Secrets.Roles(secret, itemID)
  local consumers, producer, alternative, alternatives = {}, nil, nil, {}
  for _, step in ipairs(secret.steps) do
    for _, ref in ipairs(step.takes) do
      if ref.id == itemID then consumers[#consumers + 1] = { step = step, count = ref.count } end
    end
    for _, ref in ipairs(step.tools) do
      if ref.id == itemID then consumers[#consumers + 1] = { step = step, count = ref.count, tool = true, unsure = ref.unsure } end
    end
    for _, ref in ipairs(step.products) do
      if ref.id == itemID and not producer then producer = step end
    end
    if step.any then
      for _, ref in ipairs(step.any.items) do
        if ref.id == itemID and alternative ~= step then
          alternative = step
          alternatives[#alternatives + 1] = step
        end
      end
    end
  end
  return consumers, producer, alternative, alternatives
end

-- Name(secret, owner): the secret's name, read live from what names it (its
-- first reward's name for a reward letter, an item's or spell's name), or nil
-- while the game hasn't sent it
function Secrets.Name(secret, owner)
  local ref = secret and secret.name
  if not ref then return nil end
  if REWARD_LETTERS[ref.letter] then
    secret.nameRelation = secret.nameRelation or { thing = ref.letter, id = ref.id }
    local thing = Resolve(secret.nameRelation, owner or Recollect.Verdicts.Rows.Owner())
    return thing and Recollect.Facts.Buys.Name(thing) or nil
  end
  if ref.kind == "item" then return Recollect.Facts.Item.Name(ref.id) end
  if ref.kind == "spell" then
    local ok, name = Try(seams.SpellName, ref.id)
    return ok and type(name) == "string" and name ~= "" and name or nil
  end
  return nil
end

-- RewardWords(things): "Phoenix Wishwing (a pet you don't have)" for the
-- first reward still missing, else the first one; nil while no name reads
function Secrets.RewardWords(things)
  local pick
  for _, thing in ipairs(things or {}) do
    if thing.state == "missing" then pick = thing break end
  end
  pick = pick or (things and things[1])
  if not pick then return nil end
  local name = Recollect.Facts.Buys.Name(pick)
  local kind = Secrets.KIND_WORDS[pick.what] or "a reward"
  if not name then return kind end
  if pick.state == "missing" then return ("%s (%s you don't have)"):format(name, kind) end
  if pick.state == "have" then return ("%s (%s you have)"):format(name, kind) end
  return ("%s (%s)"):format(name, kind)
end

Secrets._test = { seams = seams, Reset = Reset }
