# Adversarial review: Go–Zig binary flat-codec interoperability plan (round 03)

## Target

The revised `ephemeral/go-zig-flat-parity-plan.md` (untracked, on branch
`codex/go-zig-flat-parity` at `b55f530`) and
`ephemeral/worklog/20261008-go-zig-flat-parity.md`. Earlier rounds:
`ephemeral/reviews/20261008-go-zig-plan-round-0{1,2}.md`.

Caller constraints honoured: read-only apart from this artifact. The launch
prompt did not narrow the review's scope; this is a full re-review.

## Evidence inspected

- Repository instructions: `AGENTS.md`/`CLAUDE.md` (parity promise, "Each
  release is feature-equivalent to exactly one devalue release"), `justfile`,
  CI workflows.
- Go v5: `uneval.go` (`renderTypedArray`, hoisting), `typedarray.go`
  (`typedArrayElements` partial-element error), `uneval_value.go`,
  `stringify.go`, `internal.go`, `parse.go`.
- Upstream devalue 5.9.4 (pinned `v5/node_modules/devalue`): `uneval.js:338-365`
  and `stringify_typed_array_elements` (634-652), `stringify.js`, `parse.js`,
  `operations.js`. Change map `ephemeral/devalue-parity/5.9.2-to-6.0.2.md` row 14.
- Executed the pinned upstream (Node 26.10.0) and a scratch copy of Go v5
  (outside the repository) on one value: a valid `Uint16Array` with an explicit
  extent over an odd-sized buffer, both shared and alone.

## Round-02 findings: status

| # | Round-02 finding | Plan now | Status |
|---|---|---|---|
| 1 | Uneval skips geometry validation | Lines 27-28, 33-35: Stringify and Uneval share the validation, and invalid geometry is tested in both | Resolved, but over-broad; see finding 1 |
| 2 | Malformed-wire cases should name sentinel and out-of-range buffer indices | Lines 32-33 | Resolved |
| 3 | Formatting | Lines 27, 70-72, 81-83 still wrap unevenly | Remains (nitpick 2) |

## Findings

### 1. issue — "Neither may … emit a constructor that fails when evaluated" contradicts 5.9.4 byte parity for a valid value

**Kind:** incorrect requirement (it misreads the repository's parity promise).

Plan lines 33-35: "Test invalid geometry in Uneval as well as Stringify;
neither may silently change a view or emit a constructor that fails when
evaluated." The first half is right for geometry JavaScript cannot express,
such as misaligned offsets and out-of-range extents. The second half also
catches a value that is valid in both JavaScript and the Go model, and that
the plan's own corpus includes (line 51, "odd-sized buffers";
`binary-values.mjs` `*_odd_explicit`): a typed view with an explicit extent
over a buffer that ends in a partial element.

For that value, devalue 5.9.4's own `uneval` emits an expression that fails
when evaluated once the buffer is hoisted. When the buffer is not hoisted, it
throws instead. Executed against the pinned package:

```
const b = new ArrayBuffer(3), v = new Uint16Array(b, 0, 1)
uneval([v, b]) → (function(a){return [new Uint16Array(a).subarray(0,1),a]}(new Uint8Array([0,0,0]).buffer))
                 eval → RangeError
uneval(v)      → throws RangeError: byte length of Uint16Array should be a multiple of 2
stringify([v, b]) → [[1,2],["Uint16Array",2,0,1],["ArrayBuffer","AAAA"]]   (valid)
```

Current Go v5 already matches both byte for byte:

```
shared: "(function(a){return [new Uint16Array(a).subarray(0,1),a]}(new Uint8Array([0,0,0]).buffer))" err=<nil>
alone:  "" err=byte length of Uint16Array should be a multiple of 2
```

`AGENTS.md` requires each module to write "the bytes that devalue release
writes" for every value the Go model can express. Upstream fixes this only in
6.0.x: change map row 14, "A typed array whose backing buffer ends with a
partial element emits `new T(buffer,byteOffset,length)`". That is v6's
post-bump work, not 5.9.4 behaviour. As written, the plan has two compliant
readings:

- reject the shared case, which turns a 5.9.4-valid output into an error;
- back-port the 6.0 form, which breaks 5.9.4 byte parity in both modules.

Either breaks the parity promise that the existing code already keeps.

My round-02 finding argued that invalid geometry has no upstream output. That
holds only for values JavaScript cannot construct. The plan generalised it to
every constructor that fails when evaluated.

**Required:** limit the Uneval rule to geometry JavaScript cannot construct
(bad kind, misaligned offset or length, out-of-range extent): those must
error. Valid views must keep 5.9.4's exact Uneval behaviour, including the
partial-element case: a hoisted buffer renders the failing `new T(a).subarray(…)`
and an inline buffer returns the multiple-of error. Record or port that pair as
an upstream expectation so a later "fix" cannot pass unnoticed. Note row 14
as v6-only.

### 2. nitpick — Formatting

Lines 27, 70-72 and 81-83 still have uneven wraps, for example line 27 is
over-long and lines 82-83 split "name remaining / cross-language
differences" mid-phrase. Cosmetic only.

## Non-findings considered

- The remaining round-01 resolutions still hold:
  - Float16 Uneval with an error for unhandled kinds (42-45).
  - Module-local, pin-checked recording with Uneval expectations (57-61).
  - CI and non-vacuous interop (68-70).
  - Redirected scratch consumers, with the polytype runtime gap named (75-81).
- Upstream's two-step guard: the raw-slot peek is now required to be
  bounds-safe (30-33), matching the existing `Object` precedent at
  `parse.go:311-316`, and the revived-buffer check follows it.
- Nil view pointers are already rejected by both serializers today, so the
  shared validation adds no behaviour change there.
- Nothing in the plan is unrequested infrastructure.
  `test-interop` answers the user's explicit correction, and the CI job only
  runs it.

## Outcome

material findings remain
