# Adversarial review: Go–Zig binary flat-codec interoperability plan (round 04)

## Target

The revised `ephemeral/go-zig-flat-parity-plan.md` (untracked, on branch
`codex/go-zig-flat-parity` at `b55f530`) and
`ephemeral/worklog/20261008-go-zig-flat-parity.md`. Earlier rounds:
`ephemeral/reviews/20261008-go-zig-plan-round-0{1,2,3}.md`.

Caller constraints honoured: read-only apart from this artifact. The launch
prompt did not narrow the review's scope; this is a full re-review of the plan.

## Evidence inspected

- Repository instructions: `AGENTS.md`/`CLAUDE.md` (parity promise, major and
  minor rules, consumers, working rules, worklog protocol), `justfile`,
  `mise.toml`, `.github/workflows/{go,zig}.yml`.
- Go v5 surroundings (v6 is a copy), re-checked against the plan's current
  text: `uneval_value.go`, `typedarray.go`, `uneval.go`, `stringify.go`,
  `internal.go`, `parse.go`.
- Upstream devalue 5.9.4 (pinned `v5/node_modules/devalue`): `stringify.js`
  view and buffer cases, `parse.js` view guard, `operations.js`
  `viewInfo`/`fromViewInfo`, `uneval.js` typed-array, DataView and Float16
  rendering. Upstream tests in `ephemeral/upstream-5.9.4/`.
- Recorders and the Zig version checks, `ephemeral/devalue-parity/5.9.2-to-6.0.2.md`,
  `ephemeral/polytype-migration.md`, and the consumer imports.
- Executions from earlier rounds that still hold for the current text: the
  scratch Float16 Uneval reproduction, the Uneval geometry reproduction, and
  the pinned-upstream and Go comparison for an odd-sized shared buffer.

## Status of earlier findings

| Round | Finding | Plan now | Status |
|---|---|---|---|
| 01-1 | Float16 Uneval optional, and silently corrupt | Lines 47-50 | Resolved |
| 01-2 | Uneval changes lacked upstream evidence | Lines 63-64, 39 | Resolved |
| 01-3 | Interop not enforced in CI; gated tests skip silently | Lines 73-75 | Resolved |
| 01-4 | go.work consumer proof vacuous | Lines 80-86 | Resolved |
| 01-5 | v6 fixtures detached from pin; change map stale | Lines 62-66 | Resolved |
| 02-1 | Uneval skips geometry validation | Lines 27-29, 34-35 | Resolved |
| 02-2 | Sentinel and out-of-range buffer indices | Lines 32-34 | Resolved |
| 02-3 / 03-2 | Formatting | Rewrapped throughout | Resolved |
| 03-1 | "No failing constructor" contradicted 5.9.4 parity | Lines 35-40 | Resolved |

On 03-1, the plan now rejects only "geometry JavaScript cannot construct". For
valid views it keeps 5.9.4's exact Uneval behaviour, including the
partial-element quirk: a hoisted odd-sized buffer emits a failing
`new T(a).subarray(…)`, and an inline one returns an error. It records that
pair as an upstream expectation and assigns the corrected spelling to 6.x
(change-map row 14). This matches the pinned package's output and current Go
v5, as executed in round 03.

## Findings

No findings. I re-checked the following and found nothing material:

- **Parity promise.**
  - Wire spelling: compact when `byteLength !== bufferByteLength`, using the
    element count for typed arrays and the byte length for DataView.
  - Slot order: the view slot is allocated before its buffer.
  - Reducers run on the view's buffer, as upstream's `flatten(info.buffer)` does.
  - The raw-slot guard comes before hydration and the native buffer check after
    revival.
  - Float16 rendering, including `-0`, NaN and Infinity via `formatNumber`.
  - All of these follow `stringify.js:303-344`, `parse.js:174-197`,
    `operations.js` and `uneval.js:338-365, 634-652`.
- **API rules.**
  - Additions only: the `Float16Array` constant, `NewArrayBuffer`, and
    `BytesPerElement` returning 2 for a kind it previously rejected.
  - No exported field or type changes, so this fits a minor release within
    `/v5` and `/v6`.
  - The change lands in both maintained modules, as `AGENTS.md` requires.
- **Identity.** Keying empty buffers with positive capacity by allocation
  pointer is sound. A slice with positive capacity points inside its
  allocation, and zero-capacity reslices remain unkeyed. The plan documents the
  limitation for nil or zero-capacity slices and requires `NewArrayBuffer` for
  empty shared buffers. The Uneval hoisting change has recorded upstream
  expectations.
- **Evidence rules.**
  - Goldens come from each module's own pinned recorder, never from either
    port, and every fixture's version is checked.
  - Tests stay Node-free plain `go test`/`zig build test`.
  - `test-interop` exchanges temporary files only and generates no ledger.
  - It fails rather than skips when invoked, and CI runs it.
- **Scope.** Nothing is over-engineered. The interop recipe answers the user's
  recorded correction. Consumer proof is redirected or reported as unavailable,
  and production migration stays a separate plan. Cross-language and identity
  limitations must be named, without claiming full feature parity.

## Outcome

no findings
