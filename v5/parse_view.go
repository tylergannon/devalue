package devalue

import (
	"bytes"
	"encoding/json"
	"errors"
	"math"
	"regexp"
	"strconv"
	"strings"
)

// hydrateView follows upstream 5.9.4's two guards: inspect the raw backing
// slot before hydration, then require a genuine buffer after custom revival.
func (p *parser) hydrateView(index int, tag string, elems []json.RawMessage) (any, error) {
	if len(elems) < 2 {
		return nil, errInvalidInput
	}
	ref, ok := asIndex(elems[1])
	if !ok || ref < 0 || ref >= len(p.values) {
		return nil, errInvalidInput
	}
	var rawBuffer []json.RawMessage
	var bufferTag string
	if json.Unmarshal(p.values[ref], &rawBuffer) != nil || len(rawBuffer) == 0 ||
		json.Unmarshal(rawBuffer[0], &bufferTag) != nil || bufferTag != "ArrayBuffer" {
		return nil, errInvalidData
	}
	backing, err := p.hydrate(ref, false)
	if err != nil {
		return nil, err
	}
	buffer, ok := backing.(ArrayBuffer)
	if !ok {
		return nil, errInvalidInput
	}
	width := 1
	if tag != "DataView" {
		width = TypedArrayKind(tag).BytesPerElement()
	}
	offset := 0
	if len(elems) > 2 {
		offset, ok = viewIndex(elems[2])
		if !ok {
			return nil, errInvalidInput
		}
	}
	if offset > len(buffer) || offset%width != 0 {
		return nil, errInvalidInput
	}
	byteLength := len(buffer) - offset
	if len(elems) > 3 {
		count, valid := viewIndex(elems[3])
		if !valid || count > byteLength/width {
			return nil, errInvalidInput
		}
		byteLength = count * width // bounded above by the remaining buffer
	} else if byteLength%width != 0 {
		return nil, errInvalidInput
	}
	var view any = &DataView{Buffer: buffer, ByteOffset: offset, ByteLength: byteLength}
	if tag != "DataView" {
		view = &TypedArray{Kind: TypedArrayKind(tag), Buffer: buffer, ByteOffset: offset, ByteLength: byteLength}
	}
	p.store(index, view)
	return view, nil
}

// viewIndex implements ToIndex for JSON constructor arguments: truncation
// toward zero, NaN -> zero and primitive/array coercion. It never allocates a
// buffer or converts an extent to int before checking its range.
func viewIndex(raw json.RawMessage) (int, bool) {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	var value any
	if decoder.Decode(&value) != nil {
		return 0, false
	}
	var number float64
	switch v := value.(type) {
	case nil:
	case bool:
		if v {
			number = 1
		}
	case json.Number:
		number, _ = strconv.ParseFloat(string(v), 64)
	default:
		number = indexStringNumber(indexPrimitiveString(value))
	}
	if math.IsNaN(number) {
		number = 0
	}
	number = math.Trunc(number)
	if number < 0 || number > 9007199254740991 || number > float64(int(^uint(0)>>1)) || math.IsInf(number, 0) {
		return 0, false
	}
	return int(number), true
}

func indexPrimitiveString(value any) string {
	switch v := value.(type) {
	case nil:
		return ""
	case string:
		return v
	case bool:
		return strconv.FormatBool(v)
	case json.Number:
		f, _ := strconv.ParseFloat(string(v), 64)
		return formatNumber(f)
	case []any:
		parts := make([]string, len(v))
		for i, element := range v {
			parts[i] = indexPrimitiveString(element)
		}
		return strings.Join(parts, ",")
	default:
		return "[object Object]"
	}
}

var indexDecimal = regexp.MustCompile(`^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$`)

func indexStringNumber(s string) float64 {
	// ECMAScript WhiteSpace and LineTerminator, including BOM but not U+0085.
	s = strings.Trim(s, "\t\n\v\f\r \u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff")
	if s == "" {
		return 0
	}
	if s == "Infinity" || s == "+Infinity" {
		return math.Inf(1)
	}
	if s == "-Infinity" {
		return math.Inf(-1)
	}
	if len(s) > 2 && s[0] == '0' {
		base := 0
		switch s[1] {
		case 'x', 'X':
			base = 16
		case 'b', 'B':
			base = 2
		case 'o', 'O':
			base = 8
		}
		if base != 0 {
			// Validate all digits first: even an overflowing prefix followed
			// by an invalid digit is NaN, not an out-of-range index, in JS.
			for _, c := range s[2:] {
				digit := -1
				switch {
				case c >= '0' && c <= '9':
					digit = int(c - '0')
				case c >= 'a' && c <= 'f':
					digit = int(c-'a') + 10
				case c >= 'A' && c <= 'F':
					digit = int(c-'A') + 10
				}
				if digit < 0 || digit >= base {
					return math.NaN()
				}
			}
			n, err := strconv.ParseUint(s[2:], base, 64)
			if err == nil {
				return float64(n)
			}
			if errors.Is(err, strconv.ErrRange) {
				return math.Inf(1)
			}
			return math.NaN()
		}
	}
	if !indexDecimal.MatchString(s) {
		return math.NaN()
	}
	f, _ := strconv.ParseFloat(s, 64)
	return f
}
