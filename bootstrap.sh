#!/usr/bin/env bash

# Bootstrap: Get dotfiles repo and hand off to install.sh
#
# Usage:
#   ./bootstrap.sh [target_dir]                    # Local install
#   curl -fsSL .../bootstrap.sh | bash             # Remote install
#   curl ... | bash -s -- ~/path                   # Remote with custom path
#   ./bootstrap.sh --force                         # Skip safety prompts
#
# Flags:
#   --force         Skip safety checks and prompts (yes to everything)
#   --keep          Preserve uncommitted changes (skip dirty-state errors)
#   --clone         Copy state files when source is configured
#   --select X      Pass through to install.sh (select bundle)
#   --reveal X      Pass through to install.sh (reveal hidden bundle)

set -e

## Parse arguments
TARGET_DIR=""
FORCE=false
KEEP_CHANGES=false
CLONE=false
PASSTHROUGH_ARGS=()

show_help() {
    cat << 'EOF'
Dotfiles Bootstrap

Usage:
  ./bootstrap.sh [options] [target_dir]
  curl -fsSL .../bootstrap.sh | bash
  curl ... | bash -s -- [options] [target_dir]

Options:
  --help          Show this help message
  --force         Skip safety checks and prompts
  --keep          Preserve uncommitted changes (skip dirty-state errors)
  --clone         Copy state files (.bundles, .state/) when source is configured
  --select NAME   Pre-select a bundle (can be used multiple times)
  --reveal NAME   Show a hidden bundle in the selection menu

Examples:
  ./bootstrap.sh                          # Install to ~/.dotfiles
  ./bootstrap.sh ~/my-dotfiles            # Install to custom location
  ./bootstrap.sh --select core            # Pre-select core bundle
  ./bootstrap.sh --reveal test            # Show hidden test bundle

  curl -fsSL .../bootstrap.sh | bash                    # Remote install
  curl ... | bash -s -- --select core --select develop  # Remote with bundles

EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help|help)
            show_help
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --keep)
            KEEP_CHANGES=true
            shift
            ;;
        --clone)
            CLONE=true
            shift
            ;;
        --select|--reveal)
            PASSTHROUGH_ARGS+=("$1" "$2")
            shift 2
            ;;
        --select=*|--reveal=*)
            PASSTHROUGH_ARGS+=("$1")
            shift
            ;;
        --*)
            # Unknown flag - pass through
            PASSTHROUGH_ARGS+=("$1")
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
TARGET_DIR="${TARGET_DIR%/}"  # Normalize: remove trailing slash
REPO_URL="https://github.com/tsilenzio/dotfiles.git"
TARBALL_URL="https://github.com/tsilenzio/dotfiles/archive/refs/heads/main.tar.gz"

## Helper functions

