# Zig devalue development plan

## Intended result

A separate, directly consumable Zig package under `zig/` that encodes and
decodes devalue's flat format, preserves graph identity, and has explicit
allocation and lifetime contracts. Its first compatibility target is
**devalue 5.9.4**, with **Zig 0.17.0** as the compiler pin.

The first deliverable is a documented flat-codec profile, not a claim of full
JavaScript API parity or a finished native client. It covers the Go runtime's
value-family subset listed below, with deliberate Zig ownership and identity
semantics. The JavaScript implementation is the behavior authority; Go is a
useful comparison implementation, not an oracle for JavaScript semantics.

User-approved direction: write the graph codec in ordinary Zig, share upstream
test expectations, prove content and identity independently of round trips,
and measure performance before optimizing. Comptime may later specialize typed
Zig adapters using the same wire rules. This assignment prepares and reviews
the plan; codec implementation starts after this planning phase.

User clarification (2026-10-07): before landing, use the pinned upstream's full
behavioral test suite, ported or adapted to native Zig, with no lower test
fidelity. Tooling-only and language-specific mechanics may be excluded, but
their applicable codec invariants must still be tested. An unimplemented
behavior is not by itself a reason to omit its upstream test. Reconcile the
existing profile exclusions with this requirement before landing rather than
claiming full behavioral parity from a narrower corpus. This requirement does
not require completing all ports immediately.

Prioritize correct behavior and a usable first library version. Performance
optimization follows once that version works and can be used. Descending or
otherwise adversarial insertion orders belong in correctness tests, but optimal
complexity for every order is not an initial acceptance criterion. Preserve
upstream resource-safety behavior without making general speed optimization a
prerequisite for the first working version.

## Scope and contracts

The initial supported values are null, undefined, booleans, JavaScript f64
numbers including NaN/infinities/negative zero, valid UTF-8 strings, decimal
BigInts, ordered ordinary and null-prototype objects, dense and sparse arrays,
Map, Set, valid Dates, RegExp, ArrayBuffer, and boxed primitives. Include custom
reducers and revivers for consumer-defined flat-format tags. Define the precise
callback signatures at the public API milestone, with native examples and tests.

Object-like values have reference identity, including empty arrays/buffers and
equal-but-distinct Date/RegExp instances. Primitive deduplication and traversal
order follow upstream. Go's representational limitations do not become Zig
identity rules. Map/Set insertion uses JavaScript SameValueZero for primitives
and reference identity for object-like values, including normalizing a -0 key
to +0 and deduplicating NaNs. BigInt is canonical decimal data (`0` or an
optional minus followed by a nonzero digit and decimal digits), not a new
arithmetic library; native construction and parse reject noncanonical forms.
JavaScript's lenient parse of whitespace, empty strings, hexadecimal and other
BigInt spellings is an explicit acceptance exception in this first profile.
Number is f64, so there is no implicit wide-integer conversion policy to hide.

RegExp stores opaque JavaScript-canonical `source` text, not a raw pattern to
compile. Callers supply the equivalent JS `RegExp.source` (including `(?:)`
for an empty pattern and escaped slash/line terminators); the codec writes that
text with JSON escaping only. Flags accept `d g i m s u v y`, reject duplicates
and simultaneous `u`/`v`, and emit in `dgimsuvy` order. Decode preserves source
text rather than invoking a regex engine; noncanonical/malformed pattern text
is not normalized or syntax-validated as `new RegExp` would do. Document this
profile exception and test canonical upstream forms separately.

Date represents integral epoch milliseconds within inclusive ±8.64e15 ms.
Encoding emits UTC `toISOString` spelling with exactly three fractional digits,
four-digit years in 0000–9999, and signed six-digit expanded years outside that
range. Decode accepts only this canonical grammar and valid calendar/range
values; JavaScript's other `new Date(string)` spellings are an explicit
acceptance exception. Invalid Date values remain excluded.

