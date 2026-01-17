#!/usr/bin/env bash

# Show available rollback points
# Usage: ./scripts/history.sh

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DOTFILES_DIR"

echo "Available rollback points:"
echo ""

TAGS=$(git tag -l "pre-update/*" --sort=-creatordate)

if [[ -z "$TAGS" ]]; then
    echo "  No rollback points found."
    echo ""
    echo "Rollback points are created automatically when you run 'just update'."
    exit 0
fi

echo "$TAGS" | while read -r tag; do
    TIMESTAMP="${tag#pre-update/}"
    HASH=$(git rev-parse --short "$tag")

    # Format timestamp for display
    if [[ "$TIMESTAMP" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})-([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
        DISPLAY_DATE="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}"
    else
        DISPLAY_DATE="$TIMESTAMP"
    fi

    # Check if brew snapshot exists
    BREW_INDICATOR=""
    if [[ -f "$DOTFILES_DIR/logs/brew-snapshots/$TIMESTAMP.Brewfile" ]]; then
        BREW_INDICATOR=" [brew]"
    fi

    echo "  $TIMESTAMP  ($HASH)  $DISPLAY_DATE$BREW_INDICATOR"
done

echo ""
echo "Usage:"
echo "  just rollback <timestamp>              # Git-only rollback"
echo "  just rollback <timestamp> --with-brew  # Also revert packages"
echo "  just rollback <timestamp> --dry-run    # Preview changes"
