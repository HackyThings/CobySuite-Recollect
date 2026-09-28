-------------------------------------------------------------------------------
-- Locations: where an item can sit, by container ID (Enum.BagIndex, 12.1)
--
--   bags     0 to 5    Backpack, Bag_1 to Bag_4, ReagentBag
--   bank     6 to 11   CharacterBankTab_1 to _6
--   warband  12 to 16  AccountBankTab_1 to _5
--
-- Which bank tabs exist comes from C_Bank.FetchPurchasedBankTabIDs per bank
-- type, and their names from FetchPurchasedBankTabData. Nothing here touches
-- Blizzard's bank frames.
-------------------------------------------------------------------------------
local Locations = {}
Recollect.Inventory.Locations = Locations

local Try = Recollect.Utilities.Try

local BagIndex = Enum and Enum.BagIndex or {}
local BankType = Enum and Enum.BankType or {}

Locations.BACKPACK = BagIndex.Backpack or 0
Locations.REAGENT_BAG = BagIndex.ReagentBag or 5
Locations.FIRST_BANK_TAB = BagIndex.CharacterBankTab_1 or 6
Locations.LAST_BANK_TAB = BagIndex.CharacterBankTab_6 or 11
Locations.FIRST_WARBAND_TAB = BagIndex.AccountBankTab_1 or 12
Locations.LAST_WARBAND_TAB = BagIndex.AccountBankTab_5 or 16

Locations.BANK_TYPE_CHARACTER = BankType.Character or 0
Locations.BANK_TYPE_ACCOUNT = BankType.Account or 2

Locations.KIND_BAGS = "bags"
Locations.KIND_BANK = "bank"
Locations.KIND_WARBAND = "warband"

-- The bags a character carries, in order
function Locations.Bags()
  local list = {}
  for bagID = Locations.BACKPACK, Locations.REAGENT_BAG do list[#list + 1] = bagID end
  return list
end

-- "bags", "bank", "warband" or nil
function Locations.KindOf(bagID)
  if type(bagID) ~= "number" then return nil end
  if bagID >= Locations.BACKPACK and bagID <= Locations.REAGENT_BAG then return Locations.KIND_BAGS end
  if bagID >= Locations.FIRST_BANK_TAB and bagID <= Locations.LAST_BANK_TAB then return Locations.KIND_BANK end
  if bagID >= Locations.FIRST_WARBAND_TAB and bagID <= Locations.LAST_WARBAND_TAB then return Locations.KIND_WARBAND end
  return nil
end

-- Seams: every bank call goes through here, so suites can script it
local seams = {
  CanViewBank = function(bankType) return C_Bank.CanViewBank(bankType) end,
  FetchPurchasedBankTabIDs = function(bankType) return C_Bank.FetchPurchasedBankTabIDs(bankType) end,
  FetchPurchasedBankTabData = function(bankType) return C_Bank.FetchPurchasedBankTabData(bankType) end,
  FetchBankLockedReason = function(bankType) return C_Bank.FetchBankLockedReason(bankType) end,
}
Locations._test = { seams = seams }

-- CanView(bankType): true, false, or nil when the call failed
function Locations.CanView(bankType)
  local ok, canView = Try(seams.CanViewBank, bankType)
  if not ok or type(canView) ~= "boolean" then return nil end
  return canView
end

-- LockedReason(bankType): ok, reason. ok is false when the call failed; a
-- nil reason means unlocked (Blizzard treats any reason as locked).
function Locations.LockedReason(bankType)
  local ok, reason = Try(seams.FetchBankLockedReason, bankType)
  if not ok then return false, nil end
  return true, reason
end

-- PurchasedTabs(bankType): the purchased tab container IDs in order, or nil
-- when the call failed or returned something else
function Locations.PurchasedTabs(bankType)
  local ok, ids = Try(seams.FetchPurchasedBankTabIDs, bankType)
  if not ok or type(ids) ~= "table" then return nil end
  local list = {}
  for _, id in ipairs(ids) do
    if type(id) == "number" then list[#list + 1] = id end
  end
  table.sort(list)
  return list
end

-- TabNames(bankType): { [bagID] = name } for the purchased tabs, possibly
-- empty
function Locations.TabNames(bankType)
  local names = {}
  local ok, data = Try(seams.FetchPurchasedBankTabData, bankType)
  if ok and type(data) == "table" then
    for _, tab in ipairs(data) do
      if type(tab) == "table" and type(tab.ID) == "number" and type(tab.name) == "string" and tab.name ~= "" then
        names[tab.ID] = tab.name
      end
    end
  end
  return names
end

-- Label(bagID, names): a short place name for the list ("Bags", "Reagent
-- bag", "Bank tab 2 (Mats)", "Warband tab 1")
function Locations.Label(bagID, names)
  local kind = Locations.KindOf(bagID)
  local custom = names and names[bagID]
  if kind == Locations.KIND_BAGS then
    return bagID == Locations.REAGENT_BAG and "Reagent bag" or "Bags"
  elseif kind == Locations.KIND_BANK then
    local label = "Bank tab " .. (bagID - Locations.FIRST_BANK_TAB + 1)
    return custom and (label .. " (" .. custom .. ")") or label
  elseif kind == Locations.KIND_WARBAND then
    local label = "Warband tab " .. (bagID - Locations.FIRST_WARBAND_TAB + 1)
    return custom and (label .. " (" .. custom .. ")") or label
  end
  return "Container " .. tostring(bagID)
end
