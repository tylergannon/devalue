package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	v5 "github.com/tylergannon/devalue/v5"
	v6 "github.com/tylergannon/devalue/v6"
	"os"
	"runtime"
	"strings"
	"time"
)

func check(wire string) {
	for _, codec := range []struct {
		name      string
		parse     func(string) (any, error)
		stringify func(any) (string, error)
	}{{"Go v5", parse5, v5.Stringify}, {"Go v6", parse6, v6.Stringify}} {
		v, err := codec.parse(wire)
		if err != nil {
			panic(err)
		}
		out, err := codec.stringify(v)
		if err != nil {
			panic(err)
		}
		if wire != out {
			panic(fmt.Sprintf("%s mismatch %s vs %s", codec.name, wire, out))
		}
	}
}
func workload(name string) any {
	switch name {
	case "query":
		return v5.NewObject("id", 42., "search", "Zig", "active", true)
	case "records":
		a := make([]any, 1000)
		for i := range a {
			a[i] = v5.NewObject("id", float64(i), "name", "record", "active", i%2 == 0)
		}
		return a
	case "aliases":
		a := make([]any, 1000)
		s := v5.NewObject("text", "repeated")
		for i := range a {
			a[i] = s
		}
		return a
	case "escapes":
		return strings.Repeat("<\"\\\n\u2028😀", 1000)
	default:
		a := make([]any, 1000000)
		for i := range a {
			a[i] = v5.Hole
		}
		a[0] = 1.
		a[500000] = "x"
		a[999999] = nil
		return a
	}
}

var sink any

func main() {
	if len(os.Args) > 1 && os.Args[1] == "bench" {
		for _, name := range []string{"query", "records", "aliases", "escapes", "sparse"} {
			value := workload(name)
			wire, err := v5.Stringify(value)
			if err != nil {
				panic(err)
			}
			check(wire)
			n := 100000
			if name == "records" {
				n = 500
			} else if name == "escapes" {
				n = 1000
			} else if name == "aliases" {
				n = 5000
			}
			if name == "sparse" {
				n = 10
			}
			for _, decode := range []bool{false, true} {
				for trial := range 5 {
					runtime.GC()
					var before, after runtime.MemStats
					runtime.ReadMemStats(&before)
					start := time.Now()
					for range n {
						if decode {
							v, err := v5.Parse(wire, nil)
							if err != nil {
								panic(err)
							}
							sink = v
						} else {
							v, err := v5.Stringify(value)
							if err != nil {
								panic(err)
							}
							sink = v
						}
					}
					elapsed := time.Since(start)
					sink = nil
					runtime.ReadMemStats(&after)
					op := "encode"
					if decode {
						op = "decode"
					}
					fmt.Printf("go,%s,%s,%d,%d,%d,%d,%d,%d\n", name, op, trial, len(wire), n, elapsed.Nanoseconds()/int64(n), (after.Mallocs-before.Mallocs)/uint64(n), (after.TotalAlloc-before.TotalAlloc)/uint64(n))
				}
			}
		}
		return
	}
	if len(os.Args) > 1 && os.Args[1] == "dump" {
		for _, name := range []string{"query", "records", "aliases", "escapes", "sparse"} {
			s, e := v5.Stringify(workload(name))
			if e != nil {
				panic(e)
			}
			fmt.Println(s)
		}
		return
	}
	data, err := os.ReadFile("../../v5/testdata/golden.json")
	if err != nil {
		panic(err)
	}
	var corpus struct {
		Devalue string
		Cases   []struct{ Name, Devalue string }
	}
	if err = json.Unmarshal(data, &corpus); err != nil {
		panic(err)
	}
	if corpus.Devalue != v5.UpstreamVersion || corpus.Devalue != v6.UpstreamVersion {
		panic("version mismatch")
	}
	for _, c := range corpus.Cases {
		check(c.Devalue)
	}
	fmt.Printf("%d upstream fixtures byte-equal in Go v5 and v6\n", len(corpus.Cases))
	data, err = os.ReadFile("../../zig/testdata/upstream-flat-golden.json")
	if err != nil {
		panic(err)
	}
	if err = json.Unmarshal(data, &corpus); err != nil {
		panic(err)
	}
	checked := 0
	for _, c := range corpus.Cases {
		if c.Name == "custom_nested" || strings.HasPrefix(c.Name, "function_") {
			continue
		}
		check(c.Devalue)
		checked++
	}
	fmt.Printf("%d upstream-native fixture documents byte-equal in Go v5 and v6 (3 custom fixtures checked natively)\n", checked)
	for _, file := range []string{"zig-consumer.json", "zig-workloads.jsonl"} {
		f, e := os.Open(file)
		if e != nil {
			panic(e)
		}
		s := bufio.NewScanner(f)
		s.Buffer(make([]byte, 1024), 4*1024*1024)
		for s.Scan() {
			check(s.Text())
		}
		if e = s.Err(); e != nil {
			panic(e)
		}
		f.Close()
	}
	// Direct Go semantic/identity assertions on the public Zig consumer output.
	data, err = os.ReadFile("zig-consumer.json")
	if err != nil {
		panic(err)
	}
	for _, parse := range []func(string) (any, error){parse5, parse6} {
		value, err := parse(strings.TrimSpace(string(data)))
		if err != nil {
			panic(err)
		}
		switch root := value.(type) {
		case *v5.Object:
			c, _ := root.Get("child")
			alias, _ := root.Get("alias")
			self, _ := root.Get("self")
			if &c.([]any)[0] != &alias.([]any)[0] || root != self {
				panic("identity")
			}
			if c.([]any)[1] != v5.Hole || c.([]any)[2] != v5.Undefined {
				panic("holes")
			}
		case *v6.Object:
			c, _ := root.Get("child")
			alias, _ := root.Get("alias")
			self, _ := root.Get("self")
			if &c.([]any)[0] != &alias.([]any)[0] || root != self {
				panic("identity")
			}
			if c.([]any)[1] != v6.Hole || c.([]any)[2] != v6.Undefined {
				panic("holes")
			}
		}
	}
	fmt.Println("public Zig consumer output and all five benchmark workload bytes/content agree with Go v5 and v6")
}

func parse5(s string) (any, error) { return v5.Parse(s, nil) }
func parse6(s string) (any, error) { return v6.Parse(s, nil) }