Strings in this first profile are valid UTF-8. Native string construction
rejects invalid UTF-8 with an unsupported-string error; any direct-string
encoding entrypoint must use the same policy. Parsing raw invalid
UTF-8/WTF-8 bytes or an escaped unpaired surrogate (`\uD800` or `\uDC00`,
including either beside ordinary text) returns an invalid-document error;
valid escaped surrogate pairs decode normally. No path silently substitutes
U+FFFD. This is a documented decoder limitation relative to JavaScript's
UTF-16 strings and is compatible with Zig 0.17's JSON scanner. Invalid Date values,
URL/URLSearchParams, Temporal, typed-array/DataView views, promises/functions,
and JavaScript expression generation are outside this first profile. Recognized
excluded value tags report unsupported values; unknown unregistered tags report
an error. Do not market this subset as complete upstream feature equivalence.

Devalue owns serialization. HTTP, SvelteKit argument canonicalization, query
caching, generated Swift models/calls, and the consumer's deployment remain
consumer-owned. No Go module/import-path changes, Go v6 migration, external
schema generator, source-emitting build pipeline, generalized serialization
framework, or release publication is included.

All successful encodes match the pinned upstream bytes for equivalent values
within the profile. Decoding preserves values and graph topology; it is not
obliged to reproduce JavaScript's incidental exception text for malformed input.
Native errors distinguish invalid documents, unsupported values, caller callback
errors, and allocation failure. If upstream accepts a noncanonical or malformed
shape that Zig rejects for safety, record the exception explicitly instead of
claiming identical acceptance behavior.

## Architecture direction

- Use one graph-aware value representation with explicit ordered properties,
  array holes, and reference identity. Stable node handles are preferred over
  pointers into growable storage. Internal node IDs are not wire slot IDs:
  encoding assigns slots in upstream traversal order and deduplicates primitives.
  Public object enumeration has JavaScript order as a graph invariant: canonical
  array-index keys in `0 .. 2^32-2` sort numerically before other string keys in
  insertion order. Updating a string property keeps its position; deleting and
  reinserting it moves it to the end of the string-key group. The encoder consumes
  this enumeration. No general UTF-16 sorting or unordered-map fallback is added.
- A graph/result owns its storage through a caller-supplied allocator and has
  one clear release operation. Parsing owns all retained input-derived data by
  default; destroying the input buffer after parse must be safe. Borrowing and
  zero-copy modes are deferred until a consumer and measurements justify them.
  Document that handles are meaningful only in their owning graph; reject
  out-of-range handles and expose no naked movable-node pointers.
- Sparse arrays retain logical length plus populated elements. Operations must
  not allocate or scan proportional to a huge logical length when the upstream
  sparse representation needs only a few entries. Preserve holes separately
  from explicit undefined. Use checked arithmetic for lengths and wire indices.
- Keep traversal/indexing, primitive spelling, tag handling, and memory ownership
  easy to inspect. Prefer compact tables and shared output buffers over per-node
  temporary strings. Use Zig's JSON scanning/parsing primitives where useful;
  avoid constructing a generic JSON value tree and then a second devalue tree.
- Reducers/revivers participate in the same graph and identity bookkeeping.
  Their order, built-in override precedence, invocation count, replacement
  traversal, failure behavior, and circular-reference behavior need upstream
  evidence. Multi-stage encoding must not invoke callbacks again while emitting.
  Specifically, special sentinels bypass reducers; other newly encountered
  values receive their slot before ordered reducers run. JavaScript-falsy
  replacement values mean no match, including zero, false, null, empty string,
  undefined, NaN and zero BigInt. A matching replacement traverses the same
  identity table, including back-references to the original value. Revivers
  override built-in tags by name and receive decoded referenced/inline payloads.
  A custom cycle resolves when the payload slot is already cached, even if the
  container is only partially populated. Reject a payload only when it is being
  hydrated and is not cached, such as the infinite document `[["Custom",0]]`.
  Reproduce upstream's reentrant/double reviver invocation for a self-reference:
  callbacks can observe a graph-owned partially populated payload handle and
  later receive that same payload again. The callback context can memoize by
  payload identity and return the same graph-owned result handle on both calls.
  This responsibility and the observable invocation sequence belong in the
  public callback contract; do not promise single invocation for revivers.
  Port both `circularCustomTypes` cycle shapes from the pinned upstream tests,
  including memoized result identity and partial/full-payload observations,
  alongside the infinite-payload rejection. Pin callback
  counts and precedence to `src/stringify.js`'s flatten/reducer loop and
  `src/parse.js`'s reviver branch at v5.9.4 before defining native signatures.
  Reducer names containing quotes, backslashes, ASCII control characters, or
  invalid UTF-8 are rejected as invalid reducer names. This deliberate exception
  avoids upstream's raw reducer-name interpolation producing invalid JSON;
  test the rejection explicitly rather than silently rewriting names.
