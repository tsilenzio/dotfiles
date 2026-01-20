#!/usr/bin/env bash

# Shared library for dotfiles scripts
# Source this file: source "$DOTFILES_DIR/scripts/lib/common.sh"
#
# Requires DOTFILES_DIR to be set before sourcing

# ============================================================================
# Guard against double-sourcing
# ============================================================================
[[ -n "$_DOTFILES_LIB_COMMON_LOADED" ]] && return 0
_DOTFILES_LIB_COMMON_LOADED=1

# ============================================================================
# Symlink Management
# ============================================================================

# Safe symlink: backup existing file if it's not already pointing to our target
# Usage: safe_link <target> <link_path>
safe_link() {
    local target="$1"
    local link="$2"
    local link_dir
    link_dir=$(dirname "$link")

    mkdir -p "$link_dir"

    if [[ -e "$link" || -L "$link" ]]; then
        if [[ -L "$link" && "$(readlink "$link")" == "$target" ]]; then
            echo "  ✓ $link (already configured)"
            return 0
        fi
        local backup
        backup="${link}.backup.$(date +%Y%m%d-%H%M%S)"
        echo "  ⚠ Backing up $link → $backup"
        mv "$link" "$backup"
    fi

    ln -sf "$target" "$link"
    echo "  ✓ $link → $target"
}

# ============================================================================
# Directory Setup
# ============================================================================

# Create standard config directories with proper permissions
# Usage: ensure_config_dirs
ensure_config_dirs() {
    mkdir -p "$HOME/.config"
    mkdir -p "$HOME/.config/mise"
    mkdir -p "$HOME/.config/wezterm"
    mkdir -p "$HOME/.ssh/sockets"
    mkdir -p "$HOME/.gnupg"
    chmod 700 "$HOME/.ssh"
    chmod 700 "$HOME/.gnupg"
}

# ============================================================================
# Homebrew
# ============================================================================

# Install packages from a Brewfile
# Usage: install_brewfile <brewfile_path>
install_brewfile() {
    local brewfile="$1"

    if [[ ! -f "$brewfile" ]]; then
        echo "No Brewfile found at $brewfile"
        return 0
    fi

    brew bundle --verbose --file="$brewfile" || {
        echo "Warning: Some packages failed to install"
    }
}

# ============================================================================
# Config Symlinks
# ============================================================================

# Link base configs from DOTFILES_DIR/config to home
# Usage: link_base_configs
link_base_configs() {
    local config_dir="$DOTFILES_DIR/config"

    [[ -f "$config_dir/zsh/zshrc" ]] && safe_link "$config_dir/zsh/zshrc" "$HOME/.zshrc"
    [[ -f "$config_dir/zsh/zshenv" ]] && safe_link "$config_dir/zsh/zshenv" "$HOME/.zshenv"
    [[ -f "$config_dir/starship/starship.toml" ]] && safe_link "$config_dir/starship/starship.toml" "$HOME/.config/starship.toml"
    [[ -f "$config_dir/git/gitconfig" ]] && safe_link "$config_dir/git/gitconfig" "$HOME/.gitconfig"
    [[ -f "$config_dir/git/gitignore" ]] && safe_link "$config_dir/git/gitignore" "$HOME/.gitignore"
    [[ -f "$config_dir/mise/config.toml" ]] && safe_link "$config_dir/mise/config.toml" "$HOME/.config/mise/config.toml"
    [[ -f "$config_dir/wezterm/wezterm.lua" ]] && safe_link "$config_dir/wezterm/wezterm.lua" "$HOME/.config/wezterm/wezterm.lua"
    [[ -f "$config_dir/ssh/config" ]] && safe_link "$config_dir/ssh/config" "$HOME/.ssh/config"
    [[ -f "$config_dir/gnupg/gpg-agent.conf" ]] && safe_link "$config_dir/gnupg/gpg-agent.conf" "$HOME/.gnupg/gpg-agent.conf"
}

