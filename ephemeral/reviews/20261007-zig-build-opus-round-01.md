# Adversarial review — Zig flat codec implementation and proof, round 01

Reviewer: Claude Opus 5.5 (adversarial-review skill), 2026-10-07.

## Target

The uncommitted Zig package and proof on branch `codex/zig-development-setup`
(HEAD `90d0337`, plus working tree): `zig/` (build, sources, tests,
`testdata/flat-golden.json`, README, bench), recorder changes under
`v5/testdata/record/`, the re-recorded `v5/testdata/golden.json`, the
`justfile` and `.github/workflows/zig.yml` gates, and the evidence in
`ephemeral/zig-build-validation.md`, `ephemeral/codec-comparison/` and
`ephemeral/zig-consumer/`.

Scope came from the repository `CLAUDE.md`/`AGENTS.md`, `zig/AGENTS.md`,
`ephemeral/zig-development-plan.md` (the approved plan),
`ephemeral/zig-build-validation.md` (the user request restated there: build
the reviewed package, establish scoped equivalence with upstream and Go, no
elaborate proof machinery), and the pinned upstream source. The launch prompt
did not narrow scope, so I ignored nothing.

**The tree changed during the review.** Another session edited
`zig/src/*.zig` and `zig/tests/*.zig` at 17:43–17:44 (raw reducer-name
interpolation, an extra Set case in the allocation-failure test) and
`zig/build.zig` at 17:48 (`run.has_side_effects = true`). Every finding below
was re-checked against this final snapshot (SHA-256 prefixes):

| File | SHA-256 |
| --- | --- |
| `zig/src/root.zig` | `4ba69e3bbf7a` |
| `zig/src/encode.zig` | `0afb07305c17` |
| `zig/src/decode.zig` | `7bb655ed2ee0` |
| `zig/src/primitives.zig` | `c4c50c1b86a8` |
| `zig/tests/tests.zig` | `0a46d64b6f64` |
| `zig/tests/profile.zig` | `5573b4e1be36` |
| `zig/tests/robustness.zig` | `18165e8283d5` |
| `zig/build.zig` | `e43f7cd34f6d` |

## Evidence inspected

- Every Zig source and test file; `build.zig`, `build.zig.zon`, `README.md`,
  `bench.zig`, `testdata/flat-golden.json`; the consumer under
  `ephemeral/zig-consumer/`; `codec-comparison/{parity.txt,gate-rejection.txt}`;
  the `justfile`, CI and recorder diffs; and the worklog's implementation
  section.
- Pinned upstream: `v5/node_modules/devalue` (version 5.9.4, matching
  `v5/package.json`): `src/stringify.js`, `src/parse.js`, `src/utils.js`,
  `src/constants.js`, `src/operations.js`.
- Runs, with Zig 0.17.0 through `mise exec`:
  - `zig build test` with a fresh `--cache-dir`: 15/15 pass. `just test` and
    `just lint` exit 0, Go and Zig both.
  - A scratch fuzz (outside the repo) of 200,000 f64 bit patterns and 100,000
    Dates across ±8.64e15 ms, comparing Zig `stringify` with pinned JS
    `stringify` and then re-parsing: **0 mismatches**. Number and Date
    spelling look sound.
  - The hand-typed expected bytes in `tests.zig:19`, `profile.zig` (the
    built-in values and boxed tests): checked against pinned JS, and **all
    match**.
  - Scaling probes (findings 1 and 4) and a stale-cache probe (see
    "Resolved during review").

## Findings

### 1. Critical — Decoding and graph construction are quadratic in collection size; a sub-megabyte valid document costs tens of seconds of CPU

**Type:** verifiable bug (resource exhaustion), plus an incorrect
implementation of the plan's robustness requirement.

Every keyed insertion does a linear scan, and some also do a front insertion:

- `root.zig:128-142` `Graph.put`: a linear key-equality scan on every put,
  then a linear position scan plus `insert` (memmove) for array-index keys.
- `decode.zig:109-120` sorts object keys by insertion into a list, with a
  linear position scan and `insert`. That is O(n²) again for integer keys,
  before `put` runs.
- `root.zig:191` `mapPut` and `root.zig:201` `setAdd`: linear `equal` scans
  over all existing entries.
- `root.zig:168-174` `arrayPut`: the fast path only covers increasing
  indices. Out-of-order sparse indices scan linearly and insert at the front.

