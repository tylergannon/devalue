Adds a separate experimental Zig package for devalue 5.9.4's flat format, with a pinned Zig 0.17.0 toolchain and current development skills. The allocator-aware graph API preserves holes, shared references and cycles; the codec covers primitives, objects, arrays, Map/Set, Date/RegExp, ArrayBuffer, boxed values and custom reducers/revivers.

The implementation uses standard hash indexes with ordered enumeration and a JSON scanner token tape. Fixtures come from the pinned JavaScript recorder, and Zig runs native tests without Node. Existing Go runtime APIs are unchanged.

Validation: 28 native tests pass in Debug and ReleaseSafe; `just test` and `just lint` pass. Tests include 368 shared documents, 114 independently constructed cases, upstream malformed-input and sparse-exhaustion regressions, ownership and allocator failures. A public path-dependency consumer and Go v5/v6 comparisons pass. Claude Opus implementation consensus reached **only nitpicks remain**, with documentation clarifications applied.

This lands the user-authorized basic milestone. Full upstream parity is unfinished: typed views, expressions, async serialization and remaining value/acceptance/API differences are follow-ups. No full-parity release or publication is included. Detailed evidence and the upstream coverage note are under `ephemeral/`.
