# Adversarial review — Zig flat codec, round 02

Reviewer: Claude Opus 5.5 (`/adversarial-review`), 2026-10-07.

## Target

The entire current Zig work in the `codex/zig-development-setup` worktree
(uncommitted, on top of `0e9b8ba`): the `zig/` package (`src/`, `tests/`,
`build.zig`, `README.md`, `AGENTS.md`), the shared and Zig-specific fixtures and
their recorder (`v5/testdata/record/*`, `zig/testdata/*`), the `just`/CI
wiring, and the proof documents. Checked against:

- the repository instructions (`CLAUDE.md`, `zig/AGENTS.md`);
- `ephemeral/zig-development-plan.md`, including the uncommitted amendments.
  These make full upstream behavioral fidelity a landing requirement, but not
  an immediate one; defer performance tuning, so it is not a gate; and put
  basic flat-codec correctness and usability first;
- `ephemeral/zig-build-validation.md` and
  `ephemeral/zig-upstream-test-coverage.md`;
- pinned devalue 5.9.4 (`v5/node_modules/devalue/src/parse.js`,
  `stringify.js`) and the upstream tests from the GitHub tag
  (`ephemeral/upstream-5.9.4/*.test.js`);
- the round-1 review, `ephemeral/reviews/20261007-zig-build-opus-round-01.md`.

The caller's prompt did not narrow the scope. It only set the artifact path
and a read-only boundary, and both are valid operating constraints.

Snapshot reviewed (SHA-256 prefix). Every hash was re-checked after the probes
and tests below ran:

| File | SHA-256 |
|------|---------|
| zig/src/decode.zig | 0f1b0ce4948a |
| zig/src/encode.zig | d81a7c4c57f3 |
| zig/src/primitives.zig | c4c50c1b86a8 |
| zig/src/root.zig | 8a11443df292 |
| zig/src/wire.zig | 9564f0a19114 |
| zig/tests/graph_expect.zig | d20682ddc7c1 |
| zig/tests/profile.zig | 0f34232bab44 |
| zig/tests/robustness.zig | ba6cc8ee56fd |
| zig/tests/tests.zig | 6e7541b3c4ed |
| zig/tests/upstream.zig | ac7948dc40c0 |
| zig/build.zig | e43f7cd34f6d |
| zig/README.md | 8d80fd37a880 |
| zig/testdata/flat-golden.json | 26eaa8d3e42a |
| zig/testdata/upstream-flat-golden.json | 69d8b237d81d |
| v5/testdata/golden.json | d8d72155323d |

## Evidence inspected

- **Implementation, read in full.**
  - `wire.zig`: a token tape over `std.json.Scanner`. It enforces a depth
    limit of 256 and accepts references only as finite integers in
    `-7..2^63`.
  - `root.zig`:
    - `Object` and `Array` keep hash lookups and lazily sorted ordered views
      (`node`, `propertyLess`).
    - `Map` and `Set` are hashed with `ValueContext`, using SameValueZero
      semantics: `-0` is normalized and `NaN` is canonical.
    - `Graph.bytes` caches validation and hash data for strings and BigInts
      the graph owns.
  - `decode.zig`:
    - The object path rejects duplicate keys and `__proto__`.
    - The reviver branch matches upstream's order: the `hydrated` check comes
      before the `hydrating` guard.
    - The `Object` tag, the sparse path, and the dense path with `-2` holes.
  - `encode.zig`:
    - Traversal order, primitive deduplication, and reducer dispatch.
    - The sparse-encoding rule `(L-P)*3 > 4+d+P*(d+1)`, checked against
      upstream `stringify.js`.
