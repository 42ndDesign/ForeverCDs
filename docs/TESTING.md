# In-game testing

Turn on Lua errors (`/console scriptErrors 1`) or use BugSack. Every test below runs with `/fcds debug` on.

## Day one: settle the open questions

1. **Persistence.** `/fcds cd innervate 300`, `/reload`, `/fcds list`: Innervate should show `cd 300s (override)`. Then log out fully and back in and check again. If the override is gone, SavedVariables are not being written on this client: report it before anything else.
2. **Cast events in combat.** With a druid in the party:
   - Out of combat, in range, the druid casts Innervate. Expect a debug line like
     `cast unit=party1 guid=Player-... id=29166 name=Innervate secret:` and the timer starts within 0.5 s.
   - Same in combat. If the line shows `id=<secret>` the in-combat spell ID is secret: note whether `name=` is readable.
3. **Feral druid** casts Innervate: their row appears and starts, proving there is no spec filter.
4. **60+ yards away**: note whether a debug line appears at all.
5. **Raid of 6+**: repeat 2.
6. `/reload` and a full relog while Innervate is on cooldown: the timer comes back with the right time.

## Layout

- `/fcds test`: 3 simulated druids (ready, assumed with `?`, counting down). Check sorting, `/fcds unlock`, drag, `/fcds set scale 1.5`, `/fcds set style icons`, `/fcds set grow up`.
- Frame mode: `/fcds party frames`, then `/fcds test` solo: test icons attach to your player frame. In a party they attach to each frame. Try `/fcds anchor LEFT RIGHT 4 0` and `/fcds anchor BOTTOM TOP 0 2`.
- With ForeverUnitFrames, Blizzard frames, and any other unit-frame addon: icons sit on the right frames and follow them when moved. If one isn't found, you get one chat notice and that member shows in the window instead.
- Join a raid: the window takes over. Back to a party: frame mode returns.
