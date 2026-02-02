#!/usr/bin/env bash
# Platform-specific operations
# Usage: platform.sh <command> [options]

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES_DIR/scripts/lib/common.sh"

OS=$(detect_os)

## Commands

cmd_info() {
    echo "Detected OS: $OS"
    echo "Dotfiles:    $DOTFILES_DIR"
}

cmd_install() {
    case "$OS" in
        macos)
            echo "Running macOS installation..."
            "$DOTFILES_DIR/platforms/macos/install.sh"
            ;;
        linux)
            echo "Running Linux installation..."
            if [[ -f "$DOTFILES_DIR/platforms/linux/install.sh" ]]; then
                "$DOTFILES_DIR/platforms/linux/install.sh"
            else
                echo "Linux installer not yet implemented."
                exit 1
            fi
            ;;
        *)
            echo "Unsupported OS: $OS"
            exit 1
            ;;
    esac
}

cmd_configure() {
    local do_prefs=false
    local do_dock=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --prefs) do_prefs=true; shift ;;
            --dock) do_dock=true; shift ;;
            --help|-h)
                echo "Usage: platform.sh configure [--prefs] [--dock]"
                echo ""
                echo "Options:"
                echo "  --prefs  Apply system preferences"
                echo "  --dock   Configure dock (macOS only)"
                echo ""
                echo "If no options specified, applies all."
                exit 0
                ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    # If neither specified, do all
    if [[ "$do_prefs" == false && "$do_dock" == false ]]; then
        do_prefs=true
        do_dock=true
    fi

    if [[ "$do_prefs" == true ]]; then
        case "$OS" in
            macos)
                echo "Applying macOS preferences..."
                "$DOTFILES_DIR/platforms/macos/preferences.sh"
                ;;
            linux)
                if [[ -f "$DOTFILES_DIR/platforms/linux/preferences.sh" ]]; then
                    echo "Applying Linux preferences..."
                    "$DOTFILES_DIR/platforms/linux/preferences.sh"
                else
                    echo "Linux preferences not yet implemented, skipping."
                fi
                ;;
        esac
    fi

    if [[ "$do_dock" == true ]]; then
        case "$OS" in
            macos)
                echo "Configuring dock..."
                "$DOTFILES_DIR/platforms/macos/dock.sh"
                ;;
            linux)
                echo "Dock configuration is macOS-only, skipping."
                ;;
        esac
    fi
}

cmd_link() {
    echo "Creating symlinks for $OS..."

    ensure_config_dirs
    link_base_configs

    echo ""
    echo "Symlinks complete. Any backups are timestamped with .backup.YYYYMMDD-HHMMSS"
}

## Main

show_help() {
    cat << 'EOF'
Platform-specific operations

Usage: platform.sh <command> [options]

Commands:
  info       Show detected platform info
  install    Run full platform installation
  configure  Configure platform settings (--prefs, --dock)
  link       Create symlinks for config files

Examples:
  platform.sh info
  platform.sh install
  platform.sh configure --prefs
  platform.sh configure --dock
  platform.sh link
EOF
}

case "${1:-}" in
    info) shift; cmd_info "$@" ;;
    install) shift; cmd_install "$@" ;;
    configure) shift; cmd_configure "$@" ;;
    link) shift; cmd_link "$@" ;;
    -h|--help|help) show_help ;;
    "")
        echo "Usage: platform.sh <command> [options]"
        echo "Run 'platform.sh --help' for more information."
        exit 1
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'platform.sh --help' for available commands."
        exit 1
        ;;
esac
