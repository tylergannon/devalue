package devalue

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"reflect"
	"strings"
	"testing"
)

var binaryEmit = flag.String("binary-emit", "", "Write native Go binary documents for the interop recipe")
var binaryPeer = flag.String("binary-peer", "", "Read native Zig binary documents for the interop recipe")
var binaryEmitted, binaryPeerVerified bool

// Requested integration phases must execute even if a test/filter is renamed.
func TestMain(m *testing.M) {
	code := m.Run()
	if (*binaryEmit != "" && !binaryEmitted) || (*binaryPeer != "" && !binaryPeerVerified) {
		fmt.Fprintln(os.Stderr, "requested binary exchange phase did not complete")
		code = 1
	}
	os.Exit(code)
}

type binaryCase struct {
	Name string `json:"name"`
	Wire string `json:"devalue"`
}
type binaryCorpus struct {
	Version string       `json:"devalue"`
	Cases   []binaryCase `json:"cases"`
}

var binaryKinds = []TypedArrayKind{Int8Array, Uint8Array, Uint8ClampedArray,
	Int16Array, Uint16Array, Float16Array, Int32Array, Uint32Array, Float32Array,
	Float64Array, BigInt64Array, BigUint64Array, "DataView"}

func sequenceBuffer(length int) ArrayBuffer {
	b := NewArrayBuffer(make([]byte, length))
	for i := range b {
		b[i] = byte(i)
	}
	return b
}
func binaryView(kind TypedArrayKind, buffer ArrayBuffer, offset, count int) any {
	if kind == "DataView" {
		return NewDataViewRange(buffer, offset, count)
	}
	return &TypedArray{Kind: kind, Buffer: buffer, ByteOffset: offset, ByteLength: count * kind.BytesPerElement()}
}

// Inputs port v5.9.4/test/{index,buffer}.test.js and the explicit per-kind
// matrix in testdata/record/binary-values.mjs. Never construct them by Parse.
func binaryValue(t testing.TB, name string) any {
	t.Helper()
	for _, kind := range binaryKinds {
		if !strings.HasPrefix(name, string(kind)+"_") {
			continue
		}
		shape := strings.TrimPrefix(name, string(kind)+"_")
		width := max(1, kind.BytesPerElement())
		buffer := sequenceBuffer(32)
		switch shape {
		case "full":
			return binaryView(kind, buffer, 0, 32/width)
		case "sub":
			return binaryView(kind, buffer, width, 2)
		case "empty_end":
			return binaryView(kind, buffer, 32, 0)
		case "empty_buffer":
			return binaryView(kind, NewArrayBuffer(nil), 0, 0)
		case "odd_explicit":
			return binaryView(kind, sequenceBuffer(33), 0, 1)
		case "identity":
			view := binaryView(kind, buffer, width, 2)
			root := NewObject("view", view, "again", view, "distinct", binaryView(kind, buffer, width, 2), "buffer", buffer)
			root.Set("self", root)
			return root
		}
	}
	copyView := func(data []byte) *TypedArray { return NewTypedArray(Uint8Array, NewArrayBuffer(data)) }
	repeated := func(v any) any { return []any{v, v} }
	if name == "uint8" || name == "browser_uint8" || strings.HasPrefix(name, "source_") || strings.HasPrefix(name, "reduced_") {
		return copyView([]byte{1, 2, 3})
	}
	switch name {
	case "empty_shared":
		b := NewArrayBuffer(nil)
		v := NewTypedArray(Uint8Array, b)
		root := NewObject("buffer", b, "view", v, "again", v, "distinct", NewTypedArray(Uint8Array, b), "data", NewDataView(b), "separate", NewArrayBuffer(nil))
		root.Set("self", root)
		return root
	case "float16_values":
		return NewTypedArray(Float16Array, NewArrayBuffer([]byte{0, 0, 0, 128, 0, 60, 1, 0, 255, 3, 0, 4, 255, 123, 0, 124, 0, 252, 1, 126}))
	case "node_alloc":
		return copyView([]byte("AAAA"))
	case "empty_copy":
		return copyView(nil)
	case "float64_negative_zero":
		return NewTypedArray(Float64Array, NewArrayBuffer([]byte{0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 0, 0, 248, 63}))
	case "raw_float_bits":
		return NewTypedArray(Float64Array, NewArrayBuffer([]byte{1, 0, 0, 0, 0, 0, 248, 127, 0, 0, 0, 0, 0, 0, 0, 128}))
	case "bigint64":
		return BigInt64ArrayOf(1, -2, 3)
	case "biguint64":
		return BigUint64ArrayOf(1, 2, 3)
	case "bigint_repeat":
		return repeated(BigInt64ArrayOf(1, 2, 3))
	case "dataview":
		return NewDataView(NewArrayBuffer([]byte{1, 2, 3}))
	case "dataview_sub":
		return NewDataViewRange(sequenceBuffer(10), 2, 4)
	case "uint16_sub":
		return Uint16ArrayOf(10, 20, 30, 40).Subarray(1, 3)
	case "typed_repeat":
		return repeated(NewTypedArray(Uint8Array, sequenceBuffer(10)))
	case "data_repeat":
		return repeated(NewDataView(sequenceBuffer(10)))
	case "data_sub_repeat":
		return repeated(NewDataViewRange(sequenceBuffer(10), 2, 4))
	case "buffer_data_repeat":
		b := sequenceBuffer(10)
		v := NewDataView(b)
		return []any{v, v, b}
	case "buffer_repeat_views", "buffer_typed_repeat":
		b := sequenceBuffer(10)
		v := NewTypedArray(Uint8Array, b)
		v2 := NewTypedArray(Uint16Array, b)
		if name == "buffer_typed_repeat" {
			return []any{v, v, v2}
		}
		return []any{v, v2}
	case "ordinary_shared":
		b := sequenceBuffer(6)
		v := binaryView(Uint8Array, b, 1, 3)
		return NewObject("buffer", b, "view", v, "again", v, "data", NewDataViewRange(b, 2, 2))
	case "isolated_copies":
		v := copyView([]byte{1, 2, 3})
		root := NewObject("first", v, "again", v, "second", copyView([]byte{4, 5}))
		root.Set("self", root)
		return root
	case "file_contents":
		data, err := os.ReadFile("testdata/binary-file-input.txt")
		if err != nil {
			t.Fatal(err)
		}
		return NewObject("file", copyView(data))
	case "odd_alone", "odd_shared":
		b := NewArrayBuffer([]byte{0, 0, 0})
		v := binaryView(Uint16Array, b, 0, 1)
		if name == "odd_shared" {
			return []any{v, b}
		}
		return v
	}
	t.Fatalf("missing binary native input %s", name)
	return nil
}

