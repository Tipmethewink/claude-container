#!/bin/bash
# =============================================================================
# Entrypoint script for Claude Code container
# Installs/updates Claude Code from a persistent volume on each run
# =============================================================================

CLAUDE_BIN="${HOME}/.local/bin/claude"

# Install Claude Code if not already present in the volume
if [ ! -x "$CLAUDE_BIN" ]; then
    echo "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
else
    echo "Claude Code already installed: $($CLAUDE_BIN --version 2>/dev/null || echo 'unknown version')"
fi

# Execute the provided command, or default to bash
exec "${@:-/bin/bash}"