# Check if git command is available (not just macOS shim that triggers CLT dialog)
is_git_available() {
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

# Check if directory is configured (.bundles file exists)
is_configured() {
    local dir="$1"
    [[ -f "$dir/.bundles" ]]
}

# Check if directory is a git repository
is_git_repo() {
    local dir="$1"
    [[ -d "$dir/.git" ]]
}

# Check if directory has .allowunsafe file
is_unsafe_allowed() {
    local dir="$1"
    [[ -f "$dir/.allowunsafe" ]]
}

# Check if git repo has uncommitted changes
is_dirty() {
    local dir="$1"
    [[ -d "$dir/.git" ]] || return 1
    is_git_available || return 1  # Don't trigger CLT dialog
    [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]
}

# Describe state files in a directory (for user info)
describe_state() {
    local dir="$1"

    if [[ -f "$dir/.bundles" ]]; then
        local bundles
        bundles=$(tr '\n' ', ' < "$dir/.bundles" | sed 's/, $//')
        echo "  - .bundles (bundles: $bundles)"
    fi

    if [[ -d "$dir/.state/logs" ]]; then
        local count
        count=$(find "$dir/.state/logs" -name "*.log" 2>/dev/null | wc -l | tr -d ' ')
        [[ "$count" -gt 0 ]] && echo "  - .state/logs/ ($count log files)"
    fi

    if [[ -d "$dir/.state/snapshots" ]]; then
        local count
        count=$(find "$dir/.state/snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        [[ "$count" -gt 0 ]] && echo "  - .state/snapshots/ ($count snapshots)"
    fi

    if [[ -d "$dir/.state/loaded" ]]; then
        local count
        count=$(find "$dir/.state/loaded" -maxdepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')
        [[ "$count" -gt 0 ]] && echo "  - .state/loaded/ ($count loaded bundles)"
    fi
}

# Sync code from source to target (excludes state files)
sync_code() {
    local source="$1"
    local target="$2"

    mkdir -p "$target"
    rsync -a \
        --filter=':- .gitignore' \
        --exclude='.bundles' \
        --exclude='.state/' \
        --exclude='loaded' \
        --exclude='.allowunsafe' \
        "$source/" "$target/"
}

# Copy state files from source to target
copy_state() {
    local source="$1"
    local target="$2"

    [[ -f "$source/.bundles" ]] && cp "$source/.bundles" "$target/.bundles"
    [[ -d "$source/.state" ]] && cp -R "$source/.state" "$target/.state"
    # Note: loaded/ symlink will be recreated by install.sh
}

# Prompt user for yes/no (works with curl|bash via /dev/tty)
prompt_yes_no() {
    local prompt="$1"
    local default="$2"  # "y" or "n"
    local response

    if [[ "$default" == "y" ]]; then
        echo -n "$prompt [Y/n]: "
    else
        echo -n "$prompt [y/N]: "
    fi

    read -r response < /dev/tty || response=""

    case "$(echo "$response" | tr '[:upper:]' '[:lower:]')" in
        y|yes) return 0 ;;
        n|no) return 1 ;;
        "")
            [[ "$default" == "y" ]] && return 0 || return 1
            ;;
        *)
            [[ "$default" == "y" ]] && return 0 || return 1
            ;;
    esac
}

# Snapshot dirty state after tarball-to-git conversion, then clean
# Commits local changes so `just rollback` can restore them via create_snapshot
snapshot_and_clean() {
    local dir="$1"
    local prev_dir="$PWD"
    cd "$dir"

    # Commit dirty files so the snapshot tag preserves them
    git add -A
    if [[ -n "$(git status --porcelain)" ]]; then
        git commit -q --no-gpg-sign -m "chore: preserve tarball-era local changes"
    else
        echo "No changes to preserve after staging."
        cd "$prev_dir"
        return 0
    fi

    # Use shared snapshot function (creates tag + brew dump + bundles + metadata)
    DOTFILES_DIR="$dir" source "$dir/scripts/lib/common.sh"
    create_snapshot "pre-bootstrap"

    # Reset to clean state
    git reset -q --hard origin/main
    echo "Working tree cleaned. Recover with: just rollback $SNAPSHOT_TIMESTAMP"
    cd "$prev_dir"
}

# Initialize git in a directory (convert tarball to git repo)
init_git_repo() {
    local dir="$1"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)

    echo "Initializing git repository..."
    cd "$dir"
    git init -q

    # Commit tarball state so it's recoverable via rollback
    git add -A
    git commit -q -m "Tarball state before git conversion" --no-gpg-sign
    git remote add origin "$REPO_URL"
    git fetch -q origin
    git tag --no-sign "pre-conversion/$timestamp"
    echo "  ✓ Tarball state saved (rollback tag: pre-conversion/$timestamp)"

    # Reset to remote, discarding tarball state cleanly
    git reset --hard origin/main
    git branch --set-upstream-to=origin/main main
    echo "  ✓ Working tree updated to match remote"
    return 0
}

## Main

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                     Dotfiles Bootstrap                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Target: $TARGET_DIR"

# Detect if running from curl pipe or locally
if [[ -z "${BASH_SOURCE[0]}" ]] || [[ "${BASH_SOURCE[0]}" == "bash" ]] || [[ ! -f "${BASH_SOURCE[0]}" ]]; then
    SOURCE_DIR=""
    IS_CURL=true
else
    SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    IS_CURL=false
    echo "Source: $SOURCE_DIR"
fi
echo ""

