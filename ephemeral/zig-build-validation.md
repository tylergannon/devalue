# Zig codec implementation and validation

User request: build the reviewed package, establish scoped equivalence with upstream and Go, and obtain Claude Opus consensus. Do not introduce elaborate proof machinery. The current target is the basic flat-codec correctness milestone; user sequencing returns to missing features afterward, and full upstream behavioral test fidelity remains required before landing. The authoritative scope is `ephemeral/zig-development-plan.md` and the public profile in `zig/README.md`.

## Runtime evidence

Claude Opus round 02 reached **only nitpicks remain** for this basic milestone.
Both documentation nits (strict reference acceptance and exclusive graph access)
are clarified in the README and coverage note. Review evidence describes the
27-test snapshot; it is not full-feature or landing approval.
One inventory sentence in the review says duplicate object keys are rejected;
the implementation actually keeps the last value in the first key's insertion
position, matching JSON.parse. No review finding relies on that sentence. A native regression added after review checks duplicate-key overwrite, numeric enumeration order and that discarded payloads never invoke revivers; the implementation itself is unchanged.

- `zig build test` uses native tests: independent native encoder construction against upstream-recorded expectations, explicit decoded content/identity checks, self/mutual custom-cycle upstream ports, allocation-failure injection, input ownership/growth, malformed input, deterministic mutations/generated graphs, and bounded-depth errors. All 368 shared cases are enumerated (original 359 plus 9 additions); 35 Zig-profile and 79 upstream-native cases have independent native constructors, with decoded content/topology checks. The upstream ports also include the full five-row sparse allocation matrix and the 49,000-layer prototype attack. Debug and ReleaseSafe both run the native suite; the final count is 28 tests. See `zig-upstream-test-coverage.md` for completed ports and unfinished compatibility work. No test runs Node.
- `ephemeral/zig-consumer` is a fresh public local-path dependency consumer. Its executable constructs aliases/cycles/sparse holes, serializes, parses/inspects identity, and releases its graph/bytes. `codec-comparison/zig-consumer.json` is its output.
- `ephemeral/codec-comparison/main.go` reads the shared fixture corpus and checks parse/re-encode bytes in BOTH maintained Go versions, plus 76 upstream-native built-in fixture documents (the three custom cases are checked natively). It also consumes the real Zig executable output and asserts Go-decoded aliases/self-cycle/holes, and checks all five Zig workload documents. See `codec-comparison/parity.txt`.
- Five workloads are independently built in Zig and Go. `zig-workloads.jsonl` and `go-workloads.jsonl` compare byte-for-byte with `cmp`. Timings are admitted only after parity checks. Input size/expected structure is visible in the two benchmark sources.
- `just test` and `just lint` now include Zig; a separate CI job installs the pinned toolchain and invokes the same recipes. `codec-comparison/gate-rejection.txt` records deliberate test and formatting failures, restored immediately afterward. `runtime-fixture-rejection.txt` also records rejecting corrupted corpus metadata against a warm build cache. The native test Run step always executes because its fixture/pin inputs are read at runtime. No live CI run or release is claimed.

## Performance

Apple M4, Darwin arm64; Zig 0.17.0 ReleaseFast with std.process.Init.gpa (smp allocator), Go 1.27.1 default optimizing compiler and default GC. Five trials per workload/operation, sequential language runs. Build/setup, input graph construction, output equality checks and printing are outside timing. Encode includes new output allocation/release; decode includes all parse work and Zig graph release. Go drops references and GC runs during trials, with a forced GC BEFORE each trial outside timing; Go has no equivalent explicit per-operation free. Different lifetime and sparse representations are material to the comparison. CPU load and allocator choices can change these microbenchmarks.

CSV columns: language, workload, operation, trial, output bytes, iterations, ns/op, allocations/op, allocated bytes/op. Zig counts successful backing allocations and positive resize/remap growth, so arena suballocations do not count separately. Go uses runtime.MemStats deltas. Bytes are cumulative allocation traffic, not retained/peak memory. Small query/sparse Zig and Go query use 100,000 iterations; aliases use 5,000, escape-heavy 1,000, records 500; Go million-length sparse uses 10 because its slice representation necessarily scans/allocates by logical length.

| Workload | Operation | Bytes | Zig ns/op median [min–max] | Go ns/op median [min–max] | Zig allocs / bytes | Go allocs / bytes |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| query | encode | 46 | 271 [268–276] | 563 [558–581] | 3 / 1,317 | 23 / 728 |
| query | decode | 46 | 529 [520–535] | 1,613 [1,581–1,630] | 6 / 6,674 | 49 / 2,210 |
| records | encode | 39815 | 220,273 [219,619–224,299] | 516,704 [512,797–655,377] | 13 / 1,401,133 | 16,035 / 674,500 |
| records | decode | 39815 | 310,494 [309,194–311,843] | 1,354,187 [1,342,590–1,649,146] | 22 / 3,855,408 | 35,064 / 2,094,016 |
| aliases | encode | 2025 | 12,985 [12,860–12,998] | 14,300 [14,285–14,500] | 5 / 13,023 | 27 / 9,992 |
| aliases | decode | 2025 | 42,020 [41,773–42,073] | 82,564 [80,985–83,910] | 14 / 327,072 | 1,047 / 91,514 |
| escapes | encode | 22004 | 41,865 [41,332–42,936] | 47,139 [45,287–47,412] | 6 / 70,336 | 25 / 138,281 |
| escapes | decode | 22004 | 46,364 [45,772–49,699] | 147,790 [145,112–151,263] | 6 / 51,808 | 13 / 135,428 |
| sparse | encode | 47 | 264 [263–265] | 549,150 [543,529–590,254] | 3 / 1,317 | 24 / 744 |
| sparse | decode | 47 | 492 [467–497] | 1,208,487 [1,165,279–1,884,062] | 5 / 3,718 | 35 / 16,009,889 |

The decoder now uses a scanner token tape instead of a generic JSON value tree.
Collection lookups use standard hash tables plus ordered views. These refreshed
measurements describe the current architecture; they are diagnostics, not a speed
claim or an optimization readiness gate. Arena/token/storage overhead still varies
by workload. General allocation and performance tuning is deferred until after
this correct, usable first version.

## Reproduce

```sh
just test
just lint
mise exec -- zig build --build-file zig/build.zig test -Doptimize=ReleaseSafe
mise exec -- zig build --build-file ephemeral/zig-consumer/build.zig run > ephemeral/codec-comparison/zig-consumer.json
mise exec -- zig build --build-file zig/build.zig bench -Doptimize=ReleaseFast -- dump > ephemeral/codec-comparison/zig-workloads.jsonl
cd ephemeral/codec-comparison
go run .
go run . dump > go-workloads.jsonl
cmp zig-workloads.jsonl go-workloads.jsonl
go run . bench > go-bench.csv
cd ../../zig
mise exec -- zig build bench -Doptimize=ReleaseFast > ../ephemeral/codec-comparison/zig-bench.csv
```

No codec runtime dependency, Node in native tests, generated claims ledger, transport integration, merge, release or publishing is part of this deliverable. The supported profile and explicit acceptance exceptions are public; full JS devalue API equivalence is unfinished. Typed views, expressions, async, and other profile differences are explicit remaining work before landing, not waived tests. Basic-milestone readiness depends on independent implementation review, not the earlier plan consensus.
