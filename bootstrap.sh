#!/usr/bin/env bash

set -e  # Exit on error

# Parse arguments
# Usage: ./bootstrap.sh [--test] [--profile <name>] [target_dir]
#        curl ... | bash -s -- --profile work
#        DOTFILES_TARGET=~/custom ./bootstrap.sh
INSTALL_FLAGS=""
TARGET_DIR=""
PROFILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            INSTALL_FLAGS="$INSTALL_FLAGS --test"
            shift
            ;;
        --profile)
            PROFILE="$2"
            INSTALL_FLAGS="$INSTALL_FLAGS --profile $2"
            shift 2
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

# Check if --test was passed (for showing test profile option)
TEST_MODE=false
[[ "$INSTALL_FLAGS" == *"--test"* ]] && TEST_MODE=true

# ============================================================================
# Early profile selection (needed for curl|bash to work)
# Must happen BEFORE exec install.sh due to tee interference with /dev/tty
# ============================================================================
if [[ -z "$PROFILE" ]] && [[ -r /dev/tty ]]; then
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    Dotfiles Installer                      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "This will install dotfiles to: $TARGET_DIR"
    echo ""
    echo "Select profile:"
    echo "  1) Personal"
    echo "  2) Work"
    if [[ "$TEST_MODE" == "true" ]]; then
        echo "  3) Test (minimal packages)"
    fi
    echo ""

    if [[ "$TEST_MODE" == "true" ]]; then
        echo -n "Choice [1/2/3]: " > /dev/tty
    else
        echo -n "Choice [1/2]: " > /dev/tty
    fi
    read -r PROFILE_CHOICE < /dev/tty || true

    case $PROFILE_CHOICE in
        1) PROFILE="personal" ;;
        2) PROFILE="work" ;;
        3) [[ "$TEST_MODE" == "true" ]] && PROFILE="test" || PROFILE="personal" ;;
        *) PROFILE="personal" ;;
    esac
    INSTALL_FLAGS="$INSTALL_FLAGS --profile $PROFILE"
    echo "Using profile: $PROFILE"
fi

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

# Detect if running from curl pipe or locally
if [[ -z "${BASH_SOURCE[0]}" ]] || [[ "${BASH_SOURCE[0]}" == "bash" ]] || [[ ! -f "${BASH_SOURCE[0]}" ]]; then
    # Running from curl pipe - download from GitHub
    download_dotfiles
else
    # Running locally - copy from source (respecting .gitignore)
    SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ "$SOURCE_DIR" != "$TARGET_DIR" ]]; then
        if [[ -d "$TARGET_DIR" ]]; then
            echo "Removing existing dotfiles at $TARGET_DIR..."
            rm -rf "$TARGET_DIR"
        fi

        echo "Copying dotfiles from $SOURCE_DIR to $TARGET_DIR..."
        echo "  (respecting .gitignore - logs and other ignored files excluded)"
        mkdir -p "$TARGET_DIR"

        # Use rsync with .gitignore filter to exclude ignored files
        # Keeps .git so target can pull updates
        rsync -a --filter=':- .gitignore' "$SOURCE_DIR/" "$TARGET_DIR/"
    else
        echo "Already running from $TARGET_DIR, skipping copy..."
    fi
fi

# Run install script from target location
echo ""
echo "Running install script..."

# Export source dir so install.sh can find .cache/ if present
export DOTFILES_SOURCE_DIR="$SOURCE_DIR"

# exec replaces this process with install.sh, which then exec's into a fresh
# login shell at the end. This gives first-time users a fully configured shell.
exec "$TARGET_DIR/install.sh" $INSTALL_FLAGS