# Check for .allowunsafe in target (if exists) or source
if [[ -f "$TARGET_DIR/.allowunsafe" ]] || { [[ -n "$SOURCE_DIR" ]] && [[ -f "$SOURCE_DIR/.allowunsafe" ]]; }; then
    FORCE=true
    echo "Note: .allowunsafe file detected, running in force mode"
    echo ""
fi

## Determine scenario and act accordingly

# Same directory - just run install.sh
if [[ "$SOURCE_DIR" == "$TARGET_DIR" ]]; then
    echo "Running from target directory..."
    exec "$TARGET_DIR/install.sh" "${PASSTHROUGH_ARGS[@]}"
fi

# Collect state information
TARGET_EXISTS=false
TARGET_CONFIGURED=false
TARGET_HAS_GIT=false
TARGET_IS_DIRTY=false
SOURCE_CONFIGURED=false

[[ -d "$TARGET_DIR" ]] && TARGET_EXISTS=true
[[ "$TARGET_EXISTS" == true ]] && is_configured "$TARGET_DIR" && TARGET_CONFIGURED=true
[[ "$TARGET_EXISTS" == true ]] && is_git_repo "$TARGET_DIR" && TARGET_HAS_GIT=true
[[ "$TARGET_HAS_GIT" == true ]] && is_dirty "$TARGET_DIR" && TARGET_IS_DIRTY=true
[[ -n "$SOURCE_DIR" ]] && is_configured "$SOURCE_DIR" && SOURCE_CONFIGURED=true

## Curl pipe scenarios
if [[ "$IS_CURL" == true ]]; then

    # Scenario 9: Curl, target has state - just upgrade
    if [[ "$TARGET_CONFIGURED" == true ]]; then
        echo "Dotfiles already configured:"
        describe_state "$TARGET_DIR"
        echo ""

        # Check for dirty state
        if [[ "$TARGET_IS_DIRTY" == true ]] && [[ "$FORCE" != true ]] && [[ "$KEEP_CHANGES" != true ]]; then
            echo "ERROR: Target has uncommitted changes."
            echo ""
            echo "Options:"
            echo "  1. Commit or stash your changes first"
            echo "  2. Run with --keep to preserve them and proceed"
            echo "  3. Run with --force to skip all safety checks"
            echo ""
            exit 1
        fi

        # Convert tarball installs to git repos when git is now available
        if [[ "$TARGET_HAS_GIT" != true ]]; then
            if is_git_available; then
                echo "Target was installed without git. Converting to git repository..."
                echo ""
                init_git_repo "$TARGET_DIR" || true

                # Handle dirty state after conversion
                if is_dirty "$TARGET_DIR"; then
                    if [[ "$KEEP_CHANGES" == true ]]; then
                        echo "  Keeping local changes (--keep)."
                    else
                        echo ""
                        snapshot_and_clean "$TARGET_DIR"
                    fi
                fi
                echo ""
            elif [[ "$FORCE" == true ]]; then
                echo "Warning: Target is not a git repository (no rollback available)"
                echo ""
            else
                echo "ERROR: Target is not a git repository and git is not available."
                echo ""
                exit 1
            fi
        fi

        echo "Running upgrade on existing installation..."
        echo "(To update code first, run: just update)"
        echo ""
        exec "$TARGET_DIR/install.sh" "${PASSTHROUGH_ARGS[@]}" < /dev/tty
    fi

    # Scenario 7 & 8: Curl, fresh install (target empty or no state)
    if [[ "$TARGET_EXISTS" == true ]] && [[ "$TARGET_CONFIGURED" != true ]]; then
        echo "Target exists but is not configured (treating as fresh install)..."
    fi

    # Download dotfiles
    if [[ "$TARGET_EXISTS" == true ]]; then
        echo "Removing existing files at $TARGET_DIR..."
        # cd to safe location in case we're inside the target dir
        cd "$HOME" || cd /tmp
        rm -rf "$TARGET_DIR"
    fi

    if is_git_available; then
        echo "Cloning dotfiles from GitHub..."
        git clone "$REPO_URL" "$TARGET_DIR" < /dev/null
    else
        echo "Downloading dotfiles from GitHub (git not available)..."
        mkdir -p "$TARGET_DIR"
        curl -fsSL "$TARBALL_URL" < /dev/null | tar -xz -C "$TARGET_DIR" --strip-components=1
        echo ""
        echo "Note: Installed without git (no .git directory)"
        echo "      Updates and rollbacks will not be available."
        echo "      After installation, consider re-installing with git."
    fi

    exec "$TARGET_DIR/install.sh" "${PASSTHROUGH_ARGS[@]}" < /dev/tty
