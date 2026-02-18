#!/usr/bin/env bash

# Pull latest dotfiles changes (creates rollback point first)
# Uncommitted changes are stashed and discarded by default.
# Usage: ./scripts/update.sh [--keep]

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_DIR
cd "$DOTFILES_DIR"

# Parse flags
KEEP_CHANGES=false
for arg in "$@"; do
    case "$arg" in
        --keep) KEEP_CHANGES=true ;;
    esac
done

# Load shared library
source "$DOTFILES_DIR/scripts/lib/common.sh"


if [[ -f "$DOTFILES_DIR/.state/preview" ]]; then
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
    echo "Note: Preview active — updating on branch: $current_branch"
    echo ""
fi

if [[ ! -d ".git" ]]; then
    echo "Error: No .git directory found."
    echo "This dotfiles was installed via tarball. Re-run bootstrap to update:"
    echo "  curl -fsSL https://raw.githubusercontent.com/tsilenzio/dotfiles/main/bootstrap.sh | bash"
    exit 1
fi

# Ensure tracking is set (tarball-to-git conversions may lack it)
if ! git rev-parse --abbrev-ref '@{u}' &>/dev/null; then
    git branch --set-upstream-to=origin/main main 2>/dev/null || true
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
TIMESTAMP="$SNAPSHOT_TIMESTAMP"
TAG_NAME="$SNAPSHOT_TAG_NAME"

# Handle uncommitted changes

if [[ -n $(git status --porcelain) ]]; then
    if [[ "$KEEP_CHANGES" == true ]]; then
        echo ""
        echo "Keeping uncommitted changes (--keep)."
        PULL_FLAGS="--rebase --autostash"
    else
        echo ""
        echo "Backing up uncommitted changes to git stash..."
        git stash push -u -m "dotfiles-update/$TIMESTAMP"
        echo "Changes saved. Recover with: git stash list"
        PULL_FLAGS="--rebase"
    fi
else
    PULL_FLAGS="--rebase"
fi

# Show incoming changes
echo ""
echo "Incoming changes:"
# shellcheck disable=SC1083
git log --oneline HEAD..@{u}
echo ""

# Pull latest
echo "Pulling latest changes..."
# shellcheck disable=SC2086
git pull $PULL_FLAGS

PREV_SHORT=$(git rev-parse --short "$TAG_NAME")
NEW_SHORT=$(git rev-parse --short HEAD)
echo ""
echo "Updated: $PREV_SHORT -> $NEW_SHORT"
echo ""
echo "Run 'just upgrade' to apply any new changes."
