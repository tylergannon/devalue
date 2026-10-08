package devalue

import (
	"errors"
	"fmt"
	"math"
	"reflect"
	"testing"
)

func TestBinaryNativeGeometry(t *testing.T) {
	b := sequenceBuffer(8)
	maxInt := int(^uint(0) >> 1)
	invalid := []any{(*TypedArray)(nil), (*DataView)(nil),
		&TypedArray{Kind: "Unknown", Buffer: b, ByteLength: 8},
		NewDataViewRange(b, -1, 0), NewDataViewRange(b, 9, 0),
		NewDataViewRange(b, 7, 2), NewDataViewRange(b, 0, -1),
		NewDataViewRange(b, maxInt, 0), NewDataViewRange(b, 0, maxInt)}
	for _, kind := range binaryKinds[:12] {
		w := kind.BytesPerElement()
		for _, bounds := range [][2]int{{-1, 0}, {9, 0}, {0, -1}, {7, 2}, {maxInt, 0}, {0, maxInt}} {
			invalid = append(invalid, &TypedArray{Kind: kind, Buffer: b, ByteOffset: bounds[0], ByteLength: bounds[1]})
		}
		if w > 1 {
			invalid = append(invalid, &TypedArray{Kind: kind, Buffer: b, ByteOffset: 1, ByteLength: w}, &TypedArray{Kind: kind, Buffer: b, ByteLength: 1})
		}
		for _, valid := range []any{binaryView(kind, b, 8, 0), binaryView(kind, sequenceBuffer(9), 0, 1)} {
			if _, err := Stringify(valid); err != nil {
				t.Fatal(err)
			}
		}
	}
	for i, v := range invalid {
		t.Run(fmt.Sprint(i), func(t *testing.T) {
			if _, err := Stringify(v); err == nil {
				t.Fatalf("Stringify accepted %T", v)
			}
			if _, err := Uneval(v); err == nil {
				t.Fatalf("Uneval accepted %T", v)
			}
		})
	}
	// A custom reducer runs before native validation.
	v := &TypedArray{Kind: "Unknown"}
	out, err := StringifyWith(v, []Reducer{{Key: "View", Fn: func(x any) (any, bool, error) { _, ok := x.(*TypedArray); return "ok", ok, nil }}})
	if err != nil || out != `[["View",1],"ok"]` {
		t.Fatalf("view reducer precedence: %s %v", out, err)
	}

}

