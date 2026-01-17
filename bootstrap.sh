#!/usr/bin/env bash

# Bootstrap: Get dotfiles repo and hand off to install.sh
# Usage: ./bootstrap.sh [target_dir]
#        curl -fsSL https://raw.githubusercontent.com/.../bootstrap.sh | bash
#        curl ... | bash -s -- ~/custom/path

set -e

# Parse arguments
TARGET_DIR=""
PASSTHROUGH_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --*)
            # Pass flags through to install.sh
            PASSTHROUGH_ARGS+=("$1")
            if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
                PASSTHROUGH_ARGS+=("$2")
                shift
            fi
            shift
            ;;
        *)
            # First non-flag argument is target dir
            [[ -z "$TARGET_DIR" ]] && TARGET_DIR="$1"
            shift
            ;;
    esac
done

TARGET_DIR="${TARGET_DIR:-${DOTFILES_TARGET:-$HOME/.dotfiles}}"
REPO_URL="https://github.com/tsilenzio/dotfiles.git"
TARBALL_URL="https://github.com/tsilenzio/dotfiles/archive/refs/heads/main.tar.gz"

# ============================================================================
# Helper functions
# ============================================================================

# Check if real git exists (not just macOS shim that triggers CLT dialog)
has_real_git() {
    # If CLT is installed, /usr/bin/git is real
    if xcode-select -p &>/dev/null; then
        command -v git &>/dev/null && return 0
    fi
    # Check for git outside /usr/bin (Homebrew, etc)
    local git_path
    git_path=$(command -v git 2>/dev/null)
    if [[ -n "$git_path" && "$git_path" != "/usr/bin/git" ]]; then
        return 0
    fi
    return 1
}

# Download dotfiles from GitHub
download_dotfiles() {
    if [[ -d "$TARGET_DIR" ]]; then
        echo "Removing existing dotfiles at $TARGET_DIR..."
        rm -rf "$TARGET_DIR"
    fi

    if has_real_git; then
        echo "Cloning dotfiles from GitHub..."
        git clone "$REPO_URL" "$TARGET_DIR"
    else
        echo "Downloading dotfiles from GitHub (git not available)..."
        mkdir -p "$TARGET_DIR"
        curl -fsSL "$TARBALL_URL" | tar -xz -C "$TARGET_DIR" --strip-components=1
        echo "  (downloaded as tarball - no .git directory)"
    fi
}

# ============================================================================
# Main
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    Dotfiles Bootstrap                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Target: $TARGET_DIR"
echo ""

# Detect if running from curl pipe or locally
if [[ -z "${BASH_SOURCE[0]}" ]] || [[ "${BASH_SOURCE[0]}" == "bash" ]] || [[ ! -f "${BASH_SOURCE[0]}" ]]; then
    # Running from curl pipe - download from GitHub
    download_dotfiles
    SOURCE_DIR=""
else
    # Running locally - copy from source (respecting .gitignore)
    SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ "$SOURCE_DIR" != "$TARGET_DIR" ]]; then
        if [[ -d "$TARGET_DIR" ]]; then
            echo "Removing existing dotfiles at $TARGET_DIR..."
            rm -rf "$TARGET_DIR"
        fi

        echo "Copying dotfiles from $SOURCE_DIR to $TARGET_DIR..."
        mkdir -p "$TARGET_DIR"

        # Use rsync with .gitignore filter to exclude ignored files
        rsync -a --filter=':- .gitignore' "$SOURCE_DIR/" "$TARGET_DIR/"
    else
        echo "Already at $TARGET_DIR, skipping copy..."
    fi
fi

# Export source dir so install.sh can find .cache/ if present
export DOTFILES_SOURCE_DIR="$SOURCE_DIR"

# Hand off to install.sh
echo ""
echo "Starting installation..."
exec "$TARGET_DIR/install.sh" "${PASSTHROUGH_ARGS[@]}"
