# Adversarial review — Zig typed arrays and DataView plan, round 01

**Target:** `ephemeral/zig-binary-views-plan.md` (commit `538c0bd`, branch
`codex/zig-binary-views`), with the session worklog
`ephemeral/worklog/20261007-zig-binary-views.md`.

**Outcome: only nitpicks remain** for the current working-tree plan. Against
the committed `538c0bd` text, finding 1 was material. See the addendum.

## Scope

The launch prompt names the target, the output path and a read-only boundary.
It does not narrow the subject matter, so nothing was ignored. Scope comes from
the repository instructions (`CLAUDE.md`/`AGENTS.md`, `zig/AGENTS.md`,
`zig/README.md`), the user requirements restated in the plan and worklog
(binary views against devalue 5.9.4 with Zig 0.17.0; "ordinary native tests and
recorded upstream bytes are sufficient validation machinery"; Opus plan and
implementation consensus), and the pinned upstream source and tests.

## Evidence inspected

- Plan, worklog, `zig/AGENTS.md`, `zig/README.md`,
  `ephemeral/zig-upstream-test-coverage.md`.
- Current Zig code: `zig/src/root.zig` (Graph, Node, error set, constructor
  conventions), `zig/src/encode.zig`, `zig/src/decode.zig` (reviver path,
  `constructionError`, excluded-tag list), `zig/src/wire.zig`.
- Current Zig tests: `zig/tests/tests.zig` (368-case shared corpus),
  `zig/tests/robustness.zig` (failure injection, corpus mutation over three
  fixture paths), and the test file layout.
- Recorder: `v5/testdata/record/{README.md,record.mjs,zig-values.mjs,upstream-values.mjs}`,
  `v5/package.json` (exact pin `5.9.4`), `justfile`, `mise.toml`.
- Pinned upstream source: `v5/node_modules/devalue/src/{parse,stringify,operations,base64}.js`
  (installed version 5.9.4 confirmed).
- Upstream tests at v5.9.4: `ephemeral/upstream-5.9.4/buffer.test.js` (whole
  file), `index.test.js` (binary fixtures at lines 298–367, repetitions at
  703–777, `invalid` table at 1108–1252, typed-array cycle at 1662),
  `parse-operations.test.js` (view backing buffers, lines 176–339).
- Go model and flat codec: `v5/value.go`, `v5/uneval_value.go`,
  `v5/stringify.go`, `v5/parse.go`, `v5/internal.go`, and the existing
  `ephemeral/codec-comparison/{main.go,parity.txt}` harness.
- Probes, both run outside the repository in the session scratchpad:
  - A Go program against `v5` (via `replace`): flat `Stringify` and `Parse` for
    `Uint8Array` and `DataView`.
  - A Node 26.10.0 script against the pinned `devalue` 5.9.4: 18 parse probes
    of view geometry and coercion, plus one stringify of mixed full, sub and
    empty views.

Upstream facts the plan depends on, and confirmed:

- Encode emits trailing bounds exactly when `byteLength !== bufferByteLength`
  (`stringify.js:319`, `:331`), so the plan's full and shorter rule is
  equivalent. Probe: `[new Uint8Array(b,4,0), new Uint16Array(b,2), new DataView(b,0,4), new Uint8Array(b,0,4)]`
  → `[[1,3,4,5],["Uint8Array",2,4,0],["ArrayBuffer","AQIDBA=="],["Uint16Array",2,2,1],["DataView",2],["Uint8Array",2]]`.
- Decode guards `values[value[1]][0] !== 'ArrayBuffer'` before hydrating
  (`parse.js`), then `fromViewInfo` brand-checks the hydrated buffer and calls
  `new Constructor(buffer)` or `new Constructor(buffer, byteOffset, length)`
  (`operations.js`).
- Typed-array geometry: whole and remainder views require a divisible extent.
  An explicitly bounded view may sit in an odd-sized buffer. A misaligned
  offset is rejected. `offset == byteLength` is accepted.
- Node `Buffer` values are normalized to a fresh copy of their visible bytes
  (`operations.js` `viewInfo`).

The plan's behavioural description matches all of these.

## Findings

### 1. issue — The Go cross-check is built on a false premise: Go's flat format supports no view kind

**Plan:** "Compare the recorded binary documents and independently constructed
examples against both Go modules where their models support the kind.
Float16Array has no Go kind today: verify it against JS and native contents
instead, without silently expanding Go scope."

