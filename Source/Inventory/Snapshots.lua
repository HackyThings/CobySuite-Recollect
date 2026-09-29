-------------------------------------------------------------------------------
-- Snapshots: what each container held when it could last be read
--
-- RECOLLECT_DB = {
--   schema = 1,
--   characters = { [playerGUID] = { name, realm, class, faction, race, build,
--                  bankTabs, bankTabNames,
--                  locations = { [bagID] = { captured, read, changed } },
--                  recipes, professions (Facts.Recipes) } },
--   warband = { [bagID] = { captured, capturedBy, read, changed } },
--   warbandTabs, warbandTabNames,
--   lab = { ... },   -- development builds only; never touched here
-- }
--
-- The character's bags are captured on login and on BAG_UPDATE_DELAYED
-- (folded, and held until combat ends). The bank is captured only while it
-- is open: through a banker (Banker, CharacterBanker or AccountBanker
-- interaction) or BANKFRAME_OPENED, and only for a bank type that
-- C_Bank.CanViewBank allows. The warband bank also needs no locked reason.
-- Opening the bank reads every tab; after that a BAG_UPDATE reads again only
-- the tab it names (as Blizzard's own bank panel refreshes), and any other
-- bank event, a retry, or a read that came back incomplete reads every tab.
--
-- Rules that keep verdicts honest:
--   * An unreadable or incomplete read never replaces a stored location; the
--     read is retried a few times and the old snapshot stays meanwhile. With
--     the bank open, a purchased tab that reads no slots counts as
--     incomplete too (BA-08), so it is retried.
--   * A read is owed by a tab whose contents may have changed since it was
--     stored: one a BAG_UPDATE named, or every bank tab after an event that
--     names none. Only a good read of that tab pays it (an only-read that
--     skipped it, or a bank type that couldn't be viewed, leaves it owed).
--     A bank close, or a logout with the bank open, marks the stored tabs
--     still owed changed = true (BA-01): their rows read Unknown until the
--     next good read replaces the entry. Opening the bank, or a read that
--     came back incomplete, owes nothing by itself: those change no
--     contents, and the stored entry stays as good as it was. (Only the
--     bank's own reads are owed: with the bank closed its contents can only
--     be used up by crafting, which the live count check in Verdicts.Rows
--     sees.)
--   * Nothing here removes keys it does not own (the Lab's lab table).
--   * Only C_Container and C_Bank are read. BankFrame, BankPanel and the
--     container frames are never called, read or hooked: every bag
--     right-click reads BankPanel's state while the bank is open.
-------------------------------------------------------------------------------
local Snapshots = {}
Recollect.Inventory.Snapshots = Snapshots

local Locations = Recollect.Inventory.Locations
local Reader = Recollect.Inventory.Reader
local Utilities = Recollect.Utilities
local Try = Utilities.Try

local SCHEMA = 1
local MAX_RETRIES = 3
local RETRY_DELAY = 1
local BAG_FOLD = 0.2

local seams = {
  Store = function() return RECOLLECT_DB end,
  Now = function() return time() end,
  InCombat = function() return InCombatLockdown() end,
  PlayerKey = function() return UnitGUID("player") end,
  After = function(seconds, fn) C_Timer.After(seconds, fn) end,
  Identity = function()
    return {
      name = UnitName("player"),
      realm = GetRealmName(),
      class = UnitClassBase("player"),
      faction = UnitFactionGroup("player"),
      race = select(3, UnitRace("player")),
    }
  end,
  Fire = function(event, ...) Recollect.EventBus:Fire(event, ...) end,
}

-- Bank state from events only
local bankOpen = false
local openTypes = {}          -- [interactionType] = true while that banker is shown
local bagsDirty = false
local bagRetries, bankRetries = 0, 0
-- What the next bank fold reads: the tabs a BAG_UPDATE named, or every tab
local dirtyTabs, dirtyAll = {}, false
-- The stored tabs whose contents may have changed since their last good read
-- ({ [bagID] = true }): what a bank close marks changed (BA-01)
local owed = {}

-------------------------------------------------------------------------------
-- Storage
-------------------------------------------------------------------------------
-- Normalize(db): the tables this module owns, repaired in place; any other
-- key (the Lab's) is left as it is
function Snapshots.Normalize(db)
  if type(db.characters) ~= "table" then db.characters = {} end
  if type(db.warband) ~= "table" then db.warband = {} end
  if type(db.schema) ~= "number" then db.schema = SCHEMA end
  return db
end

function Snapshots.InitializeData()
  if type(RECOLLECT_DB) ~= "table" then RECOLLECT_DB = {} end
  Snapshots.Normalize(RECOLLECT_DB)
end

local function Store()
  local db = seams.Store()
  if type(db) ~= "table" then return nil end
  if type(db.characters) ~= "table" then db.characters = {} end
  if type(db.warband) ~= "table" then db.warband = {} end
  return db
end

-- The current character's record (created when create is true), and its key
function Snapshots.CurrentCharacter(create)
  local db = Store()
  if not db then return nil end
  local ok, key = Try(seams.PlayerKey)
  if not ok or type(key) ~= "string" then return nil end
  local char = db.characters[key]
  if type(char) ~= "table" then
    if not create then return nil end
    char = {}
    db.characters[key] = char
  end
  if type(char.locations) ~= "table" then char.locations = {} end
  return char, key
end

-- Every other character with stored locations: { { key, char } }, by name
function Snapshots.OtherCharacters()
  local db = Store()
  if not db then return {} end
  local okKey, current = Try(seams.PlayerKey)
  local list = {}
  for key, char in pairs(db.characters) do
    if key ~= (okKey and current or nil) and type(char) == "table" and type(char.locations) == "table" then
      list[#list + 1] = { key = key, char = char }
    end
  end
  table.sort(list, function(a, b) return tostring(a.char.name or a.key) < tostring(b.char.name or b.key) end)
  return list
end

function Snapshots.Warband()
  local db = Store()
  return db and db.warband or nil, db
end

local function RefreshIdentity(char)
  local ok, identity = Try(seams.Identity)
  if ok and type(identity) == "table" then
    for k, v in pairs(identity) do
      if not Utilities.IsSecret(v) then char[k] = v end
    end
  end
  char.build = Utilities.Build()
end

-- StoreRead(target, bagID, read, extra): stores a readable, complete read as
-- target[bagID]; anything else leaves the stored entry as it was. Returns
-- stored, why.
function Snapshots.StoreRead(target, bagID, read, extra)
  if type(target) ~= "table" or type(read) ~= "table" then return false, "nothing to store" end
  if not read.readable then return false, "unreadable" end
  if not read.complete then return false, "incomplete" end
  local entry = { captured = seams.Now(), read = read }
  if extra then
    for k, v in pairs(extra) do entry[k] = v end
  end
  target[bagID] = entry
  return true
end

-------------------------------------------------------------------------------
-- Bags
-------------------------------------------------------------------------------
local ScheduleBagRetry

function Snapshots.CaptureBags()
  if seams.InCombat() then
    bagsDirty = true
    return false, "combat"
  end
  bagsDirty = false
  local char = Snapshots.CurrentCharacter(true)
  if not char then return false, "no character" end
  RefreshIdentity(char)
  local incomplete = false
  for _, bagID in ipairs(Locations.Bags()) do
    local read = Reader.ReadContainer(bagID)
    local stored = Snapshots.StoreRead(char.locations, bagID, read)
    if not stored then
      if read.readable then
        incomplete = true
      elseif read.numSlots == 0 and read.reason and read.reason:find("%(0%)") then
        -- A bag slot with no bag in it: bags are always visible, so zero
        -- slots here really is empty
        char.locations[bagID] = nil
      end
    end
  end
  if incomplete then ScheduleBagRetry() else bagRetries = 0 end
  seams.Fire(Recollect.Events.InventoryChanged, "bags")
  return true
end

ScheduleBagRetry = function()
  if bagRetries >= MAX_RETRIES then return end
  bagRetries = bagRetries + 1
  seams.After(RETRY_DELAY, function() Snapshots.CaptureBags() end)
end

-------------------------------------------------------------------------------
-- Bank and warband bank
-------------------------------------------------------------------------------
local ScheduleBankRetry

-- only: nil for every tab, else { [bagID] = true } for the tabs to read
local function CaptureTabs(target, tabs, extra, captured, only)
  local incomplete = false
  for _, bagID in ipairs(tabs) do
    if not only or only[bagID] then
      local read = Reader.ReadContainer(bagID, { withTooltip = true })
      if Snapshots.StoreRead(target, bagID, read, extra) then
        captured[#captured + 1] = bagID
      else
        -- incomplete, or no slots while the bank can be viewed (the callers
        -- check CanView first): read it again (BA-08)
        incomplete = true
      end
    end
  end
  return incomplete
end

local function CaptureCharacterBank(char, captured, only)
  local bankType = Locations.BANK_TYPE_CHARACTER
  if Locations.CanView(bankType) ~= true then return false end
  local tabs = Locations.PurchasedTabs(bankType)
  if not tabs then return false end
  char.bankTabs = tabs
  char.bankTabNames = Locations.TabNames(bankType)
  return CaptureTabs(char.locations, tabs, nil, captured, only)
end

local function CaptureWarbandBank(key, captured, only)
  local bankType = Locations.BANK_TYPE_ACCOUNT
  if Locations.CanView(bankType) ~= true then return false end
  local ok, reason = Locations.LockedReason(bankType)
  if not ok or reason ~= nil then return false end
  local tabs = Locations.PurchasedTabs(bankType)
  if not tabs then return false end
  local warband, db = Snapshots.Warband()
  db.warbandTabs = tabs
  db.warbandTabNames = Locations.TabNames(bankType)
  return CaptureTabs(warband, tabs, { capturedBy = key }, captured, only)
end

-- CaptureBank(only): reads every purchased tab of both banks, or with only
-- ({ [bagID] = true }) just those tabs; the tab lists and names are read
-- again either way. An incomplete read retries every tab, and the next bank
-- event reads every tab too.
function Snapshots.CaptureBank(only)
  if not bankOpen then return false, "bank closed" end
  local char, key = Snapshots.CurrentCharacter(true)
  if not char then return false, "no character" end
  RefreshIdentity(char)
  local captured = {}
  local incompleteBank = CaptureCharacterBank(char, captured, only)
  local incompleteWarband = CaptureWarbandBank(key, captured, only)
  if incompleteBank or incompleteWarband then
    dirtyAll = true
    ScheduleBankRetry()
  elseif not only then
    bankRetries = 0
    -- every tab it could view was read and stored: no fold is needed
    if #captured > 0 then dirtyTabs, dirtyAll = {}, false end
  end
  -- a good read pays what that tab owed; nothing else does
  for _, bagID in ipairs(captured) do owed[bagID] = nil end
  if #captured > 0 then seams.Fire(Recollect.Events.SnapshotCaptured, captured) end
  seams.Fire(Recollect.Events.InventoryChanged, "bank")
  return true, captured
end

ScheduleBankRetry = function()
  if bankRetries >= MAX_RETRIES then return end
  bankRetries = bankRetries + 1
  seams.After(RETRY_DELAY, function()
    if bankOpen then Snapshots.CaptureBank() end
  end)
end

function Snapshots.IsBankOpen()
  return bankOpen
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local Interaction = Enum and Enum.PlayerInteractionType or {}
local BANKER_TYPES = {}
for _, name in ipairs({ "Banker", "CharacterBanker", "AccountBanker" }) do
  if Interaction[name] then BANKER_TYPES[Interaction[name]] = true end
end

local bagFold = CobySuite_Recollect.Utilities.Coalesce(BAG_FOLD, function() Snapshots.CaptureBags() end)
local bankFold = CobySuite_Recollect.Utilities.Coalesce(BAG_FOLD, function()
  local only = (not dirtyAll and next(dirtyTabs) ~= nil) and dirtyTabs or nil
  dirtyTabs, dirtyAll = {}, false
  if bankOpen then Snapshots.CaptureBank(only) end
end)

-- Every tab is read on the next fold
local function FoldAllTabs()
  dirtyAll = true
  bankFold:Call()
end

-- Every bank tab this character's record or the warband's knows (the tab
-- lists and the stored entries): what an event naming no tab may have changed
local function AllBankTabs()
  local set = {}
  local char = Snapshots.CurrentCharacter(false)
  local warband, db = Snapshots.Warband()
  for _, list in ipairs({ char and char.bankTabs or {}, db and db.warbandTabs or {} }) do
    for _, bagID in ipairs(type(list) == "table" and list or {}) do set[bagID] = true end
  end
  for _, target in ipairs({ char and char.locations or {}, warband or {} }) do
    for bagID in pairs(target) do
      local kind = Locations.KindOf(bagID)
      if kind and kind ~= Locations.KIND_BAGS then set[bagID] = true end
    end
  end
  return set
end

-- An event naming no tab: every tab owes a read, and every tab is read
local function OweAllTabs()
  for bagID in pairs(AllBankTabs()) do owed[bagID] = true end
  FoldAllTabs()
end

-- Marks stored bank tabs changed: those in tabs ({ [bagID] = true }), or
-- every stored bank and warband tab when tabs is nil
function Snapshots.MarkChanged(tabs)
  local char = Snapshots.CurrentCharacter(false)
  local warband = Snapshots.Warband()
  local marked = 0
  for _, target in ipairs({ char and char.locations or {}, warband or {} }) do
    for bagID, entry in pairs(target) do
      local kind = Locations.KindOf(bagID)
      if type(entry) == "table" and kind and kind ~= Locations.KIND_BAGS and (not tabs or tabs[bagID]) then
        entry.changed = true
        marked = marked + 1
      end
    end
  end
  return marked
end

-- The bank closes (or the character logs out with it open): tabs still owed
-- a read keep their old snapshot, marked changed (BA-01)
local function MarkOwedReads()
  local marked = next(owed) and Snapshots.MarkChanged(owed) or 0
  wipe(owed)
  bankFold:Cancel()
  if marked > 0 then Recollect.Debug.Log("INVENTORY", "Bank closed with reads owed: %d tabs marked changed", marked) end
end

local function SetBankOpen(open)
  if open == bankOpen then return end
  if not open then MarkOwedReads() end
  bankOpen = open
  bankRetries = 0
  dirtyTabs, dirtyAll = {}, false
  wipe(owed)
  Recollect.Debug.Log("INVENTORY", "Bank %s", open and "opened" or "closed")
  if open then
    -- Tab contents can arrive a moment after the interaction starts
    FoldAllTabs()
  else
    seams.Fire(Recollect.Events.InventoryChanged, "bank")
  end
end

local handlers = {}

function handlers.PLAYER_ENTERING_WORLD() bagFold:Call() end
function handlers.BAG_UPDATE_DELAYED() bagFold:Call() end

-- A bank tab's BAG_UPDATE reads that tab again; an ID no kind covers, every tab
function handlers.BAG_UPDATE(bagID)
  if not bankOpen then return end
  local kind = Locations.KindOf(bagID)
  if kind == Locations.KIND_BAGS then return end
  if kind then
    dirtyTabs[bagID] = true
    owed[bagID] = true
    bankFold:Call()
  else
    OweAllTabs()
  end
end

-- These name no tab
function handlers.PLAYERBANKSLOTS_CHANGED() if bankOpen then OweAllTabs() end end
function handlers.PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED() if bankOpen then OweAllTabs() end end
function handlers.BANK_TABS_CHANGED() if bankOpen then OweAllTabs() end end

-- Logging out with the bank open: no close event comes, so the reads still
-- owed are marked now (B6)
function handlers.PLAYER_LOGOUT()
  if bankOpen then MarkOwedReads() end
end

function handlers.PLAYER_REGEN_ENABLED()
  if bagsDirty then bagFold:Call() end
end

function handlers.PLAYER_INTERACTION_MANAGER_FRAME_SHOW(interactionType)
  if not BANKER_TYPES[interactionType] then return end
  openTypes[interactionType] = true
  SetBankOpen(true)
end

function handlers.PLAYER_INTERACTION_MANAGER_FRAME_HIDE(interactionType)
  if not BANKER_TYPES[interactionType] then return end
  openTypes[interactionType] = nil
  if next(openTypes) == nil then SetBankOpen(false) end
end

function handlers.BANKFRAME_OPENED() SetBankOpen(true) end

function handlers.BANKFRAME_CLOSED()
  wipe(openTypes)
  SetBankOpen(false)
end

local frame = CreateFrame("Frame")
for event in pairs(handlers) do
  -- Protected, so a client without one of these events still loads
  pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, ...)
  local handler = handlers[event]
  if handler then handler(...) end
end)

-------------------------------------------------------------------------------
-- Test seams
-------------------------------------------------------------------------------
local function CopySet(set)
  local copy = {}
  for k, v in pairs(set) do copy[k] = v end
  return copy
end

-- Whether a tab's read is owed now (its contents may have changed since its
-- last good read; PI-10: its stored rows are as uncertain as a changed tab's)
function Snapshots.IsOwed(bagID)
  return owed[bagID] == true
end

Snapshots._test = {
  seams = seams,
  SetBankOpen = function(open)
    bankOpen = open and true or false
    bankRetries = 0
    dirtyTabs, dirtyAll = {}, false
    wipe(owed)
  end,
  -- The close as the events run it (SetBankOpen above only sets the state)
  CloseBank = function() SetBankOpen(false) end,
  BankEvent = function(event, ...) handlers[event](...) end,
  FoldPending = function() return bankFold:IsPending() end,
  -- The module's state, as a copy a suite can hand back to SetState
  GetState = function()
    return {
      bankOpen = bankOpen, openTypes = CopySet(openTypes), bagsDirty = bagsDirty,
      bagRetries = bagRetries, bankRetries = bankRetries,
      dirtyTabs = CopySet(dirtyTabs), dirtyAll = dirtyAll, owed = CopySet(owed),
    }
  end,
  -- Sets each field state gives (GetState's names); a field left out keeps
  -- its value. openTypes and dirtyTabs are copied in.
  SetState = function(state)
    if state.bankOpen ~= nil then bankOpen = state.bankOpen and true or false end
    if state.openTypes ~= nil then
      wipe(openTypes)
      for k, v in pairs(state.openTypes) do openTypes[k] = v end
    end
    if state.bagsDirty ~= nil then bagsDirty = state.bagsDirty and true or false end
    if state.bagRetries ~= nil then bagRetries = state.bagRetries end
    if state.bankRetries ~= nil then bankRetries = state.bankRetries end
    if state.dirtyTabs ~= nil then dirtyTabs = CopySet(state.dirtyTabs) end
    if state.dirtyAll ~= nil then dirtyAll = state.dirtyAll and true or false end
    if state.owed ~= nil then
      wipe(owed)
      for k, v in pairs(state.owed) do owed[k] = v end
    end
  end,
  -- Runs fn with store as RECOLLECT_DB for this module; the real store
  -- comes back even when fn errors
  WithStore = function(store, fn)
    local original = seams.Store
    seams.Store = function() return store end
    local ok, err = pcall(fn)
    seams.Store = original
    if not ok then error(err, 0) end
  end,
}
