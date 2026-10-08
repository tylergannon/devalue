# Adversarial review: Go–Zig binary flat-codec interoperability plan (round 01)

## Target

`ephemeral/go-zig-flat-parity-plan.md` (untracked, on branch
`codex/go-zig-flat-parity` at `b55f530`), with its worklog
`ephemeral/worklog/20261008-go-zig-flat-parity.md`.

Caller constraints honoured: read-only apart from this artifact. The launch
prompt did not narrow the review's scope.

## Evidence inspected

- Repository instructions: `AGENTS.md`/`CLAUDE.md` (parity promise, versioning,
  consumers, working rules), `justfile`, `.github/workflows/{go,zig}.yml`.
- Go model and serializers (v5; v6 is a copy): `v5/uneval_value.go` (kinds,
  `BytesPerElement`, `TypedArray`/`DataView`, uneval `refKey`),
  `v5/typedarray.go` (`typedArrayElements`), `v5/uneval.go` (walk/render of views),
  `v5/stringify.go` (flatten/reducers/serialize), `v5/internal.go` (stringify
  `identityKey`), `v5/parse.go` (entry, hydrate, ArrayBuffer), `v5/golden_test.go`.
- Recorder: `v5/testdata/record/{record.mjs,binary-values.mjs,README.md}`,
  `v6/testdata/record/` listing.
- Upstream devalue 5.9.4 (installed pin `v5/node_modules/devalue`, version
  checked): `src/stringify.js:303-344`, `src/parse.js:174-207`,
  `src/operations.js` (`viewInfo`, `fromViewInfo`), `src/uneval.js:122-137,
  338-400, 634-652`; upstream tests in `ephemeral/upstream-5.9.4/`
  (`parse-operations.test.js:180-330`, `buffer.test.js`, `index.test.js:297-770`).
- `ephemeral/devalue-parity/5.9.2-to-6.0.2.md` (v6 work list), `zig/README.md`.
- Consumers: `/Users/tyler/src/skgo/go.mod`, skgo imports,
  `/Users/tyler/src/polytype/devalue/codegen/generate.go`.
- Scratch reproduction (outside the repository) of the Float16 Uneval path.

## Findings

### 1. critical — Adding Float16Array to the Go model leaves `Uneval` silently wrong; the plan makes rendering optional

**Kind:** incomplete requirement / verifiable bug.

The plan (lines 12-13) makes Float16Array a Go typed-array kind, then says
"Float16 adds raw storage transport; any addition to expression rendering must
also have independent upstream expression expectations" (lines 39-40). That
treats Uneval support as optional. The repository's promise is not optional:
"For every value the Go model can express, `Stringify` and `Uneval` write the
bytes that devalue release writes" (`AGENTS.md`, "The promise this repository
makes"). Upstream 5.9.4 renders Float16Array in `uneval`
(`src/uneval.js:343` and `stringify_typed_array_elements`, `src/uneval.js:643-648`,
including the `-0` rule).

Stringify and Parse validation need `BytesPerElement` to return 2 for the new
kind. `typedArrayElements` (`v5/typedarray.go:28-53`) has no Float16 case, so
every element renders as `""`, and Uneval returns corrupt JavaScript with a nil
error. I reproduced this in a scratch copy of v5 after adding only the constant
and the `BytesPerElement` case:

```
1 elements: "new Float16Array([])"   err=<nil>   // upstream: new Float16Array([0])
2 elements: "new Float16Array([,])"  err=<nil>   // upstream: new Float16Array([0,0])
3 elements: "new Float16Array([,,])" err=<nil>
```

The emitted expression even has the wrong length. The comment on the kinds
(`v5/uneval_value.go:43-45`, "Float16Array is deliberately absent") becomes
false as well.

**Required:** the plan must require Float16 Uneval rendering in both modules:
half-to-double conversion, JS number formatting, explicit `-0`, and
`.subarray` with 2-byte elements. Its expectations must be recorded from the
pinned upstream `uneval`. A guard is also needed so an unhandled kind returns
an error instead of empty elements.

### 2. issue — Uneval behaviour changes with no recorded upstream expression evidence

**Kind:** incomplete requirement.

"Key empty buffers with positive capacity by their backing allocation. Apply
the identity rule to both serializers" (plan lines 22-23) changes `Uneval`
output. Today `refKey` drops empty buffers (`v5/uneval_value.go:299-303`), so
`walk` (`v5/uneval.go:181`) never counts them. Two views over one empty buffer
then render the buffer inline twice. After the change, the buffer is hoisted
into an IIFE parameter, as upstream does (`src/uneval.js:137, 354-357`). That
is a parity fix, but `AGENTS.md` requires parity changes to carry "re-recorded
goldens, upstream test expectations ported into `uneval_test.go` with their
source cited, and targeted cases for any shape the golden corpus does not
generate."

The plan's only binary evidence source cannot supply this. The binary recorder
writes only `stringify` (`v5/testdata/record/record.mjs:46`:
`{ name, devalue: stringify(value, reducers) }`), and the main Go golden corpus
contains no typed arrays (`grep` of `v5/testdata/golden.json` finds none).
Validation (lines 44-52) speaks only of wire expectations. Combined with
finding 1, the plan changes Uneval in two ways, and nothing upstream-recorded
checks either.

