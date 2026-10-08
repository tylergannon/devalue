# Zig plan round 01 adjudication

Reviewer: Claude Fable 5.1; native session
`1c3c62e2-0048-49ae-a6a0-4b835f02f69c`. The live reviewer process requested
`claude-fable-5-1`. Review target: `ephemeral/zig-development-plan.md`.

All three material findings are accepted:

1. Repository gates omitted Zig. Milestone 1 now requires native test/format
   recipes, inclusion in aggregate `just` recipes, and a pinned Zig CI job.
   Deliberate test/format failure must demonstrate propagation through those
   gates. This is future implementation work, not a claim that current Go
   gates already cover the future codec.
2. Surrogate rejection had an ambiguous error contract. Native invalid UTF-8
   is an unsupported string; decoder raw WTF-8/invalid UTF-8 and escaped lone
   high/low surrogates are invalid documents. Valid pairs succeed. The 0.17
   JSON scanner probe demonstrates the decoder mechanism without replacement.
3. UTF-16 key sorting was accidentally imported from Go's unordered-map
   adapter. The graph's property enumeration now explicitly follows JavaScript
   index-key ordering and string insertion order; tests include index boundaries
   and non-index Unicode insertion order. Encoding consumes graph enumeration.

Both nitpicks were also addressed: callback behavior and intentional reducer-name/
BigInt policy exceptions are pinned, corpus expansion is explicit, and fixture
access has a working native prototype. The separate build-root probe uses runtime
file reading with an explicit test working directory and passes with all 359
existing cases visible. It does not embed external fixtures in the public library.

Validation: the fixture/surrogate probe reports 2/2 native tests passed under
0.17.0. `just test`, `just lint`, and whitespace checks passed for the planning
worktree. Codec behavior, actual Zig aggregate gates, and performance remain
unimplemented. Re-review the whole plan before claiming plan consensus.
