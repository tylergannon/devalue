#!/usr/bin/env bash
# Compatibility check in disposable redirected copies, not production migration.
set -euo pipefail
repo_dir="$(pwd)"
scratch_dir="$(mktemp -d "$repo_dir/ephemeral/consumer-scratch.XXXXXX")"
trap 'rm -rf "$scratch_dir"' EXIT
for project in polytype skgo; do
    mkdir -p "$scratch_dir/$project"
    rsync -a --exclude=.git --exclude=ephemeral --exclude=node_modules --exclude=.svelte-kit --exclude=.cache "/Users/tyler/src/$project/" "$scratch_dir/$project/"
done
python3 - "$scratch_dir" "$repo_dir" <<'PY'
from pathlib import Path
import sys
root, runtime = map(Path, sys.argv[1:])
for project in ('polytype','skgo'):
    for path in (root/project).rglob('*'):
        if not path.is_file() or not (path.name.endswith('.go') or path.name.endswith('.go.golden')):
            continue
        text=path.read_text()
        # Preserve the codegen package path; only redirect the runtime.
        text=text.replace('"github.com/tylergannon/polytype/devalue"',
                          '"github.com/tylergannon/devalue/v5"')
        path.write_text(text)
# The migrated runtime is a separate fixture dependency, rather than a
# package within polytype; exercise its source tracking under the new prefix.
p = root/'polytype/devalue/codegen/cache_inputs_test.go'
p.write_text(p.read_text().replace('TrackedFixtureDependencies("testdata", "github.com/tylergannon/polytype")',
                                   'TrackedFixtureDependencies("testdata", "github.com/tylergannon/devalue/v5")'))
p = root/'polytype/devalue/codegen/generate_test.go'
s = p.read_text().replace('testutils.TrackFixtureDependencies(t, "testdata", "github.com/tylergannon/polytype")',
    'testutils.TrackFixtureDependencies(t, "testdata", "github.com/tylergannon/polytype")\n\ttestutils.TrackFixtureDependencies(t, "testdata", "github.com/tylergannon/devalue/v5")')
p.write_text(s)
for path in [root/'polytype/go.mod',root/'skgo/go.mod',
             root/'polytype/devalue/codegen/testdata/fixture/go.mod']:
    path.write_text(path.read_text()+f'\nrequire github.com/tylergannon/devalue/v5 v5.0.0\nreplace github.com/tylergannon/devalue/v5 => {runtime}/v5\n')
PY
(cd "$scratch_dir" && go work init "$repo_dir/v5" "$scratch_dir/polytype" "$scratch_dir/skgo")
(cd "$scratch_dir/polytype/devalue/codegen" && GOWORK="$scratch_dir/go.work" go test -c -o "$scratch_dir/codegen.test")
(cd "$scratch_dir/polytype/devalue/codegen" && GOWORK=off "$scratch_dir/codegen.test" -test.v)
for package in . ./internal/formdata ./internal/remotearg; do
    test_file="$scratch_dir/skgo-${package##*/}.test"
    (cd "$scratch_dir/skgo" && GOWORK="$scratch_dir/go.work" go test -c -o "$test_file" "$package")
    (cd "$scratch_dir/skgo/$package" && GOWORK=off "$test_file" -test.v)
done