- Comptime supplies normal generic helpers where needed. A typed adapter is a
  later consumer-driven addition, not a second codec. It must preserve the same
  ordering/indexing/escaping rules and have an explicit pointer/identity mapping.
  Swift types are not automatically visible to Zig comptime.

## Development milestones

### 1. Runnable package and value ownership

Establish `build.zig`, `build.zig.zon`, one public root module, native tests, and
an allocator-aware graph/result API. Define scalar values, reference-bearing
nodes, ordered properties, sparse arrays, and valid-handle/lifetime contracts.
Keep module internals proportional to the implementation; this plan does not
require a particular file per type or a new abstraction layer.

Define `just test-zig` to run `mise exec -- zig build test` inside `zig/`, and
`just lint-zig` to check formatting of package/build/test Zig files. Extend
`just test` and `just lint` to include those recipes alongside the existing Go
checks. CI gains a separate Zig job installing `just` and the pinned 0.17.0
toolchain and running the same two Zig recipes. A deliberate failing Zig test or formatting
error must fail the relevant aggregate recipe and CI job; do not leave Zig
verification as an agent-only manual check.

Exit evidence: a separate Zig consumer can import the package using a local
path dependency and construct shared references and a cycle. Native tests show
identity survives storage growth, distinct empty values remain distinct, graph
release frees all allocations, and failure during construction leaks nothing.
No encoding/decoding parity is claimed yet.

### 2. Ordinary values and reference graph

Implement parse/stringify for ordinary objects, arrays, scalars, and sentinels.
Give string escaping and ECMAScript number spelling direct tests early; valid
JSON alone is insufficient. Register containers before resolving their edges
so cycles and forward references reconstruct correctly. Preserve upstream
property order, including integer-index keys before other insertion-order keys.

Exit evidence: independently built values encode to upstream bytes; independently
asserted decoded contents distinguish null/undefined/hole/negative zero; aliasing
and cycles are checked by handles and mutation of a shared target. Malformed
references and syntax fail without a crash or partial owned result.

### 3. Complete initial profile and corpus

Add sparse arrays, built-in tagged values, reducers/revivers, and their error
paths. Read the existing `v5/testdata/golden.json` from its current location;
do not move or duplicate it simply to accommodate a Zig test build. The normal
Zig suite never executes Node. Support fixture lookup without making the
installed library depend on the test corpus: the test run step sets its working
directory to the Zig package root with `setCwd(b.path("."))`, and native tests
read `../v5/testdata/golden.json` using `std.testing.io`. The fixture is read at
test runtime, never embedded by the public library. A test-only build option
can override the runtime path. The checked-in probe under
`ephemeral/zig-fixture-access/` verifies this mechanism on 0.17.0 from a separate
build root; no `b.path("../v5/...")` or cross-root `@embedFile` is required.

Exit evidence: all **359** existing 5.9.4 corpus documents decode and re-encode
to their recorded flat bytes. Independent native construction/content/identity
tests exercise every supported family and codec branch; corpus round trips are
supplemental evidence, never the sole proof. Additional expectation bytes come
from pinned JavaScript, and source-derived tests cite the exact upstream tag.
Cases added to recording tooling obey the existing `pnpm` and shasum rules.
Expand the shared recorder/corpus with boxed Boolean/String, additional
Date/RegExp/Map/Set/ArrayBuffer/null-prototype cases, and supported identity
shapes. Go-model-compatible additions go through `v5/testdata/record/main.go`
and are re-recorded from its exact JS pin, with the Go tests checked afterward.
Zig-only shapes such as distinct empty-reference identity get
`zig/testdata/flat-golden.json`. Extend the existing
`v5/testdata/record/record.mjs` with that second output and explicitly authored
Zig-profile JS inputs, using the same installed `v5/package.json` devalue pin
and version guard. The Zig native version test holds its target, both corpus
metadata versions, and the recorder package pin equal to 5.9.4. No second JS
dependency pin or changes to Go's value model are required. Native content/identity
assertions are independently authored in Zig, not inferred from fixture parsing.

