# devalue goldens

`golden.json` records what the pinned JavaScript `devalue` produces from both
`stringify` and `uneval` for each generated value, together with the devalue
version that produced it. `go test` reads it and never runs Node.

## The pin

This module is feature-equivalent to exactly one devalue release, named in
three places that `TestUpstreamVersion` requires to agree:

- `UpstreamVersion` in `version.go`, the promise the Go API publishes;
- `devDependencies.devalue` in this module's `package.json`, an exact version
  and the one the recorder installs;
- the `devalue` field of `golden.json`, written by the recorder from the
  installed package.

`record.mjs` refuses to run against any other installed version.

## Regenerate

From this module's directory, with its packages installed (`pnpm install`):

```sh
go run ./testdata/record && node testdata/record/record.mjs
```

Without edits to `main.go` or the pin, this reproduces `golden.json` byte for
byte.

## Moving to a newer devalue

A newer release within this module's upstream major is a minor release of
this module. A new upstream major gets its own module directory; see the
repository's `AGENTS.md`.

1. Pick the target from what consumers run, not from upstream's latest.
   SvelteKit renders with the devalue its own dependency range resolves, and a
   Go server mirroring SvelteKit needs output byte-equal to that.
2. Read every upstream change between the current pin and the target release:
   the GitHub release notes, the published source diff, and the
   `test/index.test.js` expectations. Record the map under `ephemeral/`.
3. Bump the `package.json` pin (`pnpm add -D devalue@<version> --save-exact`)
   and `UpstreamVersion`.
4. Re-record `golden.json`. Recorded cases that change show which outputs
   moved. The corpus does not cover every changed behavior, so extend
   `main.go` with any value shapes the release changed that it does not yet
   generate.
5. Port the changes, re-port the `uneval_test.go` expectations from the new
   release's tests, and update the version named in the README.
6. Before releasing, run each downstream consumer's tests (polytype's
   `devalue/codegen`, skgo) against the change through a `go.work` that uses
   both checkouts.
