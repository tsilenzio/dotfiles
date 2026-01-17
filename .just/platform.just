# Platform setup module (auto-detects OS)
# Usage: just platform <recipe>

set shell := ["bash", "-cu"]

DOTFILES_DIR := justfile_directory()

# Detect current OS
os := if os() == "macos" { "macos" } else if os() == "linux" { "linux" } else { "unknown" }

# Show platform commands
default:
    @just --list platform

# Show detected platform info
info:
    @echo "Detected OS: {{os}}"
    @echo "Dotfiles:    {{DOTFILES_DIR}}"

# Run full platform installation
install:
    #!/usr/bin/env bash
    set -e
    case "{{os}}" in
        macos)
            echo "Running macOS installation..."
            "{{DOTFILES_DIR}}"/platforms/macos/install.sh
            ;;
        linux)
            echo "Running Linux installation..."
            if [[ -f "{{DOTFILES_DIR}}/platforms/linux/install.sh" ]]; then
                "{{DOTFILES_DIR}}"/platforms/linux/install.sh
            else
                echo "Linux installer not yet implemented."
                exit 1
            fi
            ;;
        *)
            echo "Unsupported OS: {{os}}"
            exit 1
            ;;
    esac

# Configure platform settings
[doc("Configure platform settings. Use --prefs and/or --dock (macOS only), or neither for all.")]
[arg("prefs", long="prefs", value="true")]
[arg("dock", long="dock", value="true")]
configure prefs="" dock="":
    #!/usr/bin/env bash
    set -e

    configure_prefs() {
        case "{{os}}" in
            macos)
                echo "Applying macOS preferences..."
                "{{DOTFILES_DIR}}"/platforms/macos/preferences.sh
                ;;
            linux)
                if [[ -f "{{DOTFILES_DIR}}/platforms/linux/preferences.sh" ]]; then
                    echo "Applying Linux preferences..."
                    "{{DOTFILES_DIR}}"/platforms/linux/preferences.sh
                else
                    echo "Linux preferences not yet implemented, skipping."
                fi
                ;;
        esac
    }

    configure_dock() {
        case "{{os}}" in
            macos)
                echo "Configuring dock..."
                "{{DOTFILES_DIR}}"/platforms/macos/dock.sh
                ;;
            linux)
                echo "Dock configuration is macOS-only, skipping."
                ;;
        esac
    }

    # If neither flag specified, do all
    if [[ -z "{{prefs}}" && -z "{{dock}}" ]]; then
        configure_prefs
        configure_dock
    else
        [[ "{{prefs}}" == "true" ]] && configure_prefs
        [[ "{{dock}}" == "true" ]] && configure_dock
    fi

# Create symlinks for config files
link:
    #!/usr/bin/env bash
    set -e
    echo "Creating symlinks for {{os}}..."

    DOTFILES="{{DOTFILES_DIR}}"

    # Safe symlink: backup existing file if it's not already pointing to our target
    safe_link() {
        local target="$1"
        local link="$2"
        local link_dir=$(dirname "$link")

        # Create parent directory if needed
        mkdir -p "$link_dir"

        # If link exists (file or symlink)
        if [[ -e "$link" || -L "$link" ]]; then
            # If it's already a symlink to our target, skip
            if [[ -L "$link" && "$(readlink "$link")" == "$target" ]]; then
                echo "  ✓ $link (already linked)"
                return 0
            fi
            # Otherwise, backup the existing file/symlink
            local backup="${link}.backup.$(date +%Y%m%d-%H%M%S)"
            echo "  ⚠ Backing up $link → $backup"
            mv "$link" "$backup"
        fi

        # Create the symlink
        ln -sf "$target" "$link"
        echo "  ✓ $link → $target"
    }

    # Create directories
    mkdir -p "$HOME/.config/mise"
    mkdir -p "$HOME/.config/wezterm"
    mkdir -p "$HOME/.ssh/sockets"
    mkdir -p "$HOME/.gnupg"
    chmod 700 "$HOME/.ssh"
    chmod 700 "$HOME/.gnupg"

    # Create symlinks with backup protection
    safe_link "$DOTFILES/config/zsh/zshrc" "$HOME/.zshrc"
    safe_link "$DOTFILES/config/zsh/zshenv" "$HOME/.zshenv"
    safe_link "$DOTFILES/config/starship/starship.toml" "$HOME/.config/starship.toml"
    safe_link "$DOTFILES/config/git/gitconfig" "$HOME/.gitconfig"
    safe_link "$DOTFILES/config/git/gitignore" "$HOME/.gitignore"
    safe_link "$DOTFILES/config/mise/config.toml" "$HOME/.config/mise/config.toml"
    safe_link "$DOTFILES/config/wezterm/wezterm.lua" "$HOME/.config/wezterm/wezterm.lua"
    safe_link "$DOTFILES/config/ssh/config" "$HOME/.ssh/config"
    safe_link "$DOTFILES/config/gnupg/gpg-agent.conf" "$HOME/.gnupg/gpg-agent.conf"

    echo ""
    echo "Symlinks complete. Any backups are timestamped with .backup.YYYYMMDD-HHMMSS"
