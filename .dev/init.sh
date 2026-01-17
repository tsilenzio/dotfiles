#!/usr/bin/env bash

# Initialize dev environment - extracts just binary if needed
# Usage: source .dev/init.sh
#
# This script should be SOURCED, not executed, so PATH changes persist:
#   source .dev/init.sh
#   just dev setup

# Detect if being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed:"
    echo "  source ${BASH_SOURCE[0]}"
    exit 1
fi

DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$DEV_DIR")"
CACHE_DIR="$DOTFILES_DIR/.cache"
TMP_BIN_DIR="/tmp/dotfiles-dev-bin"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

_log() { echo -e "${GREEN}[dev-init]${NC} $1"; }
_warn() { echo -e "${YELLOW}[dev-init]${NC} $1"; }

# Check if just is already available
if command -v just &>/dev/null; then
    _log "just already available: $(command -v just)"
    return 0
fi

# Check if already extracted to temp
if [[ -x "$TMP_BIN_DIR/just" ]]; then
    _log "Using previously extracted just"
    export PATH="$PATH:$TMP_BIN_DIR"
    return 0
fi

mkdir -p "$TMP_BIN_DIR"

# Look for just tarball in cache (use latest version if multiple)
# Supports: just-1.38.0-aarch64-apple-darwin.tar.gz or just-aarch64-apple-darwin.tar.gz
JUST_TARBALL=$(find "$CACHE_DIR" -maxdepth 1 -name "just-*-aarch64-apple-darwin.tar.gz" 2>/dev/null | sort -V | tail -1)
if [[ -z "$JUST_TARBALL" ]]; then
    JUST_TARBALL=$(find "$CACHE_DIR" -maxdepth 1 -name "just-aarch64-apple-darwin.tar.gz" 2>/dev/null)
fi

if [[ -n "$JUST_TARBALL" && -f "$JUST_TARBALL" ]]; then
    # Extract from cache
    _log "Extracting just from: $(basename "$JUST_TARBALL")"
    tar -xzf "$JUST_TARBALL" -C "$TMP_BIN_DIR" just 2>/dev/null
else
    # Download from GitHub releases to cache
    _log "No cached just binary found, downloading from GitHub..."

    # Get latest release info
    RELEASE_INFO=$(curl -fsSL "https://api.github.com/repos/casey/just/releases/latest" 2>/dev/null)
    if [[ -z "$RELEASE_INFO" ]]; then
        _warn "Failed to fetch release info from GitHub"
        _warn "Check your internet connection or manually download to $CACHE_DIR"
        return 1
    fi

    # Extract download URL for aarch64-apple-darwin
    DOWNLOAD_URL=$(echo "$RELEASE_INFO" | grep -o '"browser_download_url": *"[^"]*aarch64-apple-darwin.tar.gz"' | head -1 | cut -d'"' -f4)
    if [[ -z "$DOWNLOAD_URL" ]]; then
        _warn "Could not find download URL for aarch64-apple-darwin"
        return 1
    fi

    VERSION=$(echo "$RELEASE_INFO" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
    JUST_TARBALL="$CACHE_DIR/just-${VERSION}-aarch64-apple-darwin.tar.gz"

    _log "Downloading just $VERSION to cache..."
    mkdir -p "$CACHE_DIR"
    if ! curl -fsSL "$DOWNLOAD_URL" -o "$JUST_TARBALL"; then
        _warn "Failed to download just"
        rm -f "$JUST_TARBALL"
        return 1
    fi

    # Extract from cached tarball
    _log "Extracting just from: $(basename "$JUST_TARBALL")"
    tar -xzf "$JUST_TARBALL" -C "$TMP_BIN_DIR" just 2>/dev/null
fi

if [[ ! -x "$TMP_BIN_DIR/just" ]]; then
    _warn "Failed to extract just binary"
    return 1
fi

# Add to end of PATH (so system just takes priority if it exists)
export PATH="$PATH:$TMP_BIN_DIR"

_log "just available at: $TMP_BIN_DIR/just"
_log "Run 'just dev' to see available commands"
