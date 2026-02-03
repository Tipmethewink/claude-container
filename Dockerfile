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
    && apt-get clean && rm -rf /var/lib/apt/lists/*

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

# Create user (the base image has "node" with UID 1000, so we rename it)
RUN usermod -l ${USERNAME} node && \
    groupmod -n ${USERNAME} node && \
    usermod -d /home/${USERNAME} -m ${USERNAME} && \
    sed -i "s|/home/node|/home/${USERNAME}|g" /etc/passwd

# Persist bash history
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    && mkdir -p /commandhistory \
    && touch /commandhistory/.bash_history \
    && chown -R $USERNAME:$USERNAME /commandhistory

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

# Give user sudo access (optional - remove for tighter security)
# RUN echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER $USERNAME

# =============================================================================
# Install Claude Code (using native installer, as user)
# =============================================================================
RUN curl -fsSL https://claude.ai/install.sh | bash

SHELL ["/bin/bash", "-c"]

# Default command - start interactive shell
CMD ["/bin/bash"]