// Source: v5.9.4/test/index.test.js invalid typed arrays and
// test/parse-operations.test.js "view backing buffers". Go has no JS prototype,
// proxy, realm or SharedArrayBuffer distinction; require the actual Go buffer.
func TestBinaryBackingGuardsAndBounds(t *testing.T) {
	identity := func(v any) (any, error) { return v, nil }
	for _, kind := range binaryKinds {
		t.Run(string(kind), func(t *testing.T) {
			for _, tail := range []string{"", ",0", ",-1", ",-2", ",-3", ",-4", ",-5", ",-6", ",-7", ",0.5", ",99", ",9007199254740992", ",1,-1,1", ",1,0,-1", ",1,9,0", ",1,0,9007199254740991", ",1,0,1e999"} {
				wire := fmt.Sprintf(`[[%q%s],["ArrayBuffer","AAECAwQFBgc="]]`, kind, tail)
				if _, err := Parse(wire, nil); err == nil {
					t.Fatalf("accepted %s", wire)
				}
			}
			for _, raw := range []string{`{"length":2}`, `1024`, `null`, `[]`, `["Uint8Array",0]`, `["Custom",2]`, `["ArrayBufferX","AA=="]`} {
				calls := 0
				_, err := Parse(fmt.Sprintf(`[[%q,1],%s,null]`, kind, raw), map[string]func(any) (any, error){"Custom": func(any) (any, error) { calls++; return NewArrayBuffer(nil), nil }})
				if err == nil || calls != 0 {
					t.Fatalf("raw guard: %v, calls %d", err, calls)
				}
			}
			for _, bounds := range []string{"", ",0,1"} {
				for _, payload := range []string{`1024`, `[-7,1024]`, `{"length":3},1024`} {
					calls := 0
					wire := fmt.Sprintf(`[[%q,1%s],["ArrayBuffer",2],%s]`, kind, bounds, payload)
					_, err := Parse(wire, map[string]func(any) (any, error){"ArrayBuffer": func(v any) (any, error) { calls++; return v, nil }})
					if err == nil || calls != 1 {
						t.Fatalf("revived array-like guard: %s, error %v, calls %d", wire, err, calls)
					}
				}
			}
			for _, bounds := range []string{"", ",8,1"} {
				b := sequenceBuffer(16)
				calls := 0
				v, err := Parse(fmt.Sprintf(`[[%q,1%s],["ArrayBuffer",2],null]`, kind, bounds), map[string]func(any) (any, error){"ArrayBuffer": func(any) (any, error) { calls++; return b, nil }})
				if err != nil || calls != 1 {
					t.Fatalf("genuine revived buffer: %v calls %d", err, calls)
				}
				width := max(1, kind.BytesPerElement())
				offset, length := 0, 16
				if bounds != "" {
					offset, length = 8, width
				}
				expectBinary(t, binaryView(kind, b, offset, length/width), v)
				var got ArrayBuffer
				switch view := v.(type) {
				case *TypedArray:
					got = view.Buffer
				case *DataView:
					got = view.Buffer
				}
				if reflect.ValueOf(got).Pointer() != reflect.ValueOf(b).Pointer() {
					t.Fatal("revived allocation not retained")
				}
			}
			b := NewArrayBuffer(nil)
			v, err := Parse(fmt.Sprintf(`[[%q,1],["ArrayBuffer",2],null]`, kind), map[string]func(any) (any, error){"ArrayBuffer": func(any) (any, error) { return b, nil }})
			if err != nil {
				t.Fatal(err)
			}
			expectBinary(t, binaryView(kind, b, 0, 0), v)
			width := max(1, kind.BytesPerElement())
			for _, bounds := range []string{"", ",8", ",8,0", ",0,1", fmt.Sprintf(",%d", width)} {
				wire := fmt.Sprintf(`[[%q,1%s],["ArrayBuffer","AAECAwQFBgc="]]`, kind, bounds)
				v, err := Parse(wire, nil)
				if err != nil {
					t.Fatalf("valid bounds %s: %v", wire, err)
				}
				offset, length := 0, 8
				switch bounds {
				case ",8", ",8,0":
					offset, length = 8, 0
				case ",0,1":
					length = width
				case "":
				default:
					offset, length = width, 8-width
				}
				expectBinary(t, binaryView(kind, sequenceBuffer(8), offset, length/width), v)
			}
			if width > 1 {
				for _, bounds := range []string{"", ",0", ",1,0", ",0,2"} {
					if _, err := Parse(fmt.Sprintf(`[[%q,1%s],["ArrayBuffer","AAEC"]]`, kind, bounds), nil); err == nil {
						t.Fatal("bad remainder/alignment admitted")
					}
				}
			}
		})
	}
	for _, wire := range []string{`[["Uint8Array",0]]`, `[["Uint8Array",1],["Uint8Array",0]]`, `[["Uint8Array",1],["ArrayBuffer",0]]`, `[[1,3],["ArrayBuffer",2],1024,["Uint8Array",1]]`} {
		if _, err := Parse(wire, map[string]func(any) (any, error){"ArrayBuffer": identity}); err == nil {
			t.Fatalf("cycle/cached invalid buffer admitted: %s", wire)
		}
	}
	for _, payload := range []string{`null`, `-1`, `"1024"`, `{}`, `["Uint8Array",3]`} {
		if _, err := Parse(`[["Uint8Array",1],["ArrayBuffer",2],`+payload+`,["ArrayBuffer","AA=="]]`, map[string]func(any) (any, error){"ArrayBuffer": identity}); err == nil {
			t.Fatal("nongenuine buffer accepted")
		}
	}
	v, err := Parse(`[["Uint8Array",1],42]`, map[string]func(any) (any, error){"Uint8Array": identity})
	if err != nil || v != float64(42) {
		t.Fatal("view reviver did not precede guard")
	}
	want := errors.New("reviver failure")
	_, err = Parse(`[["Uint8Array",1],["ArrayBuffer",2],null]`, map[string]func(any) (any, error){"ArrayBuffer": func(any) (any, error) { return nil, want }})
	if !errors.Is(err, want) {
		t.Fatal("reviver error lost")
	}
	b := sequenceBuffer(8)
	calls := 0
	v, err = Parse(`[[1,3,4],["ArrayBuffer",2],null,["Uint8Array",1],["DataView",1,1,3]]`, map[string]func(any) (any, error){"ArrayBuffer": func(any) (any, error) { calls++; return b, nil }})
	if err != nil || calls != 1 {
		t.Fatalf("cached genuine buffer: %v calls %d", err, calls)
	}
	expectBinary(t, []any{b, NewTypedArray(Uint8Array, b), NewDataViewRange(b, 1, 3)}, v)
}

