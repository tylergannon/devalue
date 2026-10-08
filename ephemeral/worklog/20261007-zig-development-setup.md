# Zig development setup

decision: User scoped the first phase to current Zig tooling and coding-agent research; flat codec implementation follows later, in a separate zig/ package in this repository.
friction: Homebrew zig resolves to 0.16.0-dev.2915+065c6e794 while stable 0.17.0 is available -> pin mise and use mise exec so agents do not silently use the old binary.
decision: Two Luna researchers found no inspected standalone skill verified for stable Zig 0.17 -> create compact original repository-local guidance grounded in installed source; retain candidate links in ephemeral/zig-development-research.md.
friction: mise's first Zig download mirror failed transiently; its fallback mirror installed 0.17.0 -> wait for installation completion before launching a dependent mise exec, which otherwise overlaps installation.
friction: Repository mise pin is not selected by plain zig in this shell -> use mise exec -- zig explicitly; the pinned compiler passed native allocator/JSON and allocation-failure smoke tests. Global shell/tool configuration was not changed.
correction: User asked why existing skills were not updated. Direct git checkout found zigcc/skills already includes zig-0.17, contrary to the earlier Luna research report -> inspect candidate source directly before concluding a skill is stale or absent.
decision: Adopt zigcc's 0.17 skill at 9de4482769b57e6dfabfee12038d1dd9e61afd10 with a compact entrypoint, source MIT declaration, corrected allocator claims, and exact stable version check; keep devalue-specific guidance in the existing local skill.
skill_issue: zigcc/zig-0.17 source=9de4482769b57e6dfabfee12038d1dd9e61afd10 severity=bug -> upstream version checker accepts future/development compilers, SafeAllocator guarantees omit backing allocator conditions, and several deprecated aliases are described as missing. Fix locally and validate actual API behavior.
decision: Repository has no borrowed-skill package or manifest checks and forbids provenance trackers -> retain attribution and upstream license declaration in the skill itself instead of adding a new tracking subsystem.
correction: Do not leave the default Zig stale after a request to update the toolchain -> upgraded homebrew/core/zig to stable 0.17.0, retaining the project mise pin for reproducibility. The old package came from an untrusted nightly tap; qualifying the trusted core formula avoided broad tap trust.
decision: Strategy advice proposed, awaiting user direction: hand-written graph-aware flat codec first; comptime specialization belongs in optional typed Zig adapters, sharing the same protocol rules. Runtime payload structure, reference indices, and graph identity remain runtime work.
decision: Favor explicit ownership, stable node handles, compact tables, and fewer intermediate allocations before speculative optimizations. Prove upstream bytes plus independent decoded contents/identity, then benchmark representative consumer workloads. Existing v5 corpus contains 359 cases pinned to devalue 5.9.4.
decision: Native-client Swift models are not automatically visible to Zig comptime; generated models and calls remain consumer-owned. Avoid adding an external schema/code-generation framework for this codec.
decision: User requested a written development plan, consensus review by Claude Fable, and tight test expectations before implementation. Plan and review artifacts live under ephemeral/; no codec is implemented in this phase.
friction: Installed agent CLI uses Go flag parsing and accepts flags before WORKDIR; the consensus example shows resume flags after WORKDIR -> use the installed CLI's verified argument ordering while keeping the worktree as the first positional and automatic reviewer selection.
correction: Fable round 01 found Zig absent from aggregate/CI gates, ambiguous surrogate errors, and a Go-only UTF-16 sorting rule -> require native gates/CI, define native-vs-document error classes, and make JavaScript property enumeration an explicit graph contract.
decision: Native probe verifies test-runtime fixture access from a separate Zig build root and 0.17 scanner rejection of raw WTF-8/unpaired surrogate escapes. These are setup/design evidence, not codec parity or performance proof.
correction: Fable round 02 showed valid custom cycles are resolved in 5.9.4 and a self-reference may invoke its reviver twice with a partial payload -> preserve that source behavior explicitly and require the two upstream circularCustomTypes tests plus infinite-payload rejection. Reducer-once assumptions do not apply to revivers.
decision: Claude Fable 5.1 round 03 reached only nitpicks remain; plan consensus achieved after four material findings were resolved. Final RegExp/Date metadata clarifications were folded into the test contract. This is planning readiness only, with codec implementation and runtime proof still pending.

## Implementation request

