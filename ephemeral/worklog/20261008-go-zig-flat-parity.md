# Go–Zig flat parity

correction: The user's primary goal is communication between Go and Zig; shipping a binary capability on Zig alone left a material peer integration gap. Future codec milestones must include actual bidirectional exchange across the maintained Go modules and Zig.
decision: Both Go modules and Zig still target upstream 5.9.4. Fix the existing Go value model in both modules without treating the v6 directory name as evidence of upstream 6 parity.
decision: Preserve the exported slice-based ArrayBuffer API; distinct empty ownership needs an additive allocating constructor rather than a breaking representation change.
friction: The installed agent CLI parses model flags only before the workdir, contrary to the skill example. Explicit user-selected Opus also requires unsetting caller-provider session variables. Use the verified invocation rather than silently accepting automatic reviewer selection.

decision: Opus plan review requires Float16 Uneval and empty-buffer expression expectations, module-local pin-checked binary recording, and CI enforcement of actual exchange. These are direct parity/integration requirements, not additional proof machinery.
correction: Consumer go.work verification alone is vacuous while imports still point at polytype/devalue; use explicitly redirected scratch consumer copies or report it unavailable. Production migration remains separate.

decision: Geometry validation rejects views JavaScript cannot construct; preserve upstream 5.9.4's existing odd-buffer Uneval quirk rather than back-porting 6.x expression spelling. Opus independently confirmed both current Go outputs already match the pin.

friction: A redirected polytype codegen test compiled and ran generated codecs against v5, but its fixture dependency assertion still filtered only the polytype module. The migration must track the independent runtime prefix as well; updated the scratch check and migration plan rather than claim an unredirected consumer test proves compatibility.

decision: Binary exchange is now a normal root test and CI check, with both Go modules producing native inputs for Zig and both decoding independently generated Zig output. Missing/empty peer files and wrong count/name/version fail.
decision: Each maintained module regenerates and pin-checks its own binary and expression corpus; v6 recording does not overwrite Zig's v5 fixtures. The runtime remains additive and both modules still target 5.9.4.
decision: Redirected polytype codegen and 42 selected skgo tests passed; full skgo example validation is unavailable because its frontend build is absent. This does not complete the separately requested consumer migration.

friction: Installable root Zig package PR #3 landed during implementation review. Rebased onto 20a8d45, preserving addPackage/source_dir and integrating the interop step with that working directory. Root tests/lint passed; missing integration input fails explicitly. Request a full re-review of the final combined tree rather than rely on the older snapshot.

correction: Opus caught a premature 6.x parse-error spelling in the new raw backing-slot guard. Preserve 5.9.4's Invalid data for a real slot with the wrong tag, and port its three exact upstream invalid-input rows. Missing/out-of-range/fractional references actually throw native TypeError in 5.9.4 (verified directly); those remain Go Invalid input rather than invent an upstream Invalid data expectation.
decision: Guard requested Go interop flags in TestMain, so a renamed or unmatched test filter cannot silently pass a phase. Expand redirected skgo proof to its entire root package plus internal/formdata and internal/remotearg after Opus independently verified they pass.

decision: Implementation Opus round 02 reached only nitpicks remain on the complete rebased tree. Accept and document the two malformed raw-slot diagnostic differences (null and fabricated object key 0), preserving the direct ArrayBuffer-array guard; successful upstream-produced documents and all ported upstream expectations agree. No new proof machinery requested or introduced.
