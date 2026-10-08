# Plan: move polytype and skgo onto github.com/tylergannon/devalue/v5

Written 2026-09-25, when this repository was carved out of polytype at `e521921`
(v1.2.0). Until this plan is done, polytype ships its own copy of the runtime at
`github.com/tylergannon/polytype/devalue`. As of 2026-10-08 that copy predates
the flat typed-array/DataView support in both modules here. Consumers must
complete this migration to exchange binary views with Zig; a go.work alone
does not redirect the legacy import path.

## Decisions already made

- **The runtime leaves polytype outright, with no alias shim.** The owner is
  the only consumer and accepted a breaking change inside polytype v1 (a
  minor release, not `/v2`).
- **`devalue/codegen` stays in polytype**, at the same import path. It
  generates code from polytype's type grammar and imports
  `polytype/internal/builder`, so it is a polytype backend. Only the runtime
  import in its generated code changes.
- **Each project needs a devalue major that matches the devalue its SvelteKit
  resolves.** Today that is `/v5` everywhere.

## Step 0: release v5.0.0 here

Tag `v5.0.0` with release notes starting `Parity: devalue 5.9.4`, and warm the
Go proxy. polytype cannot require an untagged module (a `replace` would break
`go install github.com/tylergannon/polytype/polytype@version`).

## Step 1: polytype (one PR, released as a minor)

- `go get github.com/tylergannon/devalue/v5@v5.0.0`.
- Set `devaluePackagePath` in `devalue/codegen/generate.go` to
  `github.com/tylergannon/devalue/v5`, then regenerate the codegen fixtures
  and goldens that embed it: `codegen/testdata/recursive/generated/codec/`,
  `devalue/codegen/testdata/fixture/`, and the `generate_test.go` and
  `cache_inputs_test.go` expectations.
- Track the new runtime prefix in `devalue/codegen/generate_test.go` with
  a second TrackFixtureDependencies call, and update the runtime-prefix
  assertion in `cache_inputs_test.go`; the old polytype-only tracker otherwise
  misses this dependency.
- Point the fixture tests that import the runtime (`codec_test.go` beside each
  generated fixture) at the new module. `codegen/codegen.go` and
  `typescript/library_test.go` import `devalue/codegen`, which keeps its path.
- Delete the runtime: every file directly in `devalue/` (not
  `devalue/codegen/`), plus `devalue/testdata/`.
- Keep the root JavaScript devalue pin: `TestRecursiveDevalueJSInterop` uses it
  to verify generated codecs against upstream, independently of the removed
  recorder. Drop `github.com/dop251/goja` from `go.mod` (only the runtime's
  tests used it; `go mod tidy` confirms).
- Delete the notes that moved here: `ephemeral/devalue-parity/`,
  `ephemeral/issue-154-uneval-migration-plan.md`,
  `ephemeral/reviews/202609181648-issue-154-*`,
  `ephemeral/reviews/202609181726-issue-154-*`,
  `ephemeral/worklog/202609181648-issue-154-plan-review.md`,
  `ephemeral/worklog/202609251013-devalue-version-pin.md` and
  `ephemeral/worklog/202609251028-devalue-5.9.4-parity.md`.
  `ephemeral/devalue-projection/` stays: it is codegen's design history.
- Docs: in the README devalue section, `AGENTS.md` (package layout and test
  structure), `skills/polytype/references/devalue-and-grammar.md`,
  and `website/src/content/docs/guides/devalue.md`, describe the
  runtime as this module and keep codegen's docs. Remove `../devalue` from the
  website's gomarkdoc `prebuild` list.
- Proof: `go test ./...`, `just lint` and `just build-tagged` pass, and
  generated fixture code compiles against `…/devalue/v5`.

## Step 2: skgo

- Replace `github.com/tylergannon/polytype/devalue` with
  `github.com/tylergannon/devalue/v5` everywhere: 18 non-test files, including
  the two generated `*_devalue_gen.go` files (regenerate those with the new
  polytype rather than editing them), plus tests.
- Bump polytype to the Step 1 release.
- Fix the stale comment in `devalue_wire_test.go`: kit's range now resolves
  devalue 5.9.4, not 5.9.2.
- Proof: skgo's root `go test ./...` and the `example` module's tests. The
  example's full-stack tests need a fresh frontend build first; they failed on
  both sides of the 5.9.4 port because the committed build was stale (adapter
  `16cb67886deb` vs `17f12e0497d6`).

## Later: v6

skgo moves to `/v6` in the same change that mirrors SvelteKit's
devalue-6 `get_replacer`, and only once SvelteKit depends on `devalue ^6`.
polytype's codegen targets the flat format, which devalue 6 writes byte for
byte like 5. When v6 ships, give codegen a choice of runtime major, or move
its default and say so in the release.
