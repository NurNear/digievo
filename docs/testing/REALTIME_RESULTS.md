# Real-time combat — 2026-10-02

## Current behavior

User explicitly replaced turn-based combat with real-time auto attacks and manual
skills with seconds-based cooldowns. This supersedes earlier I-06/I-07 auto notes.
Catalog rules version is now `mvp-1.1.0` in the unpublished memory-only prototype.

- Server schedules both fighters independently, ticking every approximately 50 ms.
  Basic interval: `max(1, 2.4 - Speed * 0.025)` seconds. Speed 16 = 2 seconds.
  First basic occurs one interval after start. Exact deadline ties use a side
  randomly chosen at battle start. There are no rounds or owner turns.
- Client Battle.Action accepts SKILL only. A click or 1–3 casts immediately after
  server validation, without waiting for or resetting a basic attack. Each unique
  skill ID has a six-second cooldown, displayed as a decimal seconds countdown.
- Wave Guard absorbs one incoming hit or expires after four seconds. Own attacks
  do not clear it. Recasting replaces the shield instead of stacking it.
- Delayed server ticks issue at most one due attack per side and rebase the next
  deadline; no catch-up burst. Lethal damage prevents subsequent attacks.
- Server auto continues with the menu hidden and no client input. Animations are
  nonblocking and can overlap. No client auto scheduler or skill queue remains.
- Valid skills tolerate older observed revisions within the same active battle;
  future revisions, another battle ID, unavailable skills and cooldown spam fail.
  Request-ID replay remains idempotent. Clients cannot specify hit damage/time.
- Snapshots contain the last 24 sequenced combat events. BattleFeed ignores stale
  revisions, duplicate responses and retired matches; recovery does not replay
  prior hits. Effects older than a second are skipped while authoritative HP is
  still applied. Timer-driven wins publish the final profile and stop attacks.
- Existing reservation, reward PREPARE/COMMIT, pending recovery, caps, disconnect
  cancellation and memory-only storage remain in use. Pending rewards are retried
  by the server at most once per second. Different players tick independently.

## Verified

- Rewritten battle/RPC suite: **178 checks**, covering autonomous fight completion,
  exact seconds boundaries, immediate skills, independent attack deadlines, speed,
  shield consumption/expiry, stale revision races, duplicate requests, death,
  forfeit, disconnect, XP/egg capacity, mutation reservations and rate limits.
- Reward faults: 100 repeated callbacks, before-PREPARE outage, lost PREPARE and
  COMMIT responses, takeover fencing and prolonged outage; no reroll/double reward.
- End-to-end domain/RPC journey: hatch → real-time training → level-five Growth
  unlock → mix with the unlocked skill in the inheritance pool.
- BattleFeed: **11 checks** for out-of-order/replayed snapshots and second countdowns.
- Regression: domain **14,322 assertions / 144 world cases**, persistence **5,534
  checks / 400 fault runs**, RPC **44**, eggs **74**, mix **76**, journey **143**.
- luau-analyze passes for changed pure rules, combat service, feed and their tests.
  Roblox client/server entry scripts compile. Rojo builds
  `build/Digievo_WORLD_AUTO_v2.rbxlx` with the new BattleFeed tests.

## Studio walkthrough — not yet verified

1. Stop Play and reopen the rebuilt local place. Start Play; check suite PASS logs.
2. Hatch a pet, walk to the blue pad and start training. Do not press attacks;
   verify both pets attack automatically and there is no round/turn UI.
3. Click a skill or press 1–3 between basic attacks. Confirm immediate damage and
   a countdown starting near 6.0 seconds. Spam cannot bypass it; recast at zero.
4. Cast during a basic animation; effects must not hold up input or HP updates.
   Hide the menu with B and reopen it: combat must have continued.
5. Test a slower turtle against a fox, Wave Guard, victory, loss and forfeit.
   Confirm one reward, no post-death attack, and cooldowns reset for a new fight.
6. Recheck collect/hatch/mix and the child/result card after the fight.

No native Studio rendering/input or multi-client performance result is claimed.
Online persistence and production publishing remain unconfigured. Real-time
balance (including six-second skills and four-second shields) is a prototype
choice to playtest, not a measured balance result.

## World arena follow-up — WORLD AUTO v2

The user screenshot showed the older F-button/round-based build still loaded in
Studio. The new artifact uses a distinct filename and an always-visible WORLD
AUTO v2 menu label to distinguish it from a cached/open older place.

- BattleStage now creates animated pet models in Workspace on TrainingArena,
  replacing the in-menu ViewportFrame. Removed the static display pets from the
  pad to avoid overlapping duplicates. World pets/visual effects are local to
  each player's view; combat results remain server-authoritative.
- Pets face each other, have overhead name/HP/shield bars, hit flashes and floating
  damage numbers. Effects use generation guards when a scene is replaced/cleared.
- Starting a fight hides the inventory menu and frames the world arena with a
  temporary camera. Three seconds after the final result, models/effects are
  cleared, the camera restored, the prompt re-enabled and the pet menu reopened.
- Independent bottom-screen HUD keeps skill clicks/1–3 available during combat,
  including with the menu hidden. Seconds countdowns and progress bars reflect
  server readyAt; no F/basic button or skill queue exists.
- Battle/RPC suite still passes 178 checks; feed suite passes 11. Changed native
  scripts compile, Rojo builds, and built XML is inspected for current scripts,
  the world marker and the absence of the old F/basic button and battle viewport.

Manual checks still required: open the specifically named v2 file, verify its
label, start a fight without pressing an attack button, cast during lunges, check
seconds bars, then verify camera/menu/prompt restoration on win/loss/forfeit and
start another fight. Inspect Studio Output for errors. No native visual test is
claimed by compile/build validation.
