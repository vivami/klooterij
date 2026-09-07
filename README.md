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

Each folder is **self-contained**: its own `Dockerfile`, wrapper script, and
`update_*.sh` rebuild script. Adding a new harness = copy a folder, swap the CLI
package, launch command, permission flags, and config-dir mount.

- `kloot` — */klʊət/*, as in strong Antwerp's Flemish _"kloten met Claude"_
  (roughly: messing about with Claude).
- `koodex` — same spirit

Every image bundles: `git`, `gh`, `git-delta`, `ripgrep`, `fzf`, `jq`, `zsh`
(with oh-my-zsh), `python3`/`pip`, `build-essential`, plus that harness's agent
CLI. Both images also carry `bubblewrap` (plus `socat` in `kloot`) for the
agent's own Linux sandbox in auto mode. The container user is `node` with
passwordless `sudo`.

## Prerequisites

- macOS with a Docker-compatible runtime installed and running — e.g. [OrbStack](https://orbstack.dev) or [Docker Desktop](https://docs.docker.com/desktop/setup/install/mac-install/). It provides the `docker` CLI and forwards the host SSH agent.
- The `docker` CLI on your `PATH` (your runtime installs this for you).

## Build

Each harness builds from its own folder; the wrapper expects the image tagged
exactly as shown in the table above.

```bash
cd ~/Github/klooterij/kloot  && docker build -t kloot:latest  .
cd ~/Github/klooterij/koodex && docker build -t koodex:latest .
```

Optional build args (per harness):

- `TZ` — set the container timezone, e.g. `--build-arg TZ="Europe/Copenhagen"`.
- `CLAUDE_CODE_VERSION` (kloot) / `CODEX_VERSION` (koodex) — pin an agent version
  (default `latest`).

```bash
cd ~/Github/klooterij/koodex
docker build -t koodex:latest \
  --build-arg TZ="$(date +%Z)" \
  --build-arg CODEX_VERSION=latest .
```

On Apple Silicon the images build natively for `arm64` (git-delta auto-detects
the architecture), so no `--platform` flag is needed.

To rebuild against the latest agent release and prune the old image, run the
folder's update script, e.g. `./koodex/update_koodex.sh` or `./kloot/update_kloot.sh`.

## Put the commands on your `PATH`

Symlink each wrapper into a directory already on `PATH`. This keeps the scripts
in the repo (so `git pull` updates them) while making the commands global:

```bash
sudo ln -s ~/Github/klooterij/kloot/kloot   /usr/local/bin/kloot
sudo ln -s ~/Github/klooterij/koodex/koodex /usr/local/bin/koodex
```

Either command now works from any directory:

```bash
cd ~/Github/my-project
kloot                       # start Claude Code in this project
koodex                      # start Codex CLI in this project
```

## Usage

The two wrappers share the same interface (`AGENT` = `Claude` for kloot,
`Codex` for koodex):

```bash
kloot  [DIR]           # auto mode (default): sandboxed autonomy, risky actions still asked
kloot  -s [DIR]        # safe mode: approval prompts on
kloot  -y [DIR]        # YOLO mode: all approvals skipped
kloot  -A [DIR]        # also forward the host SSH agent (1Password); off by default
kloot  --shell [DIR]   # drop into a zsh shell in the container
kloot  -h              # help

koodex [DIR]           # same flags
```

Flags can be combined, e.g. `kloot -s -A .`. `DIR` defaults to `~/workspace` and
is mounted as `/workspace` (the container's working directory). Pass `.` (or a
path) to target another project.

### Permission modes

| Mode          | Flag         | kloot (Claude Code)                | koodex (Codex)                                             |
|---------------|--------------|------------------------------------|------------------------------------------------------------|
| Auto (default)| *(none)*     | `--permission-mode auto`           | `--sandbox workspace-write --ask-for-approval on-request`   |
| Safe          | `-s`         | `--permission-mode manual`         | `--sandbox read-only --ask-for-approval on-request`         |
| YOLO          | `-y`         | `--dangerously-skip-permissions`   | `--dangerously-bypass-approvals-and-sandbox`                |

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

Both sandboxes build on user namespaces, which Docker's default seccomp profile
blocks — `bwrap` then fails with *"No permissions to create new namespace"* and
every sandboxed command dies. The wrappers therefore pass
`--security-opt seccomp=unconfined`. It drops Docker's syscall filter, so the
container leans on the kernel and on `--rm` isolation alone; the agent still runs
as an unprivileged user with no extra capabilities. Drop that flag from the
wrapper if you prefer the filter and can live without the agent's own sandbox.

**Safe** (`-s`) turns the prompts back on for everything: Claude Code asks
before each action, Codex is limited to reading the workspace.

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

## What gets mounted

Common to every harness:

| Host                | Container                 | Notes                                   |
|---------------------|---------------------------|-----------------------------------------|
| `<workspace>`       | `/workspace`              | The target dir (defaults to `~/workspace`).|
| `~/workspace`       | `/home/node/workspace`    | Your workspace, if the dir exists.      |
| `~/Github`          | `/home/node/Github`       | All projects, if the dir exists.        |
| `~/.gitconfig`      | `/home/node/.gitconfig`   | Read-only, if present.                  |
| host SSH agent      | `/ssh-agent`              | Only with `-A`/`--ssh` (1Password / SSH keys).|
| `<agent>-history`   | `/commandhistory`         | Named volume — persistent shell history.|

Harness-specific config/credentials:

| Harness  | Host             | Container                 | Notes                                        |
|----------|------------------|---------------------------|----------------------------------------------|
| `kloot`  | `~/.claude`      | `/home/node/.claude`      | Claude config & credentials.                 |
| `kloot`  | `~/.claude.json` | `/home/node/.claude.json` | If present.                                  |
| `koodex` | `~/.codex`       | `/home/node/.codex`       | Codex `config.toml` + `auth.json`.           |

`koodex` also forwards `OPENAI_API_KEY` into the container if it is set in your
environment (an alternative to `codex login` writing to `~/.codex`).

The container is started with `--rm`, so it's torn down on exit; persistent
state lives entirely in the mounts above.

### SSH agent forwarding (opt-in)

SSH-agent / 1Password forwarding is **off by default** — enable it per-run with
`-A` (or `--ssh`). When enabled, the wrappers forward the host SSH agent into the
container so `git` over SSH and 1Password's SSH agent work without copying keys.
On macOS, Docker Desktop and OrbStack both expose it at
`/run/host-services/ssh-auth.sock`; the wrappers use that, falling back to
`$SSH_AUTH_SOCK` otherwise. If `-A` is given but no agent socket is found,
forwarding is skipped with a warning and everything else still works.
