#!/usr/bin/env bash

# Preview a PR, branch, or commit with snapshot-backed state preservation
# Usage: rune dev preview [--pr N | --branch NAME | --commit HASH | <target>]
#        rune dev preview --restore
#        rune dev preview --status

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_DIR="$(dirname "$SCRIPT_DIR")"
DOTFILES_DIR="$(dirname "$DEV_DIR")"
export DOTFILES_DIR
cd "$DOTFILES_DIR"

# Source dev lib (create_logger) and main lib (create_snapshot)
source "$SCRIPT_DIR/lib/common.sh"
source "$DOTFILES_DIR/scripts/lib/common.sh"
create_logger "preview"

STATE_FILE="$DOTFILES_DIR/.state/preview"

# --- State helpers ---

preview_state_get() {
    local key="$1"
    [[ ! -f "$STATE_FILE" ]] && return 0
    while IFS='=' read -r k v; do
        [[ -z "$k" || "$k" =~ ^# ]] && continue
        if [[ "$k" == "$key" ]]; then
            echo "$v"
            return 0
        fi
    done < "$STATE_FILE"
}

preview_state_write() {
    mkdir -p "$(dirname "$STATE_FILE")"
    cat > "$STATE_FILE" << EOF
branch=$1
stash=$2
snapshot=$3
target=$4
started=$5
last_active=$5
EOF
}

preview_state_clear() {
    rm -f "$STATE_FILE"
}

# --- Prerequisite checks ---

require_gh() {
    if ! command -v gh &>/dev/null; then
        log "gh CLI not found. Install via the develop bundle:"
        log "  ./install.sh --select develop"
        exit 1
    fi
    if ! gh auth status &>/dev/null 2>&1; then
        log "gh CLI not authenticated. Run: gh auth login"
        exit 1
    fi
}

validate_pr_author() {
    local pr_num="$1"
    local pr_author current_user
    pr_author=$(gh pr view "$pr_num" --json author --jq '.author.login' 2>/dev/null) || {
        warn "Could not fetch PR #$pr_num"
        exit 1
    }
    current_user=$(gh api user --jq '.login' 2>/dev/null) || {
        warn "Could not determine current GitHub user"
        exit 1
    }
    if [[ "$pr_author" != "$current_user" ]]; then
        warn "PR #$pr_num belongs to '$pr_author' (you are '$current_user')"
        warn "Only your own PRs can be previewed for safety."
        exit 1
    fi
}

# --- Smart detection ---

smart_detect() {
    local input="$1"
    local matches=()

    # Pure digits → check PR first, then git hash
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        if gh pr view "$input" &>/dev/null 2>&1; then
            matches+=("pr:$input")
        fi
        if git cat-file -t "$input" &>/dev/null 2>&1; then
            matches+=("commit:$input")
        fi
    # Hex-only 7+ chars → check git hash first, then branch
    elif [[ "$input" =~ ^[0-9a-f]{7,}$ ]]; then
        if git cat-file -t "$input" &>/dev/null 2>&1; then
            matches+=("commit:$input")
        fi
        if git ls-remote --heads origin "$input" 2>/dev/null | grep -q .; then
            matches+=("branch:$input")
        fi
    # Contains / or non-hex letters → branch
    else
        if git ls-remote --heads origin "$input" 2>/dev/null | grep -q .; then
            matches+=("branch:$input")
        fi
        # Also try as PR number just in case
        if [[ "$input" =~ ^[0-9]+$ ]] && gh pr view "$input" &>/dev/null 2>&1; then
            matches+=("pr:$input")
        fi
    fi

    if [[ ${#matches[@]} -eq 0 ]]; then
        warn "Could not resolve '$input' as a PR, branch, or commit"
        exit 1
    elif [[ ${#matches[@]} -eq 1 ]]; then
        echo "${matches[0]}"
    else
        log "Ambiguous target '$input'. Multiple matches:"
        for i in "${!matches[@]}"; do
            echo "  $((i+1))) ${matches[$i]}"
        done
        echo ""
        read -r -p "Select [1-${#matches[@]}]: " sel
        if [[ ! "$sel" =~ ^[0-9]+$ ]] || [[ "$sel" -lt 1 ]] || [[ "$sel" -gt ${#matches[@]} ]]; then
            warn "Invalid selection"
            exit 1
        fi
        echo "${matches[$((sel-1))]}"
    fi
}

# --- Core flows ---

start_preview() {
    local target_type="$1"
    local target_value="$2"
    local now
    now=$(date +%s)

    # Validate PR author
    if [[ "$target_type" == "pr" ]]; then
        require_gh
        validate_pr_author "$target_value"
    fi

    # Save current branch
    local original_branch
    original_branch=$(git symbolic-ref --short HEAD 2>/dev/null) || {
        warn "Cannot start preview from detached HEAD"
        exit 1
    }

    # Stash if dirty
    local stash_ref=""
    if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
        local stash_msg="rune-preview/$now"
        log "Stashing uncommitted changes..."
        git stash push -u -m "$stash_msg"
        stash_ref="$stash_msg"
    fi

    # Create snapshot
    create_snapshot "pre-preview"
    local snapshot_tag="$SNAPSHOT_TAG_NAME"

    # Checkout target
    case "$target_type" in
        pr)
            log "Checking out PR #$target_value..."
            gh pr checkout "$target_value"
            ;;
        branch)
            log "Checking out branch: $target_value..."
            git fetch origin "$target_value"
            git checkout "$target_value"
            ;;
        commit)
            log "Checking out commit: $target_value..."
            git checkout "$target_value"
            ;;
    esac

    # Auto-lock brew during preview
    if [[ ! -f "$DOTFILES_DIR/.state/brew.lock" ]]; then
        mkdir -p "$DOTFILES_DIR/.state"
        touch "$DOTFILES_DIR/.state/brew.lock"
        log "Brew auto-locked for preview"
    fi

    # Write state
    preview_state_write "$original_branch" "$stash_ref" "$snapshot_tag" "$target_type:$target_value" "$now"

    echo ""
    log "Preview active: $target_type:$target_value"
    info "  Run 'rune upgrade' to apply changes (brew: locked)"
    info "  Run 'rune dev preview --restore' when done."
}

update_preview() {
    local target_type="$1"
    local target_value="$2"

    case "$target_type" in
        pr)
            require_gh
            log "Updating PR #$target_value..."
            gh pr checkout "$target_value" --force
            ;;
        branch)
            log "Updating branch: $target_value..."
            git fetch origin "$target_value"
            git merge --ff-only "origin/$target_value" || {
                warn "Cannot fast-forward. Branch has diverged."
                warn "Use --restore first, then start a new preview."
                exit 1
            }
            ;;
        commit)
            info "Commit targets are immutable — nothing to update."
            ;;
    esac

    log "Preview updated: $target_type:$target_value"
}

do_restore() {
    if [[ ! -f "$STATE_FILE" ]]; then
        warn "No active preview to restore"
        exit 1
    fi

    local original_branch stash_ref
    original_branch=$(preview_state_get "branch")
    stash_ref=$(preview_state_get "stash")

    if [[ -z "$original_branch" ]]; then
        warn "State file is corrupt (missing branch). Clearing state."
        preview_state_clear
        exit 1
    fi

    # Checkout original branch
    log "Restoring to branch: $original_branch..."
    git checkout "$original_branch"

    # Pop stash if we saved one
    if [[ -n "$stash_ref" ]]; then
        # Find stash by message — index may have shifted
        local stash_index
        stash_index=$(git stash list | grep -F "$stash_ref" | head -1 | cut -d: -f1)
        if [[ -n "$stash_index" ]]; then
            log "Restoring stashed changes..."
            git stash pop "$stash_index" || {
                warn "Stash pop had conflicts. Resolve manually."
                warn "Your changes are in the stash: $stash_index"
            }
        else
            warn "Stash '$stash_ref' not found (may have been manually dropped)"
        fi
    fi

    # Remove brew lock if we set it (check if preview was the one that locked)
    if [[ -f "$DOTFILES_DIR/.state/brew.lock" ]]; then
        rm -f "$DOTFILES_DIR/.state/brew.lock"
        log "Brew unlocked"
    fi

    preview_state_clear
    log "Preview restored. Back on: $original_branch"
}

do_status() {
    if [[ ! -f "$STATE_FILE" ]]; then
        info "No active preview"
        exit 0
    fi

    local target original_branch stash snapshot started
    target=$(preview_state_get "target")
    original_branch=$(preview_state_get "branch")
    stash=$(preview_state_get "stash")
    snapshot=$(preview_state_get "snapshot")
    started=$(preview_state_get "started")

    local target_type target_value
    target_type="${target%%:*}"
    target_value="${target#*:}"

    local current_head
    current_head=$(git rev-parse --short HEAD)

    echo "Preview status:"
    echo "  Target:     $target"
    echo "  Original:   $original_branch"
    echo "  Snapshot:   $snapshot"
    echo "  Stash:      ${stash:-none}"
    echo "  Current:    $current_head"
    if [[ -n "$started" ]]; then
        echo "  Started:    $(date -r "$started" '+%Y-%m-%d %H:%M:%S')"
    fi
    echo "  Brew:       $(test -f "$DOTFILES_DIR/.state/brew.lock" && echo 'locked' || echo 'unlocked')"

    # Check if behind remote
    case "$target_type" in
        pr)
            if command -v gh &>/dev/null; then
                local remote_head
                remote_head=$(gh pr view "$target_value" --json headRefOid --jq '.headRefOid' 2>/dev/null) || true
                if [[ -n "$remote_head" ]]; then
                    local local_full
                    local_full=$(git rev-parse HEAD)
                    if [[ "$local_full" != "$remote_head" ]]; then
                        echo ""
                        warn "PR has newer commits. Run 'rune dev preview $target_value' to update."
                    fi
                fi
            fi
            ;;
        branch)
            git fetch origin "$target_value" &>/dev/null 2>&1 || true
            local local_head remote_head
            local_head=$(git rev-parse HEAD)
            remote_head=$(git rev-parse "origin/$target_value" 2>/dev/null) || true
            if [[ -n "$remote_head" && "$local_head" != "$remote_head" ]]; then
                echo ""
                warn "Branch has newer commits. Run 'rune dev preview $target_value' to update."
            fi
            ;;
    esac
}

# --- Argument parsing ---

MODE=""
TARGET_TYPE=""
TARGET_VALUE=""
POSITIONAL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --restore)
            MODE="restore"
            shift
            ;;
        --status)
            MODE="status"
            shift
            ;;
        --pr)
            TARGET_TYPE="pr"
            if [[ "$2" =~ ^[^-] ]]; then
                TARGET_VALUE="$2"
                shift 2
            else
                warn "--pr requires a PR number"
                exit 1
            fi
            ;;
        --pr=*)
            TARGET_TYPE="pr"
            TARGET_VALUE="${1#--pr=}"
            shift
            ;;
        --branch)
            TARGET_TYPE="branch"
            if [[ "$2" =~ ^[^-] ]]; then
                TARGET_VALUE="$2"
                shift 2
            else
                warn "--branch requires a branch name"
                exit 1
            fi
            ;;
        --branch=*)
            TARGET_TYPE="branch"
            TARGET_VALUE="${1#--branch=}"
            shift
            ;;
        --commit)
            TARGET_TYPE="commit"
            if [[ "$2" =~ ^[^-] ]]; then
                TARGET_VALUE="$2"
                shift 2
            else
                warn "--commit requires a commit hash"
                exit 1
            fi
            ;;
        --commit=*)
            TARGET_TYPE="commit"
            TARGET_VALUE="${1#--commit=}"
            shift
            ;;
        -*)
            warn "Unknown flag: $1"
            echo "Usage: rune dev preview [--pr N | --branch NAME | --commit HASH | <target>]"
            echo "       rune dev preview --restore"
            echo "       rune dev preview --status"
            exit 1
            ;;
        *)
            POSITIONAL="$1"
            shift
            ;;
    esac
