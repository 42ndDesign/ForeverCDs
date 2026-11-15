# ForeverCDs

Tracks group cooldowns in **World of Warcraft: Forever**: Innervate, Rebirth, Lay on Hands, Power Infusion
or any spell you add, in party and raid. Shows them in a movable window or as icons on your unit frames.

- Tracks **every** group member whose class can cast a tracked spell, so a feral druid's Innervate counts. Talent spells (Mana Tide Totem, Power Infusion) are checked by an automatic inspect out of combat, and players without the talent are hidden. `/fcds talents` lists the results.
- Works in party and raid (up to 40). **Only you need the addon**: it reads group cast events, your own cooldowns and buffs it sees.
- If it hasn't seen a cooldown start, it says so: those show as *assumed ready* with a `?` mark, never as plain "Ready".
- Default list is Innervate only. Presets you can turn on: Rebirth, Tranquility, Mana Tide Totem, Blessing of Protection, Lay on Hands, Divine Intervention, Fear Ward, Power Infusion, Soulstone Resurrection. Add any other spell with `/fcds add`.
- **Window mode** (a movable list), or in a party, **frame mode**: small icons attached to each member's party frame. Works with Blizzard party frames, ForeverUnitFrames, ElvUI, Shadowed UF, Cell, Grid2, and most other unit-frame addons. Raids always use the window.
- Running cooldowns survive `/reload` and relog.
- Optional ready and cast alerts, and optional addon-message sync between players who run it.

<!-- Screenshots: window mode, frame mode, tooltip -->

## Install

- **CurseForge app:** World of Warcraft → **Forever** → search ForeverCDs.
- **By hand:** download the zip from [Releases](../../releases), unzip into `World of Warcraft\_forever_\Interface\AddOns`, then `/reload`.

## Commands

`/fcds` (or `/forevercds`) opens the options panel (Esc → Options → AddOns → ForeverCDs).

| Command | Effect |
|---|---|
| `/fcds` | Open the options panel, or print help if the panel is unavailable |
| `/fcds add <spell> [CLASS]` | Track a spell, e.g. `/fcds add Innervate DRUID` |
| `/fcds remove <spell>` | Stop tracking a spell |
| `/fcds list` | Tracked spells with their IDs and cooldowns |
| `/fcds cd <spell> <seconds>` | Override a cooldown length (`0` clears the override) |
| `/fcds party window` / `frames` | Party display mode; raids always use the window |
| `/fcds anchor <point> <relativePoint> <x> <y>` | Frame-mode anchor, e.g. `LEFT RIGHT 4 0` |
| `/fcds frames <pattern>` / `clear` | Custom unit-frame name pattern, e.g. `ElvUF_PartyGroup1UnitButton%d` |
| `/fcds lock` / `unlock` | Lock or unlock the window |
| `/fcds test` | Toggle test mode with simulated members and timers |
| `/fcds reset` | Reset position, options, talent results and the alert player list; keep the spell list |
| `/fcds sync on` / `off` | Addon-message sync (off by default) |
| `/fcds debug` | Log every group cast event: unit, GUID, spell ID, name, and which fields were secret |
| `/fcds set <option> <value>` | Set any panel option; `/fcds options` lists them |
| `/fcds alert players <names>` / `clear` | Limit alerts to these players |
| `/fcds talents` | Who has each talent spell (Mana Tide Totem, Power Infusion), and when they were checked |
| `/fcds inspect [unit \| player \| clear]` | Diagnostic probe of the talent APIs; output is saved to SavedVariables |
| `/fcds options` | List every option with its value and allowed range |
| `/fcds help` | List the commands in chat |

## How it detects casts

1. **Group cast events** (`UNIT_SPELLCAST_SUCCEEDED`) for `player`, `party1-4`, `raid1-40`. Duplicates for the same player and spell within 0.75 s count once.
2. **Your own cooldown** from `C_Spell.GetSpellCooldown`, when it is readable and not just the GCD.
3. **Buff sighting**: a tracked buff on a group member, with a readable caster, starts that caster's timer if none is running.
4. **Sync** (optional): players running ForeverCDs broadcast their own casts on the `FCDS` prefix.

A seen cast always wins over sync, and sync wins over a buff sighting or an assumption. ForeverCDs never registers the combat log, and checks every value with `issecretvalue` before using it.

## Frame mode and unit-frame addons

Anchors work the same for any unit frame. ForeverCDs finds each member's frame by its `unit`, never by position, trying in order: your custom pattern, known frame addons, Blizzard compact party frames, Blizzard party frames and PlayerFrame, then a scan of every visible frame bound to that unit (out of combat). If no frame is found, that member shows in the window and you get one notice per session.

## Development

```
lua tests/run.lua    # Lua 5.1; offline tests for Spells, Tracker, Talents and Sync
```

See `docs/TESTING.md` for in-game checks and `docs/PUBLISHING.md` for releases.

## License

MIT
