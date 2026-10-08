# Go–Zig binary flat-codec interoperability

The deliverable is a shared binary-value surface on which Go v5, Go v6 and Zig
can exchange upstream devalue 5.9.4 flat documents. The user corrected the
previous milestone: an independently working Zig codec is insufficient when
the Go peer rejects its values. Both Go modules still pin 5.9.4; this change
does not claim v6 parity with upstream 6.x.

## Result

Extend the existing Go `*TypedArray` and `*DataView` model, without changing
exported field types, to `Stringify` and `Parse`. Support all twelve upstream
typed-array tags, including Float16Array, plus DataView. Transport raw backing
bytes, preserve view kind/extent, repeated view identity, distinct equal
views, shared backing buffers and graph cycles. Use the upstream compact/full-
extent wire spelling and buffer-slot allocation order. Reducer/reviver
precedence remains intact.

Add `NewArrayBuffer([]byte)` as a copying constructor with distinct allocation
even for an empty buffer. Existing slice literals continue to work; a nil or
zero-capacity empty slice cannot express distinct buffer ownership. Decode
empty buffers into owned storage and key empty buffers with positive capacity
by their backing allocation. Apply the identity rule to both serializers.
Document the constructor requirement for empty shared buffers. Do not change
the ArrayBuffer slice type or introduce a parallel view model.

Both Stringify and Uneval use the same native view validation. It rejects
unknown constructors, nil view pointers, negative/out-of-range extents and
misaligned typed offsets/byte lengths. Bound arithmetic uses
subtraction/division so it cannot overflow. Decoder validation checks the
referenced raw slot is ArrayBuffer before hydration, then checks the revived
value is an actual ArrayBuffer. Exercise self/mutual references and array-like
allocation attacks with real reviver payloads, negative-sentinel and out-of-
range backing-slot indices. Test invalid geometry in Uneval as well as
Stringify. Reject geometry JavaScript cannot construct. For valid views
preserve 5.9.4 expression bytes, including its partial-element quirk: a
hoisted odd-sized buffer emits new T(buffer).subarray(...) that fails when
evaluated; an inline one errors while rendering its whole element list. Record
that pair as an upstream expectation; the corrected constructor spelling
belongs to upstream 6.x (change-map row 14), not this parity target.

Canonical upstream-produced view documents are the common decoding contract.
Go keeps upstream's constructor semantics for optional offset/count fields
where its existing model can express them; Zig already documents stricter
integer/arity admission for manually crafted documents. Do not silently claim
their malformed-input acceptance or every JavaScript coercion is identical.
Float16 adds raw storage transport and requires correct Uneval rendering in
both modules: half-to-double conversion, JS formatting including negative
zero, and two-byte subarray geometry. An unhandled numeric kind must return an
error rather than silently emit empty elements.

## Validation

Port the existing complete binary fixture inputs to native Go constructions in
both modules. Expectations come from the pinned JavaScript recorder, never
either port. The recorded corpus covers every kind, whole/sub/empty/odd-sized
buffers, aliases, cycles, floating bit patterns, BigInt storage, copied Node
Buffer sources, file bytes and reducers. Independently check decoded contents
and identity; a successful same-codec round trip alone is insufficient. Add
targeted malformed-wire and native-geometry tests, including upstream's raw-
buffer guard and reviver precedence. Keep module tests self-contained and
Node-free by recording their static fixtures under each testdata/. Each
module's recorder uses its own pin, regenerates its own binary corpus and
records targeted Float16 and empty-shared-buffer Uneval expectations. Native
tests require every fixture version to match UpstreamVersion. Update the v6
change map's stale binary assumptions and malformed-view parsing work item.

Add a small root `test-interop` command to normal `just test`: native Go tests
emit independently constructed upstream-verified documents for each module;
native Zig tests decode those documents and compare against independently
constructed graphs, then emit their own documents; Go tests decode the Zig
documents and check their independently constructed expected values. Exchange
temporary files only. Assert nonempty complete case counts and names in all
phases, and fail on missing files when the integration recipe is invoked. Add
a CI job with Go and mise-pinned Zig that runs this recipe. This is a direct
codec integration check, not a new proof framework or generated tracking
system. Native language suites continue to run without starting Node or the
other language compiler.

Run `just test`, `just lint`, Zig ReleaseSafe tests and relevant Go consumer
tests only after redirecting their legacy polytype/devalue imports in scratch
consumer copies to this runtime; go.work alone is vacuous because both
consumers still import polytype's bundled codec. Report this redirection and
any unavailable consumer proof explicitly. Production consumer migration
remains a separate task (ephemeral/polytype-migration.md); until it happens
that bundled runtime still cannot exchange binary views with Zig. Audit and
name remaining cross-language differences (including sparse-array allocation
limits and native identity limitations); do not label binary interoperability
as complete upstream feature parity. Retain upstream behavior coverage from
the previous milestone and update stale capability descriptions.

## Review and delivery

Claude Opus reviews this plan through the consensus skill before
implementation, and reviews the completed change and proof again before a PR.
Resolve material findings with ordinary tests and source evidence; the user
expressly rejects elaborate proof machinery. After consensus and passing
checks, create and squash-merge the PR, synchronize main, and clean up task
processes/worktree where the desktop app permits it.
