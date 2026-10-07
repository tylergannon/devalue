---
name: zig-development
description: Write and test the Zig devalue package using its pinned compiler, version-matched standard library, and explicit memory ownership. Use for Zig code, build files, allocator tests, or benchmarks in this repository.
---

# Zig development

Use the version in the repository's `mise.toml` (currently 0.17.0). Run
`mise install` on a new machine, then `mise exec -- zig version`. An unqualified
`zig` may still resolve to an older Homebrew installation.

## Resolve APIs against the compiler

Run `mise exec -- zig env` to locate `std_dir` and `lib_dir`. Search the relevant
installed source and its tests with `rg`; compile a small probe when a signature
or behavior is uncertain. This is especially useful for `std.ArrayList`, JSON,
allocators, `std.Io`, and build APIs, which differ from older examples.

Read the relevant section of the versioned
[language reference](https://ziglang.org/documentation/0.17.0/),
[standard-library docs](https://ziglang.org/documentation/0.17.0/std/), or
[release notes](https://ziglang.org/download/0.17.0/release-notes.html).
Load sections as needed. Master docs and unversioned guides can describe a
different compiler; the installed compiler and source resolve disagreements.

## Memory and serialization

- Allocating library APIs take `std.mem.Allocator`. Document who owns returned
  memory, how it is released, and whether it borrows input. Use `errdefer` to
  clean up partial results on failure.
- `std.ArrayList(T)` uses explicit allocators:
  `var list: std.ArrayList(T) = .empty;`, `try list.append(gpa, item)`, and
  `list.deinit(gpa)`. Growth can invalidate pointers into `items`; reference
  identity must survive any backing-storage relocation.
- Ordinary JSON parsing does not implement devalue's graph or special values.
  Check upstream bytes, decoded contents, and reference identity independently.
  Follow `zig/AGENTS.md` for the fixture and consumer boundaries.
- In-memory codec work needs no filesystem or network I/O. For actual I/O,
  inspect the pinned `std.Io` interfaces instead of copying old reader/writer
  examples.

## Verification

Use native Zig tests with `std.testing.allocator` for leak detection and
`std.testing.checkAllAllocationFailures` where operations allocate. Include
borrowed-input lifetime and shared-reference cases when those behaviors exist.
Run the package's build/test steps once they are defined; use `zig test` for a
standalone probe. Check changed Zig files with `mise exec -- zig fmt --check`.
Keep temporary probes and research under `ephemeral/`.

Measure performance with representative devalue workloads in a stated
optimization mode, recording compiler, target, time, and allocation behavior.
Correctness tests run with safety checks enabled. Report measured results;
language choice alone establishes no speed claim.
