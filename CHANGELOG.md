# Changelog

All notable changes to Recollect are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), version numbering follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.5] - 2026-10-18

### Added

- **Pause curator recording:** `/rec curator pause` stops curator mode from recording for the rest of the session, and `/rec curator resume`, a reload or your next login starts it again. Answering the author's collections, your own flags and feedback go on while it is paused.
- **Six more of Legion's hidden artifact appearances, 104 secrets in all,** and every hidden appearance secret now completes when the game says the look is unlocked. A secret that is no longer in the game shows on its Secret tab and on the No longer available tab.
- **76 more of the game's secrets, 98 in all:** The Hivemind, the Mote of Nasz'uro, the S.E.L.F.I.E. Camera's hidden filters, the Radiant Singer, the Secrets of Azeroth clues, 20 Midnight secrets, Memory of Scholomance and its chain, Zul'Gurub's relics, Shadowlands and Battle for Azeroth secrets, and Legion's hidden artifact appearances. Every item a step gives says which step of which secret it comes from.

### Changed

- **Item details: the first section is now called Summary and says each thing once.** A key's treasure, where it is and what it leads to are one line with its map pin, the parts an item's use takes no longer list the item itself, and the opening sentence no longer repeats what the lines below say. The Checks section is gone: hover the Still needed? answer to see every check and what it found.
- **Item details: what opening a container can give has its own What's inside tab** instead of sitting under Crafting, with each item's kind and, for gear, whether you've collected its look (a toy, mount or pet shows whether you have it).
- **Secrets whose prize is a weapon's look** (Lobstmourne, Sorrowbane and the Nightwillow Cudgel) count as done once you've collected that weapon's own appearance, and the item details' 'every use is gone' line counts a secret that's no longer in the game.
- **More items say where they come from:** ensemble pieces name their ensemble, PvP vendors list their gear again, trial and boost gear says it is starting gear, treasures under rares name the treasure, cauldrons name their potions, and Darkmoon cards name their packs. Quest rewards keep their class and race, and old holiday items and vendor goods no longer claim to be from the current expansion.
- **More from curators' findings:** prices at the Haranir Metalshaper, a housing neighborhood's drink vendor and fishing supplier, a second Silvermoon cooking supplier and a Silvermoon reagent seller, who more of the Labyrinth's and Silvermoon's quests are turned in to, the two choices of The Unbinding of Kith'ix, the Mark of Honor from Something Different, more creatures that drop the Warded Key, the Ritual Gem, the Fresh Beast Heart and the Labyrinth's Stolen Artifact, which herbs and inks Inscription's milling takes, what an Artisan's Consortium Payout can give, curios from Delve chests, what the Labyrinth's treasures hold, Icecrown Citadel's trash drops, and a Harandar rare's drop.

### Fixed

- **Midnight quest items and keys the game lists under an older expansion** (the Warded Key, Handful of Sand and 23 more) now say they are from Midnight, with the patch each arrived in.
- **Raid and dungeon loot says which difficulties it drops on** ("on Mythic difficulty"), and items that come out of another item no longer also claim to drop from the boss.
- **A boss's loot is listed once** in How to get more, with the difficulty it drops on (the Libram of the Matriarch named Kith'ix twice, once without saying Mythic only).
- **Black Empire gear tokens** and the other drops of Battle for Azeroth's Assaults say which zones drop them, and Liquid Courage and Formulated Courage are no longer called replaced: they help with alchemy experiments.
- **Hallow's End candy** (Duskwood Caramel, Drustvar Choc-O-Drops) reads as a live crafting reagent of the holiday decor recipes, and Liquid Courage's details window says what it is for.
- **The item details window names each thing once:** a treasure holding two copies of one item names it once, a requirement read twice shows once, and WHAT IT'S FOR's sentence counts each purchase, quest and achievement once and no longer says no use is known beside a container's contents, a secret or the item's own Use line.
- **A potion or other item a recipe uses is no longer called Replaced;** a crafted part says which profession and recipe make it, and an upgrade sold by one vendor per faction lists both vendors.

## [1.0.4] - 2026-10-15

### Added

