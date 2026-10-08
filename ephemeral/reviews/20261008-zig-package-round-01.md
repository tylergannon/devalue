# Adversarial review: installable Zig package, round 01

Date: 2026-10-08 01:46 local. Reviewer: Claude Fable 5.1.

## Target

Branch `codex/zig-installable-package`, commit `cbfdc3c` ("feat: make
repository archive an installable Zig package"), diffed against `b55f530`
(origin/main). Files: `build.zig`, `build.zig.zon`, `zig/build.zig`,
`zig/README.md`, `ephemeral/worklog/20261008-zig-installable-package.md`.

Reviewed against:

- `CLAUDE.md` / `AGENTS.md` working rules (baseline tests, new behavior needs
  tests, worklog protocol, no specialized proof machinery).
- Milestone 1 of `skgo/ephemeral/plans/zig-native-client.md`, Devalue side:
  "Publish a consumer-ready source archive with package-root
  `build.zig`/`build.zig.zon`, the codec, licenses and the required shared
  conformance fixtures. The archive must build and run its native codec tests
  after unpacking, without a sibling repository or checkout-relative corpus.
  Its metadata records the codec revision and devalue pin. ... No guessed
  release URL or placeholder hash satisfies the milestone."
- Caller context: phased delivery, no app migration plans, no specialized
  proof mechanisms, Fable consensus for milestone exit conditions.

Caller constraints were operating constraints only (read-only, artifact path).
No instruction narrowed the subject matter or predicted a verdict, so nothing
was ignored.

## Evidence inspected and checks run

- Read: root `build.zig`, `build.zig.zon`, `zig/build.zig`, `zig/build.zig.zon`,
  `zig/README.md`, `zig/AGENTS.md`, `README.md`, `justfile`, `mise.toml`,
  `.gitignore`, `.github/workflows/{go,zig}.yml`, `zig/tests/{tests,profile,upstream}.zig`
  (fixture and `../v5/package.json` reads), `ephemeral/zig-consumer/*`,
  `ephemeral/zig-build-validation.md`, the session worklog, and the plan.
- `just test` (Go v5, v6, Zig): pass. `just lint-zig`: pass.
- Archive consumption, from scratch:
  1. `git archive HEAD` tarball, unpacked. `zig build test` at the unpacked
     root: 33/33 pass (Debug and `-Doptimize=ReleaseSafe`). `zig build fmt`: pass.
     Steps exposed at root: `test`, `fmt`, `bench`, option `-Dgolden`.
  2. Fresh consumer package: `zig fetch --save=devalue <tarball>` recorded
     `devalue-0.1.0-QJ2gKm4cBACvKohb4m6lg6m9n3nvqrxbmai2Kn7MWNgn`;
     `zig build run` of `ephemeral/zig-consumer/main.zig` against
     `dependency.module("devalue")` produced
     `[{"child":1,"alias":1,"self":0},[2,-2,-1],"Hello <Zig> 😀"]`.
  3. The `.paths`-filtered package stored in the global cache (27 files,
     54 KB: root manifests, `v5/package.json`, `v5/testdata/golden.json`, `zig/`)
     was unpacked separately; `zig build test` there: 33/33 pass. So the
     subset is self-sufficient without a sibling checkout or Node.
  4. Relative path dependency on the repository root from the consumer: builds
     and runs.
  5. `zig fetch .` on a clean export of HEAD gives the same hash as the tarball.
     `zig fetch .` on this checkout (which has `zig/.zig-cache`, 34 MB) gives
     `devalue-0.1.0-QJ2gKk09DQJ_-yUVSJCoSaLlfV9nsChBEhfifcXyGfM1`; adding one
     junk file under `zig/.zig-cache/` changes it again.
  6. `git ls-remote origin`: `main` is `b55f530`; `cbfdc3c` is not on the remote.
  7. Zig 0.17.0 accepts an extra top-level field in `build.zig.zon` (checked with
     a scratch manifest), so recording metadata there is possible if wanted.

## Findings

### 1. Issue (verifiable bug): package hash is not hermetic for local fetches

`build.zig.zon:6` lists `"zig"` as a whole-directory path. Zig's package
hashing includes every file under a listed path, including untracked build
output that git ignores: `zig/.zig-cache/` and `zig/zig-out/`. Reproduction in
"Evidence" item 5: the checkout hashes to `…QJ2gKk09…` while the archive hashes
to `…QJ2gKm4c…`, and the hash moves with any cache file. A developer who runs
`zig fetch --save` against a local directory (a documented Zig workflow and the
likely first thing SKGo tries before a URL exists) records a hash that will
never match the GitHub archive, which is exactly the "guessed hash" the plan
forbids. It also bloats a directory fetch by the cache size. GitHub archives
and `path` dependencies are unaffected, which is why the happy path passed.
Fix: enumerate the tracked entries instead of `"zig"` (`zig/build.zig`,
`zig/build.zig.zon`, `zig/src`, `zig/tests`, `zig/testdata`, `zig/bench.zig`,
`zig/README.md`, `zig/LICENSE`, `zig/LICENSE-devalue`, `zig/AGENTS.md`).

### 2. Issue (incomplete requirement): the root package has no repository check

CLAUDE.md: "New behavior needs tests." The new behavior is the root
`build.zig`/`build.zig.zon` and its `.paths` subset. `justfile:19-24` and
`.github/workflows/zig.yml` still `cd zig` for both `test-zig` and `lint-zig`,
so nothing in `just test`, `just lint` or CI ever evaluates root `build.zig`,
`addPackage(b, "zig")`, or whether `.paths` still carries `v5/package.json`
and `v5/testdata/golden.json`. Dropping either path, or breaking the
`source_dir` joins, passes every repository check and only fails in a consumer.
The worklog also records no archive consumption check; the one above was done
during this review. The plan's exit condition is that the archive "must build
and run its native codec tests after unpacking", which the repository should
be able to demonstrate itself. A plain `zig build test` from the root in
`test-zig` (and CI) is an ordinary check, not a specialized proof mechanism; a
`zig fetch` of a `git archive` tarball plus `zig build test` in the result is
the stronger, still-ordinary form.

### 3. Issue (incomplete requirement, sequencing): nothing is published yet

Milestone 1 requires an actual published URL and hash, and says a placeholder
does not satisfy it. `cbfdc3c` is not on `origin` (Evidence item 6), and
`zig/README.md:15` documents `archive/<commit>.tar.gz` with a placeholder.
This is expected before merge and is a phase boundary rather than a code
defect, but the milestone cannot be closed on this branch alone: the exit
condition is only met once the commit is on GitHub and SKGo's `build.zig.zon`
pins that URL with the hash Zig computes from it (which, by Evidence item 5,
will be `devalue-0.1.0-QJ2gKm4cBACvKohb4m6lg6m9n3nvqrxbmai2Kn7MWNgn` if the
merged tree's packaged files are byte-identical to `cbfdc3c`; a squash merge or
any change to `zig/`, `v5/package.json`, `v5/testdata/golden.json` or the root
manifests changes it).

### 4. Nitpick: how "metadata records the codec revision and devalue pin" is met is undocumented

`build.zig.zon:3` carries `.version = "0.1.0"`, which names neither the codec
revision nor devalue 5.9.4. In practice the devalue pin is carried by the
included `v5/package.json` and `root.zig:2 upstream_version`, both asserted by
`tests/profile.zig:98-104`, and the codec revision is the commit in the archive
URL. That is a defensible reading of the plan, but neither the README nor the
worklog says so, and `0.1.0` is an unexplained number consumers will see in
every hash. Either state the mapping in `zig/README.md` or give the version a
meaning (Zig accepts extra manifest fields, Evidence item 7, if a `.devalue`
note is preferred).

### 5. Nitpick: root `README.md` still describes `zig/` as "a separate ... package"

`README.md` "Zig package" section was not updated; it points at `zig/README.md`
but does not say the repository root is the installable package or show the
`zig fetch` line. A consumer reading the root README (the GitHub landing page)
would still try a path dependency on `zig/`.

## Outcome

material findings remain
