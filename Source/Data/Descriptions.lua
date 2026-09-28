-------------------------------------------------------------------------------
-- Data.Descriptions: what an item does, in Recollect's own words, for items
-- whose tooltip leaves a new player guessing and whose use no other data
-- explains (Cobanyte, 2026-09-28). Written from the game's own tooltip and
-- spell text, never copied from a website. Read only by the item details
-- window's explanation (UI.DetailWindow FOR.Explain); never a verdict.
--   [itemID] = "One or two short sentences."
-------------------------------------------------------------------------------
Recollect.Data = Recollect.Data or {}
Recollect.Data.Descriptions = {
  [6948] = "Every character's basic way home: it is reusable, and hearthstone toys share its cooldown.",   -- Hearthstone
  [21745] = "A just-for-fun item: the ring of light is only for show and has no other effect.",   -- Elder's Moonstone
  [32757] = "A reusable teleport to the Black Temple raid in Shadowmoon Valley, in Outland.",   -- Blessed Medallion of Karabor
  [35223] = "A cosmetic treat for companion pets: it enlarges your summoned pet while it follows you, and does nothing else.",   -- Papa Hummel's Old-Fashioned Pet Biscuit
  [37863] = "A reusable Brewfest item: it brings your group to the Grim Guzzler, the tavern inside the Blackrock Depths dungeon.",   -- Direbrew's Remote
  [38233] = "A cosmetic item: the fel fire trail is only for show and has no other effect.",   -- Path of Illidan
  [38577] = "A just-for-fun novelty: it gets players nearby dancing for a moment and has no other effect.",   -- Party G.R.E.N.A.D.E.
  [41367] = "A cosmetic item: the beam is only for show and has no other effect.",   -- Dark Jade Focusing Lens
  [42420] = "A cosmetic item: the beam is only for show and has no other effect.",   -- Shadow Crystal Focusing Lens
  [46725] = "A just-for-fun toy gun: its pellet does no real harm and has no gameplay use.",   -- Red Rider Air Rifle
  [71153] = "A cosmetic treat for companion pets: it enlarges your summoned pet while it follows you, and does nothing else.",   -- Magical Pet Biscuit
  [86143] = "A pet battle supply for when the Revive Battle Pets spell is on cooldown; each bandage is used up.",   -- Battle Pet Bandage
  [89906] = "A cosmetic treat for companion pets: it shrinks your summoned pet while it follows you, and does nothing else.",   -- Magical Mini-Treat
  [116422] = "A pet battle item that is used up on one Magic-family battle pet; a pet already at level 25 can't gain from it.",   -- Magic Battle-Training Stone
  [122340] = "An upgrade for your heirloom collection: the new level cap applies to that heirloom account-wide, for every copy you make from then on. It is used up.",   -- Timeworn Heirloom Armor Casing
  [163213] = "A just-for-fun item: the skull is only for show and has no gameplay use.",   -- Ghostly Explorer's Skull
  [180817] = "Ve'nari is the Maw's broker who trades for Stygia; this cypher is reusable.",   -- Cypher of Relocation
  [188198] = "A Shadowlands item: using it adds anima to your covenant's reservoir, which your covenant's sanctum upgrades spend.",   -- Traveler's Anima Cache
  [241326] = "A flask: only one flask's effect can be active at a time, and it stays on through death.",   -- Flask of the Shattered Sun
  [243734] = "A temporary weapon enhancement: the coating stays on the weapon until its time runs out, even through death.",   -- Thalassian Phoenix Oil
  [246492] = "An augment rune, the small stat boost players add before raids and dungeons; only one augment rune's effect can be active at a time.",   -- Soulgorged Augment Rune
}
