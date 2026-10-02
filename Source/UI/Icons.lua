-------------------------------------------------------------------------------
-- UI.Icons: the small state icons beside what a line or a row says
-- (Cobanyte, 2026-09-30: "green checkmarks and iconography to represent
-- information": checks, X's, warnings), from the game's own atlases, so
-- nothing is packaged, each one Blizzard's own UI uses:
--   done   common-icon-checkmark         earned, collected, known, looted, reached
--   no     common-icon-redx              still to get or do
--   na     common-icon-redx, grayed      not for this character, no longer available
--   warn   transmog-icon-warning-small   can't be read
--   wait   UI-LFG-PendingMark            still being checked
-- They are added only where text is painted (never to a line's own text,
-- which Copy and chat use), sized to the text they sit in: inline markup
-- at height 0 takes the font's height, and a texture takes the size its
-- painter gives it.
-------------------------------------------------------------------------------
local Icons = {}
Recollect.UI.Icons = Icons

Icons.ATLAS = {
  done = "common-icon-checkmark",
  no = "common-icon-redx",
  na = "common-icon-redx",
  warn = "transmog-icon-warning-small",
  wait = "UI-LFG-PendingMark",
}
-- A kind drawn grayed (0 to 255, as the game's inline markup takes them)
Icons.GRAY = { na = { 150, 150, 150 } }

-- Markup(kind, size): the icon as inline text with a space after it, size
-- 0 (the default) being the font's height; "" for no kind
function Icons.Markup(kind, size)
  local atlas = kind and Icons.ATLAS[kind]
  if not atlas then return "" end
  size = tonumber(size) or 0
  local gray = Icons.GRAY[kind]
  if gray then
    return ("|A:%s:%d:%d:0:0:%d:%d:%d|a "):format(atlas, size, size, gray[1], gray[2], gray[3])
  end
  return ("|A:%s:%d:%d|a "):format(atlas, size, size)
end

-- Paint(texture, kind): shows the icon on a texture (the painter sizes and
-- places it); false for no kind
function Icons.Paint(texture, kind)
  local atlas = kind and Icons.ATLAS[kind]
  if not atlas then return false end
  texture:SetAtlas(atlas)
  local gray = Icons.GRAY[kind]
  texture:SetDesaturated(gray ~= nil)
  texture:SetVertexColor(1, 1, 1, 1)
  return true
end

-- FromRow(row): the icon for an item-details row's state, or nil when it
-- says nothing to check or cross (a count, an information row)
function Icons.FromRow(row)
  if type(row) ~= "table" then return nil end
  if row.state == "loading" then return "wait" end
  if row.state == "failed" then return "warn" end
  if type(row.stateText) == "string" and row.stateText:find("^Can't be read") then
    return row.stateText:find("yet", 1, true) and "wait" or "warn"
  end
  if row.filterState == "have" then return "done" end
  if row.filterState == "missing" then return "no" end
  if row.filterState == "other" then return "na" end
  return nil
end

-- FromLine(line): the icon for a panel line (UI.UsedFor): its own icon when
-- it names one, else what its tier and color say: done in the done color a
-- check, out of reach (label gray) a grayed cross, still to get or do a
-- cross; an information line none
function Icons.FromLine(line)
  if type(line) ~= "table" then return nil end
  if line.icon ~= nil then return line.icon or nil end
  local parts = Recollect.UI.UsedFor and Recollect.UI.UsedFor.parts
  if not parts then return nil end
  local colors, V = Recollect.UI.VerdictColors, Recollect.Purposes.Registry.Verdict
  if line.tier == parts.TIER_OPEN then return "no" end
  if line.tier == parts.TIER_CLOSED then
    if colors and V and line.color == colors[V.DONE] then return "done" end
    if line.color == CobySuite_Recollect.Utilities.Colors.LABEL_GRAY then return "na" end
  end
  return nil
end

-- FromOpen(open): the icon for a progress still to do (true), done (false)
-- or unknown (nil), as Facts.Achievements.ProgressWords answers
function Icons.FromOpen(open)
  if open == false then return "done" end
  if open == true then return "no" end
  return "warn"
end

-------------------------------------------------------------------------------
-- A check's done words (Cobanyte, 2026-10-01: an earned achievement in a
-- reason showed in plain gray). A check whose use is finished names the words
-- of its reason that say so in result.done ("earned, account-wide", "you've
-- done that part of it"); every painter of a reason (the details window's
-- Still needed? band and Checks rows, the audit panel) marks them here, so
-- they all look alike.
-------------------------------------------------------------------------------
-- DoneWords(purposes): every purpose's done words, each once, in order
function Icons.DoneWords(purposes)
  local words, seen = {}, {}
  for _, purpose in ipairs(type(purposes) == "table" and purposes or {}) do
    for _, word in ipairs(type(purpose.done) == "table" and purpose.done or {}) do
      if type(word) == "string" and word ~= "" and not seen[word] then
        seen[word] = true
        words[#words + 1] = word
      end
    end
  end
  return words
end

-- MarkDone(text, words, inline): the text with the last place each of words
-- stands alone (never inside a longer word: the names a reason links come
-- before its state) in the done color, with the check mark before it when
-- inline (a line whose bullet is not the check already); the text as it is
-- when no word is found
function Icons.MarkDone(text, words, inline)
  if type(text) ~= "string" or type(words) ~= "table" or #words == 0 then return text end
  local colors, V = Recollect.UI.VerdictColors, Recollect.Purposes.Registry.Verdict
  local color = colors and colors[V.DONE]
  if not color then return text end
  local function Word(b) return b ~= nil and (b >= 128 or string.char(b):find("%w") ~= nil) end
  -- longer words first, so one inside another is never marked twice
  local order = {}
  for _, word in ipairs(words) do
    if type(word) == "string" and word ~= "" then order[#order + 1] = word end
  end
  table.sort(order, function(a, b) return #a > #b end)
  local spans = {}
  for _, word in ipairs(order) do
    local found, from = nil, 1
    while true do
      local first, last = text:find(word, from, true)
      if not first then break end
      if not Word(text:byte(first - 1)) and not Word(text:byte(last + 1)) then found = { first, last } end
      from = last + 1
    end
    local free = found ~= nil
    for _, span in ipairs(spans) do
      if free and found[1] <= span[2] and found[2] >= span[1] then free = false end
    end
    if free then spans[#spans + 1] = found end
  end
  if #spans == 0 then return text end
  table.sort(spans, function(a, b) return a[1] < b[1] end)
  local out, at = {}, 1
  for _, span in ipairs(spans) do
    out[#out + 1] = text:sub(at, span[1] - 1)
    out[#out + 1] = (inline and Icons.Markup("done") or "") .. CobySuite_Recollect.Utilities.WrapColor(color, text:sub(span[1], span[2]))
    at = span[2] + 1
  end
  out[#out + 1] = text:sub(at)
  return table.concat(out)
end
