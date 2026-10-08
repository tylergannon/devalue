# Upstream test coverage — current basic flat milestone

Behavior authority: devalue **v5.9.4**, its complete `test/` directory downloaded
under `ephemeral/upstream-5.9.4/`. Native tests do not run Node. Expectation bytes
are produced by the existing recorder's single pinned upstream dependency.
This is a hand-written scope/coverage note, not a generated test ledger.

The user requires full upstream behavioral fidelity before landing. The latest
sequencing completes correctness of the basic flat codec first, then returns to
missing features. This note describes an interim milestone, not full parity or
permission to land the currently narrower profile.

## Native ports completed for the current profile

`zig/tests/upstream.zig` uses 79 explicitly authored fixture inputs in
`v5/testdata/record/upstream-values.mjs` and independently constructed Zig values.
It asserts encoder bytes against pinned JS, then compares decoded contents,
ordered fields/elements, scalar spellings/negative zero, node kinds and a
bijection of expected/actual handles. That checks both shared identity and equal
but distinct nodes without using the decoder to construct encoder test inputs.

- `index.test.js` common fixtures: all supported primitives and boxed primitives;
  RegExp, valid Date, Array/dense/sparse/empty/zero-order, ordinary Object, Set,
  Map, ArrayBuffer; all seven valid-UTF-8 string fixtures; all seven cycle shapes;
  primitive/boxed/container/Date/RegExp repetitions, shared Map keys and three
  interlinked Map-key identities; all four XSS fixtures; the three misc cases
  with native equivalents for classes/realms/enumerability.
- Nested Foo/Bar reducer/reviver fixture, including repeated custom identity.
  FunctionRef wrapper and nested function fixtures retain identical custom-tag
  bytes and payload contents as opaque native handles. Executing reconstructed
  JavaScript functions and checking JS `instanceof` are language-specific and
  are not operations supplied by this codec.
- All current-profile entries of the `invalid` table; every non-string
  null-prototype key and nested coerced-key attack; valid null-prototype keys;
  native `__proto__` construction rejection.
- Sparse prototype pollution/type confusion with callback-not-invoked checks;
  the original **49,000-layer** CPU-exhaustion payload; legitimate sparse
  content/length/hole checks and Set out-of-bounds rejection.
- All five `sparseDoSCases` at their original sizes: length/count
  10,000/250,000; 100,000/25,000; 1,000,000/2,500; 10,000,000/250;
  100,000,000/25. Spot assertions match upstream, with extra population and
  trailing-hole assertions. Huge length never implies dense storage.
- Both `circularCustomTypes` cases, including partially hydrated callbacks,
  memoized identity and double reviver invocation (`profile.zig`).
- `operations.test.js` and `parse-operations.test.js`: native handle identity,
  cycles, primitive/built-in construction, reducers/revivers, safe validation
  before payload revival, sparse logical length and actual population, and valid
  array-index boundaries are exercised by the ports above and existing native
  tests. Native array APIs admit indices only and reject string properties.
  These ports do not claim to implement upstream's optional operations API.

Previously hand-written native alias/cycle, built-in and boxed expectation
strings are also reproducible through the recorder's three `native_*` inputs.
The native source strings remain useful readable regression assertions.

## Outstanding behavior and API differences

These are explicit unfinished compatibility work, not test exemptions approved
for landing:

- `index.test.js`: invalid Date/custom fallback; all five lone/misordered UTF-16
  surrogate cases; URL/URLSearchParams/Temporal; typed arrays/DataView/Buffer,
  view backing-store/cycle/repetition/offset cases and malformed-view inputs.
- `buffer.test.js`: the complete Buffer/typed-view/backing-store suite awaits
  typed-view support. Visible bytes, independent Node Buffer backing copies,
  shared ordinary views and offsets need native equivalents.
- `stringify-async.test.js` and async cases elsewhere: promise/thenable discovery,
  resolution/rejection and cleanup need a defined native async integration.
- `uneval-primitives.test.js` and expression-only cases in `index.test.js`:
  JavaScript source output and expression reconstruction await `uneval`.
- JS operations override APIs (partial defaults, inheritance, frozen exports,
  proxies/getters, patched prototype methods and realm intrinsics) are not
  exposed by Graph. Their JS-specific invocation mechanics cannot be copied
  literally. Relevant wire/topology and callback invariants have native ports;
  any required additional API behavior needs explicit reconciliation.
- Upstream rich errors (`path`, `keys`, problematic value/root) differ from the
  current native error-set API. Native errors are checked by category; the
  diagnostic surface remains a compatibility decision before full parity.
- The documented canonical-only BigInt/Date/base64 acceptance rules, opaque
  RegExp metadata, UTF-8 policy, bounded depth and reducer-name restrictions
  remain explicit profile differences to reconcile before claiming full parity.
  Strict finite-integer slot references also reject malformed negative/fractional
  values that upstream sometimes hydrates as undefined. This is a decode
  acceptance difference, even though upstream encoders never produce them.

## Additional native robustness

Corpus mutations now seed all shared, Zig-profile and upstream-native documents.
Generated graphs vary strings, numbers/tags, buffers/boxes, ordinary/null objects,
Map/Set, sparse/dense population, insertion order, nested aliases and cycles;
expected topology is independently constructed. Allocation-failure injection,
input release, handle growth, malformed boxed references, repeated encoding,
and reverse/large collection correctness remain normal native Zig tests.

The failure-injection backing allocator refuses resize/remap so allocation
counts are repeatable across optimized runs; ordinary tests use the normal
leak-checking allocator and exercise growth. No timing threshold or general
performance improvement is a correctness acceptance requirement.