func binaryReducers(name string) []Reducer {
	if name == "reduced_view" {
		return []Reducer{{Key: "View", Fn: func(v any) (any, bool, error) { _, ok := v.(*TypedArray); return "payload", ok, nil }}}
	}
	if name == "reduced_buffer" {
		return []Reducer{{Key: "Raw", Fn: func(v any) (any, bool, error) { _, ok := v.(ArrayBuffer); return "payload", ok, nil }}}
	}
	return nil
}
func readBinary(t testing.TB, path string) binaryCorpus {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var corpus binaryCorpus
	if err := json.Unmarshal(data, &corpus); err != nil {
		t.Fatal(err)
	}
	if corpus.Version != UpstreamVersion || len(corpus.Cases) != 111 {
		t.Fatalf("binary corpus version/count: %q/%d", corpus.Version, len(corpus.Cases))
	}
	seen := map[string]bool{}
	for _, c := range corpus.Cases {
		if c.Name == "" || c.Wire == "" || seen[c.Name] {
			t.Fatalf("invalid/duplicate binary case %q", c.Name)
		}
		seen[c.Name] = true
	}
	return corpus
}

// The bijection proves sharing and distinct identities separately from bytes.
type binaryID struct {
	kind    reflect.Type
	pointer uintptr
	length  int
}

func expectBinary(t testing.TB, expected, actual any) {
	t.Helper()
	forward := map[binaryID]binaryID{}
	reverse := map[binaryID]binaryID{}
	var visit func(any, any)
	visit = func(e, a any) {
		t.Helper()
		if reflect.TypeOf(e) != reflect.TypeOf(a) {
			t.Fatalf("binary type got %T want %T", a, e)
		}
		id := func(v any) binaryID {
			rv := reflect.ValueOf(v)
			length := 0
			if rv.Kind() == reflect.Slice {
				length = rv.Len()
			}
			return binaryID{rv.Type(), rv.Pointer(), length}
		}
		switch e.(type) {
		case *Object, *TypedArray, *DataView, ArrayBuffer, []any:
			ei, ai := id(e), id(a)
			if previous, ok := forward[ei]; ok {
				if previous != ai {
					t.Fatal("shared identity lost")
				}
				return
			}
			if _, ok := reverse[ai]; ok {
				t.Fatal("distinct identities collapsed")
			}
			forward[ei] = ai
			reverse[ai] = ei
		}
		switch ev := e.(type) {
		case *Object:
			av := a.(*Object)
			if ev.NullProto != av.NullProto || !reflect.DeepEqual(ev.Keys(), av.Keys()) {
				t.Fatal("object metadata differs")
			}
			for _, key := range ev.Keys() {
				x, _ := ev.Get(key)
				y, _ := av.Get(key)
				visit(x, y)
			}
		case []any:
			av := a.([]any)
			if len(ev) != len(av) {
				t.Fatal("array length differs")
			}
			for i, x := range ev {
				visit(x, av[i])
			}
		case ArrayBuffer:
			if !bytes.Equal(ev, a.(ArrayBuffer)) {
				t.Fatal("backing bytes differ")
			}
		case *TypedArray:
			av := a.(*TypedArray)
			if ev.Kind != av.Kind || ev.ByteOffset != av.ByteOffset || ev.ByteLength != av.ByteLength {
				t.Fatal("typed view metadata differs")
			}
			visit(ev.Buffer, av.Buffer)
			if !bytes.Equal(ev.Buffer[ev.ByteOffset:ev.ByteOffset+ev.ByteLength], av.Buffer[av.ByteOffset:av.ByteOffset+av.ByteLength]) {
				t.Fatal("visible bytes differ")
			}
		case *DataView:
			av := a.(*DataView)
			if ev.ByteOffset != av.ByteOffset || ev.ByteLength != av.ByteLength {
				t.Fatal("DataView metadata differs")
			}
			visit(ev.Buffer, av.Buffer)
		default:
			if !reflect.DeepEqual(e, a) {
				t.Fatalf("binary value differs: got %v want %v", a, e)
			}
		}
	}
	visit(expected, actual)
}

