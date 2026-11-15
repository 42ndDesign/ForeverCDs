<!-- Paste into the CurseForge project's Description (Markdown). Update it with each release that adds or changes a feature. -->

**Summary:** Tracks your party and raid's cooldowns: Innervate, Rebirth, Lay on Hands, Power Infusion or any spell you add. Shows them in a movable window or as icons on your unit frames. Only you need it.

---

# ForeverCDs

**Know who has their big cooldown ready before you ask.**

ForeverCDs tracks group cooldowns in WoW: Forever, in party and in raid up to 40. It shows each one as ready, assumed ready, or counting down, in a window or right on your party frames. Nobody else in the group needs it installed.

## What it tracks

- Innervate is on by default. Presets you can turn on: Rebirth, Tranquility, Mana Tide Totem, Blessing of Protection, Lay on Hands, Divine Intervention, Fear Ward, Power Infusion and Soulstone Resurrection.
- Add any other spell by name or ID, and set your own cooldown length for any spell.
- Every group member whose class can cast the spell, so a feral druid's Innervate counts.
- Talent spells like Mana Tide Totem and Power Infusion are hidden for players who don't have the talent. ForeverCDs checks with a quiet inspect out of combat, one player every 2 seconds. Anyone it hasn't checked yet, or couldn't read fully, stays listed, and a seen cast always counts. `/fcds talents` shows the results.
- A cooldown ForeverCDs hasn't seen start shows as assumed ready with a `?` mark. It never guesses "Ready".
- Running timers survive `/reload` and relog.

## Two ways to show it

- **Cooldown window.** A movable list, ready first, then by time left. Bars or icons only, growing up or down, with adjustable scale, row width and row height. You choose whether it shows solo, in a party, in a raid, and whether it includes you.
- **Party frames.** Small icons on each party member's unit frame, with timer text. Works with Blizzard frames, ForeverUnitFrames, ElvUI, Shadowed UF, Cell and Grid2, and finds most other unit-frame addons on its own. The options panel lists the frame it found for each member. A member without a frame shows in the window instead. Raids always use the window.

## Alerts

- **Ready alert.** A chat line, plus an optional sound, when a cooldown comes back. Limit it to the players you care about, or leave it for everyone.
- **Cast alert.** A chat line when someone casts a tracked spell, naming the target when the buff shows up.
- **Sync.** Optional. Players running ForeverCDs share their own casts, which fills gaps when a caster is out of range.

## Options

Type `/fcds`, or go to Esc → Options → AddOns → ForeverCDs. The panel has tabs for Spells, Window, Party frames, and Alerts & sync. The Window and Party frames tabs show a live preview as you change settings.

| Command | Effect |
|---|---|
| `/fcds` | Open the options panel |
| `/fcds test` | Preview with simulated group members and timers |
| `/fcds add <spell> [CLASS]` | Track a spell, e.g. `/fcds add Innervate DRUID` |
| `/fcds remove <spell>` | Stop tracking a spell |
| `/fcds cd <spell> <seconds>` | Set your own cooldown length (`0` goes back to the default) |
| `/fcds party window` / `frames` | Show party cooldowns in the window or on party frames |
| `/fcds lock` / `unlock` | Lock or unlock the window |
| `/fcds debug` | Log every group cast, for bug reports |
| `/fcds help` | Every command |

## Built for Forever's addon rules

ForeverCDs never touches the combat log. It reads group spellcast events, your own cooldowns, and tracked buffs it sees on group members, and checks every value for Forever's secret values before using it.

## Feedback

Found a bug or have an idea? Open an issue on GitHub or leave a comment here. For a bug, turn on `/fcds debug`, reproduce it, and include the chat output.

---

<sub>Source: [github.com/42ndDesign/ForeverCDs](https://github.com/42ndDesign/ForeverCDs) · MIT License · Not affiliated with Blizzard Entertainment.</sub>