### 4. Robustness and usable library

Make allocation, input lifetime, handle validation, and error contracts hold
through the full codec, including callbacks. Exercise deep graphs with explicit
work stacks or a documented bounded error before call-stack exhaustion. Add
deterministic mutation/property coverage seeded from the corpus: rejection or
successful bounded parsing, no memory corruption, and semantic/identity-preserving
encode/decode for generated supported graphs. Preserve native regressions for
any discovered defect; do not add a provenance/claims tracking system.

Exit evidence: allocation-failure injection completes for representative cases
through each allocating operation and late cleanup path; input buffers can be
freed/overwritten after parse; deep/cyclic and huge-sparse cases do not crash or
expand into dense storage. A fresh consumer parses, inspects, encodes, and frees
a value with no repository-private imports. Package usage and limits are clear.

### 5. Measured performance and implementation review

Benchmark encoding and decoding separately on prebuilt payloads, outside
network/client overhead. Include a small query-shaped object, a 1,000-record
list, repeated strings/aliases, escape-heavy text, and a million-length sparse
array with three populated entries. Fix the data and operation boundaries before
comparison. Check output/content equivalence before accepting timings.

Compare with the Go v5 codec where the value is representable. Build a scratch
Go comparator under `ephemeral/` rather than changing the Go runtime. Include
output allocation/release in the stated operation boundary; disclose Go GC and
Zig ownership differences. Record compiler/toolchain, CPU, optimization modes,
payload/output sizes, repeated-run time distributions, and allocation counts/
bytes. Report results separately by workload, not as a universal language claim.

Defer performance optimization until the first correct, usable version exists;
then optimize only measured bottlenecks while preserving parity and memory behavior.
No arbitrary speed multiple is a readiness requirement. If results do not support
the intended speed advantage, state that and identify the measured bottleneck;
do not call the package fast on the strength of its implementation language.
Typed comptime adapters, SIMD, buffer-reuse APIs, and custom numeric scanners
are justified follow-ups only when a consumer or measurements call for them.

Exit evidence: reproducible benchmark source/results, a passing native consumer
smoke test, repository checks, and an independent implementation/proof review
resolved through consensus. Shipping a native-client integration, merging a PR,
tagging, and publishing are later explicitly scoped work.

## Test contract

Tests belong in Zig. Pinned JavaScript may generate expected fixture data;
it is never invoked by `zig build test` or `go test`. Do not use a JavaScript
interpreter, generated ledgers, or copied Go outputs as an expected-value oracle.

Before landing, port or adapt the complete pinned upstream behavioral suite,
including malformed-input and resource-safety regressions. Preserve each test's
behavioral assertions and edge cases; round-trip goldens do not replace them.
Only tooling-only or language-specific details may be excluded, with the reason
stated alongside the affected native tests or in a short human-written note.
Adapt equivalent native behavior where JavaScript mechanics differ. Resolve any
remaining feature/profile mismatch explicitly before claiming upstream parity.

