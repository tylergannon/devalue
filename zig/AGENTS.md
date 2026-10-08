# Zig package

This is the separate Zig devalue package. Read README.md for the supported flat
profile, public API, ownership rules, callback semantics and acceptance exceptions.

Read [the Zig development skill](../.agents/skills/zig-development/SKILL.md)
before writing Zig. The repository's `mise.toml` pins Zig 0.17.0; invoke it with
`mise exec -- zig` from the repository or this directory.

The initial implementation is flat-format encoding and decoding. Reuse the
upstream-JavaScript expectations in `../v5/testdata/golden.json` (devalue 5.9.4).
Keep native Zig tests for decoded contents, reference identity, allocation
failures, and ownership/lifetime behavior. A matching encoder/decoder round
trip alone cannot prove parity. Fixtures remain in their shared location. Expression generation is outside the
initial profile.

Devalue owns serialization. Client HTTP, Kit argument canonicalization, query
caching, and generated client models remain with their consumers.
