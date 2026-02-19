#!/usr/bin/env bash

# Pre-fetch Homebrew packages to local .cache/homebrew/
# Usage: just dev prefetch [bundles...]
#
# Examples:
#   just dev prefetch              # defaults to 'test' bundle only
#   just dev prefetch core         # Core bundle Brewfile
#   just dev prefetch work         # Core + work bundles
#   just dev prefetch personal     # Core + personal bundles
#   just dev prefetch all          # All available bundles
#   just dev prefetch test         # Test bundle only (standalone)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_DIR="$(dirname "$SCRIPT_DIR")"
DOTFILES_DIR="$(dirname "$DEV_DIR")"
CACHE_DIR="$DOTFILES_DIR/.cache"
HOMEBREW_CACHE_DIR="$CACHE_DIR/homebrew"
BUNDLES_DIR="$DOTFILES_DIR/platforms/macos/bundles"

source "$SCRIPT_DIR/lib/common.sh"
create_logger "dev-prefetch"

## Check Homebrew

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

# Disable auto-update during prefetch (speeds up operations significantly)
export HOMEBREW_NO_AUTO_UPDATE=1

## Determine which Brewfiles to use

BREWFILES=()
BUNDLES=("$@")

# Default to 'test' if no arguments
if [[ ${#BUNDLES[@]} -eq 0 ]]; then
    BUNDLES=("test")
fi

for bundle in "${BUNDLES[@]}"; do
    case "$bundle" in
        test)
            # Standalone - only test bundle
            BREWFILE="$BUNDLES_DIR/test/Brewfile"
            [[ -f "$BREWFILE" ]] && BREWFILES+=("$BREWFILE")
            ;;
        all)
            # Add all bundle Brewfiles
            for bundle_dir in "$BUNDLES_DIR"/*/; do
                bundle_dir="${bundle_dir%/}"
                bf="$bundle_dir/Brewfile"
                [[ -f "$bf" ]] && BREWFILES+=("$bf")
            done
            ;;
        *)
            # Named bundle - include core + named bundle
            CORE_BREWFILE="$BUNDLES_DIR/core/Brewfile"
            [[ -f "$CORE_BREWFILE" ]] && BREWFILES+=("$CORE_BREWFILE")

            BUNDLE_BREWFILE="$BUNDLES_DIR/$bundle/Brewfile"
            if [[ -f "$BUNDLE_BREWFILE" ]]; then
                BREWFILES+=("$BUNDLE_BREWFILE")
            else
                warn "Bundle '$bundle' not found or has no Brewfile, skipping"
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

## Pre-fetch Homebrew packages

log "Pre-fetching Homebrew packages to: $HOMEBREW_CACHE_DIR"
mkdir -p "$HOMEBREW_CACHE_DIR"
export HOMEBREW_CACHE="$HOMEBREW_CACHE_DIR"

log "Using Brewfiles:"
for bf in "${BREWFILES[@]}"; do
    # Show relative path for readability
    rel_path="${bf#"$DOTFILES_DIR"/}"
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
        if brew tap | grep -q "^$tap\$"; then
            info "  Already tapped: $tap"
        else
            info "  Tapping: $tap"
            brew tap "$tap" || warn "Failed to tap: $tap"
        fi
    done
fi

# Extract package names from all Brewfiles
PACKAGES=""
for bf in "${BREWFILES[@]}"; do
    PACKAGES+="$(grep -E '^brew "' "$bf" 2>/dev/null | sed 's/brew "//;s/".*$//')"
    PACKAGES+=$'\n'
done

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
