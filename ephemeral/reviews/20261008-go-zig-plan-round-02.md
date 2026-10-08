# Adversarial review: Go–Zig binary flat-codec interoperability plan (round 02)

## Target

The revised `ephemeral/go-zig-flat-parity-plan.md` (untracked, on branch
`codex/go-zig-flat-parity` at `b55f530`), with its updated worklog
`ephemeral/worklog/20261008-go-zig-flat-parity.md`. Round 01:
`ephemeral/reviews/20261008-go-zig-plan-round-01.md`.

Caller constraints honoured: read-only apart from this artifact. The launch
prompt did not narrow the review's scope; this is a full re-review, not only a
check of the round-01 items.

## Evidence inspected

- Repository instructions: `AGENTS.md`/`CLAUDE.md`, `justfile`, `mise.toml`,
  `.github/workflows/{go,zig}.yml`.
- Go v5 (v6 is a copy): `uneval_value.go`, `typedarray.go`, `uneval.go`
  (`walk`, `renderTypedArray`, `renderDataView`), `stringify.go`,
  `internal.go` (`identityKey`, `formatNumber`), `parse.go` (hydrate, `Object`
  raw-slot peek at 307-322), `golden_test.go`.
- Recorders: `v5/testdata/record/record.mjs` (writes Zig fixtures),
  `v6/testdata/record/record.mjs` (does not); Zig version checks
  `zig/tests/profile.zig:98-104` and `zig/tests/binary.zig:134`.
- Upstream devalue 5.9.4 (pinned `v5/node_modules/devalue`): `stringify.js`,
  `parse.js`, `operations.js`, `uneval.js` (typed-array and DataView rendering),
  and the tests under `ephemeral/upstream-5.9.4/`.
- `ephemeral/devalue-parity/5.9.2-to-6.0.2.md`, `ephemeral/polytype-migration.md`
  (it says polytype's runtime copy is identical to `v5/`, so redirecting
  imports is feasible), and the consumer checkouts' `go.mod`/imports.
- Scratch reproductions (outside the repository) of Uneval with nil and invalid
  view geometry.

## Round-01 findings: status

| # | Round-01 finding | Plan now | Status |
|---|---|---|---|
| 1 | Float16 Uneval optional, and silently corrupt | Lines 39-42 require Float16 rendering in both modules and an error for unhandled kinds | Resolved |
| 2 | Uneval changes without upstream evidence | Lines 55-56: each recorder records targeted Float16 and empty-shared-buffer `uneval` expectations | Resolved |
| 3 | Interop not in CI; gated tests skip silently | Lines 65-67: case-count and name assertions, failure on missing files, a CI job with Go and mise-pinned Zig | Resolved |
| 4 | go.work consumer proof is vacuous | Lines 71-77: redirect imports in scratch consumer copies or report the proof as unavailable; polytype's bundled runtime is named as the remaining gap | Resolved |
| 5 | v6 fixtures detached from v6's pin; change map stale | Lines 54-58: module-local recording, every fixture version checked against `UpstreamVersion`, change-map update | Resolved |

## Findings

### 1. issue — Geometry validation stops at the flat serializers, so `Uneval` keeps writing wrong views without an error

**Kind:** verifiable bug / incomplete requirement (a gap created by the plan's scope).

Plan lines 11-12 scope the change to `Stringify` and `Parse`. Lines 27-29 list
the native validation: "Native view validation rejects unknown constructors,
nil view pointers, negative/out-of-range extents and misaligned typed
offsets/byte lengths". Nothing applies that validation to `Uneval`. Yet the
plan does edit Uneval's typed-array path (Float16 rendering, the unhandled-kind
error at lines 41-42, empty-buffer identity at line 23). Today
`renderTypedArray` and `renderDataView` (`v5/uneval.go:615-679`) never check
geometry. Reproduction against current v5:

```
Uneval(&TypedArray{Kind: Uint16Array, Buffer: make(ArrayBuffer,4), ByteOffset: 1, ByteLength: 2})
  → "new Uint16Array([0,0]).subarray(0,1)"           err=<nil>
Uneval(&DataView{Buffer: make(ArrayBuffer,4), ByteOffset: 3, ByteLength: 9})
  → "new DataView(new Uint8Array([0,0,0,0]).buffer,3,9)"  err=<nil>
```

The first output drops the one-byte offset: integer division in
`renderTypedArray` turns it into `.subarray(0,1)`, so the browser receives bytes
0-1 instead of 1-2. The second evaluates to a `RangeError` in the page. Neither
value can exist in JavaScript, so upstream has no output to match, and the
right result is an error. Once this plan lands, `Stringify` rejects these
exact values while `Uneval` (skgo's SSR hydration path) emits wrong
JavaScript. One model would then have two contradictory notions of what a
valid view is. Nil view pointers are already rejected by both serializers, so
the gap is geometry only.

**Required:** run the same native geometry validation in `Uneval` for
`*TypedArray` and `*DataView` in both modules. Add native-geometry Uneval tests
next to the Stringify ones.

### 2. nitpick — Malformed-wire cases should name sentinel and out-of-range buffer indices

Plan line 30 requires peeking at the raw slot before hydration. In JavaScript,
`values[value[1]][0]` with `value[1]` = `-1` or `≥ length` reads `undefined`
and throws a `TypeError`. In Go, an unchecked `p.values[idx]` panics. The
existing `Object` peek shows the guard pattern (`v5/parse.go:311-316`: `>= 0`
and `< len`). The plan's malformed-wire list (line 52) should name negative
sentinels (−1…−7) and out-of-range indices as the buffer reference, so the
guard is tested rather than assumed.

### 3. nitpick — Formatting

Plan line 67 runs well past the file's wrap width ("…runs this recipe. This is
a direct codec integration check, not a new proof"), and so does line 77.
Cosmetic only.

## Non-findings considered

- Redirecting consumer imports in scratch copies is feasible and not
  over-engineering. `ephemeral/polytype-migration.md` says polytype's runtime
  is "identical to `v5/` here at devalue 5.9.4 parity", and the plan falls back
  to reporting the proof as unavailable.
- Module-local recorders cannot clobber Zig fixtures under a different pin.
  Only v5's recorder writes `zig/testdata/*`, and the Zig tests already check
  each corpus's `devalue` version (`profile.zig:98-104`, `binary.zig:134`).
- Float16 Uneval formatting: half values are exact in float64, so `formatNumber`
  covers the elements, including `NaN`/`Infinity` (`internal.go:183-191`) and
  the explicit `-0` the plan names. This matches `stringify_typed_array_elements`
  (`uneval.js:643-648`).
- Wire spelling, slot order, the raw-slot guard and the revived-buffer check
  still match upstream (`stringify.js:315-336`, `parse.js:187-196`,
  `operations.js` `fromViewInfo`). Keying empty buffers with positive capacity
  by pointer remains sound.

## Outcome

material findings remain
