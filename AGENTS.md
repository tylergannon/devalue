# devalue (Go)

A Go port of [devalue](https://github.com/sveltejs/devalue), the structured-value
serializer SvelteKit uses for `load` data, remote functions and SSR hydration.
It writes and reads devalue's flat JSON-array format (`Stringify`/`Parse`) and
emits its JavaScript expressions (`Uneval`/`UnevalWith`). Both serializers
share one Go value model.

## The promise this repository makes

**Each release is feature-equivalent to exactly one devalue release.** For
every value the Go model can express, `Stringify` and `Uneval` write the bytes
that devalue release writes, and `Parse` reads its documents back. Each
module names its release in `UpstreamVersion` (`vN/version.go`), and
`TestUpstreamVersion` holds that constant, the module's `package.json` pin, and
the version recorded in `testdata/golden.json` to the same exact version.

**The Go major version is devalue's major version.** Each upstream major gets
its own module, in its own directory:

| Directory | Module path | Tracks | State |
|-----------|-------------|--------|-------|
| `v5/` | `github.com/tylergannon/devalue/v5` | devalue 5.x | At parity with **5.9.4**. Not yet tagged; see "Next steps" |
| `v6/` | `github.com/tylergannon/devalue/v6` | devalue 6.x | A copy of v5 (still 5.9.4). Not tagged until it reaches parity with a devalue 6 release |

Version numbers within a module:

- **Major:** the upstream major. It never moves inside a directory. A new
  upstream major means a new `vN/` directory, started as a copy of the
  previous one.
- **Minor:** moving parity to a newer upstream release within that major
  (5.9.2 → 5.9.4 is a minor), or adding API.
- **Patch:** our own fixes at unchanged parity.
- **Never break a module's exported API within its major.** When upstream
  changes an API inside a major, add the new form alongside the old one. A
  new upstream major is the only place for breaking changes, and it is the
  place to take all of them.

Tags are plain semver with no directory prefix (`v5.0.0`, `v6.0.0`): Go
resolves `…/devalue/v5` at `v5.x.y` from the `v5/` directory. Go rejects
build metadata in module versions (such as `v5.1.0+devalue.5.9.4`), so the
upstream release is named by `UpstreamVersion` and on the first line of the
GitHub release notes: `Parity: devalue 5.9.4`.

Maintain every major that a consumer still uses. SvelteKit decides which one
that is: a Go server mirroring SvelteKit needs output byte-equal to the devalue
its SvelteKit resolves. As of 2026-09-25, SvelteKit 2.70.3 depends on
`devalue ^5.8.1` and 3.0.0-next.29 on `^5.9.4`, so v5 is the major in use.

## Consumers

- **polytype** (`/Users/tyler/src/polytype`, `github.com/tylergannon/polytype`):
  its `devalue/codegen` generates typed `Encode`/`Decode`/`Stringify`/`Parse`
  functions for Go types. The generated code imports this runtime; the
  import path is `devaluePackagePath` in `devalue/codegen/generate.go`. Until
  polytype migrates (see `ephemeral/polytype-migration.md`), polytype still
  ships its own copy of the runtime at `github.com/tylergannon/polytype/devalue`.
- **skgo** (`/Users/tyler/src/skgo`): a Go SvelteKit server. It uses the flat
  format for remote functions and form data, and `UnevalWith` with a
  `Replacer` for SSR hydration, streamed promises and transport hooks. Its
  replacers mirror SvelteKit's `get_replacer`, and its contract is
  byte-for-byte parity with SvelteKit's own output.

Before releasing, run each consumer's tests against the change through a
scratch `go.work` that `use`s both checkouts. Build test binaries under that
`GOWORK` (`go test -c`) and run them without it: some skgo tests run `go build`
in temporary projects and fail spuriously when they inherit `GOWORK`.
`go test ./...` from skgo's root does not reach its `example` module, so run
that separately.

## Commands

Each `vN/` is its own module. Run Go commands inside it, or use `just`, which
loops over every module.

```sh
just test          # go test ./... in every module
just lint          # go mod tidy, vet, staticcheck, govulncheck, golangci-lint, goimports
just record v5     # regenerate v5/testdata/golden.json from the pinned devalue
```

JavaScript tooling uses **pnpm**, never npm. `pnpm install` inside a module
installs its devalue pin, which only the recorder needs. `go test` never runs
Node.

## Working rules

- Run `just test` before changing anything, to establish a baseline. If tests
  cannot run at all, stop. If tests are broken, fix them first. Work is not
  done until `just test` and `just lint` pass.
- New behavior needs tests. Parity changes need upstream evidence:
  re-recorded goldens, upstream test expectations ported into `uneval_test.go`
  with their source cited, and targeted cases for any shape the golden corpus
  does not generate.
- Goldens come from the pinned JavaScript devalue, never from asking Go what it
  produces. `testdata/record/README.md` describes recording and the parity-bump
  procedure.
- A fix that applies to more than one maintained major goes into each module.
- Tests are plain `go test`: no test code in JavaScript or TypeScript, no Node
  inside `go test`, and no machine-generated ledgers, claims files or
  provenance trackers. The recorder (`testdata/record/*.mjs`) is test-data
  tooling, not a test.
- Check tarballs downloaded from npm against the registry's shasum. The npm
  tarball has no `test/` directory; upstream tests come from the GitHub tag.

## Session worklog protocol

All agents doing non-trivial repository work MUST follow the Session Worklog
protocol in `/Users/tyler/.agents/skills/session-worklog/SKILL.md`.

- Keep the tracked session worklog under `ephemeral/worklog/`.
- Keep review prompts, review results, research notes, change maps and every
  other temporary or raw session artifact under `ephemeral/`.
- NEVER put ephemeral or raw session artifacts in `docs/`, which is only for
  polished, durable documentation.

## History and notes

This repository was carved out of polytype at `e521921` (polytype v1.2.0),
keeping the runtime's history. `ephemeral/` carries the notes that came with
it:

- `ephemeral/devalue-parity/5.9.2-to-6.0.2.md`: every upstream change from
  5.9.2 through 6.0.2, with evidence and what the Go port does about each
  (5.9.3/5.9.4 are done; the 6.0.x items are v6's work list).
- `ephemeral/worklog/202609251028-devalue-5.9.4-parity.md`: how 5.9.4 parity was
  ported and proven, including the boxed-BigInt injection it closed.
- `ephemeral/issue-154-uneval-migration-plan.md`, with its reviews and worklog:
  how `Uneval` came over from skgo.

## Next steps

1. Create the GitHub releases: tag `v5.0.0` (`Parity: devalue 5.9.4`), then
   warm the proxy with `GOPROXY=https://proxy.golang.org go list -m github.com/tylergannon/devalue/v5@v5.0.0`.
2. Migrate polytype and skgo onto `…/devalue/v5`, following
   `ephemeral/polytype-migration.md`.
3. Port v6 to devalue 6.0.2 using the change map. v6 is its own import path,
   so it takes upstream's breaking changes directly (the `js`-tagged-template
   replacer, the new hoisting shape) instead of adding them alongside.
