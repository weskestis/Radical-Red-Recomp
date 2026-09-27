# Radical Red v4.1 coverage

This table describes version 0.5.13 as tested against unmodified gen1recomp
0.3.5 and 0.3.20. “Live” means the player's private ROM data is mounted and
consumed by the game. “Host gap” means gen1recomp does not yet reproduce every
CFRU/GBA detail.

| System | State | Evidence or boundary |
|---|---|---|
| Packaging and activation | **PASS** | One ordinary mod package; enabling it automatically installs the conversion. No modified launcher, executable, APK, or engine file. |
| ROM identity | **PASS** | Exact 32 MiB v4.1 size and MD5, header, embedded version, table pointers, counts, and sentinels are validated before use. |
| Private cache | **PASS** | ROM-derived material is generated locally under the mod-owned cache and never shipped. Schema 14 forces corrected encounters, connections, list tables, true map bounds, and selector-qualified graphics to rebuild. |
| Android importer compatibility | **PASS** | Binary ROM slices negotiate `readString`, numeric `readBytes`, or byte-at-a-time `get`. Raw tiles, metatiles, and attributes use the mod-local adapter, including a full readBytes-only cold-extraction regression. |
| World | **LIVE** | 425 maps/layouts, 1,324 warps, 116 ordered outdoor connections, metatiles, collision, objects, field events, encounters, scripts, text, movements, shops, and trainers. Every layout/warp/connection is audited; 306 odd-sized layouts use true ROM bounds rather than padded storage, and duplicate-direction edges remain intact. The 134 wild maps use RR's relocated day/night tables; 4,866 usable slots are validated and species-zero placeholders are disabled. |
| New-game setup | **LIVE** | The original v4.1 room script, prompts, and exact nested difficulty, Minimal Grinding Mode, and randomizer menus run automatically. Its unmatched black fade is cleared on the first warning frame without input. All 16 custom list tables are extracted from the ROM, so regions, natures, fossils, tutors, balls, types, floors, rematches, and modes cannot display FireRed badge names. |
| Randomizers | **LIVE** | Normal/scaled species, ability, and learnset modes use the original flags, full trainer-ID formulas, progression pools, and candidate tables read from v4.1. The region-selected starter gift is preserved rather than randomized a second time. |
| Species and forms | **LIVE** | 1,376 registry rows with stats, types, abilities, evolutions, learnsets, TM/tutor data, sprites, icons, and palettes. |
| Moves and types | **LIVE / PARTIAL** | 1,004 records, modern category split, Fairy, exact 24×24 chart, and all expanded battle-text placeholders used by v4.1 are live. Some CFRU-only effect handlers remain a host gap. |
| Abilities and items | **LIVE / PARTIAL** | All names/data and 282/750 expanded registry entries are live; some modern in-battle trigger semantics remain a host gap. |
| Presentation | **LIVE / PARTIAL** | Radical Red title, all 545 addressable object-event sprites from its ordinary, Pokémon/follower, and custom-player tables with 451 RR palettes, Pokémon/trainer art, item icons, UI chrome, naming assets, field effects, and audio are extracted. All 546 physical mappings and 397 used palette tags are ROM-checked; map selector bytes and expanded indirect graphics slots remain intact. Erased fixed addresses are replaced with RR's live Rock Smash sheet and relocated nine-frame rival naming sheet. Regular Options and Game Modes retain the authentic renderer on success and use a numeric/primitives panel only after an actual renderer exception; the Game Modes path also removes its stale black fade. Exact GBA animation timing is not claimed. |
| Script natives | **PASS** | Every one of the 72 `callnative` addresses found in the v4.1 script extraction is assigned exactly once. |
| Story and followers | **LIVE** | Follower state/reactions/movement, Mewtwo sequence support, roaming state, NG+, pluralization, sound, and related utilities. |
| Progression/QoL | **LIVE** | Running shoes are active from the first step. Level-cap operations, random/category starters, random eggs, party checks, gender/ability/form changes, and heal utilities use the selected party slot. The five bedroom-console codes retain their ROM flags; DexAll, TeamPreview (L/SELECT), and EZCatch have matching host behavior. CFRU's expanded `0x5000..0x51FF` variables are resolved for Pokémon preview, gift, egg, and cry script operands. |
| Facilities | **LIVE** | ROM-backed facility trainers, fixed/rental parties, spreads, simulator scoring, and party save/restore. |
| Raids | **LIVE** | Den selection, star rules, rewards, capture, barriers, Max moves, extra attacks, stat nullification, KO boosts, and turn/faint loss rules. |
| Saves | **PASS** | Dedicated `_radical_red_4_1` cart suffix; disabling the mod and restarting returns to the vanilla save scope. |
| Automated verification | **PASS** | Parser, battle, callback, facility, raid, story, orchestration, exact-loader, package-policy, lint, Gen 3 compatibility, vanilla-off, authentic/fail-safe Options and Game Modes draws, all 16 custom menus, every map connection/landing, all nine relocated rival frames, the randomized-mode Turtwig `0x5124` path, selector-qualified Stufful identity, and the 9,530-asset ROM/palette audit. Modern and readBytes-only cold launches plus cached relaunch pass under a 256 MiB address-space ceiling. |
| Manual graphical playthrough | **NOT RUN** | The build environment has no LÖVE executable. A device-side smoke test and full playthrough remain external validation. |

## Known host battle boundary

The stock host implements the Gen III battle core plus this mod's Radical Red
category/type and raid extensions. It does not yet have a one-for-one handler
for every modern CFRU move-effect ID, ability callback, held-item callback, or
animation script. Unsupported secondary behavior must not be mistaken for ROM
data being absent: the expanded records are present, while the missing piece
is native host semantics.

Accordingly, 0.5.13 is a functional runtime total-conversion candidate, not a
claim of byte-for-byte or frame-perfect Radical Red battle parity.
