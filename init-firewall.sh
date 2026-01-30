#!/bin/bash
# =============================================================================
# Firewall Initialization Script for Claude Code Container
# Based on Anthropic's official devcontainer setup
# This script restricts outbound connections to approved domains only
# =============================================================================

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# Allowed Domains
# Add or remove domains as needed for your workflow
# =============================================================================
ALLOWED_DOMAINS=(
    # Anthropic API
    "api.anthropic.com"
    "console.anthropic.com"
    "statsig.anthropic.com"
    
    # GitLab
    "gitlab.com"
    "api.gitlab.com"
    
    # npm registry
    "registry.npmjs.org"
    "npmjs.org"
    
    # PyPI (Python packages)
    "pypi.org"
    "files.pythonhosted.org"
    "pypi.python.org"
    
    # Go packages
    "proxy.golang.org"
    "sum.golang.org"
    
    # Rust packages
    "crates.io"
    "static.crates.io"
    
    # Common development services (add as needed)
    # "docker.io"
    # "ghcr.io"
    # "quay.io"
    "docs.anthropic.com"
    "code.claude.com"
)

# =============================================================================
# Check if running as root
# =============================================================================
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# =============================================================================
# Initialize ipset for efficient IP management
# =============================================================================
log_info "Creating ipset for allowed IPs..."

# Remove existing set if it exists
ipset destroy allowed_ips 2>/dev/null || true

# Create new set
ipset create allowed_ips hash:net

# =============================================================================
# Resolve domains and add to ipset
# =============================================================================
log_info "Resolving allowed domains..."

for domain in "${ALLOWED_DOMAINS[@]}"; do
    # Skip wildcard domains (handle separately if needed)
    if [[ $domain == \** ]]; then
        log_warn "Skipping wildcard domain: $domain"
        continue
    fi
    
    # Resolve domain to IPs
    ips=$(dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
    
    if [[ -n "$ips" ]]; then
        while IFS= read -r ip; do
            if [[ -n "$ip" ]]; then
                ipset add allowed_ips "$ip" 2>/dev/null || true
                log_info "  Added $ip ($domain)"
            fi
        done <<< "$ips"
    else
        log_warn "  Could not resolve: $domain"
    fi
done

# =============================================================================
# Add special network ranges
# =============================================================================
log_info "Adding special network ranges..."

# Docker internal DNS
ipset add allowed_ips 127.0.0.11 2>/dev/null || true

# Localhost
ipset add allowed_ips 127.0.0.0/8 2>/dev/null || true

# Docker bridge network (common range)
ipset add allowed_ips 172.17.0.0/16 2>/dev/null || true

# Docker compose networks (common range)
ipset add allowed_ips 172.18.0.0/16 2>/dev/null || true
ipset add allowed_ips 172.19.0.0/16 2>/dev/null || true

# =============================================================================
# Configure iptables rules
# =============================================================================
log_info "Configuring iptables rules..."

# Flush existing rules
iptables -F OUTPUT 2>/dev/null || true

# Allow established connections
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow loopback
iptables -A OUTPUT -o lo -j ACCEPT

# Allow DNS (UDP and TCP on port 53)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allow SSH (for git operations)
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT

# Allow connections to IPs in our allowed set
iptables -A OUTPUT -m set --match-set allowed_ips dst -j ACCEPT

# Log and drop everything else (comment out LOG for less verbose output)
# iptables -A OUTPUT -j LOG --log-prefix "BLOCKED: " --log-level 4
iptables -A OUTPUT -j DROP

# =============================================================================
# Verify firewall is active
# =============================================================================
log_info "Verifying firewall configuration..."

# Test that we can reach an allowed domain
if curl -s --connect-timeout 5 "https://api.anthropic.com" > /dev/null 2>&1; then
    log_info "✓ Allowed domain (api.anthropic.com) is reachable"
else
    log_warn "⚠ Could not reach api.anthropic.com - this may be expected if no network"
fi

# Test that we cannot reach a blocked domain
if curl -s --connect-timeout 3 "https://example.com" > /dev/null 2>&1; then
    log_error "✗ Blocked domain (example.com) is still reachable - firewall may not be working"
else
    log_info "✓ Blocked domain (example.com) is correctly blocked"
fi

log_info "Firewall initialization complete!"
echo ""
echo "=== Firewall Status ==="
echo "Allowed domains: ${#ALLOWED_DOMAINS[@]}"
echo "IPs in allowlist: $(ipset list allowed_ips | grep -c 'Members' || echo 'unknown')"
echo ""
echo "To disable the firewall temporarily, run:"
echo "  sudo iptables -F OUTPUT"
echo ""
