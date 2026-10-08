# Zig devalue

An experimental allocator-aware flat-format codec targeting **devalue 5.9.4**,
with **Zig 0.17.0**. Successful encodings match upstream JavaScript bytes for
values in the profile below. The Go v5 and v6 implementations currently target
the same release; their flat codecs do not yet support binary views. This package
does not implement `uneval` expressions or claim
all JavaScript devalue features.

Import the `devalue` module from a Zig path dependency on this directory:

```zig
const dependency = b.dependency("devalue", .{ .target = target, .optimize = optimize });
root.addImport("devalue", dependency.module("devalue"));
```

```zig
const d = @import("devalue");
var graph = d.Graph.init(allocator);
defer graph.deinit();
const object = try graph.object(false);
try graph.put(object, "message", try graph.string("Hello <Zig>"));
try graph.put(object, "self", object);
const bytes = try d.stringify(allocator, &graph, object, &.{});
defer allocator.free(bytes);
var result = try d.parse(allocator, bytes, &.{});
defer result.deinit();
const message = (try result.graph.get(result.value, "message")).?;
// message.string is owned by result.graph; bytes may already be freed.
```

## Profile

Supports null, undefined, bool, JavaScript f64 numbers (including NaN, infinities,
and negative zero), valid UTF-8 strings, canonical decimal BigInt, ordered plain
and null-prototype objects, dense/sparse arrays, Map, Set, Date, RegExp metadata,
ArrayBuffer, all twelve typed-array kinds (including Float16Array), DataView,
boxed primitives, ordered reducers and named revivers. Objects use
JavaScript enumeration order: integer-index keys first, then string keys in
insertion order. Map/Set use SameValueZero: NaN deduplicates, zero keys become
positive zero, and reference nodes compare by identity. Equal but distinct
Dates, regexps, empty arrays and buffers retain distinct handles.

Excluded: unpaired UTF-16 surrogates, invalid Dates, URL/URLSearchParams,
Temporal, promises/functions, async serialization and
expression generation. Recognized excluded tags return `UnsupportedValue`;
unknown tags return `InvalidDocument`. HTTP, Kit canonicalization and caching
belong to consumers.

Explicit decode acceptance differences from JavaScript:

- BigInt must be `0` or optional minus plus nonzero decimal digits. Whitespace,
  hex, empty strings, leading zeroes and negative zero are rejected.
- Date stores integral epoch milliseconds within ±8.64e15. Decode accepts only
  canonical UTC ISO strings, with three millisecond digits and either four-digit
  years or signed six-digit expanded years. Other JS Date strings are rejected.
- RegExp source is opaque metadata, without a regex engine. Supply canonical
  JS `RegExp.source` text (empty source is `(?:)`, slash/line terminators escaped).
  Decode preserves source text without JS syntax validation/normalization.
  Flags accept `dgimsuvy`, canonicalize order and reject duplicates and `uv`.
- Base64 requires canonical padded RFC 4648, including zero pad bits; malformed
  tag arity/reference types are rejected even where JavaScript is permissive.
- Binary views accept only finite nonnegative safe-integer bounds and two to
  four tag fields. JS also accepts coercible string/null/fractional bounds and
  ignores extra fields; this profile rejects them. For example a JS null length
  means an empty view, and fractions between -1 and 0 coerce to 0. Negative
  integer bounds, misaligned typed offsets and out-of-range extents are rejected
  by both. Omitted offset/count uses the whole buffer; offset alone uses the
  remaining bytes. A whole/remainder typed extent must be divisible by element
  width; an explicitly bounded typed view may use an odd-sized buffer.
- Slot references must be finite integers: a valid nonnegative slot or a known
  sentinel in its allowed context. Fractional, non-sentinel negative and
  out-of-bounds references return `InvalidDocument`. Upstream accepts some
  malformed negative/fractional references as undefined; this profile rejects
  them (for example `[[-8]]`, `[[0.5]]` and `[["Object",-2]]`).
- Invalid UTF-8/WTF-8 and unpaired surrogate escapes are invalid documents.
  Native string construction rejects invalid UTF-8 with `UnsupportedString`.
- `__proto__` properties are rejected, as upstream requires.

## Binary views

```zig
const buffer = try graph.arrayBuffer(&.{ 0, 1, 2, 3, 4, 5 });
const view = try graph.typedArray(.Uint16Array, buffer, 2, 2); // element count
const data = try graph.dataView(buffer, 1, 3);               // byte count
const visible = try graph.viewBytes(view); // read-only bytes 2,3,4,5
const copy = try graph.uint8ArrayCopy(visible);
```

