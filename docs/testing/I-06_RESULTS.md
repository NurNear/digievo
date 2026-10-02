# I-06 Verification — 2026-09-16

Historical turn-based verification. Current combat was replaced with server-driven
real time on 2026-10-02; see [Realtime results](REALTIME_RESULTS.md).

## Implemented

- Server-owned TRAINING battles with C01/C02 at equal probability, level one,
  zero stars, 60% initial enemy HP, and enemy BASIC commands only.
- Speed orders each round. The first tie is a 50/50 draw; subsequent tied rounds
  alternate the opening side. Each fighter gets one command per round, with
  immediate termination at zero HP and no defeated-fighter retaliation.
- Skill availability comes from unlocked slots, deduplicated by skill ID.
  Cooldowns count owner turns (use at 1, unavailable at 2/3, ready at 4).
  Shield absorbs one incoming hit or expires at the next owner-turn start.
- Battle.Start/Get/Action/Forfeit validate shape, identity, training distance,
  battle revision and skill availability. Action/forfeit share a 2/s burst-2
  bucket. Replaying a request does not execute another turn or roll again.
- A repository reservation blocks economic intents during combat/resolution;
  unexpired economic intents and uncertain/prepared mutations block battle start.
  Locked creatures may train. Loss/forfeit/disconnect do not remove resources.
- Winning grants 20 coins, up to 20 XP, and one win toward Potential stars.
  Growth unlocks at level five; XP/stars keep existing caps. The first victory
  guarantees one egg without another draw; subsequent victories roll 20% once.
  Full egg inventory stores the reward in pendingEggRewards.
- Internal reward IDs are `reward:<battleId>` with a battle-bound fingerprint.
  The existing PREPARE/COMMIT path commits the complete reward in one profile.
  A resolving match blocks new work until commit is confirmed. Battle.Get
  recovers unknown outcomes and retries the same frozen reward without rerolling,
  including when a pre-PREPARE outage outlasts the original intent.
- Added a blue training pad and Thai UI for per-creature training, HP, shield,
  rounds, skills/cooldowns, combat events, forfeit and pending reward resolution.
  Profile updates show new level, stars and XP after reward commit.

## Verified locally

- `tests/battle-run.luau`: **188 checks pass**, using Luau 0.738 and MemoryStore.
- Tests cover speed/tie order, enemy automatic actions, cooldown boundaries,
  shield absorption/expiry, skill deduplication, validation/replay, economic
  reservation, loss/forfeit/disconnect, XP/star caps, Growth unlocking, first and
  later egg rewards, full inventory, numeric overflow and a hatch → train →
  Growth unlock → mix journey through the RPC dispatcher.
- Reward fault tests cover 100 repeated storage callbacks, outage before PREPARE,
  lost PREPARE response, lost COMMIT response, recovery after intent expiry and
  new-session takeover after PREPARE. Rewards apply once with no reroll.
- Regression: I-01 **14,322 assertions / 144 world cases**, I-02 **5,534 checks /
  400 fault runs**, I-03 **44**, I-04 **74**, I-05 **76** pass.
- luau-analyze: no diagnostics for BattleService, modified repository/dispatcher
  and the battle suite/runner. Both Roblox entry scripts compile for syntax.
- Rojo 7.7.0 builds `build/RobloxMVP_I06_LocalTest.rbxlx` with BattleTests mapped
  into ServerStorage and the new gameplay module/client UI.

## Studio walkthrough — pending

1. Open `build/RobloxMVP_I06_LocalTest.rbxlx`, press Play and check Output for
   I-01 through I-06 PASS, including `I-06 PASS: 188 checks`.
2. Hatch the starter egg. Walk onto the blue training pad and press the training
   button under the creature. A locked creature should also be allowed to train.
3. Choose a species skill, then BASIC while its cooldown runs. Check HP, turn
   order, combat events and that buttons for unavailable Growth skills are absent.
4. Win a match. Coins should rise from 20 to 40, the fighter should reach level
   two, and the first victory should grant one egg. Economic actions should work
   again after reward confirmation.
5. Train the same creature to four wins: Growth unlocks at level five. At five
   wins an egg-born creature gains its first star. Check the newly available skill.
6. Start another match and forfeit. No resources/progression should be lost.
   Start again with full player HP (an enemy may attack before the first choice).
7. Collect/hatch a second creature and mix after training, checking the preview's
   inherited Growth skill. Verify inventory/coins update after confirmation.

No Studio Play or manual UI result is claimed yet. There is no automated native
UI control available for Roblox Studio in this session. Multi-client networking,
real DataStore/two-server recovery, performance and child playtest remain unverified.
This place is unpublished and memory-only; stopping Play discards all test data.

## Simplified UI and box pets — 2026-10-02

- Replaced the single long menu with Pets, Eggs, Mix and Battle tabs, larger
  action buttons, creature display names and a width-constrained panel.
- Added a client-only ViewportFrame arena with two block pets, element colors,
  HP bars, attack lunges, hit flashes, impact bursts and damage/shield text.
- Presentation consumes server events in order (including an enemy opening
  attack). Battle pushes are deferred during requests/animation; action buttons
  stay disabled until presentation completes. Server combat rules are unchanged.
- Verified: both client files compile; battle suite passes 188 checks; Rojo builds
  `build/RobloxMVP_LocalTest.rbxlx`; `git diff --check` passes.
- Studio visual/manual verification remains pending. Check all four tabs at
  desktop and narrow window sizes, hatch then train, use skills through cooldown,
  observe both attack orders, shield absorption, defeat/victory and forfeit.
  Verify mix selection/preview/confirmation and return to Pets after rewards.
