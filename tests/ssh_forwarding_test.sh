#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
agent_pid=""

cleanup() {
    if [[ -n "$agent_pid" ]]; then
        kill "$agent_pid" 2>/dev/null || true
    fi
    rm -rf "$test_root"
}
trap cleanup EXIT

fail() {
    echo "not ok - $*" >&2
    exit 1
}

assert_contains() {
    local file="$1" expected="$2"
    grep -Fqx -- "$expected" "$file" || fail "$file does not contain argument: $expected"
}

assert_not_contains_text() {
    local file="$1" unexpected="$2"
    if grep -Fq -- "$unexpected" "$file"; then
        fail "$file unexpectedly contains: $unexpected"
    fi
}

mkdir -p "$test_root/bin"

cat > "$test_root/bin/uname" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${TEST_UNAME:?}"
STUB

cat > "$test_root/bin/docker" <<'STUB'
#!/usr/bin/env bash
: "${DOCKER_ARGS_FILE:?}"
printf '%s\n' "$@" > "$DOCKER_ARGS_FILE"
STUB

chmod +x "$test_root/bin/uname" "$test_root/bin/docker"

run_wrapper() {
    local wrapper="$1" os="$2" home_dir="$3" args_file="$4"
    shift 4
    mkdir -p "$home_dir/workspace"
    env -u SSH_AUTH_SOCK \
        PATH="$test_root/bin:$PATH" \
        HOME="$home_dir" \
        TEST_UNAME="$os" \
        DOCKER_ARGS_FILE="$args_file" \
        "$wrapper" "$@" "$home_dir/workspace"
}

start_test_agent() {
    linux_socket="$test_root/linux-agent.sock"
    command -v ssh-agent >/dev/null || fail "ssh-agent is required for the Linux socket regression"
    ssh-agent -D -a "$linux_socket" >"$test_root/ssh-agent.log" 2>&1 &
    agent_pid=$!
    for _ in {1..100}; do
        [[ -S "$linux_socket" ]] && break
        sleep 0.01
    done
    [[ -S "$linux_socket" ]] || fail "test ssh-agent did not create $linux_socket"
}

test_wrapper() {
    local name="$1" wrapper="$2"
    local case_dir args_file stderr_file

    # No -A: even existing OrbStack host-key data is not exposed.
    case_dir="$test_root/$name-no-agent"
    mkdir -p "$case_dir/home/.orbstack/ssh"
    : > "$case_dir/home/.orbstack/ssh/known_hosts"
    args_file="$case_dir/docker.args"
    run_wrapper "$wrapper" Darwin "$case_dir/home" "$args_file" --shell
    assert_not_contains_text "$args_file" "target=/ssh-agent"
    assert_not_contains_text "$args_file" "SSH_AUTH_SOCK=/ssh-agent"
    assert_not_contains_text "$args_file" "ssh-add -l"
    assert_not_contains_text "$args_file" ".orbstack/ssh/known_hosts"

    # macOS: pass the VM-provided socket even though it is absent on the host.
    case_dir="$test_root/$name-macos"
    mkdir -p "$case_dir/home"
    args_file="$case_dir/docker.args"
    run_wrapper "$wrapper" Darwin "$case_dir/home" "$args_file" -A --shell
    assert_contains "$args_file" "--mount"
    assert_contains "$args_file" "type=bind,source=/run/host-services/ssh-auth.sock,target=/ssh-agent"
    assert_contains "$args_file" "--env"
    assert_contains "$args_file" "SSH_AUTH_SOCK=/ssh-agent"
    assert_not_contains_text "$args_file" ".orbstack/ssh/known_hosts"
    grep -Fq -- "ssh-add -l" "$args_file" || fail "$name lacks the in-container identity preflight"

    # Native Linux: forward a validated SSH_AUTH_SOCK.
    case_dir="$test_root/$name-linux"
    mkdir -p "$case_dir/home/workspace"
    args_file="$case_dir/docker.args"
    SSH_AUTH_SOCK="$linux_socket" \
        PATH="$test_root/bin:$PATH" \
        HOME="$case_dir/home" \
        TEST_UNAME=Linux \
        DOCKER_ARGS_FILE="$args_file" \
        "$wrapper" -A --shell "$case_dir/home/workspace"
    assert_contains "$args_file" "type=bind,source=$linux_socket,target=/ssh-agent"
    assert_contains "$args_file" "SSH_AUTH_SOCK=/ssh-agent"

    # Missing Linux socket: fail before Docker is invoked.
    case_dir="$test_root/$name-linux-missing"
    mkdir -p "$case_dir/home/workspace"
    args_file="$case_dir/docker.args"
    stderr_file="$case_dir/stderr"
    if SSH_AUTH_SOCK="$case_dir/not-a-socket" \
        PATH="$test_root/bin:$PATH" \
        HOME="$case_dir/home" \
        TEST_UNAME=Linux \
        DOCKER_ARGS_FILE="$args_file" \
        "$wrapper" -A --shell "$case_dir/home/workspace" 2>"$stderr_file"; then
        fail "$name accepted a missing Linux SSH socket"
    fi
    [[ ! -e "$args_file" ]] || fail "$name invoked Docker after Linux socket validation failed"
    grep -Fq -- "SSH_AUTH_SOCK is unset or not a socket" "$stderr_file" || \
        fail "$name did not explain the missing Linux socket"

    # OrbStack's host-key file is mounted read-only, and only when present.
    case_dir="$test_root/$name-known-hosts"
    mkdir -p "$case_dir/home/.orbstack/ssh" "$case_dir/home/workspace"
    : > "$case_dir/home/.orbstack/ssh/known_hosts"
    args_file="$case_dir/docker.args"
    run_wrapper "$wrapper" Darwin "$case_dir/home" "$args_file" -A --shell
    assert_contains "$args_file" "type=bind,source=$case_dir/home/.orbstack/ssh/known_hosts,target=/home/node/.orbstack/ssh/known_hosts,readonly"

    echo "ok - $name SSH forwarding"
}

linux_socket=""
start_test_agent
test_wrapper kloot "$repo_root/kloot/kloot"
test_wrapper koodex "$repo_root/koodex/koodex"
test_wrapper mister-all "$repo_root/mister-all/mister-all"

for config in "$repo_root/kloot/ssh_config_orbstack" "$repo_root/koodex/ssh_config_orbstack" "$repo_root/mister-all/ssh_config_orbstack"; do
    grep -Eq '^[[:space:]]*Host[[:space:]]+orb$' "$config" || fail "$config lacks Host orb"
    grep -Eq '^[[:space:]]*HostName[[:space:]]+host\.docker\.internal$' "$config" || fail "$config has the wrong OrbStack host"
    grep -Eq '^[[:space:]]*Port[[:space:]]+32222$' "$config" || fail "$config has the wrong OrbStack port"
    grep -Eq '^[[:space:]]*User[[:space:]]+default$' "$config" || fail "$config does not select OrbStack's default machine"
    grep -Eq '^[[:space:]]*HostKeyAlias[[:space:]]+127\.0\.0\.1$' "$config" || fail "$config lacks OrbStack's host-key alias"
    ! grep -Eq '^[[:space:]]*(ProxyCommand|IdentityFile|IdentitiesOnly|StrictHostKeyChecking)[[:space:]]' "$config" || \
        fail "$config overrides agent authentication or strict host-key checking"
done

for image in koodex mister-all; do
    cmp -s "$repo_root/kloot/ssh_config_orbstack" "$repo_root/$image/ssh_config_orbstack" || \
        fail "kloot and $image have different OrbStack SSH configurations"
done

echo "all SSH forwarding regressions passed"
