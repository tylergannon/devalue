# Installable Zig package

decision: SKGo needs an immutable URL/hash dependency without duplicating codec source. A root Zig package exports the existing zig/ module and includes v5/testdata/golden.json plus v5/package.json in its package paths. Tests continue using the single shared fixture location, with their working directory set to zig/.
correction: Current Devalue main is b55f530, with typed-array/DataView support; the native-client plan's e2d2dc6 profile snapshot is historical. Packaging must use current main without changing the codec profile.
friction: Zig 0.17 `zig fetch` accepts --pkg-dir, not --global-cache-dir; global compiler cache and fetched package placement are different. Archive validation used unpacking plus an independent consumer's actual fetch/build, not a guessed cache path.
correction: A package `.paths` entry for the whole zig/ directory includes ignored compiler caches during directory fetch. Enumerate tracked source entries to keep local fetch and clean archive hashes equal.
decision: Existing `just test-zig`/`lint-zig` now run the root package; CI already invokes those recipes. This tests the root entry point without a second test mechanism.
