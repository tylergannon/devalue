# Zig binary-view validation

Target: devalue 5.9.4, Zig 0.17.0, native macOS aarch64. This increment adds flat
typed arrays and DataView to the experimental Zig profile, not full devalue parity.
The plan was ratified by Claude Opus session
`2d4d625d-5d47-4c48-ac77-96cf3a65e6f1`, outcome **only nitpicks remain**;
its optional clarifications were applied before implementation.

## Behavior evidence

- 109 pinned-JS recorded binary inputs are independently constructed in native
  Zig, with exact encoder bytes and independent decoded kind, full/visible
  bytes, geometry, and view/buffer handle bijection checks. The two custom
  reducer inputs separately check encoded bytes and the expected custom revival
  or rejection instead of asserting a built-in round trip.
- Every typed kind, including Float16Array, plus DataView has full, sub,
  empty-end, empty-buffer, distinct/repeated view, buffer-sharing, cycle and
  explicitly bounded odd-buffer cases. Raw NaN-payload/negative-zero and signed
  and unsigned 64-bit integer bytes are untouched by numeric conversion.
- The eight upstream Node Buffer sources, file contents and browser-path bytes
  are recorded from JS. Native ports collapse host construction mechanics to
  the same visible-byte-copy operation; separate copies retain distinct buffers.
- Per-kind raw-slot/type/arity/alignment/range/overflow checks, omitted bounds,
  remainder bounds, genuine and empty revived buffers (checking returned identity and offsets), invalid
  length/array-like results with one reviver invocation asserted, cached buffers, invalid handles and custom cycles are exercised.
  Rejected non-ArrayBuffer wire slots cannot invoke their custom callbacks.
- Leak-checked input release and graph growth preserve visible bytes and handles.
  Existing deterministic allocation-failure enumeration covers copying, view
  construction, stringify, parse and allocating backing-buffer revivers. Binary
  fixtures participate in the existing deterministic corpus mutation test.

## Checks executed

- `just test`: passed, including **33 native Zig tests**, the 368 shared cases,
  35 existing Zig-profile cases, 79 existing upstream cases, and the new binary
  fixture set; both Go modules pass without running Node.
- `just lint`: passed, both Go modules report zero issues/no vulnerabilities,
  with Zig formatting checked.
- `cd zig && mise exec -- zig build test -Doptimize=ReleaseSafe --summary all`:
  **33/33 passed** with leak and allocation-failure checks enabled.
- `ephemeral/zig-binary-consumer`: fresh local-path dependency compiled and ran
  using public Float16Array/DataView/copy APIs, asserting offsets/counts, shared
  buffer identity, repeated view identity, surrounding cycle, visible bytes and
  distinct copied buffer. `wire.json` exactly matches pinned JS `stringify` of
  independently constructed `{buffer,typed,again:typed,data,copy,self}` using
  bytes 0..7, Float16Array(buffer,2,2), DataView(buffer,1,3), and a visible-byte copy.
- `cd ephemeral/codec-comparison && go run ./binary`: both Go modules agree on
  **108 standalone JS-recorded ArrayBuffer documents**. They reject **108 flat-view documents** and the one custom View document
  without its reviver; example native Go typed-view encoding fails as expected. Go flat-view parity is not claimed: views are expression-only there.
- Recorder ran with Node 26.10.0 and pinned devalue 5.9.4; the existing three
  fixture files reproduced unchanged. Binary recording refuses missing Float16Array.

The strict numeric-bound/arity acceptance rules and host/runtime API differences
are documented in `zig/README.md` and `ephemeral/zig-upstream-test-coverage.md`.
No performance threshold or new general proof framework is part of acceptance.
Implementation consensus and PR CI are the remaining delivery gates.