// Source: src/operations.js native fromViewInfo and ECMAScript ToIndex.
// Zig deliberately rejects these noncanonical spellings; Go preserves them.
func TestBinaryConstructorCoercions(t *testing.T) {
	for _, kind := range binaryKinds {
		t.Run(string(kind), func(t *testing.T) {
			width := max(1, kind.BytesPerElement())
			for _, c := range []struct {
				bounds        string
				offset, count int
			}{
				{`,null,null`, 0, 0}, {`,0.9,1.9`, 0, 1}, {`,-0.9,1`, 0, 1}, {`,{},1`, 0, 1},
				{`,[],1`, 0, 1}, {`,[null],1`, 0, 1}, {`,0,"1"`, 0, 1}, {`,0,true`, 0, 1},
				{`,0,"0x1"`, 0, 1}, {`,0,"0b1"`, 0, 1}, {`,0,"0o1"`, 0, 1},
				{`,0,"+0x1"`, 0, 0}, {`,0,"Inf"`, 0, 0}, {`,0,"1_0"`, 0, 0},
				{`,0,"0x100000000000000000000G"`, 0, 0},
				{`,0,1,99`, 0, 1}, {`,0,[1]`, 0, 1}, {`,0,"\ufeff1\u2028"`, 0, 1},
				{fmt.Sprintf(`,"%d",1`, width), width, 1},
			} {
				wire := fmt.Sprintf(`[[%q,1%s],["ArrayBuffer","AAECAwQFBgcICQoLDA0ODw=="]]`, kind, c.bounds)
				v, err := Parse(wire, nil)
				if err != nil {
					t.Fatalf("coercion %s: %v", wire, err)
				}
				expectBinary(t, binaryView(kind, sequenceBuffer(16), c.offset, c.count), v)
			}
		})
	}
}

func TestOwnedArrayBufferIdentityAndCopy(t *testing.T) {
	source := []byte{1, 2, 3}
	b := NewArrayBuffer(source)
	source[0] = 9
	if b[0] != 1 {
		t.Fatal("constructor borrowed bytes")
	}
	empty, other := NewArrayBuffer(nil), NewArrayBuffer(nil)
	set := NewSet(empty, empty, other)
	if set.Len() != 2 {
		t.Fatal("empty buffer SameValueZero")
	}
	m := NewMap(empty, "first", empty, "last", other, "other")
	if m.Len() != 2 {
		t.Fatal("empty buffer map identity")
	}
	if got, ok := m.Get(empty); !ok || got != "last" {
		t.Fatal("empty buffer map lookup")
	}
	var lostIdentity ArrayBuffer
	for _, buffer := range []ArrayBuffer{lostIdentity, make(ArrayBuffer, 0)} {
		if _, ok := identityKey(buffer); ok {
			t.Fatal("zero-capacity buffer got false identity")
		}
	}
	bits := []struct {
		raw  uint16
		want float64
	}{{0, 0}, {0x8000, math.Copysign(0, -1)}, {0x3c00, 1}, {0xbc00, -1}, {1, math.Ldexp(1, -24)}}
	for _, c := range bits {
		got := float16Number(c.raw)
		if got != c.want || math.Signbit(got) != math.Signbit(c.want) {
			t.Fatal("half conversion")
		}
	}
	// Element constructors also own a distinct empty allocation. Aliasing the
	// view with its buffer must not accidentally create a second backing slot.
	for _, makeView := range []func() *TypedArray{
		func() *TypedArray { return Int8ArrayOf() }, func() *TypedArray { return Uint8ArrayOf() },
		func() *TypedArray { return Uint8ClampedArrayOf() }, func() *TypedArray { return Int16ArrayOf() },
		func() *TypedArray { return Uint16ArrayOf() }, func() *TypedArray { return Int32ArrayOf() },
		func() *TypedArray { return Uint32ArrayOf() }, func() *TypedArray { return Float32ArrayOf() },
		func() *TypedArray { return Float64ArrayOf() }, func() *TypedArray { return BigInt64ArrayOf() },
		func() *TypedArray { return BigUint64ArrayOf() },
	} {
		first, second := makeView(), makeView()
		if cap(first.Buffer) == 0 || reflect.ValueOf(first.Buffer).Pointer() == reflect.ValueOf(second.Buffer).Pointer() {
			t.Fatal("element constructor lost empty ownership")
		}
		root := []any{first, first.Buffer, second}
		wire, err := Stringify(root)
		if err != nil {
			t.Fatal(err)
		}
		parsed, err := Parse(wire, nil)
		if err != nil {
			t.Fatal(err)
		}
		expectBinary(t, root, parsed)
	}
}

func FuzzBinaryRoundTrip(f *testing.F) {
	for _, c := range readBinary(f, "testdata/binary-golden.json").Cases {
		f.Add(c.Wire)
	}
	f.Fuzz(func(t *testing.T, wire string) {
		value, err := Parse(wire, nil)
		if err != nil {
			return
		}
		encoded, err := Stringify(value)
		if err != nil {
			t.Fatal(err)
		}
		parsed, err := Parse(encoded, nil)
		if err != nil {
			t.Fatal(err)
		}
		again, err := Stringify(parsed)
		if err != nil || encoded != again {
			t.Fatalf("binary encoding not stable: %s %s %v", encoded, again, err)
		}
	})
}