- **Proof.**
  - `tests/upstream.zig` has 79 natively built upstream fixtures. Each is
    checked against the bytes the pinned recorder produced, then decoded and
    compared by handle bijection in `graph_expect.zig`. It also ports these
    upstream cases:
    - the invalid-input table;
    - sparse type confusion, asserting the reviver is called 0 times;
    - the 49,000-layer prototype attack;
    - the full `sparseDoSCases` matrix;
    - the out-of-bounds index cases.
  - `tests/robustness.zig` covers:
    - malformed input that must fail with exactly `InvalidDocument`;
    - excluded tags that must fail with `UnsupportedValue`;
    - allocation-failure injection through a no-growth backing allocator;
    - depth limits;
    - 40 generated graphs that between them cover every node family;
    - mutations seeded from all three corpora;
    - 20k reverse-ordered collections;
    - 4,000 aliases of a 1 MiB string;
    - repeated encodes leaving the graph unchanged.
  - `tests/tests.zig` round-trips all 368 shared cases. The upstream
    `index.test.js` fixture groups were enumerated (primitives, boxed, basics,
    strings, cycles, repetition, misc, plus the uvu tests at lines 1257–1846)
    and compared with the coverage note.
- **Recorder.** `record.mjs` writes all three corpora from a single devalue
  pin. `upstream-values.mjs` holds the 79 inputs.
- **Gates.**
  - `zig build test --summary all`: 27/27 passed. Earlier in this round,
    `just test` and `just lint` exited 0, and Debug and ReleaseSafe each
    passed 27/27, all on this same snapshot.
- **Scaling probes.** Built ReleaseFast against `zig/src/root.zig` from the
  scratchpad; nothing in the repository was touched. Parse time in ms, at
  10k / 20k / 40k / 80k entries:

  | Shape | 10k | 20k | 40k | 80k |
  |-------|-----|-----|-----|-----|
  | Set of distinct numbers | 4 | 5 | 10 | 16 |
  | Object with distinct string keys | 2 | 3 | 6 | 13 |
  | Object with descending integer keys | 1 | 3 | 6 | 12 |
  | Sparse array with descending indices | 0 | 1 | 2 | 5 |

  All four shapes scale linearly. Round 1 measured clearly quadratic growth on
  the same probes. Aliases of a 1 MiB string at 1k / 2k / 4k references:
  parse took 2 / 1 / 3 ms and stringify 4 / 4 / 5 ms, and the output was
  byte-identical to the input.
- **Acceptance probe.** I ran the same ten edge documents through the pinned
  devalue 5.9.4 under Node, outside any test, and through the Zig `parse`. See
  finding 1.
- **Other files.**
  - `ephemeral/rework-root.py` is a one-off source-rewrite helper that
    introduced the hashed `Object`/`Array`/`Map`/`Set` structures. It is
    under `ephemeral/`, as `CLAUDE.md` allows.
  - The `zig/AGENTS.md` diff now points readers at `README.md`.

## Round-1 findings: status

| # | Round-1 finding | Status |
|---|-----------------|--------|
| 1 | Quadratic decode and graph construction | **Resolved.** Lookups are hashed and ordered views are sorted lazily (`root.zig:154-229`). The probes above scale linearly. |
| 2 | Generic `std.json` tree held in memory | **Resolved.** `wire.zig` uses a token tape with borrowed strings. The validation report's refreshed allocation figures are consistent with it. |
| 3 | Thin mutation and generated coverage | **Resolved.** Mutations are now seeded from all three corpora (`robustness.zig:365-395`). Generated graphs cover every family and are checked against independently built expected topology (`robustness.zig:222-273`). |
| 4 | Error classes not pinned | **Resolved.** The malformed list asserts exactly `InvalidDocument` (`robustness.zig:33-40`), and a boxed cycle is `InvalidDocument`. |
| 5 | Reducer order and fixture-count inconsistencies | **Resolved.** The README documents that reducer names follow `Object.getOwnPropertyNames` order. The 35-case count matches. Fixtures that were typed by hand are now recorded through `native_*` entries in `upstream-values.mjs`. |

## Findings

### 1. nitpick — Zig rejects reference values upstream accepts, and the record of it is unclear

