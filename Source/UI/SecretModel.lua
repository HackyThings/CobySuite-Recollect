-------------------------------------------------------------------------------
-- UI.SecretModel: what the details window's Secret tab shows (Task #411)
--
-- The tab is a field guide for one secret (Cobanyte, 2026-10-14: "We can
-- make the secrets tab prettier. We should have the ability to collapse and
-- show the steps in the secret that have sub-steps. Any items mentioned in
-- secrets, or NPCs or w/e should all have links that i can click on like we
-- have elsewhere"; then "quests, etc. all linkable", and for the 57 steps of
-- the Lucky Horseshoe's secret "that needs to be easier to parse"). Built
-- from UI.UsedFor.SecretSteps (through UI.DetailData.SecretStepsOf), so the
-- tab, the panel's line and WHAT IT'S FOR never disagree; UI.SecretPanel
-- paints it. It follows Task #411's design:
--   * the header's facts: the secret's own name (never a reward's), its
--     rewards, each a link with its state, progress over the steps the
--     game can report (Facts.Secrets.Reports) with how many it can't, its
--     bar fraction, the suggested step and what to check first, and this
--     item's steps (UI.SecretPanel paints a compact header from them, and
--     the rewards on the Summary page)
--   * stages: the data's own (ph), each a fold whose summary counts its
--     steps (no "Done so far" fold since Task #430); a step with sub-steps
--     folds its sub-steps
--   * a row per step with a mark on every one, its action wrapped (a short
--     title, else its first sentence, in white; the rest under it), the
--     item's role, its state and counts, what it takes with how many you
--     have, an "any N" step's checklist, what it needs first (steps as jump
--     links) and its hints, then the places it names with a pin each: its
--     own, and every creature, NPC or object it names that the data places
--   * every name a step's words use is a link (items, NPCs, objects,
--     quests, achievements, currencies, spells, zones, other steps): the
--     names its template heard, its own typed references, the data's
--     mentions (mn) and "step N"
--   * personal marks: a step the game can't report can be marked done for
--     the player's own checklist, kept per owner, secret and step; never
--     counted as the game's progress and never read by a verdict
--   * every secret reads as an explorer and a reader (Task #417; the
--     redesign of Task #430 made it every secret, however short): Tree,
--     Selected, Neighbor, Pager and Sections below
-- The presentation contract of Task #430, beside the lines: each row's
-- short title (`short`, the curated title, else a short form of its
-- words), its typed requirements (`needs`, `any`), whether the player may
-- mark it (`checklist`), its words to search; each place line's role
-- ("action": where the step is done; "mentioned": a place its words only
-- name); the model's raw counts (`counts`), its short progress for the
-- header (`progressShort`), its rewards as rows (`rewardRows`) and whose
-- copy it is (`owner`). Game completion and the player's own marks stay apart.
-- Folds, the scroll, the selection (with the item it was made for) and the
-- explorer's filter are kept per owner and secret in
-- RECOLLECT_WINDOW_STATE.secretFolds, the marks in .secretMarks. A line's
-- section says where the reader puts it.
--
-- A line is { text, color, font ("body" or "data"), links (for Hyper.Text),
-- segs (a line in pieces: { text, color, links, icon }), pin ({ places,
-- title }), role (a place line's), button ("mark" or "unmark"), step (a step jump) }.
-------------------------------------------------------------------------------
local U = CobySuite_Recollect.Utilities

local Model = {}
Recollect.UI.SecretModel = Model

local seams = {
  State = function() return RECOLLECT_WINDOW_STATE end,
  Now = function() return time() end,
  ItemIcon = function(itemID) return C_Item.GetItemIconByID(itemID) end,
}
Model.seams = seams

Model.SMALL = 3           -- a secret of this many steps or fewer: no search or filters, no list of this item's steps
Model.SHORT = 40          -- a step's words longer than this get a short title for the explorer
Model.CREATURES = 4       -- creatures, NPCs and objects a step's places name, at most
Model.MENU_PLACES = 20    -- places one pin's menu lists, at most

local function Secrets() return Recollect.Facts.Secrets end
local function Data() return Recollect.UI.DetailData end
local function UsedFor() return Recollect.UI.UsedFor end
local function Colors() return Recollect.UI.VerdictColors end
local function Verdict() return Recollect.Purposes.Registry.Verdict end

-------------------------------------------------------------------------------
-- Saved state: folds, the scroll and personal marks, per owner and secret
-------------------------------------------------------------------------------
-- OwnerKey(owner): whose folds and marks they are (a character's GUID, else its name)
function Model.OwnerKey(owner)
  owner = owner or Recollect.Verdicts.Rows.Owner()
  return tostring(owner.guid or owner.name or "viewer")
end

-- Saved(field, ownerKey, sid, create): RECOLLECT_WINDOW_STATE[field][ownerKey][sid],
-- made when create, else nil when there is none
local function Saved(field, ownerKey, sid, create)
  local state = seams.State()
  if type(state) ~= "table" or sid == nil then return nil end
  local node = state
  for _, key in ipairs({ field, ownerKey, sid }) do
    local nextNode = node[key]
    if type(nextNode) ~= "table" then
      if not create then return nil end
      nextNode = {}
      node[key] = nextNode
    end
    node = nextNode
  end
  return node
end
Model.Saved = Saved

-- FoldOpen(ownerKey, sid, kind, key, default): a fold's state ("s" a stage,
-- "p" a step's sub-steps, "m" a step's folded words), the player's choice
-- when there is one, else default
function Model.FoldOpen(ownerKey, sid, kind, key, default)
  local folds = Saved("secretFolds", ownerKey, sid)
  -- nil (never false) when nothing is saved for it: a saved scroll or a fold of
  -- another kind keeps every untouched fold at its default (Task #411 review, UI-01)
  local saved = nil
  if folds and type(folds[kind]) == "table" then saved = folds[kind][key] end
  if saved == nil then return default end
  return saved == true
end

function Model.SetFold(ownerKey, sid, kind, key, open)
  local folds = Saved("secretFolds", ownerKey, sid, true)
  if not folds then return end
  if type(folds[kind]) ~= "table" then folds[kind] = {} end
  folds[kind][key] = open and true or false
end

-- Scroll(ownerKey, sid) and SetScroll: where the tab was scrolled to
function Model.Scroll(ownerKey, sid)
  local folds = Saved("secretFolds", ownerKey, sid)
  return folds and type(folds.scroll) == "number" and folds.scroll or 0
end

function Model.SetScroll(ownerKey, sid, offset)
  local folds = Saved("secretFolds", ownerKey, sid, (offset or 0) > 0)
  if folds then folds.scroll = (offset or 0) > 0 and math.floor(offset) or nil end
end

-- Marked(ownerKey, sid, label): whether the player marked the step done on
-- their own checklist; SetMarked marks or unmarks it, ClearMarks every one
function Model.Marked(ownerKey, sid, label)
  local marks = Saved("secretMarks", ownerKey, sid)
  return marks ~= nil and marks[label] ~= nil
end

function Model.SetMarked(ownerKey, sid, label, on)
  local marks = Saved("secretMarks", ownerKey, sid, on)
  if marks then marks[label] = on and seams.Now() or nil end
end

function Model.ClearMarks(ownerKey, sid)
  local marks = Saved("secretMarks", ownerKey, sid)
  if marks then wipe(marks) end
end

-------------------------------------------------------------------------------
-- Words
-------------------------------------------------------------------------------
-- Sentences(text): the text's sentences, split where a period, question or
-- exclamation mark is followed by a space and a capital or a digit (so
-- "74.2, 37.5" stays whole)
function Model.Sentences(text)
  local out, from = {}, 1
  text = tostring(text or "")
  while true do
    local stop = text:find("[%.!?] +[%u%d]", from)
    if not stop then break end
    out[#out + 1] = text:sub(from, stop)
    from = stop + 1
    while text:sub(from, from) == " " do from = from + 1 end
  end
  local rest = text:sub(from)
  if rest ~= "" then out[#out + 1] = rest end
  return out
end

-- "A", "A and B", "A, B and C"
local function Joined(list)
  if #list <= 1 then return list[1] or "" end
  return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- A place in words: "Spires of Arak (52.0, 50.4)"
local function PlaceWords(place)
  return ("%s (%.1f, %.1f)"):format(place.zone or ("map " .. tostring(place.mapID)), place.x * 100, place.y * 100)
end
Model.PlaceWords = PlaceWords

-------------------------------------------------------------------------------
-- Links: { text, color, row } for UI.DetailWindow's Hyper.Text, whose
-- hover and clicks are a table row's (rule 36)
-------------------------------------------------------------------------------
local function Link(text, color, row)
  if type(text) ~= "string" or text == "" or type(row) ~= "table" then return nil end
  return { text = text, color = color or U.Colors.INFO_BLUE, row = row }
end

local function Add(list, link)
  if link then list[#list + 1] = link end
  return list
end

-- A zone's link: hover names it, a click sets the waypoint when the step's
-- place is on that map (a zone alone gets no invented pin)
local function ZoneLink(mapID, name, place)
  name = name or Recollect.Facts.Vendors.ZoneName(mapID)
  return Link(name, U.Colors.INFO_BLUE, { what = "zone", mapID = mapID, name = name,
    place = (place and place.mapID == mapID) and place or false })
end

local function RowLink(kind, id, name, color)
  local row = Data().LinkRow(kind, id)
  if not row then return nil end
  return Link(name, color or Data().LinkColor(row), row)
end

-- A thing Facts.Buys reads (a reward, a mount spell a step names) as a link
local function ThingLink(thing, words)
  if type(thing) ~= "table" then return nil end
  local name = words or Recollect.Facts.Buys.Name(thing)
  if thing.what == "mount" and tostring(thing.key):find("^mountspell:") then return RowLink("spell", thing.id, name) end
  return RowLink(thing.what, thing.id, name)
end

local REWARD_LETTER = { mount = "m", toy = "t", pet = "p", ensemble = "e", decor = "d", recipe = "r" }

-- One typed reference as a link (a step's own reference or a mention), or
-- nil while its name loads or when it has none: words (a text number) name
-- it as the step's words do; an object has no live name, so only its words
-- name it. "step" is a jump to that step of the secret
local function RefLink(ref, ctx)
  local kind, id = ref.kind, ref.id
  local words = ref.words and Secrets().Text(ref.words) or nil
  if kind == "item" then return RowLink("item", id, words or Recollect.Facts.Item.Name(id)) end
  if kind == "npc" then
    local row = Data().LinkRow("npc", id)
    return row and Link(words or Recollect.Facts.Vendors.NpcName(id), Data().LinkColor(row), row)
  end
  if kind == "object" then
    return words and Link(words, U.Colors.INFO_BLUE, { what = "object", objectID = id, name = words }) or nil
  end
  if kind == "zone" then return ZoneLink(id, words, ctx.place) end
  if kind == "quest" then
    local quest = words == nil and Recollect.Facts.QuestInfo.Get(id, ctx.budget) or nil
    return RowLink("quest", id, words or (quest and quest.title))
  end
  if kind == "achievement" then
    local progress = words == nil and Recollect.Facts.Achievements.Progress(id) or nil
    return RowLink("achievement", id, words or (progress and progress.name))
  end
  if kind == "currency" then
    local info = words == nil and UsedFor().parts.Currency(id) or nil
    return RowLink("currency", id, words or (info and info.name))
  end
  if kind == "spell" then return RowLink("spell", id, words or UsedFor().parts.SpellName(id)) end
  if kind == "step" then
    local step = ctx.secret.byLabel[ref.label]
    return step and Link(words or ("step " .. ref.label), U.Colors.LINK_BLUE, { secretStep = ref.label,
      name = "Step " .. ref.label }) or nil
  end
  if REWARD_LETTER[kind] or kind == "recipe" then
    ref.relation = ref.relation or { thing = ref.letter, id = id }
    return ThingLink(Recollect.Facts.Buys.Resolve(ref.relation, ctx.owner), words)
  end
  return nil
end
Model.RefLink = RefLink

-- The names UsedFor heard while wording a step ({ kind, id, text, color }) as links
local function HeardLinks(names, ctx, into)
  for _, name in ipairs(names or {}) do
    if name.kind == "zone" then
      Add(into, ZoneLink(name.id, name.text, ctx.place))
    else
      local row = Data().LinkRow(name.kind, name.id)
      -- the namer's color, else the row's kind's (Task #450)
      if row then Add(into, Link(name.text, name.color or Data().LinkColor(row), row)) end
    end
  end
  return into
end

-- Every name a step's words may use, as links: what its template heard, its
-- own typed references (a curated step's words name them in prose), its
-- zone, the data's mentions, and each "step N" it names
local function StepLinks(entry, ctx)
  local step, links = entry.step, {}
  HeardLinks(entry.links, ctx, links)
  for _, list in ipairs({ step.products, step.takes, step.tools, step.any and step.any.items or {} }) do
    for _, ref in ipairs(list) do Add(links, RefLink(ref, ctx)) end
  end
  if step.npc then Add(links, RefLink({ kind = "npc", id = step.npc }, ctx)) end
  if step.quest then Add(links, RefLink({ kind = "quest", id = step.quest }, ctx)) end
  for _, list in ipairs({ step.needs, step.hints }) do
    for _, ref in ipairs(list) do
      if ref.kind == "quest" or ref.kind == "achievement" or ref.kind == "npc" then Add(links, RefLink(ref, ctx)) end
    end
  end
  if ctx.place then Add(links, ZoneLink(ctx.place.mapID, ctx.place.zone, ctx.place)) end
  for _, ref in ipairs(step.mentions or {}) do Add(links, RefLink(ref, ctx)) end
  -- "step 21" in the words: a jump to that step (only a label the secret has)
  local text = tostring(entry.text or "")
  for word, label in text:gmatch("([Ss]tep (%w+))") do
    if ctx.secret.byLabel[label] then
      Add(links, Link(word, U.Colors.LINK_BLUE, { secretStep = label, name = "Step " .. label }))
    end
  end
  return links
end
Model.StepLinks = StepLinks

-- A step label as a jump link, its mark before it ("3A")
local function StepSeg(label, mark)
  return { icon = mark, text = label, links = { Link(label, U.Colors.LINK_BLUE, { secretStep = label, name = "Step " .. label }) } }
end

-------------------------------------------------------------------------------
-- A row's lines
-------------------------------------------------------------------------------
local function Line(text, color, font, links)
  return { text = text, color = color, font = font or "data", links = links }
end

-- The action: a curated title in white and the step's words under it, else
-- its first sentence in white and the rest under it in gray; a done step's
-- in gray
local function ActionLines(entry, links, lines, dim)
  local Secrets = Secrets()
  local step = entry.step
  local head = dim and U.Colors.LABEL_GRAY or U.Colors.HIGHLIGHT_WHITE
  local title = step.title and Secrets.Text(step.title)
  local text = tostring(entry.text or "")
  local first = #lines + 1
  if title then
    lines[#lines + 1] = Line(title, head, "body", links)
    for _, sentence in ipairs(Model.Sentences(text)) do
      lines[#lines + 1] = Line(sentence, U.Colors.LIGHT_GRAY, "body", links)
    end
  elseif step.say then
    local sentences = Model.Sentences(text)
    lines[#lines + 1] = Line(sentences[1] or text, head, "body", links)
    if #sentences > 1 then
      lines[#lines + 1] = Line(table.concat(sentences, " ", 2), dim and U.Colors.LABEL_GRAY or U.Colors.LIGHT_GRAY, "body", links)
    end
  else
    lines[#lines + 1] = Line(text, head, "body", links)
  end
  -- the reader's sections (Task #417): the first line is the step's title, the rest what to do
  lines[first].section = "title"
  for i = first + 1, #lines do lines[i].section = "action" end
  return lines[first].text
end

-- What the step takes and the tools it asks for, with how many you have
-- (the logged-in character's copy only, while the step isn't done): "Needs
-- 20 [Inert Phoenix Ash] (you have 12; 8 more) and [Glittering Phoenix
-- Ember] (you have 1)"; a count that can't be read is said, never zero
local function NeedsLine(entry, ctx)
  local step = entry.step
  local refs = {}
  for _, ref in ipairs(step.takes) do refs[#refs + 1] = ref end
  for _, ref in ipairs(step.tools) do refs[#refs + 1] = ref end
  if #refs == 0 or entry.state == "done" then return nil end
  local V, colors = Verdict(), Colors()
  local segs = { { text = "Needs " } }
  for i, ref in ipairs(refs) do
    if i > 1 then segs[#segs + 1] = { text = i == #refs and " and " or ", " } end
    if (ref.count or 1) > 1 then segs[#segs + 1] = { text = ref.count .. " " } end
    local link = RowLink("item", ref.id, Recollect.Facts.Item.Name(ref.id))
    segs[#segs + 1] = link and { text = link.text, links = { link } } or { text = "item " .. ref.id }
    if ctx.viewer then
      local held = Secrets().Held(ref.id)
      local need = ref.count or 1
      if held == nil then
        segs[#segs + 1] = { text = " (how many you have can't be read)", color = U.Colors.LABEL_GRAY }
      elseif held >= need then
        segs[#segs + 1] = { text = (" (you have %d)"):format(held), color = colors[V.DONE] }
      else
        segs[#segs + 1] = { text = held == 0 and (" (you have none; %d more)"):format(need)
          or (" (you have %d; %d more)"):format(held, need - held), color = colors[V.USEFUL] }
      end
    end
  end
  return { segs = segs, font = "data", color = U.Colors.LABEL_GRAY }
end

-- An "any N" step's checklist: how many count, that the known choices may
-- not be all, then each choice with whether you hold it (the logged-in
-- character's copy only)
local function ChoiceLines(entry, ctx, lines)
  local any = entry.step.any
  if not any then return end
  local held, readable = 0, ctx.viewer
  local list = {}
  for i, ref in ipairs(any.items) do
    local count = nil
    if ctx.viewer then count = Secrets().Held(ref.id) end
    if count == nil then readable = false end
    if count and count > 0 then held = held + 1 end
    if i > 1 then list[#list + 1] = { text = "   " } end
    local mark = nil
    if ctx.viewer then
      if count == nil then mark = "wait" elseif count > 0 then mark = "done" else mark = "pending" end
    end
    local link = RowLink("item", ref.id, Recollect.Facts.Item.Name(ref.id))
    list[#list + 1] = { icon = mark, text = link and link.text or ("item " .. ref.id), links = link and { link } or nil }
  end
  local head = any.count == 1 and "Any one of these counts; the choices known here may not be all"
    or ("Any %d different ones count; the choices known here may not be all"):format(any.count)
  if readable then head = ("%s (you have %d of them)"):format(head, held) end
  lines[#lines + 1] = Line(head, U.Colors.LABEL_GRAY)
  lines[#lines + 1] = { segs = list, font = "data", color = U.Colors.LIGHT_GRAY }
end

-- The requirements typed (Task #430, the reader's table): one row per item
-- the step takes or uses, { itemID, name, link, need, owned, missing, tool,
-- unsure }. owned is the bags, bank and warband bank of the logged-in
-- character's copy while the step isn't done, nil otherwise (unknown: no
-- missing count is made up)
local function Needs(entry, ctx)
  local step, list = entry.step, {}
  local function Add(ref, tool)
    local link = RowLink("item", ref.id, Recollect.Facts.Item.Name(ref.id))
    local need = ref.count or 1
    local owned = nil
    if ctx.viewer and entry.state ~= "done" then owned = Secrets().Held(ref.id) end
    list[#list + 1] = { itemID = ref.id, name = link and link.text or ("item " .. ref.id), link = link, need = need,
      owned = owned, missing = owned and math.max(0, need - owned) or nil, tool = tool or nil, unsure = ref.unsure or nil }
  end
  for _, ref in ipairs(step.takes) do Add(ref) end
  for _, ref in ipairs(step.tools) do Add(ref, true) end
  return list
end

-- An "any N" step's choices typed: { count, held, readable, items = { {
-- itemID, name, link, owned } } }; owned as Needs reads it
local function Choices(entry, ctx)
  local any = entry.step.any
  if not any then return nil end
  local out = { count = any.count, held = 0, readable = ctx.viewer, items = {} }
  for _, ref in ipairs(any.items) do
    local owned = nil
    if ctx.viewer then owned = Secrets().Held(ref.id) end
    if owned == nil then out.readable = false end
    if owned and owned > 0 then out.held = out.held + 1 end
    local link = RowLink("item", ref.id, Recollect.Facts.Item.Name(ref.id))
    out.items[#out.items + 1] = { itemID = ref.id, name = link and link.text or ("item " .. ref.id), link = link, owned = owned }
  end
  return out
end

-- What the step needs first: its steps as jump links with their marks
-- ("After steps 2, 3A and 3B", "After any one of steps 2 and 3" for needsAny),
-- then each other need and hint UsedFor worded (a hidden flag a step sets
-- read as that step)
local function NeedLines(entry, ctx, lines)
  local step = entry.step
  local labels = {}
  for _, ref in ipairs(step.needs) do
    if ref.kind == "step" then labels[#labels + 1] = ref.label end
  end
  if #labels > 0 then
    local segs = { { text = step.needsAny and (#labels > 1 and "After any one of steps " or "After step ")
      or (#labels > 1 and "After steps " or "After step ") } }
    for i, label in ipairs(labels) do
      if i > 1 then segs[#segs + 1] = { text = i == #labels and (step.needsAny and " or " or " and ") or ", " } end
      segs[#segs + 1] = StepSeg(label, ctx.marks[label])
    end
    lines[#lines + 1] = { segs = segs, font = "data", color = U.Colors.LABEL_GRAY }
  end
  for _, extra in ipairs(entry.extras or {}) do
    if extra.step then
      local lead = extra.hint and "Hint: if it doesn't work yet, do step " or "After step "
      lines[#lines + 1] = { segs = { { text = lead }, StepSeg(extra.step, ctx.marks[extra.step]),
        { text = extra.hint and " first" or "" } }, font = "data", color = U.Colors.LABEL_GRAY }
    else
      lines[#lines + 1] = Line(extra.text, extra.hint and U.Colors.LABEL_GRAY or extra.color, "data",
        HeardLinks(extra.links, ctx, {}))
    end
  end
end

-------------------------------------------------------------------------------
-- Places (Task #411 addendum, Cobanyte: "we mention scorching elementals and
-- living blazes - we should have map-pins we can use for that to know where
-- to go"): the step's own place, and every creature, NPC or object it names
-- that the data places (Facts.Vendors.Places), each with a pin; one with
-- several places gets a pin whose menu lists them. One the data doesn't
-- place gets none (Model.unplaced lists them, for the data's next round)
-------------------------------------------------------------------------------
-- An NPC's places as waypoint places, at most MENU_PLACES
local function NpcPlaces(npcID)
  local Vendors = Recollect.Facts.Vendors
  local list = {}
  for i, p in ipairs(Vendors.Places(npcID)) do
    if i > Model.MENU_PLACES then break end
    list[#list + 1] = { mapID = p.mapID, x = p.x, y = p.y, npcID = npcID, what = "the NPC",
      zone = Vendors.ZoneName(p.mapID) or ("map " .. p.mapID) }
  end
  return list
end
Model.NpcPlaces = NpcPlaces

-- "6 places in Spires of Arak", "6 places in 3 zones", or the one place in words
local function PlacesWords(places)
  if #places == 1 then return PlaceWords(places[1]) end
  local zones, n = {}, 0
  for _, p in ipairs(places) do
    if not zones[p.zone] then zones[p.zone], n = true, n + 1 end
  end
  if n == 1 then return ("%d places in %s"):format(#places, places[1].zone) end
  return ("%d places in %d zones"):format(#places, n)
end
Model.PlacesWords = PlacesWords

-- The NPCs and creatures a step names: its own NPC and the creatures that
-- drop what it loots (where the step is done: role "action"), then the NPCs
-- its hints and mentions name ("mentioned": Task #430, a supplier the words
-- name is never the step's destination); a list of ids and their roles
local function StepNpcs(step)
  local ids, roles, seen = {}, {}, {}
  local function Take(id, role)
    if Recollect.Utilities.IsPositiveID(id) and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
      roles[id] = role
    end
  end
  Take(step.npc, "action")
  if step.makes and (step.action == "loot" or step.action == "kill") then
    for _, relation in ipairs(Recollect.Facts.Relations.Of(step.makes.id, "dropsFrom") or {}) do
      if not (relation.flags and relation.flags.unavailable) then Take(relation.id, "action") end
    end
  end
  for _, list in ipairs({ step.hints, step.mentions or {} }) do
    for _, ref in ipairs(list) do
      if ref.kind == "npc" then Take(ref.id, "mentioned") end
    end
  end
  return ids, roles
end

local function PlaceLines(entry, ctx, lines)
  local step = entry.step
  local own = entry.place
  local shown = 0
  if own and step.at then
    local link = ZoneLink(own.mapID, own.zone, own)
    lines[#lines + 1] = { segs = { { text = link and link.text or own.zone or ("map " .. own.mapID), links = link and { link } or nil },
      { text = (" (%.1f, %.1f)"):format(own.x * 100, own.y * 100) } }, font = "data", color = U.Colors.LABEL_GRAY,
      pin = { places = { own }, title = PlaceWords(own) }, role = "action" }
  end
  local npcs, roles = StepNpcs(step)
  for _, npcID in ipairs(npcs) do
    if shown >= Model.CREATURES then break end
    local places = NpcPlaces(npcID)
    local name = Recollect.Facts.Vendors.NpcName(npcID)
    -- an NPC standing at the step's own place is that place's line already
    local same = own and step.at and #places == 1 and places[1].mapID == own.mapID
      and math.abs(places[1].x - own.x) < 0.02 and math.abs(places[1].y - own.y) < 0.02
    if #places == 0 then
      -- the step's own NPC where the step has a place of its own is placed by it
      if not (npcID == step.npc and step.at) then
        ctx.unplaced[#ctx.unplaced + 1] = { npcID = npcID, name = name, step = step.label }
      end
    elseif name and not same then
      shown = shown + 1
      local link = RefLink({ kind = "npc", id = npcID }, ctx)
      lines[#lines + 1] = { segs = { { text = name, links = link and { link } or nil }, { text = ": " .. PlacesWords(places) } },
        font = "data", color = U.Colors.LABEL_GRAY, pin = { places = places, title = ("%s: %s"):format(name, PlacesWords(places)) },
        role = roles[npcID] }
    end
  end
  -- an object the step is done at, when the step has no place of its own
  if step.object and not step.at then
    local object = Recollect.Facts.Vendors.Object(step.object)
    if object and object.mapID then
      local place = { mapID = object.mapID, x = object.x, y = object.y, what = "the spot",
        zone = Recollect.Facts.Vendors.ZoneName(object.mapID) or ("map " .. object.mapID) }
      lines[#lines + 1] = { segs = { { text = "The spot: " .. PlaceWords(place) } }, font = "data",
        color = U.Colors.LABEL_GRAY, pin = { places = { place }, title = PlaceWords(place) }, role = "action" }
    end
  end
  -- every other object its words mention that the data places, named by those
  -- words (an object has no live name): a pin each (Task #411 review, UI-05)
  local seen = { [step.object or 0] = true }
  for _, ref in ipairs(step.mentions or {}) do
    if ref.kind == "object" and not seen[ref.id] and shown < Model.CREATURES then
      seen[ref.id] = true
      local object = Recollect.Facts.Vendors.Object(ref.id)
      local words = ref.words and Secrets().Text(ref.words) or nil
      if object and object.mapID then
        local place = { mapID = object.mapID, x = object.x, y = object.y, what = "the spot",
          zone = Recollect.Facts.Vendors.ZoneName(object.mapID) or ("map " .. object.mapID) }
        local same = own and math.abs(place.x - own.x) < 0.02 and math.abs(place.y - own.y) < 0.02 and place.mapID == own.mapID
        if not same then
          shown = shown + 1
          local link = RefLink(ref, ctx)
          lines[#lines + 1] = { segs = { { text = link and link.text or words or "A spot", links = link and { link } or nil },
            { text = ": " .. PlaceWords(place) } }, font = "data", color = U.Colors.LABEL_GRAY,
            pin = { places = { place }, title = ("%s: %s"):format(words or "A spot", PlaceWords(place)) }, role = "mentioned" }
        end
      else
        ctx.unplaced[#ctx.unplaced + 1] = { objectID = ref.id, name = words, step = step.label }
      end
    end
  end
end

-------------------------------------------------------------------------------
-- A row
-------------------------------------------------------------------------------
local function StateLine(entry, ctx, row)
  local text = tostring(entry.stateText or "")
  if entry.held and entry.need and entry.state ~= "done" then
    text = ("%s, you have %d of %d"):format(text, entry.held, entry.need)
  end
  -- a step the player marked stays what the game says it is (Task #430: the
  -- checkbox under it says the player's own mark)
  if row.marked then
    return { text = text, color = entry.color or U.Colors.LABEL_GRAY, font = "data", marked = true,
      button = ctx.viewer and "unmark" or nil }
  end
  return { text = text, color = entry.color or U.Colors.LABEL_GRAY, font = "data",
    button = (row.untracked and ctx.viewer and not ctx.notFor) and "mark" or nil }
end

-- The item's role in the step, in blue (the checklist under an "any N" step says how many count)
local function RoleLine(entry)
  if not entry.roleKind then return nil end
  return Line(UsedFor().SECRET_ROLE_KIND_WORDS[entry.roleKind] or entry.roleText, U.Colors.INFO_BLUE)
end

-- Tag(lines, from, section): the reader's section of every line from index from on
local function Tag(lines, from, section)
  for i = from, #lines do lines[i].section = lines[i].section or section end
end

-- ShortTitle(step, first): what the explorer and the reader's title call a
-- step (Task #430): its curated title; else, for a step worded by its
-- template, its words up to where they start saying where or with what
-- ("Buy Phoenix Ash Talisman" of "Buy Phoenix Ash Talisman from Zektar in
-- Spires of Arak for ..."); else its first sentence
local CUTS = { " from ", " for ", " in ", " at ", " to get " }
local function ShortTitle(step, first)
  first = tostring(first or "")
  if step.title or step.say or #first <= Model.SHORT then return first end
  local at
  for _, cut in ipairs(CUTS) do
    local found = first:find(cut, 8, true)
    if found and (not at or found < at) then at = found end
  end
  return at and first:sub(1, at - 1) or first
end
Model.ShortTitle = ShortTitle

-- The words a search reads for a row: its code, its title and words, its
-- folded words and every name its words link, in lower case
local function SearchWords(row, links, more)
  local words = { row.label, row.title, row.short, row.text, more }
  for _, link in ipairs(links or {}) do words[#words + 1] = link.text end
  for i, w in ipairs(words) do words[i] = tostring(w or "") end
  return table.concat(words, "\31"):lower()
end

local function BuildRow(entry, ctx, suggested)
  local step = entry.step
  local marked = not entry.reports and entry.state ~= "done" and Model.Marked(ctx.ownerKey, ctx.sid, entry.label)
  local row = { label = entry.label, depth = entry.depth, parent = step.up, mark = entry.mark, state = entry.state,
    own = entry.own, role = entry.role, suggested = suggested, reports = entry.reports,
    untracked = not entry.reports and entry.state ~= "done", marked = marked or nil, place = entry.place,
    text = entry.text, lines = {} }
  if marked then row.mark = "marked" end
  if ctx.notFor then row.mark = "untracked" end
  row.done = entry.state == "done" or marked == true
  row.more = step.more ~= nil and Secrets().Text(step.more) ~= nil
  ctx.place = entry.place
  local links = StepLinks(entry, ctx)
  local lines = row.lines
  row.title = ActionLines(entry, links, lines, row.done or ctx.notFor)
  row.short = ShortTitle(step, row.title)
  row.needs = Needs(entry, ctx)
  row.any = Choices(entry, ctx)
  -- the player's own checklist: a step the game can't track, on the logged-in character's copy of a secret for it
  row.checklist = (row.untracked and ctx.viewer and not ctx.notFor) and true or nil
  local more = step.more and Secrets().Text(step.more) or nil
  row.search = SearchWords(row, links, more)
  if step.more then lines[#lines + 1] = { more = more, font = "body", links = links, section = "more" } end
  local at = #lines + 1
  if suggested then
    lines[#lines + 1] = Line(suggested, U.Colors.STATUS_GOLD)
    lines[#lines].suggest = true
  end
  local role = RoleLine(entry)
  if role then
    role.relevance = true
    lines[#lines + 1] = role
  end
  if not ctx.notFor then lines[#lines + 1] = StateLine(entry, ctx, row) end
  Tag(lines, at, "state")
  at = #lines + 1
  local needs = NeedsLine(entry, ctx)
  if needs then lines[#lines + 1] = needs end
  ChoiceLines(entry, ctx, lines)
  Tag(lines, at, "need")
  at = #lines + 1
  NeedLines(entry, ctx, lines)
  Tag(lines, at, "before")
  at = #lines + 1
  PlaceLines(entry, ctx, lines)
  Tag(lines, at, "where")
  ctx.place = nil
  return row
end

-------------------------------------------------------------------------------
-- The header
-------------------------------------------------------------------------------
local KIND_WORDS = { mount = "mount", toy = "toy", pet = "pet", ensemble = "ensemble", decor = "decor item",
  recipe = "recipe", achievement = "achievement", heirloom = "heirloom", illusion = "weapon illusion" }

-- The rewards line: each reward a link, its kind and its state ("not
-- collected", "collected"; an achievement "earned"), its mark before it
local function RewardsLine(things)
  local V, colors = Verdict(), Colors()
  local segs = { { text = #things > 1 and "Rewards: " or "Reward: " } }
  for i, thing in ipairs(things) do
    if i > 1 then segs[#segs + 1] = { text = "; " } end
    local link = ThingLink(thing)
    local kind = KIND_WORDS[thing.what] or "reward"
    local have = thing.what == "achievement" and "earned" or "collected"
    local mark, state, color = "wait", "can't be read yet", U.Colors.LABEL_GRAY
    if thing.state == "have" then
      mark, state, color = "done", have, colors[V.DONE]
    elseif thing.state == "missing" then
      mark, state, color = "pending", "not " .. have, colors[V.NEEDED]
    end
    segs[#segs + 1] = { icon = mark, text = link and link.text or ("a " .. kind), links = link and { link } or nil }
    segs[#segs + 1] = { text = (" (%s, "):format(kind) }
    segs[#segs + 1] = { text = state, color = color }
    segs[#segs + 1] = { text = ")" }
  end
  return { segs = segs, font = "body", color = U.Colors.LIGHT_GRAY }
end

-- Progress, honestly: "12 of 41 tracked steps done; 16 the game can't
-- track", how many can't be read yet, and how many the player marked; the
-- bar is done over tracked
local function Progress(model, summary, secret)
  local V, colors = Verdict(), Colors()
  if summary.complete == true then
    model.progress, model.progressColor = "Secret complete", colors[V.DONE]
    return
  end
  -- every step the game reports can't be read: never "0 of N"
  if summary.tracked > 0 and summary.unread >= summary.tracked then
    model.progress, model.progressColor = "Progress unavailable", U.Colors.LABEL_GRAY
    return
  end
  local words = UsedFor().SecretProgressWords(summary.trackedDone, summary.tracked, summary.total)
  if summary.unread > 0 then words = ("%s; %d can't be read yet"):format(words, summary.unread) end
  if (model.markedCount or 0) > 0 then
    words = ("%s; you marked %d yourself"):format(words, model.markedCount)
  end
  model.progress, model.progressColor = words, U.Colors.LIGHT_GRAY
  if summary.tracked > 0 then model.bar = summary.trackedDone / summary.tracked end
end

-- The header's short progress (Task #430): "0/41 tracked done; 16
-- untracked", how many can't be read, "Secret complete" only from the
-- secret's own completion, "Progress unavailable" when nothing it tracks
-- reads; and the raw counts the Summary page states
local function ShortProgress(model, summary)
  local c = { done = summary.trackedDone, tracked = summary.tracked, untracked = summary.total - summary.tracked,
    unread = summary.unread, marked = model.markedCount or 0, total = summary.total }
  model.counts = c
  if summary.complete == true then
    model.progressShort = "Secret complete"
    return
  end
  if c.tracked > 0 and c.unread >= c.tracked then
    model.progressShort = "Progress unavailable"
    return
  end
  local parts = {}
  if c.tracked >= c.total then
    parts[1] = ("%d/%d done"):format(c.done, c.total)
  elseif c.tracked > 0 then
    parts[1] = ("%d/%d tracked done"):format(c.done, c.tracked)
  end
  if c.untracked > 0 then parts[#parts + 1] = ("%d untracked"):format(c.untracked) end
  if c.unread > 0 then parts[#parts + 1] = ("%d can't be read"):format(c.unread) end
  model.progressShort = table.concat(parts, "; ")
end

-- The rewards as the Summary page's rows: { thing, link, kind, state words, color, mark }
local function RewardRows(things)
  local V, colors = Verdict(), Colors()
  local out = {}
  for _, thing in ipairs(things or {}) do
    local link = ThingLink(thing)
    local kind = KIND_WORDS[thing.what] or "reward"
    local have = thing.what == "achievement" and "earned" or "collected"
    local row = { thing = thing, link = link, name = link and link.text or ("a " .. kind), kind = kind,
      state = "can't be read yet", color = U.Colors.LABEL_GRAY, mark = "wait" }
    if thing.state == "have" then
      row.state, row.color, row.mark = have, colors[V.DONE], "done"
    elseif thing.state == "missing" then
      row.state, row.color, row.mark = "not " .. have, colors[V.NEEDED], "pending"
    end
    out[#out + 1] = row
  end
  return out
end

-- This item's steps: model.mine, one line per role (the first unfinished
-- step that uses it, the first that gives it; else the first of each), for
-- the jump to the item's own step; model.itemSteps, every step it is in, for
-- the "This item (N)" filter
local function MineLines(model, rows, itemID)
  local picks, list = {}, {}
  for _, row in ipairs(rows) do
    if row.role then
      list[#list + 1] = row
      local key = row.role .. (row.done and ":done" or "")
      picks[key] = picks[key] or row
    end
  end
  model.itemSteps = list
  local lines = {}
  for _, role in ipairs({ "uses", "gives" }) do
    local row = picks[role] or picks[role .. ":done"]
    if row then
      local link = RowLink("item", itemID, Recollect.Facts.Item.Name(itemID))
      local entry = row.entry
      local words = (entry.roleWords or ("step " .. row.label)) .. " (" .. tostring(entry.stateText or ""):gsub("^%u", string.lower) .. ")"
      lines[#lines + 1] = { segs = { { text = link and link.text or "This item", links = link and { link } or nil },
        { text = ": " .. words } }, font = "data", color = U.Colors.INFO_BLUE, step = row.label }
    end
  end
  model.mine = lines
end

-- The suggestion: its label ("Suggested next", or "Next step" when the
-- secret's curated steps are complete; UsedFor.SecretSuggest) and step, and
-- what to check first, every need of that step that isn't read as met
local function Suggestion(model, summary, ctx)
  local pick = summary.suggestion
  if summary.complete == true or not pick then return end
  local entry = pick.entry
  local check = {}
  for _, extra in ipairs(entry.extras or {}) do
    if extra.need and extra.met ~= true then check[#check + 1] = extra.text end
  end
  ctx.place = entry.place
  model.suggestion = { label = pick.label, step = entry.label, text = entry.text, links = StepLinks(entry, ctx),
    check = #check > 0 and ("Check first: " .. Joined(check)) or nil }
  ctx.place = nil
end

-------------------------------------------------------------------------------
-- Stages
-------------------------------------------------------------------------------
-- A stage's counts in words (Task #430: honest, never "Done" because the
-- steps it tracks are; the explorer's short line "0/2 tracked done; 5
-- untracked"), the summary the stage's page adds to ("next: step 7B; this
-- item: step 12I"), its counts and its first step not finished. Every
-- stage starts closed: the panel opens the selected step's path itself
local function StageSummary(stage, rows)
  local done, tracked, untracked, marked, nextLabel, mine, first = 0, 0, 0, 0, nil, nil, nil
  for i = stage.first, stage.last do
    local row = rows[i]
    if row.reports then
      tracked = tracked + 1
      if row.state == "done" then done = done + 1 end
    else
      untracked = untracked + 1
      if row.marked then marked = marked + 1 end
    end
    if not nextLabel and (row.state == "todo" or row.state == "progress" or row.state == "ready") then nextLabel = row.label end
    if not first and not row.done then first = row.label end
    if row.own and not mine then mine = row.label end
  end
  local parts = {}
  if tracked > 0 then parts[#parts + 1] = ("%d/%d tracked done"):format(done, tracked) end
  if untracked > 0 then parts[#parts + 1] = ("%d untracked"):format(untracked) end
  stage.short = table.concat(parts, "; ")
  local long = { stage.short }
  if nextLabel then long[#long + 1] = "next: step " .. nextLabel end
  if mine then long[#long + 1] = "this item: step " .. mine end
  stage.summary = table.concat(long, "; ")
  stage.counts = { done = done, tracked = tracked, untracked = untracked, marked = marked }
  stage.allDone = tracked > 0 and done == tracked and untracked == 0
  stage.firstOpen = first
  stage.mine = mine
  stage.default = false
end

-- The stages: the data's own (ph) only (Task #430: no "Done so far" fold;
-- the To do filter leaves finished steps out)
local function Stages(model, secret, rows)
  local stages = {}
  if secret.stages and #secret.stages > 0 then
    for i, s in ipairs(secret.stages) do
      local nextStage = secret.stages[i + 1]
      stages[#stages + 1] = { key = s.label, title = Secrets().Text(s.text) or ("Stage %d"):format(i), first = s.index,
        last = nextStage and nextStage.index - 1 or #rows }
    end
  end
  for _, stage in ipairs(stages) do StageSummary(stage, rows) end
  return stages
end

-------------------------------------------------------------------------------
-- The model
-------------------------------------------------------------------------------
-- Build(itemID, owner, pick, list, read): the model for pick, one of list
-- (UI.SecretPanel.Secrets); read is DetailData.SecretStepsOf's answer for
-- pick's secret (nil: its steps can't be read). Model.unplaced lists the
-- creatures and NPCs its steps name that the data doesn't place
function Model.Build(itemID, owner, pick, list, read)
  owner = owner or Recollect.Verdicts.Rows.Owner()
  local model = { secrets = list, sid = pick.sid, role = pick.role, ownerKey = Model.OwnerKey(owner), notes = {}, rows = {},
    stages = {}, mine = {}, itemSteps = {}, unplaced = {}, rewardRows = {}, itemID = itemID,
    itemKey = tostring(itemID or ""), owner = { name = owner.name, isViewer = owner.isViewer ~= false } }
  model.name = pick.name or "A secret"
  if not read then
    model.failed = true
    model.progress, model.progressColor = "Its steps can't be read right now", U.Colors.LABEL_GRAY
    model.progressShort = "Progress unavailable"
    return model
  end
  local summary, secret = read.summary, read.secret
  model.name = summary.name or pick.name or "A secret"
  model.complete = summary.complete == true
  model.rewardItem = secret.teaches and secret.teaches[1] and secret.teaches[1].id or nil
  model.rewards = #summary.things > 0 and RewardsLine(summary.things) or nil
  model.rewardRows = RewardRows(summary.things)
  model.anyOrder = summary.anyOrder
  if secret.freq == "repeat" then model.again = "Can be done again for another reward" end
  local viewer = owner.isViewer ~= false
  local applies = Secrets().Applies(secret, owner)
  local ctx = { secret = secret, owner = owner, viewer = viewer, ownerKey = model.ownerKey, sid = pick.sid,
    budget = Recollect.Facts.QuestInfo.FrameBudget(), rowsByLabel = {}, unplaced = model.unplaced }
  if applies ~= true then
    local words = Recollect.Purposes.Registry.KindWords((Recollect.Purposes.Registry.Restrictions({ secret }, owner)))
    ctx.notFor = applies == nil and "Whether this secret is for this character isn't recorded yet"
      or ("This secret is for another %s"):format(words or "character")
    model.notes[#model.notes + 1] = ctx.notFor
    model.notFor = ctx.notFor
  end
  if not viewer then
    model.notes[#model.notes + 1] = ("%s's copy: only what the whole account shares is read here; counts and quests are %s's"):format(
      owner.name or "Another character", owner.name or "that character")
  end
  if pick.role == "teaches" then model.notes[#model.notes + 1] = "This item is the secret's reward" end
  local free = summary.anyOrder
  if type(free) == "table" and #free >= 2 then
    model.notes[#model.notes + 1] = ("Steps %s can be done in any order"):format(Joined(free))
  end
  local suggested = summary.suggestion and summary.complete ~= true and summary.suggestion.entry
  -- each step's mark as its row shows it (a jump link carries it): the
  -- player's own mark on a step the game doesn't report
  ctx.marks = {}
  for _, entry in ipairs(read.steps) do
    ctx.rowsByLabel[entry.label] = entry
    local mark = entry.mark
    if not entry.reports and entry.state ~= "done" and Model.Marked(model.ownerKey, pick.sid, entry.label) then mark = "marked" end
    ctx.marks[entry.label] = ctx.notFor and "untracked" or mark
  end
  local marked = 0
  for _, entry in ipairs(read.steps) do
    local row = BuildRow(entry, ctx, entry == suggested and summary.suggestion.label or nil)
    row.entry = entry
    if row.marked then marked = marked + 1 end
    model.rows[#model.rows + 1] = row
  end
  -- children: each parent's sub-steps, in order
  local byLabel = {}
  for i, row in ipairs(model.rows) do
    row.index = i
    byLabel[row.label] = row
  end
  for _, row in ipairs(model.rows) do
    local parent = row.parent and byLabel[row.parent]
    if parent then
      parent.children = parent.children or {}
      parent.children[#parent.children + 1] = row.label
    end
  end
  -- a folded parent still says how far its sub-steps are
  for _, row in ipairs(model.rows) do
    if row.children then
      local done = 0
      for _, label in ipairs(row.children) do
        if byLabel[label].done then done = done + 1 end
      end
      row.childSummary = ("%d %s, %d done"):format(#row.children, #row.children == 1 and "sub-step" or "sub-steps", done)
    end
  end
  model.byLabel = byLabel
  model.markedCount = marked
  Progress(model, summary, secret)
  ShortProgress(model, summary)
  Suggestion(model, summary, ctx)
  if #model.rows > Model.SMALL and itemID then MineLines(model, model.rows, itemID) end
  model.stages = Stages(model, secret, model.rows)
  model.small = #model.rows <= Model.SMALL
  return model
end

-- The default open state of a parent's sub-steps: closed (Task #430: the
-- panel opens the selected step's path, every other branch starts folded)
function Model.ParentDefault()
  return false
end

-- StageOf(model, index): the stage holding a row, or nil
function Model.StageOf(model, index)
  for _, stage in ipairs(model.stages or {}) do
    if index >= stage.first and index <= stage.last then return stage end
  end
  return nil
end

-- Visible(model): the rows and stage headers to paint, in order, with each
-- fold's state read: { { stage = s, open } | { row = r, childrenOpen } }
function Model.Visible(model)
  local out = {}
  local stageOpen, parentOpen = true, {}
  local stageAt = {}
  for _, stage in ipairs(model.stages or {}) do stageAt[stage.first] = stage end
  local current
  for i, row in ipairs(model.rows) do
    local stage = stageAt[i]
    if stage then
      current = stage
      stageOpen = Model.FoldOpen(model.ownerKey, model.sid, "s", stage.key, stage.default)
      out[#out + 1] = { stage = stage, open = stageOpen }
    elseif current and i > current.last then
      current, stageOpen = nil, true
    end
    if stageOpen then
      local childrenOpen = row.children and Model.FoldOpen(model.ownerKey, model.sid, "p", row.label, Model.ParentDefault(row))
      if row.children then parentOpen[row.label] = childrenOpen end
      if not row.parent or parentOpen[row.parent] ~= false then
        out[#out + 1] = { row = row, childrenOpen = childrenOpen }
      end
    end
  end
  return out
end

-- Reveal(model, label): open the stage and the parent holding a step, so it shows
function Model.Reveal(model, label)
  local row = model.byLabel and model.byLabel[label]
  if not row then return nil end
  local stage = Model.StageOf(model, row.index)
  if stage then Model.SetFold(model.ownerKey, model.sid, "s", stage.key, true) end
  if row.parent then Model.SetFold(model.ownerKey, model.sid, "p", row.parent, true) end
  return row
end

-- SetAll(model, open): every stage and every parent's sub-steps open, or
-- closed: the explorer only (Task #430: a step's folded notes stay as the
-- player left them)
function Model.SetAll(model, open)
  for _, stage in ipairs(model.stages or {}) do Model.SetFold(model.ownerKey, model.sid, "s", stage.key, open) end
  for _, row in ipairs(model.rows) do
    if row.children then Model.SetFold(model.ownerKey, model.sid, "p", row.label, open) end
  end
end

-- A painted line's words, pieces, icons and how many links it holds, added to words
-- A list of links as its colors, so a link whose color arrives later (an
-- item's quality once it loads) paints again (Task #450)
local function LinkColors(links)
  local out = { #links }
  for _, link in ipairs(links) do
    local c = link.color
    out[#out + 1] = type(c) == "table" and ("%.2f,%.2f,%.2f"):format(c[1] or 0, c[2] or 0, c[3] or 0) or "-"
  end
  return table.concat(out, ";")
end

local function LineWords(line, words)
  if type(line) ~= "table" then return words end
  if line.text then words[#words + 1] = line.text end
  if line.more then words[#words + 1] = line.more end
  for _, seg in ipairs(line.segs or {}) do
    words[#words + 1] = tostring(seg.text) .. tostring(seg.icon) .. (seg.links and LinkColors(seg.links) or "")
  end
  if line.links then words[#words + 1] = LinkColors(line.links) end
  if line.pin then words[#words + 1] = #line.pin.places end
  if line.button then words[#words + 1] = line.button end
  return words
end

-- Signature(model): what the painted tab depends on, everything the panel
-- paints from the model (the header, the rewards, the notes, the item's lines,
-- the dropdown's entries and every row), so a refresh that read nothing new
-- paints nothing (one paint per data change) and any change paints
function Model.Signature(model)
  local parts = { tostring(model.sid), tostring(model.name), tostring(model.progress), tostring(model.markedCount),
    tostring(model.bar), tostring(model.again), tostring(model.complete), tostring(model.failed),
    tostring(model.progressShort), tostring(model.itemKey) }
  for _, reward in ipairs(model.rewardRows or {}) do parts[#parts + 1] = tostring(reward.name) .. tostring(reward.state) end
  local s = model.suggestion
  parts[#parts + 1] = s and (s.step .. tostring(s.check) .. tostring(s.text) .. #(s.links or {})) or "-"
  parts[#parts + 1] = table.concat(LineWords(model.rewards, {}), "|")
  parts[#parts + 1] = table.concat(model.notes or {}, "|")
  local mine = {}
  for _, line in ipairs(model.mine or {}) do LineWords(line, mine) end
  parts[#parts + 1] = table.concat(mine, "|") .. "#" .. #(model.itemSteps or {})
  for _, entry in ipairs(model.secrets or {}) do
    parts[#parts + 1] = ("%s:%s:%s:%s"):format(tostring(entry.sid), tostring(entry.name), tostring(entry.role),
      tostring(entry.rewardState))
  end
  for _, row in ipairs(model.rows) do
    local words = {}
    for _, line in ipairs(row.lines) do LineWords(line, words) end
    parts[#parts + 1] = ("%s|%s|%s|%s|%s"):format(row.label, tostring(row.mark), tostring(row.childSummary), tostring(row.short),
      table.concat(words, "|"))
  end
  return table.concat(parts, "\30")
end

-- Icon(model): the reward item's icon (no caller since the stage headers dropped their icon, Task #430)
function Model.Icon(model)
  local itemID = model.rewardItem
  if not itemID then return nil end
  local ok, icon = pcall(seams.ItemIcon, itemID)
  return ok and icon or nil
end

-------------------------------------------------------------------------------
-- The explorer and the reader (Task #417; Cobanyte, 2026-10-14: "a simple
-- step explorer on the left side and text container on the right side.. so
-- the steps are easy to explore and sift through, and it's not just one
-- massive word puke"; Task #430: every secret, however short). The secret
-- shows as a list of Summary & rewards, its stages and its steps on the
-- left, one page on the right: a step, a stage, or the Summary. The
-- selection, the item it was made for and the explorer's filter are kept
-- per owner and secret with the folds. A selection is a step's label,
-- "stage:<key>" or "summary"
-------------------------------------------------------------------------------
Model.FILTERS = { "all", "todo", "mine" }
Model.FILTER_WORDS = { all = "All", todo = "To do", mine = "This item" }
Model.SUMMARY = "summary"

-- Split(model): whether the tab shows the explorer and the reader (every
-- secret whose steps read)
function Model.Split(model)
  return model ~= nil and not model.failed and #(model.rows or {}) > 0
end

-- DefaultSelection(model): the Summary of a secret complete; else this
-- item's first unfinished step that uses it (an ingredient, a tool or a
-- choice), then its first unfinished step that gives it, then any step of
-- this item's, then the suggested step, then the first step
function Model.DefaultSelection(model)
  if model.complete then return Model.SUMMARY end
  local rows = model.rows or {}
  for _, role in ipairs({ "uses", "gives" }) do
    for _, row in ipairs(rows) do
      if row.role == role and not row.done then return row.label end
    end
  end
  for _, row in ipairs(rows) do
    if row.own then return row.label end
  end
  if model.suggestion and model.byLabel and model.byLabel[model.suggestion.step] then return model.suggestion.step end
  return rows[1] and rows[1].label or Model.SUMMARY
end

-- StageByKey(model, key): a stage of the model by its key, or nil
function Model.StageByKey(model, key)
  for _, stage in ipairs(model.stages or {}) do
    if stage.key == key then return stage end
  end
  return nil
end

-- Valid(model, selection): whether a selection names a step or stage the model has, or its Summary
local function Valid(model, selection)
  if type(selection) ~= "string" then return false end
  if selection == Model.SUMMARY then return Model.Split(model) end
  local key = selection:match("^stage:(.+)$")
  if key then return Model.StageByKey(model, key) ~= nil end
  return model.byLabel ~= nil and model.byLabel[selection] ~= nil
end
Model.Valid = Valid

-- Selected(model): the selection the player left on this secret when it was
-- made for the same item and is still one of its pages, else
-- DefaultSelection; and whether it was the player's (a new item opens on
-- its own step again: Task #430)
function Model.Selected(model)
  local folds = Saved("secretFolds", model.ownerKey, model.sid)
  local saved = folds and folds.sel
  if Valid(model, saved) and (folds.selFor == nil or folds.selFor == model.itemKey) then return saved, true end
  return Model.DefaultSelection(model), false
end

-- Select(model, selection): keeps the player's selection (a step's label,
-- "stage:<key>" or "summary") with the item it was made for
function Model.Select(model, selection)
  if not Valid(model, selection) then return false end
  local folds = Saved("secretFolds", model.ownerKey, model.sid, true)
  if folds then folds.sel, folds.selFor = selection, model.itemKey end
  return true
end

-- Filter(model) and SetFilter: the explorer's filter, "all" by default
function Model.Filter(model)
  local folds = Saved("secretFolds", model.ownerKey, model.sid)
  local saved = folds and folds.filter
  return Model.FILTER_WORDS[saved or ""] and saved or "all"
end

function Model.SetFilter(model, filter)
  if not Model.FILTER_WORDS[filter or ""] then return end
  local folds = Saved("secretFolds", model.ownerKey, model.sid, filter ~= "all")
  if folds then folds.filter = filter ~= "all" and filter or nil end
end

-- Searching(search): the search's words, trimmed and in lower case, or nil for none
local function Searching(search)
  search = tostring(search or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  return search ~= "" and search or nil
end

-- Filtered(filter, search): whether the filter or the search narrows the list
function Model.Filtered(filter, search)
  return (filter or "all") ~= "all" or Searching(search) ~= nil
end

-- Matches(row, filter, search): whether a step shows under the filter and
-- the search: To do leaves out what the game reads done and what the
-- player marked; This item keeps every step the item is in, whatever its
-- role or state; the search reads the step's code, its words and the names
-- they link, in any case
function Model.Matches(row, filter, search)
  if filter == "todo" and row.done then return false end
  if filter == "mine" and not row.own then return false end
  search = Searching(search)
  if not search then return true end
  local words = row.search or table.concat({ tostring(row.label), tostring(row.title or ""), tostring(row.text or "") },
    "\31"):lower()
  return words:find(search, 1, true) ~= nil
end

-- Tree(model, filter, search): the explorer's rows, in order: { stage, open }
-- and { row, depth, childrenOpen, context }. Unfiltered it is Visible's tree
-- (folds kept); filtered or searched, every matching step under its stage,
-- with the steps above it shown as context (dimmed, `context`), each stage
-- and branch open for now, the saved folds untouched
function Model.Tree(model, filter, search)
  filter = filter or "all"
  if not Model.Filtered(filter, search) then
    local out = {}
    for _, item in ipairs(Model.Visible(model)) do
      if item.stage then
        out[#out + 1] = { stage = item.stage, open = item.open }
      else
        out[#out + 1] = { row = item.row, depth = item.row.depth, childrenOpen = item.childrenOpen }
      end
    end
    return out
  end
  local keep = {}
  for i, row in ipairs(model.rows) do
    if Model.Matches(row, filter, search) then
      keep[i] = "match"
      local up = row.parent and model.byLabel[row.parent]
      while up do
        keep[up.index] = keep[up.index] or "context"
        up = up.parent and model.byLabel[up.parent]
      end
    end
  end
  local out, stageAt, shownStage = {}, {}, nil
  for _, stage in ipairs(model.stages or {}) do
    for i = stage.first, stage.last do stageAt[i] = stage end
  end
  for i, row in ipairs(model.rows) do
    if keep[i] then
      local stage = stageAt[i]
      if stage and stage ~= shownStage then
        shownStage = stage
        out[#out + 1] = { stage = stage, open = true }
      end
      out[#out + 1] = { row = row, depth = row.depth, context = keep[i] == "context" or nil }
    end
  end
  return out
end

-- Neighbor(model, selection, step, filter, search): the step before (-1) or
-- after (1) a selection in the secret's order, folded branches included;
-- with a filter or a search, the nearest matching one (a selection outside
-- them walks from where it stands); a stage's next is its first step and its
-- previous the step before it; never past either end, and none from the Summary
function Model.Neighbor(model, selection, step, filter, search)
  local rows = model.rows or {}
  local narrowed = Model.Filtered(filter, search)
  local from
  local key = type(selection) == "string" and selection:match("^stage:(.+)$")
  if key then
    local stage = Model.StageByKey(model, key)
    if not stage then return nil end
    from = step > 0 and stage.first - 1 or stage.first
  else
    local row = model.byLabel and model.byLabel[selection]
    if not row then return nil end
    from = row.index
  end
  local i = from + step
  while rows[i] do
    if not narrowed or Model.Matches(rows[i], filter, search) then return rows[i].label end
    i = i + step
  end
  return nil
end

-- Pager(model, selection, filter, search): where a step's page is, for the
-- reader's footer: { index (nil when the step is outside the filter), total,
-- kind ("page", or "match" while the list is narrowed) }; nil for a stage or the Summary
function Model.Pager(model, selection, filter, search)
  local row = type(selection) == "string" and model.byLabel and model.byLabel[selection]
  if not row then return nil end
  if not Model.Filtered(filter, search) then return { index = row.index, total = #model.rows, kind = "page" } end
  local index, total = nil, 0
  for _, r in ipairs(model.rows) do
    if Model.Matches(r, filter, search) then
      total = total + 1
      if r == row then index = total end
    end
  end
  return { index = index, total = total, kind = "match" }
end

-- Sections(row): a step's lines by the reader's section ("title", "state",
-- "action", "need", "before", "where", "more"), each a list in order
function Model.Sections(row)
  local out = { title = {}, state = {}, action = {}, need = {}, before = {}, where = {}, more = {} }
  for _, line in ipairs(row.lines or {}) do
    local list = out[line.section or "action"] or out.action
    list[#list + 1] = line
  end
  return out
end

Model._test = { Joined = Joined, Stages = Stages, PlaceLines = PlaceLines, StepNpcs = StepNpcs }
