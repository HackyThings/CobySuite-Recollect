# Changelog

All notable changes to Recollect are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), version numbering follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.3] - 2026-09-30

### Changed

- **More items say where they come from.** Midnight delve reward chests now show what curators found in them: the Bountiful Coffer's Drum of Renewed Bonds and Galerider's Mail Skirt, and the Bountiful Heavy Trunk's Pyrewalker's Mantle and Amani Blueflame Chandelier. The Apex Cache shows as a reward of the Vaults of Atal'Utek weekly, and Phaseblade's Edges and Phasebolt Thrower as drops of Nexus-Captain Leth'ir, Naigtal's world boss.

- **Every quality rank of a crafted consumable says how it's made.** Rank 1 potions, flasks and runes used to show nothing while rank 2 named its recipe: Potion of Recklessness, Light's Potential, Flask of the Magisters, Concentrated Silvermoon Health Potion, Vantus Rune: Tides and Algari Mana Oil now all do. The Hearty foods (Hearty Spiced Biscuits, Champion's Bento, Felberry Figs and Sun-Seared Lumifin) name Cooking's Hearty Food recipe.

- **The Shadowlands conduits that Sanctum of Domination and Sepulcher of the First Ones bosses drop are marked Evoker only,** so other classes no longer see those drops as meant for them.

- **Curators: places and a vendor already confirmed aren't recorded again.** 17 NPC places and Silvermoon's crest bundle vendor are settled, so curator mode stops sending the same confirmation for them; a curator who finds one of them somewhere else still reports it.

### Fixed

- **Curators: a database update no longer sends the same items again.** Items Recollect knows nothing about yet were handed over once, then sent again after every database update, so the Waiting to be sent count came back after the author collected. Once the author has an item, it isn't sent again.

## [0.0.2b] - 2026-09-30

### Changed

- **More boss loot from Shadowlands raids.** Recollect now knows what the bosses of Sanctum of Domination and Sepulcher of the First Ones drop beyond their Encounter Journal loot, as seen in game: Ancient Anima Vessel and Anima Webbing from every boss, the Evoker conduits (Spark of Savagery, Circle of Life and others), Genesis Mote from Skolex and Lihuvim, Kel'Thuzad's Phylactery Shard and Anduin's Mourne Fragment. Each shows under "How to get more" with the boss and its raid.

### Fixed

- **Resizing a window no longer makes it jump to full screen.** Dragging a window's corner past the edge of the screen could grow it to its largest size in an instant, with the corner off the screen so it couldn't be made smaller again. A window's corner now stops at the screen's edges, and a window saved too big opens fitted to the screen.

- **Curators: nothing stays waiting after a collection.** Findings recorded before 0.0.2a stayed in the curator dashboard's Waiting to be sent count after every collection, because they were too large to hand over in the new format. The author already has them from earlier collections, so they're now cleared when you log in. Findings saved under an older database are handed over in the same collection as your newest ones, so the count drops to 0 once the author collects, and a database update no longer puts findings the author already has back in the count.

## [0.0.2a] - 2026-09-30

### Changed

- **Waypoints say who is there and why you're going.** A TomTom arrow's title names the NPC and the errand, such as "use Forgotten Trinket here", "sells ...", "drops ...", "open it with ..." or "starts (quest)", instead of just "the NPC". The panel's waypoint hint and the chat line after setting one name the NPC too, once the game has read its name.

- **Prices name what you pay with.** A purchase used to read "Phoenix Ash Talisman for 1 plus 20 Apexis Crystal", leaving you to guess what the 1 was; it now reads "Phoenix Ash Talisman for 1 Phoenix Feather and 20 Apexis Crystal". The same goes for the audit panel's reasons ("Buys Phoenix Ash Talisman (for 1 Phoenix Feather and other costs), which leads to ..."), USED FOR in the details window, and the Cost column's hover list.

- **"How to get more" says something useful when Recollect doesn't know the source yet.** Instead of only the season line, it says that no source is recorded yet and what the item's binding means for getting another: whether another player can trade it to you or it may be on the Auction House, or whether only its source can give it. Curators also see a reminder to press Request info.

- **Checkmarks and crosses show what's done at a glance.** In the item details window and the audit panel, a line or row that's done, earned, collected, known or looted shows a green check; one still to get or do shows a red cross; one out of reach for this character a gray cross; one the game can't read yet a pending mark, and one it can't read at all a warning sign. The icons are the game's own and sized to the text beside them.

- **Curator mode is available only in the Americas and Oceania game region**, where the author plays: curators and the author have to reach each other in game. Elsewhere the settings still explain curator mode and say why it's unavailable, with its options grayed out; any findings already saved are kept as they are, and nothing is recorded or sent. Everything else in Recollect works everywhere.

- **Curators: a new, safer way to hand findings over.** Curator mode now talks to Recollect's author in a new format, and a curator's client hands findings only to the author's own characters, never to anyone else who happens to lead the community. Findings go in smaller parts, one after another, so no single transfer is large. Curators on 0.0.2 or older have to update before the author can collect again; findings recorded before the update are kept and handed over too.

- **Curators: the connection test answers only the author.** Your client replies to the curator connection test (`/rec curator ping`) only when the author runs it, and no longer joins the test's chat channel by itself when you log in.

### Removed

- **The prompt to leave the old curator chat channel.** Curator messages have gone by whisper since 0.0.1d; if a character is still in the old RecollectCurators channel, type `/leave RecollectCurators`.

### Fixed

- **A meta achievement you've earned now shows "(earned)" in green** in the item details window, like the achievements listed above it (it was gray).
- **Curators: a collection the author turned down or kept for a closer look now says so** in the dashboard's History, and findings he turned down no longer show as waiting.
- **Curators: the flag window shows when the author saved a flag**, not when you wrote it.
- **Curators: the connection test says it needs the author's test session**, and its encoding check no longer reports a problem that isn't there.
- **Curators: `/rec feedback` outside the Americas and Oceania region explains why feedback isn't available**, instead of telling you to turn curator mode on.
- **Chat lines from curator mode no longer say "Recollect" twice.**
- **The feature guide names your own keys** when you've changed the panel, details or waypoint key, instead of always saying Alt, Alt+D and Alt+W.
- **A purchase that's no longer in the game names what was paid**, like the rest ("Bought X for 5 Apexis Crystal").
- **A gray junk item is no longer described as worth gold**, and a spot with no known place is no longer called a treasure.
- **Hovering an NPC promises a waypoint only when Recollect knows where it is.**
- **The audit panel says what it hasn't checked in plain words** ("not checked yet: whether a recipe uses it and whether a quest needs it") instead of internal labels, and a reason that repeats its headline is shown once.
- **Counts and plurals read right with one of something** ("1 more depends", "which you own", "Teaches an Alchemy recipe", "an heirloom"), and "How many you have" no longer lists places holding none.
- **Curators with a long list of collections waiting for the author's confirmation** could still look offline to the author: the reply could come out two characters too long to send. It now always fits.

## [0.0.2] - 2026-09-29

### Added

- **Items bought with a currency now show the price:** "Sold by X for 350 Honor", or "Sold by X, 5 for 350 Honor and 10 gold" when one purchase gives several, for thousands of items sold for Honor, Conquest, Timewarped Badges, Trader's Tender and other currencies. Curators' currency prices are now compared with the database like gold prices: a matching price confirms it, and a different one is reported.

### Changed

- **Weapon oils and sharpening stones from an older expansion now read Outdated**, like older potions and flasks: each expansion makes new ones. English clients only, since the check reads the item's Use line.
- **Curator mode stops reporting what the author already checked.** A finding the author looked into and turned down (an NPC that walks, a vendor that rides on another player's mount such as the Mighty Caravan Brutosaur's) is no longer recorded or sent.
- **Curator mode sends less over time.** Each account confirms once that a vendor's (or other place's) listing matches the database, and once enough curators have confirmed a place, nobody sends a match for it again. Differences are always sent, and when one turns up, everyone may confirm that place once more.

