# ForeverCDs

## v0.1.1-beta

- Talent check for Mana Tide Totem and Power Infusion. Out of combat, ForeverCDs inspects shamans and priests in your group, one every 2 seconds, with no click needed. Players without the talent are hidden. Players it hasn't checked yet still show as assumed ready, and a seen cast counts as proof.
- Results are kept between sessions and refreshed every 30 minutes, after a spec change, or after a cast.
- `/fcds talents` lists who has each talent spell. The Spells tab has a "Check talents" toggle and shows how many players are still unchecked.
- `/fcds inspect [unit | player]` is a diagnostic probe of the talent APIs. It saves its output to SavedVariables so it can be read after a `/reload`.

## v0.1.0

- First release. Tracks Innervate for every druid in your party or raid, whatever their spec. Only you need the addon.
- Window mode, and party frame mode with icons on each member's unit frame (Blizzard frames, ForeverUnitFrames, ElvUI, Shadowed UF, Cell, Grid2, and a generic scan for other addons).
- Presets for Rebirth, Tranquility, Mana Tide Totem, Blessing of Protection, Lay on Hands, Divine Intervention, Fear Ward, Power Infusion and Soulstone Resurrection, off by default. `/fcds add` tracks any other spell.
- "Assumed ready" `?` mark for cooldowns it has not seen start.
- Running cooldowns survive `/reload` and relog.
- Optional ready and cast alerts, and optional addon-message sync.
- Options panel with tabs for Spells, Window, Party frames, and Alerts & sync. The Window and Party frames tabs show a live preview, and the Party frames tab lists the unit frame found for each member.
- `/fcds debug` logs every group cast event for bug reports.
