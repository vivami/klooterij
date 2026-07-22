# klooterij

*/ˌklʊətəˈrɛi̯/ — Antwerp Flemish for "a load of faffing (ballsing) about". A whole
`klooterij` of AI coding harnesses, each sealed in its own throwaway container so
you can let it rip.*

**klooterij** runs terminal AI coding agents ("harnesses") inside disposable,
isolated Docker containers, so you can safely run them in **YOLO-mode**: every
approval prompt skipped, the agent free to run commands, edit files, and hit the
network on its own.

Type a harness command in any project directory and you land in a throwaway
container with that agent already running against your code. On exit the
container is torn down; only your mounted files persist. Nothing else on your
host is ever reachable.

Every harness follows the same recipe: a `node:20` dev container with common CLI
tooling, your project mounted at `/workspace`, your credentials mounted in, and
the agent launched in its most autonomous mode.

Runs on any Docker-compatible runtime — e.g. [OrbStack](https://orbstack.dev) or
Docker Desktop on macOS.

## Harnesses

| Command  | Agent                                              | Folder     | Image           |
|----------|----------------------------------------------------|------------|-----------------|
| `kloot`  | [Claude Code](https://claude.com/claude-code)      | `kloot/`   | `kloot:latest`  |
| `koodex` | [OpenAI Codex CLI](https://github.com/openai/codex)| `koodex/`  | `koodex:latest` |

Each folder is **self-contained**: its own `Dockerfile`, wrapper script, and
`update_*.sh` rebuild script. Adding a new harness = copy a folder, swap the CLI
package, launch command, bypass flag, and config-dir mount.

- `kloot` — */klʊət/*, as in strong Antwerp's Flemish _"kloten met Claude"_
  (roughly: messing about with Claude).
- `koodex` — same spirit

Every image bundles: `git`, `gh`, `git-delta`, `ripgrep`, `fzf`, `jq`, `zsh`
(with oh-my-zsh), `python3`/`pip`, `build-essential`, plus that harness's agent
CLI. The container user is `node` with passwordless `sudo`.

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
kloot  [DIR]           # run the agent in bypass mode (default, autonomous)
kloot  -s [DIR]        # safe mode: approval prompts on
kloot  -A [DIR]        # also forward the host SSH agent (1Password); off by default
kloot  --shell [DIR]   # drop into a zsh shell in the container
kloot  -h              # help

koodex [DIR]           # same flags
```

Flags can be combined, e.g. `kloot -s -A .`. `DIR` defaults to `~/workspace` and
is mounted as `/workspace` (the container's working directory). Pass `.` (or a
path) to target another project.

### A note on YOLO-mode (skipping approvals)

By default the wrapper launches the agent in its most autonomous mode — no
approval prompts before it runs commands, edits files, or makes network
requests:

- **kloot:** `claude --dangerously-skip-permissions`
- **koodex:** `codex --dangerously-bypass-approvals-and-sandbox` (disables both
  Codex's approval gate **and** its internal sandbox — appropriate here because
  the container *is* the isolation boundary).

These flags are dangerous on a normal host because the agent can touch anything
your user account can. The whole point of klooterij is to make them *safe
enough*: the agent runs as the unprivileged `node` user in a throwaway (`--rm`)
container and only sees what's explicitly mounted — your workspace, `~/workspace`,
`~/Github`, and the agent's own config. It cannot reach the rest of your host.

Caveats worth keeping in mind even so:

- **Mounted dirs are writable.** The agent has full read/write to `/workspace`,
  `~/workspace`, and `~/Github`, so it can modify or delete real files in those
  paths. The `~/.gitconfig` mount is read-only; the others are not.
- **It can act with your identity.** Your `gh`/agent credentials are mounted, so
  the agent can open PRs or call APIs as you. SSH-agent forwarding (incl.
  1Password) is **off by default** — pass `-A`/`--ssh` to enable it, after which
  the agent can also `git push` over SSH as you.
- **Container ≠ full isolation.** It limits blast radius; it is not a security
  boundary against deliberately malicious code.

If you'd rather keep the approval prompts on, use safe mode (`-s`), which runs
the plain agent with permissions enabled.

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
