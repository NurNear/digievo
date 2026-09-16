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
I-04 egg/collection, I-05 mixing, and I-06 training battles/progression.
The Thai UI supports collecting at three nodes, buying/hatching eggs, locking
creatures, claiming pending eggs, and previewing/confirming a 20-coin mix.
Walk to the blue training pad and choose a creature's training button. Select
BASIC or an unlocked skill each turn; Speed, owner-turn cooldowns and shields are
resolved by the server. Winning grants 20 coins, 20 XP (up to the cap), one win
of Potential progress, and a guaranteed first victory egg (20% thereafter).
Full egg inventories keep battle rewards pending. Losing or forfeiting costs
nothing. Locked creatures can train. Economic actions wait until combat and
reward confirmation finish.

Stopping Play discards the test profile; cloud persistence remains disabled.
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
.tools/rojo-7.7.0/rojo build default.project.json -o build/RobloxMVP_LocalTest.rbxlx
open -a RobloxStudio build/RobloxMVP_LocalTest.rbxlx
```

Press Play, hatch the starter egg, walk near a gold node and collect another.
The panel shows node cooldowns, inventory and lock buttons. Walk to the blue
training pad, then press a creature's training button to enter battle. Local tool binaries
are ignored by Git; Luau 0.738 was built from source for Intel macOS.

Rojo is pinned in `aftman.toml` to the stable 7.7.0 version.

```powershell
New-Item -ItemType Directory -Path build -Force
rojo build default.project.json -o build/RobloxMVP_LocalTest.rbxlx
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