# Apply bundle-specific config overrides
# Usage: apply_config_overrides <bundle_dir>
apply_config_overrides() {
    local bundle_dir="$1"
    local config_dir="$bundle_dir/config"

    [[ ! -d "$config_dir" ]] && return 0

    while IFS= read -r -d '' bundle_file; do
        local rel_path="${bundle_file#"$config_dir"/}"
        local dest=""

        case "$rel_path" in
            zsh/zshrc)      dest="$HOME/.zshrc" ;;
            zsh/zshenv)     dest="$HOME/.zshenv" ;;
            starship/*)     dest="$HOME/.config/${rel_path}" ;;
            git/gitconfig)  dest="$HOME/.gitconfig" ;;
            git/gitignore)  dest="$HOME/.gitignore" ;;
            mise/*)         dest="$HOME/.config/mise/${rel_path#mise/}" ;;
            wezterm/*)      dest="$HOME/.config/wezterm/${rel_path#wezterm/}" ;;
            ssh/*)          dest="$HOME/.ssh/${rel_path#ssh/}" ;;
            gnupg/*)        dest="$HOME/.gnupg/${rel_path#gnupg/}" ;;
            *)              continue ;;
        esac

        safe_link "$bundle_file" "$dest"
    done < <(find "$config_dir" -type f -print0 2>/dev/null)
}

# ============================================================================
# Bundle Management
# ============================================================================
# These functions require BUNDLES_DIR to be set before use

# Get bundle config value
# Usage: get_bundle_conf <bundle_id> <key> [default]
get_bundle_conf() {
    local bundle_id="$1"
    local key="$2"
    local default="${3:-}"
    local conf_file="$BUNDLES_DIR/$bundle_id/bundle.conf"
    local value="$default"

    if [[ -f "$conf_file" ]]; then
        while IFS='=' read -r k v; do
            [[ -z "$k" || "$k" =~ ^# ]] && continue
            v="${v%\"}"
            v="${v#\"}"
            if [[ "$k" == "$key" ]]; then
                value="$v"
                break
            fi
        done < "$conf_file"
    fi

    echo "$value"
}

# Check if bundle exists and is enabled
# Usage: is_bundle_available <bundle_id>
is_bundle_available() {
    local bundle_id="$1"
    local bundle_dir="$BUNDLES_DIR/$bundle_id"

    [[ ! -d "$bundle_dir" ]] && return 1

    local enabled
    enabled=$(get_bundle_conf "$bundle_id" "enabled" "true")
    [[ "$enabled" == "false" ]] && return 1

    return 0
}

# Resolve dependencies for a list of bundles (recursive)
# Usage: resolve_dependencies bundle1 bundle2 ...
# Outputs: all bundles including dependencies, in dependency order
resolve_dependencies() {
    local -a input_bundles=("$@")
    local -a resolved=()
    local -a seen=()

    # Recursive helper
    resolve_one() {
        local bundle="$1"

        # Skip if already resolved
        for b in "${resolved[@]}"; do
            [[ "$b" == "$bundle" ]] && return 0
        done

        # Check for circular dependency
        for b in "${seen[@]}"; do
            if [[ "$b" == "$bundle" ]]; then
                echo "Error: Circular dependency detected involving '$bundle'" >&2
                return 1
            fi
        done

        seen+=("$bundle")

        # Verify bundle exists
        if ! is_bundle_available "$bundle"; then
            echo "Error: Bundle '$bundle' not found or disabled" >&2
            return 1
        fi

        # Get and resolve dependencies first
        local requires
        requires=$(get_bundle_conf "$bundle" "requires" "")
        if [[ -n "$requires" ]]; then
            IFS=',' read -ra deps <<< "$requires"
            for dep in "${deps[@]}"; do
                dep="${dep// /}"  # Trim whitespace
                [[ -n "$dep" ]] && resolve_one "$dep"
            done
        fi

        # Add this bundle after its dependencies
        resolved+=("$bundle")
    }

    # Resolve each input bundle
    for bundle in "${input_bundles[@]}"; do
        resolve_one "$bundle" || return 1
    done

    # Output resolved bundles
    printf '%s\n' "${resolved[@]}"
}

# Sort bundles by order
# Usage: sort_by_order < bundles_list
sort_by_order() {
    local -a bundles=()
    while IFS= read -r bundle; do
        [[ -n "$bundle" ]] && bundles+=("$bundle")
    done

    # Build sortable list: order|bundle_id
    for bundle in "${bundles[@]}"; do
        local order
        order=$(get_bundle_conf "$bundle" "order" "50")
        echo "$order|$bundle"
    done | sort -t'|' -k1 -n | cut -d'|' -f2
}

# Discover available bundles from directory structure
# Returns: bundle_id|name|description|order|requires (sorted by order)
# Hidden bundles are excluded unless in SHOW_HIDDEN array
# Requires: BUNDLES_DIR, SHOW_HIDDEN (array, optional)
discover_bundles() {
    for bundle_dir in "$BUNDLES_DIR"/*/; do
        [[ ! -d "$bundle_dir" ]] && continue
        local bundle_id
        bundle_id=$(basename "$bundle_dir")

        # Skip if not available (disabled, etc.)
        is_bundle_available "$bundle_id" || continue

        # Skip hidden bundles unless explicitly shown via SHOW_HIDDEN
        local hidden
        hidden=$(get_bundle_conf "$bundle_id" "hidden" "false")
        if [[ "$hidden" == "true" ]]; then
            # shellcheck disable=SC2076
            [[ ! " ${SHOW_HIDDEN[*]} " =~ " $bundle_id " ]] && continue
        fi

        local name description order requires
        name=$(get_bundle_conf "$bundle_id" "name" "$bundle_id")
        description=$(get_bundle_conf "$bundle_id" "description" "")
        order=$(get_bundle_conf "$bundle_id" "order" "50")
        requires=$(get_bundle_conf "$bundle_id" "requires" "")

        echo "$bundle_id|$name|$description|$order|$requires"
    done | sort -t'|' -k4 -n
}

