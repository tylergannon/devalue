# Adversarial review: Zig development plan, round 02

Date: 2026-10-07 (local)
Reviewer: Claude Fable 5.1
Target: `ephemeral/zig-development-plan.md` (untracked, revised after round 01)
at worktree `codex/zig-development-setup`, HEAD `46d2ba6`.

## Caller constraints and scope

The launch prompt named the target, the artifact path and a read-only
boundary, and asked for a whole-plan re-review. No narrowing was requested
and none was applied. Scope is unchanged from round 01: the user's request
for a separate, directly consumable Zig devalue package with a
graph-codec-first strategy, the repository instructions, and the sources the
plan names.

## Evidence inspected

- Round 01 review and its adjudication
  (`ephemeral/reviews/20261007-zig-development-plan-round-01*.md`), and the
  worklog diff in `ephemeral/worklog/20261007-zig-development-setup.md`.
- Repository instructions and gates: `CLAUDE.md`/`AGENTS.md`, `zig/AGENTS.md`,
  `.agents/skills/zig-development/SKILL.md`, `justfile`,
  `.github/workflows/*.yml`, `.gitignore` (`**/.zig-cache/` is ignored).
- The new probe `ephemeral/zig-fixture-access/{build.zig,tests.zig}`; I ran
  `mise exec -- zig build test --summary all` there: 4/4 steps succeeded,
  2/2 tests passed, 359 cases visible, raw WTF-8 and `\uD800`/`\uDC00`
  escapes rejected with `error.SyntaxError`, a valid pair decodes.
- Pinned upstream at tag `v5.9.4`: `src/stringify.js` (flatten, reducer
  loop, sparse heuristic), `src/parse.js` (reviver branch, `hydrating`,
  null-prototype key checks), `src/utils.js`, `test/index.test.js`
  (`circularCustomTypes` suite, `invalid` cases, custom reducer cases).
- Zig 0.17.0 standard library: `std/testing.zig:24` (`std.testing.io`),
  `std/Build/Step/Run.zig:647` (`setCwd`), `std/json/Scanner.zig:25-32`.
- Go runtime for comparison: `v5/value.go`, `v5/stringify.go`,
  `v5/testdata/golden.json`, `v5/testdata/record/`.

## Round 01 disposition

All three round-01 issues are resolved in the revised text:

1. Zig gates: milestone 1 now defines `just test-zig`/`just lint-zig`,
   folds them into `just test`/`just lint`, adds a pinned CI job, and
   requires a deliberate failure to propagate.
2. Surrogates: native invalid UTF-8 is an unsupported-string error;
   document-side raw WTF-8 and escaped unpaired surrogates are
   invalid-document errors; valid pairs succeed; no U+FFFD substitution.
   The probe confirms the scanner mechanism.
3. Key ordering: the UTF-16 sort is gone; JavaScript enumeration order is a
   graph invariant with index-key boundary tests.

Both nitpicks were addressed (callback semantics pinned, corpus expansion
and fixture access specified and prototyped).

## Findings

### 1. Issue: "custom circular payloads follow upstream's rejection behavior" misstates upstream, which resolves valid cycles

Evidence: `src/parse.js:88-110` rejects with `Invalid circular reference`
only when the payload index is already in `hydrating` and not yet in
`hydrated`, which happens for an actually infinite payload such as
`[["Custom",0]]` (`test/index.test.js:1244-1248`). A valid cycle through
custom types resolves: `test/index.test.js:2053-2120` (`circularCustomTypes`)
asserts `result.value.ref.value.ref === result` and
`result.value.ref === result`. In the self-reference case the reviver is
invoked twice for the same slot, first with a partially populated payload
(the inner back-reference, via `Object.hasOwn(hydrated, i)` at line 93) and
again from the outer call, and correctness depends on the reviver returning
the same instance both times.

Impact: the Architecture bullet says "custom circular payloads follow
upstream's rejection behavior", and the Custom callbacks test row says only
"circular cases according to 5.9.4". An implementer following the bullet
literally rejects every custom cycle, which breaks the two upstream tests
above and any SvelteKit transport hook that round-trips cyclic custom
types. The double invocation with a partial payload is also an API
contract the Zig reviver signature must expose or deliberately diverge
from, and the plan does not say which.

Required change: replace "rejection behavior" with the actual rule
(resolve when the payload slot is already hydrated, reject only when the
payload is being hydrated and not yet cached), and state the Zig reviver
contract for the self-reference case: either reproduce the second
invocation with a partially built payload, or document a single-invocation
divergence and test both upstream cycle shapes under it.

### 2. Nitpick: "covers the Go runtime's current flat-format value families" is no longer true

`v5/value.go:8-12` lists typed arrays, DataView, URL, URLSearchParams and
Temporal as Go families; the Scope section excludes all of them. Say "the
subset of the Go runtime's families listed below" so the Intended result
and Scope sections agree.

### 3. Nitpick: the Zig-only fixture under `zig/testdata/` needs a named recorder and pin

Milestone 3 adds "a small separately recorded 5.9.4 fixture under
`zig/testdata/`" but does not say what records it. Two options keep one
pin: extend `v5/testdata/record/record.mjs` with a second output path, or
give `zig/testdata/record/` its own `package.json` exact pin that
`TestUpstreamVersion`-style checks hold equal to `v5/package.json`. Name
one, so the Version binding row ("corpus metadata matches the target") has
two concrete files to check.

### 4. Nitpick: malformed-input row omits the null-prototype non-string key check

`src/parse.js:161-163` rejects `["null", <non-string>, …]` with
`Cannot parse an object with a non-string key`, and
`test/index.test.js` exercises `["__proto__"]`, `[["__proto__"]]`, `[]`,
`{}`, `0`, `true` and `null` as keys. Add it to the Malformed input row
beside `__proto__`.

### 5. Nitpick: the CI job must invoke the recipes without assuming `just`

The existing workflow runs `go test`/`go vet` directly and never installs
`just`. Milestone 1 says the Zig job runs "the same two Zig recipes"; say
whether the job installs `just` or runs `mise exec -- zig build test` and
`zig fmt --check` directly, so the "deliberate failure propagates" check
has a defined command.

## Items checked and found sound

- Reducer semantics now pinned match `src/stringify.js:107-128`: sentinels
  bypass reducers, the slot is assigned before reducers run, JS-falsy
  results (including `0n`) mean no match, and the replacement is flattened
  through the same identity table.
- Revivers override built-ins by name (`Object.hasOwn(revivers, type)`,
  `src/parse.js:80`) and receive referenced or munged inline payloads
  (`src/parse.js:82-87`).
- Reducer-name rejection is a sound, explicitly recorded divergence from
  upstream's raw interpolation at `src/stringify.js:126`.
- Map/Set SameValueZero with -0 normalised to +0 and NaN deduplicated is
  the ECMAScript rule and is consistent with upstream emitting the stored
  key.
- Canonical-decimal BigInt with the lenient `BigInt()` parse recorded as an
  exception matches `src/parse.js:154`.
- Fixture access: `std.testing.io`, `Step.Run.setCwd` and the test-only
  build option exist in 0.17.0 and the probe passes from a separate build
  root; the public library embeds nothing.
- JavaScript property enumeration rule (index keys `0..2^32-2` ascending,
  then string keys in insertion order, update keeps position, delete and
  reinsert appends) is correct.
- `**/.zig-cache/` is ignored, so the probe's cache will not be committed.

## Outcome

material findings remain