fi

## Local scenarios (source != target)

# Scenarios 5 & 6: Target has state - sync code and upgrade
if [[ "$TARGET_CONFIGURED" == true ]]; then
    echo "Target is already configured:"
    describe_state "$TARGET_DIR"
    echo ""

    # Safety checks
    if [[ "$TARGET_IS_DIRTY" == true ]] && [[ "$FORCE" != true ]] && [[ "$KEEP_CHANGES" != true ]]; then
        echo "ERROR: Target has uncommitted changes."
        echo ""
        echo "Options:"
        echo "  1. Commit or stash your changes: cd $TARGET_DIR && git stash"
        echo "  2. Run with --keep to preserve them and proceed"
        echo "  3. Run with --force to skip all safety checks"
        echo ""
        exit 1
    fi

    # Convert tarball installs to git repos when git is now available
    if [[ "$TARGET_HAS_GIT" != true ]]; then
        if is_git_available; then
            echo "Target was installed without git. Converting to git repository..."
            echo ""
            init_git_repo "$TARGET_DIR" || true

            # Handle dirty state after conversion
            if is_dirty "$TARGET_DIR"; then
                if [[ "$KEEP_CHANGES" == true ]]; then
                    echo "  Keeping local changes (--keep)."
                else
                    echo ""
                    snapshot_and_clean "$TARGET_DIR"
                fi
            fi
            echo ""
        elif [[ "$FORCE" == true ]]; then
            echo "Warning: Target is not a git repository (no rollback available)"
            echo ""
        else
            echo "ERROR: Target is not a git repository and git is not available."
            echo ""
            exit 1
        fi
    fi

    echo "Syncing code from source to target (preserving state)..."
    sync_code "$SOURCE_DIR" "$TARGET_DIR"
    echo "  ✓ Code synced"
    echo ""

    exec "$TARGET_DIR/install.sh" "${PASSTHROUGH_ARGS[@]}"
fi

# Scenarios 1-4: Target has no state - fresh install
if [[ "$SOURCE_CONFIGURED" == true ]]; then
    echo "Source is already configured:"
    describe_state "$SOURCE_DIR"
    echo ""
    echo "This state will NOT be copied to the new location by default."
    echo "The new installation will start fresh."
    echo ""

    # Determine whether to copy state
    COPY_STATE=false
    if [[ "$FORCE" == true ]] || [[ "$CLONE" == true ]]; then
        COPY_STATE=true
        echo "Copying state to new location (--force or --clone)..."
    elif prompt_yes_no "Copy state to new location?" "n"; then
        COPY_STATE=true
    fi
    echo ""
fi

# Perform the copy
if [[ "$TARGET_EXISTS" == true ]]; then
    echo "Removing existing files at $TARGET_DIR..."
    # cd to safe location in case we're inside the target dir
    cd "$HOME" || cd /tmp
    rm -rf "$TARGET_DIR"
fi

echo "Copying dotfiles from $SOURCE_DIR to $TARGET_DIR..."
sync_code "$SOURCE_DIR" "$TARGET_DIR"

# Copy .git if source has it
if [[ -d "$SOURCE_DIR/.git" ]]; then
    cp -R "$SOURCE_DIR/.git" "$TARGET_DIR/.git"
    echo "  ✓ Git repository copied"
fi

# Copy state if requested
if [[ "$COPY_STATE" == true ]] && [[ "$SOURCE_CONFIGURED" == true ]]; then
    copy_state "$SOURCE_DIR" "$TARGET_DIR"
    echo "  ✓ State files copied"
fi

echo "  ✓ Copy complete"
echo ""

# Export source dir so install.sh can find .cache/ if present
export DOTFILES_SOURCE_DIR="$SOURCE_DIR"

# Hand off to install.sh
echo "Starting installation..."
exec "$TARGET_DIR/install.sh" "${PASSTHROUGH_ARGS[@]}"