### Fixed

- **Curators with many collections waiting for the author's confirmation** could look offline to the author: their reply grew too long to send. It now sends what fits and the rest in the next reply.
- **A collection keeps going to the author's character that asked for it**, even when the author checks in from another character meanwhile.
- **Findings the author never confirmed within 30 days** are sent again in the next collection instead of being treated as delivered.
- **Items with no information** are noted again after a database update even when nothing else was waiting to be sent.
- **Curators no longer report loot the database already explains:** a world drop looted from a boss, or an item any enemy of a zone can drop looted in that zone, is no longer reported as that enemy's own drop, and a bag opened right after disenchanting is no longer taken for a disenchant.
- **Fewer false reports from curators:** a vendor someone summons or brings along (Jeeves, an Argent Squire), a holiday vendor's goods out of season, a tabard handed out again for free, a currency gained at its cap or from a craft, a world quest's reward (it changes each time the quest is up), the Trading Post item you kept from an earlier month, food eaten while learning a recipe at a trainer, and a quest giver standing where its quest starts are no longer reported.
- **Fewer false reports from curators about places:** an NPC found in several spots, a quest offered by several NPCs, a boss's loot chest, a treasure's other spawns and a boss's other forms now match what the database has, so curators no longer report them as wrong or new.
- **Curators with a reputation discount at a vendor** no longer report that vendor's prices as different from the database's: a price 5 to 20% below it counts as the same price.
- **The curator dashboard's Findings search** finds a creature or item by its name once the game has loaded that name, not only by the name it had when the list was built.
- **The curator connection test** (`/rec curator ping`) now answers only members of the curator community, replies the same way the test reached it, and runs one test at a time per character.

