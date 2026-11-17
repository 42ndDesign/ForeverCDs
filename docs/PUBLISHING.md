# Publishing ForeverCDs

Same pipeline as ForeverTrack: push a `v*` tag, GitHub Actions runs the tests, then the BigWigs
packager builds the zip, creates a GitHub release and uploads to CurseForge.

## One-time CurseForge setup

1. https://authors.curseforge.com → **Create Project** → World of Warcraft → Addons.
   - Name: **ForeverCDs** (distinct from "Forever Cooldowns", which uses `/fcd`)
   - Logo: `assets/avatar-1024.png` (source: `assets/avatar.svg`)
   - Summary and description: `docs/CURSEFORGE_DESCRIPTION.md`
   - Categories: Unit Frames / Healer, Raid Frames; License: MIT
   - Source: https://github.com/42ndDesign/ForeverCDs
2. Put the project ID in **both** TOCs: `## X-Curse-Project-ID: <id>`.
3. Repo secret `CF_API_KEY`, a CurseForge author API token. Make one at
   https://authors.curseforge.com/#/settings/api-tokens (avatar → Settings → API Tokens). CurseForge shows it
   once, so set the secret straight away: `gh secret set CF_API_KEY -R 42ndDesign/ForeverCDs` (prompts for it).
   Lost the value? Generate a new token; there's no need to recover the old one. ForeverTrack has its own
   `CF_API_KEY` secret, so if you revoke the old token, set the new one there too.
4. Commit, then `git tag v0.1.0 && git push origin main --tags`.
5. On CurseForge, check the file's game version is **Forever**. If the packager couldn't map
   interface 16001, set it by hand or add `args: -g 1.60.1` to the packager step.

## Listing copy

The CurseForge listing has no copy in the packaged zip, so the repo is the record. Each piece lives here:

| Piece | Where it lives | Where it goes |
|---|---|---|
| Summary (max ~200 chars) | `docs/CURSEFORGE_DESCRIPTION.md`, first line | CurseForge project → Summary |
| Description | `docs/CURSEFORGE_DESCRIPTION.md`, below the `---` | CurseForge project → Description (Markdown) |
| In-game notes | `## Notes:` in **both** TOCs | Addon list tooltip, CurseForge app |
| Logo | `assets/avatar-1024.png`, source `assets/avatar.svg` | CurseForge project → Avatar |
| Screenshots | not made yet: window, party-frame icons, options panel | CurseForge project → Images |

The summary, TOC notes, description intro and README intro say the same thing in different lengths.
They describe what the addon does today: which spells, where it shows them, and that group members who run it share their cooldowns.
Leave out how it started (one spell, one class, one bug). When a feature lands, update all four.

## Each release

1. New section at the top of `CHANGELOG.md`.
2. If the release adds or changes a feature, update the listing copy above, then paste the new
   summary and description into CurseForge. The packager uploads the file only, never the listing.
3. Commit, `git tag vX.Y.Z`, `git push origin main --tags`.
4. Never tag a test build: tags publish to CurseForge. For a test zip, run the release workflow
   by hand (Actions → Package and release → Run workflow): it builds the zip and attaches it to
   the run without publishing anywhere.
