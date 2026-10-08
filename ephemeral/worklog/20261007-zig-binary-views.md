# Zig binary views

decision: User assigned typed arrays/DataView here, native-client pilot elsewhere; required Claude Opus plan consensus before implementation and result consensus before merge. Use existing fixture/native-test machinery, not a new proof framework.
decision: Reused clean pinned task worktree on a new branch from origin/main; previous worktree archive was blocked by app pin protection. Baseline just test passes.
discovery: Upstream ordinary views serialize the full backing buffer and preserve its identity; Node Buffers instead normalize visible bytes to distinct fresh buffers. The API must make the distinction explicit.
