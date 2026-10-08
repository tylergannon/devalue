Go v5 and v6 rejected flat typed-array and DataView documents emitted by Zig. Both modules now encode and decode all twelve typed-array kinds and DataView against their unchanged devalue 5.9.4 pin, preserving backing bytes, view geometry, repeated views, shared buffers and graph cycles.

The existing Go structs stay intact. NewArrayBuffer provides distinct owned storage even when empty; element constructors and Parse preserve that ownership. Float16 also gains correct Uneval rendering, both serializers validate native view geometry, and the upstream 5.9.4 odd-buffer expression behavior remains pinned.

Validation:
- Native Go/Zig constructions match 111 pinned-JS binary expectations, with independent decoded contents and identity checks; nine recorded expression cases cover Float16 and empty sharing.
- `just test` and CI exchange Go v5/v6 documents with Zig in both directions. Requested phases fail if inputs or tests are missing.
- `just test`, `just lint`, Zig ReleaseSafe and both Go binary fuzz targets pass. Claude Opus plan and implementation consensus completed without material findings.
- Redirected scratch consumers pass polytype's codegen suite, all 413 skgo root tests, and its form-data/remote-argument suites. Production consumer migration remains separate; skgo's example needs its absent frontend build before full application validation.

The root installable Zig package is retained. This closes binary-view interoperability in these codec modules; it does not claim full JavaScript parity or migrate v6 to upstream 6.x. Known native model limits and malformed-document diagnostic differences are documented in README and ephemeral/go-zig-flat-validation.md.
