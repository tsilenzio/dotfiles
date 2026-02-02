#!/usr/bin/env bash
# Run linters (shellcheck + zsh syntax)

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "Running ShellCheck..."
find "$DOTFILES_DIR" -type f \( -name "*.sh" -o -name "*.bash" \) \
    ! -path "*/.git/*" ! -path "*/.cache/*" \
    -exec shellcheck --severity=warning -x {} +

echo ""
echo "Checking Zsh syntax..."
find "$DOTFILES_DIR" -type f \( -name "zshrc*" -o -name "zshenv*" -o -name "*.zsh" \) \
    ! -path "*/.git/*" ! -path "*/.cache/*" \
    -exec zsh -n {} \;

echo ""
echo "All checks passed!"
