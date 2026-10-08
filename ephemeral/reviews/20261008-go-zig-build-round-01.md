# Adversarial review: Go–Zig binary flat-codec interoperability build (round 01)

## Target

The completed change on `codex/go-zig-flat-parity`, `b55f530..8a8297e`
(`b183de2` docs: ratify the plan; `8a8297e` feat: align Go and Zig binary flat
codecs), reviewed against `ephemeral/go-zig-flat-parity-plan.md`, the
repository instructions (`CLAUDE.md`/`AGENTS.md`), and upstream devalue 5.9.4.

**Snapshot note.** Partway through this review another session began an
interactive rebase of this worktree onto `20a8d45` (`origin/main`, "publish an
installable Zig source package"). The rebase stopped with conflicts and
`HEAD` moved to `1ddf443`. All findings below are against the immutable commit
`8a8297e`, extracted with `git archive` into the session scratchpad. They do
not cover the rebased result or the conflict resolution. Re-check
`justfile`, `zig/build.zig` and `zig/README.md` after the rebase, because
`20a8d45` also touches them.

Caller constraints followed: read-only except for this file. The launch prompt
did not narrow the scope of the review.

## Evidence inspected

- The plan, `ephemeral/go-zig-flat-validation.md`, the worklog
  `ephemeral/worklog/20261008-go-zig-flat-parity.md`, the recorded
  test/lint/consumer outputs, and `ephemeral/verify-go-zig-consumers.sh`.
- The full diff `b55f530..8a8297e`: `v5/` and `v6/` `parse.go`,
  `parse_view.go`, `stringify.go`, `typedarray.go`, `uneval.go`,
  `uneval_value.go`, `value.go`, `internal.go`, `binary_test.go`,
  `binary_robustness_test.go`, `parse_test.go`, `uneval_test.go`, recorders and
  fixtures; `zig/build.zig`, `zig/tests/binary.zig`,
  `zig/testdata/binary-golden.json`; `justfile`, `.github/workflows/zig.yml`;
  README, the change map and the migration plan.
- Upstream sources: the pinned `devalue@5.9.4` `src/parse.js`,
  `src/stringify.js`, `src/uneval.js` and `src/operations.js`, and the 5.9.4
  tests in `ephemeral/upstream-5.9.4/` (`index.test.js`,
  `parse-operations.test.js`, `buffer.test.js`).
- Independent checks on the `8a8297e` snapshot:
  - `just test` passed. That covers native Zig, both Go modules, and the
    `test-interop` exchange in both directions.
  - `just lint` passed with no files modified.
  - `zig build test -Doptimize=ReleaseSafe`: 33 passed, 1 skipped. Running
    `zig build interop` without `-Dinterop-dir` fails, as intended.
  - `cmp` confirms every changed Go source, test and fixture is
    byte-identical between `v5/` and `v6/`.
  - Re-running both modules' recorders under Node 26.10.0 from the pinned
    5.9.4 reproduced every fixture byte-for-byte: v5/v6 `binary-golden.json`,
    `binary-uneval-golden.json` and `binary-file-input.txt`; the Zig flat,
    upstream-flat and binary goldens; `golden.json`.
  - A differential test of 43 offset spellings, run through the pinned JS
    `parse` and Go `Parse`, gave identical results. The spellings covered
    hex/binary/octal strings, Unicode whitespace, U+0085/U+180E, `1e1000`,
    `-0`, nested arrays, objects, booleans, `"Infinity"` variants and malformed
    exponents. Go's `ToIndex` emulation matches V8 on all of them.
  - Probes of Go nil views, unknown kinds, `nil` backing buffers,
    `b[:0]`/`b[4:]`/`make(0,8)` empty-buffer identity, Float16 Uneval and
    round trip, revived non-buffers, huge counts and offsets past the end.
    The view-handling probes behaved as designed. The one exception is the
    error message in Finding 1.
  - Consumer check, using redirected scratch copies under the scratchpad with
    test binaries built under `GOWORK` and run with `GOWORK=off`: the **full**
    skgo root package (413 tests), `internal/formdata` and
    `internal/remotearg` all pass against `8a8297e`'s v5.

## Findings

### 1. Issue: incorrect implementation. The view raw-slot guard reports 6.x's `Invalid input` instead of 5.9.4's `Invalid data`

`v5/parse_view.go:16-28` (identical in `v6/`) returns `errInvalidInput`
("Invalid input") when a view's backing slot is not a raw `ArrayBuffer`
array. In devalue 5.9.4 the same guard throws `new Error('Invalid data')`
(`src/parse.js:187-192`). The pinned 5.9.4 test suite asserts that exact
message for three documents (`test/index.test.js:1110-1114`,
`:1239-1242`, `:1250-1253`):

| Upstream case | Document | 5.9.4 (pinned JS, verified) | Go v5/v6 at `8a8297e` |
|---|---|---|---|
| typed array with non-ArrayBuffer input | `[["Int8Array", 1], { "length": 2 }, 1000000000]` | `Error: Invalid data` | `Invalid input` |
| TypedArray self-reference | `[["Uint8Array", 0]]` | `Error: Invalid data` | `Invalid input` |
| mutual TypedArray reference | `[["Uint8Array", 1], ["Uint8Array", 0]]` | `Error: Invalid data` | `Invalid input` |

Reproduce: `Parse(`[["Uint8Array", 0]]`, nil)` returns `Invalid input`, and
`node -e` with the pinned `devalue` `parse` throws `Invalid data`.

**Requirements missed.**

- *Each release is feature-equivalent to exactly one devalue release* (CLAUDE.md).
- *Parity changes need upstream evidence: … upstream test expectations ported …
  with their source cited* (CLAUDE.md).
- The plan's *Retain upstream behavior coverage*.
- The plan's instruction not to back-port 6.x behavior into this 5.9.4 target.

`TestParseInvalid` (`v5/parse_test.go:175-211`) is a row-by-row port of the
5.9.4 `invalid` table and reproduces its messages: `Invalid ArrayBuffer
encoding`, `Invalid circular reference`, `__proto__`. The change edited this
table at line 203, swapping the old `Uint8Array` "unknown type" row for
`UnknownView`. It did not add the three typed-array rows that view support now
makes applicable. `TestBinaryBackingGuardsAndBounds`
(`v5/binary_robustness_test.go:140-144`) checks the self- and mutual-reference
documents only for `err != nil`.

Turning these failures into `Invalid input` is the 6.x change e7a9a73. The
updated change map row 13 (`ephemeral/devalue-parity/5.9.2-to-6.0.2.md:64`)
says "new flat-view guards already return `Invalid input`" as if that were
correct. For the 5.9.4 modules it records the drift instead of flagging it.

**Impact.** Code that matches devalue's parse error messages sees a different
message for the one view failure that devalue 5.9.4 names itself. The
module's own claim of 5.9.4-ported parse expectations is incomplete exactly
where this change added behavior.

**Fix scope.** Make the raw-slot guard in both modules return `Invalid data`
for every input 5.9.4 rejects there: a missing, non-array or
non-`ArrayBuffer` slot, including an out-of-range or non-integer index. Port
the three upstream rows, citing their source, into both `TestParseInvalid`
tables. Correct row 13. The post-revival check and the bounds checks
legitimately stay `Invalid input`, because 5.9.4 throws native
`TypeError`/`RangeError` messages there that Go cannot reproduce. Keep the
odd case `[["Uint8Array",-1]]`, where 5.9.4 throws a raw `TypeError`
(`Cannot read properties of undefined`), on `Invalid input` as well.

### 2. Nitpick: proof gap. The recipe's final Go phase can pass without running any test

`justfile` `test-interop` runs
`go test -count=1 -run '^TestBinaryZigPeer$' -binary-peer …` with no
postcondition. If that test is renamed, `go test` prints
`testing: warning: no tests to run` and exits 0. I confirmed this with a
non-matching `-run` plus a nonexistent `-binary-peer` path: `ok`, exit 0.
The other phases are guarded: the emit phases check `test -s` on their output
files, and the Zig phase both requires its directory and must write
`zig.json`. The plan asks to *assert nonempty complete case counts and names
in all phases*.

The checks pass today. This is only a guard against a future rename silently
hollowing out the Zig→Go direction. Adding `-v` and grepping for
`--- PASS: TestBinaryZigPeer`, or having the test write a marker file that
the recipe checks, would close it.

### 3. Nitpick: the recorded consumer proof is narrower than what can run

`ephemeral/verify-go-zig-consumers.sh` runs only skgo's root package, filtered
by `-run 'Test(Wire|.*Document|.*Stream|.*Deferred|.*Promise|AssembleTemplate)'`.
That is 42 of 413 root tests. It skips `internal/formdata` and
`internal/remotearg`, which import the runtime and exercise flat `Parse`. It
also excludes the root transport, replacer and `kitgolden` tests, which
exercise the `Uneval` path this change touched (`refKey` empty-buffer
identity, `walk` geometry validation). The validation note gives a reason
only for the example module: its frontend build is absent.

I re-ran the full root suite and both internal packages against `8a8297e`
using the same redirection technique, and all pass. So no defect is hidden.
The recorded evidence just understates what was verifiable. Extending the
script, or citing this run, would let the validation note claim the broader
result.

## Areas checked without findings

- **Stringify wire spelling and slot order.** Upstream compares
  `byteLength !== bufferByteLength` and appends `offset,length` (element count)
  or `offset,byteLength` (DataView). Go matches. All 111 recorded cases match
  byte-for-byte in both modules and in Zig.
- **Decoder semantics.**
  - The reviver-first precedence matches upstream. The raw-slot check runs
    before hydration and the genuine-buffer check after it.
  - A 3-element document leaves the length undefined, so the alignment check
    is correct.
  - `null` and other coerced lengths follow `ToIndex`.
  - The bounds use subtraction and division, so they cannot overflow.
- **Native geometry.**
  - Stringify and Uneval share `validView`.
  - Nil, unknown, misaligned and out-of-range views are rejected by both
    serializers.
  - Reducers run before validation.
- **Uneval.** The Float16 conversion (normal, subnormal, ±0, ±∞, NaN) and the
  two 5.9.4 odd-buffer outcomes match the pinned expressions. Change-map
  row 14 is correctly deferred to v6.
- **Empty-buffer ownership.**
  - `NewArrayBuffer` and every element constructor allocate capacity ≥ 1.
  - Parse hands out distinct owned empty buffers.
  - Zero-capacity literals keep their documented loss of identity.
  - Map/Set SameValueZero behaves correctly.
- **No breaking API change.** `Float16Array` and `NewArrayBuffer` are additive.
  `ArrayBuffer` keeps its slice type.
- **Docs.** README, Zig README, the migration plan and the coverage notes
  describe the shared surface and its remaining limits without claiming full
  upstream parity.

## Outcome

`material findings remain`
