-------------------------------------------------------------------------------
-- Purpose: an item that teaches a mount
--
-- Mounts are account-wide. Two sources must agree: the Mount Journal's
-- isCollected and the tooltip's "Already known" line. An uncollected mount
-- is Use now only when this character could learn it: not hidden for this
-- character, not tied to the other faction, and no red line on its tooltip
-- (a requirement this character does not meet: a profession, a reputation).
--
-- A mount of the other faction never shows "Already known" on this
-- character, even when the account has it (catalog scan 2026-09-23: 63
-- Alliance mounts on a Horde character). There the tooltip's "Alliance Only"
-- or "Horde Only" line must name the faction the journal gives instead. For
-- another character's copy the tooltip is the logged-in character's
-- (tip.viewerFaction), so its line is read against that faction.
--
-- GetMountInfoByID returns name, spellID, icon, isActive, isUsable,
-- sourceType, isFavorite, isFactionSpecific (8), faction (9, PvPFaction),
-- shouldHideOnChar (10), isCollected (11), ... (12.1 docs).
-------------------------------------------------------------------------------
local R = Recollect.Purposes.Registry
local V = R.Verdict
local Try = Recollect.Utilities.Try
local IsPositiveID = Recollect.Utilities.IsPositiveID

R.Register({
  key = "mount",
  accountWide = true,   -- the same answer for any character's copy
  label = "Mount",
  order = 30,
  Evaluate = function(ctx)
    local client = Recollect.Purposes.client
    local ok, mountID = Try(client.GetMountFromItem, ctx.stack.itemID)
    -- A failed read may hide a mount: Unknown, never silence (BA-02)
    if not ok then return R.Unknown("Whether it teaches a mount can't be read", nil, "unreadable") end
    if not IsPositiveID(mountID) then return nil end
    if not Recollect.Facts.Ready.Mounts() then return R.Unknown("Mount; the Mount Journal hasn't loaded yet", nil, "loading") end
    local okInfo, _, _, _, _, _, _, _, isFactionSpecific, faction, shouldHideOnChar, isCollected =
      Try(client.GetMountInfoByID, mountID)
    if not okInfo or type(isCollected) ~= "boolean" then return R.Unknown("Mount; couldn't read the Mount Journal", nil, "unreadable") end
    local tip = ctx.Tooltip()
    if not tip then return R.Unknown("Mount; its tooltip can't be read to confirm", nil, "unreadable") end
    -- The copy's owner decides whether that character can learn it; the
    -- tooltip was read by the character logged in (tip.viewerFaction, set
    -- for another character's copy), whose faction decides what it shows (BA-06)
    local otherFaction = isFactionSpecific and faction ~= ctx.playerFaction
    local viewerFaction = tip.viewerFaction
    if viewerFaction == nil then viewerFaction = ctx.playerFaction end
    local tipOtherFaction = isFactionSpecific and faction ~= viewerFaction
    if isCollected and not tip.known and tipOtherFaction and tip.factionOnly ~= nil and tip.factionOnly == faction then
      return R.Result(V.DONE, ("Duplicate: your account already has this mount (Mount Journal); it's %s only, so its tooltip can't show that here")
        :format(faction == 0 and "Horde" or "Alliance"))
    end
    if tip.known ~= isCollected then return R.Unknown("Mount; the Mount Journal and the tooltip disagree", nil, "disagree") end
    if isCollected then return R.Result(V.DONE, "Duplicate: you already have this mount") end
    if shouldHideOnChar and not ctx.otherCharacter then return R.Unknown("Mount this character can't learn") end
    if otherFaction then return R.Unknown("Mount for the other faction") end
    if tip.redLines > 0 then return R.Unknown("Mount not collected, but this character can't use it yet (see its tooltip)") end
    return R.Result(V.USE, "Mount not collected; use it to learn")
  end,
})