**Required:** record `uneval(value)` next to `stringify` for every binary
case, or at least for the empty-shared-buffer and Float16 shapes. Assert those
expressions in both Go modules.

### 3. issue — The Go↔Zig exchange, the user's actual goal, is not enforced in CI

**Kind:** incomplete requirement.

The worklog records the user's correction: "Future codec milestones must
include actual bidirectional exchange across the maintained Go modules and
Zig." The plan adds `test-interop` only to `just test` (line 54). CI never runs
`just test`. `.github/workflows/go.yml` runs `go test ./...` per module without
a Zig toolchain, and `.github/workflows/zig.yml` runs `just test-zig` and
`just lint-zig`. The plan says nothing about CI, so a regression that breaks
Go↔Zig exchange merges with green checks.

The planned design makes this worse. The Go emitting and consuming tests must
be skipped in ordinary `go test` (lines 60-61), so they are environment-gated.
If the recipe miswires the directory or variable, every phase skips and
`test-interop` passes without exchanging anything.

**Required:** add a CI job that runs `just test-interop` with Go and the
mise-pinned Zig. The interop recipe and tests must fail, not skip, when they
run under the recipe and the expected exchanged documents are missing or empty.
For example, assert the document count on each side.

### 4. issue — The planned consumer verification is vacuous; the production Go peer still rejects views

**Kind:** incorrect implementation of a requirement (proof step).

Plan line 63 runs "relevant Go consumer tests with the documented scratch
go.work procedure." Neither consumer imports this repository's modules:

- `/Users/tyler/src/skgo/go.mod:8` requires `github.com/tylergannon/polytype v1.4.0`.
  skgo imports `github.com/tylergannon/polytype/devalue` (e.g.
  `transport.go`), and nothing in it imports `github.com/tylergannon/devalue/v5`.
- polytype generates imports of `github.com/tylergannon/polytype/devalue`
  (`devalue/codegen/generate.go:114`). `AGENTS.md` confirms that both
  migrations are still "Next steps".

A `go.work` that `use`s this checkout and a consumer checkout does not route
any consumer import to the changed code. Those test runs pass whatever this
change does. The plan would therefore record consumer compatibility (Uneval
identity changes, new `BytesPerElement` result) that it never exercised.

The deeper gap is that the Go peer that actually talks to SvelteKit/Zig today
(polytype's runtime copy, used by skgo) keeps rejecting flat views after this
lands. The user's complaint was that "the Go peer rejects its values"
(plan lines 4-6).

**Required:** state plainly that consumer verification does not apply until
migration (or exercise it with a `replace`/migration branch). Name the
polytype copy as a remaining interoperability gap, or carry the change into
the migration plan (`ephemeral/polytype-migration.md`). Do not report consumer
tests as evidence for this change.

### 5. issue — v6 binary expectations would be detached from v6's pin, and the v6 work list goes stale

**Kind:** incomplete requirement / critical antipattern for the next parity bump.

Plan line 52 allows "recording/copying" fixtures into each module's
`testdata/`. Only v5's recorder produces binary expectations
(`v5/testdata/record/binary-values.mjs`, `record.mjs:46-50`, which write into
`zig/`). `v6/testdata/record/` has no binary inputs. A copied v6 fixture is
not regenerated by `just record v6`, and `TestUpstreamVersion`
(`v5/golden_test.go:30-48`) checks only `golden.json` and `package.json`.

AGENTS.md "Next steps" 3 moves v6 to 6.0.2. After that bump, v6 would keep
passing 5.9.4 view bytes under a 6.0.2 claim. 6.0.x does change typed-array
flat parsing: change map row 13 says "Malformed typed-array and boxed payloads
throw `Invalid input` instead of a raw `TypeError` or `Invalid data`."

The plan also turns that change map's assumptions false. Row 6 says "Flat
format has no typed arrays", and the "Corpus gaps" section (line 79) says "no
typed arrays (the flat format does not carry them)". The map is v6's work
list, but "update stale capability descriptions" (plan line 68) does not name
it.

**Required:** each module's own recorder must produce its binary fixture from
its own pin, and its version must be checked alongside `golden.json`. Rows 6
and 13 and the corpus-gaps text of the 5.9.2→6.0.2 map must be updated as v6
work items.

## Non-findings considered

- Wire spelling, slot order and the decoder guard in the plan match upstream.
  The compact form is written when `byteLength !== bufferByteLength`, with
  element count for typed arrays and byte length for DataView. The view slot
  is allocated before its buffer. The raw `values[i][0] === 'ArrayBuffer'`
  check comes before hydration, and the native buffer check after revival.
  (`stringify.js:315-336`, `parse.js:187-196`, `operations.js` `fromViewInfo`.)
- Keying positive-capacity empty slices by pointer is sound in Go. A slice
  with positive capacity always points inside its allocation, and
  zero-capacity reslices are masked to the base pointer and stay unkeyed.
  `NewArrayBuffer` must allocate capacity ≥ 1 to avoid the shared zero-size
  base.
- `test-interop` does not conflict with the "no proof machinery" rule. The
  user explicitly asked for real bidirectional exchange; findings 3 and 4 are
  about it running at all and meaning something, not about its existence.

## Outcome

material findings remain
