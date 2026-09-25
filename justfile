# Every major version is its own module in its own vN/ directory.
modules := `ls -d v*/go.mod | xargs -n1 dirname | tr '\n' ' '`

test:
    #!/usr/bin/env bash
    set -euo pipefail
    for m in {{modules}}; do (cd "$m" && go test ./...); done

lint:
    #!/usr/bin/env bash
    set -euo pipefail
    for m in {{modules}}; do
        (cd "$m" && go mod tidy && modernize -fix ./... && go vet ./... && staticcheck ./... && govulncheck ./... && golangci-lint run ./...)
    done
    find . \( -path ./.git -o -path ./ephemeral -o -name node_modules \) -prune -o -name '*.go' -exec goimports -w {} +

# Regenerate one module's golden.json from its pinned devalue (installs it first).
record module:
    cd {{module}} && pnpm install --frozen-lockfile && go run ./testdata/record && node testdata/record/record.mjs
