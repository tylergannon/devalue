Parity: devalue 5.9.4

Initial standalone Go runtime release at `github.com/tylergannon/devalue/v5`.

- `Stringify` and `Parse` exchange devalue's flat graph format, including all twelve typed-array kinds and DataView.
- `Uneval` and `UnevalWith` emit JavaScript expressions from the shared Go value model.
- Binary views preserve whole backing bytes, offsets, lengths, repeated views, shared backing storage and cycles. `NewArrayBuffer` preserves owned empty-buffer identity.
- The Go and experimental Zig codecs exchange 111 upstream-recorded binary cases in both directions. Native model limits and the Zig flat-format profile are documented in the README.

The `v6` directory still tracks devalue 5.9.4 and is not released. Generated typed codecs remain in `github.com/tylergannon/polytype/devalue/codegen`; consumer migration is separate.
