#!/usr/bin/env bash

# Rollback to a previous dotfiles state
# Usage: ./scripts/rollback.sh [timestamp] [--with-brew] [--dry-run]

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DOTFILES_DIR"

SNAPSHOT_BASE="$DOTFILES_DIR/.state/snapshots"
LOG_DIR="$DOTFILES_DIR/.state/logs"

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
    while IFS= read -r line; do
        [[ -n "$line" ]] && TAGS+=("$line")
    done < <(git tag -l "pre-update/*" --sort=-creatordate)

    if [[ ${#TAGS[@]} -eq 0 ]]; then
        echo "No rollback points found."
        echo "Rollback points are created automatically when you run 'just update'."
        exit 1
    fi

    for i in "${!TAGS[@]}"; do
        tag="${TAGS[$i]}"
        TIMESTAMP="${tag#pre-update/}"
        HASH=$(git rev-parse --short "$tag")
        INDICATORS=""
        SNAPSHOT_DIR="$SNAPSHOT_BASE/$TIMESTAMP"
        if [[ -d "$SNAPSHOT_DIR" ]]; then
            [[ -f "$SNAPSHOT_DIR/Brewfile" ]] && INDICATORS+=" [brew]"
            [[ -f "$SNAPSHOT_DIR/bundles" ]] && INDICATORS+=" [bundles]"
        fi
        echo "  $((i+1))) $TIMESTAMP ($HASH)$INDICATORS"
    done

    echo ""
    read -r -p "Select rollback point [1-${#TAGS[@]}]: " SELECTION

    if [[ ! "$SELECTION" =~ ^[0-9]+$ ]] || [[ "$SELECTION" -lt 1 ]] || [[ "$SELECTION" -gt ${#TAGS[@]} ]]; then
        echo "Invalid selection."
        exit 1
    fi

    TARGET="${TAGS[$((SELECTION-1))]#pre-update/}"
fi

TAG_NAME="pre-update/$TARGET"
SNAPSHOT_DIR="$SNAPSHOT_BASE/$TARGET"

# Verify tag exists
if ! git rev-parse "$TAG_NAME" &>/dev/null; then
    echo "Error: Rollback point '$TARGET' not found."
    echo "Run 'just history' to see available points."
    exit 1
fi

CURRENT_HASH=$(git rev-parse --short HEAD)
TARGET_HASH=$(git rev-parse --short "$TAG_NAME")

echo "Rolling back: $CURRENT_HASH -> $TARGET_HASH"

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

# Create a safety tag for current state before rollback
SAFETY_TAG="pre-rollback/$(date +%Y%m%d-%H%M%S)"
git tag "$SAFETY_TAG"
echo "Safety tag created: $SAFETY_TAG"

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
        else
            echo "Brew rollback skipped by user."
        fi
    fi
fi

echo ""
echo "Rollback complete!"
echo "Safety tag available: $SAFETY_TAG (in case you need to undo this rollback)"
