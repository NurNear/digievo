# I-04 Verification — 2026-09-14

## Implemented

- Server-owned plans for Egg.Collect, Egg.Buy, Egg.Hatch,
  Creature.SetLocked and Reward.ClaimPendingEggs.
- Strict action parameters; server prices, capacities, ownership, node cooldowns,
  proximity and an injected battle-state guard. Local host checks collect distance
  again at Execute. Battle state remains false until the I-06 service exists.
- Optional deferred repository builders: Create validates a deterministic preflight
  plan without RNG; Execute materializes one plan outside UpdateAsync and retains
  it for retry. Existing internal builders retain their previous behavior.
- Local RemoteEvents use Player-derived identity, private responses/profile pushes,
  and public world phase pushes. Cyclic, deep, oversized and non-finite input is
  rejected before request fingerprinting. Player removal clears dispatcher state.
- Thai UI for inventory, hatch, buy, three collection nodes and cooldowns, locks,
  pending rewards and world state. Hatch presentation waits three seconds after
  commit; profile pushes are deferred during that presentation. Requests retry the
  same correlation ID after five seconds; pending operations poll by operation ID.

## Verification on this machine

- Luau 0.738: I-04 **74 checks pass**.
- Tests include full creature/egg inventories, ownership, unknown parameters,
  insufficient funds, absent eggs, locks/no-op locks, cooldown/proximity,
  pending reward overflow, battle guard, 100 repeated backend callbacks,
  and a lost PREPARE response recovered without rerolling or duplicate grants.
- I-01: **14,322 assertions / 144 world cases pass**.
- I-02: **5,534 checks / 400 injected fault runs pass**.
- I-03: **44 RPC checks pass**.
- luau-analyze: no diagnostics for changed pure server modules and I-04 CLI suite.
- luau-compile: both Roblox entry scripts compile. This is syntax verification,
  not Roblox engine/API or visual verification.
- Rojo 7.7.0 builds `build/RobloxMVP_LocalTest.rbxlx`, including the I-04 suite.
- Official Luau 0.738 macOS archive is ARM64. This Intel Mac uses the same tagged
  source built locally with Apple clang. Rojo uses its official x86_64 release.
  Tools and generated place are ignored by Git.

## Studio Play verification

Open the generated place and press Play. Confirm I-01 through I-04 PASS in Output,
then hatch the starter egg, walk within 12 studs of each gold node, collect and
hatch again, and toggle a creature lock. Check Thai text, scrolling, cooldowns and
three-second reveal. Buying initially rejects because starter coins are 20 and
an egg costs 40. There is no battle reward source yet; pending reward UI is empty
in normal play and its successful transfer path is exercised by the test suite.

User pressed Play on 2026-09-14. Studio CreatorOutput at 03:50:47–03:50:49 UTC
confirms I-01 (14,322), I-02 (5,534 / 400 faults), I-03 (44), and I-04 (74)
PASS, followed by local starter profile initialization. Evidence: local log
`~/Library/Logs/Roblox/0.738.0.7381393_20260914T033331Z_Studio_3c016_last.log`.
No project script errors or stack traces were found in the inspected output.
The user subsequently confirmed completing the requested manual walkthrough
(hatch starter egg, collect near a node, hatch again, lock/unlock a creature),
with no issue reported. This is user-reported manual verification, not automated
visual inspection. Multi-client network behavior remains unverified.
The host remains restricted to an unpublished Studio place (GameId/PlaceId 0),
uses only process memory, and has no cloud persistence or published experience.
Mixing, battles and the complete MVP journey remain future milestones.
