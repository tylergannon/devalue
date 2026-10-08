# Adversarial review: Zig typed arrays and DataView implementation, round 02

**Target:** branch `codex/zig-binary-views` at `8c3206d` ("test: exercise
upstream revived array-like buffers accurately"). That commit sits on top of
the implementation `4751ffb`, which round 01 reviewed. The review checks the
whole branch against the ratified plan `ephemeral/zig-binary-views-plan.md`
(`0f9fdbe`), `CLAUDE.md`/`AGENTS.md`, `zig/AGENTS.md`, `zig/README.md`, and
pinned upstream devalue 5.9.4 (`v5/node_modules/devalue` plus the GitHub-tag
tests in `ephemeral/upstream-5.9.4/`). The working tree matches `8c3206d`,
except for the untracked `ephemeral/reviewer-logs/zig-binary-build-round-02/`,
which is this session's own log directory.

**Outcome: no findings**

## Scope

The launch prompt names the target, the sources, the output path and a
read-only boundary. It does not narrow the subject matter, predict findings or
ask for a verdict, so no caller narrowing was ignored. The scope is the same as
round 01: the full plan acceptance list, the repository working rules, and
byte and acceptance parity with pinned devalue 5.9.4.

## Evidence inspected

- **`8c3206d`, in full:** `zig/tests/binary.zig`; the move of
  `binary-file-input.txt` from `zig/testdata/` to `zig/tests/`;
  `v5/testdata/record/{record.mjs,README.md}`;
  `ephemeral/codec-comparison/binary/main.go`;
  `ephemeral/zig-binary-validation.md`; `ephemeral/zig-upstream-test-coverage.md`;
  and the worklog.
- **Codec unchanged since round 01:** `git diff 4751ffb HEAD -- zig/src
  zig/README.md` is empty. Round 01's checks of the codec therefore still apply:
  decode branch `zig/src/decode.zig:212-231`, `Graph` view constructors, the
  encoder and `bound()`. The decode view branch, `d.equal` (`root.zig:333`, where
  refs compare by handle) and `build.zig.zon` `.paths` were re-read for this
  round. `.paths` includes `tests`, so the embedded input ships with the
  package.
- **Stale references:** a repository-wide grep found none of the old
  `zig/testdata/binary-file-input.txt` path and no "all 109 rejected" claim
  outside the append-only worklog. Worklog line 10 keeps its original wording,
  and line 11 records the correction.

### Commands run (repository untouched; `git status` shows only the reviewer log)

| Check | Result |
|---|---|
| `mise exec -- zig build test --summary all` (Zig 0.17.0) | 33/33 pass |
| `... -Doptimize=ReleaseSafe` | 33/33 pass |
| `zig build fmt` | clean |
| `just test` | Zig, Go v5 and Go v6 pass |
| `just lint` in a scratch copy of `HEAD` (it rewrites files) | exit 0; tree unchanged; 0 issues; no vulnerabilities |
| Re-record from scratch with `node testdata/record/record.mjs` (devalue 5.9.4, writing the new `zig/tests/` path) | `zig/testdata/`, `v5/testdata/` and `zig/tests/binary-file-input.txt` byte-identical; 109 binary cases |
| `go run ./binary` in `ephemeral/codec-comparison` | "108 standalone JS-recorded buffers agree; 108 flat-view documents rejected (views unsupported); one custom View document rejected without a reviver" |
| Mutant A, run in scratch: a revived non-`ArrayBuffer` becomes an empty view instead of `InvalidDocument` (`decode.zig:224`) | killed by `binary.test.every view validates revived …` (`expected error.InvalidDocument`) |
| Mutant B, run in scratch: decoded views ignore the wire `byteOffset` | killed by the revival test and three other binary tests |

The scratch copy for the mutants contains only `zig/`. Three tests that read
pins and corpora from outside `zig/` (`tests`, `profile` and `robustness`) fail
there on the baseline too, so they were not used as kill evidence.

## Round-01 findings re-checked

1. **Issue, fixed:** the array-like revival payload was vacuous.
   `binary.zig:283` now uses upstream's two-slot `{"length":3},1024`. Line 288
   asserts that every tag, bounds variant and payload makes exactly one reviver
   call before rejection, so the test can no longer pass before the post-revival
   check runs. Mutant A shows that the check is load-bearing.
2. **Nitpick, fixed:** the genuine-revival assertions were weaker than
   upstream. `Revival` records the handle it returns. Lines 299-300 assert buffer
   identity by handle (`d.equal` on `.ref`) and `byte_offset` (0, or 8 when
   bounds are given). This matches upstream's `result.buffer === buffer` and
   `byteOffset === bounds[0] ?? 0`. Mutant B is killed.
3. **Nitpick, fixed:** the Go harness overstated its count. The message and both
   notes now say 108 flat-view documents and one custom `View` document rejected
   without a reviver.
4. **Nitpick, fixed:** the test read a file at run time. `binary.zig:66` now
   uses `@embedFile`, so the native test does no file I/O. The JS recording
   remains as evidence that the bytes match. The recorder and its README write
   and document the new location.

## Findings

None. The fix commit adds no new behaviour, complexity or unrequested
infrastructure. The codec is unchanged and still matches pinned 5.9.4 on every
point round 01 verified:

- bounds are emitted iff `byteLength !== bufferByteLength`;
- the raw-slot `ArrayBuffer` guard runs before hydration and callbacks;
- view-tag revivers take precedence;
- a genuine buffer is required after revival;
- cycles are rejected;
- no storage is allocated from claimed lengths;
- `bound()` cannot trap.

Every plan acceptance item remains present, and its proof is now accurate. The
documented strict-decode exceptions (string, null or fractional bounds, and
extra fields) are unchanged and match the plan.
