#!/usr/bin/env bash

# Rollback to a previous dotfiles state
# Usage: ./scripts/rollback.sh [timestamp] [--with-brew] [--dry-run]

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_DIR
cd "$DOTFILES_DIR"

# Load shared library
source "$DOTFILES_DIR/scripts/lib/common.sh"

SNAPSHOT_BASE="$DOTFILES_DIR/.state/snapshots"
LOG_DIR="$DOTFILES_DIR/.state/logs"

ALL_PREFIXES=("pre-update" "pre-upgrade" "pre-bundle-change" "pre-bootstrap" "pre-change" "pre-conversion" "pre-rollback")

# Parse arguments
TARGET=""
WITH_BREW=false
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --with-brew) WITH_BREW=true ;;
        --dry-run) DRY_RUN=true ;;
        -*) echo "Unknown flag: $arg"; exit 1 ;;
        *) TARGET="$arg" ;;
    esac
done

# If no target, show interactive selection
if [[ -z "$TARGET" ]]; then
    echo "Available rollback points:"
    echo ""

    TAGS=()
    # Collect tags from all rollback-related prefixes
    TAG_ARGS=()
    for prefix in "${ALL_PREFIXES[@]}"; do
        TAG_ARGS+=("$prefix/*")
    done
    while IFS= read -r line; do
        [[ -n "$line" ]] && TAGS+=("$line")
    done < <(git tag -l "${TAG_ARGS[@]}" --sort=-creatordate)

    if [[ ${#TAGS[@]} -eq 0 ]]; then
        echo "No rollback points found."
        echo "Rollback points are created automatically when you run 'just update' or 'just upgrade'."
        exit 1
    fi

    for i in "${!TAGS[@]}"; do
        tag="${TAGS[$i]}"
        # Extract timestamp (everything after the last /)
        TIMESTAMP="${tag##*/}"
        HASH=$(git rev-parse --short "$tag")
        INDICATORS=""
        # Extract prefix for display
        PREFIX="${tag%/*}"
        SNAPSHOT_DIR="$SNAPSHOT_BASE/$TIMESTAMP"
        if [[ -d "$SNAPSHOT_DIR" ]]; then
            [[ -f "$SNAPSHOT_DIR/Brewfile" ]] && INDICATORS+=" [brew]"
            [[ -f "$SNAPSHOT_DIR/bundles" ]] && INDICATORS+=" [bundles]"
        fi
        echo "  $((i+1))) $TIMESTAMP ($HASH) [$PREFIX]$INDICATORS"
    done

    echo ""
    read -r -p "Select rollback point [1-${#TAGS[@]}]: " SELECTION

    if [[ ! "$SELECTION" =~ ^[0-9]+$ ]] || [[ "$SELECTION" -lt 1 ]] || [[ "$SELECTION" -gt ${#TAGS[@]} ]]; then
        echo "Invalid selection."
        exit 1
    fi

    # Store the full tag name for later use
    TAG_NAME="${TAGS[$((SELECTION-1))]}"
    TARGET="${TAG_NAME##*/}"
fi

# If target was provided directly, try to find the matching tag
if [[ -z "${TAG_NAME:-}" ]]; then
    for prefix in "${ALL_PREFIXES[@]}"; do
        if git rev-parse "$prefix/$TARGET" &>/dev/null; then
            TAG_NAME="$prefix/$TARGET"
            break
        fi
    done
fi
SNAPSHOT_DIR="$SNAPSHOT_BASE/$TARGET"

# Verify tag exists
if [[ -z "${TAG_NAME:-}" ]] || ! git rev-parse "$TAG_NAME" &>/dev/null; then
    echo "Error: Rollback point '$TARGET' not found."
    echo "Run 'just history' to see available points."
    exit 1
fi

CURRENT_HASH=$(git rev-parse --short HEAD)
TARGET_HASH=$(git rev-parse --short "$TAG_NAME")

echo "Rolling back: $CURRENT_HASH -> $TARGET_HASH"

# If --with-brew, check upfront if sudo will be needed and cache credentials
if [[ "$WITH_BREW" == "true" && "$DRY_RUN" != "true" ]]; then
    if [[ -f "$SNAPSHOT_DIR/Brewfile" ]]; then
        # Check if there are packages to remove
        CLEANUP_LIST=$(brew bundle cleanup --file="$SNAPSHOT_DIR/Brewfile" 2>/dev/null || true)
        if [[ -n "$CLEANUP_LIST" ]]; then
            echo ""
            echo "Brew rollback will remove packages. Requesting sudo access upfront..."
            sudo -v
            # Keep sudo alive in the background
            while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
            SUDO_KEEPALIVE_PID=$!
            trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT
        fi
    fi
fi

# Dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "[DRY RUN] Would reset to $TAG_NAME"
    echo ""
    echo "Changes that would be reverted:"
    git log --oneline "$TAG_NAME"..HEAD

    if [[ "$WITH_BREW" == "true" ]]; then
        if [[ -f "$SNAPSHOT_DIR/Brewfile" ]]; then
            echo ""
            echo "[DRY RUN] Would restore brew packages from: $SNAPSHOT_DIR/Brewfile"
            echo ""
            echo "Packages that would be removed (not in snapshot):"
            brew bundle cleanup --file="$SNAPSHOT_DIR/Brewfile" 2>/dev/null || echo "  (unable to determine)"
        else
            echo ""
            echo "[DRY RUN] No brew snapshot found for $TARGET"
        fi
    fi
    exit 0
fi

# Capture uncommitted changes so nothing is lost
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo ""
    echo "Saving uncommitted changes to rollback point..."
    git add -A
    git commit -q -m "WIP: uncommitted state before rollback" --no-gpg-sign
fi

# Create full snapshot before rollback
echo ""
create_snapshot "pre-rollback"

# Reset git
git reset --hard "$TAG_NAME"
echo "Git reset complete."

# Handle brew rollback if requested
if [[ "$WITH_BREW" == "true" ]]; then
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/rollback-$(date +%Y%m%d-%H%M%S).log"

    if [[ ! -f "$SNAPSHOT_DIR/Brewfile" ]]; then
        echo ""
        echo "Warning: No brew snapshot found for $TARGET"
        echo "Skipping brew rollback."
    else
        echo ""
        echo "Rolling back brew packages..."
        echo "Log: $LOG_FILE"

        # Start logging
        exec > >(tee -a "$LOG_FILE") 2>&1

        echo ""
        echo "=== Brew Rollback Log ==="
        echo "Timestamp: $(date)"
        echo "Rollback target: $TARGET"
        echo "Snapshot: $SNAPSHOT_DIR/Brewfile"
        echo ""

        echo "=== Packages to be removed (not in snapshot) ==="
        brew bundle cleanup --file="$SNAPSHOT_DIR/Brewfile" 2>&1 || true

        echo ""
        read -r -p "Proceed with brew cleanup and reinstall? [y/N]: " CONFIRM

        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo ""
            echo "=== Running brew bundle cleanup ==="
            brew bundle cleanup --file="$SNAPSHOT_DIR/Brewfile" --force 2>&1

            echo ""
            echo "=== Running brew bundle install ==="
            brew bundle install --file="$SNAPSHOT_DIR/Brewfile" 2>&1

            echo ""
            echo "=== Brew rollback complete ==="
            PACKAGES_CHANGED=true
        else
            echo "Brew rollback skipped by user."
        fi
    fi
fi

echo ""
echo "Rollback complete!"
echo "  To undo: just rollback $SNAPSHOT_TIMESTAMP"

# Offer to re-apply configuration
echo ""
read -r -p "Re-apply configuration? (runs 'just upgrade') [y/N]: " RUN_UPGRADE
if [[ "$RUN_UPGRADE" =~ ^[Yy]$ ]]; then
    "$DOTFILES_DIR/scripts/upgrade.sh"
fi

if [[ "${PACKAGES_CHANGED:-false}" == "true" ]]; then
    echo ""
    echo "Note: Packages were modified. Shell hooks may reference uninstalled programs."
    read -r -p "Restart shell now? [Y/n]: " RESTART_SHELL
    if [[ ! "$RESTART_SHELL" =~ ^[Nn]$ ]]; then
        exec "$SHELL"
    fi
fi