Reproduction (scratch program, ReleaseFast, Apple M4; `d.parse` time only):

| Document (valid devalue) | n | bytes | Zig parse | upstream JS `parse` |
| --- | ---: | ---: | ---: | ---: |
| `[["Set",1..n],0..n-1]` | 80,000 | 937,793 | 2,321 ms | 5.7 ms |
| plain object, keys `k0..k(n-1)` | 80,000 | 868,895 | 4,560 ms | 20.1 ms |
| plain object, integer keys in descending JSON order | 80,000 | 788,899 | **25,765 ms** | 5.8 ms |
| `[-7,…]` sparse array, descending indices | 80,000 | 708,904 | 1,426 ms | — |

Doubling n roughly quadruples the time in every row: 10k→20k→40k→80k gives
351→1,441→6,267→25,765 ms for integer keys.

A smaller amplification compounds this. `Graph.validate` re-runs
`utf8ValidateSlice` on the full string at every reference, in `put`,
`arrayPut`, `mapPut` and `setAdd` during decode, and in `flatten` before its
cache lookup during encode (`encode.zig:78`). So N aliases of an L-byte string
cost O(N·L), where upstream costs O(N). A 1 MiB string referenced 4,000 times
takes 107 ms to parse and 240 ms to stringify in Zig, against 1.2 ms and
5.8 ms in JS.

**Impact.** Devalue documents are request and response bodies: SvelteKit
remote functions and form data, and server data read by the planned native
client. Upstream treats this class as a security bug (`stringify.js:196-197`;
`parse.js:236-238`: "createSparseArray is responsible for not allocating
storage proportional to it"). The plan's milestone 4 requires "rejection or
successful bounded parsing" and that operations not "scan proportional" to
sizes upstream doesn't scan. Map/Set are specified with SameValueZero, which
JS implements with hashing. The benchmark workloads (`bench.zig`: a 3-key
object, a 1,000-element array) never build a collection large enough to show
this, so the validation report's performance claims don't cover it. The README
says only that input and population are "bounded by available memory". The
worklog's "removed measured quadratic decode scanning" fixed the
increasing-index array case only.

### 2. Issue — The decoder builds a generic `std.json.Value` tree and then a second devalue graph, which the approved plan says to avoid

**Type:** incorrect implementation (plan architecture).

`decode.zig:34` calls `std.json.parseFromSlice(std.json.Value, …)`, copies the
items into `dec.values` (`decode.zig:45`), and hydrates the graph from that
tree. The plan's architecture direction (`zig-development-plan.md:108-110`)
says: "Use Zig's JSON scanning/parsing primitives where useful; avoid
constructing a generic JSON value tree and then a second devalue tree." The
worklog records this as a deliberate "first decoder" choice, but neither the
plan nor the README was amended. The plan consensus that the validation report
relies on was reached on the opposite design.

The cost shows in the project's own numbers (`zig-build-validation.md`
table):

| Workload | Input | Zig decode traffic | Ratio | Go decode traffic |
| --- | ---: | ---: | ---: | ---: |
| records | 39,815 B | 5,271,186 B/op | ~132× | 2.09 MB |
| aliases | 2,025 B | 459,828 B/op | ~227× | 91.5 KB |

The extra bracket-counting pre-pass (`decode.zig:9-30`) exists only to bound
nesting before the tree is built. A `std.json.Scanner`-driven hydrate is not
"elaborate proof machinery". It is the design the plan approved.

Either implement the plan's direction, or amend the plan and get consensus on
the deviation explicitly. A worklog line is not a substitute for the plan
change.

### 3. Issue — Milestone-4 property coverage and the malformed-input contract are thinner than the plan requires

**Type:** incomplete requirement.

- The plan (`zig-development-plan.md:218-221`) requires "deterministic
  mutation/property coverage **seeded from the corpus** … and
  semantic/identity-preserving encode/decode for generated supported graphs".
  - `robustness.zig` "deterministic input mutations" uses one 45-byte
    hand-written seed with six replacement bytes. None of the 368 shared or
    35 Zig-only corpus documents seeds it.
  - "deterministic generated graphs" generates only a 20-element array mixing
    numbers and one self-referential object. There are no strings, Map, Set,
    sparse arrays, tagged values or nested aliases.
  - Finding 1 is exactly the kind of defect that corpus-seeded or size-varying
    generation would have exposed.
