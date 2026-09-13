# I-03 Verification - 2026-09-13

## Implemented

- Added server-side RPC view/dispatch modules for the MVP RemoteEvent boundary.
- Validates request envelopes: `apiVersion`, `requestId`, `action`, `args`, known fields and ID shape.
- Returns safe `ProfileView`, `WorldView` and receipt views without lease, prepared plans or internal storage fields.
- Adds request replay caching per player/requestId. Retrying the same request returns the same response; changing payload under the same requestId returns `IDEMPOTENCY_CONFLICT`.
- Adds token-bucket limits for read/preview/mutation routes. Rate limited requests do not call repository mutation paths.
- Adds `Operation.Create`, `Operation.Execute` and `Operation.Get` shell behavior. `Operation.Create` only accepts server-registered operation builders; client payloads cannot create arbitrary profile plans.
- Binds operation fingerprints on the server at create time. `Operation.Execute` accepts only `operationId` and reuses the stored fingerprint instead of trusting client-supplied parameters.

## Automated Results

Luau 0.738:

- I-01 regression: **14,322 assertions** and 144 parent/world cases pass.
- I-02 regression: **5,534 checks** and 400 injected memory-backend fault runs pass.
- I-03 RPC suite: **44 checks** pass.

Additional checks cover unsupported API versions, unknown fields/actions, profile-not-ready pending responses, safe profile projection, world projection, rejected insufficient-funds creates with no resource mutation, request replay, requestId conflicts, pending operation reads, unknown operation IDs, committed receipt reads and basic rate limiting.

`luau-analyze` reports no diagnostics for Catalog, DomainRules, persistence modules, RPC modules and the CLI suites.

Rojo 7.7.0 builds `build/RobloxMVP_LocalTest.rbxlx` successfully with `RpcTests` mapped into ServerStorage. Studio Play verification for I-03 is still pending.

## Limits And Next Gate

- This is still a server boundary and test harness, not playable UI.
- The only operation builder exercised in the RPC suite is a narrow `Egg.Buy` fixture. Real action rules for collect, hatch, lock, pending eggs, mix preview/commit and battle rewards belong to I-04 through I-06.
- No RemoteEvents have been wired to a client screen yet. LocalTest currently runs the server-side suite and exposes memory profile attributes only.
- No online DataStore write path is enabled. A separate test experience and verified IDs are still required before testing cloud persistence.

## Run

```powershell
.tools/luau-0.738/luau.exe tests/persistence-run.luau
.tools/luau-0.738/luau.exe tests/run.luau
rojo build default.project.json -o build/RobloxMVP_LocalTest.rbxlx
```
