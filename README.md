# Roblox

Roblox project scaffold connected to:

https://github.com/NurNear/Roblox

## Structure

- `default.project.json` - Rojo project file
- `src/ReplicatedStorage` - shared client/server modules and assets
- `src/ServerScriptService` - server scripts
- `src/StarterPlayer/StarterPlayerScripts` - client scripts

## Local Test Place

Current scope includes I-01 domain rules and I-02 profile/recovery tested with
an in-memory backend. There is no playable game loop or cloud persistence yet.
See [I-01 verification](docs/testing/I-01_RESULTS.md) and
[I-02 verification](docs/testing/I-02_RESULTS.md).

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
that memory store. No client action routes or online storage are enabled.

## GitHub

This local project has the Git remote set to:

```text
origin https://github.com/NurNear/Roblox.git
```

If the repository is private, GitHub credentials or a personal access token are required before pushing.
