# ForeverCDs

## v0.1.4-beta

- Your own talent spells are read from your spellbook, so you're no longer listed for Mana Tide Totem or Power Infusion without the talent. Since v0.1.2 you could stay "not checked yet" forever.
- If your own talents can't be read at login, ForeverCDs tries again every 30 seconds until it gets a full read.

## v0.1.3-beta

- Spell icons show again in the window, on party frames and in the options panel. Every icon had been showing as a question mark.

## v0.1.2-beta

- Talent check only hides a player after a complete, recent inspect. A partial read, one that found no talents, one older than 30 minutes, or one taken before a spec change counts as "not checked yet".
- A player whose inspect can't be read is retried with a growing wait, instead of every 2 seconds ahead of everyone else.
- A finished cooldown no longer keeps a player without the talent on the list. A running one still does.
- Players who leave keep their running cooldowns past 30 minutes until those run out, so Lay on Hands and Divine Intervention survive a long break.
- Frame mode adds icons for a member as soon as they become eligible, without waiting for a roster change.
- The window sort no longer reorders rows whose cooldowns end within 0.05 s of each other.
- Sync ignores messages with more than 7200 seconds and won't match a sender by a short name two group members share.
- Secret values are checked before any other test on them.
- Changing the window scale keeps the window where you put it.
- Frame mode moves icons when a unit-frame addon re-sorts its buttons, and "Include yourself" now applies there too.
- Lighter in raids: the window redraws less, casts from non-group units are skipped early, roster changes are batched, and the frame scan backs off.
- The "couldn't find party frame" notice waits a few seconds, so frames that load late don't trigger it.
- `/fcds add` takes the class in any case, `/fcds cd` rejects a bad number instead of clearing the override, and spells with non-Latin names get their own key.
- `/fcds talents` no longer writes to the probe log.

## v0.1.1-beta

- Talent check for Mana Tide Totem and Power Infusion. Out of combat, ForeverCDs inspects shamans and priests in your group, one every 2 seconds, with no click needed. Players without the talent are hidden. Players it hasn't checked yet still show as assumed ready, and a seen cast counts as proof.
- Results are kept between sessions and refreshed every 30 minutes, after a spec change, or after a cast.
- `/fcds talents` lists who has each talent spell. The Spells tab has a "Check talents" toggle and shows how many players are still unchecked.
- `/fcds inspect [unit | player]` is a diagnostic probe of the talent APIs. It saves its output to SavedVariables so it can be read after a `/reload`.

## v0.1.0-beta

- First release. Tracks Innervate for every druid in your party or raid, whatever their spec. Only you need the addon.
- Window mode, and party frame mode with icons on each member's unit frame (Blizzard frames, ForeverUnitFrames, ElvUI, Shadowed UF, Cell, Grid2, and a generic scan for other addons).
- Presets for Rebirth, Tranquility, Mana Tide Totem, Blessing of Protection, Lay on Hands, Divine Intervention, Fear Ward, Power Infusion and Soulstone Resurrection, off by default. `/fcds add` tracks any other spell.
- "Assumed ready" `?` mark for cooldowns it has not seen start.
- Running cooldowns survive `/reload` and relog.
- Optional ready and cast alerts, and optional addon-message sync.
- Options panel with tabs for Spells, Window, Party frames, and Alerts & sync. The Window and Party frames tabs show a live preview, and the Party frames tab lists the unit frame found for each member.
- `/fcds debug` logs every group cast event for bug reports.
