# Worklog: carve the devalue runtime out of polytype

decision (owner): the runtime becomes its own repository, because it imports
nothing from polytype (stdlib only; goja in tests). Only polytype's
`devalue/codegen` depends on polytype internals, so codegen stays there. An
in-repo nested module was considered and rejected: the runtime has its own
upstream, dependents, pin and release notes.

decision: one module per upstream major, in `vN/` directories on `main`
(`github.com/tylergannon/devalue/v5`, `/v6`), with plain tags (`v5.0.0`). The
Go major equals devalue's major; a minor moves parity within it; a patch is our
own fix. Go rejects build metadata in module versions, so the exact upstream
release lives in `UpstreamVersion` and on the first line of the release notes.

decision: `v6/` starts as a copy of `v5/`, still at 5.9.4 parity, and stays
untagged until it reaches a devalue 6 release, so no false promise is
published.

decision: each module owns its pin (`vN/package.json`, pnpm lockfile), since
v5 and v6 pin different upstream majors. `TestUpstreamVersion` reads the
module's own `package.json`.

decision (owner): polytype drops its runtime copy without a `/v2` and without
an alias shim; the owner is the only consumer. Plan:
`ephemeral/polytype-migration.md`.

decision: pin goja to polytype's version (`fabc3b8078ad`), not the newer one
`go mod tidy` picked, so the runtime's test behavior did not change in the move.

proof: history carved with `git filter-repo` from GitHub `main` at `e521921`
(runtime files and devalue notes only; `devalue/codegen` excluded; `devalue/`
renamed to `v5/`): 4 commits. With devalue 5.9.4 installed by pnpm, the
recorder reproduced `v5/testdata/golden.json` byte for byte (359 cases).
`just test` passes for v5 and v6.

friction: a local `git clone` of `/Users/tyler/src/polytype` carried its stale
local `main`, not the released `e521921`. -> carve from the GitHub remote.

license: our code is 0BSD (as polytype); devalue's MIT notice ships as
`LICENSE-devalue` because the port reproduces its behavior, messages and test
expectations. Separate files keep pkg.go.dev's license detection working.
