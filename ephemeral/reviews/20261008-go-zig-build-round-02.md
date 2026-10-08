# Adversarial review: Go–Zig binary flat-codec interoperability build (round 02)

## Target

This round reviews the whole current branch `codex/go-zig-flat-parity` at
`05618ff`, which is four commits on top of `origin/main` `20a8d45`:

- `1ddf443`: plan ratification.
- `eb26827`: the rebased feature commit, formerly `8a8297e`.
- `0c5083d`: validation docs updated for the installable package.
- `05618ff`: fixes for the round-01 findings.

The sources it is checked against are the same as in round 01:

- `ephemeral/go-zig-flat-parity-plan.md`
- the repository instructions (`CLAUDE.md`/`AGENTS.md`)
- upstream devalue 5.9.4: the pinned `src/` and the tag's `test/` in
  `ephemeral/upstream-5.9.4/`

This round also covers the rebase integration with `20a8d45`, which publishes
an installable Zig source package. Round 01 could not review that integration.

Caller constraints followed: this file is the only write. The launch prompt did
not narrow the scope of the review. Round 01
(`ephemeral/reviews/20261008-go-zig-build-round-01.md`) is left untouched.

## Evidence inspected

**Diffs reviewed**

- `git diff 8a8297e 05618ff` across the Go modules, `zig/`, the `justfile`, CI
  and the READMEs.
- The full `05618ff` diff, including the change-map row 13 edit, the validation
  note, the worklog and the consumer script.
- The `20a8d45` integration: root `build.zig`, `build.zig.zon` `.paths`,
  `zig/build.zig` `addPackage(source_dir)`, and the `zig/README.md` merge.

**Checks run on a `git archive 05618ff` snapshot in the session scratchpad**

- **Test suite.** `just test` passed. It covers native Zig, both Go modules and
  `test-interop` in both exchange directions.
- **Lint.** `just lint` passed and left the tree clean, checked against a
  scratch git baseline.
- **Zig ReleaseSafe.** `zig build test -Doptimize=ReleaseSafe` gave 33 passed and
  1 skipped. The skipped test is the exchange test, which needs an interop
  directory.
- **Interop step guard.** `zig build interop` without `-Dinterop-dir` fails with
  its explicit message.
- **Installable package.** I copied only the files listed in `build.zig.zon`
  `.paths` into a fresh directory. `zig build test` passed there (33/34, 1
  skipped), so the new exchange test does not depend on anything outside the
  published archive.
- **Interop phase guard (round-01 Finding 2).**
  - `go test -run '^Nope$' -binary-peer /nonexistent` now prints `requested
    binary exchange phase did not complete` and exits 1.
  - `-run '^TestBinaryGolden$' -binary-peer …` also exits 1.
  - `readBinary` (`v5/binary_test.go:172-192`) still requires version 5.9.4,
    exactly 111 cases, and unique non-empty names. A truncated peer file
    therefore cannot pass either.
- **v5/v6 sync.** `cmp` shows `parse_view.go`, `parse.go`, `parse_test.go` and
  `binary_test.go` are identical in `v5/` and `v6/`.
- **Fixtures unchanged.** No fixture changed between `8a8297e` and `05618ff`.
  Round 01's byte-for-byte recorder reproduction under Node 26.10.0 therefore
  still holds.
- **Error-message differential.** I parsed 21 malformed view documents with both
  the pinned JS 5.9.4 `parse` and Go `Parse` (table under Finding 1). The
  documents covered:
  - the three upstream rows
  - raw backing slots that are a number, string, `null`, `[]`, an object, a
    `Date` or a nested array
  - out-of-range, negative, fractional and string backing indices
  - a missing index
  - non-string or missing base64
  - a misaligned offset, an over-long count, and an odd buffer
- **Consumers.** I ran the committed `ephemeral/verify-go-zig-consumers.sh` from
  the snapshot, so its scratch directory stays outside the worktree. It exited 0
  with 469 `--- PASS`, 0 `--- FAIL` and four `PASS` package results:
  - polytype `devalue/codegen`
  - the full skgo root package
  - skgo `internal/formdata`
  - skgo `internal/remotearg`

**Round-01 Finding 1 re-check**

- `v5/parse_view.go:23-28` now returns `errInvalidData`, with the message
  `Invalid data`, when the raw slot is not an array headed by `"ArrayBuffer"`.
- The three 5.9.4 `index.test.js` rows are ported, with their source cited, into
  both `TestParseInvalid` tables (`v5/parse_test.go:183-187`).
