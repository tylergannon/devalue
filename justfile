# Every major version is its own module in its own vN/ directory.
modules := `ls -d v*/go.mod | xargs -n1 dirname | tr '\n' ' '`

test: test-zig test-interop
    #!/usr/bin/env bash
    set -euo pipefail
    for m in {{modules}}; do (cd "$m" && go test ./...); done

lint: lint-zig
    #!/usr/bin/env bash
    set -euo pipefail
    for m in {{modules}}; do
        (cd "$m" && go mod tidy && modernize -fix ./... && go vet ./... && staticcheck ./... && govulncheck ./... && golangci-lint run ./...)
    done
    find . \( -path ./.git -o -path ./ephemeral -o -name node_modules \) -prune -o -name '*.go' -exec goimports -w {} +

# Regenerate one module's golden.json from its pinned devalue (installs it first).
record module:
    cd {{module}} && pnpm install --frozen-lockfile && go run ./testdata/record && node testdata/record/record.mjs

# Zig tests use shared recorded fixtures without Node.
test-zig:
    mise exec -- zig build test

# Each side builds its own inputs and checks peer contents and graph identity.
test-interop:
    #!/usr/bin/env bash
    set -euo pipefail
    interop_dir="$(mktemp -d)"
    trap 'rm -rf "$interop_dir"' EXIT
    for m in {{modules}}; do
        (cd "$m" && go test -count=1 -run '^TestBinaryGolden$' -binary-emit "$interop_dir/$m.json")
        test -s "$interop_dir/$m.json"
    done
    mise exec -- zig build interop -Dinterop-dir="$interop_dir"
    test -s "$interop_dir/zig.json"
    for m in {{modules}}; do
        (cd "$m" && go test -count=1 -run '^TestBinaryZigPeer$' -binary-peer "$interop_dir/zig.json")
    done

lint-zig:
    mise exec -- zig build fmt
