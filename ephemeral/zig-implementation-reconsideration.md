# Implementation reconsideration — 2026-10-07

The user asked to pause and reconsider collection storage, decoder architecture,
and upstream test coverage after the first Claude Opus implementation review.
Further production changes paused while this audit was performed. The build is
unaccepted; the first review still has material findings.

## What went wrong

The first implementation preserved upstream traversal and wire-slot rules but
substituted linear collection lookup and sorted insertion. Matching traversal
does not preserve complexity when the supporting containers change. The five
benchmark workloads did not expose large keyed collections or descending index
insertion. The mutation test used one handwritten seed, and generated graphs
were too narrow. Corpus round trips were allowed to stand in for more complete
behavioral coverage. Those are implementation and validation mistakes, not
limitations of Zig.

The generic JSON tree was also a deviation from the approved scanner direction.
Recording that choice in the worklog did not amend the approved design.

## Collection findings

The installed Zig 0.17.0 standard library provides HashMap, StringHashMap,
AutoHashMap, and their unmanaged forms. It also provides ArrayHashMap forms:
array_hash_map.zig documents insertion-order preservation, O(1) swap removal,
O(n) ordered removal, and O(n) reIndex after direct entry changes.

Use standard hash lookup with explicit semantic enumeration order. ArrayHashMap
is a reasonable candidate for insertion-ordered Map/Set storage; separate
ordered entries plus a standard hash index is also valid. Choose between these
by representation simplicity and measured allocation cost, rather than inventing
a hash table. JavaScript integer property ordering and sparse array ordering
still require ordered enumeration; batch sorting avoids shifting all existing
entries on each reverse insertion. Binary search alone only improves lookup:
maintaining sorted contiguous storage by insertion can remain quadratic.
Bucket/radix sorting is a possible measured optimization for integer keys, not
a prerequisite for this codec.

The current uncommitted revision already replaces linear lookup with standard
hash indexes and lazy ordered views, caches owned-string validation/hashes, and
uses a Scanner token tape instead of std.json.Value. These changes have native
test passes but have not received another Opus review or refreshed comparative
performance validation. Borrowed-string alias cost and read-time internal
normalization still deserve inspection before accepting this representation.

## Upstream test audit and required coverage

All six test files from the pinned v5.9.4 tag are downloaded alongside this note
under upstream-5.9.4/. Source:
https://github.com/sveltejs/devalue/tree/v5.9.4/test

- index.test.js contains shared primitive/boxed/tag/string/cycle/repetition/XSS
  fixtures, malformed-document cases, null-prototype key guards, sparse attacks,
  five large sparse allocation cases, and circular custom-type behavior. Port
  every applicable flat-profile case into native Zig tests, citing its source.
  Independently construct encoder inputs and inspect decoded contents/identity;
  do not count a parse/stringify round trip as both proofs.
- operations.test.js and parse-operations.test.js exercise JavaScript operations
  override APIs that this package does not expose. Their relevant invariants
  still apply: identity, constructed handle graphs, safe key validation before
  hydration/callbacks, sparse length/population separation, reducer/reviver
  behavior, and input preservation. Port those native equivalents. Do not label
  the entire files inapplicable merely because the API differs.
- buffer.test.js exercises Node Buffer and typed views, including visible slice
  bytes and shared backing stores. Typed-array/DataView support is excluded from
  the reviewed profile. ArrayBuffer semantics remain applicable elsewhere.
- stringify-async.test.js exercises promises/thenables and async serialization;
  uneval-primitives.test.js exercises expression generation. Those APIs remain
  excluded by the approved first profile.

Invalid Date, lone UTF-16 surrogates, URL/Temporal, JS symbols/functions,
typed views, async, expressions and JS realm/prototype introspection cannot be
claimed as supported by this native profile. Explicitly identify exclusions
instead of silently dropping tests or expanding scope to achieve an artificial
"all upstream tests" count.

Native robustness additionally needs allocator failure, ownership after freeing
input, handle growth, strict error categories, corpus-seeded mutations, varied
generated supported graphs, and adversarial collection scaling. Keep these as
ordinary Zig tests and small benchmarks; no proof framework or generated ledger.

## Resumption condition

Keep the ordinary Zig graph codec and approved scanner architecture. Resume
implementation toward correct behavior and a usable public library, supported
by upstream-native test ports and public-consumer/Go comparisons. Do not require
optimal descending-insertion complexity or allocation tuning first. Preserve
upstream resource-safety behavior. Request whole-deliverable
re-review in the same Claude Opus consensus session. No equivalence or completion
claim is justified before those checks and review converge.

User clarification after this audit: before landing, the full upstream
behavioral suite must be ported/adapted with no lower test fidelity. Only tooling
or language-specific mechanics justify exclusion; retain their relevant native
codec invariants. Previously approved feature omissions are not automatic test
waivers and must be reconciled before claiming parity. All ports need not be
completed immediately. Performance optimization follows a correct, working,
usable first version rather than gating it.