- Change-map row 13 now says the raw-slot guards keep 5.9.4's text until the v6
  bump.
- The post-revival, offset and count checks still give `Invalid input`.

**Correction to round 01.** Round 01's fix scope said a missing, out-of-range
or fractional backing index should also give `Invalid data`. That was wrong.
Pinned 5.9.4 evaluates `values[value[1]][0]` on `undefined` there and throws a
native `TypeError` (`Cannot read properties of undefined (reading '0')`). The
implementation keeps `Invalid input` for these indices, and the validation note
explains why. That is the right call.

## Findings

### 1. Nitpick: two raw-slot shapes get `Invalid data`, though 5.9.4 never throws that message for them

`v5/parse_view.go:23-28` (identical in `v6/`) treats every slot that is not a
JSON array headed by `"ArrayBuffer"` as an `Invalid data` failure. Upstream's
test is narrower. It reads `values[value[1]][0] !== 'ArrayBuffer'`
(`src/parse.js:187`), so it differs from Go in two places:

| Document | Pinned JS 5.9.4 | Go v5/v6 at `05618ff` |
|---|---|---|
| `[["Uint8Array",1],{"0":"ArrayBuffer"}]` | `Error: Invalid input` | `Invalid data` |
| `[["DataView",1],{"0":"ArrayBuffer"}]` | `Error: Invalid input` | `Invalid data` |
| `[["Uint8Array",1],null]` | `TypeError: Cannot read properties of null (reading '0')` | `Invalid data` |

- **Object slot.** An object whose `"0"` key is the string `"ArrayBuffer"`
  passes upstream's raw guard. Upstream then hydrates the object, finds the
  non-index field value, and throws its own `Invalid input` message.
- **`null` slot.** Upstream throws a native `TypeError`. The validation note
  (`ephemeral/go-zig-flat-validation.md`, round-01 paragraph) says native
  `TypeError` cases keep Go's `Invalid input`. A `null` slot is one of those
  cases, but Go returns `Invalid data`.

The other 18 differential rows agree in kind with upstream:

- the upstream message where upstream has one
- `Invalid input` where upstream throws a native `TypeError` or `RangeError`

**Impact.** Small. Both implementations reject these documents. No upstream test
asserts either message, and only hand-crafted input reaches them. Still, Go
reports a 5.9.4-named message for a case where 5.9.4 reports a different one.
That is the same kind of drift that round-01 Finding 1 addressed, on a smaller
surface.

**Possible fix.**

- **Object slot.** Let a JSON object pass the raw guard when its `"0"` member is
  the string `"ArrayBuffer"`, then hydrate it. Ordinary object hydration
  already returns `Invalid input`.
- **`null` slot.** Return `errInvalidInput`, matching the stated
  native-`TypeError` rule.
- **Tests.** Add both shapes to `TestBinaryBackingGuardsAndBounds`.

The alternative is to document these two shapes as an accepted boundary in the
validation note.

## Areas checked without findings

- **Round-01 Finding 1 fix.**
  - The three upstream documents now give `Invalid data` in both modules.
  - The post-revival and bounds failures are unchanged.
  - Row 13 is accurate.
  - Zig is unaffected: it has its own error set and its documented stricter
    acceptance.
- **Round-01 Finding 2 fix.**
  - `TestMain` (`v5/binary_test.go:18-26`) fails the binary when a phase was
    requested but its test never completed.
  - The flags are read after `m.Run` parses them.
  - Without the interop flags, plain `go test ./...` and `just test` are
    unaffected. The package has no other `TestMain`.
- **Round-01 Finding 3 fix.** The consumer script now runs the full skgo root
  package and both internal parsing packages. The recorded and re-run results
  match.
- **Rebase integration.**
  - `addPackage(b, source_dir)` sets the interop run's working directory to the
    same `source_dir` as the test run.
  - The repository root's `build.zig` gets the `interop` step through
    `addPackage`.
  - The `justfile` invokes it from the root.
  - CI sets up Go and runs `just test-interop` after `just test-zig`.
  - The archive's `.paths` include `zig/testdata/binary-golden.json`.
  - The two README merges describe both the installable root and the binary-view
    support accurately.
- **Unchanged since round 01 and re-confirmed by the passing suites:**
  - Stringify wire spelling.
  - Decoder ordering and `ToIndex` emulation.
  - Shared `validView` geometry.
  - Float16 Uneval.
  - The preserved 5.9.4 odd-buffer Uneval quirk.
  - `NewArrayBuffer` empty-buffer identity.
  - No breaking API change.

## Outcome

`only nitpicks remain`
