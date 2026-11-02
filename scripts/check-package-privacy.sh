#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || ! -d "$1" ]]; then
    echo "Usage: $0 <package-directory>" >&2
    exit 2
fi

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scan_root="$1"

check_file() {
    local status
    if LC_ALL=C /usr/bin/grep "$@"; then
        echo "Package contains a local build path: ${file#"$scan_root"/}" >&2
        exit 1
    else
        status=$?
        # grep returns 1 for no match; other errors must fail the check too.
        [[ $status -eq 1 ]] || exit "$status"
    fi
}

while IFS= read -r -d '' file; do
    check_file -aEq '/(Users|home)/[^/[:space:]]+/' "$file"
    check_file -aFq "$project_dir/" "$file"
done < <(/usr/bin/find "$scan_root" -type f -print0)

echo 'Package privacy check passed: no local user or project paths.'
