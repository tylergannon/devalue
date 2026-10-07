# Zig development setup research — 2026-10-07

Two independent Luna research agents examined official documentation and
public coding-agent skills. Scope: toolchain and agent preparation, before
codec implementation.

## Toolchain

The [official index](https://ziglang.org/download/index.json) lists stable
0.17.0 dated 2026-10-01 and master 0.18.0-dev.35+5e754304d dated 2026-10-05.
The local Homebrew compiler was 0.16.0-dev.2915+065c6e794. Installed 0.17.0
through the existing mise manager and pinned it in the repository. Subsequently
upgraded Homebrew's default Zig to core stable 0.17.0 as well. Use
`mise exec -- zig` for the reproducible project toolchain.

Primary references:

- [0.17 language reference](https://ziglang.org/documentation/0.17.0/)
- [0.17 standard library](https://ziglang.org/documentation/0.17.0/std/)
- [0.17 release notes](https://ziglang.org/download/0.17.0/release-notes.html)
- [0.16 release notes](https://ziglang.org/download/0.16.0/release-notes.html)
  for the I/O migration
- [0.15.1 release notes](https://ziglang.org/download/0.15.1/release-notes.html)
  for unmanaged ArrayList migration

The installed standard-library source confirms `std.ArrayList(T)`, `.empty`,
allocator-taking append/deinit, `std.json.parseFromSlice`,
`std.testing.allocator`, and `std.testing.checkAllAllocationFailures`.
Compiler probes are retained beside this note. None demonstrate codec parity
or serializer performance.

Validation: `mise exec -- zig version` returned `0.17.0`; both native smoke
tests and `zig fmt --check` passed. The local skill validator, repository
`just test`, and `just lint` also passed. Plain `zig version` initially returned
the old Homebrew version; after the Homebrew upgrade it returns 0.17.0.

## Agent guidance candidates

| Source | Version/scope | Assessment at this date |
| --- | --- | --- |
| [shreeve/zig-agent-docs](https://github.com/shreeve/zig-agent-docs), [ZIG-0.17.md](https://github.com/shreeve/zig-agent-docs/blob/main/ZIG-0.17.md) | Agent reference for stable 0.17; author reports compiler probes | Best current version-specific reference found. Large, newly published, and no explicit license found by the researcher. Link to relevant sections and verify examples locally; no wholesale copying. |
| [vercel-labs/fx/AGENTS.md](https://github.com/vercel-labs/fx/blob/main/AGENTS.md) | Real project instructions; Zig 0.16.0+ | Useful allocator/ownership conventions, but project-specific rules and APIs do not transfer automatically. |
| [zigcc/skills](https://github.com/zigcc/skills/tree/9de4482769b57e6dfabfee12038d1dd9e61afd10/zig-0.17) | Standalone skill for stable 0.17 | Initial researcher incorrectly reported only 0.15/0.16. Direct checkout found 0.17 at the cited commit. Adopted locally with corrections and compiler verification. |
| [rudedogg/zig-skills](https://github.com/rudedogg/zig-skills) | Standalone skill for 0.15.2 | Version mismatch. |
| [nzrsky/zig-skills](https://github.com/nzrsky/zig-skills) | 0.17 development snapshots | Researcher found stale allocator guidance and an unreleased-version assumption; not adopted for stable 0.17. |

The initial report missed zigcc's existing 0.17 skill. After the user asked
why existing skills were not updated, a direct source checkout found and
examined it. The local `.agents/skills/zigcc/zig-0-17/` now adapts that upstream
skill at commit `9de4482769b57e6dfabfee12038d1dd9e61afd10`; its MIT declaration
is retained. The original local `zig-development` skill supplies repository
context and routes language/API guidance to the imported skill. No skill was
installed globally.

Local changes: a short entrypoint routes to the detailed migration reference;
the version script requires exact stable 0.17.0; SafeAllocator thread-safety
and non-reuse claims are qualified by backing-allocator requirements;
deprecated API aliases are distinguished from removals. Native validation
probes cover enum conversion, reflection/type construction, bit casts,
allocator cleanup, formatting, collection APIs, bit sets, build steps,
formatting steps, and `std.process.Init` argument/I/O handling. External C
translation and platform library linkage remain untested.

Validation of the imported skill: seven native API tests and the build,
formatting, and entrypoint/argument probes passed. The version checker accepts
0.17.0 and rejects 0.16.0, 0.17.0-dev.1158, 0.17.1, 0.18.0-dev.35, and 1.0.0.
Both local skill frontmatters validate; repository Go tests and lint pass.

## Starting scope

Prepare `zig/` in this repository, preserving Go module paths. Reuse the v5
upstream corpus at its current location initially. Native Zig tests will need
independent content/identity checks and allocator/lifetime coverage. Public
API, build layout, fixture relocation, and benchmarks await implementation.
