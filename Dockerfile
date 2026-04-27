# =============================================================================
# Claude Code Docker Container - Extensible Version
# Based on Anthropic's official devcontainer setup
# https://github.com/anthropics/claude-code/tree/main/.devcontainer
# =============================================================================

FROM node:20-bookworm

# Build arguments for customization
ARG TZ=UTC
ARG PYTHON_VERSION=3.13
ARG GO_VERSION=1.23.5
ARG RUST_VERSION=stable

# Set timezone
ENV TZ="${TZ}"

# =============================================================================
# Base System Packages
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Essential tools
    less \
    git \
    procps \
    sudo \
    curl \
    wget \
    ca-certificates \
    gnupg2 \
    # Shell and terminal
    fzf \
    man-db \
    # Firewall tools (for network isolation)
    iptables \
    ipset \
    iproute2 \
    dnsutils \
    aggregate \
    # Text processing and editors
    jq \
    nano \
    vim \
    ripgrep \
    fd-find \
    tree \
    bat \
    htop \
    unzip \
    zip \
    # Build essentials
    build-essential \
    pkg-config \
    libssl-dev \
    libffi-dev \
    # Python dependencies
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    # GitHub CLI
    gh \
    # Other stuff
    asciinema \
    libnotify-bin \
    emacs \
    # YubiKey support
    pcscd \
    libpcsclite1 \
    libccid \
    scdaemon \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Google Chrome (for Playwright MCP server)
# =============================================================================
RUN curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o /tmp/chrome.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends /tmp/chrome.deb && \
    rm /tmp/chrome.deb && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Wrap Chrome binary to add --no-sandbox (required in Docker where
# unprivileged user namespaces are restricted). Playwright MCP launches
# /opt/google/chrome/chrome directly, so this wrapper is transparent.
RUN mv /opt/google/chrome/chrome /opt/google/chrome/chrome.real && \
    printf '#!/bin/bash\nexec /opt/google/chrome/chrome.real --no-sandbox "$@"\n' \
      > /opt/google/chrome/chrome && \
    chmod +x /opt/google/chrome/chrome

# =============================================================================
# Go Setup (optional - comment out if not needed)
# =============================================================================
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-$(dpkg --print-architecture).tar.gz" -o /tmp/go.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz

ENV PATH="/usr/local/go/bin:$PATH"

# =============================================================================
# Rust Setup (optional - comment out if not needed)
# =============================================================================
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
ENV PATH="/usr/local/cargo/bin:$PATH"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --default-toolchain ${RUST_VERSION} && \
    chmod -R a+w ${RUSTUP_HOME} ${CARGO_HOME}

# =============================================================================
# Node.js Global Setup
# =============================================================================
# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
    chown -R node:node /usr/local/share

# =============================================================================
# Python Setup (with uv for fast package management)
# =============================================================================
# Install uv (fast Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# Create symlinks for convenience
RUN ln -sf /usr/bin/python3 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

# Install common Python tools globally
RUN pip install --break-system-packages \
    pipx \
    poetry \
    black \
    ruff \
    mypy \
    pytest \
    httpx \
    rich \
    pyright

# =============================================================================
# User Configuration
# =============================================================================
ARG USERNAME=mark
ARG USER_UID=1000
ARG USER_GID=1000

# Define user home directory
ENV USER_HOME=/home/${USERNAME}

# Set Go path now that we know the username
ENV GOPATH="${USER_HOME}/go"
ENV PATH="${GOPATH}/bin:$PATH"

# Rename the base image's "node" user (UID/GID 1000) to ${USERNAME}, then
# renumber to ${USER_UID}/${USER_GID} if they differ. usermod -u re-owns
# files in the user's home dir automatically.
RUN usermod -l ${USERNAME} node && \
    groupmod -n ${USERNAME} node && \
    usermod -d /home/${USERNAME} -m ${USERNAME} && \
    if [ "${USER_GID}" != "1000" ]; then groupmod -g ${USER_GID} ${USERNAME}; fi && \
    if [ "${USER_UID}" != "1000" ]; then usermod -u ${USER_UID} ${USERNAME}; fi && \
    sed -i "s|/home/node|/home/${USERNAME}|g" /etc/passwd

# Persist bash history
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    && mkdir -p /commandhistory \
    && touch /commandhistory/.bash_history \
    && chown -R $USERNAME:$USERNAME /commandhistory

# =============================================================================
# glab Setup (optional - comment out if not needed) - requires GOPATH
# =============================================================================
RUN git clone https://gitlab.com/gitlab-org/cli.git && \
    make -C cli build && \
    make -C cli install

# =============================================================================
# Environment Variables
# =============================================================================
ENV PATH="${USER_HOME}/.local/bin:$PATH"
ENV DEVCONTAINER=true
ENV SHELL=/bin/bash

# Node memory configuration
ENV NODE_OPTIONS="--max-old-space-size=4096"

# Claude configuration
ENV CLAUDE_CONFIG_DIR="${USER_HOME}/.claude"
ENV ENABLE_LSP_TOOLS=1

# =============================================================================
# Firewall Script (for network isolation)
# =============================================================================
COPY init-firewall.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh && \
    echo "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/${USERNAME}-firewall && \
    chmod 0440 /etc/sudoers.d/${USERNAME}-firewall

# =============================================================================
# Workspace Setup
# =============================================================================
RUN mkdir -p ${USER_HOME}/.claude && chown -R $USERNAME:$USERNAME ${USER_HOME}/.claude
RUN mkdir -p ${USER_HOME}/go && chown -R $USERNAME:$USERNAME ${USER_HOME}/go
RUN mkdir -p ${USER_HOME}/.local/{bin,share/claude,state} && chown -R $USERNAME:$USERNAME ${USER_HOME}/.local

# Disable Ctrl+Z (SIGTSTP) inside the container - it just suspends the
# foreground process with nowhere useful to go. Use Docker's detach keys
# (Ctrl+P, Ctrl+Q) or a terminal multiplexer to background instead.
RUN echo "trap '' TSTP" >> ${USER_HOME}/.bashrc

# Give user sudo access (optional - remove for tighter security)
# RUN echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# =============================================================================
# Entrypoint - installs/updates Claude Code from persistent volume on startup
# =============================================================================
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER $USERNAME

SHELL ["/bin/bash", "-c"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Default command - start interactive shell
CMD ["/bin/bash"]
