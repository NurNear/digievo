# I-05 Verification — 2026-09-14

## Implemented

- Mix.Preview validates two distinct, owned, unlocked creatures and returns the
  existing domain distributions for rarity, candidate, stars/reset and inheritance.
  Preview IDs are server-generated, user-bound, expire after 60 seconds, and bind
  profileVersion and full world phase ID. Preview performs no write or RNG call.
- Mix.Commit preflight validates without RNG. Execute rolls one child outside the
  backend callback, removes both parents and deducts 20 coins in one profile plan.
  Child XP is zero; inherited skill and starting stars follow the domain rules.
- A repository validator checks actual profile/world freshness again immediately
  before PREPARE. Previously accepted prepared operations and committed receipts
  bypass preview validation, allowing recovery after expiry or a world transition.
- Ownership, locks, active-battle guard and funds are validated. The battle guard
  is injectable and tested; the local host has no active battle service until I-06.
  Mixing at creature capacity is allowed because the resulting count decreases.
- UI separates lock buttons from parent selection; displays price, parent loss,
  all candidate probabilities, conditional star/skill outcomes and reset flags.
  Confirmation is explicit. Selection/profile/world changes and expiration clear
  the displayed preview; stale requests require a new preview and confirmation.
- Fixed ViewModels.mixPreview copying string IDs with table.clone on each string.
  Parent IDs are now copied as an array.

## Verification

- I-05: **76 checks pass** using Luau 0.738 and the in-memory backend.
- Covers input shape, identity isolation, locks, insufficient funds, battle guard,
  full collection, zero RNG during preview/create, create replay, 100 backend
  callback repetitions, exact parent/coin consumption, level-one result,
  expiry/world changes, world transition inside the storage call, lost PREPARE
  response, session takeover after expiry, pre-PREPARE outage and no rerolls.
- Regression: I-01 **14,322 assertions / 144 world cases**, I-02 **5,534 checks /
  400 fault runs**, I-03 **44 checks**, I-04 **74 checks** pass.
- luau-analyze: no diagnostics for changed pure server modules and the I-05 suite.
- Both Roblox entry scripts pass luau-compile syntax verification.
- Rojo 7.7.0 builds the local test place with MixTests in ServerStorage.

## Studio Play and user-reported mixing walkthrough

Open `build/RobloxMVP_I05_LocalTest.rbxlx` and press Play. This is a newly built
place, so an already-open I-04 tab will not automatically gain these changes.
Confirm `I-05 PASS: 76 checks` in Output, then:

1. Hatch the starter egg; walk to a gold node, collect and hatch a second egg.
2. Select both unlocked creatures in the collection and press ดูโอกาสผสม.
3. Inspect candidate probabilities, stars/inheritance and the 20-coin price.
4. Confirm. Two parents should become one level-one child and coins fall 20 → 0.
5. In a fresh Play session, obtain another preview, wait over 60 seconds and
   confirm that it must be refreshed. Also check the separate lock controls.

User pressed Play on 2026-09-14. The latest Studio log
`0.738.0.7381393_20260914T084601Z_Studio_211aa_last.log` records I-01 through
I-05 PASS at 08:46:31–08:46:34 UTC, including I-05 76 checks, followed by starter
profile initialization. No project script errors or stack traces were found in
the inspected latest output. The user subsequently confirmed testing the requested
UI mixing walkthrough, with no issue reported. This is user-reported verification
of selecting two parents, viewing probabilities and confirming the mix; it is not
automated visual inspection. Manual expiry and multi-client checks are not confirmed.
No online DataStore, real two-server recovery, load test or published experience
is claimed. Recovery tests use memory simulations. Battle gameplay remains I-06.