# ============================================================================
# Loaded Bundles Symlinks
# ============================================================================

# Setup the loaded/ directory with symlinks to active bundles
# This enables glob-based auto-discovery: source "$DOTFILES_DIR/loaded/*/config/zsh/*.zsh"
# Usage: setup_loaded_symlinks bundle1 bundle2 ...
# Requires: DOTFILES_DIR, BUNDLES_DIR
setup_loaded_symlinks() {
    local -a bundles=("$@")
    local state_loaded="$DOTFILES_DIR/.state/loaded"
    local root_loaded="$DOTFILES_DIR/loaded"

    # Create .state/loaded/ directory
    mkdir -p "$state_loaded"

    # Create ./loaded symlink to .state/loaded/ if needed
    if [[ -L "$root_loaded" ]]; then
        if [[ "$(readlink "$root_loaded")" != ".state/loaded" ]]; then
            rm -f "$root_loaded"
            ln -s ".state/loaded" "$root_loaded"
        fi
    elif [[ -e "$root_loaded" ]]; then
        # Something else exists there, back it up
        local backup
        backup="${root_loaded}.backup.$(date +%Y%m%d-%H%M%S)"
        mv "$root_loaded" "$backup"
        echo "  ⚠ Backed up existing loaded/ → $backup"
        ln -s ".state/loaded" "$root_loaded"
    else
        ln -s ".state/loaded" "$root_loaded"
    fi

    # Clear existing symlinks in loaded/
    find "$state_loaded" -maxdepth 1 -type l -delete 2>/dev/null || true

    # Create symlinks for each active bundle
    for bundle in "${bundles[@]}"; do
        local bundle_dir="$BUNDLES_DIR/$bundle"
        if [[ -d "$bundle_dir" ]]; then
            ln -sf "$bundle_dir" "$state_loaded/$bundle"
        fi
    done

    echo "  ✓ loaded/ symlinks created for: ${bundles[*]}"
}

# ============================================================================
# Logging
# ============================================================================

# Colored output helpers (only if terminal supports it)
if [[ -t 1 ]]; then
    _GREEN='\033[0;32m'
    _YELLOW='\033[1;33m'
    _BLUE='\033[0;34m'
    _RED='\033[0;31m'
    _NC='\033[0m'
else
    _GREEN=''
    _YELLOW=''
    _BLUE=''
    _RED=''
    _NC=''
fi

log_info()    { echo -e "${_BLUE}[info]${_NC} $1"; }
log_success() { echo -e "${_GREEN}[ok]${_NC} $1"; }
log_warn()    { echo -e "${_YELLOW}[warn]${_NC} $1"; }
log_error()   { echo -e "${_RED}[error]${_NC} $1"; }
