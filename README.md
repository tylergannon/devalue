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
| `github.com/tylergannon/devalue/v6` | devalue 6.x | In progress, not yet released |

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
  `*Set`, `BigInt`, `RegExp`, `ArrayBuffer` and `*Boxed`.
- **Custom types:** `StringifyWith(v, reducers)` and the `revivers` argument
  to `Parse` are the flat format's custom-type hooks, tried before the
  built-ins.
- **Expressions:** `Uneval` preserves shared references and cycles, and also
  supports typed arrays, `DataView`, `URL`, `URLSearchParams` and `Temporal`,
  which the flat format does not carry. `UnevalWith(v, replacer)` takes a
  custom hook whose result is trusted JavaScript, inserted verbatim.
- **What Go cannot express:** distinct identity for equal `Date`, `RegExp`,
  `URL`, `URLSearchParams` or `Temporal` values; shared identity for
  zero-length slices; strings holding an unpaired UTF-16 surrogate.

Typed codecs for your own Go types can be generated with
[polytype](https://github.com/tylergannon/polytype)'s `devalue/codegen`.

## How parity is checked

Each module's `testdata/golden.json` is recorded by running the pinned
JavaScript devalue over a generated corpus of values. `go test` compares
against it without Node, alongside test expectations ported from upstream's
own suite and a goja evaluation of emitted expressions. Recording and moving
the pin are described in `vN/testdata/record/README.md`.

## License

This code is released under the BSD Zero Clause License (`LICENSE`). It ports
the behavior, messages and test expectations of devalue, which is MIT-licensed
(`LICENSE-devalue`).