- **Secrets.** 22 of the game's secrets, such as the Phoenix Wishwing, Kosumoth and the Lucid Nightmare, are explained step by step in our own words. Every item, place and hidden step they involve says which secret and step it is for, your progress on each step is read live, and What it's for names the secret as a link that opens it. Items a secret still needs read Needed until their step is done. A step that takes any few of several items, such as the Incognitro felcycle's lucky items, says how many you need.
- **The Secret tab.** An item that belongs to a secret gets a Secret tab in the item details. A step list on the left has stages you can fold, a mark on every step, a search, All, To do and This item filters, and a Suggested next step at the bottom. One readable page on the right covers the step you pick: Before you start, You need (what the step takes, what you own and what you still miss), Do this, and Locations with a Set waypoint button for each place. Previous and Next walk you through the steps, every name is a link in its game color (an epic item purple, an achievement yellow), and for steps the game can't track you can tick your own checkmark. More expands or collapses every step and clears your own marks.
- **New items are never blank.** Decor now shows the housing catalog's own words for where it comes from, and gear says how the game's appearance collection lists it: a world drop, a quest reward, sold by a vendor, an achievement reward, crafted, the Trading Post, or the boss and dungeon or raid that drops it with its difficulties. Brand-new items from patch 12.1.5 show this right away, before the database knows them. It appears on the item details' Comes from tab, and on the audit panel when nothing else is known.
- **Fewer "Can't tell yet" answers.** An item only a holiday or event NPC takes, such as the Darkmoon Game Token, reads "Your call". A quest item whose quests you have all done reads "Probably done".
- **What using an item gives.** An item whose use gives you another, such as the Libram of the Matriarch and its Glyph of the Matriarch's Wings, says so, with whether you already have what it gives, and the item it gives names where it comes from.
- **More uses explained.** Drake and other mount customizations say which mount they're for, whether you've unlocked them and where they come from. Reputation items say how much and with whom, along with your standing, fishing lures name the fish they call, and armor tokens name the piece for your armor type and which classes wear the others, while each piece names the token that gives it. Soulbind conduits, garrison plans and follower or champion items say what they were for. More caches, footlockers, satchels and crates say what they hold, more recipes say what they make, and the parts of combines such as the G-99 Breakneck's turbos, the Titan Energy Cube, the War Golem Blueprint, the Universal Language Module, the Blackrock Ruby and the Kor'kron Disguise say what they combine into. The Tillers' empty containers combine with what fills them into a Bundle of Groceries.
- **Quest items.** Over a thousand quest items now say which quest needs them, with where you stand on it, and items you pick up from something during a quest say what they're found in instead of calling them the quest's reward. Many more are tied to the objective that needs them.
- **More ways to get things.** Gear and other items bought with an item, such as PvP gear for Marks of Honor and the Timeless Isle trades, say what buys them, the whole price and where. Rewards from a zone's activities and quests, from follower missions (the mission, what it costs and whether your character has those missions) and from events such as Prey hunts, garrison invasions and Ritual Sites name their source, with where you stand. Archaeology artifacts say which fragments solve them and how many you have. Items dropped by many creatures or sold by many vendors now list every one, and more items name the rares, summoned or holiday bosses, fishing, zone events and recipes the game sells or drops that they come from. Darkmoon cards and other random crafts say which recipe or pack gives them, Fleeting potions say which cauldron gives them, Hearty foods say what they're made from, Thunderforged gear names the zone it drops in, and Zul'Aman's timed-event chests list what they hold. The Griftah toy's trades and the Darkmoon jokers' cards say what each trade costs.
- **Pickpocketing and other sources.** Items you pickpocket say so, from which creature or zone, marked for Rogues, and a waypoint to that creature says what to do there. Items gathered with Herbalism from creatures, and items made by a spell, say where they come from too.
- **Ensemble pieces.** Pieces of an ensemble no longer claim the ensemble's vendor sells them: they say their look comes with the ensemble, whether you have it, and whether you've collected that piece's look.
- **What you can no longer get.** Items whose every source is gone now say they can no longer be obtained even when the patch that removed them isn't known, and so do items that never made it into the game and crafts and quest rewards that are gone, along with who they were for. A new character's starting gear says which classes or races it is given to.

### Changed