**Evidence:** The Go *value model* has `*TypedArray` and `*DataView`, but only
`Uneval` supports them. The flat codec does not.

- `v5/value.go:8-9`: "typed arrays, DataView, URL, URLSearchParams and
  Temporal are available to Uneval and remain unsupported by the flat format."
- `v5/stringify.go` `serialize` has no `*TypedArray`/`*DataView` case.
- `v5/parse.go:354` returns `Unknown type <tag>` for every view tag.

Probe output (Go v5 via `replace`):

```
Stringify Uint8Array: "" Cannot stringify arbitrary non-POJOs (*devalue.TypedArray)
Stringify DataView: "" Cannot stringify arbitrary non-POJOs (*devalue.DataView)
Parse Uint8Array: <nil> Unknown type Uint8Array
Parse DataView: <nil> Unknown type DataView
```

v6 is a copy of v5 at the same parity. The existing harness
(`ephemeral/codec-comparison/main.go` `check`) panics on the first parse error.

**Impact:** The plan says Float16Array is the one kind without a Go
comparison. In fact the Go comparison covers none of the 13 view tags. As
written, the validation step can end in one of three ways:

- a vacuous "compared against Go where supported" claim, which matches zero
  documents and misstates the proof;
- a harness that panics on every binary document;
- pressure to add flat view support to the Go modules. The plan forbids that
  ("without silently expanding Go scope"; "Existing Go APIs … remain
  unchanged"), and under `CLAUDE.md` it would be a Go parity change in both
  majors, needing its own goldens and consumer runs.

The worklog sets "ordinary native tests and recorded upstream bytes" as the
sufficient machinery, so this step adds nothing anyway.

**Fix:** Delete the Go comparison for binary documents. State that pinned JS
bytes and native Zig assertions are the only references for every view tag,
not only Float16Array. If a Go check is kept, limit it to confirming that the
pre-existing non-binary corpora still agree, which is unchanged work.

### 2. nitpick — The acceptance-difference wording misstates what JavaScript accepts

**Plan:** "JS coercion of malformed strings/null/fractions/negative values and
ignored extra fields remain a documented strict-decode exception."

**Evidence (pinned 5.9.4, Node 26.10.0):**

| Input bounds | JS result |
|---|---|
| `["Uint8Array",1,-1,1]` | `RangeError` (rejected) |
| `["DataView",1,0,-1]` | `RangeError` (rejected) |
| `["Uint8Array",1,-0.5,1]` | accepted, offset 0 |
| `["Uint8Array",1,1,null]` | accepted, **zero-length** view at offset 1 |
| `["Uint8Array",1,null,2]` | accepted, offset 0 |
| `["Uint8Array",1,"1","2"]` | accepted, offset 1, length 2 |
| `["Uint8Array",1,0,1,99]` | accepted, extra field ignored |

**Impact:** JS already rejects negative integers, so listing "negative values"
as a JS-permissive difference is wrong. Only fractions in (-1, 0) coerce to
0. The `null`-length case also deserves a separate line: JS turns it into an
empty view, not a whole-buffer view, which is easy to get wrong when
documenting the exception in `zig/README.md` and the coverage note. Spell out
the actual accepted set from probes so the README exception list is accurate.

### 3. nitpick — The error category for a revived non-buffer is not decided

**Plan:** "After any ArrayBuffer reviver runs, require an actual ArrayBuffer
graph node; reject numbers, objects, arrays, other views and invalid handles…
Public construction reports InvalidType … malformed wire reports
InvalidDocument."

A reviver returning a number, object or view is neither malformed wire nor
public construction. Upstream raises `TypeError` from the brand check, while
the wire guard raises `Error('Invalid data')`. The current decoder has no
mapping for `InvalidType`: `constructionError` in `zig/src/decode.zig` maps
only `UnsupportedValue`/`UnsupportedString` to `InvalidDocument`. So if decode
delegates to `Graph.typedArray`/`dataView`, `InvalidType` escapes `parse`
unless it is mapped explicitly. A reviver returning an out-of-graph handle
already surfaces `InvalidHandle` from `validate`.

**Impact:** The per-kind revived-buffer matrix needs one expected category per
case. Decide it in the plan, for example `InvalidDocument` for every rejected
revived payload and `InvalidHandle` only for out-of-range handles, and state
that decode maps constructor `InvalidType` to it.

### 4. nitpick — Node-Buffer test ports and `uint8ArrayCopy` are framed as host equivalence, not as the disclosure-safe path

**Plan:** "Cover … all upstream Node Buffer sources' normalization semantics
(including file contents), and the ordinary-browser equivalent without Node
globals", and expose `Graph.uint8ArrayCopy(bytes)` as "the native equivalent
of upstream's Node Buffer normalization."

**Over-engineering in tests:** The eight `buffer.test.js` sources (`from`,
`allocUnsafe`, `concat`, `slice`, `subarray`, unpooled, over-ArrayBuffer, vm
context) and the `readFileSync` case differ only in how Node allocates. In the
native model each one is `uint8ArrayCopy(<the same 3 bytes>)`. The browser
case differs only in which base64 implementation JS picks (`base64.js`). The
bytes are identical, and Zig has no globals to remove. Porting each one
separately, and reading a repository file in a Zig test to mirror
`readFileSync`, adds fixtures and file-system coupling but no native
behaviour. One recorded case per distinct observable invariant is enough:

- visible bytes only;
- an empty subarray yields an empty buffer;
- two pooled sources yield distinct buffers;
- repetition and cycles are kept.

Record the distinct JS sources' bytes as evidence that they collapse to these
invariants.

**Under-specified documentation:** The real reason a native caller needs a
copy helper is disclosure. The plan serializes "all backing bytes, including
bytes outside ordinary subviews", so `typedArray(kind, big_buffer, off, n)`
publishes the whole buffer. The Go port documents this hazard on
`TypedArray.Subarray` (`v5/uneval_value.go:97-107`). The plan's README update
only requires "distinguish completed flat binary behaviors". It should also
require the `typedArray`/`dataView` docs to warn that a subview serializes its
entire backing buffer, and point to `uint8ArrayCopy` as the safe copy.

### 5. nitpick — Float16Array fixtures depend on an unpinned Node runtime

`mise.toml` pins only Zig, and `just record` runs whatever `node` is on
`PATH`. `Float16Array` is a global only in recent Node lines (present in the
26.10.0 used here). Upstream's own matrix guards it with
`globalThis.Float16Array` and `.filter(Boolean)` (`parse-operations.test.js:190-198`).

**Impact:** Two failure modes:

- On an older Node, a recorder that names `Float16Array` directly throws.
- A recorder that copies upstream's filter silently drops the Float16 cases,
  and the Zig tests then lose coverage without failing.

Make the recorder fail loudly when `Float16Array` is absent, or record the
minimum Node version in the recorder README. Have the Zig test assert the
expected count of binary fixture cases, as `tests.zig` does for the 368-case
corpus.

## Not findings (checked)

- Encode rule, reference ordering (view slot before buffer slot), and reducer
  precedence on both view and buffer match `stringify.js`.
- The raw-slot guard before hydration, the reviver-before-built-in order,
  cached revived-buffer validation and reviver cycles through
  `["ArrayBuffer",<view slot>]` are all reachable with the existing `pending`
  logic in `decode.zig`, matching upstream's `hydrating` set.
- Metadata-only views avoid allocating from a claimed length. The guard plus
  the brand check covers `parse-operations.test.js`'s 1024-length, sparse and
  array-like payloads.
- Recording through the existing pinned recorder, keeping
  `golden.json`/Go APIs unchanged, and using the existing failure-injection and
  corpus-mutation tests all comply with `CLAUDE.md` working rules. The
  mutation test lists fixture paths explicitly
  (`zig/tests/robustness.zig:366`), so the new fixture file must be added
  there, as the plan says.

## Addendum — concurrent plan correction

After this review's evidence was gathered, the working tree changed outside
this review (`git diff`, uncommitted). These changes were not made by this
reviewer:

- `ephemeral/zig-binary-views-plan.md` line 23 now says both Go modules
  implement views only for expression generation, and that Float16Array is
  absent. It says binary-view parity is validated against pinned JS and native
  contents and topology, not claimed against Go. It limits the Go comparison
  to standalone ArrayBuffer bytes and the existing shared corpus, plus
  recording Go's current rejection of flat view tags.
- The worklog records the same discovery.

The rewritten paragraph resolves finding 1. Go v5 and v6 do round-trip
standalone `["ArrayBuffer",…]`, so that comparison is meaningful. Recording
the rejection in a hand-written note is consistent with `CLAUDE.md`, provided
it is not a generated ledger. The edit raises no new issue. Findings 2–5 still
apply unchanged to the current text.

## Outcome

- Committed plan (`538c0bd`): **material findings remain** (finding 1).
- Current working-tree plan: **only nitpicks remain** (findings 2–5).
