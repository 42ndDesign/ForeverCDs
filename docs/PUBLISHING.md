# Publishing ForeverCDs

Same pipeline as ForeverTrack: push a `v*` tag, GitHub Actions runs the tests, then the BigWigs
packager builds the zip, creates a GitHub release and uploads to CurseForge.

## One-time CurseForge setup

1. https://authors.curseforge.com → **Create Project** → World of Warcraft → Addons.
   - Name: **ForeverCDs** (distinct from "Forever Cooldowns", which uses `/fcd`)
   - Summary and description: `docs/CURSEFORGE_DESCRIPTION.md`
   - Categories: Unit Frames / Healer, Raid Frames; License: MIT
   - Source: https://github.com/42ndDesign/ForeverCDs
2. Put the project ID in **both** TOCs: `## X-Curse-Project-ID: <id>`.
3. Repo secret `CF_API_KEY` (the same CurseForge API token ForeverTrack uses):
   `gh secret set CF_API_KEY -R 42ndDesign/ForeverCDs`
4. Commit, then `git tag v0.1.0 && git push origin main --tags`.
5. On CurseForge, check the file's game version is **Forever**. If the packager couldn't map
   interface 16001, set it by hand or add `args: -g 1.60.1` to the packager step.

## Each release

1. New section at the top of `CHANGELOG.md`.
2. Commit, `git tag vX.Y.Z`, `git push origin main --tags`.
3. Never tag a test build: tags publish to CurseForge.
