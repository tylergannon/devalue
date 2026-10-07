---
name: zig-0-17
description: Use current Zig 0.17.0 language, allocator, reflection, I/O, and build APIs when writing Zig or migrating older code. Read the relevant migration reference when older examples or compiler diagnostics conflict with the stable toolchain.
license: MIT
metadata:
  version: "0.17.0"
  language: zig
---

# Zig 0.17 development

Adapted from [zigcc/skills, zig-0.17](https://github.com/zigcc/skills/tree/9de4482769b57e6dfabfee12038d1dd9e61afd10/zig-0.17),
which declares the MIT license in its `SKILL.md`. The source has no separate
license file. Local changes split the reference from this entrypoint, tighten
the version check, and correct statements against the installed stable source.

Use the project's pinned compiler. In this repository, run
`mise exec -- zig env` to discover its standard-library source and
`mise exec -- bash .agents/skills/zigcc/zig-0-17/scripts/check-zig-version.sh`
to check the exact stable version. Master and development snapshots are
separate targets.

Search installed source and compile a minimal probe for uncertain APIs. Read
the relevant part of [the migration reference](references/migration.md) for:

- language changes: enum/backing-integer conversions, `@splat`, `@bitCast`,
  `@hasDecl`, and removed syntax;
- allocation and collections: `SafeAllocator`, `BufferFirstAllocator`,
  allocator formatting, `ArrayList.last`, and bit sets;
- metaprogramming: SoA type reflection and type-creating builtins;
- build/entrypoint changes: maker/configurer separation, lazy paths,
  passthrough arguments, and `std.process.Init`.

The [versioned language reference](https://ziglang.org/documentation/0.17.0/)
and installed library resolve uncertainty. A deprecated compatibility alias
may still compile; use the current API in new code. Do not substitute a
pointer cast for a wire-format conversion without accounting for alignment
and endianness.

Allocating library APIs accept a caller allocator and specify ownership and
borrowed-input lifetimes. Use `std.testing.allocator` for leak detection and
`std.testing.checkAllAllocationFailures` for allocating operations. Run native
tests and `zig fmt --check`; validate changed build steps with `zig build`.
Report the exact compiler and checks, and qualify untested platform behavior.
