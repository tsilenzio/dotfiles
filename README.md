# Dotfiles

Personal dotfiles for macOS with multi-bundle support.

## Quick Start

```bash
# Fresh install (interactive bundle selection)
curl -fsSL https://raw.githubusercontent.com/tsilenzio/dotfiles/main/bootstrap.sh | bash

# Non-interactive with specific bundles
curl -fsSL https://... | bash -s -- --select core --select personal
```

Or manually:

```bash
git clone https://github.com/tsilenzio/dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

## What's Included

- **Zsh** configuration with Starship prompt
- **Git** config with delta diffs and GPG signing
- **Ghostty** terminal configuration (with WezTerm fallback)
- **Homebrew** packages organized by bundle
- **macOS** preferences automation
- **Dock** customization
- **Secrets** management with age encryption and cloud backup
- **License** management for installed applications

## Bundles

Bundles are modular configurations with automatic dependency resolution:

| Bundle | Description | Requires |
|--------|-------------|----------|
| `core` | Essential tools and base configuration | - |
| `develop` | Development tools, IDEs, and programming utilities | core |
| `personal` | Gaming, entertainment, and personal apps | core |
| `work` | Office communication and productivity | core |
| `test` | Minimal packages for VM testing (hidden) | - |

**Example combinations:**
- Personal machine: `--select personal` (auto-includes core)
- Work machine: `--select work --select develop` (auto-includes core)
- Full setup: `--select personal --select work --select develop`

## Commands

This repo uses [just](https://github.com/casey/just) for common tasks:

```bash
just                  # Show available commands
just install          # Run full installation
just upgrade          # Re-apply bundles (packages + symlinks + preferences/dock prompts)
just update           # Pull latest changes (creates rollback point)
just update --keep    # Pull latest, preserve uncommitted changes
just history          # Show available rollback points
just rollback [id]    # Rollback to previous state
just rollback [id] --with-brew  # Also rollback packages
just rollback [id] --dry-run    # Preview changes
just licenses         # Manage application licenses
just manifest ...     # Manage config manifest (add, remove, list)
just secrets ...      # Secrets management (init, backup, restore)
```

## Structure

```
~/.dotfiles/
├── config/                    # Base configurations
│   ├── manifest              # Declares what gets linked where
│   ├── ghostty/
│   ├── git/
│   ├── gnupg/
│   ├── mise/
│   ├── ssh/
│   ├── starship/
│   ├── wezterm/
│   └── zsh/
├── platforms/
│   └── macos/
│       ├── bin/                # Platform scripts (on PATH)
│       ├── secrets/            # Platform-level encrypted secrets
│       ├── bundles/           # Bundle-specific setup
│       │   ├── core/
│       │   │   ├── Brewfile
│       │   │   ├── bundle.conf
│       │   │   ├── setup.sh
│       │   │   └── manifest      # (optional) Config links
│       │   ├── develop/
│       │   ├── personal/
│       │   ├── work/
│       │   └── test/
│       ├── install              # macOS platform installer
│       ├── preflight            # Sudo caching / preflight checks
│       ├── preferences          # macOS system preferences
│       └── dock                 # Dock layout configuration
├── scripts/
│   ├── lib/
│   │   └── common.sh         # Shared library (logging, symlinks, bundles)
│   ├── upgrade                # Re-apply bundles
│   ├── update                 # Pull + snapshot
│   ├── rollback               # Revert to snapshot
│   ├── history                # List rollback points
│   ├── secrets                # Secrets management (backup/restore/encrypt)
│   ├── secrets-init           # Initialize encryption
│   ├── licenses               # License manager (Python)
│   ├── daemons                # Daemon/agent manager (Python)
│   ├── manifest               # Manifest management (add/remove/list)
│   └── platform               # Platform operations (configure/link)
├── secrets/                   # Encrypted secrets (age)
├── loaded/                    # Symlinks to active bundles (for glob discovery)
├── bootstrap.sh
└── install.sh
```

## Adding a Bundle

1. Create a new directory under `platforms/macos/bundles/`:

```bash
mkdir -p platforms/macos/bundles/mybundle
```

2. Add `bundle.conf`:

```bash
name="My Bundle"
description="Description of this bundle"
order=30
requires="core"  # Optional: comma-separated dependencies
```

3. Add `Brewfile` with packages:

```ruby
brew "some-package"
cask "some-app"
```

4. Add `setup.sh`:

```bash
#!/usr/bin/env bash
set -e
MODE="${1:-install}"

# Load shared library
source "$DOTFILES_DIR/scripts/lib/common.sh"

echo "Running mybundle setup ($MODE)..."

# Install Brewfile
install_brewfile "$BUNDLE_DIR/Brewfile"

# Apply config overrides (if bundle has config/ directory)
apply_config_overrides "$BUNDLE_DIR"

# Add custom setup here
```

5. Make it executable:

```bash
chmod +x platforms/macos/bundles/mybundle/setup.sh
```

6. (Optional) Add a `manifest` file for config linking instead of hardcoding in `setup.sh`:

```
# Link individual files
myconfig/settings.toml -> $HOME/.config/myapp/settings.toml

# Link entire directories (trailing /)
myconfig/ -> $HOME/.config/myapp/

# Set directory permissions
@chmod 700 $HOME/.config/myapp
```

The bundle will automatically appear in the selection menu.

## Requirements

- macOS 26+ (Tahoe)
- Internet connection (for Homebrew)

