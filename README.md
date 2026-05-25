# kloot

*/klʊət/*, as in strong Antwerp's Flemish _"kloten met Claude"_.

Run [Claude Code](https://claude.com/claude-code) inside an isolated Docker container on macOS, using [OrbStack](https://orbstack.dev) as the container runtime. Your code is mounted into the container, but Claude runs sandboxed away from the rest of your host, which makes
`--dangerously-skip-permissions` a reasonable default.

Type `kloot` in any project directory and you land in a throwaway dev container with Claude Code already running against that directory.

## What's in here

| File         | Purpose                                                                 |
|--------------|-------------------------------------------------------------------------|
| `Dockerfile` | A `node:20`-based dev container with Claude Code + common CLI tooling.   |
| `kloot`      | A bash wrapper that builds the `docker run` invocation and mounts.       |

The image bundles: `git`, `gh`, `git-delta`, `ripgrep`, `fzf`, `jq`, `zsh`
(with oh-my-zsh), `python3`/`pip`, `build-essential`, plus the
`@anthropic-ai/claude-code` CLI. The container user is `node` with passwordless
`sudo`.

## Prerequisites

- macOS with [OrbStack](https://orbstack.dev) or [Docker](https://docs.docker.com/desktop/setup/install/mac-install/) installed and running (provides the `docker` CLI and forwards the host SSH agent).
- The `docker` CLI on your `PATH` (OrbStack installs this for you).

## Build

```bash
cd ~/kloot
docker build -t kloot:latest .
```

The wrapper expects the image to be tagged exactly `kloot:latest`.

Optional build args:

- `TZ` — set the container timezone, e.g.
  `--build-arg TZ="Europe/Copenhagen"`.
- `CLAUDE_CODE_VERSION` — pin a Claude Code version (default `latest`), e.g.
  `--build-arg CLAUDE_CODE_VERSION=1.2.3`.

```bash
docker build -t kloot:latest \
  --build-arg TZ="$(date +%Z)" \
  --build-arg CLAUDE_CODE_VERSION=latest .
```

On Apple Silicon the image builds natively for `arm64` (git-delta auto-detects
the architecture), so no `--platform` flag is needed.

## Call `kloot` from anywhere

First make the wrapper executable:

```bash
chmod +x /path/to/kloot
```

Then put it on your `PATH`. The cleanest option is a symlink into a directory
that's already on `PATH` — this keeps the script in this repo (so `git pull`
updates it) while making the command global:

```bash
sudo ln -s ~/path/to/kloot /usr/local/bin/kloot
```

Alternatively, add this repo to your `PATH` in `~/.zshrc`:

```bash
echo 'export PATH="$HOME/kloot:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

Either way, `kloot` now works from any directory:

```bash
cd ~/Github/my-project
kloot                       # start Claude in this project
```

## Usage

```bash
kloot [DIR]            # run Claude with --dangerously-skip-permissions (default)
kloot -s [DIR]         # run Claude with permission prompts on (safe mode)
kloot --shell [DIR]    # drop into a zsh shell in the container
kloot -h               # help
```

`DIR` defaults to the current directory and is mounted as `/workspace`
(the container's working directory).

### A note on `--dangerously-skip-permissions`

By default (bypass mode), the wrapper launches Claude with
`claude --dangerously-skip-permissions`. This flag tells Claude Code **not** to
prompt for approval before running commands, editing files, or making network
requests — it acts autonomously.

That flag is dangerous on a normal host because Claude can touch anything your
user account can. The whole point of kloot is to make it *safe enough* to
use: Claude runs as the unprivileged `node` user inside a throwaway
(`--rm`) container, and only sees what's explicitly mounted in — your
workspace, `~/workspace`, `~/Github`, and your Claude/git config. It cannot
reach the rest of your Mac.

Caveats worth keeping in mind even so:

- **Mounted dirs are writable.** Claude has full read/write to `/workspace`,
  `~/workspace`, and `~/Github` (mounted read-write), so it can modify or delete
  real files in those paths. The `~/.gitconfig` mount is read-only; the others
  are not.
- **It can push and act with your identity.** Your SSH agent (incl.
  1Password) and `gh`/Claude credentials are forwarded, so Claude can `git
  push`, open PRs, or call APIs as you.
- **Container ≠ full isolation.** It limits blast radius; it is not a security
  boundary against deliberately malicious code.

If you'd rather keep the approval prompts on, use safe mode — it runs plain
`claude` with permissions enabled:

```bash
kloot -s [DIR]         # permission prompts on
```

## What gets mounted

| Host                | Container                 | Notes                                  |
|---------------------|---------------------------|----------------------------------------|
| `<workspace>`       | `/workspace`              | The target dir (defaults to `$PWD`).   |
| `~/workspace`       | `/home/node/workspace`    | Your workspace, if the dir exists.     |
| `~/Github`          | `/home/node/Github`       | All projects, if the dir exists.       |
| `~/.claude`         | `/home/node/.claude`      | Claude config & credentials.           |
| `~/.claude.json`    | `/home/node/.claude.json` | If present.                            |
| `~/.gitconfig`      | `/home/node/.gitconfig`   | Read-only, if present.                 |
| host SSH agent      | `/ssh-agent`              | 1Password / SSH keys via OrbStack.     |
| `kloot-history`     | `/commandhistory`         | Named volume — persistent shell history.|

The container is started with `--rm`, so it's torn down on exit; persistent
state lives entirely in the mounts above.

### SSH agent forwarding

OrbStack exposes the host SSH agent at `/run/host-services/ssh-auth.sock`. The
wrapper forwards it into the container so `git` over SSH and 1Password's SSH
agent work without copying keys. If no agent socket is found, SSH forwarding is
disabled with a warning and everything else still works.