- The malformed-input test accepts `InvalidDocument or DepthLimit` for every
  case (`robustness.zig:29`), so no error class is pinned per input. The plan
  requires that "native errors distinguish invalid documents, unsupported
  values, caller callback errors, and allocation failure"
  (`zig-development-plan.md:80-82`). In practice, the malformed self-boxing
  documents `[["Object",0]]` and `[["Object",1],["Object",0]]` return
  `DepthLimit`, a resource error, after recursing 256 levels, not
  `InvalidDocument`. Upstream rejects them immediately as invalid input
  (`parse.js:139-147`). The README says malformed tag reference types are
  rejected, which implies `InvalidDocument`.
- The plan's "Lifetime and growth" row asks to "encode repeatedly without
  mutating the input graph". No test asserts that the graph is unchanged after
  `stringify`.

### 4. Nitpick — The proof record has drifted from the tests, and some encoder expectations are not recorded from upstream

- `zig-build-validation.md` says "34 Zig-profile cases have independent native
  constructors", and the worklog says the same. `profile.zig` asserts 35
  (`expectEqual(@as(usize, 35), …)`) after the `custom_name` regression was
  added. Update the report.
- The native-construction expectations for BigInt, Map, Set, RegExp flags,
  ArrayBuffer, boxed Number/String/BigInt/-0 and null-prototype objects
  (`profile.zig` "built-in values…" and "boxed primitives…") and
  `tests.zig:19` are hand-typed. The plan's test contract asks for
  "upstream-recorded bytes" and says "Additional expectation bytes come from
  pinned JavaScript". I checked these strings against devalue 5.9.4 and they
  match, so there is no parity defect. Their provenance is just not
  reproducible through `just record`. Moving them into `zig-values.mjs` would
  close this at no cost.
- The shared-corpus test (`tests.zig:32-54`) is round-trip only. I confirmed
  that replacing a golden document with a different valid document
  (`["corrupted"]`) still passes. This is the known, plan-acknowledged
  limitation. It means the encoder evidence for the shared families rests on
  the native tests above, not on the 368-case figure.

### 5. Nitpick — The reducer ordering contract differs silently from upstream's key order

Upstream orders reducers by `Object.getOwnPropertyNames(reducers)`
(`stringify.js:82`), which puts integer-like names (`"1"`, `"10"`) first in
numeric order, then other names in insertion order. Upstream names are also
unique. Zig runs reducers in slice order and allows duplicate names. The
README states "supplied order" but doesn't warn that a caller porting a JS
reducer object with integer-like keys must reorder it to keep output
byte-identical. One README sentence would suffice.

## Resolved during review (not counted)

- **Stale cached test results.** In the snapshot before 17:48, the `test` run
  step had no declared inputs for the runtime-read fixtures. In a scratch copy,
  after editing `../v5/testdata/golden.json` and the `v5/package.json` pin,
  `zig build test` printed `run test cached` and succeeded. A fresh cache
  showed 2 failures. So `just record v5` followed by `just test` could report
  a stale pass locally (CI, with no cache, was unaffected). The concurrent
  edit adding `run.has_side_effects = true` (`zig/build.zig`) fixes this: the
  same scratch probe now re-executes the run step.
- **Reducer-name escaping.** The 17:43 edit switched reducer names to raw
  interpolation, matching `stringify.js:125`. The `custom_name` fixture
  (`"Name< "`) now passes against upstream bytes.

## Not defects (checked)

- Traversal and slot order: reducers after identity registration, sentinel
  bypass, the dense/sparse cost rule (`stringify.js:248-267`), boxed values as
  flattened references (`stringify.js:168`), Map/Set edge order, and
  null-prototype layout all match upstream.
- Reviver precedence, inline-payload pushing, cached-payload short-circuit,
  the pending guard and double invocation all match `parse.js:80-111`, and
  both `circularCustomTypes` shapes are ported.
- Object key enumeration (array-index keys `0..2^32-2` first) matches the
  spec and upstream `is_valid_array_index`.
- Gates: `just test`/`just lint` include Zig, and CI runs both recipes.
  Recorded deliberate-failure probes exist. No live CI run is claimed.
- The consumer uses only the public path dependency.

## Outcome

material findings remain
