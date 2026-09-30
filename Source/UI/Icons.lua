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
