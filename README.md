# klooterij

*/ˌklʊətəˈrɛi̯/ — Antwerp Flemish for "a load of faffing (ballsing) about". A whole
`klooterij` of AI coding harnesses, each sealed in its own throwaway container so
you can let it rip.*

**klooterij** runs terminal AI coding agents ("harnesses") inside disposable,
isolated Docker containers. By default each agent starts in its **auto mode**:
the agent edits files and runs commands in the workspace on its own, and asks
before riskier actions. Full **YOLO-mode** (every approval prompt skipped) stays
one flag away (`-y`).

Type a harness command in any project directory and you land in a throwaway
container with that agent already running against your code. On exit the
container is torn down; only your mounted files persist. Nothing else on your
host is ever reachable.

Every harness follows the same recipe: a `node:20` dev container with common CLI
tooling, your project mounted at `/workspace`, your credentials mounted in, and
the agent launched in its auto mode.

Runs on any Docker-compatible runtime — e.g. [OrbStack](https://orbstack.dev) or
Docker Desktop on macOS.

## Harnesses

| Command  | Agent                                              | Folder     | Image           |
|----------|----------------------------------------------------|------------|-----------------|
| `kloot`  | [Claude Code](https://claude.com/claude-code)      | `kloot/`   | `kloot:latest`  |
| `koodex` | [OpenAI Codex CLI](https://github.com/openai/codex)| `koodex/`  | `koodex:latest` |
| `mister-all` | [Mistral Vibe](https://github.com/mistralai/mistral-vibe) | `mister-all/` | `mister-all:latest` |

Each folder is **self-contained**: its own `Dockerfile`, wrapper script, and
`update_*.sh` rebuild script. Adding a new harness = copy a folder, swap the CLI
package, launch command, permission flags, and config-dir mount.

- `kloot` — */klʊət/*, as in strong Antwerp's Flemish _"kloten met Claude"_
  (roughly: messing about with Claude).
- `koodex` — same spirit
- `mister-all` — "Mistral", as an Antwerp tongue says it.

Every image bundles: `git`, `gh`, `git-delta`, `ripgrep`, `fzf`, `jq`, `zsh`
(with oh-my-zsh), `python3`/`pip`, `build-essential`, plus that harness's agent
CLI. The `kloot` and `koodex` images also carry `bubblewrap` (plus `socat` in
`kloot`) for the agent's own Linux sandbox in auto mode. The `mister-all` image
installs Vibe with `uv`. The container user is `node` with passwordless `sudo`.

## Prerequisites

- A Docker-compatible runtime installed and running. On macOS, use e.g. [OrbStack](https://orbstack.dev) or [Docker Desktop](https://docs.docker.com/desktop/setup/install/mac-install/); native Linux Docker is also supported.
- The `docker` CLI on your `PATH` (your runtime installs this for you).

## Build

Each harness builds from its own folder; the wrapper expects the image tagged
exactly as shown in the table above.

```bash
cd ~/Github/klooterij/kloot  && docker build -t kloot:latest  .
cd ~/Github/klooterij/koodex && docker build -t koodex:latest .
cd ~/Github/klooterij/mister-all && docker build -t mister-all:latest .
```

Optional build args (per harness):

- `TZ` — set the container timezone, e.g. `--build-arg TZ="Europe/Copenhagen"`.
- `CLAUDE_CODE_VERSION` (kloot) / `CODEX_VERSION` (koodex) / `VIBE_VERSION`
  (mister-all) — pin an agent version (default `latest`).
- `UV_VERSION` (mister-all) — pin the `ghcr.io/astral-sh/uv` image tag (default
  `latest`).

```bash
cd ~/Github/klooterij/koodex
docker build -t koodex:latest \
  --build-arg TZ="$(date +%Z)" \
  --build-arg CODEX_VERSION=latest .
```

On Apple Silicon the images build natively for `arm64` (git-delta auto-detects
the architecture), so no `--platform` flag is needed.

To rebuild against the latest agent release and prune the old image, run the
folder's update script, e.g. `./koodex/update_koodex.sh`, `./kloot/update_kloot.sh`
or `./mister-all/update_mister-all.sh`.

## Put the commands on your `PATH`

Symlink each wrapper into a directory already on `PATH`. This keeps the scripts
in the repo (so `git pull` updates them) while making the commands global:

```bash
sudo ln -s ~/Github/klooterij/kloot/kloot   /usr/local/bin/kloot
sudo ln -s ~/Github/klooterij/koodex/koodex /usr/local/bin/koodex
sudo ln -s ~/Github/klooterij/mister-all/mister-all /usr/local/bin/mister-all
```

Each command now works from any directory:

```bash
cd ~/Github/my-project
kloot                       # start Claude Code in this project
koodex                      # start Codex CLI in this project
mister-all                  # start Mistral Vibe in this project
```

## Usage

The three wrappers share the same interface (`AGENT` = `Claude` for kloot,
`Codex` for koodex, `Vibe` for mister-all):

```bash
kloot  [DIR]           # auto mode (default): sandboxed autonomy, risky actions still asked
kloot  -s [DIR]        # safe mode: approval prompts on
kloot  -y [DIR]        # YOLO mode: all approvals skipped
kloot  -A [DIR]        # also forward the host SSH agent (1Password); off by default
kloot  --shell [DIR]   # drop into a zsh shell in the container
kloot  -h              # help

koodex [DIR]           # same flags
mister-all [DIR]       # same flags
```

Flags can be combined, e.g. `kloot -s -A .`. `DIR` defaults to `~/workspace` and
is mounted as `/workspace` (the container's working directory). Pass `.` (or a
path) to target another project.

### Permission modes

| Mode          | Flag         | kloot (Claude Code)                | koodex (Codex)                                             | mister-all (Vibe)          |
|---------------|--------------|------------------------------------|------------------------------------------------------------|----------------------------|
| Auto (default)| *(none)*     | `--permission-mode auto`           | `--sandbox workspace-write --ask-for-approval on-request`   | `--agent smart-approve`    |
| Safe          | `-s`         | `--permission-mode manual`         | `--sandbox read-only --ask-for-approval on-request`         | `--agent ask`              |
| YOLO          | `-y`         | `--dangerously-skip-permissions`   | `--dangerously-bypass-approvals-and-sandbox`                | `--agent auto-approve`     |

**Auto** is the default and the recommended mode. The agent works on its own
inside the workspace — it reads files, edits them, and runs commands — but it
does not get a blanket skip of every check:

- **kloot:** Claude Code auto mode classifies each tool call for risky actions
  and prompt injection. It runs the lower-risk calls and stops for the rest.
  The image ships `bubblewrap` and `socat` so the Linux sandbox works. If the
  runtime blocks user namespaces, Claude Code drops the sandbox and keeps the
  classifier. Auto mode also needs a plan that includes it; without one, use
  `-s` or `-y`.
- **koodex:** Codex runs in its `workspace-write` sandbox and asks before it
  writes outside the workspace or uses the network. The image ships
  `bubblewrap`; without it Codex warns on every start and falls back to its
  bundled copy.
- **mister-all:** Vibe's `smart-approve` agent sends each tool call to a model
  classifier. It runs the safe calls and asks for the risky calls. Vibe has no
  Linux sandbox, so the container is the only boundary.

The Claude Code and Codex sandboxes build on user namespaces, which Docker's
default seccomp profile blocks — `bwrap` then fails with *"No permissions to
create new namespace"* and every sandboxed command dies. The `kloot` and
`koodex` wrappers therefore pass `--security-opt seccomp=unconfined`. It drops
Docker's syscall filter, so the container leans on the kernel and on `--rm`
isolation alone; the agent still runs as an unprivileged user with no extra
capabilities. Drop that flag from the wrapper if you prefer the filter and can
live without the agent's own sandbox. `mister-all` does not pass the flag, so
it keeps the filter.

**Safe** (`-s`) turns the prompts back on for everything: Claude Code asks
before each action, Codex is limited to reading the workspace, and Vibe asks
before each tool call.

**YOLO** (`-y`) skips every approval and, for Codex, the internal sandbox too.
It is the old default. The container is what makes it tolerable: the agent runs
as the unprivileged `node` user in a throwaway (`--rm`) container and only sees
what is explicitly mounted — your workspace, `~/workspace`, `~/Github`, and the
agent's own config. It cannot reach the rest of your host.

Caveats worth keeping in mind in any mode:

- **Mounted dirs are writable.** The agent has full read/write to `/workspace`,
  `~/workspace`, and `~/Github`, so it can modify or delete real files in those
  paths. The `~/.gitconfig` mount is read-only; the others are not.
- **It can act with your identity.** Your `gh`/agent credentials are mounted, so
  the agent can open PRs or call APIs as you. SSH-agent forwarding (incl.
  1Password) is **off by default** — pass `-A`/`--ssh` to enable it, after which
  the agent can also `git push` over SSH as you.
- **Container ≠ full isolation.** It limits blast radius; it is not a security
  boundary against deliberately malicious code.

### MCP servers from the host config

`koodex` mounts your `~/.codex`, so the container inherits the MCP servers you
configured on macOS. Servers whose binary lives on the host cannot start there.
The ChatGPT desktop app writes one of these — `node_repl`, a Mach-O binary under
`/Applications/ChatGPT.app` — which made every session open with:

```
⚠ MCP client for `node_repl` failed to start: MCP startup failed: No such file or directory (os error 2)
⚠ MCP startup incomplete (failed: node_repl)
```

The wrapper now passes `-c mcp_servers.node_repl.enabled=false` for the run, so
the server is skipped in the container and your `~/.codex/config.toml` keeps it
for normal macOS use. Add further names to `host_only_mcp` in `koodex/koodex` if
other host-only servers turn up.

### Vibe in mister-all

**Model.** The wrapper sets the default model through Vibe's `VIBE_*`
environment variables, so `~/.vibe/config.toml` stays untouched. To start on
another model, set `VIBE_ACTIVE_MODEL` on the host. You can also switch models
in the session.

**API key.** On macOS, Vibe keeps the key in the Keychain, and the container
cannot read the Keychain. Export `MISTRAL_API_KEY` on the host, or let Vibe ask
on the first container run. Vibe then saves the key to `~/.vibe/.env`.

**Folder trust.** Vibe records trusted folders by path. Every project mounts at
`/workspace`, so when you trust `/workspace` once, Vibe trusts every project
that you open later. Do not trust `/workspace` persistently if you open
repositories that you do not control.

## What gets mounted

Common to every harness:

| Host                | Container                 | Notes                                   |
|---------------------|---------------------------|-----------------------------------------|
| `<workspace>`       | `/workspace`              | The target dir (defaults to `~/workspace`).|
| `~/workspace`       | `/home/node/workspace`    | Your workspace, if the dir exists.      |
| `~/Github`          | `/home/node/Github`       | All projects, if the dir exists.        |
| `~/Library/Application Support/CleanShot/media` | Same absolute host path | Read-only, if present; enables CleanShot drag-and-drop paths. |
| `~/.gitconfig`      | `/home/node/.gitconfig`   | Read-only, if present.                  |
| host SSH agent      | `/ssh-agent`              | Only with `-A`/`--ssh` (1Password / SSH keys).|
| `~/.orbstack/ssh/known_hosts` | `/home/node/.orbstack/ssh/known_hosts` | Read-only, only with `-A` and if present. |
| `<agent>-history`   | `/commandhistory`         | Named volume — persistent shell history.|

Harness-specific config/credentials:

| Harness  | Host             | Container                 | Notes                                        |
|----------|------------------|---------------------------|----------------------------------------------|
| `kloot`  | `~/.claude`      | `/home/node/.claude`      | Claude config & credentials.                 |
| `kloot`  | `~/.claude.json` | `/home/node/.claude.json` | If present.                                  |
| `koodex` | `~/.codex`       | `/home/node/.codex`       | Codex `config.toml` + `auth.json`.           |
| `mister-all` | `~/.vibe`    | `/home/node/.vibe`        | Vibe `config.toml`, sessions, `.env` API key.|

`koodex` also forwards `OPENAI_API_KEY` into the container if it is set in your
environment (an alternative to `codex login` writing to `~/.codex`).
`mister-all` does the same with `MISTRAL_API_KEY`.

### CleanShot drag and drop

On macOS, dragging a CleanShot capture into Ghostty inserts its absolute host
path, typically under
`~/Library/Application Support/CleanShot/media`. When that directory exists,
all wrappers mount it read-only at the same absolute path inside the container,
so Claude Code, Codex or Vibe can open the pasted path. The rest of the host home
directory remains unavailable unless covered by another documented mount.

The container is started with `--rm`, so it's torn down on exit; persistent
state lives entirely in the mounts above.

### SSH agent forwarding (opt-in)

SSH-agent / 1Password forwarding is **off by default** — enable it per-run with
`-A` (or `--ssh`). When enabled, the wrappers forward the host SSH agent into the
container so `git` over SSH and 1Password's SSH agent work without copying keys.
On macOS, Docker Desktop and OrbStack expose the agent inside their Linux VM at
`/run/host-services/ssh-auth.sock`; that path normally does not exist in the
macOS filesystem, so the wrappers deliberately pass it through without a host
socket check. On native Linux, the wrappers require `$SSH_AUTH_SOCK` to name an
existing Unix socket.

An `-A` run executes `ssh-add -l` inside the container before starting the agent
or `--shell`. The run fails immediately with a diagnostic if the forwarded
socket is unreachable or the agent exposes no identities. This catches a
stopped/disabled 1Password agent, an ineligible key set, and runtime socket
forwarding failures before the AI harness starts. Runs without `-A` receive no
SSH-agent mount and no `SSH_AUTH_SOCK` environment variable.

Forwarding does not move a private key into the container: 1Password retains the
private key and handles signing requests over the socket. However, every process
running as `node` in an `-A` container can ask the agent to sign, so enable it
only for workspaces you trust. The wrappers never mount `~/.ssh`, a 1Password
key file, or OrbStack's generated private key.

#### SSH to OrbStack machines

All images include a Linux-native `Host orb` configuration. It connects to
OrbStack's built-in SSH service at `host.docker.internal:32222`, uses
`HostKeyAlias 127.0.0.1`, and reads host keys from the read-only
`~/.orbstack/ssh/known_hosts` mount when that file exists on the Mac. It does not
copy OrbStack's generated macOS config: that file contains a macOS-only
`ProxyCommand` and forces OrbStack's generated private key, neither of which is
appropriate inside the container. The image config also deliberately leaves
`IdentitiesOnly` unset so OpenSSH can offer keys from the forwarded 1Password
agent.

Use the same multiplexed usernames that OrbStack documents:

```bash
kloot -A --shell             # or: koodex / mister-all -A --shell
ssh orb                      # default OrbStack machine
ssh machine@orb              # named machine, default user
ssh user@machine@orb         # named machine and user
ssh user@192.0.2.10          # ordinary SSH target
```

Before the first 1Password-backed connection, authorize the **public** half of
the chosen 1Password SSH Key item. Copy its complete public-key line from
1Password, substitute it below, and run this once on the Mac:

```bash
orb_public_key='ssh-ed25519 AAAAC3... selected-key-comment'
install -d -m 700 "$HOME/.orbstack/ssh"
touch "$HOME/.orbstack/ssh/authorized_keys"
chmod 600 "$HOME/.orbstack/ssh/authorized_keys"
grep -qxF -- "$orb_public_key" "$HOME/.orbstack/ssh/authorized_keys" || \
  printf '%s\n' "$orb_public_key" >> "$HOME/.orbstack/ssh/authorized_keys"
```

Quit and reopen OrbStack after updating the file so its built-in SSH server
reloads it. This adds one authorized public key; it neither replaces OrbStack's
generated key nor changes the 1Password item. On the first authentication,
1Password should show its normal local authorization prompt. Removing that line
from `authorized_keys` and restarting OrbStack should make these agent-backed
connections fail again.