done

# --- Dispatch ---

case "$MODE" in
    restore)
        do_restore
        exit 0
        ;;
    status)
        do_status
        exit 0
        ;;
esac

# Need a target for start/update
if [[ -z "$TARGET_TYPE" && -z "$POSITIONAL" ]]; then
    if [[ -f "$STATE_FILE" ]]; then
        do_status
    else
        echo "Usage: rune dev preview [--pr N | --branch NAME | --commit HASH | <target>]"
        echo "       rune dev preview --restore"
        echo "       rune dev preview --status"
        echo ""
        echo "Examples:"
        echo "  rune dev preview 42         # Smart detect: PR #42"
        echo "  rune dev preview feat/foo   # Smart detect: branch"
        echo "  rune dev preview abc1234    # Smart detect: commit"
        echo "  rune dev preview --pr 42    # Explicit PR"
    fi
    exit 0
fi

# Smart detect if positional arg given
if [[ -z "$TARGET_TYPE" && -n "$POSITIONAL" ]]; then
    # For smart detection on PRs, we need gh
    require_gh
    detected=$(smart_detect "$POSITIONAL")
    TARGET_TYPE="${detected%%:*}"
    TARGET_VALUE="${detected#*:}"
fi

# Check for active preview
if [[ -f "$STATE_FILE" ]]; then
    active_target=$(preview_state_get "target")
    if [[ "$active_target" == "$TARGET_TYPE:$TARGET_VALUE" ]]; then
        # Same target — update
        update_preview "$TARGET_TYPE" "$TARGET_VALUE"
    else
        # Different target — restore first, then start new
        log "Switching preview: $active_target → $TARGET_TYPE:$TARGET_VALUE"
        do_restore
        echo ""
        start_preview "$TARGET_TYPE" "$TARGET_VALUE"
    fi
else
    start_preview "$TARGET_TYPE" "$TARGET_VALUE"
fi
