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
  [21744] = "A Lunar Festival firework from Lucky Red Envelopes; it is fired from a cluster rocket launcher.",   -- Lucky Rocket Cluster
  [21745] = "A just-for-fun item: using it puts a ring of light around you, just for show.",   -- Elder's Moonstone
  [32757] = "A reusable teleport to the Black Temple raid in Shadowmoon Valley, in Outland.",   -- Blessed Medallion of Karabor
  [33455] = "Brewfest's ticket from 2007, before Brewfest Prize Tokens; during Brewfest, Belbi Quikswitch (Alliance) and Blix Fixwidget (Horde) still trade it for Prize Tokens.",   -- Brewfest Prize Ticket
  [33475] = "The Lich King's runeblade as the game keeps it for its own characters: players can't obtain it, so it only shows up through a link.",   -- Frostmourne
  [33820] = "A fishing hat that also carries a reusable lure, so it earns its place with your fishing gear.",   -- Weather-Beaten Fishing Hat
  [35223] = "A cosmetic treat for companion pets: it enlarges your summoned pet while it follows you.",   -- Papa Hummel's Old-Fashioned Pet Biscuit
  [37265] = "Supplied for Tua'kea's Crab Traps at Moa'ki Harbor in Dragonblight, so you can bring traps up from the seabed.",   -- Tua'kea's Breathing Bladder
  [37863] = "A reusable Brewfest item: it brings your group to the Grim Guzzler, the tavern inside the Blackrock Depths dungeon.",   -- Direbrew's Remote
  [38233] = "A cosmetic item: using it leaves a trail of fel fire behind you, just for show.",   -- Path of Illidan
  [38577] = "A just-for-fun novelty: it gets players nearby dancing for a moment.",   -- Party G.R.E.N.A.D.E.
  [40643] = "The cosmetic reward for the achievement Twenty-Five Tabards.",   -- Tabard of the Achiever
  [41367] = "A cosmetic item: using it shows a beam of light, just for show.",   -- Dark Jade Focusing Lens
  [42420] = "A cosmetic item: using it shows a beam of light, just for show.",   -- Shadow Crystal Focusing Lens
  [46725] = "A Feast of Winter Veil item: the achievement BB King asks you to hit the other faction's leaders with its pellets.",   -- Red Rider Air Rifle
  [46765] = "Fuel from the original Warbot promotion: Warbots given opposite fuel colors fight when they meet.",   -- Blue War Fuel
  [46766] = "Fuel from the original Warbot promotion: Warbots given opposite fuel colors fight when they meet.",   -- Red War Fuel
  [71153] = "A cosmetic treat for companion pets: it enlarges your summoned pet while it follows you.",   -- Magical Pet Biscuit
  [81055] = "Pays for one ride on the Darkmoon Faire's carousel or roller coaster on Darkmoon Island; a ride gives an hour of bonus experience and reputation.",   -- Darkmoon Ride Ticket
  [82800] = "A battle pet packed so it can be traded or sold; using it adds the pet to your Pet Journal, and its link shows the pet's species, level and quality.",   -- Pet Cage
  [86143] = "A pet battle supply for when the Revive Battle Pets spell is on cooldown; each bandage is used up.",   -- Battle Pet Bandage
  [89906] = "A cosmetic treat for companion pets: it shrinks your summoned pet while it follows you.",   -- Magical Mini-Treat
  [116422] = "A pet battle item that is used up on one Magic-family battle pet; a pet already at level 25 can't gain from it.",   -- Magic Battle-Training Stone
  [119449] = "Beast Mastery hunters bring these to Gara in Shadowmoon Valley while working toward taming her.",   -- Shadowberry
  [122340] = "An upgrade for your heirloom collection: the new level cap applies to that heirloom account-wide, for every copy you make from then on. It is used up.",   -- Timeworn Heirloom Armor Casing
  [139175] = "Used while collecting the rare Legion fish for Bigger Fish to Fry and the Underlight Angler; Conjurer Margoss in Dalaran sells it for Drowned Mana.",   -- Arcane Lure
  [162025] = "A readable story piece about the Lightbound's ambitions, found during the Mag'har orc recruitment story.",   -- Sermon of the High Exarch
  [163213] = "A just-for-fun item: using it shows a ghostly skull, just for show.",   -- Ghostly Explorer's Skull
  [168328] = "Unlocks the first rank of the essence Azeroth's Undying Gift for the Heart of Azeroth.",   -- Hardened Azerite Formation
  [173038] = "A Shadowlands fishing bait; Lost Sole is a Shadowlands cooking ingredient.",   -- Lost Sole Bait
  [173039] = "A Shadowlands fishing bait; Iridescent Amberjack is a Shadowlands cooking ingredient.",   -- Iridescent Amberjack Bait
  [173040] = "A Shadowlands fishing bait; Silvergill Pike is a Shadowlands cooking ingredient.",   -- Silvergill Pike Bait
  [173043] = "A Shadowlands fishing bait; Elysian Thade is a Shadowlands cooking ingredient.",   -- Elysian Thade Bait
  [174768] = "The key to a Black Empire Coffer during the Black Empire assaults in Uldum and the Vale of Eternal Blossoms.",   -- Cursed Relic
  [180168] = "A cosmetic fishing item from the Shadowlands: it swaps your fishing bobber for one in the style of Oribos, just for looks.",   -- Oribobber
  [180653] = "The key to one Mythic+ run of the dungeon it names, at the level it shows; a run finished in time raises its level, and a new keystone comes each week.",   -- Mythic Keystone
  [180817] = "Ve'nari is the Maw's broker who trades for Stygia; each cypher holds five uses.",   -- Cypher of Relocation
  [182599] = "Dead Blanchy in Revendreth asks for this water on your fourth visit while you work toward her mount.",   -- Bucket of Clean Water
  [188198] = "A Shadowlands item: using it adds anima to your covenant's reservoir, which your covenant's sanctum upgrades spend.",   -- Traveler's Anima Cache
  [199686] = "An heirloom trinket put together from the four Dimmed Primeval elemental pieces.",   -- Unstable Elemental Confluence
  [220756] = "Found during Hallowfall's Spreading the Light event once your Hallowfall Arathi renown reaches 9; its light reveals hidden herbs, ore and treasure there.",   -- Flickering Torch
  [225767] = "Only useful during Awakening the Machine, the wave event in the Ringing Deeps of Khaz Algar.",   -- Spare Toolbox
  [237497] = "Plant it in Rich Soil, the spots by rivers and ponds in Eversong Woods, Harandar and Zul'Aman, to grow an herb you can gather.",   -- Resilient Seed
  [238487] = "A just-for-fun item fished up in Midnight's waters: using it kicks the can, just for show.",   -- Kickin' Can
  [238494] = "A reusable fishing novelty: your character poses with a sparkling catch, just for show.",   -- Another's Treasure
  [241326] = "A flask: only one flask's effect can be active at a time, and it stays on through death.",   -- Flask of the Shattered Sun
  [243734] = "A temporary weapon enhancement: the coating stays on the weapon until its time runs out, even through death.",   -- Thalassian Phoenix Oil
  [246492] = "An augment rune, the small stat boost players add before raids and dungeons; only one augment rune's effect can be active at a time.",   -- Soulgorged Augment Rune
  [246585] = "A bundle of crafting materials, the payout for filling Midnight patron crafting orders.",   -- Artisan's Consortium Payout
  [253750] = "Gathered during the Pandaren and Grummle neighborhood endeavor: carrying it keeps your Luck up while you pick berries, and Brother Cloudbluff takes five for his climbing course.",   -- Luckydo
  [258839] = "Opening it gives a profession recipe from Midnight's dungeon recipe pool.",   -- Concealed Catalogue
  [271424] = "Three of these make a Diver's Key, which opens the Sunken Diver's Chest on the north shore of the Coiled Isle; the chest holds a mask toy.",   -- Diver's Key Fragment
  [274481] = "Earned in the Cursed Keepsake housing scenario, more for enemies defeated over its floor pools; quest 98204 takes it, and the Cursed Keepsake vendor sells more of its decoration for 100.",   -- Keepsake Corruption
  [276547] = "Use it before you accept a Nightmare Prey hunt: the hunt goes faster and ends with an extra Preyhunter's Champion Chest. In a group, every hunter needs their own.",   -- Afflicted Soul
  [279287] = "A Vaults of Atal'Utek reward bag that can hold Venom-Cursed equipment.",   -- Corroded Pouch
  [280732] = "Hero Mistcrests pay for upgrading Hero-track gear in Midnight Season 2; the crests go to the character who opens the pack.",   -- Warbound Pack of Hero Mistcrests
}
