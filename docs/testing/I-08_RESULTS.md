# I-08 local fault and data safety — 2026-10-02

Status: local simulated verification passed. Online acceptance remains open.

## Changes

- Operation.Get recovers uncertain/prepared writes and retries an operation that
  previously received Execute when storage returns. Polling a token that has never
  received Execute does not start it. Existing validation still applies to retries.
- Reissuing an existing intent preserves its actual expiry. Expired unprepared
  intents return EXPIRED_INTENT; prepared plans and receipts take priority.
- Per-player ingress limits apply before request traversal and cached replay
  (burst 40, refill 20/s). Unknown routes cannot grow action-bucket keys. Request
  fingerprints bound table entries and length-prefix strings. Rejections preserve
  a valid request ID so clients can correlate the response.

## Verified

`tests/safety-run.luau`: **27,680 checks; 2,000 fault scenarios**.

| Scenario | Repeats |
| --- | ---: |
| Hatch, mix and battle reward × before PREPARE, lost PREPARE response, before COMMIT, lost COMMIT response, repeated callbacks | 3 × 5 × 100 = 1,500 |
| Prepared mix lease takeover, fencing and recovery | 100 |
| Before-PREPARE outage beyond lease/intent expiry | 100 |
| Reject unsupported schema on copied profiles without rewriting | 100 |
| Disconnect cancels active battle; prepared reward survives reconnect | 100 |
| Projected profile exceeds size limit before writing | 100 |

Assertions cover single resource consumption/reward, unchanged frozen outcomes,
no rerolls or duplicate starter grants, no premature result exposure, and recovery
through the real RPC status routes. Repeated-callback scenarios invoke callbacks
100 times. Additional checks cover expiry reuse, unexecuted status reads, 1,000
cached requests, 1,000 unknown routes, per-player isolation/refill, wide/cyclic
payloads, nonfinite values and oversized strings.

Regression passed: domain 14,322 assertions / 144 cases; persistence 5,534 checks /
400 fault runs; RPC 44; eggs 74; mix 76; battle 178; feed 11; journey 143.
Changed persistence/dispatcher and safety suite pass luau-analyze; the Studio
harness compiles. Rojo builds the local WORLD AUTO v2 place with SafetyTests.

Run locally:

```sh
.tools/luau-0.738/luau tests/safety-run.luau
```

For an optional Studio run, set Workspace boolean attribute `RunSafetyTests` to
true before Play. The heavy suite is off by default.

## Remaining acceptance

- The backend here is an injected in-memory test double, not Roblox DataStore or
  MemoryStoreService. Takeovers model two owners sequentially, not live servers.
- Real DataStore failures/budgets, live two-server fencing and reconnect require
  a separate test experience with verified UniverseId/PlaceId under I-00.
- Schema version 1 has no migration implementation. Rejecting copied version 99
  profiles is a fail-closed test, not a successful migration rehearsal.
- Size checks inject the measurement boundary; real encoded-size/performance,
  long-session replay-cache growth and four-client I-09 measurements remain open.
- Native Studio rendering/input and the full manual gameplay journey are pending.

No production publishing or online storage configuration was performed.