## [0.0.1d] - 2026-09-28

### Added

- **Curator dashboard:** `/rec curator` now opens a window for curators. **Overview** starts with one line saying whether curator mode is recording (or why not, such as combat) and three numbers: what waits to be sent, what the author has saved so far, and when the last collection was. Anything you should know or fix comes next, such as a character outside the community (with a Join button); then what waits, by kind, against the 1 MB limit, and the last few collections. The connection to the author, the lines `/rec curator diag` prints and what gets recorded are folded away at the bottom. **Findings** lists everything you recorded in a table you can sort, search and filter: what kind of finding it is, what you saw next to what the database says, and whether it's waiting, sent or saved; hover a row for all of it. **History** lists every collection the author asks for from now on: when, which of the author's characters, what it held and how it went. The bottom of the window has the curator settings, feedback, "Ask me before each collection" and a button to turn curator mode off. `/rec curator status` prints the one-line status the command showed before.
- **Items with no information:** with curator mode on, Recollect notes items its database knows nothing about, from your bags, bank and warband bank, loot, vendors and quests, so the author can look into them. Only the item and where you saw it are kept, never how many you have, your currencies or gold. Curators who turned curator mode on before this version see a one-time chat line before their bags and banks are included. On such an item the details window's Curator Flag reads **Request info**, with Missing info already chosen. The curator dashboard counts them in a **No info** tile.
- **Want to be a curator?** With curator mode off, the item details window shows this button where curators see Curator Flag. Hover it for what curator mode does; click it to open the Curator settings.
- **Achievement button:** achievement rows in the item details window's tables have a small achievement icon in the Map column. One click opens the game's achievement window at that achievement.

### Changed

