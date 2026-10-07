#!/usr/bin/env bash
# This skill describes stable Zig 0.17.0, not future or development compilers.
set -euo pipefail

zig_command="${ZIG_CMD:-zig}"
if ! command -v "$zig_command" >/dev/null 2>&1; then
    printf 'ERROR: zig not found. Set ZIG_CMD or run through mise exec.\n' >&2
    exit 1
fi

zig_actual_version="$("$zig_command" version)"
if [[ "$zig_actual_version" != "0.17.0" ]]; then
    printf 'ERROR: expected stable Zig 0.17.0; detected %s.\n' "$zig_actual_version" >&2
    exit 1
fi
printf 'OK: stable Zig %s detected.\n' "$zig_actual_version"
