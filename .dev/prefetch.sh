#!/usr/bin/env bash

# Pre-fetch Homebrew packages to local .cache/homebrew/
# Usage: just dev prefetch [profiles...]
#
# Examples:
#   just dev prefetch              # defaults to 'test' profile only
#   just dev prefetch core         # Core profile Brewfile
#   just dev prefetch work         # Core + work profiles
#   just dev prefetch personal     # Core + personal profiles
#   just dev prefetch all          # All available profiles
#   just dev prefetch test         # Test profile only (standalone)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="$DOTFILES_DIR/.cache"
HOMEBREW_CACHE_DIR="$CACHE_DIR/homebrew"
PROFILES_DIR="$DOTFILES_DIR/platforms/macos/profiles"

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
            # Standalone - only test profile
            BREWFILE="$PROFILES_DIR/test/Brewfile"
            [[ -f "$BREWFILE" ]] && BREWFILES+=("$BREWFILE")
            ;;
        all)
            # Add all profile Brewfiles
            for profile_dir in "$PROFILES_DIR"/*/; do
                bf="$profile_dir/Brewfile"
                [[ -f "$bf" ]] && BREWFILES+=("$bf")
            done
            ;;
        *)
            # Named profile - include core + named profile
            CORE_BREWFILE="$PROFILES_DIR/core/Brewfile"
            [[ -f "$CORE_BREWFILE" ]] && BREWFILES+=("$CORE_BREWFILE")

            PROFILE_BREWFILE="$PROFILES_DIR/$profile/Brewfile"
            if [[ -f "$PROFILE_BREWFILE" ]]; then
                BREWFILES+=("$PROFILE_BREWFILE")
            else
                warn "Profile '$profile' not found or has no Brewfile, skipping"
            fi
            ;;
    esac
done

# Remove duplicates while preserving order (bash 3.x compatible)
UNIQUE_BREWFILES=()
for bf in "${BREWFILES[@]}"; do
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
    # Show relative path for readability
    rel_path="${bf#$DOTFILES_DIR/}"
    log "  - $rel_path"
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
    warn "No packages found in Brewfiles"
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
