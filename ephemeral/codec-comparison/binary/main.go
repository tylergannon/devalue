package main

import (
	"encoding/json"
	"fmt"
	v5 "github.com/tylergannon/devalue/v5"
	v6 "github.com/tylergannon/devalue/v6"
	"os"
)

func main() {
	b, err := os.ReadFile("../../zig/testdata/binary-golden.json")
	if err != nil {
		panic(err)
	}
	var corpus struct {
		Cases []struct{ Name, Devalue string }
	}
	if err := json.Unmarshal(b, &corpus); err != nil {
		panic(err)
	}
	buffers := 0
	for _, c := range corpus.Cases {
		if _, err := v5.Parse(c.Devalue, nil); err == nil {
			panic("unexpected v5 view support: " + c.Name)
		}
		if _, err := v6.Parse(c.Devalue, nil); err == nil {
			panic("unexpected v6 view support: " + c.Name)
		}
		var slots []json.RawMessage
		if err := json.Unmarshal([]byte(c.Devalue), &slots); err != nil {
			panic(err)
		}
		for _, slot := range slots {
			var tag []json.RawMessage
			if json.Unmarshal(slot, &tag) != nil || len(tag) != 2 || string(tag[0]) != `"ArrayBuffer"` {
				continue
			}
			wire := "[" + string(slot) + "]"
			x, err := v5.Parse(wire, nil)
			if err != nil {
				panic(err)
			}
			s, err := v5.Stringify(x)
			if err != nil || s != wire {
				panic("v5 buffer mismatch")
			}
			y, err := v6.Parse(wire, nil)
			if err != nil {
				panic(err)
			}
			s, err = v6.Stringify(y)
			if err != nil || s != wire {
				panic("v6 buffer mismatch")
			}
			buffers++
		}
	}
	if _, err := v5.Stringify(v5.NewTypedArray(v5.Uint8Array, v5.ArrayBuffer{1, 2, 3})); err == nil {
		panic("v5 flat encode view unexpectedly supported")
	}
	if _, err := v6.Stringify(v6.NewDataView(v6.ArrayBuffer{1, 2, 3})); err == nil {
		panic("v6 flat encode view unexpectedly supported")
	}
	fmt.Printf("Go v5/v6: %d standalone JS-recorded buffers agree; all %d binary documents rejected as expected (flat views unsupported)\n", buffers, len(corpus.Cases))
}
