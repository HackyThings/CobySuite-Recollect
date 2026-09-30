-------------------------------------------------------------------------------
-- Data.Descriptions: what an item does, in Recollect's own words, for items
-- whose tooltip leaves a new player guessing and whose use no other data
-- explains (Cobanyte, 2026-09-28). Written from the game's own tooltip and
-- spell text, or from research kept in the repo's notes, always in our own
-- words and never copied from a website. Read by the item details
-- window's explanation (UI.DetailWindow FOR.Explain) and by curator mode's
-- test for items the data says nothing about (Curator.Host Knows); never a
-- verdict.
--   [itemID] = "One or two short sentences."
-------------------------------------------------------------------------------
Recollect.Data = Recollect.Data or {}
Recollect.Data.Descriptions = {
  [6948] = "Every character's basic way home: it is reusable, and hearthstone toys share its cooldown.",   -- Hearthstone
  [8383] = "A letter kept from your mailbox as an item, so it can be read again whenever you like.",   -- Plain Letter
  [21745] = "A just-for-fun item: using it puts a ring of light around you, just for show.",   -- Elder's Moonstone
  [32757] = "A reusable teleport to the Black Temple raid in Shadowmoon Valley, in Outland.",   -- Blessed Medallion of Karabor
  [33475] = "The Lich King's runeblade as the game keeps it for its own characters: players can't obtain it, so it only shows up through a link.",   -- Frostmourne
  [35223] = "A cosmetic treat for companion pets: it enlarges your summoned pet while it follows you.",   -- Papa Hummel's Old-Fashioned Pet Biscuit
  [37863] = "A reusable Brewfest item: it brings your group to the Grim Guzzler, the tavern inside the Blackrock Depths dungeon.",   -- Direbrew's Remote
  [38233] = "A cosmetic item: using it leaves a trail of fel fire behind you, just for show.",   -- Path of Illidan
  [38577] = "A just-for-fun novelty: it gets players nearby dancing for a moment.",   -- Party G.R.E.N.A.D.E.
  [41367] = "A cosmetic item: using it shows a beam of light, just for show.",   -- Dark Jade Focusing Lens
  [42420] = "A cosmetic item: using it shows a beam of light, just for show.",   -- Shadow Crystal Focusing Lens
  [46725] = "A Feast of Winter Veil item: the achievement BB King asks you to hit the other faction's leaders with its pellets.",   -- Red Rider Air Rifle
  [71153] = "A cosmetic treat for companion pets: it enlarges your summoned pet while it follows you.",   -- Magical Pet Biscuit
  [86143] = "A pet battle supply for when the Revive Battle Pets spell is on cooldown; each bandage is used up.",   -- Battle Pet Bandage
  [89906] = "A cosmetic treat for companion pets: it shrinks your summoned pet while it follows you.",   -- Magical Mini-Treat
  [116422] = "A pet battle item that is used up on one Magic-family battle pet; a pet already at level 25 can't gain from it.",   -- Magic Battle-Training Stone
  [122340] = "An upgrade for your heirloom collection: the new level cap applies to that heirloom account-wide, for every copy you make from then on. It is used up.",   -- Timeworn Heirloom Armor Casing
  [163213] = "A just-for-fun item: using it shows a ghostly skull, just for show.",   -- Ghostly Explorer's Skull
  [173038] = "A Shadowlands fishing bait; Lost Sole is a Shadowlands cooking ingredient.",   -- Lost Sole Bait
  [173039] = "A Shadowlands fishing bait; Iridescent Amberjack is a Shadowlands cooking ingredient.",   -- Iridescent Amberjack Bait
  [173040] = "A Shadowlands fishing bait; Silvergill Pike is a Shadowlands cooking ingredient.",   -- Silvergill Pike Bait
  [173043] = "A Shadowlands fishing bait; Elysian Thade is a Shadowlands cooking ingredient.",   -- Elysian Thade Bait
  [180653] = "The key to one Mythic+ run of the dungeon it names, at the level it shows; a run finished in time raises its level, and a new keystone comes each week.",   -- Mythic Keystone
  [180817] = "Ve'nari is the Maw's broker who trades for Stygia; each cypher holds five uses.",   -- Cypher of Relocation
  [188198] = "A Shadowlands item: using it adds anima to your covenant's reservoir, which your covenant's sanctum upgrades spend.",   -- Traveler's Anima Cache
  [225767] = "Only useful during Awakening the Machine, the wave event in the Ringing Deeps of Khaz Algar.",   -- Spare Toolbox
  [241326] = "A flask: only one flask's effect can be active at a time, and it stays on through death.",   -- Flask of the Shattered Sun
  [243734] = "A temporary weapon enhancement: the coating stays on the weapon until its time runs out, even through death.",   -- Thalassian Phoenix Oil
  [246492] = "An augment rune, the small stat boost players add before raids and dungeons; only one augment rune's effect can be active at a time.",   -- Soulgorged Augment Rune
}
