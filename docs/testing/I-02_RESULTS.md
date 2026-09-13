# I-02 Verification - 2026-09-12

## Implemented

- Server-only profile schema v1 with bounded inventory, finite integers, immutable
  creature identity, valid references, serializable data and a 256 KiB size guard.
- ProfileRepository: UpdateAsync-based acquire/renew/release, 120-second leases,
  monotonically increasing fencing generations, server-issued 60-second intents,
  PREPARE/COMMIT, latest 100 receipts and a durable sequence high watermark.
- Every callback revalidates ownership and current state. Random outcomes are
  supplied by a server plan builder once, outside the storage callback.
- Unknown storage outcomes block new mutations and cached profile reads until
  authoritative UpdateAsync observation/recovery. No cached GetAsync reads or
  default-profile fallback are used for recovery.
- Prepared results survive expired intent tokens and session takeover. A
  receipt acknowledges success only after commit. Both prepared and projected
  committed sizes are checked before accepting the operation.
- ProfileSession handles join, starter grant, 30-second renewal and leave.
  LocalTest runs it against a separate in-memory store after the test suite.
- RobloxStore is an injected standard DataStore adapter with bounded 1/2/4/8
  second backoff plus jitter, budget checks and metadata preservation. Its
  constructor checks Studio, exact nonzero test UniverseId/PlaceId and namespace
  `RobloxMVP_Test_v1` before calling the supplied DataStore factory.

## Automated Results

Luau 0.738: **5,534 checks passed**, including 400 fault runs (100 at each point):

| Fault | Expected outcome |
|---|---|
| Before PREPARE | Original inventory; retry may commit once |
| After PREPARE, response lost | Recover the stored plan without rerolling |
| Before COMMIT | Original resources reserved; recover and commit once |
| After COMMIT, response lost | Return original receipt without duplicate mutation |

Additional checks cover 100 repeated callbacks, 100 repeated starter requests,
lease takeover during a callback, old-owner fencing, a simulated 120-second
outage, expired intents, unissued IDs, input conflicts, receipt eviction,
unknown schemas, invalid profiles, oversize projected commits, reentrant calls,
heartbeat/rejoin, and resuming new work after a lost starter response.

The Luau CLI uses a conservative JSON-size upper bound; Studio uses the real
`HttpService:JSONEncode` byte length. Boundary-injection tests independently
ensure an oversize COMMIT cannot leave a durable PREPARED operation behind.

I-01 regression suite: 14,322 assertions and all 144 world cases pass.
Rojo 7.7.0 builds the combined local test place successfully.
Luau analyzer reports no diagnostics for all five persistence modules and the CLI suite.
Studio Play verification of I-02 is pending; no online DataStore claim is made.

## Limits And Next Gate

- MemoryStore is a test double, not Roblox MemoryStoreService. It survives a
  repository replacement in a test, but not stopping Studio or process exit.
- The 400 fault runs are simulations, not the full I-08 durable/backend fault
  matrix, real two-server concurrency, outage timing or load verification.
- No cloud experience or test IDs have been configured. The adapter is not
  connected in LocalTest. Online persistence must remain disabled until a
  separate test experience and its IDs are verified. Nothing is published.
- Only schema v1 is supported. Unknown versions are rejected without rewriting
  the stored value; no speculative migration or automatic rollback exists.
- Plan builders are trusted server code, never client data. They still require
  the action-specific rules in I-03 through I-06: ownership from Player identity,
  request validation, active-battle restrictions, prices/rewards, proximity and
  preview tokens. The repository is not a general client mutation endpoint.
- The game screen remains a baseplate; this task adds no playable egg or battle UI.

## Run

```powershell
.tools/luau-0.738/luau.exe tests/persistence-run.luau
rojo build default.project.json -o build/RobloxMVP_LocalTest.rbxlx
```

Connect Rojo in the local test place and press Play. Output should contain both
`I-01 PASS` and `I-02 PASS`. Player attributes `ProfileStatus`, `TestCoins` and
`TestEggs` expose local harness state to Studio inspection only.

## References

Checked 2026-09-12: [Roblox Data stores](https://create.roblox.com/docs/cloud-services/data-stores)
and [GlobalDataStore](https://create.roblox.com/docs/reference/engine/classes/GlobalDataStore).
Leases, fencing and two-phase operations are project policies, not guarantees
supplied by the DataStore API itself.
