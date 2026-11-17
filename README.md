# ForeverCDs

Tracks group cooldowns in **World of Warcraft: Forever**: Innervate, Rebirth, Lay on Hands, Power Infusion
or any spell you add, in party and raid. Shows them in a movable window or as icons on your unit frames.

**Best with your guild or regular group.** Forever hides other players' spells from addons during
combat, and big cooldowns are almost always used in combat. Each player's own client can still read
their own cooldowns, so group members who run ForeverCDs share theirs. Get your healers and
paladins to install it.

- **Sharing between ForeverCDs users** is on by default. Each player reports every tracked spell of their class, whether or not they track it themselves: time left, ready, or "I don't have this spell". If a message is blocked, for example during a boss fight, it is sent once it gets through, with the right time left. `/fcds sync status` shows who in your group runs it.
- For group members without ForeverCDs, casts are only seen out of combat. When a fight ends, ForeverCDs also re-reads their buffs and checks Blizzard's damage meter for that fight. That catches Soulstone, Fear Ward and Divine Intervention while the buff is up, and Lay on Hands and Tranquility from their healing. A meter hit only says the spell was used during the fight, so the timer starts at the fight's end. Rebirth used mid-fight can't be seen without ForeverCDs. Those players otherwise show as *assumed ready* until a cast is seen.
- Tracks **every** group member whose class can cast a tracked spell, so a feral druid's Innervate counts. Talent spells (Mana Tide Totem, Power Infusion) are checked by an automatic inspect out of combat, and players without the talent are hidden. A player who runs ForeverCDs reports this directly. `/fcds talents` lists the inspect results.
- Works in party and raid (up to 40).
- If it hasn't seen a cooldown start, it says so: those show as *assumed ready* with a `?` mark, never as plain "Ready".
- Default list is Innervate only. Presets you can turn on: Rebirth, Tranquility, Mana Tide Totem, Blessing of Protection, Lay on Hands, Divine Intervention, Fear Ward, Power Infusion, Soulstone Resurrection. Add any other spell with `/fcds add`.
- **Window mode** (a movable list), or in a party, **frame mode**: small icons attached to each member's party frame. Works with Blizzard party frames, ForeverUnitFrames, ElvUI, Shadowed UF, Cell, Grid2, and most other unit-frame addons. Raids always use the window.
- Running cooldowns survive `/reload` and relog.
- Optional ready and cast alerts.

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
| `/fcds sync on` / `off` | Share cooldowns with other ForeverCDs users (on by default) |
| `/fcds sync status` | Which group members run ForeverCDs, and when each was last heard from |
| `/fcds debug` / `debug clear` | Log every cast event and sync message, saved to SavedVariables on `/reload`; `clear` empties the log |
| `/fcds secrecy` | Diagnostic: how secret the client says each tracked spell and group member is |
| `/fcds set <option> <value>` | Set any panel option; `/fcds options` lists them |
| `/fcds alert players <names>` / `clear` | Limit alerts to these players |
| `/fcds talents` | Who has each talent spell (Mana Tide Totem, Power Infusion), and when they were checked |
| `/fcds inspect [unit \| player \| clear]` | Diagnostic probe of the talent APIs; output is saved to SavedVariables |
| `/fcds options` | List every option with its value and allowed range |
| `/fcds help` | List the commands in chat |

## How it detects casts

On Forever, every tracked spell is *contextually secret*: in combat, another player's cast event carries a hidden spell ID and name, and their buffs can be hidden too. Your own casts are always readable.

1. **Sync**, on the `FCDS` addon-message prefix. Each player sends `H|2|key=value,...` for every tracked spell of their class (seconds left, `0` ready, `?` unknown, `-` not known) when it changes, every 2 minutes, and in reply to `R|2`, which a player sends on joining a group or after `/reload`. Replies wait 1 to 3 s at random. A refused send is retried every 5 s, and the time left is worked out at send time. The v0.1 `C|key|seconds` message is still accepted.
2. **Group cast events** (`UNIT_SPELLCAST_SUCCEEDED`) for `player`, `party1-4`, `raid1-40`, when the spell is readable. Duplicates for the same player and spell within 0.75 s count once.
3. **Your own cooldown** from `C_Spell.GetSpellCooldown`, when it is readable and not just the GCD.
4. **Buff sighting**: a tracked buff on a group member, with a readable caster, starts that caster's timer if none is running.
5. **After combat**, once `C_RestrictedActions` reports the combat restriction lifted (checked every second, up to 20 s): every group member's buffs are read again, and `C_DamageMeter` is read for the latest session. A tracked spell in a member's healing or damage breakdown starts their timer at the fight's end, if none is running. A bigger total in the same session counts as a new use.

A member's own report, a seen cast and your own cooldown rank the same, so the newest wins; a buff sighting or a meter hit only fills an empty slot. A member's report that they don't know a spell hides them for it. ForeverCDs never registers the combat log, and checks every value with `issecretvalue` before using it.

## Frame mode and unit-frame addons

Anchors work the same for any unit frame. ForeverCDs finds each member's frame by its `unit`, never by position, trying in order: your custom pattern, known frame addons, Blizzard compact party frames, Blizzard party frames and PlayerFrame, then a scan of every visible frame bound to that unit (out of combat). If no frame is found, that member shows in the window and you get one notice per session.

## Development

```
lua tests/run.lua    # Lua 5.1; offline tests for Spells, Tracker, Talents and Sync
```

See `docs/TESTING.md` for in-game checks and `docs/PUBLISHING.md` for releases.

## License

MIT
