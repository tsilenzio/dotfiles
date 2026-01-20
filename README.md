# Dotfiles

Personal dotfiles for macOS with multi-bundle support.

## Quick Start

```bash
# Fresh install (interactive bundle selection)
curl -fsSL https://raw.githubusercontent.com/tsilenzio/dotfiles/main/bootstrap.sh | bash

# Non-interactive with specific bundles
curl -fsSL https://... | bash -s -- --bundle core --bundle personal
```

Or manually:

```bash
git clone https://github.com/tsilenzio/dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

## What's Included

- **Zsh** configuration with Starship prompt
- **Git** config with delta diffs and GPG signing
- **Homebrew** packages organized by bundle
- **macOS** preferences automation
- **Dock** customization
- **Secrets** management with age encryption

## Bundles

Bundles are modular configurations with automatic dependency resolution:

| Bundle | Description | Requires |
|--------|-------------|----------|
| `core` | Essential tools (zsh, git, CLI utilities) | - |
| `develop` | Development tools, IDEs, containers | core |
| `personal` | Gaming, entertainment, MS Office | core |
| `work` | Office communication (Outlook, Slack, Zoom) | core |
| `test` | Minimal packages for VM testing (hidden) | - |

**Example combinations:**
- Personal machine: `--bundle personal` (auto-includes core)
- Work machine: `--bundle work --bundle develop` (auto-includes core)
- Full setup: `--bundle personal --bundle work --bundle develop`

## Commands

This repo uses [just](https://github.com/casey/just) for common tasks:

```bash
just                  # Show available commands
just install          # Run full installation
just upgrade          # Re-apply bundles (packages + symlinks)
just update           # Pull latest changes (creates rollback point)
just history          # Show available rollback points
just rollback [id]    # Rollback to previous state
just secrets ...      # Secrets management (init, encrypt, decrypt)
```

## Structure

```
~/.dotfiles/
├── config/                    # Base configurations
│   ├── git/
│   ├── starship/
│   ├── wezterm/
│   └── zsh/
├── platforms/
│   └── macos/
│       ├── bundles/           # Bundle-specific setup
│       │   ├── core/
│       │   │   ├── Brewfile
│       │   │   ├── bundle.conf
│       │   │   └── setup.sh
│       │   ├── develop/
│       │   ├── personal/
│       │   ├── work/
│       │   └── test/
│       ├── install.sh
│       ├── preferences.sh
│       └── dock.sh
├── scripts/
│   ├── upgrade.sh
│   ├── update.sh
│   ├── rollback.sh
│   └── secrets.sh
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

The bundle will automatically appear in the selection menu.

## Requirements

- macOS 15+ (Sequoia)
- Internet connection (for Homebrew)

## Documentation

- [Secrets Management](docs/secrets-management.md) - SSH/GPG key encryption
- [Custom App Icons](docs/custom-app-icons.md) - Replace app icons
- [GPG Extended Cache](docs/gpg-extended-cache.md) - Workaround for pinentry-touchid
