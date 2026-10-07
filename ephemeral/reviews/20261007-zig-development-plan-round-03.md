# Adversarial review: Zig development plan, round 03

Date: 2026-10-07 (local)
Reviewer: Claude Fable 5.1
Target: `ephemeral/zig-development-plan.md` (untracked, revised after round 02)
at worktree `codex/zig-development-setup`, HEAD `46d2ba6`.

## Caller constraints and scope

Whole-plan re-review with a read-only boundary and a named artifact path. No
narrowing was requested or applied. Scope is unchanged from rounds 01 and 02.

## Evidence inspected

- Round 01 and 02 reviews and adjudications under `ephemeral/reviews/`.
- Repository instructions and gates: `CLAUDE.md`/`AGENTS.md`, `zig/AGENTS.md`,
  `.agents/skills/zig-development/SKILL.md`, `justfile`,
  `.github/workflows/*.yml`, `.gitignore`.
- `v5/testdata/record/record.mjs` (version guard, single `golden.json` output,
  input from generated `values.mjs`), `v5/testdata/record/main.go`,
  `v5/testdata/golden.json` (the three `["a"]` cases are the string `"a"`,
  not custom tags, so corpus round trips need no registered callbacks).
- Probe `ephemeral/zig-fixture-access/` (run in round 02: 2/2 pass).
- Pinned upstream `v5.9.4`: `src/parse.js:60-110` (reviver branch,
  `hydrating` set, cached-payload shortcut), `src/stringify.js:107-128,
  182-260` (reducer loop, RegExp payload, sparse heuristic),
  `src/operations.js:70-74,146-158` (`toISOString`, `regExpInfo`,
  `fromISOString`, `fromRegExpInfo`), `src/utils.js:169-173`
  (`valid_array_indices`), `test/index.test.js` (`circularCustomTypes`,
  `invalid`, custom reducer cases).

## Round 02 disposition

The round-02 issue is resolved. The Architecture bullet now states the
upstream rule exactly: a custom cycle resolves when the payload slot is
cached (even partially populated), rejection happens only for an uncached
payload already being hydrated, and the self-reference reviver is invoked
twice (first with the partial payload, then the full one). I re-traced both
`circularCustomTypes` shapes through `src/parse.js:80-110`: for the mutual
cycle the outer type's reviver runs twice and the inner one once; for the
self-cycle the single reviver runs twice. The plan's contract (graph-owned
partial payload handle, caller memoization by payload identity, no
single-invocation promise) matches, and the test row names both shapes plus
the infinite `[["Custom",0]]` rejection.

All four round-02 nitpicks are addressed: the profile is a subset by name;
the Zig-only fixture is `zig/testdata/flat-golden.json` written by the
existing recorder under the single `v5/package.json` pin, with a native
version test tying the four versions together; non-string null-prototype
keys are in the malformed-input row; the CI job installs `just`.

## Findings

No material findings remain. Two nitpicks:

### 1. Nitpick: RegExp payload spelling depends on JavaScript-canonical `source` and `flags`

`src/stringify.js:183-187` writes `regexp.source` and `regexp.flags`
(`src/operations.js:74`). Both are canonicalised by the JS engine: flags are
emitted in `dgimsuvy` order regardless of construction order, `/` is
escaped in `source`, line terminators are escaped, and an empty pattern is
`(?:)`. A Zig consumer supplies raw text, and the package has no regular
expression parser. The Tagged values row promises "exact payload spelling"
for every included tag; for RegExp that is only provable if the plan says
the source is opaque consumer text written verbatim (with JSON escaping
only), and that flags are validated against the eight known letters,
deduplicated and emitted in canonical order or rejected. Record it as a
documented profile rule, as the BigInt and reducer-name exceptions already
are.

### 2. Nitpick: Date payload range and decoder leniency are implicit

`src/operations.js:70` writes `date.toISOString()`, which uses the expanded
six-digit signed year form outside 0000–9999 and throws beyond
±8.64e15 ms; `src/operations.js:146` parses with `new Date(iso)`, which
accepts many non-ISO spellings. The Tagged values row says "finite Date
range" only. Add the expanded-year spelling and the millisecond limit to
the encoder expectations, and record that the Zig decoder accepts only the
exact `toISOString` grammar as an acceptance exception, consistent with the
BigInt policy.

## Items re-checked and found sound

- Reducer semantics (sentinel bypass, slot before reducers, JS-falsy means
  no match including `0n`, replacement flattened through the shared identity
  table) match `src/stringify.js:107-128`.
- Sparse heuristic inputs (`length`, leading valid-index run from
  `Object.keys`, digit count of `length`) match `src/stringify.js:252-256`
  and `src/utils.js:169-173`; the plan's zero-population, boundary and
  huge-length cases are well defined against it.
- Fixture access, version binding, and Zig gates/CI are specified with a
  passing native probe and concrete recipes.
- Property enumeration rule, surrogate policy, BigInt canonical form and
  Map/Set SameValueZero are unchanged from round 02 and remain correct.
- Milestone 3's 359-case round trip is feasible without custom callbacks
  (no corpus case carries a custom tag).

## Outcome

only nitpicks remain
