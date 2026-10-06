#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fail() {
    echo "not ok - $*" >&2
    exit 1
}

mkdir -p "$test_root/bin"

cat > "$test_root/bin/docker" <<'STUB'
#!/usr/bin/env bash
: "${DOCKER_ARGS_FILE:?}"
printf '%s\n' "$@" > "$DOCKER_ARGS_FILE"
STUB
chmod +x "$test_root/bin/docker"

run_wrapper() {
    local wrapper="$1" home_dir="$2" args_file="$3"
    mkdir -p "$home_dir/workspace"
    HOME="$home_dir" \
        PATH="$test_root/bin:$PATH" \
        DOCKER_ARGS_FILE="$args_file" \
        "$wrapper" --shell "$home_dir/workspace"
}

test_wrapper() {
    local name="$1" wrapper="$2"
    local home_with_media="$test_root/$name Home With Spaces"
    local media_dir="$home_with_media/Library/Application Support/CleanShot/media"
    local present_args="$test_root/$name-present.args"
    local home_without_media="$test_root/$name-absent"
    local absent_args="$test_root/$name-absent.args"
    local expected_mount

    mkdir -p "$media_dir"
    run_wrapper "$wrapper" "$home_with_media" "$present_args"
    expected_mount="type=bind,source=$media_dir,target=$media_dir,readonly"
    grep -Fqx -- "$expected_mount" "$present_args" || \
        fail "$name did not pass the exact read-only CleanShot mount as one argument"

    run_wrapper "$wrapper" "$home_without_media" "$absent_args"
    if grep -Fq -- "CleanShot/media" "$absent_args"; then
        fail "$name mounted a missing CleanShot media directory"
    fi
    [[ ! -e "$home_without_media/Library/Application Support/CleanShot/media" ]] || \
        fail "$name created a missing CleanShot media directory"

    echo "ok - $name CleanShot mount"
}

test_wrapper kloot "$repo_root/kloot/kloot"
test_wrapper koodex "$repo_root/koodex/koodex"
test_wrapper mister-all "$repo_root/mister-all/mister-all"

echo "all CleanShot mount regressions passed"
