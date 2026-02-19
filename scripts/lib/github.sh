#!/usr/bin/env bash

# GitHub release helpers for dotfiles scripts
# Source this file: source "$DOTFILES_DIR/scripts/lib/github.sh"
#
# Requires: common.sh sourced first (for log_*, detect_arch)
# Dependencies: curl, tar (both ship with macOS)

# Guard against double-sourcing
[[ -n "$_DOTFILES_LIB_GITHUB_LOADED" ]] && return 0
_DOTFILES_LIB_GITHUB_LOADED=1

# Fetch the latest release tag from a GitHub repository
# Usage: gh_latest_tag <owner/repo>
# Example: gh_latest_tag "charmbracelet/gum"
# Returns: tag name (e.g., "v0.17.0")
gh_latest_tag() {
    local repo="$1"
    local url="https://api.github.com/repos/${repo}/releases/latest"
    local response tag

    if [[ -z "$repo" ]]; then
        log_error "gh_latest_tag: repository required (e.g., owner/repo)"
        return 1
    fi

    if ! command -v curl &>/dev/null; then
        log_error "gh_latest_tag: curl is required"
        return 1
    fi

    response=$(curl -fsSL "$url" 2>/dev/null) || {
        log_error "gh_latest_tag: failed to fetch release info for $repo"
        return 1
    }

    # Extract tag_name from JSON without jq (Bash 3.2 compatible)
    # Matches: "tag_name": "v1.2.3"
    tag=$(echo "$response" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

    if [[ -z "$tag" ]]; then
        log_error "gh_latest_tag: could not parse tag from $repo release"
        return 1
    fi

    echo "$tag"
}

# Fetch the version string (tag with leading 'v' stripped)
# Usage: gh_latest_version <owner/repo>
# Example: gh_latest_version "charmbracelet/gum"  # returns "0.17.0"
gh_latest_version() {
    local tag
    tag=$(gh_latest_tag "$1") || return 1
    echo "${tag#v}"
}

# Build the asset filename for a GitHub release tarball
# Usage: gh_asset_name <name> <version> <os> <arch> [ext]
# Example: gh_asset_name "gum" "0.17.0" "Darwin" "arm64"
# Returns: gum_0.17.0_Darwin_arm64.tar.gz
# The naming convention (name_version_OS_arch.ext) covers most Go/Rust projects
# published via goreleaser or similar tools.
gh_asset_name() {
    local name="$1"
    local version="$2"
    local os="$3"
    local arch="$4"
    local ext="${5:-tar.gz}"

    echo "${name}_${version}_${os}_${arch}.${ext}"
}

# Build the full download URL for a GitHub release asset
# Usage: gh_asset_url <owner/repo> <tag> <asset_filename>
# Example: gh_asset_url "charmbracelet/gum" "v0.17.0" "gum_0.17.0_Darwin_arm64.tar.gz"
gh_asset_url() {
    local repo="$1"
    local tag="$2"
    local asset="$3"

    echo "https://github.com/${repo}/releases/download/${tag}/${asset}"
}

# Download and extract a GitHub release tarball to a target directory
# Usage: gh_download_release <owner/repo> <asset_filename> <tag> <target_dir>
# Example: gh_download_release "charmbracelet/gum" "gum_0.17.0_Darwin_arm64.tar.gz" "v0.17.0" "/usr/local/bin"
# Extracts the tarball into target_dir (creates it if needed)
gh_download_release() {
    local repo="$1"
    local asset="$2"
    local tag="$3"
    local target_dir="$4"
    local url

    if [[ -z "$repo" || -z "$asset" || -z "$tag" || -z "$target_dir" ]]; then
        log_error "gh_download_release: requires <owner/repo> <asset> <tag> <target_dir>"
        return 1
    fi

    url=$(gh_asset_url "$repo" "$tag" "$asset")

    mkdir -p "$target_dir"

    log_info "Downloading $asset from $repo ($tag)..."

    curl -fsSL "$url" | tar -xz -C "$target_dir" || {
        log_error "gh_download_release: failed to download or extract $asset"
        return 1
    }

    log_success "Extracted $asset → $target_dir"
}

# High-level: fetch latest release and install a binary from GitHub
# Usage: gh_install_release <owner/repo> <binary_name> <target_dir> [os] [arch]
# Example: gh_install_release "charmbracelet/gum" "gum" "/usr/local/bin"
# Auto-detects OS and arch if not provided. Downloads, extracts, and verifies
# the binary exists in target_dir.
gh_install_release() {
    local repo="$1"
    local binary_name="$2"
    local target_dir="$3"
    local os="${4:-}"
    local arch="${5:-}"
    local tag version asset

    if [[ -z "$repo" || -z "$binary_name" || -z "$target_dir" ]]; then
        log_error "gh_install_release: requires <owner/repo> <binary_name> <target_dir>"
        return 1
    fi

    # Auto-detect OS
    if [[ -z "$os" ]]; then
        case "$(uname -s)" in
            Darwin) os="Darwin" ;;
            Linux)  os="Linux" ;;
            *)      os="$(uname -s)" ;;
        esac
    fi

    # Auto-detect arch
    if [[ -z "$arch" ]]; then
        arch=$(detect_arch)
    fi

    tag=$(gh_latest_tag "$repo") || return 1
    version="${tag#v}"
    asset=$(gh_asset_name "$binary_name" "$version" "$os" "$arch")

    # Check if already installed at this version
    if [[ -x "$target_dir/$binary_name" ]]; then
        local current_version
        current_version=$("$target_dir/$binary_name" --version 2>/dev/null | sed -n 's/.*[v ]\([0-9][0-9.]*\).*/\1/p' | head -1) || true
        if [[ "$current_version" == "$version" ]]; then
            log_success "$binary_name $version already installed"
            return 0
        fi
    fi

    gh_download_release "$repo" "$asset" "$tag" "$target_dir" || return 1

    if [[ -x "$target_dir/$binary_name" ]]; then
        log_success "$binary_name $version installed → $target_dir/$binary_name"
    else
        log_warn "$binary_name not found in $target_dir after extraction (may need different binary name or nested path)"
    fi
}
