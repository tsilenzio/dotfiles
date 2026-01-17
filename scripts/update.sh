#!/usr/bin/env bash

# Pull latest dotfiles changes (creates rollback point first)
# Usage: ./scripts/update.sh

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DOTFILES_DIR"

if [[ ! -d ".git" ]]; then
    echo "Error: No .git directory found."
    echo "This dotfiles was installed via tarball. Re-run bootstrap to update:"
    echo "  curl -fsSL https://raw.githubusercontent.com/tsilenzio/dotfiles/main/bootstrap.sh | bash"
    exit 1
fi

# Fetch first to check if there are updates
git fetch
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "$LOCAL")

if [[ "$LOCAL" == "$REMOTE" ]]; then
    echo "Already up to date."
    exit 0
fi

# Create rollback point
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TAG_NAME="pre-update/$TIMESTAMP"

echo "Creating rollback point: $TAG_NAME"
git tag "$TAG_NAME"

# Snapshot current brew state (if brew available)
if command -v brew &>/dev/null; then
    SNAPSHOT_DIR="$DOTFILES_DIR/logs/brew-snapshots"
    mkdir -p "$SNAPSHOT_DIR"
    SNAPSHOT_FILE="$SNAPSHOT_DIR/$TIMESTAMP.Brewfile"
    echo "Saving brew snapshot: $SNAPSHOT_FILE"
    brew bundle dump --file="$SNAPSHOT_FILE" --force
fi

# Check for dirty files
if [[ -n $(git status --porcelain) ]]; then
    echo ""
    echo "Note: Uncommitted changes will be stashed during update."
fi

# Show incoming changes
echo ""
echo "Incoming changes:"
git log --oneline HEAD..@{u}
echo ""

# Pull with autostash
echo "Pulling latest changes..."
git pull --rebase --autostash

PREV_SHORT=$(git rev-parse --short "$TAG_NAME")
NEW_SHORT=$(git rev-parse --short HEAD)
echo ""
echo "Updated: $PREV_SHORT -> $NEW_SHORT"
echo ""
echo "To rollback: just rollback $TIMESTAMP"
echo "Run 'just install' to apply any new changes."