func checkBinaryDecode(t testing.TB, name, wire string) {
	t.Helper()
	identity := func(v any) (any, error) { return v, nil }
	if name == "reduced_buffer" {
		if _, err := Parse(wire, map[string]func(any) (any, error){"Raw": identity}); err == nil {
			t.Fatal("custom raw-buffer slot admitted")
		}
		return
	}
	if name == "reduced_view" {
		v, err := Parse(wire, map[string]func(any) (any, error){"View": identity})
		if err != nil || v != "payload" {
			t.Fatalf("view override: %v %v", v, err)
		}
		return
	}
	actual, err := Parse(wire, nil)
	if err != nil {
		t.Fatal(err)
	}
	expectBinary(t, binaryValue(t, name), actual)
}

func TestBinaryGolden(t *testing.T) {
	corpus := readBinary(t, "testdata/binary-golden.json")
	for i, c := range corpus.Cases {
		t.Run(c.Name, func(t *testing.T) {
			encoded, err := StringifyWith(binaryValue(t, c.Name), binaryReducers(c.Name))
			if err != nil {
				t.Fatal(err)
			}
			if encoded != c.Wire {
				t.Fatalf("binary encoding\n got %s\nwant %s", encoded, c.Wire)
			}
			corpus.Cases[i].Wire = encoded
			checkBinaryDecode(t, c.Name, c.Wire)
		})
	}
	if *binaryEmit != "" {
		data, err := json.Marshal(corpus)
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(*binaryEmit, data, 0o600); err != nil {
			t.Fatal(err)
		}
		binaryEmitted = !t.Failed()
	}
}

func TestBinaryZigPeer(t *testing.T) {
	if *binaryPeer == "" {
		t.Skip("run just test-interop for native Zig exchange")
	}
	peer := readBinary(t, *binaryPeer)
	golden := readBinary(t, "testdata/binary-golden.json")
	for i, c := range peer.Cases {
		if c.Name != golden.Cases[i].Name || c.Wire != golden.Cases[i].Wire {
			t.Fatalf("peer case %d differs from upstream", i)
		}
		t.Run(c.Name, func(t *testing.T) { checkBinaryDecode(t, c.Name, c.Wire) })
	}
	binaryPeerVerified = !t.Failed()
}

// Sources: v5.9.4/src/uneval.js, test/index.test.js typed arrays and shared
// references. Odd-buffer behavior is intentionally pinned to 5.9.4, not 6.x.
func TestBinaryUnevalGolden(t *testing.T) {
	data, err := os.ReadFile("testdata/binary-uneval-golden.json")
	if err != nil {
		t.Fatal(err)
	}
	var corpus struct {
		Version string `json:"devalue"`
		Cases   []struct {
			Name       string `json:"name"`
			Expression string `json:"uneval"`
			Error      string `json:"error"`
		} `json:"cases"`
	}
	if err := json.Unmarshal(data, &corpus); err != nil {
		t.Fatal(err)
	}
	if corpus.Version != UpstreamVersion || len(corpus.Cases) != 9 {
		t.Fatal("binary expression version/count differs")
	}
	for _, c := range corpus.Cases {
		t.Run(c.Name, func(t *testing.T) {
			out, err := Uneval(binaryValue(t, c.Name))
			if c.Error != "" {
				if err == nil || err.Error() != c.Error {
					t.Fatalf("got error %v want %s", err, c.Error)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if out != c.Expression {
				t.Fatalf("expression\n got %s\nwant %s", out, c.Expression)
			}
		})
	}
}
