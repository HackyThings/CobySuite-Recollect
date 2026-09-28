-------------------------------------------------------------------------------
-- Purpose: a bag (item class 1)
--
-- Its size comes from the tooltip's "36 Slot Bag" line (CONTAINER_SLOTS, so
-- any language), its kind from its subclass: 0 a bag, 11 a reagent bag,
-- anything else a profession bag (Herb Bag, Mining Bag, ...), which holds
-- only its profession's items. What it is compared with: the bags worn in
-- the four bag slots (Enum.BagIndex 1 to 4), or the reagent bag slot (5) for
-- a reagent bag, each read as (worn or empty, slots, subclass).
--
--   an empty slot it could go in                  Useful
--   bigger than the smallest bag worn there       Useful (a profession bag:
--                                                 Unknown, it holds less)
--   no bigger than every bag worn there           Outdated (a bag: only when
--                                                 every worn bag is a plain bag)
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try
local IsFiniteNumber = CobySuite_Recollect.Utilities.IsFiniteNumber
local Ready = Recollect.Facts.Ready

local SUB_BAG, SUB_REAGENT = 0, 11
local BAG_SLOTS = { 1, 2, 3, 4 }
local REAGENT_SLOTS = { 5 }

-- The worn bags in slots: { empty = n, smallest = slots, allPlain = bool },
-- or nil when a worn bag can't be read
local function Worn(client, slots)
  local worn = { empty = 0, smallest = nil, allPlain = true }
  for _, bagID in ipairs(slots) do
    local ok, exists, numSlots, subclassID = Try(client.GetEquippedBag, bagID)
    if not ok or type(exists) ~= "boolean" then return nil end
    if not exists then
      worn.empty = worn.empty + 1
    else
      if not IsFiniteNumber(numSlots) or numSlots <= 0 then return nil end
      if not worn.smallest or numSlots < worn.smallest then worn.smallest = numSlots end
      if subclassID ~= SUB_BAG then worn.allPlain = false end
    end
  end
  return worn
end

R.Register({
  key = "bag",
  label = "Bag",
  order = 63,
  Evaluate = function(ctx)
    if ctx.facts.classID ~= R.CLASS_CONTAINER then return nil end
    local tip = ctx.Tooltip()
    local size = tip and tip.bagSlots
    if not IsFiniteNumber(size) then return R.Unknown("Bag; its size can't be read from its tooltip") end
    local sizeText = ("%d-slot"):format(size)
    local what = ("%s %s %s"):format(R.Article(sizeText), sizeText, (tip.bagKind or "bag"):lower())
    if not Ready.Equipment() then return R.Unknown(what .. "; your bags can't be read yet") end
    local sub = ctx.facts.subclassID
    local reagent = sub == SUB_REAGENT
    local profession = not reagent and sub ~= SUB_BAG
    local worn = Worn(Recollect.Purposes.client, reagent and REAGENT_SLOTS or BAG_SLOTS)
    if not worn then return R.Unknown(what .. "; your bags can't be read") end
    if worn.empty > 0 then
      return R.Result(V.USEFUL, what .. (reagent and "; you have no reagent bag equipped" or "; you have an empty bag slot"))
    end
    local smallest = reagent and ("the reagent bag you wear (%d)"):format(worn.smallest)
      or ("your smallest bag (%d)"):format(worn.smallest)
    if size > worn.smallest then
      if profession then
        return R.Info(("%s, bigger than %s, but it holds only its profession's items"):format(what, smallest))
      end
      return R.Result(V.USEFUL, ("%s, bigger than %s"):format(what, smallest))
    end
    if not reagent and not profession and not worn.allPlain then
      return R.Info(("%s, no bigger than %s; one of your bags is a profession bag, which holds only its profession's items")
        :format(what, smallest))
    end
    local every = reagent and ("the reagent bag you wear holds %d"):format(worn.smallest)
      or ("every bag you wear holds at least %d"):format(worn.smallest)
    return R.Result(V.OUTDATED, ("%s; %s"):format(what, every) .. R.BindNote(ctx))
  end,
})
