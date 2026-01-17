#!/usr/bin/env bash

# Pre-fetch Homebrew packages to local .cache/homebrew/
# Usage: just dev prefetch [profiles...]
#
# Examples:
#   just dev prefetch              # defaults to 'test' profile only
#   just dev prefetch base         # Brewfile only
#   just dev prefetch work         # Brewfile + Brewfile.work
#   just dev prefetch personal     # Brewfile + Brewfile.personal
#   just dev prefetch work personal # Brewfile + both profiles
#   just dev prefetch all          # All available Brewfiles
#   just dev prefetch test         # Brewfile.test only

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="$DOTFILES_DIR/.cache"
HOMEBREW_CACHE_DIR="$CACHE_DIR/homebrew"
PLATFORM_DIR="$DOTFILES_DIR/platforms/macos"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[dev-prefetch]${NC} $1"; }
warn() { echo -e "${YELLOW}[dev-prefetch]${NC} $1"; }
info() { echo -e "${BLUE}[dev-prefetch]${NC} $1"; }

# ============================================================================
# Check Homebrew
# ============================================================================
if ! command -v brew &>/dev/null; then
    # Try to find Homebrew
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    else
        warn "Homebrew not installed. Run 'just dev setup' first."
        exit 1
    fi
fi

# ============================================================================
# Determine which Brewfiles to use
# ============================================================================
BREWFILES=()
PROFILES=("$@")

# Default to 'test' if no arguments
if [[ ${#PROFILES[@]} -eq 0 ]]; then
    PROFILES=("test")
fi

for profile in "${PROFILES[@]}"; do
    case "$profile" in
        test)
            [[ -f "$PLATFORM_DIR/Brewfile.test" ]] && BREWFILES+=("$PLATFORM_DIR/Brewfile.test")
            ;;
        base)
            [[ -f "$PLATFORM_DIR/Brewfile" ]] && BREWFILES+=("$PLATFORM_DIR/Brewfile")
            ;;
        all)
            # Add all Brewfiles found
            for bf in "$PLATFORM_DIR"/Brewfile*; do
                [[ -f "$bf" ]] && BREWFILES+=("$bf")
            done
            ;;
        *)
            # Profile name (work, personal, etc.) - include base + profile
            [[ -f "$PLATFORM_DIR/Brewfile" ]] && BREWFILES+=("$PLATFORM_DIR/Brewfile")
            if [[ -f "$PLATFORM_DIR/Brewfile.$profile" ]]; then
                BREWFILES+=("$PLATFORM_DIR/Brewfile.$profile")
            else
                warn "Brewfile.$profile not found, skipping"
            fi
            ;;
    esac
done

# Remove duplicates while preserving order (bash 3.x compatible)
UNIQUE_BREWFILES=()
for bf in "${BREWFILES[@]}"; do
    # Check if already in UNIQUE_BREWFILES
    duplicate=false
    for existing in "${UNIQUE_BREWFILES[@]}"; do
        if [[ "$existing" == "$bf" ]]; then
            duplicate=true
            break
        fi
    done
    if [[ "$duplicate" == false ]]; then
        UNIQUE_BREWFILES+=("$bf")
    fi
done
BREWFILES=("${UNIQUE_BREWFILES[@]}")

if [[ ${#BREWFILES[@]} -eq 0 ]]; then
    warn "No Brewfiles found"
    exit 1
fi

# ============================================================================
# Pre-fetch Homebrew packages
# ============================================================================
log "Pre-fetching Homebrew packages to: $HOMEBREW_CACHE_DIR"
mkdir -p "$HOMEBREW_CACHE_DIR"
export HOMEBREW_CACHE="$HOMEBREW_CACHE_DIR"

log "Using Brewfiles:"
for bf in "${BREWFILES[@]}"; do
    log "  - $(basename "$bf")"
done

# Extract and add taps first (required for some formulas)
TAPS=""
for bf in "${BREWFILES[@]}"; do
    TAPS+="$(grep -E '^tap "' "$bf" 2>/dev/null | sed 's/tap "//;s/".*$//')"
    TAPS+=$'\n'
done
TAPS=$(echo "$TAPS" | grep -v '^$' | sort -u)

if [[ -n "$TAPS" ]]; then
    log "Adding taps..."
    for tap in $TAPS; do
        info "  Tapping: $tap"
        brew tap "$tap" 2>/dev/null || warn "Failed to tap: $tap"
    done
fi

# Extract package names from all Brewfiles
PACKAGES=""
for bf in "${BREWFILES[@]}"; do
    PACKAGES+="$(grep -E '^brew "' "$bf" 2>/dev/null | sed 's/brew "//;s/".*$//')"
    PACKAGES+=$'\n'
done

# Sort and dedupe
PACKAGES=$(echo "$PACKAGES" | grep -v '^$' | sort -u)

if [[ -z "$PACKAGES" ]]; then
    warn "No packages found in Brewfile"
    exit 0
fi

TOTAL=$(echo "$PACKAGES" | wc -l | tr -d ' ')
CURRENT=0

for pkg in $PACKAGES; do
    CURRENT=$((CURRENT + 1))
    info "[$CURRENT/$TOTAL] Fetching: $pkg"
    brew fetch --deps "$pkg" 2>/dev/null || warn "Failed to fetch: $pkg"
done

echo ""
log "Prefetch complete!"
log "Cache location: $HOMEBREW_CACHE_DIR"
log "Cache size: $(du -sh "$HOMEBREW_CACHE_DIR" 2>/dev/null | cut -f1)"