Views reference a buffer in the same graph without copying it. Their handles
and backing-buffer identity survive graph growth. **Serializing an ordinary
subview includes its entire backing buffer**, including bytes outside the view.
`uint8ArrayCopy` copies only the supplied visible bytes into a fresh Uint8Array
and fresh buffer, matching upstream's Node Buffer normalization. Reuse its
returned handle for repeated references; separate calls produce distinct copies.
`viewBytes` borrows graph-owned storage until graph deinitialization.

The codec preserves raw bytes rather than converting numeric elements or casting
byte slices to typed pointers. Consumers interpreting multi-byte elements must
choose their own byte order. These are fixed owned buffers, without JS realms,
getters/proxies, SharedArrayBuffer synchronization or resizing/detachment APIs.
Decode requires an ArrayBuffer-tagged raw slot and a genuine buffer node after
revival; array-like values cannot cause length-based buffer allocation. Revived
non-buffers return `InvalidDocument`, invalid callback handles `InvalidHandle`.
View-tag revivers retain their normal override precedence.

## Ownership and callbacks

Never copy a live `Graph` or `ParseResult`: there is exactly one owner and one
`deinit`. Constructors copy strings, property keys and buffers into graph-owned
storage. Parsed graphs own all retained bytes and never borrow the input.
Direct `.string`/`.bigint` union literals are borrowed: their bytes must remain
valid and immutable while retained. Prefer `graph.string`/`graph.bigint` for
retained dynamic data.
Handles are meaningful only in their owning graph; bounds are checked but a
handle from another graph cannot be detected. Handles survive graph growth.
`node` normalizes enumeration order in internal storage. Node views and slices
are read-only snapshots, valid only until graph mutation;
use methods to mutate rather than writing graph internals. Removing/replacing
values does not reclaim individual arena allocations; `deinit` releases them.

`stringify` returns allocator-owned bytes that the caller frees. Reducers can
allocate replacement nodes in the input graph, which retain normal graph
ownership even on callback/encoding failure. They must not mutate the containers
being traversed. Reducers run in supplied order on newly indexed values; shared
values invoke them once. Undefined and special numbers bypass them. To port a JavaScript reducer object, supply unique names in its
`Object.getOwnPropertyNames` order: numeric index names first, then string names.
The Zig slice intentionally specifies this order directly. A returned
null optional or JavaScript-falsy `Value` declines the match. Names containing
quotes, backslashes, controls or invalid UTF-8 return `InvalidReducerName`, an
explicit exception to upstream's unsafe raw-name interpolation.

Revivers override built-in tags by name and receive decoded referenced or inline
payloads. A custom cycle can invoke a reviver twice on the same payload, first
partially populated and later complete. Memoize by payload handle in context to
return the same result identity. Infinite uncached custom payload dependencies
return `InvalidDocument`. Callbacks return `CallbackError` for their own failures;
allocator failure remains `OutOfMemory`. Callback context remains caller-owned; discard handles retained by context
when parsing fails. There is no implicit transactional rollback of callback
side effects.

Both wire JSON nesting and recursive graph traversal are limited to 256 levels;
more returns `DepthLimit`. Cached aliases/backreferences terminate traversal.
Collection lookups use hash tables. Ordered views are sorted lazily, with
O(n log n) enumeration for reverse index keys/array indices; strings owned by
the graph cache validation and hash data. Sparse arrays retain logical `u32`
length and populated entries, so huge
sparse lengths never allocate dense storage. Input byte count and graph population
are bounded by available memory. Graph access is not thread-safe: `node` and
`stringify` can sort internal storage and rebuild indexes even when the caller
does not change values. They require exclusive access to the graph, as do
mutation and callbacks; synchronize shared use externally.

## Development

From repository root: `mise install`, then `just test` and `just lint` include
Zig alongside Go. `just test-zig` runs native tests without Node. The shared corpus
stays in `../v5/testdata/golden.json`; `-Dgolden=/absolute/path` overrides lookup.
The test run always executes, so runtime fixture/pin changes cannot reuse a cached
success. These tests require the repository checkout. `just record v5` regenerates
the shared corpus, `zig/testdata/flat-golden.json`, and the upstream-native
`zig/testdata/upstream-flat-golden.json`, and `zig/testdata/binary-golden.json`
from the single pinned JS package. Binary recording requires Node with
Float16Array (Node 26+); native tests need no Node installation.

`cd zig && mise exec -- zig build bench -Doptimize=ReleaseFast` runs five repeated
encode/decode benchmarks, including output allocation/free and parsed graph
release. `-- dump` writes workload documents for direct Go comparison. No speed
claim follows from language choice; results vary by workload and allocator.

This package is BSD-0-Clause (`LICENSE`); upstream devalue attribution and its
MIT license are included in `LICENSE-devalue`.
