#!/usr/bin/env bash
# Test bootstrap in different modes
# Usage: test.sh [local|curl] [extra args...]

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$DOTFILES_DIR"

MODE="${1:-local}"
shift 2>/dev/null || true

case "$MODE" in
    local)
        ./bootstrap.sh --reveal test "$@"
        ;;
    curl)
        echo "Emulating: curl ... | bash -s -- --reveal test $*"
        cat bootstrap.sh | bash -s -- --reveal test "$@"
        ;;
    *)
        echo "Usage: test.sh [local|curl] [extra args...]"
        echo ""
        echo "Modes:"
        echo "  local  Run bootstrap.sh directly (default)"
        echo "  curl   Emulate curl|bash piped execution"
        exit 1
        ;;
esac