- Updated for World of Warcraft patch 12.1.5.
- **Patch 12.1.5 in the database.** What all five Silvermoon renown representatives, Estelia Archtender and the Aqir Research Enclave vendor sell and for how much, where to buy over a hundred new decor items and for how much, rewards and turn-ins of the new campaign quests, Kith'ix's drops and the Matriarch weapons' quests, the new Delve rewards, and loot from the Labyrinth of Kindo'jan's chests. Recipe reagent counts are updated for the patch, which lowered the cost of many decor recipes.
- **Follow a chain back to what you need.** How to get more walks back along the way: the Ancient Amani Mask's chest says whether you've looted it and shows the Diver's Key, the 3 fragments it's combined from and where they drop, each a link. Items that combine into a key say what its treasure holds, and the Diver's Key Fragment reads Keep it while the mask is missing and the chest isn't looted. When an item is found at a spot, the item details and the audit panel say what opens it and how many it takes, such as the Vile Essence for the Hexed Vilefeather Eagle's spot. An item you don't hold that teaches a toy, mount or pet says whether you've collected it.
- **More complete item details.** Many more containers and treasures list everything they hold (Gurubashi Tribute, the Unsealed Chest's keepsakes, the Satchels of Surplus, the archaeology crates, the Swog sacs and more), hundreds more combines and achievement rewards are known, what a placed item counts toward (Arcantina's displays) and what the Mega-Mecha parts build are named, and dozens more items name the vendors, drops, treasure spots, fishing zones and containers they come from and the quests that use them.
- **A bigger database from curators' findings.** More vendors, prices and sources, among them K'aresh's transmogrifier, food, repair and resource market vendors, the housing neighborhoods' decor specialists and lower decor prices at Om'sirik, the Arcantina and Razorwind Shores vendors' prices, more Delve chest, quest turn-in and drop sources, what the S.C.R.A.P. Scrubber Deluxe and Sifted Pile of Scrap hold, rewards from more caches (emissary and weekly caches, the Warfront weekly quests), more shared rare and treasure loot, vendors that sell the same goods as another vendor, and the Voldunai quartermaster's full prices. The Primordial Venom Mote lists every Venomous Abyss boss that drops it, the Titan Emitters and the Slumbering Dream Fragment say what they really are, and Midnight's patron crafting order rewards (knowledge, finishing reagents) say where they come from. Decor you can buy shows the vendor and the exact price the game's housing catalog lists, for about 1,900 vendor listings, and about 200 more decor items and goods name who sells them (some are best guesses that curators can correct). Darkmoon cards from Legion on name the deck they complete, the Mists Darkmoon cards name the recipes that draw them, and the Crude Effigy pieces again say they combine into the Spirit Effigy.
- **Item details.** What a key opens, and what an item combines into, teaches or makes, is named as a link when it is only one thing, and a treasure that holds up to three items links each of them. Quests for a profession you don't have now say "you don't have Alchemy", the same words the recipe lines use.
- **Curator mode records more.** From your own profession windows it can now note salvage inputs and every quality of what a recipe makes. It also notes item uses that combine several parts, where you found a treasure, where a rare or other creature stands that the database has no place for, drops from skinning and what you pickpocket, and it reports a world or zone drop for the other faction instead of ignoring it.
- **Curator mode findings are more precise, and collections send less.** Loot, quest and recipe findings take into account who can get an item and on which difficulty, a recipe counts as confirmed only when every reagent it takes matches, findings keep the zone and difficulty of the moment they were seen, and loot taken right after a boss kill counts as the boss's only when it came from the boss. A difference you already reported isn't reported again until the database changes. Findings can be compressed before they are sent, so a collection needs fewer messages; older versions keep working as before.
- Many smaller look and wording improvements, such as thousands separators in large counts (1,000 Vile Essence) and What it's for no longer repeating an item's own description.
- Performance improvements.

### Fixed

