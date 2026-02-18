#!/usr/bin/env bash
# Run linters (shellcheck + zsh syntax)

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# List git-aware files (tracked + untracked non-ignored) that exist on disk
_lint_files() {
    git -C "$DOTFILES_DIR" ls-files --cached --others --exclude-standard \
        | grep -E "$1" \
        | while IFS= read -r f; do
            [[ -f "$DOTFILES_DIR/$f" ]] && echo "$DOTFILES_DIR/$f"
        done
}

echo "Running ShellCheck..."
_lint_files '\.(sh|bash)$' | xargs shellcheck --severity=warning -x

echo ""
echo "Checking Zsh syntax..."
_lint_files '(zshrc|zshenv|zprofile|\.zsh)$' | xargs -I{} zsh -n {}

echo ""
echo "All checks passed!"
