# I-01 Verification - 2026-09-12

## Scope

Baseline v1.0 pure domain rules only. The Studio place contains a baseplate,
spawn, shared modules and the same test suite used by the Luau CLI. It is not
the playable hatch/battle/mix journey.

## Verification

- Luau CLI 0.738: `tests/run.luau` passes 14,322 assertions; checks all 36 unordered parent pairs
  across four phases (144 cases). Also checks documented rarity probabilities,
  parent symmetry, conditional inheritance, RNG boundaries, progression,
  world boundaries, damage examples and invalid input/config rejection.
- Stats are compared with an integer-arithmetic reference for eight definitions,
  ten levels and six star counts. This caught and fixed a floating-point floor error.
- `luau-analyze` reports no diagnostics for Catalog, DomainRules and the CLI suite.
- Rojo 7.7.0-rc.1 builds `build/RobloxMVP_LocalTest.rbxlx` successfully.
- XML inspection confirms Catalog/DomainRules, the server test entry point,
  ServerStorage test suite, StarterPlayerScripts, baseplate and spawn are present.
- Studio opened the generated local file and its process responds. Rojo serves
  `RobloxMVP_LocalTest` on `127.0.0.1:34872`.
- User confirmed Connect and Play. Studio CreatorOutput at 2026-09-12 08:17:35 UTC
  independently records: `I-01 PASS: 14322 assertions, 144 world cases. Local-only; no player data is saved.`
- After restarting the project-owned Rojo process, `/api/rojo` confirms
  `expectedPlaceIds: [0]`. The server remains running; reconnect the plugin if
  it disconnected during that restart.

## Isolation And Outstanding Checks

- Rojo allows live sync only to PlaceId 0. No gameId/placeId override is configured.
- The test entry point refuses to run outside Studio or with nonzero GameId/PlaceId.
- No DataStore or remote mutation implementation exists. Nothing writes player data.
- No cloud experience has been created or published. Before online persistence
  tests, create a separate test experience and verify its UniverseId/PlaceId and
  data namespace `RobloxMVP_Test_v1`. Do not substitute production data.
- Native UI automation failed to initialize twice. The user performed Connect
  and Play; Studio logs confirm the suite passed in the actual engine.
- Ownership, locks, balance/capacity, stale preview tokens and durable commits
  belong to later tasks. `rollMix` only evaluates a result; it does not grant it.
- No persistence, fault/replay, network, performance or child playtest results yet.

## Tool Provenance

- Rojo uses the existing local installation, pinned in `aftman.toml`.
- Luau [official release 0.738](https://github.com/luau-lang/luau/releases/tag/0.738)
  is cached under ignored `.tools/luau-0.738`.
- Windows archive SHA-256 verified before execution:
  `1d465aa225dff00ed589f32dd79f6e766b54c4de57e3b8652410ccbd4d491695`.
- [Rojo project format](https://rojo.space/docs/v7/project-format/) documents
  `servePlaceIds`; [Luau CLI](https://luau.org/getting-started/) documents
  the runtime and analyzer used for these checks.
