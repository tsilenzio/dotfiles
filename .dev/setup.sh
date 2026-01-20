#!/usr/bin/env bash

# Install CLT and Homebrew from local .cache/ directory
# Usage: just dev setup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="$DOTFILES_DIR/.cache"
PLATFORM_DIR="$DOTFILES_DIR/platforms/macos"

# Run preflight (sets up sudo, triggers permission dialogs)
if [[ -f "$PLATFORM_DIR/preflight.sh" ]]; then
    source "$PLATFORM_DIR/preflight.sh"
    trap preflight_cleanup EXIT
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[dev-setup]${NC} $1"; }
warn() { echo -e "${YELLOW}[dev-setup]${NC} $1"; }
info() { echo -e "${BLUE}[dev-setup]${NC} $1"; }

# ============================================================================
# Check cache directory
# ============================================================================
if [[ ! -d "$CACHE_DIR" ]]; then
    echo "Cache directory not found: $CACHE_DIR"
    echo ""
    echo "Place the following files in $CACHE_DIR:"
    echo "  - Command Line Tools DMG (e.g., Command_Line_Tools_for_Xcode_16.dmg)"
    echo "  - Homebrew PKG (e.g., Homebrew-4.4.0.pkg)"
    exit 1
fi

# ============================================================================
# Install Xcode Command Line Tools
# ============================================================================
if xcode-select -p &>/dev/null; then
    log "Xcode Command Line Tools already installed"
else
    # Find CLT DMG in cache (use latest version if multiple exist)
    # Supports: Command_Line_Tools_for_Xcode_16.1.dmg or Command_Line_Tools.dmg
    CLT_DMG=$(find "$CACHE_DIR" -maxdepth 1 -name "Command_Line_Tools_for_Xcode*.dmg" 2>/dev/null | sort -V | tail -1)
    if [[ -z "$CLT_DMG" ]]; then
        CLT_DMG=$(find "$CACHE_DIR" -maxdepth 1 -name "Command_Line_Tools.dmg" 2>/dev/null)
    fi

    if [[ -n "$CLT_DMG" && -f "$CLT_DMG" ]]; then
        log "Installing Xcode Command Line Tools from: $(basename "$CLT_DMG")"

        # Mount DMG and extract mount point (handles spaces in volume name)
        MOUNT_OUTPUT=$(hdiutil attach "$CLT_DMG" -nobrowse)
        MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep -o '/Volumes/.*' | head -1)

        if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
            # Find and install PKG
            PKG_FILE=$(find "$MOUNT_POINT" -maxdepth 1 -name "*.pkg" 2>/dev/null | head -1)
            if [[ -n "$PKG_FILE" ]]; then
                sudo installer -pkg "$PKG_FILE" -target /
                log "Xcode Command Line Tools installed"
            else
                warn "No PKG found in DMG at: $MOUNT_POINT"
                info "Contents: $(ls -la "$MOUNT_POINT" 2>/dev/null || echo 'unable to list')"
            fi

            # Unmount
            hdiutil detach "$MOUNT_POINT" -quiet || true
        else
            warn "Failed to mount DMG"
            info "Mount output: $MOUNT_OUTPUT"
        fi
    else
        warn "No CLT DMG found in $CACHE_DIR"
        info "Download from: https://developer.apple.com/download/more/"
    fi
fi

# ============================================================================
# Install Homebrew
# ============================================================================
# Check CLT is installed (required for Homebrew)
if ! xcode-select -p &>/dev/null; then
    warn "Skipping Homebrew: Command Line Tools not installed"
    exit 1
fi

# Check if Homebrew is installed (check PATH and common locations)
BREW_BIN=""
if command -v brew &>/dev/null; then
    BREW_BIN="$(command -v brew)"
elif [[ -x "/opt/homebrew/bin/brew" ]]; then
    BREW_BIN="/opt/homebrew/bin/brew"
elif [[ -x "/usr/local/bin/brew" ]]; then
    BREW_BIN="/usr/local/bin/brew"
fi

if [[ -n "$BREW_BIN" ]]; then
    log "Homebrew already installed at: $BREW_BIN"
else
    # Find Homebrew PKG in cache (use latest version if multiple exist)
    # Supports: Homebrew-4.4.0.pkg or Homebrew.pkg
    BREW_PKG=$(find "$CACHE_DIR" -maxdepth 1 -name "Homebrew-*.pkg" 2>/dev/null | sort -V | tail -1)
    if [[ -z "$BREW_PKG" ]]; then
        BREW_PKG=$(find "$CACHE_DIR" -maxdepth 1 -name "Homebrew.pkg" 2>/dev/null)
    fi

    if [[ -n "$BREW_PKG" && -f "$BREW_PKG" ]]; then
        log "Installing Homebrew from: $(basename "$BREW_PKG")"
        sudo installer -pkg "$BREW_PKG" -target /
        log "Homebrew installed"
    else
        warn "No Homebrew PKG found in $CACHE_DIR"
        info "Download from: https://github.com/Homebrew/brew/releases"
    fi
fi

# ============================================================================
# Add Homebrew to PATH for current session
# ============================================================================
if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    log "Homebrew added to PATH"
elif [[ -x "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
    log "Homebrew added to PATH"
fi

echo ""
log "Setup complete!"
log ""
log "Next steps:"
log "  just dev bootstrap    # Run bootstrap with test bundle option"
log "  -- or --"
log "  ./bootstrap.sh --test # Same thing, runs install with test bundle"