- **Wrong facts removed.** Recollect no longer says an item is from Classic when it came later; such items say they are from an older expansion. Housing decor sellers no longer show as drops, and neither do Brazie's Black Book of Secrets and two of Andorov's plans, which are sold. Items inside a bag, box or token a vendor sells, and items a vendor only takes in trade, no longer claim the vendor sells them; garrison mission loot no longer claims to drop from the Command Table; some items no longer claim to be found in objects that don't exist; and a quest item no longer says it comes from the quest it starts. Items bought with any one of several tokens (the Venthyr anima spherules) list each price apart instead of adding them up.
- **Fairer answers for older items.** A recipe that can no longer be learned, a part of a combine that is gone, and an event item whose every use is gone no longer say Keep it. An item that teaches a mount, toy, pet or ensemble no longer says every use is gone when only its old quest or vendor left the game. Older trade goods you can use themselves (fish you can eat, clams you can open, seeds to plant) no longer read Replaced just because none of your recipes use them, and pet-battle food reads Your call instead of Replaced.
- **Another character's copy in the item details window describes that character.** An achievement reward no longer shows your own progress unless it is earned or account-wide, and the Rewards and Leads to columns and the Overview's reward lines no longer judge a recipe reward by your own spellbook.
- **Item details:** a quest whose name the game never sends now reads "name unavailable" and "Can't be read" after about 20 seconds, instead of "name not loaded" and "Checking" for good. A part a quest gives names that quest instead of saying no way to get it is recorded yet, an item that can no longer be obtained still says so beside what it holds, and the Crafting tab's number counts only recipes, so it matches the recipe count in What it's for.
- Several smaller bug fixes.

## [1.0.3] - 2026-10-11

### Added

- **Other addons by the same author.** `/rec addons` lists every addon Cobanyte has released, the same list in each of them: what it does, pictures you can click to see bigger, and its CurseForge link to copy into your browser. Addons you already have are marked. It only opens when you ask, and the guide's last section points to it. The list remembers its size and where you left it.
- **Reset windows.** `/rec reset windows` puts every window back to its default place and size after you confirm; your settings are not touched.
- **Where more things come from.** Disenchanting results, skins and scales, herbs, ores and other gathering yields now name the profession action that gives them, and skins name the creatures they were skinned from. Spark of Tides reads as a seasonal drop from the season's dungeons and raids instead of one boss's loot, and the Concealed Catalogue says it drops only on Mythic or Mythic Keystone. Every Timewalking vendor now lists its goods with their badge prices, guild vendors and the Siege of Orgrimmar raid vendors show what they sell, pet supply bags list what's inside, and many holiday quests show what they give. Two quests the game calls daily no longer read as weekly, and about 30 more items say what they're for.
- **Delve rewards and other qualities.** Items a Delve gives when you complete it now say so in Comes from (a "Delve reward" row), such as Star-in-a-Jar and the gear Delves hand out. An item that comes in several qualities, or has a twin of the same name (Fused Vitality is bought with two different currencies), now lists its other qualities in Comes from, each with its own tooltip and link.
- **How mounts, pets and toys are obtained.** Far more mounts, pets and toys now say where they come from: the in-game shop, a promotion, a Trading Card Game loot card or a Recruit-A-Friend reward each get their own row in Comes from, and more of them name the Trading Post, the achievement that rewards them, the creature that drops them, the container they come out of or the zone where they're fished. The Comes from tab of any mount or pet also shows the mount or pet journal's own words for where it comes from.
- **Newer version notice.** When someone in your guild or group has a newer version of Recollect, one line in chat says which version is out and which one you have. Your copy shares its version with them quietly, so they hear about a newer one from you too. On by default; turn it off with "Tell me when a newer version is out" in `/rec settings` (Audit panel).

### Changed

- **Still needed? answers far more items.** Novelties such as pet treats that change a pet's size, fireworks and disguises now read "Just for fun". Items for pet battles, older items with a use, and tokens that only buy things you can still buy read "Your call". Older stat scrolls and stat boosts read "Replaced". The Hearthstone reads "Keep it". Recipes in your bank and warband bank are checked too. None of these answers ever says an item is safe to delete.
- **A bigger database.** Brewfest brew and food prices, Delve mount prices in Silvermoon, the Hearty Food recipes and what they make, the flawless battle-stones in pet supply bags, about 20 more recipes, the Darkmoon Faire's draughts and tinctures, Ride Ticket Books and what they hold, the Timewalking coin from Scholomance's last boss, the Coiled Isle's daily fishing quests, where fish are caught in Silvermoon City, Fused Vitality from more professions' weekly quests, the Fortify the Runestones quests that use Latent Arcana, and a few more quest turn-ins, choice rewards, drops and NPC places.
- **Item descriptions.** About 400 more items, many of them consumables, now say in a sentence or two what they are and how you use them.
- **Curator mode.** While it is on, when the author checks who is online, your game also says which zone you are in and whether you are in a dungeon, raid, delve, battleground, arena or other instance, so a collection never starts by itself while you are in one (a house or neighborhood does not hold it back). With curator mode off, none of this is sent. The settings page says so.

### Fixed