scope: User authorized building the reviewed Zig package and implementation consensus with Claude Opus; explicitly rejected elaborate proof machinery. Use native tests, upstream fixtures, scratch Go comparison and a real local-path public consumer.
friction: Installed `agent` automatically overrides CLI model flags when CODEX_THREAD_ID is present. Explicit user-requested Opus requires standalone selection with those caller-detection environment variables unset; CLI `opus` alias is documented as the latest Opus in installed Claude help. This is a user-authorized override of automatic reviewer selection, not a tool change.
decision: First decoder uses Zig's iterative JSON parser as a temporary wire tree plus an owned devalue graph. This is simpler than a new JSON scanner; measure the cost before specializing. The wire tree is released before returning. Resource nesting/traversal limits are explicit.
friction: Zig numeric zero-padding of signed positive integers emits a plus sign; Date fields must be unsigned magnitudes. Native date fixture exposed this immediately.
decision: Ordinary increasing array insertion now appends directly, removing measured quadratic decode scanning. Aliased 1,000-element decoding improved from ~163us to ~34us in initial samples; timings and allocation traffic stay in the tracked benchmark report rather than claims infrastructure.
decision: Shared fixture corpus expanded from 359 to 368 through the existing pinned upstream recorder; Zig-only corpus currently has 34 independent native constructors. Scratch Go comparator confirms shared documents and actual public Zig consumer output in both v5/v6; distinct identities outside Go representability are validated natively.
correction: Upstream reducer tag names are interpolated raw, unlike ordinary strings. JSON-safe names containing `<` or U+2028 must retain those exact bytes; applying normal devalue string escaping broke parity. Added a pinned JS fixture/native-constructor regression and kept invalid quote/backslash/control/UTF-8 rejection explicit.
review_finding: Opus reproduced a stale Zig test-run cache: changing runtime corpus/version metadata alone reused a cached success. Set the test Run step's has_side_effects=true, then warmed the cache, corrupted only corpus metadata and confirmed rejection without source/cache changes. Restored the exact fixture and confirmed success. This is a native build-step fix, not a new proof framework.

### User correction: reconsider the implementation before continuing

The user challenged the collection complexity and missing upstream robustness
coverage. Paused further production changes and audited installed Zig 0.17
containers and all six upstream v5.9.4 test files. Zig has both ordinary and
insertion-ordered hash maps; there is no need for a custom bucket table.
Preserving upstream wire traversal did not justify replacing hashed lookups with
linear scans. Binary search would not fix repeated sorted insertion costs.

The prior corpus figure overstated the breadth of behavioral evidence: round
trips do not independently prove encoder inputs, decoder semantics, hostile
input handling, or collection scaling. The next work must port all applicable
upstream cases, including relevant invariants in operations-override tests,
and explicitly identify features excluded by the approved profile. Wrote
`ephemeral/zig-implementation-reconsideration.md` with the audit and resumption
conditions. The current hash-index/scanner revision remains uncommitted and
unaccepted; comparative timings and Opus re-review are still outstanding.

correction: User made full pinned-upstream behavioral test fidelity a before-landing requirement. Tooling-only/language-specific mechanics may be excluded, but applicable native codec invariants must be retained. Existing feature/profile omissions cannot silently waive behavioral tests; reconcile them before claiming parity. Ports need not all happen immediately.
correction: User prioritized correct behavior and a usable first version, with efficiency work afterward. Do not turn optimal descending insertion complexity or allocation tuning into an initial readiness gate. Keep upstream resource-safety regression behavior distinct from general performance optimization. Updated the development plan and reconsideration note accordingly; production implementation remains paused during this clarification.

### Basic flat-codec correctness resumed

scope: User directed finishing basic correctness and usability first, then returning to typed views, expression generation and async; full upstream test fidelity still gates landing. Keep current standard hash indexes/ordered views instead of requiring an ArrayHashMap refactor or optimal insertion performance.
correction: First Opus review found linear keyed lookup/sorted insertion, the generic JSON-tree deviation and thin mutation/generated-graph tests. Current revision uses standard hash lookup, lazy ordered enumeration, cached owned-string validation/hashes, and a std.json.Scanner token tape. These are implementation corrections, not a new proof framework.
decision: Ported 79 explicit upstream/native fixture inputs through the pinned recorder and independent Zig construction/topology assertions; added the complete five-size sparse DoS matrix, 49,000-layer prototype attack, invalid/null-prototype key cases and pre-reviver guards. Custom FunctionRef bytes/payloads are covered without implementing JavaScript function execution. Outstanding feature and API differences are recorded in ephemeral/zig-upstream-test-coverage.md, not treated as blanket waivers.
friction: Optimized safety mode exposed NondeterministicMemoryUsage in standard allocation-failure enumeration despite passing debug tests. In-place backing resize/remap success can change allocation counts across runs. Use the normal leak-checking allocator with resize/remap refused only below failure injection, so every backing growth takes a repeatable allocation path; normal tests still exercise allocator growth. ReleaseSafe now passes all 27 tests, including every allocation failure.
decision: Fresh public path-dependency consumer builds/runs against the revised API. Both maintained Go codecs agree with all 368 shared documents, 76 built-in upstream-native documents, consumer output and five independently constructed workload byte streams. Refreshed benchmark results describe current code; general tuning remains deferred and no universal speed claim is made.
review_result: Claude Opus 5.5 round 02 reached only nitpicks remain after whole-implementation review, independent Debug/ReleaseSafe and repository checks, upstream coverage comparison and scaling probes. All material round-01 findings resolved. The basic correctness milestone has consensus; this does not authorize landing with deferred upstream features.
correction: Clarified strict numeric-reference acceptance separately from base64 and documented exclusive access for node/stringify, which lazily normalize internal order. Also made borrowed primitive byte immutability explicit. These are ownership/acceptance documentation clarifications, not new APIs.
review_note: Round 02's inventory mistakenly says duplicate JSON keys are rejected. Current decoder keeps the last value in the first insertion position, matching JSON.parse. Added a native regression for that behavior and zero reviver effects from discarded payloads; no production implementation changed after review. Final Debug/ReleaseSafe have 28 tests, just test/just lint pass, and diff whitespace checks pass. Deferred features and acceptance/API differences remain tracked before-landing work.