| Behavior | Evidence that can fail independently |
| --- | --- |
| Version binding | Compiler pin is 0.17.0; Zig upstream target, `v5/testdata/golden.json` metadata, `zig/testdata/flat-golden.json` metadata, and `v5/package.json` devalue pin agree at 5.9.4. The existing recorder rejects an unexpected installed version. |
| Encoder bytes | Native graph construction plus upstream-recorded bytes, including traversal order and equal-but-distinct reference values. No decoder in the arrange step. |
| Decoder contents | Explicit scalar/field/element/tag assertions against native expectations. No encoder determines expected values. |
| Graph identity | Same target referenced twice, distinct equal targets, self-cycle, mutual cycle, and Map/Set edges; assert handles and shared-target mutation. Include empty arrays/buffers. |
| Number spelling | Zero vs negative zero; NaN/infinities; 1e-6/1e-7 and 1e20/1e21 boundaries and adjacent f64 values; safe-integer boundary, smallest subnormal, largest finite value. |
| Strings and keys | Controls, quotes/backslashes, `<`, U+2028/U+2029, BMP/astral Unicode; index-key boundaries `"01"`, `"4294967294"`, `"4294967295"`, `"-1"`, `"1.0"`; non-index Unicode keys stay in insertion order. Invalid native UTF-8 returns unsupported-string; raw WTF-8 and escaped unpaired high/low surrogates return invalid-document; valid surrogate pairs succeed. No Kit canonicalization. |
| Sparse arrays | Dense/sparse choice immediately below/at/above the upstream cost boundary; zero population, holes vs undefined, cycles/aliases, and huge logical length with three populated indices. |
| Tagged values | Every included tag, exact payload spelling, and distinct/shared identity. BigInt canonical decimal and rejected noncanonical spellings; base64 validity; RegExp canonical source examples, flags order/duplicates/u-v exclusion and documented opaque-source behavior; Date ±8.64e15 ms boundaries, four/signed-six-digit years, exact milliseconds, calendar validity and rejected noncanonical date strings; excluded/unknown tags. |
| Custom callbacks | Competing reducers, built-in overrides, reducer identity invocation counts, falsy replacement/non-match cases, rejected unsafe reducer names, referenced/inline payloads, and callback failures. Port both upstream `circularCustomTypes` cycle shapes; assert the self-reference reviver's double invocation, partial/full payload views, and memoized shared result handle. Reject the infinite `[["Custom",0]]` payload. |
| Malformed input | Empty/non-document roots, fractional/out-of-range references, malformed tags, non-string null-prototype keys, `__proto__` keys, invalid sparse indices/lengths, truncated JSON/base64, and arithmetic overflow. Expected accept/reject behavior is anchored in the chosen profile and upstream evidence. |
| Allocation failure | `std.testing.checkAllAllocationFailures` through graph creation, parse, stringify, and callbacks that allocate; leaks/double frees/partial results fail the test. |
| Lifetime and growth | Free/overwrite source bytes after parse; grow backing storage after retaining handles; encode repeatedly without mutating the input graph; release after partial failure. |
| Deep input | Deep chains/cycles either complete using bounded stack space or return the documented depth/resource error, with cleanup. |
| Corpus regression | Every existing named corpus case is enumerated; skipped cases fail. Parse/re-encode equality supplements the independent tests above. |
| Public consumption | Fresh local-path consumer builds and exercises only public APIs, including cleanup. |
| Performance | Same data/semantics and operation boundaries, verified output, repeated timings, allocation counts/bytes, and stated compiler/mode/platform. |

## Completion and authoritative references

Implementation is ready for its scoped handoff when the supported profile is
documented, all milestone evidence above exists, native tests and formatting
pass under the pinned compiler, `just test` and `just lint` pass, benchmarks
honestly describe the results, and implementation/proof consensus has no material
findings. Plan consensus does not prove runtime behavior or shipping readiness.
Landing additionally requires the full upstream behavioral test fidelity stated
above. Performance tuning is deferred work, not a prerequisite for a correct,
usable first version.

- Repository `AGENTS.md` and `zig/AGENTS.md`; user-approved scope in this plan.
- [Pinned upstream source](https://github.com/sveltejs/devalue/tree/v5.9.4),
  particularly `src/stringify.js`, `src/parse.js`, `src/constants.js`, and
  `src/utils.js`. Upstream tests come from the GitHub tag, not the npm tarball.
- `v5/testdata/golden.json`, `v5/testdata/record/README.md`, and native Go
  tests as comparison cases; limitations or malformed-input policies need an
  explicit Zig decision rather than accidental inheritance.
- `.agents/skills/zig-development/SKILL.md`, the adapted
  `.agents/skills/zigcc/zig-0-17/SKILL.md`, the installed 0.17 library source,
  and [the versioned Zig reference](https://ziglang.org/documentation/0.17.0/).
