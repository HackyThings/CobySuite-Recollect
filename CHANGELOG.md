# Changelog

All notable changes to Recollect are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), version numbering follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/HackyThings/CobySuite-Recollect/compare/v1.0.3...HEAD
[1.0.3]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v1.0.3
[1.0.2]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v1.0.2
[1.0.1]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v1.0.1
[1.0.0]: https://github.com/HackyThings/CobySuite-Recollect/releases/tag/v1.0.0
