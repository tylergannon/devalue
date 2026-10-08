# Go–Zig binary interoperability validation

Target: upstream devalue 5.9.4, both Go modules, Zig 0.17.0. The branch
includes main's installable root package (20a8d45), and the integration recipe
runs through that root entry point; the nested Zig checkout remains supported. Plan consensus:
Claude Opus session `598b847f-2392-4c96-b083-d9fb1fa90186`, round 04 reports
**no findings**. This change closes the binary-view mismatch in the codec
modules; it does not move v6 to upstream 6.x or claim full JavaScript parity.

## Behavior

- Each Go module independently constructs all 111 binary cases and compares
  encoder bytes to its own pin-checked JS-recorded fixture. Decoder assertions
  compare native types, whole and visible bytes, geometry and a bijection of
  view/buffer/container identities. Zig does the same with graph handles.
- `just test-interop` emits Go v5 and v6 documents into a fresh temporary
  directory, Zig checks both against independent native graphs and emits fresh
  Zig-constructed documents, then both Go modules check them against their own
  native constructions. All three files must exist and have the complete case
  count/names/version. CI invokes the same command with Go and pinned Zig.
- The corpus covers all twelve kinds plus DataView, full/sub/empty-end/empty
  storage, explicit odd-buffer extents, distinct equal/repeated views, cycles,
  shared backing storage, raw NaN/negative-zero bits and BigInt bytes, Node
  visible-byte copies, file bytes, browser path and custom reducers/revivers.
  New empty-shared and Float16-value inputs are recorded directly by JS.
- Owned Go empty buffers preserve sharing without collapsing independent
  allocations. NewArrayBuffer and every element constructor provide owned
  storage. Parse allocates distinct empty buffers. Map/Set identity, copying,
  aliases with standalone buffers and zero-capacity legacy limitations have
  targeted native tests.
- Raw backing-slot and revived-buffer guards port upstream's entire applicable
  backing-buffer matrix. Callback counts, offsets, genuine buffer identity,
  cached values, array-like payloads, custom cycles and view-tag override order
  are asserted. Native geometry is shared by Stringify and Uneval. Bounds use
  subtraction/division to avoid overflow and never allocate from claimed length.
- Nine module-local pinned JS expression expectations cover Float16 normal,
  subnormal, signed zero, infinities, NaN, subviews and shared identities, plus
  empty backing sharing. They preserve both 5.9.4 odd-buffer Uneval outcomes;
  upstream 6.x constructor spelling is deliberately left to the parity bump.
- Go preserves JSON constructor coercions and ignores extra fields like the
  upstream default operations; Zig's stricter bounds/arity remain documented.
  An independent pinned-JS probe checked 221 portable coercion expectations.

## Checks

- `just test`: passed (native Zig corpus, both native Go suites and both
  directions of the 111-case binary exchange).
- `just lint`: passed (Zig format, both Go modules; zero issues/vulnerabilities).
- Zig ReleaseSafe: 33 native tests passed, 1 exchange test skipped because this
  package-only command has no peer files; the exchange runs separately in root
  test and CI and fails if explicitly invoked without its directory.
- Both Go binary fuzz targets ran for 5 seconds with two workers, passing
  approximately 119,000 and 127,000 mutated inputs respectively. Go deduplicates
  identical seed wires to 101 inputs; native case-name coverage remains 111.
- Both binary recorders ran from their own installed 5.9.4 pin under Node
  26.10.0. v6 installation reused pnpm's verified cache (zero downloads). The
  existing main and Zig scalar corpora did not change. Native tests start no Node.
- Disposable consumer copies explicitly redirected polytype/devalue runtime
  imports to this worktree's v5 module, leaving the codegen import path intact.
  Test binaries were compiled with scratch go.work and run with GOWORK=off.
  Polytype's full codegen suite and selected skgo wire/document/deferred/stream
  tests passed. Script and output: `ephemeral/verify-go-zig-consumers.sh` and
  `ephemeral/go-zig-consumer-results.txt`. An initial failure exposed the new
  runtime prefix needed by polytype's fixture source tracker; the scratch check
  includes that migration fix and the migration plan records it.

Consumer compatibility is bounded to those redirected suites, not a production
migration or full application validation. skgo's example has no frontend build
in its checkout (`web/build` contains only .gitkeep), so its full application
suite is unavailable without that separate build. No consumer checkout changed.

## Remaining shared-profile boundaries

Production polytype/skgo still import the bundled runtime until the separate
migration lands. Go's shared empty-array identity and distinct equal Date/RegExp
identity remain unrepresentable; owned empty buffers are now handled. Go's sparse
array allocation limit is 2,097,152. Go strings cannot carry lone UTF-16
surrogates. Zig excludes invalid Dates, URL/URLSearchParams, Temporal, async and
expressions, and its documented handcrafted-document acceptance is stricter.
Canonical Date/RegExp/BigInt metadata remains the shared input convention.
These are named compatibility boundaries, not a full-upstream-parity claim.
