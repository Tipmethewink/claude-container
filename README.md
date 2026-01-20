# Claude Code Docker Container

An extensible Docker setup for running Claude Code safely in an isolated container environment. Based on [Anthropic's official devcontainer configuration](https://github.com/anthropics/claude-code/tree/main/.devcontainer).

## Why Run Claude Code in Docker?

Running Claude Code in a container provides several benefits:

1. **Safety with `--dangerously-skip-permissions`**: The container isolates Claude's actions from your host system
2. **Reproducible environment**: Same setup across different machines
3. **Network isolation**: Optional firewall restricts outbound connections to approved domains only
4. **Clean host system**: No global npm packages or dependencies on your machine

## Quick Start

### Option 1: Docker Compose (Recommended)

```bash
# Clone or copy these files to your project
cd your-project

# Set your API key
export ANTHROPIC_API_KEY="your-key-here"

# Start the container
docker compose up -d

# Enter the container
docker compose exec claude zsh

# Run Claude Code with skipped permissions (safe inside container)
claude --dangerously-skip-permissions
```

### Option 2: Direct Docker Build

```bash
# Build the image
docker build -t claude-code .

# Run interactively
docker run -it \
  -v $(pwd):/workspace \
  -v claude-config:/home/node/.claude \
  -e ANTHROPIC_API_KEY="your-key" \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  claude-code

# Inside the container
claude --dangerously-skip-permissions
```

## Available Dockerfiles

| File | Description | Size |
|------|-------------|------|
| `Dockerfile` | Full version with Python, Go, Rust | ~2.5GB |
| `Dockerfile.slim` | Lightweight Python-only version | ~1.2GB |

To use the slim version:
```bash
docker build -f Dockerfile.slim -t claude-code-slim .
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Your Anthropic API key | (required) |
| `GITHUB_TOKEN` | GitHub token for `gh` CLI | (optional) |
| `TZ` | Timezone | `UTC` |
| `CLAUDE_CODE_VERSION` | Claude Code version to install | `latest` |

### Build Arguments

Customize the build with:
```bash
docker build \
  --build-arg PYTHON_VERSION=3.11 \
  --build-arg GO_VERSION=1.21 \
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

### Mount Additional Volumes

In `docker-compose.yml`:
```yaml
volumes:
  - ${HOME}/.ssh:/home/node/.ssh:ro
  - ${HOME}/.gitconfig:/home/node/.gitconfig:ro
  - /path/to/data:/data
```

## Included Tools

### Languages & Runtimes
- **Node.js 20** (with npm)
- **Python 3.13** (with pip, uv, poetry)
- **Go 1.22** (full version only)
- **Rust stable** (full version only)

### Development Tools
- **Git** with GitHub CLI (`gh`)
- **ripgrep** (`rg`) - fast search
- **fzf** - fuzzy finder
- **jq** - JSON processor
- **zsh** with oh-my-zsh

### Python Tools
- `uv` - fast package installer
- `poetry` - dependency management
- `black` - code formatter
- `ruff` - linter
- `pytest` - testing
- `mypy` - type checking

## Troubleshooting

### "Permission denied" errors
Ensure you're running as the `node` user or have proper permissions:
```bash
sudo chown -R node:node /workspace
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
