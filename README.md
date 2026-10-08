# devalue for Go

A Go port of [devalue](https://github.com/sveltejs/devalue), the serializer
SvelteKit uses for `load` data, remote functions and SSR hydration. It reads
and writes devalue's flat JSON-array format and emits its JavaScript
expressions, so a Go server can speak SvelteKit's wire format byte for byte.

## Which version to use

Each module tracks one devalue major, and each release matches one exact
devalue release:

| Import path | Matches | Status |
|-------------|---------|--------|
| `github.com/tylergannon/devalue/v5` | devalue **5.9.4** | Current |
| `github.com/tylergannon/devalue/v6` | currently **5.9.4**; moving to 6.x | In progress, not yet released |

Use the major that matches the devalue your SvelteKit version resolves. For
example, SvelteKit 2.x and the 3.0 prereleases depend on devalue 5, so use
`/v5`. The exact release a module matches is `devalue.UpstreamVersion`, and
the first line of each GitHub release names it.

```sh
go get github.com/tylergannon/devalue/v5
```

## Usage

```go
import "github.com/tylergannon/devalue/v5"

s, err := devalue.Stringify(devalue.NewObject("name", "Ada", "tags", []any{"a", "b"}))
// [{"name":1,"tags":2},"Ada",[3,4],"a","b"]

v, err := devalue.Parse(s, nil) // *devalue.Object; numbers are float64, null is nil

js, err := devalue.Uneval(devalue.NewObject("name", "Ada"))
// {name:"Ada"}
```

- **Value model:** `*devalue.Object` with ordered properties (`Get`, `Set`,
  `Keys`; a `map[string]any` is accepted on encode with sorted keys), `[]any`,
  `string`, the Go numeric kinds (float64 after parse), `bool`, `nil`,
  `devalue.Undefined`, `devalue.Hole`, and the tagged forms `Date`, `*Map`,
  `*Set`, `BigInt`, `RegExp`, `ArrayBuffer`, `*TypedArray`, `*DataView` and `*Boxed`.
- **Custom types:** `StringifyWith(v, reducers)` and the `revivers` argument
  to `Parse` are the flat format's custom-type hooks, tried before the
  built-ins.
- **Expressions:** `Uneval` preserves shared references and cycles, and also
  supports `URL`, `URLSearchParams` and `Temporal`, which this Go flat codec
  does not yet carry. `UnevalWith(v, replacer)` takes a
  custom hook whose result is trusted JavaScript, inserted verbatim.
- **What Go cannot express:** distinct identity for equal `Date`, `RegExp`,
  `URL`, `URLSearchParams` or `Temporal` values; shared identity for
  zero-length arrays or zero-capacity empty buffers; strings holding an unpaired
  UTF-16 surrogate. `NewArrayBuffer` preserves owned empty-buffer identity.

## Binary views and Go–Zig exchange

Both Go modules and Zig carry all twelve typed-array kinds (including
Float16Array) and DataView in the devalue **5.9.4 flat format**. Views preserve
their complete backing bytes, offset, length, repeated identity and shared
backing-buffer identity. TypedArray.ByteLength is measured in bytes; its Len()
and the wire count are measured in elements. DataView lengths are in bytes.

```go
buffer := devalue.NewArrayBuffer([]byte{0, 1, 2, 3, 4, 5})
view := devalue.NewTypedArray(devalue.Uint16Array, buffer).Subarray(1, 3)
data := devalue.NewDataViewRange(buffer, 1, 3)
wire, err := devalue.Stringify(devalue.NewObject("buffer", buffer, "view", view, "again", view, "data", data))
// Zig parses this using d.parse; Go parses Zig's corresponding documents.
```

`NewArrayBuffer` copies its input into distinct owned storage, including for
empty buffers. Reuse the returned slice to share storage; separate calls keep
distinct identity. The element constructors such as Uint8ArrayOf also own
distinct storage. Existing ArrayBuffer literals work, but nil/zero-capacity
empty slices cannot express ownership. Parse returns owned buffers and pointer
views; mutating a decoded backing byte is visible through every shared view.
Float16 storage travels as raw bytes and does not require a Go float16 type.

Ordinary subviews serialize **all backing bytes**, including bytes outside the
visible extent. For an isolated visible-byte copy use
`NewTypedArray(view.Kind, NewArrayBuffer(view.Buffer[view.ByteOffset:view.ByteOffset+view.ByteLength]))`.
Both serializers reject geometry JavaScript cannot construct. Uneval preserves
5.9.4's upstream quirk for valid typed views over odd-sized buffers; the flat
format handles their explicit extent correctly.

`just test-interop` exchanges 111 independently constructed binary cases in
both directions and checks decoded contents and reference topology. It runs
under `just test` and in CI; native Go and Zig suites need no Node. Each module's
recorder pins its own binary fixtures and expression expectations.

This shared surface does not erase native model limits: Go rejects sparse
array lengths above 2,097,152, cannot retain shared empty-array identity or
distinct identity of equal Date/RegExp values, and Zig has stricter admission
rules for manually crafted documents (see its profile). Use canonical upstream
metadata and supported values. URL/Temporal and expressions remain outside the
Zig profile. polytype/skgo still use polytype's older bundled runtime until the
separate [consumer migration](ephemeral/polytype-migration.md) lands; these
changes apply to `github.com/tylergannon/devalue/v5` and `/v6`.

Typed codecs for your own Go types can be generated with
[polytype](https://github.com/tylergannon/polytype)'s `devalue/codegen`.

## How parity is checked

Each module's `testdata/golden.json` is recorded by running the pinned
JavaScript devalue over a generated corpus of values. `go test` compares
against it without Node, alongside test expectations ported from upstream's
own suite and a goja evaluation of emitted expressions. Recording and moving
the pin are described in `vN/testdata/record/README.md`.

## Zig package

The repository root is an installable experimental Zig 0.17.0 package exporting
the codec in [`zig/`](zig/README.md). It targets
an explicit devalue 5.9.4 flat-format profile, with allocator ownership, stable
graph handles and native tests. It shares the upstream fixtures with Go;
expression generation and the excluded JavaScript types are outside this profile.
`just test` and `just lint` include both languages.

## License

This code is released under the BSD Zero Clause License (`LICENSE`). It ports
the behavior, messages and test expectations of devalue, which is MIT-licensed
(`LICENSE-devalue`).
