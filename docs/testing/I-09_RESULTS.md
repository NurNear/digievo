# I-09 measurement tooling — 2026-10-02

Status: instrumentation ready; performance acceptance has NOT been measured.
I-08 online fault acceptance and I-07 manual gameplay remain open.

## Enable in the unpublished Studio place

1. Before Play, add a boolean Workspace attribute `MeasurePerformance = true`.
   Leave `RunSafetyTests` false to avoid running the heavy fault suite during load.
2. Start a server with four clients. Set the measured client to a 1920×1080
   viewport and graphics level 5; record actual viewport, graphics setting,
   client identity, active GPU, and network RTT. The report includes viewport;
   it does not configure it or establish network RTT.
3. Play for 15 minutes with a full 30-pet collection. Exercise normal collection,
   hatch/mix, auto battles and immediate skills. Capture at least 200 commands.
4. Copy `I-09 METRICS` JSON lines from each client and server Output separately.
   Reports emit every 60 seconds after enablement. Keep the final full-duration
   report and timestamps; do not average percentile values across reports.
5. Disable the attribute and repeat a comparable run to evaluate observer overhead.

All metrics are opt-in and local; no telemetry uploads or profile writes are added.
Each series retains at most 65,536 recent samples. `count` is lifetime count,
`retained` is the window size, and p95 is the nearest-rank percentile of that
window. At high frame rates this can be shorter than 15 minutes; report the
window limitation rather than claiming full-run p95. Sorting/reporting can itself
add overhead. Startup/loading frames are included, without a warmup filter.

## Available measurements

- `frameMs`: RenderStepped interval, including stalls; not GPU execution time.
- `rpcMs.<action>.<status>`: first send to first received response, recorded before
  the client's 50 ms polling loop consumes it. Includes retransmission delay;
  duplicate responses do not add samples. Never-answered requests have no completed
  latency sample, so record timeouts/pending requests separately during the run.
- `dispatchMs`: server dispatcher duration across all actions/statuses; not network
  RTT, durable transaction duration or isolated prepare/commit timing.
- `joinMs.<status>`: memory-session initialization duration; not end-to-end client
  profile-ready latency.
- `profileBytes`: JSON-encoded profile size at join only; not full-inventory size.

The harness uses simulated memory storage. Durable latency, separate PREPARE and
COMMIT latency, DataStore budgets, full-profile encoded size, input-to-visible
feedback, 200 mutations and 50 joins require additional controlled measurements.
No synthetic timing substitutes for these acceptance results.

## Host inventory (not a performance result)

- MacBookPro16,1; six-core Intel Core i7 2.6 GHz; 16 GB RAM.
- Intel UHD Graphics 630 and AMD Radeon Pro 5300M (4 GB VRAM).
- macOS 26.6.2 (25G83).
- Connected displays reported 3072×1920 and 1920×1080. The GPU and viewport used
  by an actual Studio run have not been verified.

## Tooling verification

`tests/metrics-run.luau` passes nearest-rank p95, window eviction, total versus
retained counts, series isolation, snapshot isolation, zero and invalid values.
Pure module/tests pass luau-analyze; instrumented scripts compile; Rojo builds.
The default run does not connect frame sampling or start reporting timers.

NFR targets remain proposed: visible feedback p95 ≤100 ms, battle response ≤500 ms,
frame interval ≤16.7 ms; durable mutations ≤3 s and profile ready ≤8 s under the
specified backend/network conditions. No pass/fail decision on these targets has
been made. Native four-client testing is still required.
