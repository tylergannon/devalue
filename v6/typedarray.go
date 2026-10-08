package devalue

import (
	"encoding/binary"
	"errors"
	"math"
	"strconv"
	"strings"
)

// typedArrayElements renders the whole of buf, read as kind, as the
// comma-separated element list `new <kind>([...])` takes.
//
// It reads the buffer rather than the view because that is what devalue does:
// the emitted constructor always rebuilds the entire buffer, and a view that
// covers only part of it gets a trailing `.subarray(...)`.
func typedArrayElements(kind TypedArrayKind, buf ArrayBuffer) (string, error) {
	per := kind.BytesPerElement()
	if per == 0 {
		return "", errors.New("Cannot stringify arbitrary non-POJOs") //nolint:staticcheck // ST1005: devalue's message is part of the compatibility surface.
	}
	if len(buf)%per != 0 {
		return "", errors.New("byte length of " + string(kind) + " should be a multiple of " + strconv.Itoa(per))
	}

	n := len(buf) / per
	parts := make([]string, n)
	for i := range n {
		b := buf[i*per:]
		switch kind {
		case Int8Array:
			parts[i] = strconv.Itoa(int(int8(b[0])))
		case Uint8Array, Uint8ClampedArray:
			parts[i] = strconv.Itoa(int(b[0]))
		case Int16Array:
			parts[i] = strconv.Itoa(int(int16(binary.LittleEndian.Uint16(b))))
		case Uint16Array:
			parts[i] = strconv.Itoa(int(binary.LittleEndian.Uint16(b)))
		case Float16Array:
			parts[i] = formatFloatElement(float16Number(binary.LittleEndian.Uint16(b)))
		case Int32Array:
			parts[i] = strconv.Itoa(int(int32(binary.LittleEndian.Uint32(b))))
		case Uint32Array:
			parts[i] = strconv.FormatUint(uint64(binary.LittleEndian.Uint32(b)), 10)
		case Float32Array:
			parts[i] = formatFloatElement(float64(math.Float32frombits(binary.LittleEndian.Uint32(b))))
		case Float64Array:
			parts[i] = formatFloatElement(math.Float64frombits(binary.LittleEndian.Uint64(b)))
		case BigInt64Array:
			// bigint elements need the `n` suffix, or the emitted
			// `new BigInt64Array([...])` throws.
			parts[i] = strconv.FormatInt(int64(binary.LittleEndian.Uint64(b)), 10) + "n"
		case BigUint64Array:
			parts[i] = strconv.FormatUint(binary.LittleEndian.Uint64(b), 10) + "n"
		default:
			return "", errors.New("devalue: unhandled typed array kind")
		}
	}
	return strings.Join(parts, ","), nil
}

// validView checks JavaScript-constructible geometry without multiplying or
// adding untrusted extents. Explicitly bounded views may use odd-sized buffers.
func validView(buffer ArrayBuffer, offset, length, width int) bool {
	return width > 0 && offset >= 0 && length >= 0 && offset <= len(buffer) &&
		length <= len(buffer)-offset && offset%width == 0 && length%width == 0
}

func float16Number(bits uint16) float64 {
	exponent := int((bits >> 10) & 31)
	fraction := int(bits & 1023)
	var value float64
	switch exponent {
	case 0:
		value = math.Ldexp(float64(fraction), -24)
	case 31:
		value = math.Inf(1)
		if fraction != 0 {
			value = math.NaN()
		}
	default:
		value = math.Ldexp(float64(1024+fraction), exponent-25)
	}
	if bits&0x8000 != 0 {
		value = -value
	}
	return value
}

// formatFloatElement renders one float element. `toString()` collapses -0 to
// "0", silently losing the sign on round-trip, so devalue writes it out.
func formatFloatElement(f float64) string {
	if f == 0 && math.Signbit(f) {
		return "-0"
	}
	return formatNumber(f)
}
