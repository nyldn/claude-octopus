#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SPAWN="$ROOT_DIR/scripts/lib/spawn.sh"

source "$SPAWN"

if ! declare -f octopus_new_task_id >/dev/null 2>&1; then
    echo "FAIL: spawn runtime has no collision-resistant task ID generator" >&2
    exit 1
fi

declare -A seen=()
for _ in $(seq 1 16); do
    task_id="$(octopus_new_task_id)"
    if [[ -n "${seen[$task_id]:-}" ]]; then
        echo "FAIL: duplicate generated task ID: $task_id" >&2
        exit 1
    fi
    seen[$task_id]=1
done

if ! grep -Fq 'local capture_id="${agent_type}-${task_id}"' "$SPAWN"; then
    echo "FAIL: spawn scratch artifacts are not provider-qualified" >&2
    exit 1
fi

for suffix in out err; do
    if ! grep -Fq ".tmp-\${capture_id}.${suffix}" "$SPAWN"; then
        echo "FAIL: .tmp scratch ${suffix} does not use provider-qualified capture ID" >&2
        exit 1
    fi
done

if ! grep -Fq '.raw-${capture_id}.out' "$SPAWN"; then
    echo "FAIL: raw scratch output does not use provider-qualified capture ID" >&2
    exit 1
fi

echo "PASS: spawn defaults and scratch artifacts are collision-resistant"
