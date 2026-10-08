# Adversarial review: Zig development plan, round 01

Date: 2026-10-07 (local)
Reviewer: Claude Fable 5.1
Target: `ephemeral/zig-development-plan.md` at worktree `codex/zig-development-setup`
(HEAD `46d2ba6`; the plan file is untracked in this worktree).

## Caller constraints and scope

The launch prompt named the target, the artifact path, and a read-only
boundary. It did not narrow subject matter or predict a verdict, so nothing was
ignored. Scope was derived from the user request (a separate, directly
consumable Zig devalue package; graph-codec-first, comptime later; adversarial
validation before implementation), repository instructions, and the sources
the plan names.

## Evidence inspected

- Repository instructions: `CLAUDE.md`/`AGENTS.md`, `zig/AGENTS.md`,
  `.agents/skills/zig-development/SKILL.md`, `.agents/skills/zigcc/zig-0-17/`,
  `mise.toml`, `justfile`, `.github/workflows/*.yml`.
- Session artifacts: `ephemeral/zig-development-research.md`,
  `ephemeral/worklog/20261007-zig-development-setup.md`.
- Go runtime: `v5/version.go`, `v5/value.go`, `v5/stringify.go`,
  `v5/testdata/record/README.md`, `v5/testdata/record/main.go`,
  `v5/testdata/golden.json` (devalue 5.9.4, 359 cases, every case has both a
  `devalue` and an `uneval` field).
- Pinned upstream at tag `v5.9.4` (fetched from GitHub; `package.json` version
  confirmed `5.9.4`): `src/stringify.js`, `src/parse.js`, `src/constants.js`,
  `src/utils.js`, `test/index.test.js`.
- Installed Zig 0.17.0 standard library (`lib/std/json/Scanner.zig`,
  `lib/std/Build.zig`) for the JSON surrogate policy and build-root path rules.

Corpus tag coverage (from `golden.json`): BigInt 7, Object (boxed) 4, custom
`a` 3, Map 2, Date 1, RegExp 1, Set 1, ArrayBuffer 1, null-prototype 1. No
typed-array, DataView, URL, Temporal, invalid-Date, or lone-surrogate case.
Sparse cases: `sparse_array`, `_96`, `_97`, `_1000`, `_shared`, `_cycle`,
`_cycle_34`, `_cycle_35`.

## Findings

### 1. Issue: the completion gates `just test`, `just lint` and "repository checks" never run Zig

Evidence: `justfile` defines `modules` as every directory holding `go.mod`
and both `test` and `lint` loop only those; `.github/workflows` has one Go job
with matrix `[v5, v6]`. The plan's completion section requires "native tests
and formatting pass under the pinned compiler, `just test` and `just lint`
pass" and milestone 5 names "repository checks" as exit evidence, but no
milestone adds a Zig recipe to `just` or a CI job (which needs `mise` or a
`setup-zig` step for 0.17.0).

Impact: as written, the only Zig verification is whatever an agent runs by
hand; a regression in `zig/` passes every repository gate. The plan also
says the "normal Zig suite never executes Node" without saying what the normal
suite's entry point is.

Required change: milestone 1 should state that `just test` gains
`mise exec -- zig build test` (and `just lint` gains `zig fmt --check`) for
`zig/`, and that CI gets a Zig job pinned to 0.17.0, or the plan must say
explicitly that Zig is excluded from the repository gates and why.

### 2. Issue: the lone-surrogate policy is underspecified on the decode side and collides with the error taxonomy

