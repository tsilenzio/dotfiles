#!/usr/bin/env bash

# Shared library for dotfiles scripts
# Source this file: source "$DOTFILES_DIR/scripts/lib/common.sh"
#
# Requires DOTFILES_DIR to be set before sourcing

# Guard against double-sourcing
[[ -n "$_DOTFILES_LIB_COMMON_LOADED" ]] && return 0
_DOTFILES_LIB_COMMON_LOADED=1

## Symlink Management

# Backup existing file if it's not already pointing to our target
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

## Directory Setup

# Create standard config directories with proper permissions
# Reads @chmod directives from base manifest, also ensures .config and .ssh/sockets
ensure_config_dirs() {
    mkdir -p "$HOME/.config"
    mkdir -p "$HOME/.ssh/sockets"

    local manifest="$DOTFILES_DIR/config/manifest"
    if [[ -f "$manifest" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Strip leading/trailing whitespace
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            case "$line" in
                @chmod\ *) _apply_chmod_directive "$line" ;;
            esac
        done < "$manifest"
    fi
}

## Homebrew

# Install packages from a Brewfile
install_brewfile() {
    local brewfile="$1"

    if [[ ! -f "$brewfile" ]]; then
        echo "No Brewfile found at $brewfile"
        return 0
    fi

    # Dev brew lock: skip installation but show what would change
    if [[ -f "$DOTFILES_DIR/.state/brew.lock" ]]; then
        echo "Brew locked — skipping: $(basename "$brewfile")"
        local check_output
        check_output=$(brew bundle check --file="$brewfile" 2>&1) || true
        if [[ "$check_output" != *"are satisfied"* ]]; then
            echo "  Would change:"
            echo "$check_output" | sed 's/^/    /'
        fi
        return 0
    fi

    brew bundle --verbose --file="$brewfile" || {
        echo "Warning: Some packages failed to install"
    }
}

## Manifest-Driven Config Linking

# Apply a manifest file: link files, recurse directories, set permissions
# Usage: apply_manifest <manifest_file> <source_base_dir>
apply_manifest() {
    local manifest="$1"
    local base_dir="$2"

    [[ ! -f "$manifest" ]] && return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip comments and blank lines
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Directives
        if [[ "$line" == @chmod\ * ]]; then
            _apply_chmod_directive "$line"
            continue
        fi
        if [[ "$line" == @merge\ * || "$line" == @defaults\ * ]]; then
            _apply_merge_directive "$line" "$base_dir"
            continue
        fi

        # Parse: source -> destination
        local src dest
        src="${line%% ->*}"
        dest="${line##*-> }"

        # Strip whitespace from src/dest
        src="${src%"${src##*[![:space:]]}"}"
        dest="${dest#"${dest%%[![:space:]]*}"}"

        # Expand $HOME in destination
        dest="${dest/\$HOME/$HOME}"

        # Directory linking (trailing /)
        if [[ "$src" == */ && "$dest" == */ ]]; then
            _link_directory "$base_dir/$src" "$dest"
            continue
        fi

        # File linking
        local full_src="$base_dir/$src"
        [[ -f "$full_src" ]] && safe_link "$full_src" "$dest"
    done < "$manifest"
}

# Recursively link all files from source directory to destination directory
# Skips .DS_Store files
# Usage: _link_directory <source_dir> <dest_dir>
_link_directory() {
    local src_dir="${1%/}"
    local dest_dir="${2%/}"

    [[ ! -d "$src_dir" ]] && return 0

    while IFS= read -r -d '' file; do
        local rel_path="${file#"$src_dir"}"
        # Skip .DS_Store
        local basename
        basename=$(basename "$file")
        [[ "$basename" == ".DS_Store" ]] && continue

        safe_link "$file" "$dest_dir$rel_path"
    done < <(find "$src_dir" -type f -print0 2>/dev/null)
}

# Parse and apply a @chmod directive
# Usage: _apply_chmod_directive "@chmod 700 $HOME/.ssh"
_apply_chmod_directive() {
    local line="$1"
    local mode path

    # Strip @chmod prefix
    line="${line#@chmod }"
    mode="${line%% *}"
    path="${line#* }"

    # Expand $HOME
    path="${path/\$HOME/$HOME}"

    mkdir -p "$path"
    chmod "$mode" "$path"
}

# Parse and apply a @merge or @defaults directive
# @merge: deep merge, dotfiles values override existing keys
# @defaults: only add keys not already present in target
# Usage: _apply_merge_directive "@merge source -> dest" <base_dir>
_apply_merge_directive() {
    local line="$1"
    local base_dir="$2"
    local mode

    if [[ "$line" == @merge\ * ]]; then
        mode="override"
        line="${line#@merge }"
    else
        mode="defaults"
        line="${line#@defaults }"
    fi

    local src dest
    src="${line%% ->*}"
    dest="${line##*-> }"

    src="${src%"${src##*[![:space:]]}"}"
    dest="${dest#"${dest%%[![:space:]]*}"}"
    dest="${dest/\$HOME/$HOME}"

    local full_src="$base_dir/$src"

    if [[ ! -f "$full_src" ]]; then
        return 0
    fi

    if ! command -v jq &>/dev/null; then
        echo "  ⚠ jq not found, skipping merge for $dest"
        return 0
    fi

    if [[ ! -f "$dest" ]]; then
        mkdir -p "$(dirname "$dest")"
        cp "$full_src" "$dest"
        echo "  ✓ $dest (created)"
        return 0
    fi

    local merged
    if [[ "$mode" == "override" ]]; then
        # Target * Source: source keys win
        merged=$(jq -s '.[0] * .[1]' "$dest" "$full_src" 2>/dev/null)
    else
        # Source * Target: existing keys win
        merged=$(jq -s '.[0] * .[1]' "$full_src" "$dest" 2>/dev/null)
    fi

    if [[ -n "$merged" ]]; then
        echo "$merged" > "$dest"
        echo "  ✓ $dest (merged, mode: $mode)"
    else
        echo "  ⚠ Failed to merge $dest, skipping"
    fi
}

## Config Symlinks

# Link base configs from DOTFILES_DIR/config to home
link_base_configs() {
    apply_manifest "$DOTFILES_DIR/config/manifest" "$DOTFILES_DIR/config"
}

# Apply bundle-specific config overrides
# Checks for bundle manifest first, falls back to legacy case-statement
apply_config_overrides() {
    local bundle_dir="$1"

    # Manifest-based: bundle has its own manifest file
    if [[ -f "$bundle_dir/manifest" ]]; then
        apply_manifest "$bundle_dir/manifest" "$DOTFILES_DIR/config"
        return 0
    fi

    # Legacy: scan bundle config/ directory with case-statement mapping
    _apply_config_overrides_legacy "$bundle_dir"
}

# Legacy config override logic for bundles without a manifest
_apply_config_overrides_legacy() {
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
            atuin/*)        dest="$HOME/.config/atuin/${rel_path#atuin/}" ;;
            ghostty/*)      dest="$HOME/.config/ghostty/${rel_path#ghostty/}" ;;
            wezterm/*)      dest="$HOME/.config/wezterm/${rel_path#wezterm/}" ;;
            ssh/*)          dest="$HOME/.ssh/${rel_path#ssh/}" ;;
            gnupg/*)        dest="$HOME/.gnupg/${rel_path#gnupg/}" ;;
            *)              continue ;;
        esac

        safe_link "$bundle_file" "$dest"
    done < <(find "$config_dir" -type f -print0 2>/dev/null)
}

## Bundle Management (requires BUNDLES_DIR)

# Get bundle config value: get_bundle_conf <bundle_id> <key> [default]
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
is_bundle_available() {
    local bundle_id="$1"
    local bundle_dir="$BUNDLES_DIR/$bundle_id"

    [[ ! -d "$bundle_dir" ]] && return 1

    local enabled
    enabled=$(get_bundle_conf "$bundle_id" "enabled" "true")
    [[ "$enabled" == "false" ]] && return 1

    return 0
}

# Resolve dependencies recursively, returns bundles in dependency order
resolve_dependencies() {
    local -a input_bundles=("$@")
    local -a resolved=()
    local -a seen=()

    resolve_one() {
        local bundle="$1"

        for b in "${resolved[@]}"; do
            [[ "$b" == "$bundle" ]] && return 0
        done

        # Circular dependency check
        for b in "${seen[@]}"; do
            if [[ "$b" == "$bundle" ]]; then
                echo "Error: Circular dependency detected involving '$bundle'" >&2
                return 1
            fi
        done

        seen+=("$bundle")

        if ! is_bundle_available "$bundle"; then
            echo "Error: Bundle '$bundle' not found or disabled" >&2
            return 1
        fi

        # Resolve dependencies first
        local requires
        requires=$(get_bundle_conf "$bundle" "requires" "")
        if [[ -n "$requires" ]]; then
            IFS=',' read -ra deps <<< "$requires"
            for dep in "${deps[@]}"; do
                dep="${dep// /}"  # Trim whitespace
                [[ -n "$dep" ]] && resolve_one "$dep"
            done
        fi

        resolved+=("$bundle")
    }

    for bundle in "${input_bundles[@]}"; do
        resolve_one "$bundle" || return 1
    done

    printf '%s\n' "${resolved[@]}"
}

# Sort bundles by order field (pipe bundle list to this function)
sort_by_order() {
    local -a bundles=()
    while IFS= read -r bundle; do
        [[ -n "$bundle" ]] && bundles+=("$bundle")
    done

    for bundle in "${bundles[@]}"; do
        local order
        order=$(get_bundle_conf "$bundle" "order" "50")
        echo "$order|$bundle"
    done | sort -t'|' -k1 -n | cut -d'|' -f2
}

# Discover available bundles, returns: bundle_id|name|description|order|requires
# Hidden bundles excluded unless in REVEALED array
discover_bundles() {
    for bundle_dir in "$BUNDLES_DIR"/*/; do
        [[ ! -d "$bundle_dir" ]] && continue
        local bundle_id
        bundle_id=$(basename "$bundle_dir")

        is_bundle_available "$bundle_id" || continue

        # Skip hidden bundles unless revealed
        local hidden
        hidden=$(get_bundle_conf "$bundle_id" "hidden" "false")
        if [[ "$hidden" == "true" ]]; then
            # shellcheck disable=SC2076
            [[ ! " ${REVEALED[*]} " =~ " $bundle_id " ]] && continue
        fi

        local name description order requires
        name=$(get_bundle_conf "$bundle_id" "name" "$bundle_id")
        description=$(get_bundle_conf "$bundle_id" "description" "")
        order=$(get_bundle_conf "$bundle_id" "order" "50")
        requires=$(get_bundle_conf "$bundle_id" "requires" "")

        echo "$bundle_id|$name|$description|$order|$requires"
    done | sort -t'|' -k4 -n
}

## Loaded Bundles Symlinks

# Setup loaded/ directory with symlinks to active bundles for glob-based auto-discovery
setup_loaded_symlinks() {
    local -a bundles=("$@")
    local state_loaded="$DOTFILES_DIR/.state/loaded"
    local root_loaded="$DOTFILES_DIR/loaded"

    mkdir -p "$state_loaded"

    # Create ./loaded symlink to .state/loaded/
    if [[ -L "$root_loaded" ]]; then
        if [[ "$(readlink "$root_loaded")" != ".state/loaded" ]]; then
            rm -f "$root_loaded"
            ln -s ".state/loaded" "$root_loaded"
        fi
    elif [[ -e "$root_loaded" ]]; then
        local backup
        backup="${root_loaded}.backup.$(date +%Y%m%d-%H%M%S)"
        mv "$root_loaded" "$backup"
        echo "  ⚠ Backed up existing loaded/ → $backup"
        ln -s ".state/loaded" "$root_loaded"
    else
        ln -s ".state/loaded" "$root_loaded"
    fi

    find "$state_loaded" -maxdepth 1 -type l -delete 2>/dev/null || true

    for bundle in "${bundles[@]}"; do
        local bundle_dir="$BUNDLES_DIR/$bundle"
        if [[ -d "$bundle_dir" ]]; then
            ln -sf "$bundle_dir" "$state_loaded/$bundle"
        fi
    done

    echo "  ✓ loaded/ symlinks created for: ${bundles[*]}"
}

## Snapshots

# Create a rollback snapshot (git tag + state snapshot)
# Usage: create_snapshot [tag_prefix]
# Sets: SNAPSHOT_TIMESTAMP, SNAPSHOT_TAG_NAME
SNAPSHOT_TIMESTAMP=""
SNAPSHOT_TAG_NAME=""

create_snapshot() {
    local prefix="${1:-pre-change}"
    SNAPSHOT_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    local tag_name="$prefix/$SNAPSHOT_TIMESTAMP"
    local snapshot_dir="$DOTFILES_DIR/.state/snapshots/$SNAPSHOT_TIMESTAMP"
    local git_hash

    echo "Creating rollback point: $tag_name"

    # Only create git tag if in a git repo
    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        git_hash=$(git -C "$DOTFILES_DIR" rev-parse HEAD)
        git -C "$DOTFILES_DIR" tag --no-sign "$tag_name" 2>/dev/null || true
    else
        git_hash="none"
    fi

    mkdir -p "$snapshot_dir"

    # Snapshot current brew state
    if command -v brew &>/dev/null; then
        echo "Saving brew snapshot..."
        brew bundle dump --file="$snapshot_dir/Brewfile" --force 2>/dev/null || true
    fi

    # Snapshot current bundles
    if [[ -f "$DOTFILES_DIR/.bundles" ]]; then
        cp "$DOTFILES_DIR/.bundles" "$snapshot_dir/bundles"
    fi

    # Create metadata
    cat > "$snapshot_dir/metadata.json" << EOF
{
  "timestamp": "$SNAPSHOT_TIMESTAMP",
  "git_hash": "$git_hash",
  "git_tag": "$tag_name",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

    echo "Snapshot saved: .state/snapshots/$SNAPSHOT_TIMESTAMP/"

    # Set result variable for caller
    # shellcheck disable=SC2034
    SNAPSHOT_TAG_NAME="$tag_name"
}

## Logging (colors disabled if not a terminal)
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

## Cloud Storage

CLOUD_DOTFILES_SUBDIR=".dotfiles"

# Discover available cloud storage roots (checked in priority order)
get_cloud_roots() {
    local roots=()

    # Dropbox
    [[ -d "$HOME/Dropbox" ]] && roots+=("$HOME/Dropbox")

    # Google Drive (new location)
    for dir in "$HOME/Library/CloudStorage"/GoogleDrive-*/; do
        [[ -d "${dir}My Drive" ]] && roots+=("${dir}My Drive")
    done
    # Google Drive (legacy location)
    [[ -d "$HOME/Google Drive" ]] && roots+=("$HOME/Google Drive")

    # OneDrive (new location)
    for dir in "$HOME/Library/CloudStorage"/OneDrive-*/; do
        [[ -d "$dir" ]] && roots+=("${dir%/}")
    done
    # OneDrive (legacy location)
    [[ -d "$HOME/OneDrive" ]] && roots+=("$HOME/OneDrive")

    # iCloud (last)
    [[ -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ]] && \
        roots+=("$HOME/Library/Mobile Documents/com~apple~CloudDocs")

    printf '%s\n' "${roots[@]}"
}

# Expand shorthand cloud provider names to full paths
expand_cloud_shorthand() {
    local input="$1"

    case "$input" in
        icloud)
            echo "$HOME/Library/Mobile Documents/com~apple~CloudDocs"
            ;;
        dropbox)
            echo "$HOME/Dropbox"
            ;;
        gdrive|google)
            for dir in "$HOME/Library/CloudStorage"/GoogleDrive-*/; do
                if [[ -d "${dir}My Drive" ]]; then
                    echo "${dir}My Drive"
                    return 0
                fi
            done
            [[ -d "$HOME/Google Drive" ]] && echo "$HOME/Google Drive" && return 0
            echo "$input"
            ;;
        onedrive)
            for dir in "$HOME/Library/CloudStorage"/OneDrive-*/; do
                if [[ -d "$dir" ]]; then
                    echo "${dir%/}"
                    return 0
                fi
            done
            [[ -d "$HOME/OneDrive" ]] && echo "$HOME/OneDrive" && return 0
            echo "$input"
            ;;
        *)
            echo "$input"
            ;;
    esac
}

