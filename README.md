# Claude Code Docker Container

An extensible Docker setup for running Claude Code safely in an isolated container environment. Based on [Anthropic's official devcontainer configuration](https://github.com/anthropics/claude-code/tree/main/.devcontainer).

## Why Run Claude Code in Docker?

Running Claude Code in a container provides several benefits:

1. **Safety with `--dangerously-skip-permissions`**: The container isolates Claude's actions from your host system
2. **Reproducible environment**: Same setup across different machines
3. **Network isolation**: Optional firewall restricts outbound connections to approved domains only
4. **Clean host system**: No global npm packages or dependencies on your machine
5. **Seamless integration**: Uses your existing Claude configuration and SSH keys from the host

## Quick Start

### Option 1: Run From Anywhere (Recommended)

The container automatically mounts your current directory and uses your host's Claude configuration and SSH keys:

```bash
# Set your API key (or use existing ~/.claude config)
export ANTHROPIC_API_KEY="your-key-here"

# Build the image (one-time setup)
docker compose -f ~/git/claude-container/docker-compose.yml build

# Run Claude Code from any project directory
cd /path/to/your/project
docker compose -f ~/git/claude-container/docker-compose.yml run claude claude --dangerously-skip-permissions
```

For convenience, drop a shell function like this in your `~/.bashrc` /
`~/.bash_profile`. It sets `PROJECT_ROOT` / `WORK_DIR` for the compose file's
bind mounts, supports a `--host-port` flag (exposed inside the container as
`$HOST_PORT` via `host.docker.internal`), and a `--root` flag for mounting a
parent directory while starting Claude in a subdirectory:

```bash
function sclaude {
    local host_port_args=()
    local claude_args=()
    local project_root=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host-port)
                host_port_args=(-e "HOST_PORT=$2")
                shift 2
                ;;
            --root)
                project_root=$(realpath "$2")
                shift 2
                ;;
            *)
                claude_args+=("$1")
                shift
                ;;
        esac
    done

    local mount_root="${project_root:-$PWD}"

    if [[ "$PWD" != "$mount_root" && "$PWD" != "$mount_root"/* ]]; then
        echo "Error: current directory ($PWD) is not under --root ($mount_root)"
        return 1
    fi

    PROJECT_ROOT="$mount_root" WORK_DIR="$PWD" \
        docker compose -f ~/git/claude-container/docker-compose.yml run \
        --remove-orphans --rm \
        "${host_port_args[@]}" \
        claude claude --dangerously-skip-permissions "${claude_args[@]}"
}
```

Usage:

```bash
cd ~/git/myproject
sclaude                                       # mounts $PWD, starts claude there
sclaude --host-port 3000                      # exposes a host dev server as $HOST_PORT
cd ~/git/myproject/subdir
sclaude --root ~/git/myproject                # mounts the repo root, starts claude in subdir
```

### Option 2: Interactive Container Session

```bash
cd your-project

# Start the container in background
docker compose -f ~/git/claude-container/docker-compose.yml up -d

# Enter the container
docker compose -f ~/git/claude-container/docker-compose.yml exec claude bash

# Run Claude Code inside the container
claude --dangerously-skip-permissions
```

### Option 3: Direct Docker Build

```bash
# Build the image
docker build -t claude-code .

# Run interactively (replaces $USER with the host username baked into the image)
docker run -it \
  -v $(pwd):$(pwd) \
  -w $(pwd) \
  -v ${HOME}/.claude:/home/$USER/.claude \
  -v ${HOME}/.ssh:/home/$USER/.ssh:ro \
  -e ANTHROPIC_API_KEY="your-key" \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  claude-code

# Inside the container
claude --dangerously-skip-permissions
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Your Anthropic API key | (required unless using ~/.claude) |
| `GITHUB_TOKEN` | GitHub token for `gh` CLI | (optional) |
| `TZ` | Timezone | `UTC` |
| `CONTAINER_USER` | Username inside the container | host `$USER` |
| `HOST_UID` | UID inside the container | `1000` |
| `HOST_GID` | GID inside the container | `1000` |

To fully mirror the host user (recommended when your host UID/GID is not 1000, so
that bind-mounted files have correct ownership inside the container):

```bash
export HOST_UID=$(id -u) HOST_GID=$(id -g)
docker compose -f ~/git/claude-container/docker-compose.yml build
```

Or place them in a `.env` file next to `docker-compose.yml`.

### Build Arguments

Customize the build with:
```bash
docker compose -f ~/git/claude-container/docker-compose.yml build \
  --build-arg PYTHON_VERSION=3.11 \
  --build-arg GO_VERSION=1.23.5 \
  --build-arg USERNAME=youruser
```

Or with direct docker build:
```bash
docker build \
  --build-arg PYTHON_VERSION=3.11 \
  --build-arg GO_VERSION=1.23.5 \
  --build-arg USERNAME=youruser \
  --build-arg RUST_VERSION=nightly \
  -t claude-code .
```

## Network Firewall

The container includes an optional network firewall that restricts outbound connections to approved domains only. This provides an extra layer of security when running with `--dangerously-skip-permissions`.

### Enable Firewall

```bash
# Inside the container
sudo /usr/local/bin/init-firewall.sh
```

### Allowed Domains (Default)

- `api.anthropic.com` - Claude API
- `github.com`, `api.github.com` - Git operations
- `registry.npmjs.org` - npm packages
- `pypi.org` - Python packages
- `proxy.golang.org` - Go packages
- `crates.io` - Rust packages

### Customize Allowed Domains

Edit `init-firewall.sh` and modify the `ALLOWED_DOMAINS` array:

```bash
ALLOWED_DOMAINS=(
    "api.anthropic.com"
    "your-custom-domain.com"
    # Add more as needed
)
```

### Disable Firewall

```bash
sudo iptables -F OUTPUT
```

## Extending the Container

### Add System Packages

Add to the Dockerfile before `USER $USERNAME`:
```dockerfile
RUN apt-get update && apt-get install -y \
    your-package-here \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
```

### Add Python Packages

```dockerfile
RUN pip install --break-system-packages \
    your-package-here
```

### Add npm Packages

```dockerfile
RUN npm install -g your-package-here
```

### Volume Mounts (Default)

The docker-compose.yml automatically mounts:

| Host Path | Container Path | Mode |
|-----------|----------------|------|
| `${PWD}` | `${PWD}` | read-write |
| `${HOME}/.claude` | `/home/${CONTAINER_USER}/.claude` | read-write |
| `${HOME}/.ssh` | `/home/${CONTAINER_USER}/.ssh` | read-only |
| `${HOME}/.gitconfig` | `/home/${CONTAINER_USER}/.gitconfig` | read-only |

### Mount Additional Volumes

Add custom mounts in `docker-compose.yml`:
```yaml
volumes:
  - /path/to/data:/data
  - ${HOME}/.aws:/home/${CONTAINER_USER}/.aws:ro
```

## Included Tools

### Languages & Runtimes
- **Node.js 20** (with npm)
- **Python 3** (with pip, uv, poetry)
- **Go 1.23.5** (full version only)
- **Rust stable** (full version only)

### Development Tools
- **Git** with GitHub CLI (`gh`)
- **ripgrep** (`rg`) - fast search
- **fd** (`fd-find`) - fast file finder
- **fzf** - fuzzy finder
- **jq** - JSON processor
- **bat** - syntax-highlighted cat
- **htop** - process viewer
- **vim**, **nano**, **emacs** - editors

### Python Tools
- `uv` - fast package installer
- `poetry` - dependency management
- `black` - code formatter
- `ruff` - linter
- `pytest` - testing
- `mypy` - type checking
- `pyright` - type checker

## Troubleshooting

### "Permission denied" errors
The container runs as `$CONTAINER_USER` (defaults to the host `$USER`) with UID/GID
`$HOST_UID`/`$HOST_GID` (both default to `1000`). If your host UID/GID isn't 1000,
rebuild the image with matching values so bind-mounted files are writable:
```bash
export HOST_UID=$(id -u) HOST_GID=$(id -g)
docker compose -f ~/git/claude-container/docker-compose.yml build
```

### Firewall blocking needed domains
Add the domain to `init-firewall.sh` and re-run:
```bash
sudo /usr/local/bin/init-firewall.sh
```

### Claude Code not finding API key
Ensure the environment variable is set:
```bash
echo $ANTHROPIC_API_KEY
# Or login interactively
claude /login
```

## Security Considerations

1. **API Keys**: Never commit API keys to version control. Use environment variables or secrets management.

2. **Firewall**: The network firewall provides defense-in-depth but is not foolproof. Malicious code could potentially bypass it.

3. **Volume Mounts**: Be careful what you mount into the container. Avoid mounting sensitive directories like `~/.ssh` unless necessary.

4. **`--dangerously-skip-permissions`**: Only use this flag inside containers where Claude's actions are isolated from your host system.

## License

This configuration is based on Anthropic's official devcontainer setup. See the [Claude Code repository](https://github.com/anthropics/claude-code) for license information.
