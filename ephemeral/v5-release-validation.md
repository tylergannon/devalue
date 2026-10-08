# v5.0.0 release validation

Runtime candidate: 7cae5a8e8fd846303d2b746b1b50d16856df5f05, unchanged devalue 5.9.4 parity. This release preparation changes session notes and the migration plan only.

- `just test` passes: both Go modules, native Zig tests and 111 binary cases exchanged in both directions.
- `just lint` passes: both Go modules and Zig formatting, zero lint issues and vulnerabilities.
- All 23 test-bearing polytype packages pass in a redirected disposable consumer copy, including generated-codec compilation, recursive typed codecs and JavaScript interchange. Existing optional tsc checks skip because tsc is absent; Oxc and tsgo checks execute with installed pinned tools.
- All 24 test-bearing skgo root/example packages were exercised against the new runtime and redirected generator. The frontend was installed from its frozen pnpm lockfile and rebuilt before compiling the example tests. Every package/test passed across the recorded runs. The full final sweep stopped at one relay failure; the subsequent focused test passed on skgo CI's Node 24.21.0. No skgo product changes were made.
- The checks compiled each package's binary with a scratch go.work using v5 and both consumer copies, then ran the binary in its package directory with GOWORK=off. Every legacy runtime import in the copies was redirected; temporary fixture modules also needed explicit local runtime/generator replacements because replace directives are not transitive.
- The scratch gen fixtureModule and starter tests received only local dependency redirects; behavioral assertions were retained. These tests exercise generated codecs in compiled consumers, real handlers, prerender TS/JS builds, starter apps and the freshly built example.

The standalone release is not a claim that production consumers have migrated. polytype's migration/release is the next authorized phase, and skgo's production migration remains separate.

Source CI for the unchanged runtime:
https://github.com/tylergannon/devalue/actions/runs/37749785369
https://github.com/tylergannon/devalue/actions/runs/37749785286

Captured output is provided as the v5-consumer-checks.tar.gz release asset. It includes unsuccessful broad runs together with their dependency/toolchain fixes and focused successful reruns; those failures are not represented as passing sweeps.