# Show available cloud shorthands
show_cloud_shorthands() {
    echo "Available shorthands:"
    echo "  icloud   → iCloud Drive"
    echo "  dropbox  → Dropbox"
    echo "  gdrive   → Google Drive"
    echo "  onedrive → OneDrive"
    echo ""
    echo "Or specify a custom path directly."
}

# Find the cloud .dotfiles directory
# Usage: find_cloud_dir
find_cloud_dir() {
    local roots
    roots=$(get_cloud_roots)

    while IFS= read -r root; do
        [[ -z "$root" ]] && continue
        local cloud_dir="$root/$CLOUD_DOTFILES_SUBDIR"
        if [[ -d "$cloud_dir" ]]; then
            echo "$cloud_dir"
            return 0
        fi
    done <<< "$roots"

    return 1
}

## Platform Detection

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux) echo "linux" ;;
        *) echo "unknown" ;;
    esac
}

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }

## Architecture Detection

# Detect CPU architecture, normalized to GitHub release naming conventions
# Returns: arm64, x86_64, armv6, armv7, i386
detect_arch() {
    local machine
    machine="$(uname -m)"
    case "$machine" in
        aarch64|arm64) echo "arm64" ;;
        x86_64|amd64)  echo "x86_64" ;;
        armv6*)        echo "armv6" ;;
        armv7*)        echo "armv7" ;;
        i386|i686)     echo "i386" ;;
        *)             echo "$machine" ;;
    esac
}