Upstream `hydrate` reads any integer slot it does not recognise as a sentinel
as `values[i]`, which is `undefined` when out of range. It also coerces
non-integer indices. As a result, pinned devalue 5.9.4 accepts every one of
these documents (Node, against `v5/node_modules/devalue`):

```
[[-8]]               => [undefined]
[[0.5]]              => [undefined]
[["Object",-2]]      => {}
[{"a":-9}]           => {a: undefined}
[["Set",-8]]         => Set {undefined}
[["Map",-9,1],2]     => Map {undefined => 2}
```

Zig `parse` returns `InvalidDocument` for all six. The scratchpad probe is
`acc.zig`. `zig/tests/robustness.zig:33` pins `[[-8]]` as a required rejection,
along with `[[-7,4,0.5,0]]`, which is the same shape inside a sparse array.

Rejecting these documents is a reasonable safety choice, and the plan allows it
on one condition (`zig-development-plan.md:105-107`): "record the exception
explicitly instead of claiming identical acceptance behavior". The current
record does not meet that condition:

- The only mention is the second half of the base64 bullet
  (`zig/README.md:59-60`): "malformed tag arity/reference types are rejected
  even where JavaScript is permissive". A reader takes that as a base64 or
  arity rule. It does not say that well-typed negative, fractional or
  out-of-range numeric references are rejected, although upstream reads them
  as `undefined`.
- The "explicit profile differences to reconcile" list in
  `ephemeral/zig-upstream-test-coverage.md:79-81` names BigInt, Date, base64,
  RegExp, UTF-8, depth and reducer names, but not references.

**Impact.** No encoder can produce these documents, so encoding parity is
unaffected. But a consumer reading the README could believe decode acceptance
matches upstream for references, and the full-fidelity reconciliation list
omits a known divergence.

**Fix direction.** Add a separate README bullet for reference values, and the
matching entry in the coverage note's reconciliation list.

### 2. nitpick — `stringify` and `node` change shared graph state, so concurrent read-only use is a data race

`Graph.node(*Graph, …)` (`root.zig:154-170`) sorts properties and elements in
place the first time it sees an unsorted collection, then clears the
`ordered` flag. `stringify(…, graph: *d.Graph, …)` (`encode.zig:27`, `:90`)
goes through `node`. If a decoded or freshly built graph that has never been
sorted is encoded from two threads at once, both threads reorder the same
`ArrayList` and rebuild the same lookup. That is a data race, even though the
caller never mutated the graph.

The README (`:106`) says only that the "API is not thread-safe during
mutation". A reasonable reader would conclude that concurrent encodes of a
graph they no longer change are safe.

The `*Graph` parameter type is a hint, and the plan does not require thread
safety, so this is a nitpick. **Fix direction:** either state in the README
that `node`, `stringify` and enumeration may reorder internal storage and need
exclusive access, or offer an explicit `normalize` call. After that call,
shared `*const` reads would be safe.

## Not findings

- **Depth limit of 256.** It rejects deep linear documents that upstream
  accepts. It is documented (`README.md:98-99`), listed as a profile
  difference, and allowed by the plan's resource-safety rule.
- **Unported upstream suites.** These are typed views and Buffer, URL and
  Temporal, async, `uneval`, the operations-override API, rich errors, invalid
  Date, and the surrogate cases. They are listed as outstanding in
  `zig-upstream-test-coverage.md:56-81`, and the validation report (`:56`)
  states that landing requires them. The amended plan makes full fidelity a
  pre-landing requirement, not a requirement for this basic milestone. The 79
  upstream-native fixtures cover the supported subset of `index.test.js`.
- **Wyhash with a fixed seed.** Map, Set and object-key hashing is
  deterministic, as Zig's `StringHashMap` is. Crafting collision floods
  against it has not been shown, and the plan explicitly makes performance
  tuning a non-gate.
- **`ephemeral/rework-root.py`.** It is a raw session artifact, and it lives in
  `ephemeral/`, where `CLAUDE.md` puts such files.

## Outcome

only nitpicks remain
