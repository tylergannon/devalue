# Zig plan round 02 adjudication

Same Claude Fable 5.1 native session:
`1c3c62e2-0048-49ae-a6a0-4b835f02f69c`.

The material finding is accepted. The plan's generic custom-cycle rejection
statement was wrong: upstream resolves cycles when the payload is cached,
including a partially built container, and rejects an uncached payload already
being hydrated. The callback contract now reproduces upstream's reentrant/double
reviver invocation, permits observing the same partially populated payload handle,
and documents caller memoization of the returned result handle. Both pinned
`circularCustomTypes` shapes and infinite-payload rejection are named test cases.

All four nitpicks were addressed: the profile is explicitly a subset; the
existing v5 recorder will write the named Zig-only corpus using the single
shared exact package pin; null-prototype non-string keys are an explicit negative
case; the CI job will install `just` before invoking the same Zig recipes.

The reviewer independently reran the separate fixture/string-policy probe and
reported 2/2 native tests passed. This validates those design mechanisms only;
codec and callback behavior remain future implementation work. Submit the whole
current plan to another review round before declaring plan consensus.