## Gum (TUI helper — auto-downloaded and cached)

GUM_VERSION="0.17.0"
GUM_CACHE_DIR="$DOTFILES_DIR/.cache"

# Ensure gum is available: system PATH → cache → download.
# On success: sets GUM_BIN to the resolved path, adds to PATH, returns 0.
# On failure: logs reason to stderr, returns 1.
GUM_BIN=""

ensure_gum() {
    # Already in PATH
    local found
    found=$(command -v gum 2>/dev/null) && { GUM_BIN="$found"; return 0; }

    # Check cache
    if [[ -x "$GUM_CACHE_DIR/gum" ]]; then
        GUM_BIN="$GUM_CACHE_DIR/gum"
        export PATH="$GUM_CACHE_DIR:$PATH"
        return 0
    fi

    # Non-interactive — can't prompt for download
    if [[ ! -t 0 ]]; then
        log_warn "gum not available (non-interactive session)" >&2
        return 1
    fi

    # Source GitHub release helpers for download
    # shellcheck source=scripts/lib/github.sh
    source "$DOTFILES_DIR/scripts/lib/github.sh"

    log_info "Downloading gum v${GUM_VERSION}..."
    local arch asset tag url
    arch=$(detect_arch)
    tag="v${GUM_VERSION}"
    asset=$(gh_asset_name "gum" "$GUM_VERSION" "Darwin" "$arch")
    url=$(gh_asset_url "charmbracelet/gum" "$tag" "$asset")

    mkdir -p "$GUM_CACHE_DIR"
    if curl -fsSL "$url" | tar xz --strip-components=1 -C "$GUM_CACHE_DIR" 2>/dev/null; then
        chmod +x "$GUM_CACHE_DIR/gum"
        GUM_BIN="$GUM_CACHE_DIR/gum"
        export PATH="$GUM_CACHE_DIR:$PATH"
        log_success "Cached gum v${GUM_VERSION} at $GUM_BIN"
        return 0
    fi

    log_error "Failed to download gum v${GUM_VERSION} from GitHub" >&2
    return 1
}
