package devalue

// UpstreamVersion is the release of the JavaScript devalue package
// (https://github.com/sveltejs/devalue) that this package is feature-equivalent
// to. Each release of this module names exactly one, and the module's major
// version is that release's major: for every value the Go model can express
// and each serializer supports, [Stringify] and [Uneval] write the
// bytes that release writes, and [Parse] reads that release's documents back
// into the same value. The package documentation lists what the Go model cannot
// express.
//
// It is the devalue version pinned in this module's package.json and the
// version that recorded the conformance goldens, and a test fails if the three
// disagree. Moving it to a newer devalue is a deliberate change that re-records
// the goldens and ports every behavior the new release changed.
const UpstreamVersion = "5.9.4"
