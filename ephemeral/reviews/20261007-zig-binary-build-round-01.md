# Adversarial review: Zig typed arrays and DataView implementation, round 01

**Target:** commit `4751ffb` ("feat: support Zig typed arrays and DataView in
the flat codec") on branch `codex/zig-binary-views`, checked against the
ratified plan `ephemeral/zig-binary-views-plan.md` (`0f9fdbe`) and its proof
artifacts. The working tree matches `4751ffb`, except for the untracked
`ephemeral/reviewer-logs/zig-binary-build-round-01/`, which is this review
session's own log directory.

**Outcome: material findings remain** (one issue, three nitpicks). The codec
behaviour checked here matches pinned devalue 5.9.4. The one issue is in the
proof: a ported upstream test passes without exercising the case it names.

## Scope

The launch prompt gives the target, the output path and a read-only boundary.
It does not narrow the subject matter or predict findings, so no caller
narrowing was ignored. Scope comes from:

- `CLAUDE.md`/`AGENTS.md` (working rules, goldens from pinned JS, upstream
  evidence for parity changes, `just test`/`just lint`);
- `zig/AGENTS.md`, `zig/README.md` and `.agents/skills/zig-development/SKILL.md`;
- the plan, including its restated user authorization and acceptance list;
- the round-01 plan review `ephemeral/reviews/20261007-zig-binary-plan-round-01.md`;
- pinned upstream source and tests.

## Evidence inspected

- Full diff of `4751ffb`: `zig/src/{root,encode,decode}.zig`;
  `zig/tests/{binary,graph_expect,robustness,tests,upstream}.zig`;
  `zig/README.md`; `zig/testdata/binary-golden.json` and
  `binary-file-input.txt`; `v5/testdata/record/{binary-values.mjs,record.mjs,README.md}`;
  `ephemeral/codec-comparison/binary/main.go`; `ephemeral/zig-binary-consumer/*`;
  `ephemeral/zig-binary-validation.md`; `ephemeral/zig-upstream-test-coverage.md`;
  and the worklog.
- Surrounding code: all of `decode.zig`, including the reviver/pending logic
  and `constructionError`; the encoder's flatten, reducer and reference cache;
  the Graph node, handle and validation code; `graph_expect.zig`'s handle
  bijection; and the CI workflows.
- Pinned upstream, with `v5/node_modules/devalue` confirmed at 5.9.4:
  - `src/parse.js`, where the view-tag raw-slot guard runs before `hydrate`;
  - `src/operations.js`, with `fromViewInfo`'s brand check and `viewInfo`'s
    Node Buffer copy;
  - `src/stringify.js` lines 303–343, where bounds are emitted iff
    `byteLength !== bufferByteLength`;
  - the tag tests `ephemeral/upstream-5.9.4/{index,buffer,parse-operations}.test.js`.

### Commands run (all read-only with respect to the repository)

| Check | Result |
|---|---|
| `mise exec -- zig build test --summary all` (Zig 0.17.0) | 33/33 pass |
| `... -Doptimize=ReleaseSafe` | 33/33 pass |
| `zig build fmt` | clean |
| `just test` | Zig plus Go v5/v6 pass |
| `just lint`, run in a scratch copy because it rewrites files | exit 0, no files changed, 0 issues, no vulnerabilities |
| Re-record with `node testdata/record/record.mjs` (Node 26.10.0, devalue 5.9.4) in a scratch copy | all five fixture outputs byte-identical to the checked-in files, 109 binary cases |
| `go run ./binary` in `ephemeral/codec-comparison` | "108 standalone JS-recorded buffers agree; all 109 binary documents rejected" |
| Fresh path-dependency consumer (`zig build run` in a scratch copy) | output equals `wire.json`; an independent JS `stringify` of the described value produces the same bytes |
| JS vs Zig decode probe of 22 edge documents (scratch) | see below |

The edge probe covered: empty buffers, offset equal to length for 1/2/8-byte
kinds, whole and remainder divisibility, explicit bounds in an odd buffer,
`-0`, `1e0`, `1.0`, `1e-7`, DataView extents, distinct equal views, and a
buffer slot cached before view hydration. JS and Zig agree on acceptance,
geometry and re-encoded bytes, except in two cases. Both are documented strict
exceptions: an extra ArrayBuffer field, and a fractional length.

## Findings

### 1. issue: The per-kind "array-like object" revival case never reaches the reviver or the post-revival check

**Requirement:** the plan (line 21) says to "Port … the per-kind revived-buffer
matrix for genuine buffers, empty buffers, invalid lengths/array-like/object/view
results". The coverage note (`ephemeral/zig-upstream-test-coverage.md:76-77`)
and the validation note (`ephemeral/zig-binary-validation.md:24`) say each kind
"rejects revived numeric lengths, sparse arrays and array-like objects".

**Evidence:** upstream (`parse-operations.test.js`, "rejects revived lengths
and array-like values") uses the payload `[{ length: 3 }, 1024]`. That is two
slots, so `length` refers to slot 3, which holds `1024`. The port at
`zig/tests/binary.zig:276` drops the second slot:

```zig
for ([_][]const u8{ "1024", "[-7,1024]", "{\"length\":3}" }) |payload| {
    const wire = try a.print("[[\"{s}\",1{s}],[\"ArrayBuffer\",2],{s}]", ...);
```

In `[["Int8Array",1],["ArrayBuffer",2],{"length":3}]`, the property refers to
slot 3, which does not exist. `hydrate` returns `InvalidDocument` at
`decode.zig:76` while it is still hydrating the reviver payload. The
`ArrayBuffer` reviver is never called, and the `backing != .array_buffer`
check (`decode.zig:223-224`) is never reached. The assertion passes for an
unrelated reason.

**Reproduction:** a scratch probe used a counting `ArrayBuffer` reviver over
every kind, with both bounds variants:

```
REACH Int8Array bounds='' payload=1024: reviver calls=1
REACH Int8Array bounds='' payload=[-7,1024]: reviver calls=1
REACH Int8Array bounds='' payload={"length":3}: reviver calls=0          <- ported case
REACH Int8Array bounds='' payload={"length":3},1024: reviver calls=1     <- upstream shape
REACH DataView bounds=',0,1' payload={"length":3}: reviver calls=0
REACH DataView bounds=',0,1' payload={"length":3},1024: reviver calls=1
```

All 13 tags × 2 bounds behave the same way.

**Impact:**

- The upstream-shaped document is rejected correctly today (the probe got
  `InvalidDocument` after one reviver call), so this is not a codec bug.
- The proof does not cover the one input this upstream test targets: a revived
  length-bearing array-like value, `{length:N}`, which `new TypedArray(x)`
  would treat as an allocation request. No kind exercises it. The closest test
  is `binary.zig:302`, which revives an empty `{}` for `Uint8Array` only.
- Two hand-written notes claim coverage that does not exist. A later change to
  the post-revival check that admitted array-like objects would leave this
  test green.

**Fix:** use `{"length":3},1024`, upstream's two-slot payload, in the per-kind
loop. Optionally assert that the reviver ran once, so the test cannot pass
before the reviver is reached.

### 2. nitpick: The ported genuine-revival case drops upstream's identity and offset assertions

Upstream's "accepts genuine revived backing buffers" asserts three things:

- `result.buffer` is the revived buffer;
- `byteOffset === bounds[0] ?? 0`;
- `byteLength`.

`binary.zig:282-294` checks only the backing length (16), the reviver call
count and the visible length.

Two mistakes would still pass:

- a decoder that substituted another 16-byte buffer;
- a decoder that placed the bounded view at offset 0 instead of 8.

Have `Revival` record the handle it returns. Then assert
`d.equal(view.buffer, recorded)` and the expected `byte_offset`.

### 3. nitpick: The Go harness overstates its rejection evidence by one document

`ephemeral/codec-comparison/binary/main.go:65` prints "all 109 binary documents
rejected as expected (flat views unsupported)". `ephemeral/zig-binary-validation.md:48`
repeats the claim. One of the 109 documents is `reduced_view`,
`[["View",1],"payload"]`. It contains no view tag, and Go rejects it only as an
unknown custom tag because no reviver is passed. So the evidence that Go
rejects flat view tags covers 108 documents. Either say so, or skip the
reducer cases in the count.

### 4. nitpick: The native `file_contents` input reads a checked-in copy of the pinned `package.json`

The plan says "collapse equivalent native invariants rather than duplicate
native tests for host allocation methods/file I/O". Plan-review nitpick 4
argued against reading a repository file in a Zig test to mirror
`readFileSync`.

The implementation still does this:

- `binary-values.mjs:58-61` records devalue's `package.json`;
- `record.mjs` writes it to `zig/testdata/binary-file-input.txt`;
- `binary.zig:65-71` reads it from the filesystem to build
  `uint8ArrayCopy(input)`.

Natively, this is the same visible-byte-copy invariant that `source_*`
already covers. The cost is low, because the recorder regenerates the file on
each pin bump. Still, it adds a second fixture file and a test-time file read,
and the plan meant to collapse exactly this. Keeping the JS recording as
evidence and dropping it from the native encode set, or embedding a short
literal, would meet the plan more directly.

## Not findings (checked)

**Encoding:**

- Tags come from `@tagName` on JS constructor names.
- Bounds are emitted iff `length*width != size`. That is upstream's
  `byteLength !== bufferByteLength`, and no overflow is possible after
  `checkView`.
- The view slot is emitted before the buffer slot.
- Reducers apply to both the view and the buffer.
- All 109 recorded byte sequences reproduce exactly from independently built
  native inputs.

**Decoding:**

- The raw-slot `ArrayBuffer` guard runs before hydration and before callbacks,
  as in upstream `parse.js`.
- View-tag revivers take precedence over the guard.
- After revival a genuine `array_buffer` node is required. `InvalidType` from a
  non-ref value maps to `InvalidDocument`, and an out-of-range callback handle
  stays `InvalidHandle`.
- Self, mutual and reviver cycles are rejected, matching upstream's `hydrating`
  set.
- No storage is allocated from a claimed length.
- Overwriting the cache in reviver-reentry cases has the same identity effect
  as upstream's `hydrated[index]` overwrite.

**Bounds:**

- `bound()` rejects non-finite, fractional, negative and unsafe values.
  `@intFromFloat` cannot trap after those checks, including on 32-bit `usize`.

**Graph API:**

- The constructors use subtraction and division only.
- `viewBytes` revalidates geometry and borrows arena storage, which is stable
  across growth (tested).
- `uint8ArrayCopy` yields distinct buffers per call.
- Nodes are immutable after construction, so encode-time geometry cannot drift.

**Plan acceptance items present:**

- Float16Array is required at record time, and the fixture count is asserted
  (109).
- Coverage includes upstream index fixtures, repetitions and the invalid table;
  all synchronous `buffer.test.js` flat invariants; and the browser-path
  recording.
- Per-kind geometry, arity, type and overflow guards are tested.
- Input lifetime and graph growth are tested.
- Allocation-failure enumeration runs through copy, construct, encode, decode
  and reviver.
- The mutation corpus includes the binary fixtures.
- The consumer run and the README/coverage-note updates are done.
- Go APIs and shared goldens are unchanged.
- `just test`, `just lint` and ReleaseSafe all pass.

**Documented strict-decode differences:** null, string or fractional bounds,
and extra fields. These match the plan's explicit exceptions and the JS probe.