Evidence: upstream `src/utils.js:64-89` (`get_escaped_char`) escapes only
`"`, `<`, `\`, control characters and U+2028/2029; lone surrogates pass
through unescaped, so a genuine 5.9.4 document may contain WTF-8 bytes, or
`\uD800`-style escapes after any JSON re-serialization. Zig 0.17.0
`std/json/Scanner.zig:25-32` documents that unpaired surrogate halves in `\u`
sequences are forbidden and line 799 returns `error.SyntaxError`; invalid
UTF-8 bytes are also syntax errors. The plan says lone surrogates "must cause
a documented unsupported-string error when encountered on input, rather than
silent replacement" and separately that "native errors distinguish invalid
documents, unsupported values, caller callback errors, and allocation
failure", and recommends using "Zig's JSON scanning/parsing primitives".

Impact: "on input" does not say whether this means encoder input (native
strings) or parse input (documents). If the decoder leans on `std.json`
scanning as the plan suggests, a lone surrogate in a document surfaces as an
invalid-document error, not the unsupported-string error the plan promises,
and the "Strings and keys" test row ("rejected lone-surrogate input") can be
satisfied by either, so the test cannot pin the contract.

Required change: state the decode policy explicitly (which error class, for
both raw WTF-8 bytes and `\uD8xx` escapes), state the encode policy for
non-UTF-8 byte slices, and make the test row name both forms.

### 3. Issue: "UTF-16-sensitive key ordering" imports a Go workaround as a Zig rule

Evidence: upstream objects are emitted via `for (const key in thing)`
(`src/stringify.js:365-400`): canonical array-index keys ascending, then the
remaining keys in insertion order; there is no UTF-16 sort anywhere upstream.
The UTF-16 sort exists only in Go's `v5/stringify.go:187-198`, as a
deterministic fallback for `map[string]any`, which has no order. The plan's
"Strings and keys" test row nevertheless lists "UTF-16-sensitive key ordering
where applicable", while the Scope section says "Go's representational
limitations do not become Zig identity rules".

Impact: an implementer following the test table will build a sort that
upstream does not perform, or leave "where applicable" undefined. The plan is
also silent on where the integer-index rule is enforced: on insertion into
the Zig object (so the graph API itself has JS ordering) or at emit time (so
a graph may hold an order the wire can never express). That choice shapes
the milestone 1 API and the "Preserve upstream property order" exit evidence
of milestone 2.

Required change: delete the UTF-16 ordering item, name the JS rule
(canonical numeric strings in `0 .. 2^32-2` ascending, then insertion order),
decide whether ordering is a graph invariant or an encoder step, and add
the boundary tests the corpus lacks (`"01"`, `"4294967294"`, `"4294967295"`,
`"-1"`, `"1.0"`).

### 4. Nitpick: reducer and reviver semantics worth pinning before the API milestone

The plan correctly defers these to upstream evidence; the evidence is in the
pinned source and is cheap to cite now:

- Reducers run before type dispatch for every value except `undefined` and
  the special numbers, including strings, numbers and booleans
  (`src/stringify.js:122-128`); a falsy return means "not mine", so a
  reducer cannot emit `0`, `""`, `false` or `null` as its payload.
- The slot index is assigned before the reducer runs, so a reducer result
  that references the original value serializes as a back-reference
  (`src/stringify.js:117-128`, test `circularCustomTypes`).
- The reducer key is interpolated raw into `["${key}",…]`; Zig should reject
  keys containing `"` or `\` instead of reproducing the injection.
- Revivers win over every built-in tag by name (`Object.hasOwn(revivers,
  type)`, `src/parse.js:80`), including `"Object"`, `"Date"` and `"null"`;
  a built-in payload is munged by appending it to `values`
  (`src/parse.js:82-87`), and `hydrating` detects circular custom payloads
  (`src/parse.js:98-110`).
- `BigInt(value[1])` on parse accepts hex, surrounding whitespace and the
  empty string; the plan's "decimal, validated" profile is a documented
  exception to record, per its own rule.

### 5. Nitpick: corpus evidence for milestone 3 is thinner than "all 359 documents" suggests

The corpus holds one Date, one RegExp, one Set, one ArrayBuffer, one
null-prototype object and no boxed `Boolean`/`String` cases (the four
`Object` cases are boxed numbers and BigInts; confirm in `record/main.go`).
Milestone 3's exit evidence rests mostly on primitives, objects and arrays.
The plan already requires additional pinned-JavaScript bytes; it should say
that such cases are added through `v5/testdata/record/main.go`, which
re-records `golden.json` for the Go tests too, and should check early that
`std.Build.path` can reference `../v5/testdata/golden.json` from `zig/`
(the pinned `std/Build.zig:2239-2241` forbids a dirname escaping the build
root; a cwd-relative path or a build option may be needed). Reading the
corpus from its current location is still the right call; the fixture
lookup mechanism just needs a verified answer before milestone 3.

## Items checked and found sound

- The 5.9.4 sparse-array scheme (`SPARSE` = -7, cost heuristic at
  `src/stringify.js:252-256`, `is_valid_array_len`/`index` checks at
  `src/parse.js:228-250`) matches the plan's sparse-array and
  huge-logical-length requirements, including "huge-sparse cases do not
  expand into dense storage".
- Special numbers are classified before the identity map
  (`src/stringify.js:107-113`), so the plan's primitive-deduplication
  statement is consistent with upstream.
- `__proto__` rejection on both sides, unknown-tag error, boxed-`Object`
  malformed-input guard, and empty/non-array root rejection all exist
  upstream and are covered by the plan's malformed-input row.
- Version binding: `UpstreamVersion` is `5.9.4`, the corpus header is
  `5.9.4`, and `mise.toml` pins `0.17.0`.
- Exclusions (typed arrays, DataView, URL, URLSearchParams, Temporal,
  invalid Dates, promises/`stringifyAsync`, `options.operations`) are all
  real 5.9.4 features and are stated as exclusions rather than claimed.
- The worklog for this session exists under `ephemeral/worklog/` as the
  repository requires.

## Outcome

material findings remain
