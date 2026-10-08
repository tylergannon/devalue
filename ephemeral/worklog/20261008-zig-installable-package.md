# Installable Zig package

decision: SKGo needs an immutable URL/hash dependency without duplicating codec source. A root Zig package exports the existing zig/ module and includes v5/testdata/golden.json plus v5/package.json in its package paths. Tests continue using the single shared fixture location, with their working directory set to zig/.
correction: Current Devalue main is b55f530, with typed-array/DataView support; the native-client plan's e2d2dc6 profile snapshot is historical. Packaging must use current main without changing the codec profile.
