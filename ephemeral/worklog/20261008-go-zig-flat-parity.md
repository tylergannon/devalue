# Go–Zig flat parity

correction: The user's primary goal is communication between Go and Zig; shipping a binary capability on Zig alone left a material peer integration gap. Future codec milestones must include actual bidirectional exchange across the maintained Go modules and Zig.
decision: Both Go modules and Zig still target upstream 5.9.4. Fix the existing Go value model in both modules without treating the v6 directory name as evidence of upstream 6 parity.
decision: Preserve the exported slice-based ArrayBuffer API; distinct empty ownership needs an additive allocating constructor rather than a breaking representation change.
friction: The installed agent CLI parses model flags only before the workdir, contrary to the skill example. Explicit user-selected Opus also requires unsetting caller-provider session variables. Use the verified invocation rather than silently accepting automatic reviewer selection.

decision: Opus plan review requires Float16 Uneval and empty-buffer expression expectations, module-local pin-checked binary recording, and CI enforcement of actual exchange. These are direct parity/integration requirements, not additional proof machinery.
correction: Consumer go.work verification alone is vacuous while imports still point at polytype/devalue; use explicitly redirected scratch consumer copies or report it unavailable. Production migration remains separate.

decision: Geometry validation rejects views JavaScript cannot construct; preserve upstream 5.9.4's existing odd-buffer Uneval quirk rather than back-porting 6.x expression spelling. Opus independently confirmed both current Go outputs already match the pin.
