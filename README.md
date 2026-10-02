# Digievo

Roblox project scaffold connected to:

https://github.com/NurNear/digievo

## Structure

- `default.project.json` - Rojo project file
- `src/ReplicatedStorage` - shared client/server modules and assets
- `src/ServerScriptService` - server scripts
- `src/StarterPlayer/StarterPlayerScripts` - client scripts

## Local Test Place

Current local scope includes I-01 domain rules, I-02 profile/recovery, I-03 RPC,
I-04 egg/collection, I-05 mixing, I-06 training battles/progression, and
I-07 guided journey/prototype visuals.
The Thai UI supports collecting at three nodes, buying/hatching eggs, locking
creatures, claiming pending eggs, and previewing/confirming a 20-coin mix.
Walk to the blue training pad and choose a creature's training button. Combat is
real-time: the server schedules each fighter's basic attacks independently.
Click a skill (or press 1–3) to cast immediately, with a **6-second cooldown**.
Speed determines attack interval: `max(1, 2.4 - Speed * 0.025)` seconds.
Wave Guard lasts four seconds or one incoming hit. There are no rounds, queued
skills or client-driven basic commands. Hiding the menu does not pause combat. Winning grants 20 coins, 20 XP (up to the cap), one win
of Potential progress, and a guaranteed first victory egg (20% thereafter).
The UI has Pets, Eggs, Mix and Battle tabs, a next-step guide and a result card
with the hatched/mixed pet and skills. Box fox/turtle models have eight variants
shared by collection portraits and pets fighting directly on the blue world pad.
The menu closes when combat starts; a temporary arena camera frames the pets,
HP bars float above them, and skill buttons/countdown bars stay at the bottom
of the screen. The normal camera returns three seconds after the result. Press **B** to
show/hide the menu, **E** near an egg node or training pad, **1–3** to cast available battle skills. Skill shortcuts work whenever the combat HUD is visible, even with the menu
hidden; typing in chat does not trigger them. Basic attacks need no input.
Full egg inventories keep battle rewards pending. Losing or forfeiting costs
nothing. Locked creatures can train. Economic actions wait until combat and
reward confirmation finish.

Stopping Play discards the test profile; cloud persistence remains disabled.
Current real-time combat checks and the Studio walkthrough are in
[Real-time combat verification](docs/testing/REALTIME_RESULTS.md).
I-07 verification and the remaining manual walkthrough are in
[I-07 verification](docs/testing/I-07_RESULTS.md).
I-06 CLI verification and the Studio walkthrough are documented in
[I-06 verification](docs/testing/I-06_RESULTS.md). Studio Play/manual battle
verification is still pending; the prior I-05 walkthrough is recorded in
[I-05 verification](docs/testing/I-05_RESULTS.md).

On this Intel Mac:

```sh
.tools/luau-0.738/luau tests/run.luau
.tools/luau-0.738/luau tests/persistence-run.luau
.tools/luau-0.738/luau tests/eggs-run.luau
.tools/luau-0.738/luau tests/mix-run.luau
.tools/luau-0.738/luau tests/battle-run.luau
.tools/luau-0.738/luau tests/journey-run.luau
.tools/luau-0.738/luau tests/battle-feed-run.luau
.tools/luau-0.738/luau tests/safety-run.luau
.tools/luau-0.738/luau tests/metrics-run.luau
.tools/rojo-7.7.0/rojo build default.project.json -o build/Digievo_WORLD_AUTO_v2.rbxlx
open -a RobloxStudio build/Digievo_WORLD_AUTO_v2.rbxlx
```

Press Play, hatch the starter egg, walk near a gold node and collect another.
The panel shows node cooldowns, inventory and lock buttons. Walk to the blue
training pad, then press a creature's training button to enter battle. Local tool binaries
are ignored by Git; Luau 0.738 was built from source for Intel macOS.

Rojo is pinned in `aftman.toml` to the stable 7.7.0 version.

I-08 local data-safety verification passes 27,680 checks across 2,000 simulated
fault scenarios; see [I-08 results](docs/testing/I-08_RESULTS.md). To run this
heavier suite inside the unpublished Studio harness, set the Workspace boolean
attribute `RunSafetyTests` to `true` before Play. It is disabled by default.
Real DataStore, two-server and migration rehearsals remain pending.

```powershell
New-Item -ItemType Directory -Path build -Force
rojo build default.project.json -o build/Digievo_WORLD_AUTO_v2.rbxlx
rojo serve
```

Open the generated file in Roblox Studio. Connect the existing Rojo plugin to
`localhost:34872`, then press Play. The Output panel should report `I-01 PASS`
with 144 world cases, followed by `I-02 PASS` for simulated persistence faults.
The test place only runs in unpublished Studio sessions;
Rojo sync is restricted to PlaceId 0. Do not publish this test harness.

## Domain Tests

The local Luau 0.738 tool cache was downloaded from the official release and
verified by SHA-256. On another machine, obtain the same release using the
links in the verification report; binaries are intentionally not committed.

```powershell
.tools/luau-0.738/luau.exe tests/run.luau
.tools/luau-0.738/luau.exe tests/persistence-run.luau
.tools/luau-0.738/luau-analyze.exe src/ReplicatedStorage/Shared/Catalog.luau src/ReplicatedStorage/Shared/DomainRules.luau tests/DomainRules.spec.luau tests/run.luau
```

`Catalog` contains immutable versioned data. Construct `DomainRules.new(Catalog)`
once and provide server-owned creature snapshots and an injected RNG to its
pure functions. Server-only persistence modules live under
`src/ServerScriptService/Persistence`. The local harness initializes a test
profile with starter resources and renews its lease; stopping Play discards
that memory store. Client action routes are connected in the local test place; online storage is disabled.

## GitHub

This local project has the Git remote set to:

```text
origin https://github.com/NurNear/digievo.git
```

If the repository is private, GitHub credentials or a personal access token are required before pushing.

## Studio performance measurements

Set Workspace boolean attribute `MeasurePerformance` to true before Play to emit
local client/server metrics every 60 seconds. See [I-09 procedure and limitations](docs/testing/I-09_RESULTS.md).
Four-client gameplay performance has not yet been measured.
