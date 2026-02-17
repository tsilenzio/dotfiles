#!/usr/bin/env bash

# Pull latest dotfiles changes (creates rollback point first)
# Usage: ./scripts/update.sh

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_DIR
cd "$DOTFILES_DIR"

# Load shared library
source "$DOTFILES_DIR/scripts/lib/common.sh"

if [[ ! -d ".git" ]]; then
    echo "Error: No .git directory found."
    echo "This dotfiles was installed via tarball. Re-run bootstrap to update:"
    echo "  curl -fsSL https://raw.githubusercontent.com/tsilenzio/dotfiles/main/bootstrap.sh | bash"
    exit 1
fi

# Fetch first to check if there are updates
git fetch
LOCAL=$(git rev-parse HEAD)
# shellcheck disable=SC1083
REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "$LOCAL")

if [[ "$LOCAL" == "$REMOTE" ]]; then
    echo "Already up to date."
    exit 0
fi

# Create rollback point
create_snapshot "pre-update"

# Check for dirty files
if [[ -n $(git status --porcelain) ]]; then
    echo ""
    echo "Note: Uncommitted changes will be stashed during update."
fi

# Show incoming changes
echo ""
echo "Incoming changes:"
# shellcheck disable=SC1083
git log --oneline HEAD..@{u}
echo ""

# Pull with autostash
echo "Pulling latest changes..."
git pull --rebase --autostash

PREV_SHORT=$(git rev-parse --short "pre-update/$SNAPSHOT_TIMESTAMP")
NEW_SHORT=$(git rev-parse --short HEAD)
echo ""
echo "Updated: $PREV_SHORT -> $NEW_SHORT"
echo ""
echo "Run 'just upgrade' to apply any new changes."