- **Quests for a profession you don't have.** In Comes from and How to get more, the "Needs Alchemy" style quests now come after the ones you can do or have done.
- **Done quests look done.** A quest you have done now shows the green check, a weekly or daily you finished this week or today included, and only a quest you haven't done shows the red cross.
- **Your professions.** Recipe, crafted-by and reagent lines say "you don't have Tailoring" when your character doesn't have that profession.
- **Achievement items on your other characters.** An alt's item that counts toward an achievement no longer reads Needed, or done, from the character you're logged in on. Unless the achievement is account-wide, its progress is per character, so Recollect says it can be checked fully only on that alt. An earned achievement still counts for every character.
- **Past-season sparks and other crafting materials.** "You have every appearance of the gear it makes" now needs each crafted piece's own tooltip to agree that its look is collected; when one can't be confirmed, the item reads Can't tell instead of Outdated.
- **Item details.** A gear purchase says "Look collected" or "Look not collected" only when the item's own tooltip agrees. A recipe whose product is still loading no longer lands under the "Already have or done" or "Still to get or do" filter. New uses found while the window is open (a profession scan, the mount and pet journals finishing their read, a new endeavor task) now show up without reopening it. A quest link that loads late no longer replaces a tooltip you opened after clicking it. What it's for no longer says what an item is twice ("A consumable from Classic" on two lines).
- **Audit panel.** Hovering two rows of the same item in the item list one right after the other shows the second row's own answer and location, not the first one's.
- **Curator mode.** When the author stops a collection before you answer the review prompt, the prompt now goes away instead of waiting for an answer.

## [1.0.2] - 2026-10-06

### Changed

- **A bigger database.** A few fishing zones, what some containers hold, who takes in a few quests, and about 50 more item descriptions and guide notes.
- **Item details.** The Still needed? band gives a short answer ("Keep it: Leads to Phoenix Wishwing, a pet you don't have"), and What it's for gives the full explanation, so the two no longer say the same thing.
- **Item details.** The No longer available tab has a For column, so a removed way for one faction no longer looks like a duplicate.
- **Guide.** It names the keys you actually set, and when the panel or a key is off, says where to turn it on instead of naming a key that does nothing.
- **Settings:** the Cancel button is now **Undo edits**, with the same job: it drops changes you have not applied.
- Performance improvements.
- Many smaller look and wording improvements across the windows.

### Fixed

- **Item details.** Hovering a cell cut short ("Leads to a...") shows its whole text.
- Several smaller bug fixes.

## [1.0.1] - 2026-10-01

A bigger database, a new look for the settings, and clearer item details.

### Added

- **Just for fun.** On English clients, a roleplay drink such as an old ale now answers "Just for fun" instead of "Can't tell yet" once nothing Recollect checks still needs it.

### Changed

- **A bigger database.** Many more items now say where they come from, and quest-chain rewards say how the chain starts.

- **Old ales and wines are no longer Outdated** on English clients; they read Can't tell.

- **Done shows as done.** An earned achievement or a finished part of one is now green with a check mark wherever its check is named: the details window's Still needed? band and Checks list, and the audit panel.

- **New look for the settings.** Four pages, with an example of the panel, when each bank was last read, key-clash warnings and clearer curator controls.

- **Clearer linked achievement lines.** An item linked to a part of an achievement now reads "Linked to a part that's done" (or "not done yet") wherever the details window and the audit panel list it.

- **Quest-chain rewards.** For a collectible a quest rewards, item details list the recorded quests, who starts them and what they ask for; the audit panel says how the chain starts.

- **Curator dashboard tiles.** The numbers on the curator dashboard's Overview (what waits to be sent, what the author saved, each kind of finding) now use the same tiles as the settings window, and wrap to fewer per line in a narrow window.

- **Easier to read small windows.** The window that asks you to open the achievements window (Show Achievement in the item details window) and curator mode's windows (stopping curator mode, adding a character to the community, and a collection being sent or asked for) now use larger text, and grow to fit it.

- **Item details say things once.** Why you'd keep an item is no longer repeated in What it's for and Checks, and a single kind of source reads plainly ("1 way to get it: a drop").

### Fixed

- Item details no longer write "at A vendor" mid-sentence, "Buys: Buys", or two parentheses in a row.

- The Still needed? band no longer puts a stray semicolon between an achievement's name and its progress.