- **Windows no longer stay on top of the game's own windows.** Recollect's windows now sit with the game's panels: clicking any window brings it to the front, and a window opens in front. Only questions that need an answer, such as confirmations, stay above everything.
- **Curator mode no longer uses a hidden chat channel.** Everything it sends is now a hidden whisper, which reaches every realm and takes none of your chat channel slots. A character still in the old RecollectCurators channel is asked once, after login, whether to leave it; **Leave channel** leaves that channel and no other. `/rec curator channel` is no longer needed.
- **Show Achievement** (the item details window's right-click menu on an achievement) goes straight to the achievement when the achievement window is already open. When it's closed, a small window asks you to click **Open achievements**, which opens it the way the game's own button does, and Recollect then shows the achievement there. Opening that window from the addon itself could get the game to blame Recollect for blocked actions later. In combat it waits until combat ends.
- **What it's for tiles** now say what their numbers mean in each kind's own words ("Achievements: not earned yet", "Crafting: 79 make things you lack"), and every tile in the item details window has a tooltip with the breakdown.

### Fixed

- **Blocked-action errors after opening the settings from the game's menu:** pressing **Open Settings** on the Recollect page under Options > AddOns brought the game menu back behind the settings window, and the game blamed Recollect for SpellStopCasting, SpellStopTargeting and an unnamed protected action ("Recollect has been blocked from an action only available to the Blizzard UI"). The button now just closes Options and opens the settings window.
- **Right-click on names in the item details window's Overview** opens the same menu the tables do (it opened nothing before).

## [0.0.1c] - 2026-09-28

### Added

- **Curator connection test:** `/rec curator transport Name-Realm` (or `/rec curator ping`) tests every way Recollect can reach that player and reports which work and how much each carries. A route counts as working only when that player answered, not whoever else happened to be online.

### Fixed

- **Curators on other realms:** curator mode now reaches curators whose realm isn't connected to the author's. Recollect had only used whispers within a realm group and sent everything else on a chat channel that stops there; whispers reach across realms, so collections go by whisper.

## [0.0.1b] - 2026-09-28

### Added

- **Curators on an alt:** the first time you log in on a character that isn't in the Recollect Curators community, a small window asks whether to add it. Join puts the invite link in chat; No thanks is fine too, since what you record there is still collected through your characters in the community, and that character isn't asked again.
- **Still needed?:** the item details window opens with an answer band across its full width, on every tab: an icon (a check mark when you're likely done with the item, a coin for junk, a lock to keep it), Recollect's suggestion (Keep it, Sell it, Likely safe to delete, Probably done, Replaced, Lower level or Can't tell yet) and a short reason why, tinted in the answer's color. Hover it for the whole reason and the Tip. It only ever suggests; it's always your call. Items known to stay in your bags after their use is done are marked in the database, so once every use is done they read as likely safe to delete. For an item you aren't holding, the band says how many you have and where.
- **Shift-click anything into chat:** in the item details window, Shift-click links any item, achievement, quest, currency or recipe in chat, and an NPC or a treasure spot goes in as its name, zone and coordinates with a map pin anyone can click. Quests open their tooltip on a click even before the game has loaded them; a quest the game can't link yet goes in as its name, so the message always sends.
- **NPCs and treasure spots are links:** in the item details window, an NPC's or a spot's name can be hovered (what Recollect knows of it: a boss and its dungeon, how many items a vendor sells, what a treasure holds, where it is) and clicked or right-clicked for a waypoint and its Wowhead link.
- **Recollect Audit tabs:** tabs along the bottom: My Items (you and the warband bank), All Characters, and one per character Recollect has stored. "Include your other characters" is now on by default (turned on once for everyone who had it off).
- **TomTom waypoints:** with TomTom installed, waypoints (the waypoint key, the map buttons and the right-click menu) go to TomTom's arrow; the new Waypoints setting can send them to the game's map pin instead. In the item details menu you can pick either each time.
- **What buying something requires:** items sold by vendors say what you need first: achievements with your progress ("Requires the achievements Void Response Team (3 of 5 done) and Ritual Site Disruptor (earned)"), a renown level, a reputation standing, or a quest to finish. The item details window's rows show the same, dimmed until you meet them.
- **Copy Wowhead link:** right-click an item, quest, NPC, achievement, currency, recipe, treasure or faction in the item details window (a table row or a name in the Overview) and pick Copy Wowhead link. The link appears selected in a small box; press Ctrl+C and it closes.

### Changed

- **Curators:** findings you haven't sent yet are kept when Recollect or its database updates, labelled with the version they were recorded under, and go out with your next collections. Before, an update deleted them.
- **Items that buy class gear:** when everything an item buys is for other classes, the reason names those classes and says nothing for yours is recorded yet ("Buys 5 things, all Hunter, Shaman and Evoker only; none recorded yet for Paladin"), instead of only "for another class". A raid curio, for example, trades for your own armor type's token at its vendor, and Recollect's data so far holds only what that vendor showed a mail wearer.
- **The audit panel is a short summary:** holding Alt over an item shows the verdict and its reason, the few uses that matter most, where the item comes from, and the keys. Everything an item buys is one line, such as "Buys 4 decor and 2 pets you don't have". When something was left out, the details key's line says "for everything": the item details window still shows every use, every check and what kind of item it is.
- **Right-click menus:** the item details window's right-click menu is the game's own menu, at the mouse, titled with what you clicked, in sections: open, link or preview it (an achievement also has Show Achievement, which opens the achievement window right at it), set a waypoint, and copy its Wowhead link or name.
- **Guide notes:** the short notes for items no game data explains are labeled "Guide note" (and whether they're confirmed in game) instead of naming a website.
- **PvP gear:** the item details window says when an item is PvP gear and the item level it counts as in Arenas and Battlegrounds, and gear, recipes, gems and other items whose use is plain from what they are no longer read "Recollect knows no use for it yet".
- **Treasures say what they hold:** a key's line names what the treasure holds ("Opens a treasure in Zul'Aman, which holds Amani War Axe", or "which can hold any of 12 items"), and What it's for spells out the treasure, where it is, whether you've looted it and the other parts opening it takes.
- **Recollect Audit, clearer:** it says what it's for at the top and counts your stacks by verdict in their colors; each column title explains itself when you hover it ("Purpose" is now "Checks", "As of" is now "Last read"); the filter menu is grouped under Verdict, Where it is, Uses, and Why Recollect can't tell, each verdict in its color with what it means on hover; and an empty list says why (nothing read yet, nothing on that character, or nothing matching your search and filters).
- **Settings:** the window can be made bigger by dragging its bottom-right corner and remembers its size, and its sections sit closer together. The Tooltips category is now two groups: when the audit panel shows, and the keys it offers, each key under its checkbox. The categories are called Tooltips and Recollect Audit, and a Guide button opens the feature guide.
- **Item details, easier to scan:** in the Overview, each group inside a section ("Buys", "Quests and places", "Crafting with it", a reagent's recipes) now has a white title with space above it, and every section's lines sit at the same indent.
- **What it's for explains the item:** the section opens by saying what the item is, where it's from, how it's made and what it's used for ("Worn in one of your two ring slots, from Midnight. Crafted with Jewelcrafting. It counts toward 1 achievement and is used at 1 place."), with the game's own filing of it under that. Gems, keys, holiday items, caged battle pets and other kinds that said nothing before now get their own words. The item's own Use line is quoted under that explanation, so you don't have to hover it, and for items whose Use line leaves you guessing, a sentence or two says what it's really for.
- **Achievements, a section of their own:** the achievements an item counts toward are listed apart from quests and places, with the meta achievements they are part of and your progress on each.
- **What crafting takes moved to How to get more:** the reagents a recipe needs to make the item are listed under How to get more ("What crafting it takes"), not under What it's for.
- **Item details header:** redesigned: the window is titled "Item Details", the item's icon sits in a frame of its quality's color, and under the name one quiet line says what the item is ("Worn in one of your two ring slots · Midnight · PvP gear"). The item's name no longer has "Bags" or "Linked item" beside it.
- **At a glance:** What it's for and How to get more open with a row of tiles, one per kind (Buys, Quests, Achievements, Crafting; Sold by, Drops from, Reward), each with its count and how many are still open, and every achievement and meta achievement has a progress bar under it.
- **What you have:** shown as tiles, one per place (Bags, Worn, Bank, Warband bank), each with its icon and its count, places with none dimmed, and, with "Include your other characters" on, an Other characters tile with their total. Hover a tile to see exactly where: which bag, each bank or warband tab by its own name ("Bank tab 1 (Mats): 3") with when it was last read, or each of your other characters with their bags and bank. The section's summary names only the places that hold the item, and your other characters that hold it are listed too, as last seen.
- **Item details tables:** the last column fills the rest of the table and has no divider to drag, and the Map button sits beside the place it points to. The filter menu names each kind in full ("Recipes that use it", "Vendors that sell it", "Not for this character").

### Fixed

- The minimap button sits just outside the minimap's edge again, and follows it when Edit Mode resizes the minimap; on the larger minimap it had been stuck inside the map.
- **Crafted items of several qualities:** every quality now shows the recipe that crafts it, not just one.
- **Milling, prospecting and other salvage:** the herbs, ore and other items a salvage recipe takes now show that recipe as a use.
- **Item details tables:** dragging a divider on a table whose columns already fill the window widens that column again (the others give way), instead of doing nothing or making it narrower. A column you widened keeps its width when you open another item.
- **What it takes tab:** the Others and Status columns show their values (they were empty), and Others sorts when clicked. The No longer available tab opens sorted by name.
- **Resizing Recollect's windows:** dragging the corner no longer makes a window jump bigger than where the cursor is, and a column drag always ends when you let go.

## [0.0.1a] - 2026-09-28

### Added

- **Curator check:** `/rec curator diag` prints what your game sees of curator mode (the community, its channel, who can collect, the messages that arrived, and why the last one went unanswered), and the debug log (`/rec debug`, Copy All) records each step, so a curator can send it to the author.

### Changed

- **Database:** added 17 Inscription glyph recipes that were missing (Glyph of Shackle Undead and others), so their parchment and inks now say which glyphs they make. Fused Vitality now shows as a reward of the Tailoring weekly quest.

### Fixed

- **Curator collections from a friend's game:** a curator whose game didn't know the author's character yet ignored every request from the author. It now reads the name from the community list, and reads the list again when a message arrives from someone it doesn't know yet.
- **Curator collections between two players:** the game never passed curator messages between players over the community's chat channel, so the author could only reach their own game. Curator mode now whispers the author directly once the author has been in touch, and otherwise uses a hidden channel that it joins by itself and that never shows in your chat. `/rec curator channel` joins it again if it ever can't (for example when every chat channel slot is in use).
- **Curator findings:** salvage recipes such as Milling are no longer reported as missing from the database.

## [0.0.1] - 2026-09-27

### Added

- **A verdict for every item you hold:** Needed, Use now, Useful, Can't tell, Junk, Outdated, Lower level or Purpose done, with the facts behind it. Junk is the game's own label for gray items with a vendor price, and its reason says what junk is. This covers your bags, your bank and the warband bank, which is remembered from your last visit.
- **The audit panel:** hold Alt over any item to see its audit beside the tooltip. It shows the verdict (or, when Recollect can't tell, what the item is for), what the item is used for, what kind of item it is and its expansion, and every check that looked at it. It works on chat links, vendors, loot, quest rewards and the auction house too. An item you are not holding gets the facts and how many you have.
- **USED FOR:** what an item is used for, with where you stand. What you still need comes first and what you have already done comes last, so a long list never hides what is left:
  - the quest whose objective it is, whether you're on it or have done it, and what it rewards;
  - the achievement it counts toward, and your progress;
  - what it buys and from which vendor (mounts, pets, toys, housing decor, ensembles, heirlooms, recipes and other items), and whether you have them;
  - the quests that use it, or that you hand it in to;
  - what a key opens: where, what the treasure holds, and whether you have looted it;
  - the NPC it is used at;
  - what it combines into, and whether you have that yet;
  - the recipe it teaches, and whether you know it;
  - the currency it names, and the vendor that takes it;
  - the recipes whose reagent it is, by profession;
  - what your other characters' recipe scans recorded using it ("Tanklite's Leatherworking scan (Sep 24) recorded 9 recipes using this").
  - Holiday, daily and weekly quests are known to come back, so an item for a yearly quest you've already done still reads as useful.
  - A purchase, quest or source only for the other faction, other classes or other races says so ("Horde only", "Paladin only", "Blood Elf only"), is grayed out in the panel and the item details window alike, and is never counted as something you still need; one offered only during a holiday or event says "During a holiday or event" on every character, and counts as before. One that is no longer in the game is left out of the panel and the list, and shown only in the pinned details as no longer obtainable.
- **Item details window:** press Alt+D while the panel shows, or click a row of the Recollect Audit, to open everything about an item in its own window. The pin key in `/rec settings` can be a click instead, such as Alt+Left Click: that click opens any item, in your bags or bank, a chat link, loot or a vendor's, even in combat. Anything you look at there has a table, so no website is needed:
  - an Overview that answers what it is, what it's for (and how many that takes), how to get more and where, and what you have;
  - a tab for each kind of use: what it buys, quests and achievements, crafting, where it comes from, what a use takes, and what is no longer available, each with its count;
  - every table has icons and item names in their colors, sorts by any column (ties go A to Z), opens with its columns fitted to what it shows (a column you drag keeps its width for every item, and double-clicking a divider fits that column to its contents), and has a search box and a filter for what you still need, what you have, or one kind;
  - a reagent says which professions use it and in how many recipes; a crafted item says which profession makes it and lists its reagents with how many you have;
  - ensembles, pets and recipes that an item buys show as the items you'd get, with their icons, tooltips and links;
  - quests say where they start and who gives them, with a Map button, and what is no longer available says where it was sold;
  - names in the Overview and the header are links, shown in brackets like chat links, and a place's map pin sits right after its line;
  - hover an item's name for the game's own tooltip, with what each click does listed under it; a row clicks like its link in chat (a click opens its tooltip, Shift-click links it in chat, Ctrl-click previews it); Alt-click an item to open its details in the window (with Back and Forward), right-click for more, and click the waypoint pin for a waypoint;
  - big items (Mark of Honor buys over 8,000 things) load with a progress bar and never stall your game.
- **Light on your game:** the shipped data takes about 1 MB less memory and loads faster, holding Alt over an item with thousands of uses no longer stutters, and what Recollect remembers while you play stays within a fixed size.
- **Why Recollect can't tell:** a Can't tell names the one thing that would settle it, such as "Open your bank once so Recollect can read it again" or "Open your Leatherworking window once".
- **COMES FROM:** the quests that reward an item and whether you have done them, the vendors that sell it, the creatures and bosses that drop it and where they are (a boss by its name and its dungeon or raid, from the Adventure Guide, which a click on it opens), drops from any enemy in a zone or anywhere in the world, the spots it is found at, the profession recipe that crafts it ("Crafted by Blacksmithing"), what it is made from, and the recipe item that teaches it.
- **Mount links:** hold Alt over a mount someone links in chat to see where it comes from: its drop, vendor or quest, and the Mount Journal's own source.
- **Parts:** an item that combines with other parts into something ("Combine the Reinforced Amani Haft, Tempered Amani Spearhead, and Toughened Amani Leather Wrap to reform the Amani Warrior's Spear") says what they make, how many of the parts you have and which you still need, and is Use now once every part is in your bags. Darkmoon Faire cards say which deck their set makes.
- **More items explained:** over 126,000 items now have a known use or source, including loot that a zone's rares share, quest starters like the Darkmoon Faire's artifacts, the Darkmoon Game Token's minigames, keys that take many of an item ("with 1000"), anima vessels ("Worth 35 Reservoir Anima"), and items you can use from your bags.
- **Waypoints:** Alt+W while the panel names a vendor, a treasure or an NPC puts a waypoint on your map to it. The key can be changed or turned off in the settings.
- **Checks:**
  - toys, mounts, pets, recipes, ensembles and weapon illusions (already known or still to learn);
  - quest starters and quest items;
  - achievement items;
  - items that buy mounts, pets or housing decor;
  - gear (appearance and item level against what you wear: below it is Outdated only for gear from a past season or an older expansion, and Lower level otherwise; a piece saved in one of your equipment sets is never called either);
  - consumables, gems and item enhancements (current or from an older expansion);
  - crafting reagents (whether a recipe you know uses them, milling and prospecting included);
  - profession tools, bags and housing decor;
  - combines, your Mythic+ keystone, and gray junk.
- **The Recollect Audit (`/rec`, or the minimap button):**
  - every stack, sortable by any column; double-click a column divider to fit that column to the longest entry listed;
  - a search box and a filter for verdict, place, items with a known use, items your other characters' recipe scans recorded, and why Recollect can't tell;
  - click a row to pin its details;
  - an option to include your other characters' items.
  - The Reason column always keeps enough room to read.
- **The changelog (`/rec changelog`):** what changed in each version, one section per version, opened by itself after an update.
- **The feature guide (`/rec guide`),** which opens by itself the first time you log in, the settings window (`/rec settings`), a minimap button (click for the Recollect Audit, right-click for settings, drag to move, hide it in the settings) and an Addon Compartment entry.
- **The Tip:** when every use Recollect could read is done, a labeled Tip under the verdict names them, says what it couldn't check, and that the item is most likely safe to sell or delete, but that's your call. Junk gets one for selling it to a vendor. The verdict itself stays strict.
- **Links you can use:** item, quest and achievement names on the panel are in their links' colors. In the details window they are real links: hover one for the game's own tooltip, click it like a chat link, Alt-click an item to open it there.
- **Neighborhood endeavors:** an item a task of your neighborhood's current endeavor names is useful while the task is open, with the task and its progress (Home-Grown Wax in "Candle Culture"). Visit your neighborhood or open the Housing Dashboard's Endeavors tab so the game sends the endeavor.
- **Past seasons:** an upgrade item from a past season of this expansion, such as the Ascendant Voidcore from Midnight Season 1, is outdated for gear, and the panel says which season is current. Sparks and other reagents that still make gear with an appearance you haven't collected read "Useful for transmog only".
- **Every use gone:** an item whose every known use has been removed from the game is outdated, and says what it was for ("it bought 55 things" for Primeval Essence). COMES FROM says in which patch it could no longer be obtained.
- **What purchases lead to:** an item that buys something which leads to a collectible you don't have, such as Phoenix Ash Talisman and the Phoenix Wishwing pet from its quest, is useful and says how.
- **Achievement rewards:** COMES FROM names the achievement that rewards an item, with your progress.
- **What recipes make:** in the details window a reagent's recipes show what each one makes and whether you have it ("Pet: 1 of 3 collected"). Recipes of systems Recollect can't read, such as Protoform Synthesis, say so instead of "Not known", and a reagent used only there reads "Used in 52 Protoform Synthesis recipes" rather than outdated. The step to settle a reagent names only the professions whose recipes use it, or every profession window you haven't opened yet when the game's data names no recipe for it or a recipe whose profession it can't tell.
- **Guide notes:** for a few items nothing in the game explains (Latent Arcana, Home-Grown Wax, Essence of Lumber and others), what a guide says they are for, how many and where, labeled with the site and "not confirmed in game yet". A guide note never changes a verdict.
- **Linked achievements:** an item tied to parts of an achievement, such as Black Claw of Sethe and Advanced Husbandry, shows one line per achievement with your progress and how many of its linked parts are still to do. It is useful while a part is open, never "needed". Parts the game lists without an ID, such as every part of Traversing the Spheres, are matched by the item's name.
- **Which expansion an item is really from:** when AllTheThings dates the item itself to a later expansion than the game's label, ABOUT says both, such as "Key, from Shadowlands (added in patch 9.1.0; the game files it under Battle for Azeroth)" for the Seal Breaker Key. An item is called outdated for its age only when both agree.
- **What using an older item gives:** an item whose Use grants a currency says how much and how many you have ("Using it gives 48 Cataloged Research"), and one that works in a single place says where ("it works only in Undermine").
- **Older game systems:** Runecarving memories, Heart of Azeroth essences and the Ashjra'kamas upgrade say what the system was and whether it still works, with the source. A memory your tooltip shows as already known, on a copy only this character can use, is done.
- **Profession tools with an empty slot:** a tool for a profession whose tool slot is empty reads "your Enchanting tool slot is empty; equip it" when it adds profession stats, and says so when it adds none Recollect can read (the Runed Titanium Rod).
- **Whole prices:** hover a Cost cell on the Buys tab to see everything the trade costs, each with its icon and how many you have (items, currencies and gold). The Overview and the reasons write the whole price ("for 50 plus 1 Apexis Crystal and 25 gold"), and a trade with no vendor named says where it happens ("In Blade's Edge Mountains").
- **Expandable Overview sections:** each section (What it's for, How to get more, Guide notes, What you have, Checks) is a large heading with its icon, a one-line summary and a plus button, like the guide's. Click it to open or close the section. Only the first section starts open, and the ones you open or close stay that way. Inside a section, "and 8,372 more on the Buys tab" has the same plus button: it opens an indented box of the rows, 25 at a time, with the same links and states as the tab, and stays open while you play. A section never shows a count alone: it names its rows, the ones still to do first, and lines that read the same are merged.
- **One count for reagents:** the headline and WHAT IT'S FOR agree ("A crafting reagent in 11 recipes"), with how many of them you know.
- **Other crafting systems:** a reagent used by Protoform Synthesis, Mechagon tinkering and similar systems is useful when those recipes make a mount, pet or other collectible you don't have, and names them (Protoform Sentience Crown).
- **Gear an item buys:** an item that buys gear whose appearance you haven't collected is useful and names the pieces (Seedbloom).
- **Quests for another class or faction:** an item whose only quests are for another class or faction says so ("Used in "The Sacred and the Corrupt" for another class"), and a quest starter whose quest is gone from the game is outdated (Dastardly Invitation). A quest item no quest in your log names also says which quests give it and whether you've done them.
- **Finished items:** an item whose every use Recollect read is done (an achievement earned, a quest done that may come back) has its own filter in the Recollect Audit, "Can't tell: every use found is done".
- **Curator mode (optional, off by default):** help build Recollect's database. Turn it on under `/rec settings`, Curator. While it's on, Recollect notes where the game shows you something its database gets wrong or doesn't have: a vendor's stock and prices, a drop, a quest reward or giver, a recipe's reagents, what a combine makes, what an item's use gives, where an NPC stands. It records only game IDs and map positions plus your character's class, race, level, faction and professions, never names, chat, gold or your inventory, and never grows past 1 MB. Recollect's author collects the findings in the background through the "Recollect Curators" community; you'll see a chat line when a collection starts and ends, `/rec curator` shows it with a Cancel button, and "Ask me before each collection" asks you first. Turning curator mode off offers to delete your findings and shows how to leave the community.
  - **Curator Flag:** with curator mode on, the item details window has a Curator Flag button. Pick what's wrong (missing info, incorrect info, the wrong place or price, no longer obtainable, the verdict, or something else) and add your own words if you like; "something else" needs a few. It goes to the author with your next collection. Click it again to change it before then, or to add more afterwards; it shows when your flag was delivered.
  - **Feedback:** `/rec feedback` opens a box for anything you want the author to know. It goes with your next collection too.
  - **Errors:** any Recollect error your game shows is kept and sent along, so it can be fixed. Flags, feedback and errors are read only by the author, and what the author already has is cleared when a new database arrives.

[Unreleased]: https://github.com/HackyThings/CobySuite-Recollect/compare/v0.0.3...HEAD
[0.0.3]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v0.0.3
[0.0.2b]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v0.0.2b
[0.0.2a]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v0.0.2a
[0.0.2]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v0.0.2
[0.0.1d]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v0.0.1d
[0.0.1c]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v0.0.1c
[0.0.1b]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v0.0.1b
[0.0.1a]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v0.0.1a
[0.0.1]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v0.0.1
