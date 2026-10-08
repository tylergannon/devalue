# Adversarial review: installable Zig package, round 02

Date: 2026-10-08 local. Reviewer: Claude Fable 5.1. Round 01:
`ephemeral/reviews/20261008-zig-package-round-01.md`.

## Target

Branch `codex/zig-installable-package` at `16bc1b5` (pushed to origin),
commits `cbfdc3c`, `6348149`, `16bc1b5`, diffed against `b55f530`
(origin/main). Files: `build.zig`, `build.zig.zon`, `zig/build.zig`,
`zig/README.md`, `README.md`, `justfile`,
`ephemeral/worklog/20261008-zig-installable-package.md`.

Authoritative sources, unchanged from round 01: `CLAUDE.md`/`AGENTS.md`
working rules; milestone 1 of `skgo/ephemeral/plans/zig-native-client.md`
(Devalue side: consumer-ready source archive with package-root manifests,
codec, licenses and shared fixtures; tests run after unpacking without a
sibling checkout or Node; metadata records codec revision and devalue pin; no
placeholder URL or guessed hash); caller context (phased delivery, no
specialized proof mechanisms, Fable consensus for exit conditions). The caller
prompt contained operating constraints only; nothing was ignored.

## Evidence inspected and checks run

- Read the full diff since `b55f530` and the round 01 findings, plus root and
  nested `build.zig`/`build.zig.zon`, `justfile`, `.github/workflows/zig.yml`,
  `zig/tests/binary.zig:66` (`@embedFile("binary-file-input.txt")`, so the
  tests directory must ship, which it does).
- `just test` (Go v5, v6, Zig at root): pass. `just lint-zig` (root): pass.
- Real published archive:
  `zig fetch --save=devalue https://github.com/tylergannon/devalue/archive/16bc1b502e07a6535b5cde10dda0ff1933bf3ee0.tar.gz`
  from a fresh scratch consumer recorded
  `devalue-0.1.0-QJ2gKoMeBAC-jGq_M30rVJvF7jT-GzcB0MwMxEWxoIVk`; `zig build run`
  of `ephemeral/zig-consumer/main.zig` against `dependency.module("devalue")`
  printed `[{"child":1,"alias":1,"self":0},[2,-2,-1],"Hello <Zig> 😀"]`.
- Round 01 finding 1 (hash hermeticity): `zig fetch .` on this checkout, with
  both `.zig-cache` and `zig/.zig-cache` present, now yields the same hash as
  the GitHub archive. Fixed.
- The `.paths`-filtered package Zig stored (26 files, identical list to round
  01) unpacked on its own: `zig build test` 33/33 pass, `zig build fmt` pass.
  No sibling checkout, no Node.
- Round 01 finding 2 (no repository check): `just test-zig` and `just lint-zig`
  now run from the root manifest, and `zig.yml` invokes those recipes. In a
  scratch export, a misformatted root `build.zig` and a misformatted
  `zig/src/wire.zig` each make `zig build fmt` fail at root, so the fmt chain
  through `addPackage` plus the root `addFmt` is live.
- Path dependency on `zig/` (`ephemeral/zig-consumer`) and `zig build test`
  inside `zig/` still work.
- Round 01 findings 3 to 5: branch is on origin so an immutable archive URL
  exists and was consumed above; `zig/README.md` now states how revision and
  pin are recorded; root `README.md` now names the root as the package.

## Findings

No material findings remain. Nitpicks:

### 1. Nitpick: the nested `zig/build.zig` entry point is no longer exercised by any recipe

`justfile:22-26` moved both recipes to the root, and CI calls those recipes.
`zig/build.zig:3-5` (`addPackage(b, ".")`) is still a documented entry point
(`zig/README.md:21`, "path dependency on the root or `zig/` directory") and
the README's bench instruction still runs there, but nothing automated builds
it now. It passed manually in this review. If the nested entry is to remain
supported, one more recipe line (`cd zig && zig build test`) keeps it honest;
if not, drop the `zig/` path-dependency sentence.

### 2. Nitpick: root `build.zig:5` reaches into `b.top_level_steps` to extend `fmt`

Looking up the step by name after `addPackage` created it works, but it
couples the root file to the step name and panics with `.?` if the name
changes. Letting `addPackage` take the extra fmt paths, or return the fmt
step, is the plain form.

### 3. Nitpick: milestone closure still depends on the SKGo side

The Devalue half of milestone 1 is met: the archive at `16bc1b5` is fetchable
and hashes to `devalue-0.1.0-QJ2gKoMeBAC-jGq_M30rVJvF7jT-GzcB0MwMxEWxoIVk`.
The plan's exit condition also requires that URL and hash pinned in SKGo's
`build.zig.zon`, which this repository cannot show. Note the hash is
content-based: a squash merge yields a different URL but the same hash as long
as the packaged files are byte-identical, and `zig/README.md:15` keeps a
generic `<commit>` placeholder, which is fine for a README but SKGo must pin
the concrete commit.

## Outcome

only nitpicks remain
