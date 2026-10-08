# Published module consumer proof

This consumer uses polytype v1.5.0 and devalue/v5 v5.0.0 from the public Go proxy, with GOWORK=off and no replace directives. The generated codec was removed before regeneration with the released generator. It checks the exact expected flat document and typed decoding through the standalone runtime.

Reproduce from this directory:

```sh
export GOWORK=off GOPROXY=https://proxy.golang.org
go mod download github.com/tylergannon/polytype@v1.5.0 github.com/tylergannon/devalue/v5@v5.0.0
go run ./gen
go mod tidy
go mod tidy -diff
go run .
go install github.com/tylergannon/polytype/polytype@v1.5.0
```

result.txt records the passing public version/commit checks, generation, roundtrip, CLI help and binary metadata. attempt-01.txt and attempt-02.txt preserve setup failures from querying/building before the fresh module's checksum entries were populated. Explicitly downloading the pinned modules resolved those failures; no product code or assertions were changed.
