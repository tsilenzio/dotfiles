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

# Apply profile-specific config overrides
# Usage: apply_config_overrides <profile_dir>
apply_config_overrides() {
    local profile_dir="$1"
    local config_dir="$profile_dir/config"

    [[ ! -d "$config_dir" ]] && return 0

    while IFS= read -r -d '' profile_file; do
        local rel_path="${profile_file#"$config_dir"/}"
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

        safe_link "$profile_file" "$dest"
    done < <(find "$config_dir" -type f -print0 2>/dev/null)
}

# ============================================================================
# Profile Management
# ============================================================================
# These functions require PROFILES_DIR to be set before use

# Get profile config value
# Usage: get_profile_conf <profile_id> <key> [default]
get_profile_conf() {
    local profile_id="$1"
    local key="$2"
    local default="${3:-}"
    local conf_file="$PROFILES_DIR/$profile_id/profile.conf"
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

# Check if profile exists and is enabled
# Usage: is_profile_available <profile_id>
is_profile_available() {
    local profile_id="$1"
    local profile_dir="$PROFILES_DIR/$profile_id"

    [[ ! -d "$profile_dir" ]] && return 1

    local enabled
    enabled=$(get_profile_conf "$profile_id" "enabled" "true")
    [[ "$enabled" == "false" ]] && return 1

    return 0
}

# Resolve dependencies for a list of profiles (recursive)
# Usage: resolve_dependencies profile1 profile2 ...
# Outputs: all profiles including dependencies, in dependency order
resolve_dependencies() {
    local -a input_profiles=("$@")
    local -a resolved=()
    local -a seen=()

    # Recursive helper
    resolve_one() {
        local profile="$1"

        # Skip if already resolved
        for p in "${resolved[@]}"; do
            [[ "$p" == "$profile" ]] && return 0
        done

        # Check for circular dependency
        for p in "${seen[@]}"; do
            if [[ "$p" == "$profile" ]]; then
                echo "Error: Circular dependency detected involving '$profile'" >&2
                return 1
            fi
        done

        seen+=("$profile")

        # Verify profile exists
        if ! is_profile_available "$profile"; then
            echo "Error: Profile '$profile' not found or disabled" >&2
            return 1
        fi

        # Get and resolve dependencies first
        local requires
        requires=$(get_profile_conf "$profile" "requires" "")
        if [[ -n "$requires" ]]; then
            IFS=',' read -ra deps <<< "$requires"
            for dep in "${deps[@]}"; do
                dep="${dep// /}"  # Trim whitespace
                [[ -n "$dep" ]] && resolve_one "$dep"
            done
        fi

        # Add this profile after its dependencies
        resolved+=("$profile")
    }

    # Resolve each input profile
    for profile in "${input_profiles[@]}"; do
        resolve_one "$profile" || return 1
    done

    # Output resolved profiles
    printf '%s\n' "${resolved[@]}"
}

# Sort profiles by order
# Usage: sort_by_order < profiles_list
sort_by_order() {
    local -a profiles=()
    while IFS= read -r profile; do
        [[ -n "$profile" ]] && profiles+=("$profile")
    done

    # Build sortable list: order|profile_id
    for profile in "${profiles[@]}"; do
        local order
        order=$(get_profile_conf "$profile" "order" "50")
        echo "$order|$profile"
    done | sort -t'|' -k1 -n | cut -d'|' -f2
}

# Discover available profiles from directory structure
# Returns: profile_id|name|description|order|requires (sorted by order)
# Hidden profiles are excluded unless in SHOW_HIDDEN array
# Requires: PROFILES_DIR, SHOW_HIDDEN (array, optional)
discover_profiles() {
    for profile_dir in "$PROFILES_DIR"/*/; do
        [[ ! -d "$profile_dir" ]] && continue
        local profile_id
        profile_id=$(basename "$profile_dir")

        # Skip if not available (disabled, etc.)
        is_profile_available "$profile_id" || continue

        # Skip hidden profiles unless explicitly shown via SHOW_HIDDEN
        local hidden
        hidden=$(get_profile_conf "$profile_id" "hidden" "false")
        if [[ "$hidden" == "true" ]]; then
            # shellcheck disable=SC2076
            [[ ! " ${SHOW_HIDDEN[*]} " =~ " $profile_id " ]] && continue
        fi

        local name description order requires
        name=$(get_profile_conf "$profile_id" "name" "$profile_id")
        description=$(get_profile_conf "$profile_id" "description" "")
        order=$(get_profile_conf "$profile_id" "order" "50")
        requires=$(get_profile_conf "$profile_id" "requires" "")

        echo "$profile_id|$name|$description|$order|$requires"
    done | sort -t'|' -k4 -n
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
