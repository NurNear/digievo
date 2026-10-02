# I-07 Verification — 2026-10-02

Combat scheduling notes below record the earlier implementation. The current
server-driven real-time system supersedes them; see [Realtime results](REALTIME_RESULTS.md).

## Implemented locally

- Four-tab Thai UI with a next-action guide: starter hatch, free egg collection,
  training, mix preview and another training loop. Handles no coins, locked pets,
  full inventories, pending eggs, active combat and uncertain operations without
  recommending a resource-consuming action during pending work.
- Two box pet silhouettes (fox ears/tail; turtle shell/head/feet), eight distinct
  catalog variants with body/accent colors and rarity markings. Shared model
  builder powers collection portraits, committed hatch/mix results, arena pets
  and training-pad scenery. No external assets or new gameplay stats.
- Pet cards show stats, skills and the level-five Growth unlock. Committed results
  show the child model, name, level, stars and skills; uncertain results stay pending.
- World trails/pedestals, E proximity prompts, B menu toggle, automatic basic attacks and
  1–3 skill queue shortcuts. Combat shortcuts respect tab/menu visibility, text focus,
  busy state and cooldown. Server range/ownership checks remain authoritative.
- Day/night/rain lighting uses the existing server world phase; Thai condition
  text also appears in mix previews. Weather is represented by lighting here.
- Battle stage consumes server events in order and defers pushed snapshots during
  requests/animation. Snapshot-only recovery updates directly instead of replaying
  old HP. No combat or economy rule changes.

## Automated verification

- I-07: **143 checks** for first-session guide flow, pending/combat priority,
  empty/full/locked inventories, missing funds, pending eggs and all eight styles.
- I-01: **14,322 assertions / 144 world cases**.
- I-02: **5,534 checks / 400 injected fault runs**.
- I-03: **44 RPC checks**; I-04: **74**; I-05: **76**; I-06: **211** (including auto/RPC integration).
- I-06 includes hatch → battle → Growth unlock → mix via the real RPC/domain
  modules with the memory backend. This is not an end-to-end UI test.
- New pure presentation modules/test suite pass luau-analyze. All new/changed
  Roblox presentation and entry files pass luau-compile.
- Rojo builds `build/RobloxMVP_LocalTest.rbxlx`; JourneyTests is also mapped into
  ServerStorage and runs with the other suites on Studio startup.

## Studio walkthrough — pending

1. Open the generated place and press Play. Verify I-01 through I-07 PASS in
   Output. Inspect the new scenery and menu at normal and narrow window widths.
2. Use the guide to hatch the starter. Wait for the committed reveal; check its
   portrait, Thai name, stats and locked level-five skill.
3. Press B to hide the menu, walk along the gold trails, press E to collect an
   egg and hatch a second pet. Try the same node during cooldown.
4. Follow the blue path, press E, choose a pet and train. Let basic attacks run without input; use 1–3 to queue skills. Check
   lunge/hit/HP order, shield feedback, cooldowns and no extra action from spam.
   Confirm skill shortcuts do nothing while typing in chat or with the menu hidden,
   while automatic attacks continue. Check queue replacement/cancellation and
   ready → in-use → cooldown → ready labels.
5. Win, check coins/XP/egg then train to level five and inspect the Growth skill.
   Also lose/forfeit and start a fresh encounter; no resources should be lost.
6. Open Mix, select two unlocked pets, inspect probabilities and the warning that
   both parents are consumed. Confirm and inspect the committed child/skills.
   Test a locked parent, expired preview and a world phase change before confirm.
7. Return to training with the child. Inspect day/night condition text and light;
   check guide behavior with pending eggs/full inventories where test data permits.

No native Studio rendering, input, multi-client or FPS result is claimed. Native
UI automation is unavailable in this session. O-01 growth/evolution appearance is
still open; these are level-independent prototype models. Online persistence,
publishing, test universe verification and final-art acceptance remain outside
this local implementation result.

## Auto follow-up — 2026-10-02

User requested automatic basics and manual cooldown skills. AutoBattle schedules
one command at a time, waits 1.5 seconds after confirmation/presentation, and
stops at resolving/ended. The queue accepts available skills during a basic
animation, blocks the skill currently being cast, uses the latest battle revision
and drops invalid/finished selections. Server rules and reward authority remain
unchanged. Scheduler suite: **23 checks**; real battle/RPC suite: **211 checks**.
Native Studio animation/input verification is still pending.