- Hovering the Still needed? band no longer drops the achievement's name from the reason, and no longer repeats a reason the band already says.

- An item's What it's for no longer shows the same sentence twice, under its heading and again in the section.

- Clicking a quest in the item details window whose details hadn't loaded yet showed only its title; it now shows them once they arrive.

- The audit panel's Still needed? line now always gives the same answer as the item details window: an item whose uses are all done reads Probably done (or Likely safe to delete) in both, never Can't tell yet in the panel.

- The audit panel beside an item shown outside your bags could say "Not in your bags" at the top while saying how many you have just below it; it now says "Shown elsewhere".

- A profession tool or accessory no longer says your slot is empty (and to equip it) when the game didn't say what you have equipped there; it says it can't tell.

- A crafting material from a past season is no longer called Outdated before Recollect knows whether everything it makes is gear: a product the game hasn't loaded yet is counted as not read.

- Right after you log in, an item is no longer called Useful because a quest chain looks open before your quest history has loaded; it waits for it.

- Curator mode: flags and feedback the author turned down aren't sent again unless you change them.

- Curator mode: after a database update, findings the author already received stay separate from new ones and aren't sent again.

- Stopping curator mode offered to delete "my findings (0)" when every finding left was from an older database; the count now includes those, since they're deleted too.

## [1.0.0] - 2026-10-01

The first release of Recollect: what every item in your bags, bank and warband bank is for, and whether you still need it.

### Added

- **A verdict on every item you hold.** Needed, Use now, Useful, Can't tell, Junk, Outdated, Lower level or Purpose done, always with the reason. Recollect never decides for you: a suggestion such as "most likely safe to sell or delete, but that's your call" comes with why.

- **The audit panel.** Hover an item and hold **Alt** (or Shift, Ctrl, or always, in the settings): beside the tooltip, a short summary of the verdict, the uses that matter most and where you stand on each, where the item comes from, and a Tip when one applies. On an item you don't hold, such as a chat link, loot or a vendor's goods, it shows how many you have instead.

- **The item details window.** **Alt+D** while the panel shows, or a click on a row of the Recollect Audit, opens everything Recollect knows about one item, so you don't need a website: what it's for, the achievements it counts toward with progress bars, every way to get more with the whole price and what buying requires first, guide notes, your counts on every character, and every check Recollect ran. Tabs list its purchases, quests, crafting, sources and requirements in sortable, searchable tables; names work as they do in chat, Alt-click opens another item here, and right-click links it, previews it, sets a waypoint or copies its Wowhead link. The key can be a click instead, such as Alt+click, which works on any item, even in combat.

- **The Recollect Audit.** `/rec` or the minimap button lists every stack you hold with its verdict, counted at the top. Search it, filter it by verdict, place, use or why Recollect can't tell, and switch between this character with the warband bank, all your characters, or one of your others as of their last login.

- **Waypoints.** **Alt+W** while the panel names a vendor, treasure or NPC sets a waypoint to it: a TomTom arrow when TomTom is installed, naming the NPC and why you're going, else the game's map pin.

- **A database built for players.** Vendors and their whole prices (items, currencies and gold), drops from creatures, bosses and zones, quest rewards and quest items, recipes and their reagents, treasures and keys, combines, renown rewards, the Black Market and the Trading Post, meta achievements, and when items were added or removed from the game. Names are read live from the game in your language.

- **Curator mode (optional, Americas and Oceania region).** Off by default. Curators help keep the database right: while it's on, Recollect notes where the game disagrees with its database or shows something it lacks, such as a vendor's price, a drop or where an NPC stands, and hands only those findings to the author's own characters, in small parts. It records game IDs and positions with your character's class, race, level, faction, professions and zone, never names, chat, gold or what you carry. `/rec curator` opens the curator dashboard, and **Curator Flag** in the details window reports a problem with an item in your own words.

- **Settings, a guide and a changelog.** `/rec settings` (also a right-click on the minimap button or Options > AddOns), `/rec guide`, which opens by itself on your first login, and `/rec changelog`.

[Unreleased]: https://github.com/HackyThings/CobySuite-Recollect/compare/v1.0.5...HEAD
[1.0.5]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v1.0.5
[1.0.4]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v1.0.4
[1.0.3]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v1.0.3
[1.0.2]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v1.0.2
[1.0.1]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v1.0.1
[1.0.0]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v1.0.0
