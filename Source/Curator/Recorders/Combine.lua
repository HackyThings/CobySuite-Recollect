-------------------------------------------------------------------------------
-- Curator recorder: combines (curator spec, "v1 recorders")
--
-- The Lab's evidence rule (Tests/Lab/Combines.lua), written again for
-- release builds, which carry no Lab, on the shared bag observer
-- (Recorders/Bags.lua). A combine seen in game is exactly one item gone up
-- (the product) and, among the items gone down, one that went down by a
-- count the shipped data says it combines (a makes code, confirmed or not,
-- or its count among a combine's parts) and whose own Use spell the player
-- cast within the observer's CAST_WINDOW: a vendor trade or a mail that
-- swaps one item for another casts no such spell. Several parts used up by
-- one cast are each recorded as making the product; parts of different
-- spells both cast just before are no answer. Other items gone down in the
-- same update don't refuse it. Compare.Combine turns each into a
-- confirmation, an addition or a conflict, in a later frame, keeping the
-- Use spell with each observation.
-------------------------------------------------------------------------------
local Curator = Recollect.Curator
local Host = Curator.Host
local Bags = Curator.Recorders.Bags

local Combine = {}
Curator.Recorders.Combine = Combine

-- The counts the shipped data says an item combines: { [n] = true }
local function CombineCounts(itemID)
  local counts = {}
  for _, combine in ipairs(Host.Combines(itemID)) do counts[combine.count] = true end
  return counts
end

-- Judge(before, after): the combines the change shows, one per input
-- ({ { input, inCount, output, outCount, spell, also } }), or nil
function Combine.Judge(before, after)
  local down, up = Bags.Changes(before, after)
  if #down == 0 or #up ~= 1 then return nil end
  local inputs, spell = {}, nil
  for _, d in ipairs(down) do
    local cast = CombineCounts(d.id)[d.n] and Bags.CastJustNow(d.id)
    if cast then
      if spell and cast ~= spell then return nil end   -- two casts, either could have made it: no answer
      spell = cast
      inputs[#inputs + 1] = d
    end
  end
  if #inputs == 0 then return nil end
  local also = {}
  for _, d in ipairs(down) do
    if not CombineCounts(d.id)[d.n] or Bags.CastJustNow(d.id) ~= spell then also[#also + 1] = ("%dx%d"):format(d.id, d.n) end
  end
  local alsoText = #also > 0 and table.concat(also, ",") or nil
  local out = {}
  for _, d in ipairs(inputs) do
    out[#out + 1] = { input = d.id, inCount = d.n, output = up[1].id, outCount = up[1].n, spell = spell, also = alsoText }
  end
  return out
end

function Combine.OnBagsChanged(before, after)
  local judged = Combine.Judge(before, after)
  if not judged then return end
  Curator.Main.Defer(function()
    local ctx = Curator.Context.Current()
    for _, seen in ipairs(judged) do
      local result = Curator.Compare.Combine(seen, ctx)
      Host.Log("Combine seen: %d x%d made %d x%d (%s)", seen.input, seen.inCount, seen.output, seen.outCount,
        tostring(result or "no shipped combine of that count"))
    end
  end)
end

Bags.Subscribe(function(before, after) Combine.OnBagsChanged(before, after) end)
