ARG UV_VERSION=latest
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM node:20

ARG TZ
ENV TZ="$TZ"
ARG VIBE_VERSION=latest

RUN apt-get update && apt-get install -y --no-install-recommends \
        less git procps sudo fzf zsh man-db unzip gnupg2 gh jq nano vim wget \
        ripgrep openssh-client build-essential \
        python3 python3-pip python3-venv \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/local/share/npm-global && chown -R node:node /usr/local/share

ARG USERNAME=node

RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    && mkdir /commandhistory \
    && touch /commandhistory/.bash_history \
    && chown -R $USERNAME /commandhistory

ENV DEVCONTAINER=true

RUN mkdir -p /workspace /home/node/.vibe /home/node/.orbstack/ssh \
    && chown -R node:node /workspace /home/node/.vibe /home/node/.orbstack
COPY ssh_config_orbstack /etc/ssh/ssh_config.d/20-orbstack.conf
WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) \
    && wget -q "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
    && dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
    && rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

RUN echo "node ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node

COPY --from=uv /uv /uvx /usr/local/bin/

USER node

ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin:/home/node/.local/bin
ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano

# Force HTTP/1.1 for git and disable interactive prompts. This avoids the
# transient "expected flush after ref listing" / "could not read Username"
# failure when the oh-my-zsh installer clones over GitHub's HTTP/2 endpoint.
ENV GIT_TERMINAL_PROMPT=0
RUN git config --global http.version HTTP/1.1

ARG ZSH_IN_DOCKER_VERSION=1.2.1
RUN for attempt in 1 2 3 4 5; do \
        sh -c "$(wget -qO- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
            -p git \
            -p fzf \
            -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
            -a "source /usr/share/doc/fzf/examples/completion.zsh" \
            -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
            -x && exit 0; \
        echo "zsh-in-docker: attempt $attempt failed (GitHub rate limit?); retrying"; \
        rm -rf "$HOME/.oh-my-zsh"; \
        sleep $((attempt * 20)); \
    done; \
    echo "zsh-in-docker: failed after 5 attempts" >&2; \
    exit 1

# Mistral Vibe needs Python >= 3.12; node:20 (Debian bookworm) ships 3.11.
# Without --python 3.12, uv picks the system 3.11, skips the prebuilt wheel and
# tries to build Vibe from source, which fails without a Rust toolchain.
RUN if [ "$VIBE_VERSION" = latest ]; then spec=mistral-vibe; \
    else spec="mistral-vibe==${VIBE_VERSION}"; fi \
    && uv tool install --python 3.12 "$spec" \
    && uv cache clean

CMD ["vibe"]
